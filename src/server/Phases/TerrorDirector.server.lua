local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local event = remotes:FindFirstChild("HorrorEvent")

if not event then
    event = Instance.new("RemoteEvent")
    event.Name = "HorrorEvent"
    event.Parent = remotes
end

local events = {
    "LIGHTS_FLICKER",
    "DISTANT_SOUND",
    "FALSE_ALARM",
    "ENVIRONMENT_WARNING"
}

while true do
    task.wait(math.random(45, 90))

    local selected = events[math.random(1, #events)]

    for _, player in ipairs(Players:GetPlayers()) do
        event:FireClient(player, selected)
    end
end
