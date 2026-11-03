-- Modelos procedurales de objetos, máquinas, escondites y utilería.
local Shared = game:GetService("ReplicatedStorage").Shared
local ItemConfig = require(Shared.Config.ItemConfig)

local FeatureBuilder = {}

local function part(parent, name, size, offset, color, material, shape)
    local item = Instance.new("Part")
    item.Name = name
    item.Size = size
    item.CFrame = offset
    item.Anchored = true
    item.Color = color
    item.Material = material or Enum.Material.Metal
    item.TopSurface = Enum.SurfaceType.Smooth
    item.BottomSurface = Enum.SurfaceType.Smooth
    item.CanTouch = false
    item.CastShadow = false
    if shape then
        item.Shape = shape
    end
    item.Parent = parent
    return item
end

local function model(parent, name)
    local item = Instance.new("Model")
    item.Name = name
    item.Parent = parent
    return item
end

function FeatureBuilder.AddPrompt(host, actionText, objectText, holdDuration)
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "NocturnaPrompt"
    prompt.ActionText = actionText
    prompt.ObjectText = objectText or ""
    prompt.HoldDuration = holdDuration or 0
    prompt.MaxActivationDistance = 9
    prompt.RequiresLineOfSight = false
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.Parent = host
    return prompt
end

function FeatureBuilder.Pickup(parent, itemId, cframe)
    local definition = ItemConfig[itemId]
    local holder = part(
        parent,
        "Pickup_" .. itemId,
        Vector3.new(1.2, 1.2, 1.2),
        cframe * CFrame.new(0, 1.2, 0),
        definition.Color,
        Enum.Material.Neon
    )
    holder.CanCollide = false

    local stand = part(
        holder,
        "Stand",
        Vector3.new(2, 0.5, 2),
        cframe * CFrame.new(0, 0.25, 0),
        Color3.fromRGB(45, 46, 50),
        Enum.Material.Metal
    )
    stand.CanCollide = false

    local glow = Instance.new("PointLight")
    glow.Color = definition.Color
    glow.Brightness = 0.6
    glow.Range = 7
    glow.Shadows = false
    glow.Parent = holder

    return holder, FeatureBuilder.AddPrompt(holder, "Recoger", definition.DisplayName, 0.3)
end

function FeatureBuilder.Document(parent, title, cframe)
    local holder = model(parent, "Document")
    part(
        holder,
        "Table",
        Vector3.new(3, 2.4, 2),
        cframe * CFrame.new(0, 1.2, 0),
        Color3.fromRGB(58, 50, 42),
        Enum.Material.Wood
    )
    local sheet = part(
        holder,
        "Sheet",
        Vector3.new(1.3, 0.1, 1.7),
        cframe * CFrame.new(0, 2.5, 0) * CFrame.Angles(0, 0.3, 0),
        Color3.fromRGB(225, 218, 190),
        Enum.Material.SmoothPlastic
    )
    sheet.CanCollide = false
    holder.PrimaryPart = sheet

    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(240, 225, 180)
    glow.Brightness = 0.4
    glow.Range = 6
    glow.Shadows = false
    glow.Parent = sheet

    return holder, FeatureBuilder.AddPrompt(sheet, "Leer", title, 0.2)
end

function FeatureBuilder.Generator(parent, feature, cframe)
    local holder = model(parent, feature.Id)
    local body = part(
        holder,
        "Body",
        Vector3.new(6, 5, 4),
        cframe * CFrame.new(0, 2.5, 0),
        Color3.fromRGB(62, 66, 58),
        Enum.Material.DiamondPlate
    )
    holder.PrimaryPart = body
    part(
        holder,
        "Exhaust",
        Vector3.new(1.2, 3, 1.2),
        cframe * CFrame.new(-2, 6, 1),
        Color3.fromRGB(40, 40, 42),
        Enum.Material.Metal,
        Enum.PartType.Cylinder
    )
    local indicator = part(
        holder,
        "Indicator",
        Vector3.new(1, 1, 0.3),
        cframe * CFrame.new(0, 3.6, -2.1),
        Color3.fromRGB(190, 40, 35),
        Enum.Material.Neon
    )
    indicator.CanCollide = false

    return holder, FeatureBuilder.AddPrompt(body, "Insertar fusible", feature.Label, 1), indicator
