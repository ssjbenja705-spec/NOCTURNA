-- Galería del Núcleo: el escenario de la persecución final, armado por tramos.
-- Ancha, recta y oscura: hormigón vencido, caños, luces de emergencia, carteles de
-- evacuación, camillas volcadas, marcas de garras y el tejido del Organismo que
-- crece hacia el fondo. Sólo existen los tramos cerca del grupo (presupuesto de
-- celular): lo de atrás se borra y lo de adelante se construye a tiempo.
--
-- Los obstáculos no chocan (CanCollide = false): el servidor decide si cada
-- jugador los pasó bien. Así nadie queda trabado por la física. Las compuertas sí
-- son sólidas hasta que alguien las embiste.
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Rng = require(Shared.Logic.Rng)

local ChaseArena = {}
ChaseArena.__index = ChaseArena

local FOLDER_NAME = "NOCTURNA_CHASE"
local LIGHT_TAG = "NocturnaChaseLight"

local CONCRETE = Color3.fromRGB(64, 61, 57)
local CONCRETE_DARK = Color3.fromRGB(40, 38, 36)
local TILE = Color3.fromRGB(58, 70, 64)
local RUST = Color3.fromRGB(92, 58, 40)
local METAL = Color3.fromRGB(70, 72, 74)
local TISSUE = Color3.fromRGB(70, 18, 22)
local STAIN = Color3.fromRGB(48, 14, 12)
local EMERGENCY = Color3.fromRGB(255, 58, 40)
local AMBER = Color3.fromRGB(255, 150, 60)

local SIGNS = {
    "SECTOR N — ACCESO AL NÚCLEO",
    "EVACUACIÓN  →",
    "PELIGRO: SUSTRATO ACTIVO",
    "NO RESPONDER A LAS VOCES",
    "FUNDACIÓN LETEO — PERSONAL AUTORIZADO",
    "CONTENCIÓN 3 · CLAUSURADA",
}

local function part(parent, name, size, cframe, color, material, collide)
    local piece = Instance.new("Part")
    piece.Name = name
    piece.Size = size
    piece.CFrame = cframe
    piece.Color = color
    piece.Material = material or Enum.Material.Concrete
    piece.Anchored = true
    piece.CanCollide = collide == true
    piece.CanTouch = false
    piece.CanQuery = collide == true
    piece.CastShadow = false
    piece.TopSurface = Enum.SurfaceType.Smooth
    piece.BottomSurface = Enum.SurfaceType.Smooth
    piece.Parent = parent
    return piece
end

local function cylinder(parent, name, length, diameter, cframe, color, material)
    -- El eje de un cilindro de Roblox es X: el largo va en X.
    local piece = part(parent, name, Vector3.new(length, diameter, diameter), cframe, color, material)
    piece.Shape = Enum.PartType.Cylinder
    return piece
end

local function sign(parent, text, cframe, width)
    local board = part(parent, "Sign", Vector3.new(width, 1.6, 0.2), cframe, Color3.fromRGB(28, 60, 36), Enum.Material.SmoothPlastic)
    local gui = Instance.new("SurfaceGui")
    gui.Face = Enum.NormalId.Front
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = 40
    gui.LightInfluence = 1
    gui.Parent = board
    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextScaled = true
    label.Font = Enum.Font.SpecialElite
    label.TextColor3 = Color3.fromRGB(214, 226, 200)
    label.Parent = gui
    return board
end

local function dust(parent, cframe, rate, color)
    local anchor = part(parent, "DustSource", Vector3.new(1, 1, 1), cframe, CONCRETE, Enum.Material.SmoothPlastic)
    anchor.Transparency = 1
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
    emitter.Rate = rate
    emitter.Lifetime = NumberRange.new(5, 8)
    emitter.Speed = NumberRange.new(0.6, 1.6)
    emitter.SpreadAngle = Vector2.new(70, 70)
    emitter.Acceleration = Vector3.new(0, -0.6, 0)
    emitter.Size = NumberSequence.new(0.4, 1.4)
    emitter.Transparency = NumberSequence.new(0.82, 1)
    emitter.Color = ColorSequence.new(color or Color3.fromRGB(150, 140, 128))
    emitter.LightEmission = 0
    emitter.Parent = anchor
    return emitter
