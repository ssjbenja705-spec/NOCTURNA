-- Los sustos al azar, tal como los ve y oye cada jugador: una sombra que cruza al
-- fondo, una silueta que desaparece, un portazo, algo que se cae, una luz que
-- parpadea y muestra a alguien, una cara en una ventana, una figura a tu espalda,
-- pasos detrás tuyo, una silueta en lo oscuro. Todo es local y se borra solo:
-- no hay nada que la IA pueda ver ni que choque.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ScareConfig = require(Shared.Config.ScareConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local FirstPerson = require(script.Parent.Parent.Camera.FirstPerson)
local SoundKit = require(script.Parent.Parent.Final.SoundKit)

local player = Players.LocalPlayer
local AUDIO = ScareConfig.Audio
local SHADOW = Color3.fromRGB(8, 7, 8)
local PALE = Color3.fromRGB(196, 190, 178)

local ScareEffects = {}
local active = {}
local played = {}

local function part(parent, name, size, color, material, shape)
    local piece = Instance.new("Part")
    piece.Name = name
    piece.Size = size
    piece.Color = color
    piece.Material = material or Enum.Material.SmoothPlastic
    piece.Anchored = true
    piece.CanCollide = false
    piece.CanTouch = false
    piece.CanQuery = false
    piece.CastShadow = false
    if shape then
        piece.Shape = shape
    end
    piece.Parent = parent
    return piece
end

-- Figura alta y flaca, apenas más alta que una persona. Devuelve el modelo y una
-- función que la ubica (base en el piso, mirando hacia lookAt).
local function figure(withEyes)
    local model = Instance.new("Model")
    model.Name = "NocturnaScareFigure"
    local pieces = {
        {part(model, "Head", Vector3.new(1.2, 1.4, 1.2), SHADOW, nil, Enum.PartType.Ball), CFrame.new(0, 7.1, 0)},
        {part(model, "Torso", Vector3.new(1.7, 3.1, 0.8), SHADOW), CFrame.new(0, 4.9, 0)},
        {part(model, "LeftArm", Vector3.new(0.45, 3.6, 0.45), SHADOW), CFrame.new(-1.15, 4.4, 0) * CFrame.Angles(0, 0, 0.05)},
        {part(model, "RightArm", Vector3.new(0.45, 3.6, 0.45), SHADOW), CFrame.new(1.15, 4.4, 0) * CFrame.Angles(0, 0, -0.05)},
        {part(model, "LeftLeg", Vector3.new(0.6, 3.4, 0.6), SHADOW), CFrame.new(-0.45, 1.7, 0)},
        {part(model, "RightLeg", Vector3.new(0.6, 3.4, 0.6), SHADOW), CFrame.new(0.45, 1.7, 0)},
    }
    if withEyes then
        for _, side in ipairs({-1, 1}) do
            local eye = part(model, "Eye", Vector3.new(0.16, 0.1, 0.05), Color3.fromRGB(230, 225, 210), Enum.Material.Neon)
            table.insert(pieces, {eye, CFrame.new(side * 0.25, 7.2, -0.6)})
        end
    end
    local function place(base, lookAt, hunch)
        local flat = Vector3.new(lookAt.X, base.Y, lookAt.Z)
        local frame = (flat - base).Magnitude > 0.01 and CFrame.lookAt(base, flat) or CFrame.new(base)
        if hunch then
            frame *= CFrame.Angles(-hunch, 0, 0)
        end
        for _, entry in ipairs(pieces) do
            entry[1].CFrame = frame * entry[2]
        end
    end
    model.Parent = workspace
    table.insert(active, model)
    return model, place
end

local function remove(instance)
    local index = table.find(active, instance)
    if index then
        table.remove(active, index)
    end
    if instance.Parent then
        instance:Destroy()
    end
end

local function clearAll()
    for _, instance in ipairs(table.clone(active)) do
        remove(instance)
    end
end

local function cameraFrame()
    local camera = workspace.CurrentCamera
    return camera and camera.CFrame or CFrame.new()
end

-- ¿Está mirando hacia el punto?
local function looking(position, threshold)
    local camera = cameraFrame()
    local offset = position - camera.Position
    if offset.Magnitude < 0.01 then
        return true
    end
    return camera.LookVector:Dot(offset.Unit) >= (threshold or 0.6)
end

local function rootPosition()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and root.Position or nil
end

-- El punto que eligió el servidor, acercado si hay una pared en el medio (así la
-- figura nunca queda metida en la pared).
local function visiblePoint(target)
    local eye = cameraFrame().Position
    local offset = Vector3.new(target.X, eye.Y, target.Z) - eye
    if offset.Magnitude < 1 then
        return target
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {player.Character}
    local hit = workspace:Raycast(eye, offset, params)
    if hit then
        local back = hit.Position - offset.Unit * 2
        return Vector3.new(back.X, target.Y, back.Z)
    end
    return target
end

-- Espera hasta que pase el tiempo o se cumpla la condición. Devuelve true si se cumplió.
local function waitUntil(seconds, condition)
    local deadline = os.clock() + seconds
    while os.clock() < deadline do
        if condition and condition() then
            return true
        end
        task.wait(0.05)
    end
    return false
end

local SCARES = {}

function SCARES.SHADOW_CROSS(data)
    local center = visiblePoint(data.Position)
    local from = data.From
    local forward = Vector3.new(center.X - from.X, 0, center.Z - from.Z)
    forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, 1)
    local side = Vector3.new(-forward.Z, 0, forward.X)
    local model, place = figure(false)
    local started = os.clock()
    local duration = 0.75
    for step = 0, 2 do
        task.delay(step * 0.22, function()
            SoundKit.Play(AUDIO.Step, center, 1.5)
        end)
    end
    while os.clock() - started < duration and model.Parent do
        local alpha = (os.clock() - started) / duration
        local base = Vector3.new(center.X, 0, center.Z) + side * (-5 + 10 * alpha)
        place(base, base + side, 0.35)
        task.wait()
    end
    remove(model)
