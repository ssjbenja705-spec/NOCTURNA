-- Cámara de la captura (sólo la víctima): sale de la primera persona a un plano
-- dramático que muestra a la criatura y al jugador. Nunca atraviesa paredes ni el
-- cuerpo de la criatura, y busca un ángulo donde un brazo no tape la cabeza:
--   * resorte críticamente amortiguado para posición y foco (sin saltos);
--   * rayo desde la cabeza de la víctima hasta la cámara (paredes);
--   * prueba contra las cajas de las piezas de la criatura (no queda adentro);
--   * cada 0,2 s elige entre varios ángulos el que ve la cabeza sin estorbos.
-- Mientras corre el tiempo el plano se acerca a la cara (o a la boca) de la
-- criatura. Al terminar devuelve la primera persona mirando a la criatura.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CaptureConfig = require(Shared.Config.CaptureConfig)

local player = Players.LocalPlayer

local BIND_NAME = "NocturnaCaptureCamera"
local BLEND_IN = 0.5
local CHOOSE_INTERVAL = 0.2
local POSITION_FREQUENCY = 7
local FOCUS_FREQUENCY = 9
local WALL_MARGIN = 0.6
local CREATURE_MARGIN = 0.45
local RETURN_DELAY = {Escaped = 0.35, Failed = 0.2, Ended = 0}
-- Red de seguridad: si se pierde el aviso del final, la cámara vuelve igual.
local SAFETY_PADDING = 4

local CaptureCamera = {}
local shot = nil
local token = 0
local random = Random.new()

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local blockParams = RaycastParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Include

local function flat(vector)
    return Vector3.new(vector.X, 0, vector.Z)
end

local function ease(alpha)
    alpha = math.clamp(alpha, 0, 1)
    return alpha * alpha * (3 - 2 * alpha)
end

-- Resorte críticamente amortiguado (sin rebote): x tiende a goal.
local function spring(state, goal, frequency, deltaTime)
    local omega = frequency * 1.6
    local decay = math.exp(-omega * deltaTime)
    local offset = state.Value - goal
    local velocity = state.Velocity
    state.Value = goal + (offset + (velocity + offset * omega) * deltaTime) * decay
    state.Velocity = (velocity - (velocity + offset * omega) * (omega * deltaTime)) * decay
end

local function creatureParts(model)
    local parts = {}
    -- La malla con piel (criaturas con huesos) mide lo que el cuerpo entero en
    -- reposo: su caja no sirve para esquivarla. Ahí cuentan las guías Head y Jaw.
    local body = model:GetAttribute("BoneRig") == true and model:FindFirstChild("Body") or nil
    for _, child in ipairs(model:GetDescendants()) do
        if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" and not (body and child:IsDescendantOf(body)) then
            table.insert(parts, child)
        end
    end
    return parts
end

local function insidePart(part, point, margin)
    local localPoint = part.CFrame:PointToObjectSpace(point)
    local half = part.Size / 2 + Vector3.new(margin, margin, margin)
    return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

local function insideCreature(parts, point)
    for _, part in ipairs(parts) do
        if part.Parent and insidePart(part, point, CREATURE_MARGIN) then
            return true
        end
    end
    return false
end

