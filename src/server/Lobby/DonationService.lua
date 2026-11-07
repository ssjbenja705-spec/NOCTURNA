-- Donaciones con productos de desarrollador. Cada compra se acredita una sola vez:
-- el total de cada donante y las compras ya procesadas se guardan juntos, en una
-- sola escritura atómica. Un OrderedDataStore copia los totales para armar el podio
-- de los tres mayores donantes, con su avatar como estatua.
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local DonationConfig = require(Shared.Config.DonationConfig)
local LobbyConfig = require(Shared.Config.LobbyConfig)
local RateLimiter = require(Shared.Logic.RateLimiter)
local Remotes = require(Shared.Modules.RemoteHelper)

local GameState = require(script.Parent.Parent.Core.GameState)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)
local ServerMode = require(script.Parent.ServerMode)

local DONORS_STORE = "NOCTURNA_DONATIONS_V1"
local RANKING_STORE = "NOCTURNA_DONATION_RANKING_V1"
-- Compras recordadas por donante: Roblox reintenta un recibo por pocos días.
local MAX_RECEIPTS = 200
local TOP_SIZE = 3
local REFRESH_DELAY = 3

local Decision = Enum.ProductPurchaseDecision

local DonationService = {}
local donorsStore = nil
local rankingStore = nil
local top = {}
local names = {}
local refreshing = false
local refreshQueued = false
local limiter = RateLimiter.new(1, 2)

local function getStores()
    if donorsStore and rankingStore then
        return donorsStore, rankingStore
    end
    local success, err = pcall(function()
        donorsStore = DataStoreService:GetDataStore(DONORS_STORE)
        rankingStore = DataStoreService:GetOrderedDataStore(RANKING_STORE)
    end)
    if not success then
        donorsStore, rankingStore = nil, nil
        warn("[NOCTURNA] Donaciones sin DataStore:", err)
    end
    return donorsStore, rankingStore
end

local function donorKey(userId)
    return "DONOR_" .. tostring(userId)
end

local function normalize(record)
    local result = {Total = 0, Receipts = {}}
    if type(record) == "table" then
        if type(record.Total) == "number" and record.Total >= 0 then
            result.Total = math.floor(record.Total)
        end
        if type(record.Receipts) == "table" then
            for _, purchaseId in ipairs(record.Receipts) do
                if type(purchaseId) == "string" then
                    table.insert(result.Receipts, purchaseId)
                end
            end
        end
    end
    return result
end

local function nameOf(userId)
    local player = Players:GetPlayerByUserId(userId)
    if player then
        names[userId] = player.Name
        return player.Name
    end
    if names[userId] then
        return names[userId]
    end
    local success, name = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    if success and type(name) == "string" then
        names[userId] = name
        return name
    end
    return nil
end