end

function FeatureBuilder.Terminal(parent, feature, cframe)
    local holder = model(parent, feature.Id)
    local desk = part(
        holder,
        "Desk",
        Vector3.new(5, 2.6, 2.5),
        cframe * CFrame.new(0, 1.3, 0),
        Color3.fromRGB(52, 54, 60),
        Enum.Material.Metal
    )
    holder.PrimaryPart = desk
    local screen = part(
        holder,
        "Screen",
        Vector3.new(3, 2, 0.3),
        cframe * CFrame.new(0, 3.8, 0.4),
        Color3.fromRGB(70, 170, 130),
        Enum.Material.Neon
    )
    screen.CanCollide = false

    return holder, FeatureBuilder.AddPrompt(desk, feature.Prompt or "Usar", feature.Label, feature.Hold), screen
end

function FeatureBuilder.Valve(parent, feature, cframe)
    local holder = model(parent, feature.Id)
    local pipe = part(
        holder,
        "Pipe",
        Vector3.new(1.4, 6, 1.4),
        cframe * CFrame.new(0, 3, 0),
        Color3.fromRGB(80, 62, 58),
        Enum.Material.Metal
    )
    holder.PrimaryPart = pipe
    local wheel = part(
        holder,
        "Wheel",
        Vector3.new(0.5, 3, 3),
        cframe * CFrame.new(0, 3.6, -1) * CFrame.Angles(0, math.rad(90), 0),
        Color3.fromRGB(170, 50, 45),
        Enum.Material.Metal,
        Enum.PartType.Cylinder
    )
    wheel.CanCollide = false

    return holder, FeatureBuilder.AddPrompt(pipe, feature.Prompt or "Cerrar", "Válvula de contención", feature.Hold), wheel
end

function FeatureBuilder.Core(parent, feature, cframe)
    local holder = model(parent, feature.Id)
    local base = part(
        holder,
        "Base",
        Vector3.new(7, 1.5, 7),
        cframe * CFrame.new(0, 0.75, 0),
        Color3.fromRGB(44, 46, 56),
        Enum.Material.DiamondPlate
    )
    holder.PrimaryPart = base
    local column = part(
        holder,
        "Column",
        Vector3.new(3, 9, 3),
        cframe * CFrame.new(0, 6, 0),
        Color3.fromRGB(120, 60, 170),
        Enum.Material.Neon
    )
    column.CanCollide = false

    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(150, 90, 230)
    glow.Brightness = 1.2
    glow.Range = 22
    glow.Shadows = false
    glow.Parent = column

    return holder, FeatureBuilder.AddPrompt(base, feature.Prompt, feature.Label, feature.Hold), column
end

function FeatureBuilder.Exit(parent, feature, cframe)
    local holder = model(parent, feature.Id)
    local frame = part(
        holder,
        "Frame",
        Vector3.new(7, 8, 1.5),
        cframe * CFrame.new(0, 4, 0),
        Color3.fromRGB(70, 72, 78),
        Enum.Material.Metal
    )
    holder.PrimaryPart = frame
    local panel = part(
        holder,
        "Panel",
        Vector3.new(0.8, 1.2, 0.3),
        cframe * CFrame.new(2.6, 3.8, -0.9),
        Color3.fromRGB(200, 170, 60),
        Enum.Material.Neon
    )
    panel.CanCollide = false

    return holder, FeatureBuilder.AddPrompt(frame, feature.Prompt, feature.Id == "ELEVATOR" and "Ascensor de servicio" or "Salida", feature.Hold), panel
