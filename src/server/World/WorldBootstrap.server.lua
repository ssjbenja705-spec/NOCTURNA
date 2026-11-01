local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local shared = ReplicatedStorage:WaitForChild("Shared")
local remoteFolder = ReplicatedStorage:FindFirstChild("NocturnaRemotes")

if not remoteFolder then
    remoteFolder = Instance.new("Folder")
    remoteFolder.Name = "NocturnaRemotes"
    remoteFolder.Parent = ReplicatedStorage
end

for _, name in ipairs({"SprintEvent", "FlashlightEvent", "PlayerStateEvent", "ObjectiveEvent", "AdminEvent"}) do
    if not remoteFolder:FindFirstChild(name) then
        local event = Instance.new("RemoteEvent")
        event.Name = name
        event.Parent = remoteFolder
    end
end

Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(18, 22, 28)
Lighting.OutdoorAmbient = Color3.fromRGB(8, 10, 15)
Lighting.FogColor = Color3.fromRGB(12, 16, 20)
Lighting.FogStart = 8
Lighting.FogEnd = 100

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
atmosphere.Density = 0.38
atmosphere.Offset = 0.1
atmosphere.Color = Color3.fromRGB(125, 140, 150)
atmosphere.Decay = Color3.fromRGB(35, 42, 50)
atmosphere.Parent = Lighting

print("[NOCTURNA] Mundo y eventos inicializados.")
