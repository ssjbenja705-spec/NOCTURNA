-- Persecución final en el cliente: transición, la criatura detrás, la acción
-- contextual (Espacio salta y embiste, C se agacha, botón en el celular), la cámara
-- que transmite velocidad y miedo (sin quitar el control), las poses de salto,
-- deslizamiento y tropezón de cada jugador y la partitura. El servidor decide todo
-- lo que importa: acá sólo se dibuja, suena y se pide.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local FinalChaseConfig = require(Shared.Config.FinalChaseConfig)
local ChasePlan = require(Shared.Logic.ChasePlan)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local FirstPerson = require(script.Parent.Parent.Camera.FirstPerson)
local MovementInput = require(script.Parent.Parent.Movement.MovementInput)
local Theme = require(script.Parent.Parent.UI.Theme)
local ChaseCreature = require(script.Parent.ChaseCreature)
local ChaseScore = require(script.Parent.ChaseScore)

local player = Players.LocalPlayer
local CONFIG = FinalChaseConfig
local ARENA = CONFIG.Arena
local OBSTACLES = CONFIG.Obstacles
local TIMING = CONFIG.Timing
local Colors = Theme.Colors

local UNDO_BIND = "NocturnaChaseUndo"
local CAMERA_BIND = "NocturnaChaseCamera"
local ACTION_COOLDOWN = 0.25
local PROMPT_RANGE = 26
local VAULT_TIME = 0.6
local SLIDE_TIME = 0.75
local STUMBLE_TIME = 0.75
local HOP_TIME = 0.3
local LIGHT_TAG = "NocturnaChaseLight"

local FinalChaseClient = {}
local view = nil
local ui: {[string]: any} = {}
local creature = nil
local poses = {}
local highlight = nil
local applied = nil
local lastAction = -math.huge
local lightClock = 0
local roarClock = 0
local fx = {
    Move = nil,
    MoveAt = 0,
    LookBack = 0,
    LookBackTarget = 0,
    RevealUntil = 0,
    Fov = 0,
}

-- Utilidades -----------------------------------------------------------------------

local function point(s, lateral, height)
    local origin = ARENA.Origin
    return Vector3.new(origin.X + (lateral or 0), height or 0, origin.Z + s)
end

local function rootPart()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
        return nil
    end
    return root
end

-- Posición del jugador en la galería: s, lateral y si está adentro.
local function localPosition()
    local root = rootPart()
    if not root then
        return nil
    end
    local origin = ARENA.Origin
    local s = root.Position.Z - origin.Z
    local lateral = root.Position.X - origin.X
    local inside = math.abs(lateral) <= ARENA.Width / 2 + 4 and s >= ARENA.BackS - 10 and s <= ARENA.Length + 10
    if not inside then
        return nil
    end
    return s, lateral
end

local function setControls(enabled)
    local scripts = player:FindFirstChild("PlayerScripts")
    local module = scripts and scripts:FindFirstChild("PlayerModule")
    if not module then
        return
    end
    pcall(function()
        local controls = require(module):GetControls()
        if enabled then
            controls:Enable()
        else
            controls:Disable()
        end
    end)
end

local function obstacleModel(id)
    local folder = workspace:FindFirstChild("NOCTURNA_CHASE")
    if not folder then
        return nil
    end
    for _, descendant in ipairs(folder:GetDescendants()) do
        if descendant:IsA("Model") and descendant:GetAttribute("ChaseObstacle") == id then
            return descendant
        end
    end
    return nil
end

local function obstacleById(id)
    for _, entry in ipairs(view and view.Obstacles or {}) do
        if entry.Id == id then
            return entry
        end
    end
    return nil
end

