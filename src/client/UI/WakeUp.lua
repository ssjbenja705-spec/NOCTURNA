-- Al empezar cada capítulo el jugador se despierta: negro total, los párpados se
-- abren, se entrecierran y vuelven a abrirse; el desenfoque se va, la cámara se
-- mece y el sonido pasa de apagado a nítido. Dura unos cuatro segundos.
-- CutsceneUI lo dispara cuando termina el título del capítulo.
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Theme = require(script.Parent.Theme)
local AudioController = require(script.Parent.Parent.Effects.AudioController)

local Colors = Theme.Colors

-- Apertura de los párpados (0 cerrados, 1 abiertos) y desenfoque de cada tramo.
local STEPS = {
    {Gap = 0.16, Blur = 22, Time = 0.8},
    {Gap = 0.03, Blur = 26, Time = 0.35},
    {Gap = 0.42, Blur = 14, Time = 0.9},
    {Gap = 0.24, Blur = 16, Time = 0.4},
    {Gap = 1, Blur = 0, Time = 1.3},
}
local HOLD = 0.35
local LID_TRAVEL = 0.62
local SOUND_GROUPS = {"NocturnaMusic", "NocturnaEffects"}

local WakeUp = {}
WakeUp.Duration = HOLD
for _, step in ipairs(STEPS) do
    WakeUp.Duration += step.Time
end

local holder = nil
local topLid = nil
local bottomLid = nil
local sides = {}
local blur = nil
local equalizers = {}
local token = 0
local swayStart = 0
local swayUntil = 0

local function lidPositions(gap)
    local offset = gap * LID_TRAVEL
    return UDim2.fromScale(0.5, 0.5 - offset), UDim2.fromScale(0.5, 0.5 + offset)
end