end

function SCARES.ROOM_SILHOUETTE(data)
    local spot = visiblePoint(data.Position)
    local model, place = figure(true)
    place(Vector3.new(spot.X, 0, spot.Z), data.From)
    local watched = 0
    waitUntil(5, function()
        local root = rootPosition()
        if root and (root - spot).Magnitude < 16 then
            return true
        end
        if looking(spot + Vector3.new(0, 5, 0), 0.85) then
            watched += 0.05
        end
        return watched >= 1.1
    end)
    if model.Parent then
        SoundKit.Play(AUDIO.Sting, nil, 1, 0.7)
    end
    remove(model)
end

function SCARES.DOOR_SLAM(data)
    -- Si el servidor cerró una puerta de verdad, su golpe ya sonó en el lugar.
    if not data.Slammed then
        SoundKit.Play(AUDIO.Slam, data.Position)
    end
    FirstPerson.Shake(1.6, 0.5)
    task.wait(0.4)
    SoundKit.Play(AUDIO.Whisper, data.Position, 0.9, 0.6)
end

function SCARES.OBJECT_FALL(data)
    local spot = visiblePoint(data.Position)
    local holder = Instance.new("Model")
    holder.Name = "NocturnaScareObject"
    holder.Parent = workspace
    table.insert(active, holder)
    local box = part(holder, "FallingBox", Vector3.new(1.6, 1.2, 1.4), Color3.fromRGB(96, 78, 58), Enum.Material.Wood)
    local start = Vector3.new(spot.X, 8, spot.Z)
    local started = os.clock()
    local fallTime = 0.55
    while os.clock() - started < fallTime and box.Parent do
        local alpha = (os.clock() - started) / fallTime
        box.CFrame = CFrame.new(start:Lerp(Vector3.new(spot.X, 0.6, spot.Z), alpha * alpha)) * CFrame.Angles(alpha * 2.4, alpha, 0)
        task.wait()
    end
    if box.Parent then
        box.CFrame = CFrame.new(spot.X, 0.6, spot.Z) * CFrame.Angles(0.3, 1.1, 0)
    end
    SoundKit.Play(AUDIO.Fall, spot)
    SoundKit.Play(AUDIO.Clatter, spot, 1.1, 0.7)
    FirstPerson.Shake(0.8, 0.3)
    task.wait(8)
    remove(holder)