local function burst(position, count, color)
    local holder = Instance.new("Attachment")
    holder.WorldPosition = position
    holder.Parent = workspace.Terrain
    local emitter = Instance.new("ParticleEmitter")
    emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
    emitter.Rate = 0
    emitter.Lifetime = NumberRange.new(1.2, 2.4)
    emitter.Speed = NumberRange.new(8, 18)
    emitter.SpreadAngle = Vector2.new(80, 80)
    emitter.Acceleration = Vector3.new(0, -6, 0)
    emitter.Size = NumberSequence.new(1.5, 4)
    emitter.Transparency = NumberSequence.new(0.4, 1)
    emitter.Color = ColorSequence.new(color or Color3.fromRGB(130, 120, 110))
    emitter.Parent = holder
    emitter:Emit(count or 30)
    task.delay(3, function()
        holder:Destroy()
    end)
end

local function shakeFrom(position, strength, range)
    local root = rootPart()
    if not root then
        return
    end
    local power = 1 - math.clamp((root.Position - position).Magnitude / range, 0, 1)
    if power > 0 then
        FirstPerson.Shake(strength * power, 0.5)
    end
end

-- Interfaz -------------------------------------------------------------------------

local function fade(alpha, seconds)
    if not ui.Curtain then
        return
    end
    ui.Curtain.Visible = true
    Theme.Tween(ui.Curtain, seconds or 0.6, {BackgroundTransparency = 1 - alpha})
    if alpha <= 0 then
        task.delay(seconds or 0.6, function()
            if ui.Curtain and ui.Curtain.BackgroundTransparency >= 0.99 then
                ui.Curtain.Visible = false
            end
        end)
    end
end

local function caption(text, seconds)
    if not ui.Caption then
        return
    end
    ui.Caption.Text = text or ""
    ui.Caption.TextTransparency = 0
    local shownText = ui.Caption.Text
    task.delay(seconds or 2.4, function()
        if ui.Caption and ui.Caption.Text == shownText then
            Theme.Tween(ui.Caption, 0.6, {TextTransparency = 1})
        end
    end)
end

local function shout(text, seconds)
    if not ui.Shout then
        return
    end
    ui.Shout.Text = text
    ui.Shout.Visible = true
    local shownText = text
    task.delay(seconds or 1.4, function()
        if ui.Shout and ui.Shout.Text == shownText then
            ui.Shout.Visible = false
        end
    end)
end

local function buildUi()
    local overlay = Theme.Screen("NocturnaChase", 46, true)
    ui.Curtain = Theme.New("Frame", {
        Name = "Curtain",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
    }, overlay)
    ui.Caption = Theme.Label(overlay, {
        Name = "Caption",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.42),
        Size = UDim2.new(0.8, 0, 0, 90),
        TextSize = 22,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTransparency = 1,
    })
    ui.Shout = Theme.Title(overlay, {
        Name = "Shout",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.3),
        Size = UDim2.new(0.9, 0, 0, 110),
        TextSize = 72,
        Text = "",
        Visible = false,
    })
    -- Borde rojo que late cuando la criatura está encima.
    ui.Danger = Theme.New("Frame", {
        Name = "Danger",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(120, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, overlay)
    Theme.New("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.25, 1),
            NumberSequenceKeypoint.new(0.75, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
    }, ui.Danger)

    local controls = Theme.Screen("NocturnaChaseControls", 7)
    ui.Hint = Theme.Label(controls, {
        Name = "Hint",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -96),
        Size = UDim2.fromOffset(420, 34),
        TextSize = 24,
        Font = Theme.Fonts.Title,
        TextColor3 = Colors.Text,
        TextStrokeTransparency = 0.4,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        Visible = false,
    })
    if Theme.IsTouch then
        ui.Action = Theme.Button(controls, "SALTAR", {
            Name = "ChaseAction",
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -112, 1, -116),
            Size = UDim2.fromOffset(96, 96),
            BackgroundColor3 = Colors.ButtonActive,
            BackgroundTransparency = 0.15,
            TextSize = 14,
            TextWrapped = true,
            Visible = false,
        })
        Theme.Corner(ui.Action, 48)
        ui.Action.Activated:Connect(function()
            FinalChaseClient.PressContext()
        end)
    end
end

-- Poses de cada jugador (las ven todos) ---------------------------------------------