end

local function lamp(parent, cframe, color, flicker)
    local housing = part(parent, "EmergencyLight", Vector3.new(1.4, 0.8, 2.2), cframe, color, Enum.Material.Neon)
    local light = Instance.new("PointLight")
    light.Color = color
    light.Range = 26
    light.Brightness = 1.5
    light.Shadows = false
    light.Parent = housing
    housing:SetAttribute("Flicker", flicker == true)
    CollectionService:AddTag(housing, LIGHT_TAG)
    return housing
end

function ChaseArena.new(config, obstacles, seed)
    local folder = Instance.new("Model")
    folder.Name = FOLDER_NAME
    folder.Parent = workspace

    local self = setmetatable({
        Config = config,
        Arena = config.Arena,
        Obstacles = obstacles,
        Seed = seed or 1,
        Folder = folder,
        Segments = {},
        State = {},
        Shutter = nil,
    }, ChaseArena)
    self:BuildEnds()
    return self
end

-- Posición en el mundo de un punto de la galería.
function ChaseArena:Point(s, lateral, height)
    local origin = self.Arena.Origin
    return Vector3.new(origin.X + (lateral or 0), height or 0, origin.Z + s)
end

-- Mirando hacia la compuerta del Núcleo (+Z).
function ChaseArena:Frame(s, lateral, height)
    local position = self:Point(s, lateral, height)
    return CFrame.lookAt(position, position + Vector3.new(0, 0, 1))
end

function ChaseArena:Coordinates(position)
    local origin = self.Arena.Origin
    return position.Z - origin.Z, position.X - origin.X
end

function ChaseArena:Contains(position)
    local s, lateral = self:Coordinates(position)
    local arena = self.Arena
    return math.abs(lateral) <= arena.Width / 2 + 4 and s >= arena.BackS - 10 and s <= arena.Length + 10
        and position.Y > -20 and position.Y < arena.Height + 10
end

-- Paredes de los extremos: atrás, la pared que revienta la criatura; adelante,
-- el fondo del vestíbulo del Núcleo. También la compuerta final, levantada.
function ChaseArena:BuildEnds()
    local arena = self.Arena
    local width, height = arena.Width, arena.Height
    local ends = Instance.new("Model")
    ends.Name = "Ends"
    ends.Parent = self.Folder

    -- Fondo de atrás, reventado en el centro: de ahí sale El Organismo.
    local back = arena.BackS
    for _, side in ipairs({-1, 1}) do
        part(ends, "BackWall", Vector3.new(width * 0.32, height, 2), self:Frame(back, side * width * 0.34, height / 2), CONCRETE_DARK, Enum.Material.Concrete, true)
    end
    part(ends, "BackLintel", Vector3.new(width * 0.36, height * 0.35, 2), self:Frame(back, 0, height * 0.82), CONCRETE_DARK, Enum.Material.Concrete, true)
    for index = 1, 5 do
        local offset = (index - 3) * 2.6
        part(ends, "BreachRubble", Vector3.new(2.4, 1.6, 2.2), self:Frame(back + 3 + index, offset, 0.8) * CFrame.Angles(0.3 * index, index, 0.2), CONCRETE, Enum.Material.Slate)
    end
    dust(ends, self:Frame(back + 4, 0, height - 3), 10)

    -- Fondo del vestíbulo, pasada la compuerta del Núcleo.
    part(ends, "FrontWall", Vector3.new(width + 4, height + 2, 2), self:Frame(arena.Length + 1, 0, height / 2), CONCRETE_DARK, Enum.Material.Concrete, true)

    -- Marco enorme de la compuerta del Núcleo, con luz fría del otro lado.
    local finish = arena.FinishS
    for _, side in ipairs({-1, 1}) do
        part(ends, "CorePost", Vector3.new(3, height, 3), self:Frame(finish, side * (width / 2 - 1.5), height / 2), METAL, Enum.Material.DiamondPlate, true)
    end
    part(ends, "CoreLintel", Vector3.new(width, 3, 3), self:Frame(finish, 0, height - 1.5), METAL, Enum.Material.DiamondPlate)
    sign(ends, "NÚCLEO", self:Frame(finish - 1.7, 0, height - 1.5) * CFrame.Angles(0, math.pi, 0), 10)
    local glow = part(ends, "CoreGlow", Vector3.new(width - 6, 0.4, 0.4), self:Frame(finish + 6, 0, height - 4), Color3.fromRGB(150, 210, 230), Enum.Material.Neon)
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(160, 210, 235)
    light.Range = 40
    light.Brightness = 1.4
    light.Shadows = false
    light.Parent = glow

    -- La compuerta queda arriba y baja cuando todos pasaron.
    self.Shutter = part(ends, "CoreShutter", Vector3.new(width - 6, height - 3, 1.4), self:Frame(finish + 2.5, 0, height + (height - 3) / 2 - 1), RUST, Enum.Material.CorrodedMetal)
    self.ShutterClosed = self:Frame(finish + 2.5, 0, (height - 3) / 2)
