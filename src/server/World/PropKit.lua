-- Utilidades comunes de la utilería procedural: piezas livianas para celulares,
-- presupuesto de piezas por capítulo y el gancho para mallas importadas.
--
-- Gancho de mallas: si existe ServerStorage.NocturnaProps.<Nombre> (un Model o una
-- MeshPart), se clona escalado a la caja del objeto en lugar de la versión
-- procedural. Los nombres y medidas de cada caja están en PropKit.Boxes y en
-- assets/models/props/README.md.
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage").Shared
local TextureAssets = require(Shared.Config.TextureAssets)
local MaterialLibrary = require(script.Parent.MaterialLibrary)

local PropKit = {}

PropKit.FOLDER = "NocturnaProps"

-- Caja (ancho X, alto Y, profundidad Z) de cada objeto reemplazable por una malla.
-- El frente mira hacia -Z; la base de la caja apoya en el piso del objeto.
PropKit.Boxes = {
    -- Objetos que se juntan
    Fuse = Vector3.new(1.8, 0.6, 0.6),
    Battery = Vector3.new(0.7, 1.4, 0.7),
    Medkit = Vector3.new(1.8, 1, 1.2),
    Key = Vector3.new(1.4, 0.2, 0.6),
    Keycard = Vector3.new(1, 0.15, 0.7),
    Radio = Vector3.new(1.6, 2, 0.7),
    Sample = Vector3.new(1.2, 1.3, 0.6),
    MemoryShard = Vector3.new(1, 0.1, 0.8),
    PickupStand = Vector3.new(1.8, 1.6, 1.6),
    -- Escondites (la puerta o la abertura mira hacia -Z)
    Locker = Vector3.new(3.4, 7.6, 2.8),
    Wardrobe = Vector3.new(4.6, 7.8, 2.6),
    HideDesk = Vector3.new(6, 3, 3.2),
    HideBed = Vector3.new(7.4, 3.2, 3.8),
    VentDuct = Vector3.new(4.2, 12.9, 3.4),
    -- Máquinas
    Generator = Vector3.new(6.4, 6.2, 4.4),
    FusePanel = Vector3.new(3, 3.2, 0.8),
    Terminal = Vector3.new(5, 5.4, 2.8),
    Valve = Vector3.new(3.4, 13, 3),
    Core = Vector3.new(7, 11, 7),
    ExitDoor = Vector3.new(9, 10, 2.4),
    DocumentTable = Vector3.new(3, 2.6, 2),
    -- Muebles de las salas (contra la pared, el respaldo hacia +Z)
    Desk = Vector3.new(5.6, 4.4, 4.6),
    FilingCabinet = Vector3.new(2, 4.6, 2.2),
    Shelf = Vector3.new(6, 7.2, 2),
    Bookcase = Vector3.new(6, 8, 1.8),
    LabTable = Vector3.new(7, 4.4, 3),
    HospitalBed = Vector3.new(3.6, 6.2, 7.4),
    Wheelchair = Vector3.new(2.4, 3.4, 3),
    Workbench = Vector3.new(7, 6.5, 2.6),
    CrateStack = Vector3.new(6, 5.5, 4),
    BarrelGroup = Vector3.new(5.5, 4.2, 3),
    ElectricalPanel = Vector3.new(3, 4.6, 1.2),
    ServerRack = Vector3.new(3.2, 7.4, 2.4),
    Sofa = Vector3.new(7, 3.2, 3),
    KitchenCounter = Vector3.new(8, 7.4, 2.4),
    ChildBed = Vector3.new(3.4, 3, 6.4),
    Dresser = Vector3.new(4.4, 6, 2),
    TVStand = Vector3.new(4, 4.4, 2),
    SpecimenTank = Vector3.new(3.4, 8.4, 3.4),
    OperatingTable = Vector3.new(3, 10, 6.6),
    GrowthMass = Vector3.new(5, 6, 4),
    Boiler = Vector3.new(4.4, 8.6, 4),
    WaterCooler = Vector3.new(1.4, 4.4, 1.4),
    Plant = Vector3.new(1.6, 4.2, 1.6),
    Extinguisher = Vector3.new(1, 2.6, 0.8),
    TrashBin = Vector3.new(1.4, 1.8, 1.4),
    Crate = Vector3.new(4, 5, 4),
    Barrel = Vector3.new(3, 4.5, 3),
    CornerPipe = Vector3.new(2, 13, 2),
    Cable = Vector3.new(3, 4, 3),
}