local POSE_TIME = {Vault = VAULT_TIME, Slide = SLIDE_TIME, Stumble = STUMBLE_TIME, Door = 0.5}

local function rootJoint(character)
    local lower = character:FindFirstChild("LowerTorso")
    local joint = lower and lower:FindFirstChild("Root")
    if joint and joint:IsA("Motor6D") then
        return joint
    end
    local root = character:FindFirstChild("HumanoidRootPart")
    joint = root and root:FindFirstChild("RootJoint")
    if joint and joint:IsA("Motor6D") then
        return joint
    end
    return nil
end

local function restorePose(character)
    local pose = poses[character]
    if pose then
        if pose.Joint.Parent then
            pose.Joint.C0 = pose.Base
        end
        poses[character] = nil
    end
end

local function startPose(character, kind)
    if not character or not POSE_TIME[kind] then
        return
    end
    local joint = rootJoint(character)
    if not joint then
        return
    end
    local base = joint.C0
    if poses[character] then
        base = poses[character].Base
        joint.C0 = base
    end
    poses[character] = {Kind = kind, Joint = joint, Base = base, Started = os.clock()}
end

-- Desplazamiento del cuerpo en el espacio de la raíz (vale para R15 y R6).
local function poseOffset(kind, alpha)
    local wave = math.sin(math.pi * alpha)
    if kind == "Vault" then
        return CFrame.new(0, 1.8 * wave, -0.6 * wave) * CFrame.Angles(-0.55 * wave, 0, 0.25 * wave)
    elseif kind == "Slide" then
        local hold = math.min(1, alpha / 0.15, (1 - alpha) / 0.25)
        return CFrame.new(0, -1.7 * hold, 0) * CFrame.Angles(1.15 * hold, 0, 0)
    elseif kind == "Stumble" then
        local hit = alpha < 0.25 and alpha / 0.25 or 1 - (alpha - 0.25) / 0.75
        return CFrame.new(0, -0.9 * hit, -0.4 * hit) * CFrame.Angles(-0.85 * hit, 0, 0.3 * hit)
    elseif kind == "Door" then
        return CFrame.Angles(-0.3 * wave, 0.4 * wave, 0)
    end
    return CFrame.identity
end

local function updatePoses()
    local now = os.clock()
    for character, pose in pairs(poses) do
        local alpha = (now - pose.Started) / POSE_TIME[pose.Kind]
        if alpha >= 1 or not pose.Joint.Parent or not character.Parent then
            restorePose(character)
        else
            pose.Joint.C0 = poseOffset(pose.Kind, alpha) * pose.Base
        end
    end
end

local function characterOf(userId)
    for _, other in ipairs(Players:GetPlayers()) do
        if other.UserId == userId then
            return other.Character, other
        end
    end
    return nil
end

-- Cámara: empuje del campo visual, salto, deslizamiento, tropezón y mirar atrás ------

local function startMove(kind)
    fx.Move = kind
    fx.MoveAt = os.clock()
    if kind == "Vault" then
        ChaseScore.Hit("Vault")
        task.delay(VAULT_TIME * 0.85, function()
            ChaseScore.Hit("Land")
            FirstPerson.Shake(1.2, 0.25)
        end)
    elseif kind == "Slide" then
        ChaseScore.Hit("Slide")
    elseif kind == "Stumble" then
        ChaseScore.Hit("Stumble")
        ChaseScore.Hit("Land", nil, 0.8)
        FirstPerson.Shake(4, 0.6)
    end
end