end

-- Tramo k: de k * largo a (k + 1) * largo.
function ChaseArena:BuildSegment(k)
    local arena = self.Arena
    local length = arena.SegmentLength
    local width, height = arena.Width, arena.Height
    local s0 = k * length
    local mid = s0 + length / 2
    local rng = Rng.new(self.Seed * 31 + (k + 10) * 977)
    local progress = math.clamp(s0 / arena.FinishS, 0, 1)

    local segment = Instance.new("Model")
    segment.Name = "Segment" .. k
    segment:SetAttribute("Index", k)

    -- Estructura (lo único sólido además de las compuertas).
    part(segment, "Floor", Vector3.new(width + 4, 2, length), self:Frame(mid, 0, -1), CONCRETE_DARK, Enum.Material.Concrete, true)
    part(segment, "Ceiling", Vector3.new(width + 4, 2, length), self:Frame(mid, 0, height + 1), CONCRETE_DARK, Enum.Material.Concrete, true)
    for _, side in ipairs({-1, 1}) do
        part(segment, "Wall", Vector3.new(2, height + 2, length), self:Frame(mid, side * (width / 2 + 1), height / 2), CONCRETE, Enum.Material.Concrete, true)
        -- Zócalo de azulejos de hospital, manchado.
        part(segment, "Tiles", Vector3.new(0.3, 3.6, length), self:Frame(mid, side * (width / 2 - 0.15), 1.8), TILE, Enum.Material.Slate)
        -- Columnas y caños por las paredes.
        for _, offset in ipairs({2, length / 2 + 2}) do
            part(segment, "Pillar", Vector3.new(2.6, height, 2.6), self:Frame(s0 + offset, side * (width / 2 - 1.3), height / 2), CONCRETE_DARK, Enum.Material.Concrete, true)
        end
        for row, y in ipairs({height - 3, height - 4.6}) do
            local broken = row == 1 and rng:Chance(0.3)
            local pipeLength = broken and length * 0.6 or length
            cylinder(segment, "Pipe", pipeLength, 1.2, self:Frame(s0 + pipeLength / 2, side * (width / 2 - 1.1), y) * CFrame.Angles(0, math.pi / 2, 0), RUST, Enum.Material.CorrodedMetal)
            if broken then
                dust(segment, self:Frame(s0 + pipeLength, side * (width / 2 - 1.1), y - 0.6), 6, Color3.fromRGB(90, 96, 100))
            end
        end
    end
    part(segment, "Beam", Vector3.new(width, 1.6, 1.8), self:Frame(s0 + 2, 0, height - 0.8), CONCRETE_DARK, Enum.Material.Concrete)

    -- Luz de emergencia: una por tramo, de un lado o del otro; algunas parpadean.
    local lampSide = (k % 2 == 0) and -1 or 1
    local color = rng:Chance(0.7) and EMERGENCY or AMBER
    lamp(segment, self:Frame(s0 + length * 0.7, lampSide * (width / 2 - 0.5), height - 7) * CFrame.Angles(0, math.pi / 2, 0), color, rng:Chance(0.4))

    -- Polvo que cae del techo.
    dust(segment, self:Frame(mid, rng:Int(-8, 8), height - 1.2), 3)

    -- Escombros contra las paredes.
    for _ = 1, rng:Int(2, 4) do
        local side = rng:Chance(0.5) and -1 or 1
        local size = Vector3.new(rng:Int(15, 40) / 10, rng:Int(10, 26) / 10, rng:Int(15, 40) / 10)
        part(segment, "Rubble", size, self:Frame(s0 + rng:Int(2, length - 2), side * (width / 2 - 2 - rng:Float() * 3), size.Y / 2 - 0.2)
            * CFrame.Angles(rng:Float() * 0.6, rng:Float() * 3, rng:Float() * 0.6), CONCRETE, Enum.Material.Slate)
    end

    -- Manchas en el piso (algo terrible pasó acá).
    if rng:Chance(0.6) then
        part(segment, "Stain", Vector3.new(rng:Int(30, 70) / 10, 0.05, rng:Int(30, 70) / 10), self:Frame(s0 + rng:Int(4, length - 4), rng:Int(-12, 12), 0.03)
            * CFrame.Angles(0, rng:Float() * 3, 0), STAIN, Enum.Material.SmoothPlastic)
    end

    self:BuildProps(segment, rng, s0, progress)
    self:BuildObstacles(segment, s0, s0 + length)

    segment.Parent = self.Folder
    self.Segments[k] = segment
    return segment