-- Presupuesto ------------------------------------------------------------------

local budget = {Count = 0, Limit = math.huge, Reserve = 0}

function PropKit.ResetBudget(limit)
    budget.Count = 0
    budget.Limit = limit or math.huge
    budget.Reserve = 0
end

-- Piezas apartadas para una pasada posterior (por ejemplo, el desgaste de las
-- paredes): mientras dure la reserva, Fits las cuenta como usadas.
function PropKit.SetReserve(count)
    budget.Reserve = math.max(0, count or 0)
end

function PropKit.Used()
    return budget.Count
end

function PropKit.Remaining()
    return budget.Limit - budget.Count
end

-- ¿Entran `count` piezas más sin pasarse?
function PropKit.Fits(count)
    return budget.Count + count + budget.Reserve <= budget.Limit
end

-- Piezas ------------------------------------------------------------------------

local materialCache = {}

function PropKit.Material(name)
    local cached = materialCache[name]
    if cached then
        return cached
    end
    local success, material = pcall(function()
        return Enum.Material[name]
    end)
    cached = success and material or Enum.Material.Concrete
    materialCache[name] = cached
    return cached
end

-- Texturas PBR propias -------------------------------------------------------------
-- Las horneadas en Blender (assets/textures) se suben a Roblox y sus números se
-- pegan en TextureAssets; MaterialLibrary crea los MaterialVariant al cargar cada
-- capítulo. Paredes, pisos y techos usan la variante de ThemeConfig.Surfaces
-- (Wall/Floor/Ceiling) y la utilería y las puertas la que corresponde a su material
-- (PropKit.SurfaceProps). Sin números (0) todo sigue con los materiales de Roblox.
-- Una variante hecha a mano en Studio con el mismo nombre también se usa.
local variantCache = {}

