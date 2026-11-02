-- NOCTURNA: Dynamic Horror Intensity

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local horrorEvent = remotes:FindFirstChild("HorrorIntensity")

if not horrorEvent then
    horrorEvent = Instance.new("RemoteEvent")
    horrorEvent.Name = "HorrorIntensity"
    horrorEvent.Parent = remotes
end

local playerData = {}

local function setupPlayer(player)
    playerData[player] = {
        StartedAt = os.clock(),
        Intensity = 0,
        LastEvent = 0,
    }
end

local function updatePlayer(player)
    local data = playerData[player]
    if not data then return end

    local elapsed = os.clock() - data.StartedAt
    local intensity = math.clamp(elapsed / 900, 0, 1)
    data.Intensity = intensity
    player:SetAttribute("HorrorIntensity", math.floor(intensity * 100))

    if os.clock() - data.LastEvent >= 30 then
        data.LastEvent = os.clock()
        horrorEvent:FireClient(player, {
            intensity = intensity,
            elapsed = elapsed,
        })
    end
end

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
    playerData[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
    setupPlayer(player)
end

while true do
    task.wait(5)
    for player in pairs(playerData) do
        if player.Parent == Players then
            updatePlayer(player)
        end
    end
end