-- Cámara en primera persona con balanceo al caminar, sacudidas, vista desde el
-- escondite y modo espectador.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)

local player = Players.LocalPlayer
local CONFIG = GameConfig.Player
local CROUCH_OFFSET = Vector3.new(0, -1.6, 0)

-- Desde el escondite se puede espiar un poco hacia los costados.
local HIDE_YAW = math.rad(26)
local HIDE_PITCH = math.rad(12)
local HIDE_TOUCH_SPEED = 1 / 260
-- Ojos acostumbrados a la oscuridad: adentro se ve un poco más.
local HIDE_EXPOSURE = 0.6
-- Teclas para salir del escondite (además del botón SALIR en pantalla).
local EXIT_KEYS = {Enum.KeyCode.E, Enum.KeyCode.ButtonB}
local EXIT_COOLDOWN = 0.4

local FirstPerson = {}
local shakeUntil = 0
local shakeStrength = 0
local bobClock = 0
local hideCFrame = nil
local hideLook = Vector2.zero
local hideAim = Vector2.zero
local exposureBefore = nil
local lastExitRequest = -math.huge
local spectating = false
local spectateReadyAt = 0
local SPECTATE_DELAY = 2.5
local SPECTATE_CHECK = 0.5
local random = Random.new()

function FirstPerson.Shake(strength, duration)
    shakeStrength = math.max(shakeStrength, strength)
    shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

local function currentHumanoid()
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function enterFirstPerson()
    local camera = workspace.CurrentCamera
    player.CameraMode = Enum.CameraMode.LockFirstPerson
    camera.CameraType = Enum.CameraType.Custom
    local humanoid = currentHumanoid()
    if humanoid then
        camera.CameraSubject = humanoid
    end
end

local function spectateNext()
    local camera = workspace.CurrentCamera
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                player.CameraMode = Enum.CameraMode.Classic
                camera.CameraType = Enum.CameraType.Custom
                camera.CameraSubject = humanoid
                return true
            end
        end
    end
    return false
end

local function updateBob(deltaTime, humanoid)
    local moving = humanoid.MoveDirection.Magnitude > 0.1
    local sprinting = player:GetAttribute("IsSprinting") == true
    local crouching = player:GetAttribute("IsCrouching") == true

    if moving then
        bobClock += deltaTime * (sprinting and 14 or 9)
    end

    local amount = moving and (sprinting and 0.14 or 0.07) or 0
    local bob = Vector3.new(math.cos(bobClock * 0.5) * amount, math.sin(bobClock) * amount, 0)
    local base = crouching and CROUCH_OFFSET or Vector3.zero
    humanoid.CameraOffset = humanoid.CameraOffset:Lerp(base + bob, math.min(1, deltaTime * 12))
end

local function updateFieldOfView(deltaTime, camera)
    local sprinting = player:GetAttribute("IsSprinting") == true
    local target = sprinting and CONFIG.SprintFieldOfView or CONFIG.FieldOfView
    camera.FieldOfView += (target - camera.FieldOfView) * math.min(1, deltaTime * 6)
end

-- La sacudida se aplica después de la cámara de Roblox y se deshace antes del
-- cuadro siguiente: si no, Roblox parte de la vista sacudida y la mirada se corre.
local lastShake = nil

local function undoShake()
    local camera = workspace.CurrentCamera
    if lastShake and camera then
        camera.CFrame *= lastShake:Inverse()
    end
    lastShake = nil
end

local function applyShake(camera)
    if os.clock() >= shakeUntil then
        shakeStrength = 0
        return
    end

    local remaining = shakeUntil - os.clock()
    local power = shakeStrength * math.clamp(remaining, 0, 1)
    local rotation = CFrame.Angles(
        random:NextNumber(-1, 1) * power * 0.02,
        random:NextNumber(-1, 1) * power * 0.02,
        random:NextNumber(-1, 1) * power * 0.03
    )
    camera.CFrame *= rotation
    lastShake = rotation
end

-- El servidor sólo conoce el giro del cuerpo. Localmente el haz sigue a la cámara,
-- para poder apuntar también hacia arriba, donde anda El Trepador.
local function aimFlashlight(camera)
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    local attachment = head and head:FindFirstChild("NocturnaFlashlightAttachment")
    if attachment then
        attachment.WorldCFrame = camera.CFrame
    end
end

local function setPromptsEnabled(enabled)
    -- Mientras está escondido no se ven ni se disparan los demás prompts: así la
    -- tecla E queda libre para salir.
    pcall(function()
        ProximityPromptService.Enabled = enabled
    end)
end

local function setHidden(hidden, cframe, ejected)
    local camera = workspace.CurrentCamera
    if hidden and cframe then
        hideCFrame = cframe
        hideLook = Vector2.zero
        hideAim = Vector2.zero
        camera.CameraType = Enum.CameraType.Scriptable
        camera.CFrame = cframe
        if exposureBefore == nil then
            exposureBefore = Lighting.ExposureCompensation
            Lighting.ExposureCompensation = exposureBefore + HIDE_EXPOSURE
        end
        setPromptsEnabled(false)
        return
    end

    local wasHidden = hideCFrame ~= nil
    hideCFrame = nil
    if exposureBefore ~= nil then
        Lighting.ExposureCompensation = exposureBefore
        exposureBefore = nil
    end
    setPromptsEnabled(true)
    if wasHidden or ejected then
        enterFirstPerson()
    end
    if ejected then
        FirstPerson.Shake(5, 0.8)
    end
