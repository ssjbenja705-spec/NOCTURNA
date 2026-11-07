-- Alma, la hermanita perdida: una nena de verdad, chiquita y tierna, no un muñeco.
--
-- El cuerpo sale, en este orden, de:
--   1. ServerStorage.NocturnaModels.Alma, si es un modelo con Humanoid.
--   2. Un avatar R15 de Roblox (Players:CreateHumanoidModelFromDescription) con
--      proporciones de chica: más baja, cabeza grande, cara feliz, ropa por colores.
--   3. Un R15 armado con piezas, con los mismos nombres de articulaciones, si la
--      API falla (sin conexión o en el motor de pruebas).
-- Mientras espera respira y mira alrededor; cuando el grupo la encuentra salta,
-- saluda y festeja con las animaciones de Roblox, se enciende una luz cálida con
-- chispas y después sigue al jugador más cercano.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)

local AlmaBuilder = {}

local MODELS_FOLDER = "NocturnaModels"
local UPDATE_INTERVAL = 0.2
local FIND_RANGE = 16
local FOLLOW_DISTANCE = 5
local CATCH_UP_DISTANCE = 22
local LOST_DISTANCE = 90
local HAPPY_TIME = 4.8
-- Si lejos del jugador casi no avanza en STALL_TIME segundos (trabada contra algo),
-- aparece detrás de él igual que cuando queda muy atrás.
local STALL_RANGE = 12
local STALL_PROGRESS = 2
local STALL_TIME = 3

AlmaBuilder.Animations = {
    Idle = "rbxassetid://507766666",
    LookAround = "rbxassetid://507766951",
    Walk = "rbxassetid://507777826",
    Run = "rbxassetid://507767714",
    Wave = "rbxassetid://507770239",
    Cheer = "rbxassetid://507770677",
}

local SKIN = Color3.fromRGB(241, 204, 178)
local SWEATER = Color3.fromRGB(255, 205, 105)
local OVERALLS = Color3.fromRGB(120, 152, 205)
local SHOES = Color3.fromRGB(235, 232, 240)
local HAIR = Color3.fromRGB(92, 58, 38)
local WARM = Color3.fromRGB(255, 196, 140)

-- Avatar -------------------------------------------------------------------------

function AlmaBuilder.Description()
    local description = Instance.new("HumanoidDescription")
    description.HeightScale = 0.75
    description.HeadScale = 1.1
    description.WidthScale = 0.8
    description.DepthScale = 0.85
    description.BodyTypeScale = 0
    description.ProportionScale = 0
    description.HeadColor = SKIN
    description.LeftArmColor = SKIN
    description.RightArmColor = SKIN
    description.TorsoColor = SWEATER
    description.LeftLegColor = OVERALLS
    description.RightLegColor = OVERALLS
    -- Face = 0: la cara clásica de Roblox, que sonríe.
    description.Face = 0
    return description
end

local function fromHook()
    local folder = ServerStorage:FindFirstChild(MODELS_FOLDER)
    local hook = folder and folder:FindFirstChild("Alma")
    if hook and hook:IsA("Model") and hook:FindFirstChildOfClass("Humanoid") and hook:FindFirstChild("HumanoidRootPart") then
        return hook:Clone()
    end
    if hook then
        warn("[NOCTURNA] NocturnaModels.Alma necesita un Humanoid y un HumanoidRootPart: se usa el avatar.")
    end
    return nil
end

local function fromDescription()
    local success, rig = pcall(function()
        return Players:CreateHumanoidModelFromDescription(AlmaBuilder.Description(), Enum.HumanoidRigType.R15)
    end)
    if success and rig and rig:FindFirstChild("HumanoidRootPart") and rig:FindFirstChildOfClass("Humanoid") then
        return rig
    end
    return nil
end