end

-- Utilería que cuenta lo que pasó: camillas volcadas, ventanas de observación
-- rotas, garras en las paredes, papeles, carteles y el tejido del Organismo.
function ChaseArena:BuildProps(segment, rng, s0, progress)
    local arena = self.Arena
    local width, height, length = arena.Width, arena.Height, arena.SegmentLength
    local half = width / 2

    local kinds = {"Gurney", "Window", "Claws", "Papers", "Cables", "Cabinet"}
    rng:Shuffle(kinds)
    for index = 1, 2 do
        local kind = kinds[index]
        local s = s0 + rng:Int(6, length - 6)
        local side = rng:Chance(0.5) and -1 or 1
        if kind == "Gurney" then
            local base = self:Frame(s, side * (half - 4), 1.4) * CFrame.Angles(0, rng:Float() * 2, side * 1.3)
            part(segment, "Gurney", Vector3.new(2.4, 0.4, 6), base, Color3.fromRGB(150, 150, 146), Enum.Material.Metal)
            part(segment, "GurneySheet", Vector3.new(2.2, 0.3, 5), base * CFrame.new(0, 0.35, 0), Color3.fromRGB(170, 160, 150), Enum.Material.Fabric)
        elseif kind == "Window" then
            -- Marco contra la pared, adentro negro y adelante el vidrio roto.
            local turn = CFrame.Angles(0, math.pi / 2, 0)
            part(segment, "WindowFrame", Vector3.new(8.6, 5, 0.3), self:Frame(s, side * (half - 0.15), 6) * turn, METAL, Enum.Material.Metal)
            part(segment, "Darkness", Vector3.new(7.6, 4, 0.1), self:Frame(s, side * (half - 0.35), 6) * turn, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
            local glass = part(segment, "BrokenGlass", Vector3.new(7.6, 4, 0.1), self:Frame(s, side * (half - 0.5), 6) * turn, Color3.fromRGB(120, 140, 140), Enum.Material.Glass)
            glass.Transparency = 0.55
        elseif kind == "Claws" then
            for scratch = -1, 1 do
                part(segment, "ClawMark", Vector3.new(0.12, 5, 0.3), self:Frame(s + scratch * 0.7, side * (half - 0.05), 7 + scratch * 0.3)
                    * CFrame.Angles(0.35, 0, 0), Color3.fromRGB(20, 16, 16), Enum.Material.SmoothPlastic)
            end
        elseif kind == "Papers" then
            for _ = 1, 3 do
                part(segment, "Paper", Vector3.new(0.9, 0.04, 1.2), self:Frame(s + rng:Int(-3, 3), rng:Int(-10, 10), 0.04)
                    * CFrame.Angles(0, rng:Float() * 3, 0), Color3.fromRGB(214, 206, 186), Enum.Material.SmoothPlastic)
            end
        elseif kind == "Cables" then
            for strand = 0, 1 do
                part(segment, "Cable", Vector3.new(0.2, 6, 0.2), self:Frame(s + strand * 1.5, rng:Int(-10, 10), height - 3)
                    * CFrame.Angles(rng:Float() * 0.4 - 0.2, 0, rng:Float() * 0.4 - 0.2), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic)
            end
        elseif kind == "Cabinet" then
            part(segment, "Cabinet", Vector3.new(2.2, 5, 2), self:Frame(s, side * (half - 3), 1) * CFrame.Angles(math.pi / 2, rng:Float(), 0), Color3.fromRGB(86, 90, 86), Enum.Material.Metal)
        end
    end

    -- Carteles de la Fundación cada dos tramos.
    if (s0 / length) % 2 == 0 then
        local side = rng:Chance(0.5) and -1 or 1
        sign(segment, rng:Pick(SIGNS), self:Frame(s0 + 10, side * (half - 0.2), 9) * CFrame.Angles(0, -side * math.pi / 2, 0), 9)
    end

    -- El tejido del Organismo crece hacia el Núcleo.
    for _ = 1, math.floor(progress * 4 + rng:Float()) do
        local side = rng:Chance(0.5) and -1 or 1
        local radius = rng:Int(20, 45) / 10
        local blob = part(segment, "Tissue", Vector3.new(radius, radius, radius), self:Frame(s0 + rng:Int(2, length - 2), side * (half - 0.4), rng:Int(1, math.floor(height - 4))),
            TISSUE, Enum.Material.SmoothPlastic)
        blob.Shape = Enum.PartType.Ball
    end
end

-- Zona del derrumbe: centro lateral y ancho de la franja según el lado.
function ChaseArena:DebrisZone(side)
    local width = self.Arena.Width
    if side == 0 then
        return 0, width * 0.44
    end
    return side * (width / 2 - width * 0.275), width * 0.55
end

function ChaseArena:BuildObstacle(segment, entry)
    local arena = self.Arena
    local width, height = arena.Width, arena.Height
    local settings = self.Config.Obstacles
    local model = Instance.new("Model")
    model.Name = "Obstacle" .. entry.Id
    model:SetAttribute("ChaseObstacle", entry.Id)
    model:SetAttribute("Kind", entry.Kind)
    local state = self.State[entry.Id] or {}
    self.State[entry.Id] = state

    if entry.Kind == "Vault" then
        -- Un conducto caído de pared a pared, con lockers volcados encima.
        local duct = cylinder(model, "Duct", width - 1, settings.VaultHeight - 0.4, self:Frame(entry.S, 0, (settings.VaultHeight - 0.4) / 2), RUST, Enum.Material.CorrodedMetal)
        model.PrimaryPart = duct
        part(model, "Locker", Vector3.new(5, 1.4, 2), self:Frame(entry.S, -width / 4, settings.VaultHeight - 0.3) * CFrame.Angles(0, 0.2, 0), Color3.fromRGB(70, 84, 92), Enum.Material.Metal)
        part(model, "Locker", Vector3.new(5, 1.4, 2), self:Frame(entry.S, width / 4, settings.VaultHeight - 0.4) * CFrame.Angles(0, -0.3, 0), Color3.fromRGB(70, 84, 92), Enum.Material.Metal)
        part(model, "Hazard", Vector3.new(width - 4, 0.3, 0.1), self:Frame(entry.S - 1.3, 0, 1.4), Color3.fromRGB(200, 160, 40), Enum.Material.SmoothPlastic)
    elseif entry.Kind == "Slide" then
        -- Una viga de acero caída en diagonal: por debajo se pasa agachado.
        local clearance = settings.SlideClearance
        local beam = part(model, "Beam", Vector3.new(width + 2, 1.8, 1.6), self:Frame(entry.S, 0, clearance + 0.9) * CFrame.Angles(0, 0, 0.05), METAL, Enum.Material.DiamondPlate)
        model.PrimaryPart = beam
        part(model, "Ducts", Vector3.new(width - 2, 2.4, 1.4), self:Frame(entry.S + 0.6, 0, clearance + 3), RUST, Enum.Material.CorrodedMetal)
        part(model, "Hazard", Vector3.new(width - 4, 0.3, 0.1), self:Frame(entry.S - 0.85, 0, clearance + 0.3), Color3.fromRGB(200, 160, 40), Enum.Material.SmoothPlastic)
        local sparks = part(model, "Sparks", Vector3.new(0.4, 0.4, 0.4), self:Frame(entry.S, width / 2 - 4, clearance + 0.4), AMBER, Enum.Material.Neon)
        local emitter = Instance.new("ParticleEmitter")
        emitter.Rate = 9
        emitter.Lifetime = NumberRange.new(0.3, 0.7)
        emitter.Speed = NumberRange.new(6, 12)
        emitter.SpreadAngle = Vector2.new(50, 50)
        emitter.Acceleration = Vector3.new(0, -40, 0)
        emitter.Size = NumberSequence.new(0.15, 0)
        emitter.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90))
        emitter.LightEmission = 1
        emitter.Parent = sparks
    elseif entry.Kind == "Debris" then
        -- Una losa colgando del techo sobre la franja donde va a caer.
        local center, span = self:DebrisZone(entry.Side or 0)
        local hanging = self:Frame(entry.S, center, height - 1.6) * CFrame.Angles(0.12, 0, 0.08)
        local landed = self:Frame(entry.S, center, 0.9) * CFrame.Angles(0.08, 0.2, -0.06)
        local slab = part(model, "Slab", Vector3.new(span, 1.8, 7), state.Landed and landed or hanging, CONCRETE, Enum.Material.Slate)
        model.PrimaryPart = slab
        model:SetAttribute("Center", center)
        model:SetAttribute("Span", span)
        state.Slab = slab
        state.Landed = state.Landed == true
        state.LandedCFrame = landed
        part(model, "Crack", Vector3.new(span, 0.1, 0.6), self:Frame(entry.S - 3.6, center, height - 0.05), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
    elseif entry.Kind == "Door" then
        -- Compuerta de emergencia: sólida hasta que alguien la embiste.
        local leafHeight = 12
        for _, side in ipairs({-1, 1}) do
            part(model, "Post", Vector3.new(3, height, 2), self:Frame(entry.S, side * (width / 2 - 1.5), height / 2), METAL, Enum.Material.DiamondPlate, true)
        end
        part(model, "Header", Vector3.new(width, height - leafHeight, 1.6), self:Frame(entry.S, 0, leafHeight + (height - leafHeight) / 2), CONCRETE_DARK, Enum.Material.Concrete, true)
        sign(model, "COMPUERTA DE EMERGENCIA", self:Frame(entry.S - 0.9, 0, leafHeight + 2) * CFrame.Angles(0, math.pi, 0), 12)
        lamp(model, self:Frame(entry.S - 1.2, 0, leafHeight + 0.8), EMERGENCY, true)
        state.Leaves = {}
        local leafWidth = width / 2 - 3
        for _, side in ipairs({-1, 1}) do
            local closed = self:Frame(entry.S, side * (leafWidth / 2), leafHeight / 2)
            local hinge = self:Frame(entry.S, side * leafWidth, leafHeight / 2)
            -- Abierta: arrancada de las bisagras, tirada hacia adelante.
            local open = hinge * CFrame.new(0, -leafHeight / 2 + 0.6, 6) * CFrame.Angles(math.pi / 2 - 0.15, side * 0.4, 0) * CFrame.new(-side * leafWidth / 2, 0, 0)
            local leaf = part(model, "Leaf", Vector3.new(leafWidth, leafHeight, 1), state.Burst and open or closed, RUST, Enum.Material.DiamondPlate, not state.Burst)
            table.insert(state.Leaves, {Part = leaf, Open = open})
        end
        model.PrimaryPart = state.Leaves[1].Part
    end

    model.Parent = segment
    return model
end

function ChaseArena:BuildObstacles(segment, fromS, toS)
    local folder = Instance.new("Folder")
    folder.Name = "Obstacles"
    folder.Parent = segment
    for _, entry in ipairs(self.Obstacles) do
        if entry.S >= fromS and entry.S < toS then
            self:BuildObstacle(folder, entry)
        end
    end
end

-- Construye lo que falta entre fromS y toS y borra lo que quedó atrás de fromS.
function ChaseArena:Stream(fromS, toS)
    local arena = self.Arena
    local length = arena.SegmentLength
    local first = math.floor(math.max(arena.BackS, fromS) / length)
    local last = math.floor(math.min(arena.Length - 0.01, toS) / length)

    for k, segment in pairs(self.Segments) do
        if (k + 1) * length < fromS then
            segment:Destroy()
            self.Segments[k] = nil
        end
    end
    for k = first, last do
        if not self.Segments[k] then
            self:BuildSegment(k)
        end
    end
end

function ChaseArena:SegmentCount()
    local count = 0
    for _ in pairs(self.Segments) do
        count += 1
    end
    return count
end

function ChaseArena:PartCount()
    local count = 0
    for _, descendant in ipairs(self.Folder:GetDescendants()) do
        if descendant:IsA("BasePart") then
            count += 1
        end
    end
    return count
end

function ChaseArena:BurstDoor(id)
    local state = self.State[id] or {}
    self.State[id] = state
    if state.Burst then
        return false
    end
    state.Burst = true
    for _, leaf in ipairs(state.Leaves or {}) do
        if leaf.Part.Parent then
            leaf.Part.CanCollide = false
            leaf.Part.CanQuery = false
            leaf.Part.CFrame = leaf.Open
        end
    end
    return true
end

function ChaseArena:IsDoorOpen(id)
    local state = self.State[id]
    return state ~= nil and state.Burst == true
end

function ChaseArena:LandDebris(id)
    local state = self.State[id] or {}
    self.State[id] = state
    state.Landed = true
    if state.Slab and state.Slab.Parent and state.LandedCFrame then
        state.Slab.CFrame = state.LandedCFrame
    end
end

function ChaseArena:CloseShutter()
    if self.Shutter and self.Shutter.Parent then
        self.Shutter.CFrame = self.ShutterClosed
        self.Shutter.CanCollide = true
    end
end

function ChaseArena:Destroy()
    if self.Folder then
        self.Folder:Destroy()
    end
    self.Segments = {}
end

return ChaseArena
