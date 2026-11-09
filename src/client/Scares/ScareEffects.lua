-- Los sustos al azar, tal como los ve y oye cada jugador: una sombra que cruza al
-- fondo, una silueta que desaparece, un portazo, algo que se cae, una luz que
-- parpadea y muestra a alguien, una cara en una ventana, una figura a tu espalda,
-- pasos detrás tuyo, una silueta en lo oscuro, y dos sustos de golpe: una cara
-- pálida o una criatura que se tiran contra la cámara a pantalla completa con
-- estallido, destello y sacudón. Todo es local y se borra solo: no hay nada que
-- la IA pueda ver ni que choque.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ScareConfig = require(Shared.Config.ScareConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local FirstPerson = require(script.Parent.Parent.Camera.FirstPerson)
local SoundKit = require(script.Parent.Parent.Final.SoundKit)

local player = Players.LocalPlayer
local AUDIO = ScareConfig.Audio
local SHADOW = Color3.fromRGB(12, 10, 12)
local PALE = Color3.fromRGB(196, 190, 178)
-- Susto de golpe: cuánto dura en pantalla y desde/hasta qué distancia se tira.
local LUNGE_TIME = 0.62
local LUNGE_REACH = 0.14

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

-- Destello a pantalla completa que se apaga solo (encima de todo, sin bloquear
-- toques: es sólo un Frame sin botones).
local function screenFlash(color, opacity, duration)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end
    local gui = Instance.new("ScreenGui")
    gui.Name = "NocturnaScareFlash"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 60
    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BorderSizePixel = 0
    frame.BackgroundColor3 = color
    frame.BackgroundTransparency = 1 - opacity
    frame.Parent = gui
    gui.Parent = playerGui
    table.insert(active, gui)
    TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {BackgroundTransparency = 1}):Play()
    task.delay(duration + 0.05, function()
        remove(gui)
    end)
end

-- Luz pegada adelante de lo que se tira encima: en un pasillo a oscuras, sin esto
-- sería una mancha negra.
local function faceLight(holder, color, brightness)
    local lamp = part(holder, "ScareLight", Vector3.new(0.2, 0.2, 0.2), color, Enum.Material.SmoothPlastic)
    lamp.Transparency = 1
    local light = Instance.new("PointLight")
    light.Color = color
    light.Brightness = brightness
    light.Range = 6
    light.Shadows = false
    light.Parent = lamp
    return lamp
end

-- El susto de golpe: `pieces` es una lista {pieza, desplazamiento} armada con el
-- frente hacia -Z. Aparece a `from` studs delante de la cámara, se tira hasta
-- `to` en LUNGE_REACH segundos y tiembla pegada a la cara hasta LUNGE_TIME, con
-- estallido, grito, destello, viñeta roja, sacudón y golpe de cámara.
local lungeCount = 0
local function lunge(holder, pieces, from, to, flashColor)
    holder.Parent = workspace
    table.insert(active, holder)
    lungeCount += 1
    local bindName = "NocturnaScareLunge" .. lungeCount
    local started = os.clock()
    local side = (lungeCount % 2 == 0) and 1 or -1

    SoundKit.Play(AUDIO.Jumpscare)
    SoundKit.Play(AUDIO.Shriek)
    task.delay(0.05, function()
        SoundKit.Play(AUDIO.Screech)
    end)
    screenFlash(Color3.new(1, 1, 1), 0.85, 0.22)
    screenFlash(flashColor, 0.5, 0.9)
    FirstPerson.Shake(7, 0.8)
    if FirstPerson.Impulse then
        FirstPerson.Impulse(1.5, side)
    end

    local function update()
        local t = os.clock() - started
        if t > LUNGE_TIME or holder.Parent == nil then
            return false
        end
        local camera = workspace.CurrentCamera
        if not camera then
            return false
        end
        local approach = 1 - (1 - math.clamp(t / LUNGE_REACH, 0, 1)) ^ 3
        local distance = from + (to - from) * approach
        local jitter = Vector3.new(math.sin(t * 93) * 0.05, math.cos(t * 71) * 0.04 - 0.15, -distance)
        local frame = camera.CFrame * CFrame.new(jitter) * CFrame.Angles(0, math.pi, math.sin(t * 37) * 0.07)
        for _, entry in ipairs(pieces) do
            entry[1].CFrame = frame * entry[2]
        end
        return true
    end

    update()
    local bound = pcall(function()
        RunService:BindToRenderStep(bindName, Enum.RenderPriority.Camera.Value + 5, function()
            update()
        end)
    end)
    waitUntil(LUNGE_TIME + 0.05, function()
        if not bound then
            update()
        end
        return holder.Parent == nil
    end)
    if bound then
        RunService:UnbindFromRenderStep(bindName)
    end
    remove(holder)
    -- El eco del golpe: un golpe sordo y el corazón que sigue.
    SoundKit.Play(AUDIO.Thud)