local function block(rig, name, size, color, material)
    local piece = Instance.new("Part")
    piece.Name = name
    piece.Size = size
    piece.Color = color
    piece.Material = material or Enum.Material.SmoothPlastic
    piece.TopSurface = Enum.SurfaceType.Smooth
    piece.BottomSurface = Enum.SurfaceType.Smooth
    piece.CastShadow = false
    piece.Parent = rig
    return piece
end

local function joint(name, part0, part1, c0, c1)
    local motor = Instance.new("Motor6D")
    motor.Name = name
    motor.Part0 = part0
    motor.Part1 = part1
    motor.C0 = c0
    motor.C1 = c1
    motor.Parent = part1
    return motor
end

-- R15 hecho con piezas (articulaciones con los nombres de Roblox, así las
-- animaciones oficiales funcionan igual). Medidas de una nena de unos 4 studs.
function AlmaBuilder.BuildFallbackRig()
    local rig = Instance.new("Model")
    rig.Name = "Alma"

    local root = block(rig, "HumanoidRootPart", Vector3.new(1.3, 1.3, 0.7), SKIN)
    root.Transparency = 1
    root.CanCollide = false
    local lower = block(rig, "LowerTorso", Vector3.new(1.3, 0.3, 0.7), OVERALLS, Enum.Material.Fabric)
    local upper = block(rig, "UpperTorso", Vector3.new(1.4, 1, 0.75), SWEATER, Enum.Material.Fabric)
    local head = block(rig, "Head", Vector3.new(1.25, 1.2, 1.2), SKIN)
    local headShape = Instance.new("SpecialMesh")
    headShape.MeshType = Enum.MeshType.Head
    headShape.Scale = Vector3.new(1, 1, 1)
    headShape.Parent = head
    local face = Instance.new("Decal")
    face.Name = "face"
    face.Texture = "rbxasset://textures/face.png"
    face.Face = Enum.NormalId.Front
    face.Parent = head

    -- Origen en el centro de la cadera (LowerTorso).
    joint("Root", root, lower, CFrame.identity, CFrame.identity)
    joint("Waist", lower, upper, CFrame.new(0, 0.15, 0), CFrame.new(0, -0.5, 0))
    joint("Neck", upper, head, CFrame.new(0, 0.5, 0), CFrame.new(0, -0.6, 0))

    for _, side in ipairs({"Left", "Right"}) do
        local x = side == "Left" and -1 or 1
        local upperArm = block(rig, side .. "UpperArm", Vector3.new(0.55, 0.8, 0.55), SWEATER, Enum.Material.Fabric)
        local lowerArm = block(rig, side .. "LowerArm", Vector3.new(0.5, 0.7, 0.5), SKIN)
        local hand = block(rig, side .. "Hand", Vector3.new(0.5, 0.25, 0.5), SKIN)
        joint(side .. "Shoulder", upper, upperArm, CFrame.new(x * 0.97, 0.38, 0), CFrame.new(0, 0.3, 0))
        joint(side .. "Elbow", upperArm, lowerArm, CFrame.new(0, -0.4, 0), CFrame.new(0, 0.35, 0))
        joint(side .. "Wrist", lowerArm, hand, CFrame.new(0, -0.35, 0), CFrame.new(0, 0.12, 0))

        local upperLeg = block(rig, side .. "UpperLeg", Vector3.new(0.6, 0.75, 0.6), OVERALLS, Enum.Material.Fabric)
        local lowerLeg = block(rig, side .. "LowerLeg", Vector3.new(0.55, 0.7, 0.55), OVERALLS, Enum.Material.Fabric)
        local foot = block(rig, side .. "Foot", Vector3.new(0.6, 0.2, 0.8), SHOES)
        joint(side .. "Hip", lower, upperLeg, CFrame.new(x * 0.34, -0.15, 0), CFrame.new(0, 0.375, 0))
        joint(side .. "Knee", upperLeg, lowerLeg, CFrame.new(0, -0.375, 0), CFrame.new(0, 0.35, 0))
        joint(side .. "Ankle", lowerLeg, foot, CFrame.new(0, -0.35, 0), CFrame.new(0, 0.1, 0.1))
    end

    local humanoid = Instance.new("Humanoid")
    humanoid.RigType = Enum.HumanoidRigType.R15
    -- Del piso al borde de abajo de la raíz: pierna + pie.
    humanoid.HipHeight = 1.15
    humanoid.Parent = rig
    Instance.new("Animator").Parent = humanoid

    rig.PrimaryPart = root
    return rig
