local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local store = DataStoreService:GetDataStore("NocturnaPlayerData_v1")
local loaded, saving, sessionStarted = {}, {}, {}

local function playerKey(player)
    return "Player_" .. player.UserId
end

local function loadPlayer(player)
    local success, data
    for attempt = 1, 3 do
        success, data = pcall(function() return store:GetAsync(playerKey(player)) end)
        if success then break end
        task.wait(attempt * 1.5)
    end
    if not player.Parent then return end
    if not success then
        warn("[NOCTURNA] Error cargando datos:", data)
        player:SetAttribute("DataLoaded", false)
        return
    end
    if type(data) ~= "table" then data = {} end
    player:SetAttribute("LastChapter", math.clamp(math.floor(tonumber(data.LastChapter) or 1), 1, 5))
    player:SetAttribute("PlayTime", math.max(0, math.floor(tonumber(data.PlayTime) or 0)))
    player:SetAttribute("DataLoaded", true)
    loaded[player] = true
    sessionStarted[player] = os.time()
end

local function savePlayer(player)
    if not loaded[player] or saving[player] then return false end
    saving[player] = true
    local elapsed = math.max(0, os.time() - (sessionStarted[player] or os.time()))
    local data = {
        Version = 1,
        LastChapter = math.clamp(math.floor(tonumber(player:GetAttribute("LastChapter")) or 1), 1, 5),
        PlayTime = math.max(0, math.floor(tonumber(player:GetAttribute("PlayTime")) or 0)) + elapsed,
    }
    local success, err
    for attempt = 1, 3 do
        success, err = pcall(function()
            store:UpdateAsync(playerKey(player), function(old)
                old = type(old) == "table" and old or {}
                old.Version, old.LastChapter, old.PlayTime = data.Version, data.LastChapter, data.PlayTime
                return old
            end)
        end)
        if success then break end
        task.wait(attempt * 1.5)
    end
    saving[player] = nil
    if success then
        player:SetAttribute("PlayTime", data.PlayTime)
        sessionStarted[player] = os.time()
    else
        warn("[NOCTURNA] Error guardando datos:", err)
    end
    return success
end

Players.PlayerAdded:Connect(loadPlayer)
Players.PlayerRemoving:Connect(function(player)
    savePlayer(player)
    loaded[player], sessionStarted[player], saving[player] = nil, nil, nil
end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(loadPlayer, player) end

game:BindToClose(function()
    local pending = 0
    for _, player in ipairs(Players:GetPlayers()) do
        pending += 1
        task.spawn(function()
            savePlayer(player)
            pending -= 1
        end)
    end
    local deadline = os.clock() + 25
    while pending > 0 and os.clock() < deadline do task.wait(0.1) end
end)

print("[NOCTURNA] Guardado de progreso preparado.")