-- Silueta oscura para un puesto vacío o si el avatar no se puede cargar.
local function silhouette()
    local model = Instance.new("Model")
    model.Name = "Silhouette"
    local color = Color3.fromRGB(16, 16, 18)
    local function piece(name, size, offset, shape)
        local part = Instance.new("Part")
        part.Name = name
        part.Size = size
        part.CFrame = CFrame.new(offset)
        part.Anchored = true
        part.CanCollide = false
        part.CanTouch = false
        part.CastShadow = false
        part.Color = color
        part.Material = Enum.Material.Slate
        if shape then
            part.Shape = shape
        end
        part.Parent = model
        return part
    end
    model.PrimaryPart = piece("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0))
    piece("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.7, 0), Enum.PartType.Ball)
    for _, side in ipairs({-1, 1}) do
        piece("Arm", Vector3.new(1, 2, 1), Vector3.new(side * 1.5, 0, 0))
        piece("Leg", Vector3.new(1, 2, 1), Vector3.new(side * 0.5, -2, 0))
    end
    return model
end

local function avatar(userId)
    local success, model = pcall(function()
        return Players:CreateHumanoidModelFromUserId(userId)
    end)
    if not success or typeof(model) ~= "Instance" or not model:IsA("Model") then
        warn("[NOCTURNA] Sin avatar para el donante", userId, model)
        return silhouette()
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.Anchored = true
            descendant.CanCollide = false
            descendant.CanTouch = false
        elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant:Destroy()
        end
    end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end
    return model
end

local function placeStatue(podium, entry)
    local folder = LobbyBuilder.StatueFolder()
    local userId = entry and entry.UserId or 0
    if podium.UserId == userId then
        return
    end
    podium.UserId = userId

    -- Cargar el avatar tarda: si mientras tanto cambió el podio, esta estatua sobra.
    local statue = entry and avatar(entry.UserId) or silhouette()
    if podium.UserId ~= userId then
        statue:Destroy()
        return
    end
    if podium.Statue then
        podium.Statue:Destroy()
    end
    statue.Name = "Statue" .. podium.Rank
    statue:PivotTo(podium.CFrame)
    statue.Parent = folder
    podium.Statue = statue
end

local function applyTop()
    for rank, podium in ipairs(LobbyBuilder.Podiums()) do
        local entry = top[rank]
        local labels = podium.Labels
        if entry then
            labels.Name.Text = string.format("%d° %s", rank, entry.Name)
            labels.Total.Text = DonationConfig.FormatRobux(entry.Total) .. " R$"
        else
            labels.Name.Text = string.format("%d° Puesto libre", rank)
            labels.Total.Text = "Doná para aparecer acá"
        end
        task.spawn(placeStatue, podium, entry)
    end
end

function DonationService.RefreshTop()
    local _, ranking = getStores()
    if not ranking then
        return top
    end

    local success, page = pcall(function()
        return ranking:GetSortedAsync(false, TOP_SIZE):GetCurrentPage()
    end)
    if not success then
        warn("[NOCTURNA] No se pudo leer el podio de donaciones:", page)
        return top
    end

    local fresh = {}
    for _, item in ipairs(page) do
        local userId = tonumber(item.key)
        local total = item.value
        if userId and type(total) == "number" and total > 0 then
            table.insert(fresh, {
                UserId = userId,
                Total = total,
                Name = nameOf(userId) or ("Donante " .. tostring(#fresh + 1)),
            })
        end
        if #fresh >= TOP_SIZE then
            break
        end
    end
    top = fresh
    applyTop()
    return top
end

-- Varias donaciones seguidas piden una sola lectura del podio.
local function scheduleRefresh()
    if refreshQueued then
        return
    end
    refreshQueued = true
    task.delay(REFRESH_DELAY, function()
        refreshQueued = false
        if not refreshing then
            refreshing = true
            pcall(DonationService.RefreshTop)
            refreshing = false
        end
    end)
end

local function thank(userId, robux)
    local player = Players:GetPlayerByUserId(userId)
    local amount = DonationConfig.FormatRobux(robux)
    if player then
        Remotes.FireClient("DonationUpdate", player, {Thanks = robux})
        Remotes.FireAll("StoryNotice", string.format("%s donó %s R$ a la Fundación. ¡Gracias!", player.DisplayName, amount))
    end
end

-- Roblox llama a esto por cada compra y lo repite hasta recibir PurchaseGranted, por
-- lo que tiene que poder correr dos veces sin acreditar dos veces.
function DonationService.ProcessReceipt(receipt)
    if type(receipt) ~= "table" then
        return Decision.NotProcessedYet
    end
    local userId = receipt.PlayerId
    local purchaseId = receipt.PurchaseId
    local product = DonationConfig.FindByProductId(receipt.ProductId)
    if type(userId) ~= "number" or purchaseId == nil or not product then
        warn("[NOCTURNA] Recibo de un producto desconocido:", receipt.ProductId)
        return Decision.NotProcessedYet
    end
    purchaseId = tostring(purchaseId)

    local donors, ranking = getStores()
    if not donors or not ranking then
        return Decision.NotProcessedYet
    end

    local alreadyCounted = false
    local latest = nil
    local success, err = pcall(function()
        donors:UpdateAsync(donorKey(userId), function(stored)
            local record = normalize(stored)
            latest = record
            if table.find(record.Receipts, purchaseId) then
                alreadyCounted = true
                return nil
            end
            alreadyCounted = false
            record.Total += product.Robux
            table.insert(record.Receipts, purchaseId)
            while #record.Receipts > MAX_RECEIPTS do
                table.remove(record.Receipts, 1)
            end
            return record
        end)
    end)
    if not success or not latest then
        warn("[NOCTURNA] No se pudo acreditar la donación", purchaseId, err)
        return Decision.NotProcessedYet
    end

    -- El ranking es una copia del total: si falla, el reintento la vuelve a escribir
    -- sin sumar de nuevo.
    local mirrored, mirrorError = pcall(function()
        ranking:SetAsync(tostring(userId), latest.Total)
    end)
    if not mirrored then
        warn("[NOCTURNA] No se pudo actualizar el podio de donaciones:", mirrorError)
        return Decision.NotProcessedYet
    end

    if not alreadyCounted then
        thank(userId, product.Robux)
        scheduleRefresh()
    end
    return Decision.PurchaseGranted
end

function DonationService.Top()
    return top
end

local function openPanel(player)
    if GameState.Phase ~= "Lobby" or not limiter:Allow(player, os.clock()) then
        return
    end
    local prompt = LobbyBuilder.DonationPrompt()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local host = prompt and prompt.Parent
    if not root or not host or (host.Position - root.Position).Magnitude > prompt.MaxActivationDistance + 5 then
        return
    end
    Remotes.FireClient("DonationUpdate", player, {Open = true, Top = top})
end

function DonationService.Start()
    -- Sólo puede haber un ProcessReceipt por juego, y tiene que existir en todos los
    -- servidores: un recibo pendiente puede llegar a cualquiera.
    MarketplaceService.ProcessReceipt = DonationService.ProcessReceipt

    Players.PlayerRemoving:Connect(function(player)
        limiter:Forget(player)
    end)

    if ServerMode.IsMatchServer() then
        return
    end

    LobbyBuilder.Build()
    local prompt = LobbyBuilder.DonationPrompt()
    if prompt then
        prompt.Triggered:Connect(openPanel)
    end

    applyTop()
    task.spawn(function()
        while true do
            pcall(DonationService.RefreshTop)
            task.wait(LobbyConfig.Donations.RefreshInterval)
        end
    end)
end

return DonationService