local function moveOffset()
    local kind = fx.Move
    if not kind then
        return 0, 0, 0
    end
    local duration = kind == "Vault" and VAULT_TIME or kind == "Slide" and SLIDE_TIME or kind == "Stumble" and STUMBLE_TIME or HOP_TIME
    local alpha = (os.clock() - fx.MoveAt) / duration
    if alpha >= 1 then
        fx.Move = nil
        return 0, 0, 0
    end
    local wave = math.sin(math.pi * alpha)
    if kind == "Vault" then
        return 2.2 * wave, -0.16 * wave, 0.04 * wave
    elseif kind == "Slide" then
        local hold = math.min(1, alpha / 0.15, (1 - alpha) / 0.25)
        return -2.4 * hold, 0.1 * hold, 0.12 * hold
    elseif kind == "Stumble" then
        local hit = alpha < 0.2 and alpha / 0.2 or 1 - (alpha - 0.2) / 0.8
        return -1.1 * hit, -0.5 * hit, 0.22 * hit
    elseif kind == "Hop" then
        return 0.6 * wave, 0, 0
    elseif kind == "Duck" then
        return -1 * wave, 0, 0
    end
    return 0, 0, 0
end

local function intensity()
    if not view or not view.Display then
        return 0
    end
    local s = localPosition()
    local reference = s or view.Rear
    if not reference then
        return 0
    end
    local gap = reference - view.Display
    return math.clamp(1 - (gap - FinalChaseConfig.Creature.CatchDistance) / 30, 0, 1)
end

local function undoCamera()
    local camera = workspace.CurrentCamera
    if applied and camera then
        camera.CFrame *= applied.Offset:Inverse()
        camera.FieldOfView -= applied.Fov
    end
    applied = nil
end

local function applyCamera(deltaTime)
    local camera = workspace.CurrentCamera
    if not view or not camera or camera.CameraType == Enum.CameraType.Scriptable then
        return
    end
    if not localPosition() then
        return
    end

    local revealing = os.clock() < fx.RevealUntil
    local target = revealing and 1 or fx.LookBackTarget
    fx.LookBack += (target - fx.LookBack) * math.min(1, deltaTime * (revealing and 3 or 9))

    local lift, pitch, roll = moveOffset()
    local yaw = math.pi * 0.94 * fx.LookBack
    local offset = CFrame.new(0, lift, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch + 0.12 * fx.LookBack, 0, roll)

    local running = view.Phase == "Run"
    local fovTarget = running and (4 + 9 * intensity()) or 0
    fx.Fov += (fovTarget - fx.Fov) * math.min(1, deltaTime * 3)

    camera.CFrame *= offset
    camera.FieldOfView += fx.Fov
    applied = {Offset = offset, Fov = fx.Fov}
end

-- Acción contextual ------------------------------------------------------------------

local function nextObstacle()
    local s = localPosition()
    if not view or not s then
        return nil, nil
    end
    return ChasePlan.NextObstacle(view.Obstacles, s, view.Resolved, view.Doors), s
end

local function inWindow(entry, s)
    if entry.Kind == "Door" then
        return s >= entry.S - OBSTACLES.DoorReach and s <= entry.S + 1
    end
    return s >= entry.S - OBSTACLES.ActionReach and s <= entry.S + OBSTACLES.ActionLate
end

function FinalChaseClient.Action(action)
    if not view or view.Phase ~= "Run" then
        return false
    end
    local now = os.clock()
    if now - lastAction < ACTION_COOLDOWN then
        return true
    end
    lastAction = now

    -- Predicción: el gesto arranca ya; si el servidor no lo acepta, llega el tropezón.
    local entry, s = nextObstacle()
    if entry and s and CONFIG.Actions[entry.Kind] == action and inWindow(entry, s) then
        if entry.Kind ~= "Door" then
            view.Resolved[entry.Id] = true
            startMove(entry.Kind)
        else
            startMove("Hop")
        end
    else
        startMove(action == "Duck" and "Duck" or "Hop")
    end
    Remotes.FireServer("ChaseAction", action)
    return true
end

-- Botón táctil: hace lo que pide el obstáculo que viene.
function FinalChaseClient.PressContext()
    local entry = nextObstacle()
    local action = entry and CONFIG.Actions[entry.Kind] or "Jump"
    return FinalChaseClient.Action(action)
end