end

function FirstPerson.IsHidden()
    return hideCFrame ~= nil
end

function FirstPerson.HideCFrame()
    return hideCFrame
end

function FirstPerson.RequestExit()
    if not hideCFrame or os.clock() - lastExitRequest < EXIT_COOLDOWN then
        return false
    end
    lastExitRequest = os.clock()
    Remotes.FireServer("ExitHiding")
    return true
end

-- Mirar alrededor desde adentro: el mouse (libre mientras está escondido) o
-- arrastrando el dedo. Siempre dentro de un margen chico.
local function onInputChanged(input)
    if not hideCFrame then
        return
    end
    local camera = workspace.CurrentCamera
    if input.UserInputType == Enum.UserInputType.MouseMovement and camera then
        local size = camera.ViewportSize
        local offset = Vector2.new(input.Position.X, input.Position.Y) - size / 2
        hideAim = Vector2.new(
            math.clamp(offset.X / (size.X / 2), -1, 1),
            math.clamp(offset.Y / (size.Y / 2), -1, 1)
        )
    elseif input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Delta
        hideAim = Vector2.new(
            math.clamp(hideAim.X + delta.X * HIDE_TOUCH_SPEED, -1, 1),
            math.clamp(hideAim.Y + delta.Y * HIDE_TOUCH_SPEED, -1, 1)
        )
    end
end

local function onInputBegan(input, processed)
    if processed or not hideCFrame then
        return
    end
    for _, key in ipairs(EXIT_KEYS) do
        if input.KeyCode == key then
            FirstPerson.RequestExit()
            return
        end
    end
end

function FirstPerson.Start()
    player.CameraMode = Enum.CameraMode.LockFirstPerson

    player.CharacterAdded:Connect(function(character)
        setHidden(false, nil, false)
        spectating = false
        character:WaitForChild("Humanoid", 10)
        enterFirstPerson()
    end)

    Remotes.OnClient("HideState", setHidden)

    -- El servidor es la fuente de verdad: si dice que ya no está escondido, la
    -- cámara vuelve aunque se haya perdido el aviso.
    player:GetAttributeChangedSignal("Hidden"):Connect(function()
        if player:GetAttribute("Hidden") ~= true and hideCFrame then
            setHidden(false, nil, false)
        end
    end)

    UserInputService.InputBegan:Connect(onInputBegan)
    UserInputService.InputChanged:Connect(onInputChanged)

    Remotes.OnClient("DownState", function(data)
        if data.Spectating then
            spectating = true
            spectateReadyAt = os.clock() + SPECTATE_DELAY
            task.delay(SPECTATE_DELAY, function()
                if spectating then
                    spectateNext()
                end
            end)
        elseif data.Down == false then
            spectating = false
        end
    end)

    -- Si el compañero que se mira cae o se va, la cámara pasa al siguiente con vida.
    task.spawn(function()
        while true do
            task.wait(SPECTATE_CHECK)
            if spectating and os.clock() >= spectateReadyAt then
                local camera = workspace.CurrentCamera
                local subject = camera and camera.CameraSubject
                local watching = subject ~= nil and subject:IsA("Humanoid") and subject.Health > 0
                    and subject.Parent ~= player.Character and subject:IsDescendantOf(workspace)
                if not watching then
                    spectateNext()
                end
            end
        end
    end)

    ClientState.Subscribe("Game", function(data)
        if data.Phase == "Lobby" then
            spectating = false
            FirstPerson.ResetCamera()
        end
    end)

    RunService:BindToRenderStep("NocturnaCameraUndoShake", Enum.RenderPriority.Camera.Value - 1, undoShake)

    RunService:BindToRenderStep("NocturnaCamera", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end

        if hideCFrame then
            hideLook = hideLook:Lerp(hideAim, math.min(1, deltaTime * 6))
            local sway = math.sin(os.clock() * 0.9) * 0.004
            camera.CameraType = Enum.CameraType.Scriptable
            camera.CFrame = hideCFrame * CFrame.Angles(
                -hideLook.Y * HIDE_PITCH + sway,
                -hideLook.X * HIDE_YAW + sway * 0.5,
                0
            )
        elseif not spectating then
            local humanoid = currentHumanoid()
            if humanoid and humanoid.Health > 0 then
                updateBob(deltaTime, humanoid)
                aimFlashlight(camera)
            end
            updateFieldOfView(deltaTime, camera)
        end

        applyShake(camera)
    end)
end

function FirstPerson.ResetCamera()
    setHidden(false, nil, false)
    if player.Character then
        enterFirstPerson()
    end
end

return FirstPerson