local function refreshFilters(model)
    local excluded = {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other.Character then
            table.insert(excluded, other.Character)
        end
    end
    local monsters = workspace:FindFirstChild("Monsters")
    if monsters then
        table.insert(excluded, monsters)
    elseif model then
        table.insert(excluded, model)
    end
    rayParams.FilterDescendantsInstances = excluded
end

-- Desde el pivote (cabeza de la víctima) hasta donde se pueda: ni pared ni criatura.
local function protect(pivot, desired, parts)
    local offset = desired - pivot
    local distance = offset.Magnitude
    if distance < 0.05 then
        return desired, 1
    end
    local direction = offset / distance
    local hit = workspace:Raycast(pivot, offset, rayParams)
    if hit then
        distance = math.max(0.3, (hit.Position - pivot).Magnitude - WALL_MARGIN)
    end
    local reach = distance
    -- Si el punto cae adentro de la criatura, se acerca de a poco al pivote.
    while reach > 0.3 and insideCreature(parts, pivot + direction * reach) do
        reach -= 0.25
    end
    return pivot + direction * reach, reach / (offset.Magnitude)
end

local function keyPoints(data)
    local model = data.Monster
    local character = player.Character
    local victimHead = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
    if not model or not model.Parent or not victimHead then
        return nil
    end
    local head = model:FindFirstChild("Head") or model.PrimaryPart
    if not head then
        return nil
    end
    local mouth = model:FindFirstChild("Jaw")
    local focus = head.Position
    if mouth and data.Profile.Mouth == "Jaw" then
        focus = head.Position:Lerp(mouth.Position, 0.5)
    end
    local pivot = victimHead.Position
    if victimHead.Name ~= "Head" then
        pivot += Vector3.new(0, 1.5, 0)
    end
    return pivot, focus, head
end

-- Plano candidato: detrás y al costado de la víctima, mirando a la criatura.
local function candidate(pivot, focus, settings, side, up, closeness)
    local toward = flat(focus - pivot)
    toward = toward.Magnitude > 0.05 and toward.Unit or Vector3.new(0, 0, -1)
    local right = toward:Cross(Vector3.new(0, 1, 0))
    local back = settings.Back * (1 - 0.35 * closeness)
    return pivot - toward * back + right * side + Vector3.new(0, up, 0)
end

-- Ve la cabeza de la criatura sin que otra pieza suya (un brazo, una placa) la tape.
local function seesHead(from, focus, parts, head)
    local blockers = {}
    for _, part in ipairs(parts) do
        if part ~= head and part.Name ~= "Jaw" and part.Name ~= "Eye" then
            table.insert(blockers, part)
        end
    end
    if #blockers == 0 then
        return true
    end
    blockParams.FilterDescendantsInstances = blockers
    return workspace:Raycast(from, focus - from, blockParams) == nil
end

local function choose(data, pivot, focus, head, closeness)
    local settings = data.Profile.Camera
    local options = {
        {settings.Side, settings.Up},
        {-settings.Side, settings.Up},
        {settings.Side * 0.4, settings.Up + 1.4},
        {-settings.Side * 0.4, settings.Up + 1.4},
    }
    local best, bestScore = options[1], -math.huge
    for index, option in ipairs(options) do
        local wanted = candidate(pivot, focus, settings, option[1], option[2], closeness)
        local position, kept = protect(pivot, wanted, data.Parts)
        local score = kept * 2 - index * 0.05
        if seesHead(position, focus, data.Parts, head) then
            score += 3
        end
        if score > bestScore then
            best, bestScore = option, score
        end
    end
    return best
end

-- En primera persona Roblox oculta el cuerpo propio; en el plano de la captura
-- tiene que verse. Las piezas se juntan una vez por captura.
local function showCharacter(data)
    if not data.CharacterParts then
        data.CharacterParts = {}
        local character = player.Character
        for _, part in ipairs(character and character:GetDescendants() or {}) do
            if part:IsA("BasePart") then
                table.insert(data.CharacterParts, part)
            end
        end
    end
    for _, part in ipairs(data.CharacterParts) do
        pcall(function()
            part.LocalTransparencyModifier = 0
        end)
    end
end

local function restore(lookAt)
    local camera = workspace.CurrentCamera
    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
    end)
    if not camera then
        return
    end
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    if head and lookAt and (lookAt - head.Position).Magnitude > 0.5 then
        camera.CFrame = CFrame.lookAt(head.Position, lookAt)
    end
    camera.FieldOfView = shot and shot.FovBefore or camera.FieldOfView
    local ok = pcall(function()
        local module = script.Parent:FindFirstChild("FirstPerson")
        require(module).ResetCamera()
    end)
    if not ok then
        player.CameraMode = Enum.CameraMode.LockFirstPerson
        camera.CameraType = Enum.CameraType.Custom
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            camera.CameraSubject = humanoid
        end
    end
end