end

local function nearestLight(position)
    local best, bestDistance = nil, 60
    for _, fixture in ipairs(CollectionService:GetTagged("NocturnaLight")) do
        if fixture:IsA("BasePart") then
            local distance = (fixture.Position - position).Magnitude
            if distance < bestDistance then
                best, bestDistance = fixture, distance
            end
        end
    end
    return best
end

function SCARES.LIGHT_REVEAL(data)
    local fixture = typeof(data.Light) == "Instance" and data.Light or nearestLight(data.Position)
    local light = fixture and fixture:FindFirstChildOfClass("PointLight")
    local spot = visiblePoint(data.Position)
    local model, place = figure(true)
    place(Vector3.new(spot.X, 0, spot.Z), data.From)
    model.Parent = nil
    local original = light and light.Enabled
    SoundKit.Play(AUDIO.Buzz, fixture and fixture.Position or spot)
    for flash = 1, 6 do
        if light then
            light.Enabled = false
        end
        if flash == 4 then
            model.Parent = nil
        end
        task.wait(0.09)
        if light then
            light.Enabled = original and fixture:GetAttribute("Dark") ~= true
        end
        -- En el tercer destello hay alguien parado debajo de la luz.
        if flash == 3 then
            model.Parent = workspace
            SoundKit.Play(AUDIO.Sting, nil, 1.1, 0.6)
        end
        task.wait(flash == 3 and 0.35 or 0.13)
    end
    if light and light.Parent then
        light.Enabled = original and fixture:GetAttribute("Dark") ~= true
    end
    remove(model)
end