end

local SCARES = {}

function SCARES.FACE_LUNGE()
    local holder = Instance.new("Model")
    holder.Name = "NocturnaScareLungeFace"
    local skin = Color3.fromRGB(205, 198, 184)
    local pieces = {
        {part(holder, "Hair", Vector3.new(1.9, 2.3, 1.3), Color3.fromRGB(10, 9, 9), Enum.Material.Fabric, Enum.PartType.Ball), CFrame.new(0, 0.25, 0.35)},
        {part(holder, "Face", Vector3.new(1.5, 1.95, 1.3), skin, Enum.Material.SmoothPlastic, Enum.PartType.Ball), CFrame.new()},
        {part(holder, "Mouth", Vector3.new(0.42, 0.95, 0.3), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball), CFrame.new(0, -0.48, -0.55)},
        {faceLight(holder, Color3.fromRGB(230, 225, 215), 4), CFrame.new(0, 0.1, -1.6)},
    }
    for _, sideX in ipairs({-1, 1}) do
        table.insert(pieces, {part(holder, "Socket", Vector3.new(0.46, 0.56, 0.3), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, Enum.PartType.Ball), CFrame.new(sideX * 0.31, 0.22, -0.55)})
        table.insert(pieces, {part(holder, "Pupil", Vector3.new(0.09, 0.09, 0.05), Color3.fromRGB(240, 236, 220), Enum.Material.Neon, Enum.PartType.Ball), CFrame.new(sideX * 0.29, 0.2, -0.71)})
        -- Venas oscuras que bajan de los ojos.
        table.insert(pieces, {part(holder, "Vein", Vector3.new(0.05, 0.5, 0.05), Color3.fromRGB(70, 40, 50)), CFrame.new(sideX * 0.33, -0.12, -0.62) * CFrame.Angles(0, 0, sideX * 0.15)})
    end
    lunge(holder, pieces, 7, 0.95, Color3.fromRGB(90, 0, 0))
end

function SCARES.CREATURE_LUNGE()
    local holder = Instance.new("Model")
    holder.Name = "NocturnaScareLungeCreature"
    local hide = Color3.fromRGB(38, 26, 26)
    local bone = Color3.fromRGB(214, 204, 182)
    local pieces = {
        {part(holder, "Skull", Vector3.new(1.7, 1.4, 1.9), hide, Enum.Material.Slate, Enum.PartType.Ball), CFrame.new(0, 0.3, 0.1)},
        {part(holder, "Brow", Vector3.new(1.5, 0.35, 0.6), Color3.fromRGB(26, 18, 18), Enum.Material.Slate), CFrame.new(0, 0.55, -0.7) * CFrame.Angles(-0.25, 0, 0)},
        {part(holder, "UpperJaw", Vector3.new(1.3, 0.32, 1), hide, Enum.Material.Slate), CFrame.new(0, -0.15, -0.55)},
        {part(holder, "LowerJaw", Vector3.new(1.15, 0.28, 1.1), hide, Enum.Material.Slate), CFrame.new(0, -1.05, -0.45) * CFrame.Angles(0.55, 0, 0)},
        {part(holder, "Throat", Vector3.new(1, 0.85, 0.2), Color3.fromRGB(60, 6, 10), Enum.Material.SmoothPlastic), CFrame.new(0, -0.6, -0.3)},
        {faceLight(holder, Color3.fromRGB(255, 70, 50), 5), CFrame.new(0, 0, -1.8)},
    }
    for _, sideX in ipairs({-1, 1}) do
        table.insert(pieces, {part(holder, "Eye", Vector3.new(0.22, 0.16, 0.1), Color3.fromRGB(255, 40, 30), Enum.Material.Neon, Enum.PartType.Ball), CFrame.new(sideX * 0.38, 0.32, -0.95)})
        -- Brazos que entran desde abajo a los costados, con garras hacia la cámara.
        local arm = CFrame.new(sideX * 1.25, -0.95, 0.1) * CFrame.Angles(0.7, sideX * 0.3, 0)
        table.insert(pieces, {part(holder, "Arm", Vector3.new(0.32, 0.32, 1.8), hide, Enum.Material.Slate), arm})
        for finger = -1, 1 do
            table.insert(pieces, {part(holder, "Claw", Vector3.new(0.07, 0.07, 0.6), bone, Enum.Material.SmoothPlastic), arm * CFrame.new(finger * 0.12, 0, -1.1) * CFrame.Angles(0.2, finger * 0.2, 0)})
        end
    end
    for tooth = -2, 2 do
        table.insert(pieces, {part(holder, "Tooth", Vector3.new(0.1, 0.3, 0.1), bone, Enum.Material.SmoothPlastic), CFrame.new(tooth * 0.22, -0.4, -1.0)})
        table.insert(pieces, {part(holder, "Tooth", Vector3.new(0.1, 0.26, 0.1), bone, Enum.Material.SmoothPlastic), CFrame.new(tooth * 0.2, -0.82, -0.9)})
    end
    lunge(holder, pieces, 9, 1.05, Color3.fromRGB(110, 10, 0))