local function update(deltaTime)
    local data = shot
    local camera = workspace.CurrentCamera
    if not data or not camera then
        return
    end
    local now = os.clock()
    if now > data.SafetyAt then
        CaptureCamera.Finish("Ended")
        return
    end

    local pivot, focus, head = keyPoints(data)
    if not pivot then
        return
    end
    data.LastFocus = focus

    -- Peligro: cuánto falta para que se acabe el tiempo (0 al empezar, 1 al final).
    local danger = 0
    if data.Deadline and data.TimeLimit and data.TimeLimit > 0 then
        danger = 1 - math.clamp((data.Deadline - now) / data.TimeLimit, 0, 1)
    end
    if data.Phase == "Fail" then
        danger = 1
        data.FailBlend = math.min(1, (data.FailBlend or 0) + deltaTime / 0.6)
    end
    local closeness = math.clamp(danger * 0.8 + (data.FailBlend or 0) * 0.5, 0, 1)

    if now >= data.NextChoice then
        data.NextChoice = now + CHOOSE_INTERVAL
        refreshFilters(data.Monster)
        data.Option = choose(data, pivot, focus, head, closeness)
    end

    local settings = data.Profile.Camera
    local wanted = candidate(pivot, focus, settings, data.Option[1], data.Option[2], closeness)
    local target = protect(pivot, wanted, data.Parts)
    local lookGoal = pivot:Lerp(focus, math.clamp(settings.Bias + closeness * 0.2, 0, 1))

    if not data.Position then
        data.Position = {Value = target, Velocity = Vector3.zero}
        data.Focus = {Value = lookGoal, Velocity = Vector3.zero}
    end
    spring(data.Position, target, POSITION_FREQUENCY, deltaTime)
    spring(data.Focus, lookGoal, FOCUS_FREQUENCY, deltaTime)

    -- El resorte también se protege: en ningún cuadro queda del otro lado de una pared.
    local position = protect(pivot, data.Position.Value, data.Parts)
    local cframe = CFrame.lookAt(position, data.Focus.Value)

    -- Sacudida: temblor de fondo que crece con el peligro, más los tirones del forcejeo.
    data.Jolt = math.max(0, data.Jolt - deltaTime * 3.5)
    local power = 0.12 + danger * 0.5 + data.Jolt
    cframe *= CFrame.Angles(
        random:NextNumber(-1, 1) * power * 0.012,
        random:NextNumber(-1, 1) * power * 0.012,
        random:NextNumber(-1, 1) * power * 0.02
    )
    -- Golpe de cámara del contragolpe: un empujón corto hacia la criatura.
    if data.Punch > 0 then
        data.Punch = math.max(0, data.Punch - deltaTime * 4)
        cframe *= CFrame.new(0, 0, -data.Punch * 0.8)
    end

    local blend = ease((now - data.StartedAt) / BLEND_IN)
    if blend < 1 then
        cframe = data.From:Lerp(cframe, blend)
    end
    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = cframe
    camera.FieldOfView = settings.Fov - closeness * 8 + data.Punch * 14
    showCharacter(data)
end

function CaptureCamera.IsActive()
    return shot ~= nil
end

function CaptureCamera.Begin(data)
    local camera = workspace.CurrentCamera
    local model = data and data.Monster
    if not camera or typeof(model) ~= "Instance" or not model.Parent then
        return
    end
    local profile = CaptureConfig.Creatures[data.Kind] or CaptureConfig.Creatures.ElOyente
    CaptureCamera.Finish("Ended", true)
    token += 1
    local now = os.clock()
    shot = {
        Monster = model,
        Kind = data.Kind,
        Profile = profile,
        Parts = creatureParts(model),
        Phase = "Grab",
        StartedAt = now,
        From = camera.CFrame,
        FovBefore = camera.FieldOfView,
        NextChoice = 0,
        Option = {profile.Camera.Side, profile.Camera.Up},
        Jolt = 1,
        Punch = 0,
        SafetyAt = now + (tonumber(data.GrabTime) or 2) + 30,
    }
    refreshFilters(model)
    camera.CameraType = Enum.CameraType.Scriptable
    RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 8, update)
end

-- Datos nuevos del servidor: fase, plazo y tiempo total.
function CaptureCamera.Sync(data)
    if not shot or typeof(data) ~= "table" then
        return
    end
    if type(data.TimeLeft) == "number" and type(data.TimeLimit) == "number" then
        shot.Deadline = os.clock() + data.TimeLeft
        shot.TimeLimit = data.TimeLimit
        shot.SafetyAt = shot.Deadline + CaptureConfig.FailTime + SAFETY_PADDING
    end
    if data.Event == "Failing" then
        shot.Phase = "Fail"
    elseif data.Event == "Struggle" then
        shot.Phase = "Struggle"
    end
end

-- Tirón de cámara: cada tecla del forcejeo (más fuerte si fue un error).
function CaptureCamera.Jolt(strength)
    if shot then
        shot.Jolt = math.min(2, shot.Jolt + (strength or 0.5))
    end
end

-- kind: "Escaped" (golpe de cámara y vuelve), "Failed" o "Ended".
function CaptureCamera.Finish(kind, immediate)
    if not shot then
        return
    end
    local current = shot
    token += 1
    local mine = token
    local lookAt = current.LastFocus
    if kind == "Escaped" then
        current.Punch = 1
        current.Jolt = 1.5
    end
    local delay = immediate and 0 or (RETURN_DELAY[kind] or 0)
    local function finish()
        if mine ~= token or shot ~= current then
            return
        end
        restore(lookAt)
        shot = nil
    end
    if delay > 0 then
        task.delay(delay, finish)
    else
        finish()
    end
end

function CaptureCamera.Start()
    -- Si el personaje cambia (reaparición) o termina la partida, se devuelve la cámara.
    player.CharacterAdded:Connect(function()
        CaptureCamera.Finish("Ended", true)
    end)
end

return CaptureCamera