local JUMP_KEYS = {[Enum.KeyCode.Space] = true, [Enum.KeyCode.ButtonA] = true}
local DUCK_KEYS = {[Enum.KeyCode.C] = true, [Enum.KeyCode.LeftControl] = true, [Enum.KeyCode.ButtonB] = true}

-- Manejador de MovementInput: C no pone en sigilo durante la persecución. Espacio
-- lo atiende onJumpInput, porque Roblox marca el salto como "procesado".
local function onActionKey(key)
    if not view or not localPosition() then
        return false
    end
    if JUMP_KEYS[key] then
        return true
    elseif DUCK_KEYS[key] then
        -- Durante la persecución C no pone en sigilo: se agacha para pasar.
        FinalChaseClient.Action("Duck")
        return true
    end
    return false
end

local function setHighlight(entry)
    local model = entry and entry.Kind ~= "Debris" and obstacleModel(entry.Id) or nil
    if not model then
        if highlight then
            highlight.Adornee = nil
        end
        return
    end
    if not highlight then
        highlight = Instance.new("Highlight")
        highlight.Name = "NocturnaChaseHighlight"
        highlight.FillTransparency = 1
        highlight.OutlineColor = Colors.Accent
        highlight.OutlineTransparency = 0.25
        highlight.DepthMode = Enum.HighlightDepthMode.Occluded
        highlight.Parent = workspace.Terrain
    end
    if highlight.Adornee ~= model then
        highlight.Adornee = model
    end
end

local function updatePrompt()
    local entry, s = nextObstacle()
    local show = view and view.Phase == "Run" and entry ~= nil and s ~= nil and entry.S - s <= PROMPT_RANGE
    if not show then
        if ui.Hint then
            ui.Hint.Visible = false
        end
        if ui.Action then
            ui.Action.Visible = false
        end
        setHighlight(nil)
        return
    end
    local ready = entry.Kind == "Debris" or inWindow(entry, s)
    local prompt = CONFIG.Prompts[entry.Kind]
    if ui.Hint and not Theme.IsTouch then
        ui.Hint.Visible = true
        ui.Hint.Text = prompt.Key
        ui.Hint.TextColor3 = ready and Colors.Danger or Colors.Text
    end
    if ui.Action then
        ui.Action.Visible = entry.Kind ~= "Debris"
        ui.Action.Text = prompt.Touch
        ui.Action.BackgroundColor3 = ready and Colors.Danger or Colors.ButtonActive
    end
    if ui.Hint and Theme.IsTouch and entry.Kind == "Debris" then
        ui.Hint.Visible = true
        ui.Hint.Text = prompt.Touch
    elseif ui.Hint and Theme.IsTouch then
        ui.Hint.Visible = false
    end
    setHighlight(entry)
end

-- Escenografía local: derrumbes, compuertas y luces que parpadean ---------------------

local function animateDebris(data)
    local entry = obstacleById(data.Id)
    if not entry then
        return
    end
    local model = obstacleModel(data.Id)
    local slab = model and model.PrimaryPart
    local center = model and model:GetAttribute("Center") or 0
    local span = model and model:GetAttribute("Span") or ARENA.Width * 0.5
    local warn = tonumber(data.Warn) or OBSTACLES.DebrisWarn

    -- Marca en el piso donde va a caer.
    local marker = Instance.new("Part")
    marker.Name = "DebrisWarning"
    marker.Anchored = true
    marker.CanCollide = false
    marker.CanQuery = false
    marker.CanTouch = false
    marker.Material = Enum.Material.Neon
    marker.Color = Color3.fromRGB(200, 30, 20)
    marker.Transparency = 0.7
    marker.Size = Vector3.new(span, 0.1, 7)
    marker.CFrame = CFrame.new(point(entry.S, center, 0.08))
    marker.Parent = workspace.Terrain

    ChaseScore.Hit("DebrisWarn", point(entry.S, center, ARENA.Height - 2))
    burst(point(entry.S, center, ARENA.Height - 2), 12)
    local hanging = slab and slab.CFrame
    local landed = CFrame.new(point(entry.S, center, 0.9)) * CFrame.Angles(0.08, 0.2, -0.06)
    local started = os.clock()
    local connection
    connection = RunService.RenderStepped:Connect(function()
        local alpha = (os.clock() - started) / warn
        marker.Transparency = 0.45 + 0.35 * math.abs(math.sin(alpha * 12))
        if slab and slab.Parent and hanging then
            if alpha < 0.6 then
                local shake = 0.04 * math.sin(alpha * 60)
                slab.CFrame = hanging * CFrame.Angles(shake, 0, shake)
            else
                local fall = math.clamp((alpha - 0.6) / 0.4, 0, 1)
                slab.CFrame = hanging:Lerp(landed, fall * fall)
            end
        end
        if alpha >= 1 then
            connection:Disconnect()
            marker:Destroy()
        end
    end)