end

function FeatureBuilder.Sister(parent, feature, cframe)
    local holder = model(parent, feature.Id)
    local skin = Color3.fromRGB(216, 190, 165)
    local hospital = Color3.fromRGB(200, 205, 205)

    local chair = part(
        holder,
        "Chair",
        Vector3.new(4, 2, 4),
        cframe * CFrame.new(0, 1, 0),
        Color3.fromRGB(70, 56, 48),
        Enum.Material.WoodPlanks
    )
    holder.PrimaryPart = chair
    part(holder, "Torso", Vector3.new(2, 2.4, 1), cframe * CFrame.new(0, 3.2, 0.4), hospital, Enum.Material.Fabric)
    part(holder, "Head", Vector3.new(1.3, 1.3, 1.3), cframe * CFrame.new(0, 5.1, 0.4), skin, Enum.Material.SmoothPlastic)
    part(holder, "Hair", Vector3.new(1.5, 1.5, 0.8), cframe * CFrame.new(0, 5.2, 0.8), Color3.fromRGB(50, 34, 26), Enum.Material.Fabric)
    part(holder, "ArmLeft", Vector3.new(0.7, 2.2, 0.7), cframe * CFrame.new(-1.4, 3.2, 0.2), hospital, Enum.Material.Fabric)
    part(holder, "ArmRight", Vector3.new(0.7, 2.2, 0.7), cframe * CFrame.new(1.4, 3.2, 0.2), hospital, Enum.Material.Fabric)
    part(holder, "Legs", Vector3.new(2, 1, 2.4), cframe * CFrame.new(0, 2.4, -0.8), hospital, Enum.Material.Fabric)

    for index = 1, 3 do
        local cable = part(
            holder,
            "Cable",
            Vector3.new(0.25, 7, 0.25),
            cframe * CFrame.new((index - 2) * 0.7, 9, 1) * CFrame.Angles(0.15, 0, 0),
            Color3.fromRGB(90, 30, 45),
            Enum.Material.SmoothPlastic
        )
        cable.CanCollide = false
    end

    local glow = Instance.new("PointLight")
    glow.Color = Color3.fromRGB(255, 220, 180)
    glow.Brightness = 1
    glow.Range = 16
    glow.Shadows = false
    glow.Parent = chair

    return holder, FeatureBuilder.AddPrompt(chair, feature.Prompt, "Alma", feature.Hold), chair
end

function FeatureBuilder.Locker(parent, cframe)
    local holder = model(parent, "Locker")
    local shell = Color3.fromRGB(70, 78, 80)
    local back = part(holder, "Back", Vector3.new(4, 7.5, 0.4), cframe * CFrame.new(0, 3.75, 1.6), shell)
    holder.PrimaryPart = back
    part(holder, "Left", Vector3.new(0.4, 7.5, 3.4), cframe * CFrame.new(-1.8, 3.75, 0), shell)
    part(holder, "Right", Vector3.new(0.4, 7.5, 3.4), cframe * CFrame.new(1.8, 3.75, 0), shell)
    part(holder, "Top", Vector3.new(4, 0.4, 3.6), cframe * CFrame.new(0, 7.7, 0), shell)
    local door = part(holder, "Door", Vector3.new(3.2, 7.5, 0.25), cframe * CFrame.new(0, 3.75, -1.7), Color3.fromRGB(58, 66, 68))
    door.CanCollide = false

    for index = 1, 3 do
        local slit = part(
            holder,
            "Slit",
            Vector3.new(2.2, 0.12, 0.05),
            cframe * CFrame.new(0, 5.4 + index * 0.3, -1.85),
            Color3.fromRGB(8, 8, 9),
            Enum.Material.SmoothPlastic
        )
        slit.CanCollide = false
    end

    return holder, FeatureBuilder.AddPrompt(door, "Esconderse", "Casillero", 0.25)
