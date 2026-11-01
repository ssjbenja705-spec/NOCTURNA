local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local store = DataStoreService:GetDataStore("NocturnaPlayerData_v1")
local loaded = {}
local saving = {}

local function playerKey(player)
    return "Player_" .. player.UserId
end

local function loadPlayer(player)
    local success, data = pcall(function()
        return store:GetAsync(playerKey(player))
    end)

    if not player.Parent then return end
    if not success then
        warn("[NOCTURNA] Error cargando datos:", data)
        return
    end

    if type(data) == "table" then
        player:SetAttribute("LastChapter", math.max(1, tonumber(data.LastChapter) or 1))
        player:SetAttribute("PlayTime", math.max(0, tonumber(data.PlayTime) or 0))
    else
        player:SetAttribute("LastChapter", 1)
        player:SetAttribute("PlayTime", 0)
    end
    loaded[player] = true
end

local function savePlayer(player)
    if not loaded[player] or saving[player] then return false end
    saving[player] = true

    local data = {
        Version = 1,
        LastChapter = player:GetAttribute("LastChapter") or 1,
        PlayTime = player:GetAttribute("PlayTime") or 0,
    }
    local success, err = pcall(function()
        store:UpdateAsync(playerKey(player), function()
            return data
        end)
    end)

    saving[player] = nil
    if not success then
        warn("[NOCTURNA] Error guardando datos:", err)
    end
    return success
end

Players.PlayerAdded:Connect(loadPlayer)
Players.PlayerRemoving:Connect(function(player)
    savePlayer(player)
    loaded[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(loadPlayer, player)
end

game:BindToClose(function()
    local pending = 0
    for _, player in ipairs(Players:GetPlayers()) do
        pending += 1
        task.spawn(function()
            savePlayer(player)
            pending -= 1
        end)
    end
    while pending > 0 do
        task.wait()
    end
end)

print("[NOCTURNA] Guardado de progreso preparado.")