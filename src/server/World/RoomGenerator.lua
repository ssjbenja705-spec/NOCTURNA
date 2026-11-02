local RoomGenerator = {}

local function createPart(parent, name, size, position, color)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.Position = position
    part.Anchored = true
    part.Material = Enum.Material.Concrete
    part.Color = color or Color3.fromRGB(45, 48, 52)
    part.Parent = parent
    return part
end

function RoomGenerator.CreateRoom(origin, width, depth, height, name)
    local folder = Instance.new("Model")
    folder.Name = name or "NocturnaRoom"

    local wall = 2
    local color = Color3.fromRGB(42, 46, 50)

    createPart(folder, "Floor",
        Vector3.new(width, wall, depth),
        origin,
        Color3.fromRGB(25, 28, 30))

    createPart(folder, "Ceiling",
        Vector3.new(width, wall, depth),
        origin + Vector3.new(0, height, 0),
        color)

    createPart(folder, "NorthWall",
        Vector3.new(width, height, wall),
        origin + Vector3.new(0, height / 2, -depth / 2),
        color)

    createPart(folder, "SouthWall",
        Vector3.new(width, height, wall),
        origin + Vector3.new(0, height / 2, depth / 2),
        color)

    createPart(folder, "EastWall",
        Vector3.new(wall, height, depth),
        origin + Vector3.new(width / 2, height / 2, 0),
        color)

    createPart(folder, "WestWall",
        Vector3.new(wall, height, depth),
        origin + Vector3.new(-width / 2, height / 2, 0),
        color)

    folder.Parent = workspace
    return folder
end

return RoomGenerator
