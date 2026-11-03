-- Cámara en primera persona con balanceo al caminar, sacudidas, vista desde el
-- escondite y modo espectador.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)

local player = Players.LocalPlayer
local CONFIG = GameConfig.Player
local CROUCH_OFFSET = Vector3.new(0, -1.6, 0)

local FirstPerson = {}
local shakeUntil = 0
local shakeStrength = 0
local bobClock = 0
local hideCFrame = nil
local spectating = false
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

local function applyShake(camera)
    if os.clock() >= shakeUntil then
        shakeStrength = 0
        return
    end

    local remaining = shakeUntil - os.clock()
    local power = shakeStrength * math.clamp(remaining, 0, 1)
    camera.CFrame *= CFrame.Angles(
        random:NextNumber(-1, 1) * power * 0.02,
        random:NextNumber(-1, 1) * power * 0.02,
        random:NextNumber(-1, 1) * power * 0.03
    )
end

local function setHidden(hidden, cframe, ejected)
    local camera = workspace.CurrentCamera
    if hidden then
        hideCFrame = cframe
        camera.CameraType = Enum.CameraType.Scriptable
        TweenService:Create(camera, TweenInfo.new(0.35), {CFrame = cframe}):Play()
    else
        hideCFrame = nil
        enterFirstPerson()
        if ejected then
            FirstPerson.Shake(5, 0.8)
        end
    end
end

function FirstPerson.Start()
    player.CameraMode = Enum.CameraMode.LockFirstPerson

    player.CharacterAdded:Connect(function(character)
        hideCFrame = nil
        spectating = false
        character:WaitForChild("Humanoid", 10)
        enterFirstPerson()
    end)

    Remotes.OnClient("HideState", setHidden)

    Remotes.OnClient("DownState", function(data)
        if data.Spectating then
            spectating = true
            task.delay(2.5, function()
                if spectating then
                    spectateNext()
                end
            end)
        elseif data.Down == false then
            spectating = false
        end
    end)

    ClientState.Subscribe("Game", function(data)
        if data.Phase == "Lobby" then
            spectating = false
            FirstPerson.ResetCamera()
        end
    end)

    RunService:BindToRenderStep("NocturnaCamera", Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
        local camera = workspace.CurrentCamera
        if not camera then
            return
        end

        if hideCFrame then
            local sway = math.sin(os.clock() * 0.9) * 0.004
            camera.CFrame = hideCFrame * CFrame.Angles(sway, sway * 0.5, 0)
        elseif not spectating then
            local humanoid = currentHumanoid()
            if humanoid and humanoid.Health > 0 then
                updateBob(deltaTime, humanoid)
            end
            updateFieldOfView(deltaTime, camera)
        end

        applyShake(camera)
    end)
end

function FirstPerson.ResetCamera()
    hideCFrame = nil
    if player.Character then
        enterFirstPerson()
    end
end

return FirstPerson