end

local PROPS = {}

function PROPS.Crate(parent, cframe)
    part(parent, "Crate", Vector3.new(4, 3, 4), cframe * CFrame.new(0, 1.5, 0), Color3.fromRGB(74, 58, 42), Enum.Material.Wood)
    part(parent, "CrateSmall", Vector3.new(2.5, 2, 2.5), cframe * CFrame.new(0.4, 4, 0.2) * CFrame.Angles(0, 0.5, 0), Color3.fromRGB(64, 50, 38), Enum.Material.Wood)
end

function PROPS.Barrel(parent, cframe)
    part(parent, "Barrel", Vector3.new(4.5, 3, 3), cframe * CFrame.new(0, 2.25, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 50, 42), Enum.Material.Metal, Enum.PartType.Cylinder)
end

function PROPS.Pipe(parent, cframe)
    part(parent, "Pipe", Vector3.new(1.2, 12, 1.2), cframe * CFrame.new(0, 6, 1), Color3.fromRGB(60, 62, 64), Enum.Material.Metal)
    part(parent, "PipeJoint", Vector3.new(2, 0.8, 2), cframe * CFrame.new(0, 4, 1), Color3.fromRGB(80, 60, 45), Enum.Material.Metal)
end

function PROPS.Desk(parent, cframe)
    part(parent, "Desk", Vector3.new(5, 2.5, 2.5), cframe * CFrame.new(0, 1.25, 0), Color3.fromRGB(86, 80, 70), Enum.Material.Wood)
    part(parent, "Chair", Vector3.new(1.6, 2.6, 1.6), cframe * CFrame.new(0.6, 1.3, -2.4) * CFrame.Angles(0, 0.7, 0), Color3.fromRGB(44, 46, 50), Enum.Material.Fabric)
end

function PROPS.Cabinet(parent, cframe)
    part(parent, "Cabinet", Vector3.new(4.5, 7, 2), cframe * CFrame.new(0, 3.5, 0.6), Color3.fromRGB(84, 88, 92), Enum.Material.Metal)
end

function PROPS.Growth(parent, cframe)
    part(parent, "Growth", Vector3.new(5, 4, 5), cframe * CFrame.new(0, 1.2, 0) * CFrame.Angles(0.2, 0.6, 0.1), Color3.fromRGB(120, 40, 55), Enum.Material.Slate, Enum.PartType.Ball)
    part(parent, "Vein", Vector3.new(0.6, 9, 0.6), cframe * CFrame.new(0.8, 5, 0.6) * CFrame.Angles(0.15, 0, 0.2), Color3.fromRGB(160, 50, 70), Enum.Material.Neon)
end

function PROPS.Table(parent, cframe)
    part(parent, "TableTop", Vector3.new(4, 0.4, 3), cframe * CFrame.new(0, 2.6, 0), Color3.fromRGB(98, 72, 48), Enum.Material.Wood)
    part(parent, "TableLeg", Vector3.new(2.6, 2.4, 1.6), cframe * CFrame.new(0, 1.2, 0), Color3.fromRGB(78, 58, 40), Enum.Material.Wood)
end

function PROPS.Chair(parent, cframe)
    part(parent, "Seat", Vector3.new(2, 2, 2), cframe * CFrame.new(0, 1, 0), Color3.fromRGB(90, 70, 52), Enum.Material.Wood)
    part(parent, "Backrest", Vector3.new(2, 2.4, 0.4), cframe * CFrame.new(0, 3.2, 0.8), Color3.fromRGB(90, 70, 52), Enum.Material.Wood)
end

function FeatureBuilder.Prop(parent, kind, cframe)
    local builder = PROPS[kind]
    if not builder then
        return nil
    end

    local holder = model(parent, kind)
    builder(holder, cframe)
    return holder
end

FeatureBuilder.PropKinds = PROPS

return FeatureBuilder
