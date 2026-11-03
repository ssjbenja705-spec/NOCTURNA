-- Sala de preparación: el estacionamiento abandonado sobre la vieja sede de Leteo.
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local ThemeConfig = require(Shared.Config.ThemeConfig)
local RoomGenerator = require(script.Parent.RoomGenerator)

local ORIGIN = GameConfig.Map.LobbyOrigin
local SIZE = 70
local HEIGHT = 18

local LobbyBuilder = {}

local function origin()
    return Vector3.new(ORIGIN.X, ORIGIN.Y, ORIGIN.Z)
end

local function buildVan(parent, base)
    local create = RoomGenerator.CreatePart
    local body = Color3.fromRGB(150, 150, 142)
    create(parent, "VanBody", Vector3.new(7, 6, 16), base + Vector3.new(0, 3.8, 0), body, Enum.Material.Metal)
    create(parent, "VanHood", Vector3.new(7, 3.4, 4), base + Vector3.new(0, 2.5, 10), body, Enum.Material.Metal)
    create(parent, "VanGlass", Vector3.new(6.6, 2, 0.4), base + Vector3.new(0, 5, 8.1), Color3.fromRGB(30, 40, 50), Enum.Material.Glass)

    for _, side in ipairs({-1, 1}) do
        for _, front in ipairs({-6, 9}) do
            create(parent, "Wheel", Vector3.new(1.2, 2.4, 2.4), base + Vector3.new(side * 3.4, 1.2, front), Color3.fromRGB(20, 20, 22), Enum.Material.Rubber)
        end
    end

    local beam = Instance.new("SpotLight")
    beam.Face = Enum.NormalId.Front
    beam.Color = Color3.fromRGB(255, 225, 170)
    beam.Brightness = 3
    beam.Range = 34
    beam.Angle = 60
    beam.Shadows = false

    local lamp = create(parent, "Headlight", Vector3.new(1, 0.8, 0.2), base + Vector3.new(0, 3, 12.1), Color3.fromRGB(255, 240, 200), Enum.Material.Neon)
    beam.Parent = lamp
end

function LobbyBuilder.Build()
    local existing = workspace:FindFirstChild("NOCTURNA_LOBBY")
    if existing then
        return existing
    end

    local create = RoomGenerator.CreatePart
    local theme = ThemeConfig.Lobby
    local center = origin()

    local lobby = Instance.new("Model")
    lobby.Name = "NOCTURNA_LOBBY"

    create(lobby, "Floor", Vector3.new(SIZE, 2, SIZE), center + Vector3.new(0, -1, 0), theme.Floor, Enum.Material.Concrete)
    create(lobby, "Ceiling", Vector3.new(SIZE, 2, SIZE), center + Vector3.new(0, HEIGHT + 1, 0), theme.Ceiling, Enum.Material.Concrete)

    for _, side in ipairs({-1, 1}) do
        create(lobby, "Wall", Vector3.new(SIZE, HEIGHT, 2), center + Vector3.new(0, HEIGHT / 2, side * SIZE / 2), theme.Wall, Enum.Material.Brick)
        create(lobby, "Wall", Vector3.new(2, HEIGHT, SIZE), center + Vector3.new(side * SIZE / 2, HEIGHT / 2, 0), theme.Wall, Enum.Material.Brick)
    end

    for _, offset in ipairs({-18, 18}) do
        local fixture = create(lobby, "Lamp", Vector3.new(6, 0.5, 2), center + Vector3.new(offset, HEIGHT - 0.3, 0), Color3.fromRGB(170, 160, 130), Enum.Material.SmoothPlastic)
        fixture.CanCollide = false
        local light = Instance.new("PointLight")
        light.Color = theme.Light
        light.Brightness = 1.1
        light.Range = 40
        light.Shadows = false
        light.Parent = fixture
    end

    buildVan(lobby, center + Vector3.new(-18, 0, -14))

    local gate = create(lobby, "Gate", Vector3.new(20, 12, 1), center + Vector3.new(0, 6, SIZE / 2 - 1.5), Color3.fromRGB(80, 60, 44), Enum.Material.CorrodedMetal)
    gate.CanCollide = true

    local spawn = Instance.new("SpawnLocation")
    spawn.Name = "PlayerSpawn"
    spawn.Size = Vector3.new(14, 1, 14)
    spawn.Position = center + Vector3.new(6, 0.5, 0)
    spawn.Anchored = true
    spawn.Neutral = true
    spawn.Transparency = 1
    spawn.CanCollide = false
    spawn.Duration = 0
    spawn.Parent = lobby

    lobby.Parent = workspace
    CollectionService:AddTag(lobby, "NocturnaLobby")
    return lobby
end

function LobbyBuilder.SpawnCFrame(index)
    local center = origin()
    local spread = ((index or 1) - 2.5) * 4
    return CFrame.lookAt(center + Vector3.new(6 + spread, 3.5, 4), center + Vector3.new(6 + spread, 3.5, 30))
end

return LobbyBuilder