end

-- Coloca cada pieza según sus articulaciones (el motor lo hace solo, pero así la
-- nena aparece armada aunque la física todavía no haya corrido).
local function layout(rig, rootCFrame)
    local root = rig:FindFirstChild("HumanoidRootPart")
    root.CFrame = rootCFrame
    local placed = {[root] = true}
    local motors = {}
    for _, descendant in ipairs(rig:GetDescendants()) do
        if descendant:IsA("Motor6D") then
            table.insert(motors, descendant)
        end
    end
    for _ = 1, #motors do
        local progress = false
        for _, motor in ipairs(motors) do
            if motor.Part0 and motor.Part1 and placed[motor.Part0] and not placed[motor.Part1] then
                motor.Part1.CFrame = motor.Part0.CFrame * motor.C0 * motor.C1:Inverse()
                placed[motor.Part1] = true
                progress = true
            end
        end
        if not progress then
            break
        end
    end
end

-- Pelo castaño con dos colitas, soldado a la cabeza.
local function addHair(rig)
    local head = rig:FindFirstChild("Head")
    if not head or not head:IsA("BasePart") then
        return
    end
    local size = head.Size
    local function lock(name, partSize, offset)
        local piece = Instance.new("Part")
        piece.Name = name
        piece.Size = partSize
        piece.Color = HAIR
        piece.Material = Enum.Material.SmoothPlastic
        piece.CanCollide = false
        piece.CanQuery = false
        piece.CanTouch = false
        piece.Massless = true
        piece.CastShadow = false
        piece.CFrame = head.CFrame * offset
        local shape = Instance.new("SpecialMesh")
        shape.MeshType = Enum.MeshType.Sphere
        shape.Parent = piece
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = head
        weld.Part1 = piece
        weld.Parent = piece
        piece.Parent = rig
    end
    lock("Hair", Vector3.new(size.X * 1.12, size.Y * 0.75, size.Z * 1.12), CFrame.new(0, size.Y * 0.22, size.Z * 0.06))
    for _, x in ipairs({-1, 1}) do
        lock("Pigtail", Vector3.new(0.45, 0.6, 0.45), CFrame.new(x * size.X * 0.6, size.Y * 0.05, size.Z * 0.2))
    end
end