end

local function debrisLanded(data)
    local entry = obstacleById(data.Id)
    if not entry then
        return
    end
    local model = obstacleModel(data.Id)
    local center = model and model:GetAttribute("Center") or 0
    local where = point(entry.S, center, 1)
    ChaseScore.Hit("DebrisImpact", where)
    burst(where, 40)
    shakeFrom(where, 7, 60)
end

local function doorBurst(data)
    local entry = obstacleById(data.Id)
    if not entry then
        return
    end
    view.Doors[data.Id] = true
    local where = point(entry.S, 0, 5)
    ChaseScore.Hit("DoorBurst", where)
    burst(where, 36, Color3.fromRGB(110, 80, 60))
    shakeFrom(where, 5, 50)
    local character = characterOf(data.UserId)
    startPose(character, "Door")
end

local function flickerLights(deltaTime)
    lightClock += deltaTime
    if lightClock < 0.08 then
        return
    end
    lightClock = 0
    for _, fixture in ipairs(CollectionService:GetTagged(LIGHT_TAG)) do
        if fixture:GetAttribute("Flicker") == true then
            local light = fixture:FindFirstChildOfClass("PointLight")
            if light then
                light.Enabled = math.random() > 0.18
            end
        end
    end
end

-- Estado ---------------------------------------------------------------------------

local function ensureCreature()
    if creature then
        return creature
    end
    creature = ChaseCreature.new(workspace, ARENA.Origin, FinalChaseConfig.Creature.Height / 17)
    creature.OnStep = function(position)
        ChaseScore.Hit("CreatureStep", position)
        shakeFrom(position, 2.2, 70)
    end
    return creature
end

local function cleanup()
    if not view then
        return
    end
    view = nil
    for character in pairs(poses) do
        restorePose(character)
    end
    if creature then
        creature:Destroy()
        creature = nil
    end
    if highlight then
        highlight:Destroy()
        highlight = nil
    end
    ChaseScore.Stop()
    setControls(true)
    fx.LookBackTarget = 0
    fx.RevealUntil = 0
    fx.Move = nil
    if ui.Hint then
        ui.Hint.Visible = false
    end
    if ui.Action then
        ui.Action.Visible = false
    end
    if ui.Shout then
        ui.Shout.Visible = false
    end
    if ui.Danger then
        ui.Danger.BackgroundTransparency = 1
    end
end

local EVENTS = {}

function EVENTS.Intro(data)
    setControls(false)
    fade(1, tonumber(data.Fade) or TIMING.FadeOut)
    local lines = typeof(data.Lines) == "table" and data.Lines or {}
    local total = (tonumber(data.Fade) or TIMING.FadeOut) + TIMING.Arrive
    local each = #lines > 0 and total / #lines or total
    task.spawn(function()
        for _, line in ipairs(lines) do
            if typeof(line) == "string" then
                caption(line, each - 0.3)
            end
            task.wait(each)
        end
    end)
end

