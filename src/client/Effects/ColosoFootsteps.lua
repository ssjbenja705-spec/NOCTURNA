-- Pisadas de El Coloso que se sienten: cada paso suena fuerte cerca (golpe +
-- retumbe del piso + escombros), sacude la cámara ~1 s según la distancia (fuerte
-- a menos de ~10 studs, nada desde ~60), levanta polvo y hace titilar las luces
-- cercanas; de lejos se oye un retumbe grave que avisa que viene.
--
-- Va aparte de la animación: escucha el atributo "Footstep" que el animador pone
-- en el modelo en cada apoyo (el signo dice qué pie). Si el cuerpo no publica
-- pasos (fuera del alcance del animador, otro esqueleto, animación rota), arma
-- los pasos con un reloj a partir de MoveSpeed, para que nunca camine en silencio.
--
-- Cuando el animador publica el paso, él mismo ya tocó el golpe (ColosoStep) y el
-- impacto de cámara (FirstPerson.Impulse); acá se suman las otras capas. Con el
-- reloj de respaldo, acá se hace todo.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local ColosoFootsteps = {}

local KIND = "ElColoso"
-- Distancias (studs) desde la cámara hasta el pie.
local NEAR = 8
local FAR = 60
local DUST_RANGE = 45
local FLICKER_RANGE = 28
local DEBRIS_RANGE = 40
local RUMBLE_FROM = 35
local RUMBLE_RANGE = 220
-- Sin pulsos del animador por más de esto (veces el paso esperado): reloj propio.
local SILENCE_FACTOR = 1.6
local MIN_SPEED = 0.6
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local tracked = {}
local feedback = nil
local stepCount = 0
local lastInfo = nil
local started = false

-- Sonido, cámara y calidad se cargan aparte (como en MonsterAnimator: nunca se
-- traba un cuadro esperando un require).
local function getFeedback()
    if feedback then
        return feedback
    end
    local loaded = {}
    local effects = script.Parent
    local cameraFolder = effects.Parent:FindFirstChild("Camera")
    local modules = {
        Audio = effects:FindFirstChild("AudioController"),
        Camera = cameraFolder and cameraFolder:FindFirstChild("FirstPerson"),
        Quality = effects:FindFirstChild("QualityController"),
    }
    for name, module in pairs(modules) do
        if module then
            local ok, result = pcall(require, module)
            loaded[name] = ok and result or nil
        end
    end
    feedback = loaded
    return loaded
end

local function playAt(name, position)
    local audio = getFeedback().Audio
    if audio and audio.PlayAt then
        pcall(audio.PlayAt, name, position)
    end
end

local function lowQuality()
    local quality = getFeedback().Quality
    if quality and quality.IsLow then
        local ok, low = pcall(quality.IsLow)
        return ok and low == true
    end
    return false
end

-- Fuerza (0..1) del impacto de cámara a `distance` studs (la misma curva que usa
-- el animador: fuerte de cerca, se apaga suave y es cero desde FAR).
function ColosoFootsteps.Power(distance)
    if distance >= FAR then
        return 0
    end
    local alpha = 1 - math.clamp((distance - NEAR) / (FAR - NEAR), 0, 1)
    return alpha * alpha
end

-- Cuánto tarda un paso a esa velocidad (studs/s): ~0,9 s caminando, ~0,45 s corriendo.
function ColosoFootsteps.StepInterval(speed)
    return math.clamp(5.5 / math.max(speed, 0.1), 0.45, 1.3)
end

local function isColoso(model)
    return model:IsA("Model") and (model:GetAttribute("Kind") == KIND or model.Name == KIND)
end

local function rootOf(model)
    local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
    return root and root:IsA("BasePart") and root or nil
end

-- El punto del piso bajo el pie (`side` -1/1).
local function footPoint(model, root, side)
    local frame = root.CFrame
    local width = math.clamp(root.Size.X * 0.6, 1, 3)
    local above = frame.Position + frame.RightVector * side * width
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {model}
    local hit = workspace:Raycast(above, Vector3.new(0, -40, 0), params)
    if hit and hit.Position.Y < above.Y then
        return hit.Position
    end
    return Vector3.new(above.X, 0, above.Z)
end

local function cameraPosition()
    local camera = workspace.CurrentCamera
    return camera and camera.CFrame.Position or nil
end

local function puffDust(point, power)
    local holder = Instance.new("Attachment")
    holder.Name = "NocturnaColosoDust"
    holder.WorldPosition = point + Vector3.new(0, 0.3, 0)
    holder.Parent = workspace.Terrain
    local dust = Instance.new("ParticleEmitter")
    dust.Texture = DUST_TEXTURE
    dust.Color = ColorSequence.new(Color3.fromRGB(122, 112, 98))
    dust.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.55),
        NumberSequenceKeypoint.new(0.4, 0.75),
        NumberSequenceKeypoint.new(1, 1),
    })
    dust.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5)})
    dust.Lifetime = NumberRange.new(0.9, 1.6)
    dust.Speed = NumberRange.new(3, 7)
    dust.SpreadAngle = Vector2.new(80, 15)
    dust.EmissionDirection = Enum.NormalId.Top
    dust.Acceleration = Vector3.new(0, -2, 0)
    dust.Drag = 3
    dust.Rate = 0
    dust.LightInfluence = 1
    dust.Parent = holder
    dust:Emit(math.floor(8 + 10 * power))
    Debris:AddItem(holder, 2.5)
    return holder
