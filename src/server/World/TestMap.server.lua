local RoomGenerator = require(script.Parent.RoomGenerator)

if workspace:FindFirstChild("NocturnaTestMap") then
    workspace.NocturnaTestMap:Destroy()
end

local map = Instance.new("Folder")
map.Name = "NocturnaTestMap"
map.Parent = workspace

local room = RoomGenerator.CreateRoom(
    Vector3.new(0, 0, 0),
    60,
    60,
    24,
    "FirstUndergroundRoom"
)

room.Parent = map

local spawn = Instance.new("SpawnLocation")
spawn.Name = "NocturnaSpawn"
spawn.Size = Vector3.new(6, 1, 6)
spawn.Position = Vector3.new(0, 1, 0)
spawn.Anchored = true
spawn.Neutral = true
spawn.Parent = map

print("[NOCTURNA] Mapa de prueba creado.")