function EVENTS.Start(data)
    local previous = view
    if previous then
        for character in pairs(poses) do
            restorePose(character)
        end
    end
    local obstacles = {}
    for _, entry in ipairs(typeof(data.Obstacles) == "table" and data.Obstacles or {}) do
        if typeof(entry) == "table" and tonumber(entry.S) then
            table.insert(obstacles, {Id = entry.Id, Kind = entry.Kind, S = entry.S, Side = entry.Side})
        end
    end
    local creatureData = typeof(data.Creature) == "table" and data.Creature or {}
    view = {
        Phase = data.Phase == "Run" and "Run" or "Intro",
        Obstacles = obstacles,
        Resolved = {},
        Doors = typeof(data.Doors) == "table" and table.clone(data.Doors) or {},
        Target = tonumber(creatureData.S) or (ARENA.StartS - FinalChaseConfig.Creature.StartGap),
        Speed = tonumber(creatureData.Speed) or 0,
        ReceivedAt = os.clock(),
        Display = nil,
        Rear = ARENA.StartS,
    }
    ensureCreature():SetVisible(view.Phase == "Run")
    if view.Phase == "Run" then
        view.Display = view.Target
        setControls(true)
        fade(0, 0.6)
    else
        setControls(false)
    end
    ChaseScore.Start()
end

function EVENTS.Reveal(data)
    if not view then
        return
    end
    fade(0, 0.5)
    -- Irrumpe desde la pared del fondo y se lanza hasta su lugar.
    view.Display = ARENA.BackS + 6
    view.Target = tonumber(data.S) or view.Target
    local monster = ensureCreature()
    monster:SetVisible(true)
    monster:StartRoar(1.8)
    burst(point(ARENA.BackS + 4, 0, 8), 60)
    ChaseScore.Hit("CreatureRoar", point(ARENA.BackS + 6, 0, 8))
    ChaseScore.Hit("Stinger")
    FirstPerson.Shake(5, 1.6)
    fx.RevealUntil = os.clock() + TIMING.Reveal - 0.3
end

function EVENTS.Countdown()
    shout("¡CORRÉ!", 1.4)
end

function EVENTS.Run()
    if not view then
        return
    end
    view.Phase = "Run"
    fx.RevealUntil = 0
    setControls(true)
    if ui.Curtain and ui.Curtain.Visible then
        fade(0, 0.4)
    end
end

function EVENTS.Tick(data)
    if not view then
        return
    end
    view.Target = tonumber(data.S) or view.Target
    view.Speed = tonumber(data.Speed) or view.Speed
    view.Rear = tonumber(data.Rear) or view.Rear
    view.ReceivedAt = os.clock()
    view.Recoil = data.Recoil == true
end

function EVENTS.Act(data)
    if not view then
        return
    end
    local character, owner = characterOf(data.UserId)
    startPose(character, data.Kind)
    if owner == player then
        if data.Kind == "Stumble" then
            startMove("Stumble")
        elseif data.Obstacle and not view.Resolved[data.Obstacle] then
            view.Resolved[data.Obstacle] = true
            startMove(data.Kind)
        end
    end
end

function EVENTS.Door(data)
    if view then
        doorBurst(data)
    end
end

function EVENTS.Debris(data)
    if view then
        task.spawn(animateDebris, data)
    end
end

function EVENTS.DebrisLanded(data)
    if view then
        debrisLanded(data)
    end
end

function EVENTS.Catch(data)
    if not view then
        return
    end
    local monster = ensureCreature()
    monster:StartRoar(1.2)
    monster:StartLunge()
    ChaseScore.Hit("CreatureRoar", monster:Position(view.Display or view.Target))
    local _, owner = characterOf(data.UserId)
    if owner == player then
        FirstPerson.Shake(7, 0.8)
        ChaseScore.Hit("Stinger")
    end
end

function EVENTS.Safe(data)
    local _, owner = characterOf(data.UserId)
    if owner == player then
        caption("Pasaste la compuerta. ¡Vamos, que falta poco!", 2.5)
        if ui.Hint then
            ui.Hint.Visible = false
        end
    end
end

