-- Escondites: casilleros, roperos, debajo de escritorios y camas, y conductos de
-- ventilación. Mientras dure, el personaje queda fijo adentro y los monstruos no lo
-- perciben, salvo que lo hayan visto entrar.
--
-- Salir siempre funciona: con E o el botón SALIR del celular (remoto ExitHiding), y
-- además el servidor suelta solo al que muere, reaparece, se va, o cuyo escondite
-- desapareció. Nadie puede quedar anclado adentro.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Rng = require(Shared.Logic.Rng)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local FlashlightService = require(script.Parent.Parent.Data.FlashlightService)
local FeatureBuilder = require(script.Parent.FeatureBuilder)
local HideModels = require(script.Parent.HideModels)
local InteractionService = require(script.Parent.InteractionService)
local RoomGenerator = require(script.Parent.RoomGenerator)

local WATCHDOG_INTERVAL = 0.5

local HidingService = {}
local spots = {}
local hiddenPlayers = {}

local KNOWN_KINDS = {}
for _, kind in ipairs(HideModels.Kinds) do
    KNOWN_KINDS[kind] = true
end

local function release(player, ejected)
    local state = hiddenPlayers[player]
    if not state then
        return
    end

    hiddenPlayers[player] = nil
    local spot = state.Spot
    spot.Occupant = nil
    if spot.Prompt.Parent then
        spot.Prompt.Enabled = true
    end
    player:SetAttribute("Hidden", false)

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root and root == state.Root then
        -- Primero se ubica afuera (todavía anclado) y recién después se suelta: así
        -- el cliente, dueño de la física, no pisa la posición con la de adentro.
        if spot.Model:IsDescendantOf(workspace) then
            root.CFrame = spot.ExitCFrame
        end
        root.Anchored = false
    elseif state.Root and state.Root.Parent then
        state.Root.Anchored = false
    end

    Remotes.FireClient("HideState", player, false, nil, ejected == true)
end

local function enter(spot, player)
    if spot.Occupant or hiddenPlayers[player] then
        return
    end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then
        return
    end

    spot.Occupant = player
    spot.Prompt.Enabled = false
    hiddenPlayers[player] = {Spot = spot, Since = os.clock(), Root = root}

    FlashlightService.SetEnabled(player, false)
    player:SetAttribute("Hidden", true)
    root.Anchored = true
    root.CFrame = spot.InsideCFrame

    Remotes.FireClient("HideState", player, true, spot.CameraCFrame, false, spot.Kind)
end

-- Reparte los tipos de escondite del tema, mezclados pero siempre iguales para la
-- misma semilla. Un tipo puesto a propósito en el plan se respeta.
local function assignKinds(plan, theme)
    local kinds = theme and theme.HideKinds or {"Locker"}
    if #kinds == 0 then
        kinds = {"Locker"}
    end

    local queue = {}
    for index = 1, #plan.Hides do
        queue[index] = kinds[(index - 1) % #kinds + 1]
    end
    Rng.new((plan.Layout.Seed or 0) + 4099):Shuffle(queue)

    for index, hide in ipairs(plan.Hides) do
        if not (hide.Kind and hide.Kind ~= "Locker" and KNOWN_KINDS[hide.Kind]) then
            hide.Kind = queue[index]
        end
    end
end

function HidingService.Populate(plan, map, theme)
    HidingService.Clear()

    local folder = Instance.new("Folder")
    folder.Name = "Hides"
    folder.Parent = map

    assignKinds(plan, theme)
    local style = theme and theme.HideStyle

    for _, hide in ipairs(plan.Hides) do
        local cframe = RoomGenerator.SlotCFrame(plan.Layout, hide.Cell, hide.Slot)
        local holder, prompt, spec = FeatureBuilder.Hide(folder, hide.Kind, cframe, style)
        local spot = {
            Kind = spec.Kind,
            Model = holder,
            Prompt = prompt,
            InsideCFrame = cframe * spec.Inside,
            -- La cámara queda adentro, detrás de las rendijas, mirando hacia la sala.
            CameraCFrame = cframe * spec.Camera,
            ExitCFrame = cframe * spec.Exit,
            Occupant = nil,
        }
        table.insert(spots, spot)

        InteractionService.Bind(prompt, function(player)
            enter(spot, player)
        end)
    end
end

function HidingService.Clear()
    for player in pairs(hiddenPlayers) do
        release(player, false)
    end
    table.clear(spots)
end

function HidingService.IsHidden(player)
    return hiddenPlayers[player] ~= nil
end

function HidingService.HiddenFor(player)
    local state = hiddenPlayers[player]
    return state and os.clock() - state.Since or 0
end

function HidingService.KindOf(player)
    local state = hiddenPlayers[player]
    return state and state.Spot.Kind or nil
end

function HidingService.ForceOut(player)
    release(player, true)
end

function HidingService.Exit(player)
    release(player, false)
end

-- Red de seguridad: suelta a quien ya no puede seguir escondido.
local function watchdog()
    for player, state in pairs(hiddenPlayers) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local valid = player.Parent == Players
            and root ~= nil
            and root == state.Root
            and root.Anchored
            and humanoid ~= nil
            and humanoid.Health > 0
            and state.Spot.Model:IsDescendantOf(workspace)
        if not valid then
            release(player, false)
        end
    end
end

function HidingService.Start()
    Remotes.OnServer("ExitHiding", 4, function(player)
        release(player, false)
    end)

    EventBus.On("PlayerDied", function(player)
        release(player, false)
    end)

    local function watchCharacter(player)
        player.CharacterRemoving:Connect(function()
            release(player, false)
        end)
    end
    Players.PlayerAdded:Connect(watchCharacter)
    for _, player in ipairs(Players:GetPlayers()) do
        watchCharacter(player)
    end

    Players.PlayerRemoving:Connect(function(player)
        local state = hiddenPlayers[player]
        if state then
            state.Spot.Occupant = nil
            if state.Spot.Prompt.Parent then
                state.Spot.Prompt.Enabled = true
            end
            hiddenPlayers[player] = nil
        end
    end)

    local elapsed = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed >= WATCHDOG_INTERVAL then
            elapsed = 0
            watchdog()
        end
    end)
end

return HidingService