function SCARES.WINDOW_FACE(data)
    local spot = visiblePoint(data.Position)
    local holder = Instance.new("Model")
    holder.Name = "NocturnaScareFace"
    holder.Parent = workspace
    table.insert(active, holder)
    local head = part(holder, "Face", Vector3.new(1.3, 1.6, 1.2), PALE, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
    local eyes = {}
    for _, side in ipairs({-1, 1}) do
        table.insert(eyes, {part(holder, "EyeHole", Vector3.new(0.25, 0.32, 0.1), Color3.new(0, 0, 0)), side})
    end
    local mouth = part(holder, "Mouth", Vector3.new(0.35, 0.5, 0.1), Color3.new(0, 0, 0))
    local base = Vector3.new(spot.X, 5.6, spot.Z)
    local toward = Vector3.new(data.From.X, 5.6, data.From.Z)
    local frame = (toward - base).Magnitude > 0.01 and CFrame.lookAt(base, toward) or CFrame.new(base)
    local started = os.clock()
    SoundKit.Play(AUDIO.Whisper, spot, 1.1, 0.8)
    while os.clock() - started < 1.6 and head.Parent do
        local alpha = (os.clock() - started) / 1.6
        -- Se asoma, mira, y se corre de golpe.
        local slide = alpha < 0.75 and 0 or (alpha - 0.75) / 0.25 * 2.5
        local tilt = 0.25 + math.sin(alpha * 9) * 0.03
        local current = frame * CFrame.new(slide, 0, 0) * CFrame.Angles(0, 0, tilt)
        head.CFrame = current
        for _, eye in ipairs(eyes) do
            eye[1].CFrame = current * CFrame.new(eye[2] * 0.28, 0.2, -0.58)
        end
        mouth.CFrame = current * CFrame.new(0, -0.4, -0.55)
        task.wait()
    end
    remove(holder)
end

-- Detrás del jugador, a la altura del piso: el punto opuesto a donde mira.
local function behind(distance)
    local root = rootPosition()
    local camera = cameraFrame()
    if not root then
        return nil
    end
    local look = Vector3.new(camera.LookVector.X, 0, camera.LookVector.Z)
    look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
    return Vector3.new(root.X, 0, root.Z) - look * distance, look
end

function SCARES.FIGURE_BEHIND()
    local spot = behind(7)
    if not spot then
        return
    end
    local model, place = figure(true)
    place(spot, rootPosition())
    SoundKit.Play(AUDIO.Breath, spot + Vector3.new(0, 5, 0))
    local seen = waitUntil(4, function()
        return looking(spot + Vector3.new(0, 5, 0), 0.55)
    end)
    if seen then
        task.wait(0.12)
        SoundKit.Play(AUDIO.Sting)
        FirstPerson.Shake(2.5, 0.4)
    end
    remove(model)
end

function SCARES.FOOTSTEPS_BEHIND()
    for step = 1, 6 do
        local distance = 14 - step * 1.7
        local spot = behind(distance)
        if not spot then
            return
        end
        -- Si se da vuelta, los pasos se cortan: no hay nadie.
        if looking(spot + Vector3.new(0, 3, 0), 0.4) then
            return
        end
        SoundKit.Play(AUDIO.Step, spot + Vector3.new(0, 1, 0), 0.9 + step * 0.02, 0.6 + step * 0.08)
        task.wait(0.52)
    end
    SoundKit.Play(AUDIO.Whisper, nil, 1, 0.5)
end

function SCARES.DARK_SILHOUETTE(data)
    local spot = visiblePoint(data.Position)
    local model, place = figure(false)
    place(Vector3.new(spot.X, 0, spot.Z), data.From)
    waitUntil(6, function()
        local root = rootPosition()
        if root and (root - spot).Magnitude < 12 then
            return true
        end
        -- La linterna encima la hace desaparecer.
        return player:GetAttribute("FlashlightEnabled") == true and looking(spot + Vector3.new(0, 4, 0), 0.94)
    end)
    remove(model)
end

function ScareEffects.Play(data)
    if typeof(data) ~= "table" or typeof(data.Position) ~= "Vector3" then
        return false
    end
    if typeof(data.From) ~= "Vector3" then
        data.From = data.Position
    end
    local handler = SCARES[data.Kind]
    if not handler then
        return false
    end
    table.insert(played, data.Kind)
    task.spawn(handler, data)
    return true
end

function ScareEffects.Played()
    return played
end

function ScareEffects.ActiveCount()
    return #active
end

function ScareEffects.Clear()
    clearAll()
end

function ScareEffects.Start()
    Remotes.OnClient("ScareEvent", ScareEffects.Play)

    -- Nada queda flotando si cambia la partida, empieza una escena o el jugador cae.
    ClientState.Subscribe("Game", function(state)
        if state.Phase ~= "Playing" then
            clearAll()
        end
    end)
    Remotes.OnClient("Cinematic", clearAll)
    Remotes.OnClient("ChaseState", function(data)
        if typeof(data) == "table" and data.Event == "Intro" then
            clearAll()
        end
    end)
    Remotes.OnClient("DownState", function(data)
        if typeof(data) == "table" and (data.Down or data.Failed) then
            clearAll()
        end
    end)

    -- Red de seguridad: ninguna figura queda más de 15 segundos.
    local born = setmetatable({}, {__mode = "k"})
    RunService.Heartbeat:Connect(function()
        local now = os.clock()
        for _, instance in ipairs(table.clone(active)) do
            born[instance] = born[instance] or now
            if now - born[instance] > 15 then
                remove(instance)
            end
        end
    end)
end

return ScareEffects