local function prepare(rig)
    rig.Name = "Alma"
    local humanoid = rig:FindFirstChildOfClass("Humanoid")
    humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
    humanoid.BreakJointsOnDeath = false
    humanoid.UseJumpPower = false
    humanoid.JumpHeight = 3.5
    humanoid.WalkSpeed = 12
    if not humanoid:FindFirstChildOfClass("Animator") then
        Instance.new("Animator").Parent = humanoid
    end

    -- Los jugadores la atraviesan: no traba pasillos ni se la empuja contra la pared.
    for _, descendant in ipairs(rig:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CastShadow = false
        elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
            descendant:Destroy()
        end
    end

    local root = rig:FindFirstChild("HumanoidRootPart")
    local glow = Instance.new("PointLight")
    glow.Name = "AlmaGlow"
    glow.Color = WARM
    glow.Brightness = 0.6
    glow.Range = 9
    glow.Shadows = false
    glow.Parent = root

    local sparkles = Instance.new("ParticleEmitter")
    sparkles.Name = "AlmaSparkles"
    sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    sparkles.Color = ColorSequence.new(WARM, Color3.fromRGB(255, 240, 200))
    sparkles.LightEmission = 1
    sparkles.Size = NumberSequence.new(0.35, 0)
    sparkles.Lifetime = NumberRange.new(0.8, 1.6)
    sparkles.Speed = NumberRange.new(1.5, 4)
    sparkles.SpreadAngle = Vector2.new(180, 180)
    sparkles.Acceleration = Vector3.new(0, 2, 0)
    sparkles.Rate = 0
    sparkles.Parent = root
    return humanoid, root, glow, sparkles
end

function AlmaBuilder.CreateRig()
    local rig = fromHook()
    local source = "Hook"
    if not rig then
        rig = fromDescription()
        source = "Avatar"
    end
    if not rig then
        rig = AlmaBuilder.BuildFallbackRig()
        source = "Fallback"
    end
    rig:SetAttribute("Source", source)
    return rig
end

-- Comportamiento --------------------------------------------------------------------

local Alma = {}
Alma.__index = Alma

function Alma:Track(name, looped, priority)
    local tracks = self.Tracks
    if tracks[name] ~= nil then
        return tracks[name] or nil
    end
    local animator = self.Humanoid:FindFirstChildOfClass("Animator")
    local success, track = pcall(function()
        local animation = Instance.new("Animation")
        animation.Name = name
        animation.AnimationId = AlmaBuilder.Animations[name]
        local loaded = animator:LoadAnimation(animation)
        loaded.Looped = looped
        loaded.Priority = priority
        return loaded
    end)
    tracks[name] = success and track or false
    return success and track or nil
end

function Alma:Play(name, looped, priority, fade)
    local track = self:Track(name, looped, priority)
    if track then
        track:Play(fade or 0.25)
    end
    return track
end

function Alma:Stop(name, fade)
    local track = self.Tracks[name]
    if track then
        track:Stop(fade or 0.25)
    end
end

function Alma:SetState(state)
    self.State = state
    self.StateTime = 0
    self.Holder:SetAttribute("AlmaState", state)
end

local function livingPlayers()
    local result = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid and humanoid.Health > 0 then
            table.insert(result, {Player = player, Root = root, Character = character})
        end
    end
    return result
end

function Alma:CanSee(entry)
    local origin = self.Root.Position + Vector3.new(0, 1.5, 0)
    local direction = entry.Root.Position - origin
    if direction.Magnitude < 0.5 then
        return true
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {self.Holder, entry.Character}
    return workspace:Raycast(origin, direction, params) == nil
end

function Alma:Nearest()
    local best, bestDistance = nil, math.huge
    for _, entry in ipairs(livingPlayers()) do
        local distance = (entry.Root.Position - self.Root.Position).Magnitude
        if distance < bestDistance then
            best, bestDistance = entry, distance
        end
    end
    return best, bestDistance
end

-- ¡La encontraron! Salta, saluda, festeja y se ilumina.
function Alma:Found(entry)
    self.Holder:SetAttribute("Found", true)
    self.Holder:SetAttribute("FoundBy", entry.Player.Name)
    self:SetState("Happy")
    self.Jumps = 0

    local flat = (entry.Root.Position - self.Root.Position) * Vector3.new(1, 0, 1)
    if flat.Magnitude > 0.1 then
        self.Root.CFrame = CFrame.lookAt(self.Root.Position, self.Root.Position + flat)
    end

    self:Stop("LookAround")
    self:Play("Wave", false, Enum.AnimationPriority.Action, 0.15)
    pcall(function()
        self.Sparkles:Emit(30)
    end)
    self.Sparkles.Rate = 8
    TweenService:Create(self.Glow, TweenInfo.new(1.2, Enum.EasingStyle.Sine), {Brightness = 1.6, Range = 16}):Play()
end

function Alma:UpdateHappy()
    local time = self.StateTime
    -- Saltitos de alegría.
    local jumpTimes = {0, 0.9, 2.6}
    local nextJump = jumpTimes[self.Jumps + 1]
    if nextJump and time >= nextJump then
        self.Jumps += 1
        self.Humanoid.Jump = true
    end
    if time >= 2.4 and not self.Cheered then
        self.Cheered = true
        self:Stop("Wave", 0.2)
        self:Play("Cheer", false, Enum.AnimationPriority.Action, 0.2)
    end
    if time >= HAPPY_TIME then
        self:Stop("Cheer", 0.4)
        self.Sparkles.Rate = 1.5
        self:SetState("Follow")
    end
end

-- Aparece detrás del jugador en lugar de perderse o quedarse trabada.
function Alma:JoinBehind(entry)
    local behind = entry.Root.CFrame * CFrame.new(0, 0, 4)
    self.Rig:PivotTo(CFrame.new(behind.Position) * (self.Root.CFrame - self.Root.Position))
    self.StallFrom = nil
    self.StallTime = 0
end

-- Cuenta el tiempo que pasa lejos del jugador sin avanzar. Devuelve true si ya
-- está trabada.
function Alma:Stalled(distance, deltaTime)
    local position = self.Root.Position
    if distance <= STALL_RANGE then
        self.StallFrom = nil
        self.StallTime = 0
        return false
    end
    local from = self.StallFrom
    if not from or ((position - from) * Vector3.new(1, 0, 1)).Magnitude >= STALL_PROGRESS then
        self.StallFrom = position
        self.StallTime = 0
        return false
    end
    self.StallTime = (self.StallTime or 0) + deltaTime
    return self.StallTime >= STALL_TIME
end

-- Las puertas comunes cerradas se abren a su paso, como con las criaturas. Se pide
-- por el bus de eventos: DoorService usa FeatureBuilder, que arma a Alma, y
-- requerirlo desde acá formaría un ciclo.
local function openDoorsNear(position)
    EventBus.Emit("OpenDoorsNear", position)
end

-- Camina hacia el jugador más cercano por el laberinto, sin pegarse demasiado.
function Alma:UpdateFollow(deltaTime)
    local entry, distance = self:Nearest()
    local humanoid = self.Humanoid
    if not entry then
        humanoid:MoveTo(self.Root.Position)
        return
    end
    self.Holder:SetAttribute("Following", entry.Player.Name)

    local target = entry.Root.Position
    if distance > LOST_DISTANCE or self:Stalled(distance, deltaTime) then
        -- Quedó muy atrás o trabada: aparece detrás del jugador.
        self:JoinBehind(entry)
        return
    end

    if distance <= FOLLOW_DISTANCE then
        humanoid:MoveTo(self.Root.Position)
        self.Moving = false
    else
        openDoorsNear(self.Root.Position)
        humanoid.WalkSpeed = distance > CATCH_UP_DISTANCE and 17 or 12
        local goal = target
        local nav = GameState.Nav
        if nav then
            local points = nav:Waypoints(self.Root.Position, target, self.Root.Position.Y)
            if points then
                for _, point in ipairs(points) do
                    if (point - self.Root.Position).Magnitude > 2 then
                        goal = point
                        break
                    end
                end
            end
        end
        humanoid:MoveTo(Vector3.new(goal.X, self.Root.Position.Y, goal.Z))
        self.Moving = true
    end

    -- Camina o corre según lo que de verdad avanzó.
    local position = self.Root.Position
    local speed = ((position - (self.LastPosition or position)) * Vector3.new(1, 0, 1)).Magnitude / deltaTime
    self.LastPosition = position
    local walking = self.Moving and speed > 0.5
    if walking and not self.Walking then
        self:Play("Walk", true, Enum.AnimationPriority.Movement, 0.2)
    elseif not walking and self.Walking then
        self:Stop("Walk", 0.3)
    end
    self.Walking = walking
    local walk = self.Tracks.Walk
    if walking and walk then
        walk:AdjustSpeed(math.clamp(speed / 10, 0.6, 1.8))
    end
end

function Alma:UpdateIdle()
    -- De vez en cuando mira alrededor, como esperando a alguien.
    if self.StateTime >= self.NextLook then
        self.NextLook = self.StateTime + 6 + math.random() * 5
        self:Play("LookAround", false, Enum.AnimationPriority.Idle, 0.4)
    end

    for _, entry in ipairs(livingPlayers()) do
        if (entry.Root.Position - self.Root.Position).Magnitude <= FIND_RANGE and self:CanSee(entry) then
            self:Found(entry)
            return
        end
    end
end

function Alma:Update(deltaTime)
    self.StateTime += deltaTime
    if self.State == "Idle" then
        self:UpdateIdle()
    elseif self.State == "Happy" then
        self:UpdateHappy()
    elseif self.State == "Follow" then
        self:UpdateFollow(deltaTime)
    end
end

local function attach(holder, host, rig, cframe)
    if not holder.Parent then
        rig:Destroy()
        return nil
    end

    local humanoid, root, glow, sparkles = prepare(rig)
    local height = humanoid.HipHeight + root.Size.Y / 2
    layout(rig, cframe * CFrame.new(0, height, 0))
    -- El pelo se suelda con la cabeza ya en su lugar.
    addHair(rig)
    rig.Parent = holder

    -- El cartel para tomarle la mano va con ella.
    host.CFrame = root.CFrame
    host.Anchored = false
    host.Massless = true
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = root
    weld.Part1 = host
    weld.Parent = host

    pcall(function()
        root:SetNetworkOwner(nil)
    end)

    local alma = setmetatable({
        Holder = holder,
        Rig = rig,
        Humanoid = humanoid,
        Root = root,
        Glow = glow,
        Sparkles = sparkles,
        Tracks = {},
        State = "Idle",
        StateTime = 0,
        NextLook = 3,
        Jumps = 0,
    }, Alma)
    alma:SetState("Idle")
    alma:Play("Idle", true, Enum.AnimationPriority.Idle, 0)
    holder:SetAttribute("Found", false)
    return alma
end

-- Arma a Alma en su lugar. Devuelve el modelo y la pieza que lleva el cartel.
function AlmaBuilder.Build(parent, feature, cframe)
    local holder = Instance.new("Model")
    holder.Name = feature.Id

    -- Ancla invisible: existe desde el principio para el cartel y el objetivo;
    -- cuando aparece el cuerpo se suelda a él y la acompaña.
    local host = Instance.new("Part")
    host.Name = "AlmaAnchor"
    host.Size = Vector3.new(2, 4, 2)
    host.CFrame = cframe * CFrame.new(0, 2, 0)
    host.Transparency = 1
    host.Anchored = true
    host.CanCollide = false
    host.CanTouch = false
    host.CanQuery = false
    host.Parent = holder
    holder.PrimaryPart = host
    holder:SetAttribute("AlmaState", "Loading")
    holder.Parent = parent

    -- El avatar se descarga: se arma aparte para no frenar la carga del mapa.
    task.spawn(function()
        local alma = attach(holder, host, AlmaBuilder.CreateRig(), cframe)
        if not alma then
            return
        end
        local elapsed = 0
        local connection
        connection = RunService.Heartbeat:Connect(function(deltaTime)
            if not holder.Parent then
                connection:Disconnect()
                return
            end
            elapsed += deltaTime
            if elapsed >= UPDATE_INTERVAL then
                local step = elapsed
                elapsed = 0
                local success, err = pcall(alma.Update, alma, step)
                if not success then
                    connection:Disconnect()
                    warn("[NOCTURNA] Alma dejó de responder:", err)
                end
            end
        end)
    end)

    return holder, host
end

return AlmaBuilder