end

-- Las luces cercanas bajan de golpe y vuelven: no se tocan las apagadas ni las que
-- otro efecto está haciendo parpadear (sólo el brillo, nunca Enabled).
local dimmed = {}
local function flickerLights(point, power)
    local count = 0
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        if fixture:IsA("BasePart") and (fixture.Position - point).Magnitude <= FLICKER_RANGE then
            local light = fixture:FindFirstChildOfClass("PointLight") or fixture:FindFirstChildOfClass("SpotLight")
            if light and light.Enabled and not dimmed[light] then
                local original = light.Brightness
                dimmed[light] = original
                light.Brightness = original * (1 - 0.75 * power)
                count += 1
                task.delay(0.07, function()
                    if light.Parent then
                        light.Brightness = original * 0.6
                    end
                    task.wait(0.06)
                    if light.Parent then
                        light.Brightness = original
                    end
                    dimmed[light] = nil
                end)
                if count >= 3 then
                    break
                end
            end
        end
    end
    return count
end

-- Un paso. synthetic = true si lo armó el reloj de respaldo (entonces también
-- toca el golpe y el impacto de cámara que normalmente pone el animador).
-- Devuelve qué hizo (para pruebas y ajustes).
function ColosoFootsteps.Step(model, side, synthetic)
    local root = rootOf(model)
    local eye = cameraPosition()
    if not root or not eye then
        return nil
    end
    side = (side or 1) < 0 and -1 or 1
    stepCount += 1
    local foot = footPoint(model, root, side)
    local distance = (foot - eye).Magnitude
    local rage = model:GetAttribute("Rage") == true
    local power = ColosoFootsteps.Power(distance) * (rage and 1.25 or 1)
    local info = {Distance = distance, Power = power, Synthetic = synthetic == true, Side = side}

    if synthetic then
        playAt("ColosoStep", foot)
        local camera = getFeedback().Camera
        if power > 0 and camera and camera.Impulse then
            pcall(camera.Impulse, power, side)
            info.Impulse = power
        end
    end
    if distance <= FAR + 20 then
        playAt("ColosoBoom", foot)
        info.Boom = true
    end
    if distance <= DEBRIS_RANGE then
        playAt("ColosoDebris", foot + Vector3.new(0, 6, 0))
    end
    if distance >= RUMBLE_FROM and distance <= RUMBLE_RANGE then
        playAt("ColosoRumble", foot)
        info.Rumble = true
    end
    if distance <= DUST_RANGE and not lowQuality() then
        info.Dust = puffDust(foot, power)
    end
    if power > 0.05 then
        info.Flicker = flickerLights(foot, math.clamp(power, 0.3, 1))
    end
    lastInfo = info
    return info
end

local function track(model)
    if tracked[model] or not isColoso(model) then
        return
    end
    local state = {
        LastPulse = -math.huge,
        LastStep = os.clock(),
        Side = 1,
        Connections = {},
    }
    tracked[model] = state
    table.insert(state.Connections, model:GetAttributeChangedSignal("Footstep"):Connect(function()
        local value = model:GetAttribute("Footstep")
        if type(value) ~= "number" or value == 0 then
            return
        end
        state.LastPulse = os.clock()
        state.LastStep = state.LastPulse
        state.Side = value < 0 and -1 or 1
        ColosoFootsteps.Step(model, state.Side, false)
    end))
end

local function untrack(model)
    local state = tracked[model]
    if state then
        for _, connection in ipairs(state.Connections) do
            connection:Disconnect()
        end
        tracked[model] = nil
    end
end

-- Reloj de respaldo: si camina y el animador no publica pasos, se arman acá.
function ColosoFootsteps.Update()
    local now = os.clock()
    for model, state in pairs(tracked) do
        if model.Parent == nil then
            untrack(model)
        else
            local speed = model:GetAttribute("MoveSpeed")
            speed = type(speed) == "number" and speed or 0
            local interval = ColosoFootsteps.StepInterval(speed)
            local silent = now - state.LastPulse > interval * SILENCE_FACTOR
            if speed >= MIN_SPEED and silent and now - state.LastStep >= interval then
                state.LastStep = now
                state.Side = -state.Side
                ColosoFootsteps.Step(model, state.Side, true)
            end
        end
    end
end

function ColosoFootsteps.Track(model)
    track(model)
    return tracked[model] ~= nil
end

function ColosoFootsteps.Tracked()
    return tracked
end

function ColosoFootsteps.Count()
    return stepCount
end

function ColosoFootsteps.LastStep()
    return lastInfo
end

function ColosoFootsteps.Start()
    if started then
        return
    end
    started = true
    CollectionService:GetInstanceAddedSignal("NocturnaMonster"):Connect(function(model)
        -- El atributo Kind puede llegar un instante después que la etiqueta.
        task.defer(track, model)
    end)
    CollectionService:GetInstanceRemovedSignal("NocturnaMonster"):Connect(untrack)
    for _, model in ipairs(CollectionService:GetTagged("NocturnaMonster")) do
        track(model)
    end
    RunService.Heartbeat:Connect(ColosoFootsteps.Update)
end

return ColosoFootsteps