end

function SCARES.SHADOW_CROSS(data)
    local center = visiblePoint(data.Position)
    local from = data.From
    local forward = Vector3.new(center.X - from.X, 0, center.Z - from.Z)
    forward = forward.Magnitude > 0.01 and forward.Unit or Vector3.new(0, 0, 1)
    local side = Vector3.new(-forward.Z, 0, forward.X)
    local model, place = figure(true)
    local started = os.clock()
    local duration = 1.05
    SoundKit.Play(AUDIO.Sting, nil, 1.2, 0.6)
    for step = 0, 3 do
        task.delay(step * 0.24, function()
            SoundKit.Play(AUDIO.Step, center, 1.4)
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
    SoundKit.Play(AUDIO.Thud, nil, 1.1, 0.7)
    FirstPerson.Shake(3.5, 0.6)
    task.wait(0.4)
    SoundKit.Play(AUDIO.Whisper, data.Position, 0.9, 1)
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
    SoundKit.Play(AUDIO.Clatter, spot, 1.1, 1)
    SoundKit.Play(AUDIO.Sting, nil, 1.2, 0.5)
    FirstPerson.Shake(2.5, 0.4)
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
        if alpha >= 0.75 and not data.Stung then
            data.Stung = true
            SoundKit.Play(AUDIO.Sting, nil, 1.1, 0.7)
        end
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
    task.delay(1.2, function()
        if model.Parent then
            SoundKit.Play(AUDIO.Whisper, spot + Vector3.new(0, 5, 0), 0.9)
        end
    end)
    local seen = waitUntil(5, function()
        return looking(spot + Vector3.new(0, 5, 0), 0.55)
    end)
    if seen then
        task.wait(0.12)
        SoundKit.Play(AUDIO.Sting)
        SoundKit.Play(AUDIO.Shriek, nil, 1.3, 0.6)
        screenFlash(Color3.fromRGB(80, 0, 0), 0.35, 0.6)
        FirstPerson.Shake(4.5, 0.5)
    else
        -- No se dio vuelta: igual siente el aliento en la nuca.
        SoundKit.Play(AUDIO.Breath, nil, 0.9, 1.2)
        FirstPerson.Shake(1.2, 0.4)
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
        -- Si se da vuelta, los pasos se cortan de golpe: no hay nadie.
        if looking(spot + Vector3.new(0, 3, 0), 0.4) then
            SoundKit.Play(AUDIO.Sting, nil, 1.3, 0.5)
            return
        end
        SoundKit.Play(AUDIO.Step, spot + Vector3.new(0, 1, 0), 0.9 + step * 0.02, 0.8 + step * 0.1)
        task.wait(0.48)
    end
    SoundKit.Play(AUDIO.Whisper, nil, 1, 1)
    SoundKit.Play(AUDIO.Breath, nil, 0.9, 1)
    FirstPerson.Shake(1.5, 0.4)
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
    if model.Parent then
        SoundKit.Play(AUDIO.Whisper, spot + Vector3.new(0, 4, 0), 0.8)
        SoundKit.Play(AUDIO.Sting, nil, 1.15, 0.6)
    end
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
