local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("NocturnaRemotes")
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "NocturnaRemotes"
    folder.Parent = ReplicatedStorage
end

local function getRemote(name)
    local remote = folder:FindFirstChild(name)
    if not remote then
        remote = Instance.new("RemoteEvent")
        remote.Name = name
        remote.Parent = folder
    end
    return remote
end

local noiseRemote = getRemote("PlayerNoise")
local lookRemote = getRemote("PlayerLook")
getRemote("MonsterEffect")

local lastNoise = {}
local lastLook = {}
_G.NocturnaRecentNoise = {}

local function pruneNoises(now)
    for index = #_G.NocturnaRecentNoise, 1, -1 do
        if now - _G.NocturnaRecentNoise[index].Time > 5 then
            table.remove(_G.NocturnaRecentNoise, index)
        end
    end
end

noiseRemote.OnServerEvent:Connect(function(player, position, intensity)
    if typeof(position) ~= "Vector3" or typeof(intensity) ~= "number" then return end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return end
    if (root.Position - position).Magnitude > 15 then return end

    local now = os.clock()
    if now - (lastNoise[player] or 0) < 0.35 then return end
    lastNoise[player] = now

    pruneNoises(now)
    table.insert(_G.NocturnaRecentNoise, {
        Position = root.Position,
        Intensity = math.clamp(intensity, 1, 100),
        Time = now,
        Player = player,
    })
end)

lookRemote.OnServerEvent:Connect(function(player, direction)
    if typeof(direction) ~= "Vector3" then return end
    if direction.Magnitude < 0.5 or direction.Magnitude > 1.5 then return end

    local now = os.clock()
    if now - (lastLook[player] or 0) < 0.12 then return end
    lastLook[player] = now
    player:SetAttribute("CameraLookDirection", direction.Unit)
end)

Players.PlayerRemoving:Connect(function(player)
    lastNoise[player] = nil
    lastLook[player] = nil
    for index = #_G.NocturnaRecentNoise, 1, -1 do
        if _G.NocturnaRecentNoise[index].Player == player then
            table.remove(_G.NocturnaRecentNoise, index)
        end
    end
end)

print("[NOCTURNA] Señales de monstruos preparadas.")