local function setGap(gap, seconds)
    local top, bottom = lidPositions(gap)
    local shade = math.clamp(gap * 1.4, 0, 1)
    if seconds and seconds > 0 then
        Theme.Tween(topLid, seconds, {Position = top}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        Theme.Tween(bottomLid, seconds, {Position = bottom}, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
        for _, side in ipairs(sides) do
            Theme.Tween(side, seconds, {BackgroundTransparency = shade}, Enum.EasingStyle.Sine)
        end
    else
        topLid.Position = top
        bottomLid.Position = bottom
        for _, side in ipairs(sides) do
            side.BackgroundTransparency = shade
        end
    end
end

local function buildLid(parent, name, anchorY)
    local lid = Theme.New("Frame", {
        Name = name,
        AnchorPoint = Vector2.new(0.5, anchorY),
        Size = UDim2.fromScale(1.1, 0.6),
        BackgroundColor3 = Colors.Black,
        BorderSizePixel = 0,
    }, parent)
    -- Borde difuso: el párpado no corta como una regla.
    local edge = Theme.New("Frame", {
        Name = "Edge",
        AnchorPoint = Vector2.new(0, anchorY == 1 and 0 or 1),
        Position = UDim2.fromScale(0, anchorY == 1 and 1 or 0),
        Size = UDim2.fromScale(1, 0.2),
        BackgroundColor3 = Colors.Black,
        BorderSizePixel = 0,
    }, lid)
    Theme.New("UIGradient", {
        Rotation = anchorY == 1 and 90 or -90,
        Transparency = NumberSequence.new(0, 1),
    }, edge)
    return lid
end

local function soundGroups()
    local result = {}
    for _, name in ipairs(SOUND_GROUPS) do
        local group = SoundService:FindFirstChild(name)
        if group and group:IsA("SoundGroup") then
            table.insert(result, group)
        end
    end
    return result
end

-- El sonido arranca apagado, como con los oídos tapados, y se aclara.
local function muffle(seconds)
    for _, group in ipairs(soundGroups()) do
        local equalizer = equalizers[group]
        if not equalizer or equalizer.Parent ~= group then
            equalizer = Instance.new("EqualizerSoundEffect")
            equalizer.Name = "NocturnaWakeMuffle"
            equalizer.Parent = group
            equalizers[group] = equalizer
        end
        equalizer.HighGain = -45
        equalizer.MidGain = -18
        equalizer.LowGain = 0
        equalizer.Enabled = true
        Theme.Tween(equalizer, seconds, {HighGain = 0, MidGain = 0}, Enum.EasingStyle.Linear)
    end
end

local function release()
    holder.Visible = false
    if blur then
        blur.Enabled = false
        blur.Size = 0
    end
    for _, equalizer in pairs(equalizers) do
        equalizer.Enabled = false
    end
end

local function ensureBlur()
    if not blur or blur.Parent ~= Lighting then
        blur = Instance.new("BlurEffect")
        blur.Name = "NocturnaWakeBlur"
        blur.Size = 0
        blur.Enabled = false
        blur.Parent = Lighting
    end
    return blur
end

-- Balanceo de la cámara. La cámara de Roblox arranca cada cuadro desde hacia dónde
-- miraba, así que el balanceo del cuadro anterior se deshace antes de que corra
-- (si no, se acumularía y el jugador terminaría mirando al piso) y se vuelve a
-- aplicar después. Cuando termina, la cámara queda exactamente como estaba.
local appliedOffset = nil
local appliedCamera = nil

local function undoSway()
    if appliedOffset then
        local camera = workspace.CurrentCamera
        if camera and camera == appliedCamera then
            camera.CFrame = camera.CFrame * appliedOffset:Inverse()
        end
        appliedOffset = nil
        appliedCamera = nil
    end
end

local function applySway()
    local now = os.clock()
    local camera = workspace.CurrentCamera
    if now >= swayUntil or not camera then
        return
    end
    local elapsed = now - swayStart
    local strength = math.clamp((swayUntil - now) / math.max(0.01, swayUntil - swayStart), 0, 1)
    local roll = math.sin(elapsed * 1.7) * 0.06 * strength
    local pitch = (math.sin(elapsed * 1.1 + 0.6) * 0.035 - 0.025) * strength
    appliedOffset = CFrame.Angles(pitch, 0, roll)
    appliedCamera = camera
    camera.CFrame = camera.CFrame * appliedOffset
end

function WakeUp.IsPlaying()
    return holder ~= nil and holder.Visible
end

-- Corta el despertar (por ejemplo, si empieza otra escena).
function WakeUp.Cancel()
    token += 1
    swayUntil = 0
    if holder then
        release()
    end
end

-- Cierra los ojos al instante y empieza a abrirlos. Devuelve false si no pudo.
function WakeUp.Play()
    if not holder then
        return false
    end
    token += 1
    local current = token

    holder.Visible = true
    setGap(0)

    local useBlur = not Theme.IsLowQuality()
    if useBlur then
        ensureBlur()
        blur.Size = 28
        blur.Enabled = true
    end
    muffle(WakeUp.Duration)
    swayStart = os.clock()
    swayUntil = swayStart + WakeUp.Duration + 0.8

    task.spawn(function()
        task.wait(HOLD)
        if current ~= token then
            return
        end
        AudioController.Play("Breath")
        for index, step in ipairs(STEPS) do
            if current ~= token then
                return
            end
            setGap(step.Gap, step.Time)
            if useBlur and blur then
                Theme.Tween(blur, step.Time, {Size = step.Blur}, Enum.EasingStyle.Sine)
            end
            if index == 3 then
                AudioController.Play("Heartbeat")
            end
            task.wait(step.Time)
        end
        if current == token then
            release()
        end
    end)
    return true
end

function WakeUp.Start()
    local root = Theme.Screen("NocturnaWake", 45, true)
    holder = Theme.New("Frame", {
        Name = "Eyes",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    }, root)

    -- Las esquinas se oscurecen junto con los párpados: se lee como un ojo.
    for _, side in ipairs({{0, 0}, {1, 180}}) do
        local frame = Theme.New("Frame", {
            Name = "Side",
            AnchorPoint = Vector2.new(side[1], 0),
            Position = UDim2.fromScale(side[1], 0),
            Size = UDim2.fromScale(0.26, 1),
            BackgroundColor3 = Colors.Black,
            BorderSizePixel = 0,
        }, holder)
        Theme.New("UIGradient", {
            Rotation = side[2],
            Transparency = NumberSequence.new(0, 1),
        }, frame)
        table.insert(sides, frame)
    end

    topLid = buildLid(holder, "TopLid", 1)
    bottomLid = buildLid(holder, "BottomLid", 0)
    setGap(1)

    RunService:BindToRenderStep("NocturnaWakeSwayUndo", Enum.RenderPriority.First.Value, undoSway)
    RunService:BindToRenderStep("NocturnaWakeSway", Enum.RenderPriority.Camera.Value + 2, applySway)
end

return WakeUp
