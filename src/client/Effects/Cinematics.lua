-- Cinemáticas cortas: cuando una prueba u objetivo abre una puerta, la cámara
-- encuadra la apertura con franjas negras y vuelve sola al jugador. El control
-- siempre se devuelve, aunque algo falle: hay un tope de tiempo de seguridad.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Parent.UI.Theme)

local player = Players.LocalPlayer

local BIND_NAME = "NocturnaCinematic"
local BLEND_TIME = 0.45
local MIN_DURATION = 0.5
local MAX_DURATION = 5
local SAFETY_MARGIN = 1.5
local BAR_HEIGHT = 0.12
local BAR_TWEEN = TweenInfo.new(0.35)

local Cinematics = {}
local token = 0
local active = false
local topBar = nil
local bottomBar = nil
local caption = nil

local function ease(alpha)
    alpha = math.clamp(alpha, 0, 1)
    return alpha * alpha * (3 - 2 * alpha)
end

local function humanoidOf()
    local character = player.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

-- Desactiva o devuelve el movimiento del personaje (teclado, palanca táctil y mando).
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

local function setBars(visible)
    local barSize = visible and UDim2.fromScale(1, BAR_HEIGHT) or UDim2.fromScale(1, 0)
    TweenService:Create(topBar, BAR_TWEEN, {Size = barSize}):Play()
    TweenService:Create(bottomBar, BAR_TWEEN, {Size = barSize}):Play()
    caption.TextTransparency = visible and 0 or 1
end

local function restoreCamera()
    local ok = pcall(function()
        local camera = script.Parent.Parent:FindFirstChild("Camera")
        local module = camera and camera:FindFirstChild("FirstPerson")
        require(module).ResetCamera()
    end)
    if not ok then
        local camera = workspace.CurrentCamera
        local humanoid = humanoidOf()
        player.CameraMode = Enum.CameraMode.LockFirstPerson
        camera.CameraType = Enum.CameraType.Custom
        if humanoid then
            camera.CameraSubject = humanoid
        end
    end
end

-- Termina la escena actual y devuelve cámara y control. Se puede llamar de más.
-- keepCamera: la cámara ya la tomó otro (por ejemplo, la vista del escondite).
function Cinematics.Stop(keepCamera)
    if not active then
        return
    end
    active = false
    token += 1
    pcall(function()
        RunService:UnbindFromRenderStep(BIND_NAME)
    end)
    setBars(false)
    if not keepCamera and player:GetAttribute("Hidden") ~= true then
        restoreCamera()
    end
    setControls(true)
end

function Cinematics.IsPlaying()
    return active
end

local function validVector(value)
    return typeof(value) == "Vector3" and value.Magnitude < 1e6
end

function Cinematics.Play(data)
    if typeof(data) ~= "table" or not validVector(data.Focus) or not validVector(data.From) or not validVector(data.To) then
        return
    end
    local humanoid = humanoidOf()
    if not humanoid or humanoid.Health <= 0 or player:GetAttribute("Hidden") == true then
        return
    end
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end

    Cinematics.Stop()
    active = true
    token += 1
    local current = token
    local duration = math.clamp(tonumber(data.Duration) or 2.8, MIN_DURATION, MAX_DURATION)

    local startCFrame = camera.CFrame
    local shotStart = CFrame.lookAt(data.From, data.Focus)
    local shotEnd = CFrame.lookAt(data.To, data.Focus)
    local started = os.clock()

    caption.Text = typeof(data.Label) == "string" and string.sub(data.Label, 1, 80) or ""
    setBars(true)
    setControls(false)
    camera.CameraType = Enum.CameraType.Scriptable

    -- Corre después de la cámara en primera persona para tener la última palabra.
    RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 5, function()
        local elapsed = os.clock() - started
        if elapsed < BLEND_TIME then
            camera.CFrame = startCFrame:Lerp(shotStart, ease(elapsed / BLEND_TIME))
        else
            camera.CFrame = shotStart:Lerp(shotEnd, ease((elapsed - BLEND_TIME) / (duration - BLEND_TIME)))
        end
    end)

    task.delay(duration, function()
        if current == token then
            Cinematics.Stop()
        end
    end)
    -- Red de seguridad: pase lo que pase, el jugador recupera el control.
    task.delay(duration + SAFETY_MARGIN, function()
        if current == token then
            Cinematics.Stop()
        end
    end)
end

function Cinematics.Start()
    local root = Theme.Screen("NocturnaCinematic", 45)

    topBar = Theme.New("Frame", {
        Name = "TopBar",
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
    }, root)
    bottomBar = Theme.New("Frame", {
        Name = "BottomBar",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 0),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
    }, root)
    caption = Theme.Label(bottomBar, {
        Name = "Caption",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.9, 0, 0, 28),
        TextSize = 18,
        Font = Enum.Font.GothamMedium,
        TextColor3 = Theme.Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTransparency = 1,
    })

    Remotes.OnClient("Cinematic", function(data)
        Cinematics.Play(data)
    end)

    -- Si el jugador cae, se esconde o termina la partida, la escena se corta ya.
    Remotes.OnClient("DownState", function(data)
        if typeof(data) == "table" and (data.Down or data.Failed) then
            Cinematics.Stop()
        end
    end)
    Remotes.OnClient("HideState", function(hidden)
        if hidden then
            Cinematics.Stop(true)
        end
    end)
    ClientState.Subscribe("Game", function(state)
        if state.Phase ~= "Playing" then
            Cinematics.Stop()
        end
    end)
    player.CharacterAdded:Connect(function()
        Cinematics.Stop()
    end)
end

return Cinematics