local function findVariant(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    local cached = variantCache[name]
    if cached ~= nil then
        return cached or nil
    end
    local found = false
    local success, service = pcall(function()
        return game:GetService("MaterialService")
    end)
    if success and service then
        local variant = service:FindFirstChild(name, true)
        if variant and variant:IsA("MaterialVariant") then
            found = variant
        end
    end
    variantCache[name] = found
    return found or nil
end

-- Crea las variantes que ya tienen imágenes y vuelve a buscarlas (al cargar cada
-- capítulo).
function PropKit.RefreshSurfaces()
    local ok, err = pcall(MaterialLibrary.Ensure)
    if not ok then
        warn("[NOCTURNA] No se pudieron crear las texturas propias: " .. tostring(err))
    end
    table.clear(variantCache)
end

local function luminance(color)
    return color.R * 0.299 + color.G * 0.587 + color.B * 0.114
end

local function useVariant(part, variant)
    part.Material = variant.BaseMaterial
    part.MaterialVariant = variant.Name
end

-- Aplica la textura PBR de `key` (Wall, Floor, Ceiling...) del tema si existe.
-- El material base pasa a ser el del MaterialVariant para que Roblox lo acepte.
-- Las texturas propias ya traen su color: la pieza toma el tono de la variante
-- (Tint), con la misma variación de brillo que tenía respecto del color del tema.
-- Devuelve true si la usó.
function PropKit.Surface(part, theme, key)
    local surfaces = theme and theme.Surfaces
    local variant = surfaces and findVariant(surfaces[key])
    if not variant then
        return false
    end
    useVariant(part, variant)
    local tint = variant:GetAttribute(MaterialLibrary.TINT)
    if typeof(tint) == "Color3" then
        local base = theme[key]
        local factor = 1
        if typeof(base) == "Color3" and luminance(base) > 0.01 then
            factor = math.clamp(luminance(part.Color) / luminance(base), 0.85, 1.15)
        end
        part.Color = PropKit.Shade(tint, factor)
    end
    return true
end

-- Una pieza teñida: el color de la pieza dividido por el color medio de la textura
-- (Roblox multiplica los dos), así el mueble conserva su tono y su brillo.
local function compensate(part, variant)
    local mean = variant:GetAttribute(MaterialLibrary.MEAN)
    if typeof(mean) ~= "Color3" then
        return
    end
    local color = part.Color
    part.Color = Color3.new(
        math.clamp(color.R / math.max(mean.R, 0.2), 0, 1),
        math.clamp(color.G / math.max(mean.G, 0.2), 0, 1),
        math.clamp(color.B / math.max(mean.B, 0.2), 0, 1)
    )
end

-- Lo que no lleva textura de utilería: luces, sangre y daños (son geometría con su
-- propio color), mallas con textura propia y piezas invisibles.
local SKIP_FOLDERS = {Weathering = true}

local function skipped(part, root)
    if part.MaterialVariant ~= "" or part.Transparency >= 0.95 then
        return true
    end
    if part:IsA("MeshPart") and (part.TextureID ~= "" or part:FindFirstChildOfClass("SurfaceAppearance")) then
        return true
    end
    local parent = part.Parent
    while parent and parent ~= root do
        if SKIP_FOLDERS[parent.Name] then
            return true
        end
        parent = parent.Parent
    end
    return false
end

-- Utilería, muebles, puertas y escondites: cada pieza toma la variante que el tema
-- asigna a su material (TextureAssets.PropMaterials → ThemeConfig.Surfaces).
-- Devuelve cuántas piezas cambió.
function PropKit.SurfaceProps(root, theme)
    local surfaces = theme and theme.Surfaces
    if not root or not surfaces then
        return 0
    end
    local byMaterial = {}
    local any = false
    for materialName, key in pairs(TextureAssets.PropMaterials) do
        local variant = findVariant(surfaces[key])
        if variant then
            byMaterial[materialName] = variant
            any = true
        end
    end
    if not any then
        return 0
    end
    local count = 0
    for _, part in ipairs(root:GetDescendants()) do
        if part:IsA("BasePart") then
            local variant = byMaterial[part.Material.Name]
            if variant and not skipped(part, root) then
                useVariant(part, variant)
                compensate(part, variant)
                count += 1
            end
        end
    end
    return count
end

function PropKit.Shade(color, factor)
    return Color3.new(
        math.clamp(color.R * factor, 0, 1),
        math.clamp(color.G * factor, 0, 1),
        math.clamp(color.B * factor, 0, 1)
    )
end

-- Pequeña variación de tono para que dos paredes iguales no se vean idénticas.
function PropKit.Vary(color, rng, amount)
    return PropKit.Shade(color, 1 + (rng:Float() * 2 - 1) * (amount or 0.06))
end

-- Pieza decorativa: anclada, sin colisión, sin consultas ni sombras. Así no pesa
-- en la física del celular ni tapa la vista de las criaturas.
-- options: Shape, Solid (colisiona y bloquea la vista), Shadow, Transparency,
-- Reflectance, Class ("WedgePart" para cortes en cuña, como los zarpazos).
function PropKit.Part(parent, name, size, cframe, color, material, options)
    local item = Instance.new(options ~= nil and options.Class or "Part")
    item.Name = name
    item.Size = size
    item.CFrame = cframe
    item.Anchored = true
    item.Color = color
    item.Material = material or Enum.Material.SmoothPlastic
    item.TopSurface = Enum.SurfaceType.Smooth
    item.BottomSurface = Enum.SurfaceType.Smooth
    item.CanTouch = false

    local solid = options ~= nil and options.Solid == true
    item.CanCollide = solid
    item.CanQuery = solid
    item.CastShadow = options ~= nil and (options.Shadow == true or (options.Shadow == nil and solid)) or false

    if options then
        if options.Shape then
            item.Shape = options.Shape
        end
        if options.Transparency then
            item.Transparency = options.Transparency
        end
        if options.Reflectance then
            item.Reflectance = options.Reflectance
        end
    end

    item.Parent = parent
    budget.Count += 1
    return item
end

local SOLID = {Solid = true}
local CYLINDER = {Shape = Enum.PartType.Cylinder}
local SOLID_CYLINDER = {Shape = Enum.PartType.Cylinder, Solid = true}
local BALL = {Shape = Enum.PartType.Ball}

PropKit.SOLID = SOLID
PropKit.CYLINDER = CYLINDER
PropKit.SOLID_CYLINDER = SOLID_CYLINDER
PropKit.BALL = BALL

-- Pieza que colisiona: estructura y muebles grandes.
function PropKit.Solid(parent, name, size, cframe, color, material)
    return PropKit.Part(parent, name, size, cframe, color, material, SOLID)
end

-- Cilindro con el eje a lo largo de X (como lo dibuja Roblox).
function PropKit.Cylinder(parent, name, length, diameter, cframe, color, material, solid)
    return PropKit.Part(
        parent,
        name,
        Vector3.new(length, diameter, diameter),
        cframe,
        color,
        material,
        solid and SOLID_CYLINDER or CYLINDER
    )
end

-- Cilindro parado (eje vertical).
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
function PropKit.Column(parent, name, height, diameter, cframe, color, material, solid)
    return PropKit.Cylinder(parent, name, height, diameter, cframe * UPRIGHT, color, material, solid)
end

function PropKit.Model(parent, name)
    local item = Instance.new("Model")
    item.Name = name
    item.Parent = parent
    return item
end

function PropKit.AddPrompt(host, actionText, objectText, holdDuration)
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

function PropKit.Light(parent, className, color, brightness, range, shadows)
    local light = Instance.new(className or "PointLight")
    light.Color = color
    light.Brightness = brightness
    light.Range = range
    light.Shadows = shadows == true
    light.Parent = parent
    return light
end

-- Gancho de mallas ----------------------------------------------------------------

function PropKit.Template(name)
    local folder = ServerStorage:FindFirstChild(PropKit.FOLDER)
    local template = folder and folder:FindFirstChild(name)
    if template and (template:IsA("Model") or template:IsA("BasePart")) then
        return template
    end
    return nil
end

local CORNERS = {}
for _, x in ipairs({-0.5, 0.5}) do
    for _, y in ipairs({-0.5, 0.5}) do
        for _, z in ipairs({-0.5, 0.5}) do
            table.insert(CORNERS, Vector3.new(x, y, z))
        end
    end
end

local function collectParts(root)
    local parts = {}
    if root:IsA("BasePart") then
        table.insert(parts, root)
    end
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("BasePart") then
            table.insert(parts, descendant)
        end
    end
    return parts
end

-- Clona la plantilla y la escala para que entre en la caja `size`, apoyada en el
-- piso de `base` (centro de la base de la caja, orientado como el objeto).
function PropKit.FitTemplate(template, parent, base, size)
    local clone = template:Clone()
    local parts = collectParts(clone)
    if #parts == 0 then
        clone:Destroy()
        return nil
    end

    local minimum = Vector3.new(math.huge, math.huge, math.huge)
    local maximum = -minimum
    for _, piece in ipairs(parts) do
        for _, corner in ipairs(CORNERS) do
            local point = (piece.CFrame * CFrame.new(piece.Size * corner)).Position
            minimum = minimum:Min(point)
            maximum = maximum:Max(point)
        end
    end

    local extent = maximum - minimum
    local scale = math.min(
        size.X / math.max(extent.X, 0.05),
        size.Y / math.max(extent.Y, 0.05),
        size.Z / math.max(extent.Z, 0.05)
    )
    local anchor = Vector3.new((minimum.X + maximum.X) / 2, minimum.Y, (minimum.Z + maximum.Z) / 2)

    for _, piece in ipairs(parts) do
        local offset = (piece.Position - anchor) * scale
        local rotation = piece.CFrame - piece.Position
        piece.Size *= scale
        piece.CFrame = base * CFrame.new(offset) * rotation
        piece.Anchored = true
        piece.CanTouch = false
    end

    clone:SetAttribute("NocturnaMesh", true)
    clone.Parent = parent
    budget.Count += #parts
    return clone
end

-- Dibuja un objeto con la malla importada si existe, o con `build(parent)` si no.
-- Devuelve true cuando usó la malla.
function PropKit.Visual(parent, name, base, build)
    local template = PropKit.Template(name)
    if template then
        local size = PropKit.Boxes[name] or Vector3.new(4, 4, 4)
        if PropKit.FitTemplate(template, parent, base, size) then
            return true
        end
    end
    build(parent)
    return false
end

return PropKit