function EVENTS.Finish(data)
    ChaseScore.Hit("Slam")
    FirstPerson.Shake(6, 1)
    if creature then
        creature:StartRoar(2)
    end
    fade(1, tonumber(data.Fade) or TIMING.FinishFade)
end

function EVENTS.Arrive(data)
    cleanup()
    fade(0, 1.2)
    if typeof(data.Text) == "string" then
        caption(data.Text, 4)
    end
end

function EVENTS.Stop()
    cleanup()
    if ui.Curtain and ui.Curtain.Visible then
        fade(0, 0.6)
    end
end

function FinalChaseClient.IsActive()
    return view ~= nil
end

function FinalChaseClient.View()
    return view
end

local function update(deltaTime)
    updatePoses()
    if not view then
        return
    end

    -- La criatura sigue al servidor sin saltos: se predice con su velocidad y se
    -- acerca al valor real con un límite (si el último cae, corre, no aparece).
    local predicted = view.Target + view.Speed * math.min(os.clock() - view.ReceivedAt, 0.4)
    if view.Display == nil then
        view.Display = predicted
    end
    local limit = math.max(view.Speed, 10) * 2.5 * deltaTime
    view.Display += math.clamp(predicted - view.Display, -limit, limit)
    if creature then
        creature:Update(view.Display, view.Recoil and 2 or view.Speed, deltaTime)
    end

    -- Lo que ya quedó atrás no se vuelve a pedir.
    local s = localPosition()
    if s then
        for _, entry in ipairs(view.Obstacles) do
            if entry.S < s - 2 then
                view.Resolved[entry.Id] = true
            end
        end
    end

    local level = view.Phase == "Run" and intensity() or 0.15
    ChaseScore.SetIntensity(level)
    ChaseScore.Update(deltaTime)
    if ui.Danger then
        local pulse = 0.5 + 0.5 * math.sin(os.clock() * (4 + level * 8))
        ui.Danger.BackgroundTransparency = 1 - math.clamp((level - 0.45) * 1.2, 0, 0.6) * pulse
    end

    roarClock += deltaTime
    if creature and view.Phase == "Run" and level > 0.5 and roarClock > 7 then
        roarClock = 0
        creature:StartRoar(1)
        ChaseScore.Hit("CreatureRoar", creature:Position(view.Display), 1, 0.7)
    end

    updatePrompt()
    flickerLights(deltaTime)
end

function FinalChaseClient.Start()
    buildUi()

    Remotes.OnClient("ChaseState", function(data)
        if typeof(data) ~= "table" then
            return
        end
        local handler = EVENTS[data.Event]
        if handler then
            handler(data)
        end
    end)

    MovementInput.SetActionHandler(onActionKey)

    UserInputService.InputBegan:Connect(function(input, processed)
        -- El salto de Roblox (Espacio, A del mando) llega como procesado: se acepta
        -- igual, salvo que el jugador esté escribiendo.
        if JUMP_KEYS[input.KeyCode] and view and localPosition() then
            local ok, box = pcall(function()
                return UserInputService:GetFocusedTextBox()
            end)
            if not (ok and box) then
                FinalChaseClient.Action("Jump")
            end
        -- Mirar atrás (opcional): mantener Q.
        elseif not processed and input.KeyCode == Enum.KeyCode.Q and view and view.Phase == "Run" then
            fx.LookBackTarget = 1
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.Q then
            fx.LookBackTarget = 0
        end
    end)

    Remotes.OnClient("DownState", function(data)
        if typeof(data) == "table" and data.Failed then
            fx.LookBackTarget = 0
            if ui.Action then
                ui.Action.Visible = false
            end
        end
    end)

    ClientState.Subscribe("Game", function(state)
        if state.Phase == "Lobby" or state.Phase == "Loading" then
            EVENTS.Stop()
        end
    end)

    RunService:BindToRenderStep(UNDO_BIND, Enum.RenderPriority.First.Value, undoCamera)
    RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 2, applyCamera)
    RunService.RenderStepped:Connect(update)
end

return FinalChaseClient
