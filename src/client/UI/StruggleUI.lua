-- Forcejeo cuando una criatura te agarra: la secuencia de teclas, la barra para
-- soltarse y el tiempo que se escurre. Teclado (Q E R F ESPACIO), mando (X Y B RB
-- A) o botones táctiles grandes numerados. El cliente sólo manda "apreté esta
-- tecla para este paso": el servidor valida y decide; acá se predice para que la
-- respuesta sea inmediata y se corrige con lo que diga el servidor.
-- A los compañeros les aparece un aviso con el progreso de quien está atrapado.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CaptureConfig = require(Shared.Config.CaptureConfig)
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local AudioController = require(script.Parent.Parent.Effects.AudioController)
local CaptureCamera = require(script.Parent.Parent.Camera.CaptureCamera)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local ACTION = "NocturnaStruggle"
local MAX_CHIPS = 12
local CHIP = 54
local TOUCH_SIZE = 92
-- Sin teclas en vuelo durante este tiempo, manda el índice del servidor.
local RESYNC_AFTER = 0.25
local LOW_TIME = 0.35

-- Por nombre de tecla: así la búsqueda no depende de la identidad del EnumItem.
local KEY_NAMES = {
    Q = "Q", E = "E", R = "R", F = "F", Space = "Space",
    ButtonX = "Q", ButtonY = "E", ButtonB = "R", ButtonR1 = "F", ButtonA = "Space",
}
local BOUND_KEYS = {}
for name in pairs(KEY_NAMES) do
    table.insert(BOUND_KEYS, (Enum.KeyCode :: any)[name])
end

local StruggleUI = {}
local current = nil
local mode = Theme.IsTouch and "Touch" or "Keyboard"
local ui = {}
local banner = {}

local function creatureName(kind)
    local settings = MonsterConfig[kind]
    return settings and settings.DisplayName or "La criatura"
end

local function label(key)
    local display = CaptureConfig.Display[key]
    return display and display[mode] or key
end

local function victimName(userId)
    local other = Players:GetPlayerByUserId(userId)
    return other and other.DisplayName or "Un compañero"
end

-- Pantalla ---------------------------------------------------------------------

local function chip(parent, index)
    local frame = Theme.New("TextLabel", {
        Name = "Chip" .. index,
        Size = UDim2.fromOffset(CHIP, CHIP),
        BackgroundColor3 = Colors.Button,
        BorderSizePixel = 0,
        Font = Theme.Fonts.Title,
        TextSize = 20,
        TextColor3 = Colors.Text,
        TextScaled = false,
        Text = "",
        LayoutOrder = index,
        Visible = false,
    }, parent)
    Theme.Corner(frame, 6)
    Theme.Stroke(frame, Colors.Stroke, 2, 0)
    return frame
end

local function buildVictimPanel(root)
    local panel = Theme.New("Frame", {
        Name = "StrugglePanel",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, Theme.IsTouch and -(TOUCH_SIZE + 40) or -36),
        Size = UDim2.fromOffset(700, 190),
        BackgroundTransparency = 1,
        Visible = false,
    }, root)
    ui.Panel = panel

    ui.Title = Theme.Label(panel, {
        Name = "Title",
        Size = UDim2.new(1, 0, 0, 44),
        Font = Theme.Fonts.Display,
        TextSize = 40,
        TextColor3 = Colors.Danger,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = "",
    })
    ui.Hint = Theme.Label(panel, {
        Name = "Hint",
        Position = UDim2.fromOffset(0, 44),
        Size = UDim2.new(1, 0, 0, 22),
        TextSize = 16,
        TextColor3 = Colors.Text,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = "",
    })

    local lane = Theme.New("Frame", {
        Name = "Sequence",
        Position = UDim2.fromOffset(0, 72),
        Size = UDim2.new(1, 0, 0, CHIP + 8),
        BackgroundTransparency = 1,
    }, panel)
    Theme.New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
    }, lane)
    ui.Chips = {}
    for index = 1, MAX_CHIPS do
        ui.Chips[index] = chip(lane, index)
    end

    local escape = Theme.New("Frame", {
        Name = "EscapeBar",
        Position = UDim2.fromOffset(60, 142),
        Size = UDim2.new(1, -120, 0, 14),
        BackgroundColor3 = Colors.Track,
        BorderSizePixel = 0,
    }, panel)
    Theme.Corner(escape, 4)
    Theme.Stroke(escape, Colors.Stroke, 1, 0.1)
    ui.EscapeFill = Theme.New("Frame", {
        Name = "Fill",
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Colors.Exit,
        BorderSizePixel = 0,
    }, escape)
    Theme.Corner(ui.EscapeFill, 4)

    local timer = Theme.New("Frame", {
        Name = "TimeBar",
        Position = UDim2.fromOffset(60, 162),
        Size = UDim2.new(1, -120, 0, 8),
        BackgroundColor3 = Colors.Track,
        BorderSizePixel = 0,
    }, panel)
    Theme.Corner(timer, 3)
    ui.TimeFill = Theme.New("Frame", {
        Name = "Fill",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Colors.Accent,
        BorderSizePixel = 0,
    }, timer)
    Theme.Corner(ui.TimeFill, 3)
end

-- Botones táctiles: grandes, separados y numerados, con el color de su tecla.
local function buildTouchButtons(root)
    local holder = Theme.New("Frame", {
        Name = "StruggleButtons",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -20),
        Size = UDim2.fromOffset(#CaptureConfig.Keys * (TOUCH_SIZE + 14), TOUCH_SIZE),
        BackgroundTransparency = 1,
        Visible = false,
    }, root)
    Theme.New("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 14),
    }, holder)
    ui.TouchHolder = holder
    ui.TouchButtons = {}
    for index, key in ipairs(CaptureConfig.Keys) do
        local display = CaptureConfig.Display[key]
        local button = Theme.Button(holder, display.Touch, {
            Name = "Key" .. key,
            LayoutOrder = index,
            Size = UDim2.fromOffset(TOUCH_SIZE, TOUCH_SIZE),
            BackgroundColor3 = display.Color,
            BackgroundTransparency = 0.05,
            TextSize = 34,
            TextColor3 = Colors.Black,
        })
        Theme.Corner(button, TOUCH_SIZE / 2)
        button.Activated:Connect(function()
            StruggleUI.Press(key)
        end)
        ui.TouchButtons[key] = button
    end
end

-- Aviso para los compañeros: quién está atrapado y cuánto le falta.
local function buildBanner(root)
    local frame = Theme.Panel(root, {
        Name = "CaptureBanner",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 64),
        Size = UDim2.fromOffset(420, 58),
        Visible = false,
    }, true)
    banner.Frame = frame
    banner.Text = Theme.Label(frame, {
        Name = "Text",
        Position = UDim2.fromOffset(12, 6),
        Size = UDim2.new(1, -24, 0, 24),
        TextSize = 16,
        TextColor3 = Colors.Danger,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local track = Theme.New("Frame", {
        Name = "Track",
        Position = UDim2.fromOffset(20, 36),
        Size = UDim2.new(1, -40, 0, 10),
        BackgroundColor3 = Colors.Track,
        BorderSizePixel = 0,
    }, frame)
    Theme.Corner(track, 3)
    banner.Fill = Theme.New("Frame", {
        Name = "Fill",
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Colors.Exit,
        BorderSizePixel = 0,
    }, track)
    Theme.Corner(banner.Fill, 3)
end

-- Estado ------------------------------------------------------------------------

local function renderChips()
    if not current or not current.Sequence then
        for _, frame in ipairs(ui.Chips) do
            frame.Visible = false
        end
        return
    end
    local sequence = current.Sequence
    for index, frame in ipairs(ui.Chips) do
        local key = sequence[index]
        frame.Visible = key ~= nil
        if key then
            local display = CaptureConfig.Display[key]
            local done = index <= current.LocalIndex
            local upcoming = index == current.LocalIndex + 1
            frame.Text = done and "" or label(key)
            frame.TextSize = upcoming and 24 or 18
            frame.Size = upcoming and UDim2.fromOffset(CHIP + 10, CHIP + 10) or UDim2.fromOffset(CHIP, CHIP)
            frame.BackgroundColor3 = display.Color
            frame.BackgroundTransparency = done and 0.75 or (upcoming and 0 or 0.45)
            frame.TextColor3 = done and Colors.TextDim or Colors.Black
        end
    end
end

local function renderBars(now)
    if not current then
        return
    end
    local progress = current.Sequence and (current.LocalIndex / #current.Sequence) or 0
    ui.EscapeFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
    local left = current.Deadline and math.max(0, current.Deadline - now) or (current.TimeLimit or 1)
    local fraction = current.TimeLimit and current.TimeLimit > 0 and left / current.TimeLimit or 1
    ui.TimeFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
    local low = fraction < LOW_TIME
    ui.TimeFill.BackgroundColor3 = low and Colors.Danger or Colors.Accent
    if low and current.Phase == "Struggle" and now >= (current.NextTick or 0) then
        current.NextTick = now + 0.4
        AudioController.Play("StruggleTick")
    end
end

local function bindKeys(enabled)
    if enabled then
        -- Por encima de todo: mientras forcejea, F no prende la linterna ni ESPACIO salta.
        ContextActionService:BindActionAtPriority(ACTION, function(_, state, input)
            if state == Enum.UserInputState.Begin then
                local key = input.KeyCode and KEY_NAMES[input.KeyCode.Name]
                if key then
                    StruggleUI.Press(key)
                end
            end
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value + 100, table.unpack(BOUND_KEYS))
    else
        ContextActionService:UnbindAction(ACTION)
    end
end

local function showVictim(visible)
    ui.Panel.Visible = visible
    ui.TouchHolder.Visible = visible and mode == "Touch" and current ~= nil and current.Phase == "Struggle"
end

local function finishVictim(title, color, hold)
    if not current then
        return
    end
    bindKeys(false)
    current.Phase = "Done"
    ui.TouchHolder.Visible = false
    ui.Title.Text = title
    ui.Title.TextColor3 = color
    ui.Hint.Text = ""
    local finished = current
    task.delay(hold, function()
        if current == finished then
            current = nil
            showVictim(false)
        end
    end)
end

local function sync(data)
    if not current or data.Id ~= current.Id then
        return
    end
    if type(data.TimeLeft) == "number" then
        current.Deadline = os.clock() + data.TimeLeft
    end
    if type(data.TimeLimit) == "number" then
        current.TimeLimit = data.TimeLimit
    end
    if type(data.Index) == "number" and os.clock() - current.LastSent > RESYNC_AFTER then
        current.LocalIndex = data.Index
    end
    renderChips()
end

local function onVictimUpdate(data)
    local event = data.Event
    if event == "Begin" then
        bindKeys(false)
        current = {
            Id = data.Id,
            Kind = data.Kind,
            Phase = "Grab",
            LocalIndex = 0,
            LastSent = -math.huge,
            LastPress = -math.huge,
        }
        local profile = CaptureConfig.Creatures[data.Kind] or {}
        ui.Title.Text = string.upper(creatureName(data.Kind)) .. " TE AGARRÓ"
        ui.Title.TextColor3 = Colors.Danger
        ui.Hint.Text = profile.Verb and ("..." .. profile.Verb) or ""
        renderChips()
        showVictim(true)
        AudioController.Play("CaptureGrab")
        AudioController.Play("Heartbeat")
        CaptureCamera.Begin(data)
        return
    end
    if not current or data.Id ~= current.Id then
        return
    end

    CaptureCamera.Sync(data)
    if event == "Struggle" then
        current.Phase = "Struggle"
        current.Sequence = data.Sequence
        current.LocalIndex = data.Index or 0
        ui.Title.Text = "¡SOLTATE!"
        ui.Hint.Text = mode == "Touch" and "Tocá los botones en orden, rápido" or "Apretá las teclas en orden, rápido"
        sync(data)
        showVictim(true)
        bindKeys(true)
    elseif event == "Progress" then
        sync(data)
    elseif event == "Escaped" then
        current.LocalIndex = current.Sequence and #current.Sequence or 0
        renderChips()
        AudioController.Play("CaptureHit")
        CaptureCamera.Finish("Escaped")
        finishVictim("¡TE SOLTASTE! ¡CORRÉ!", Colors.Exit, 1.2)
    elseif event == "Failing" then
        AudioController.Play("CaptureDevour")
        finishVictim("NO...", Colors.Blood, 1.4)
    elseif event == "Failed" then
        CaptureCamera.Finish("Failed")
        finishVictim("", Colors.Blood, 0.1)
    elseif event == "Ended" then
        CaptureCamera.Finish("Ended")
        finishVictim("", Colors.Text, 0)
    end
end

local bannerToken = 0
local function onTeammateUpdate(data)
    local event = data.Event
    local name = victimName(data.Victim)
    bannerToken += 1
    local mine = bannerToken
    banner.Fill.Size = UDim2.fromScale(math.clamp(tonumber(data.Progress) or 0, 0, 1), 1)
    if event == "Begin" or event == "Struggle" or event == "Progress" then
        banner.Text.Text = "¡" .. name .. " está atrapado por " .. creatureName(data.Kind) .. "!"
        banner.Text.TextColor3 = Colors.Danger
        banner.Frame.Visible = true
        if event == "Begin" and typeof(data.Monster) == "Instance" and data.Monster.PrimaryPart then
            AudioController.PlayAt("CaptureGrab", data.Monster.PrimaryPart.Position)
        end
        return
    end
    if event == "Escaped" then
        banner.Text.Text = name .. " se soltó."
        banner.Text.TextColor3 = Colors.Exit
    elseif event == "Failing" or event == "Failed" then
        banner.Text.Text = name .. " no pudo soltarse."
        banner.Text.TextColor3 = Colors.Blood
    else
        banner.Frame.Visible = false
        return
    end
    task.delay(2, function()
        if mine == bannerToken then
            banner.Frame.Visible = false
        end
    end)
end

-- Una tecla (o botón) del forcejeo.
function StruggleUI.Press(key)
    if not current or current.Phase ~= "Struggle" or not current.Sequence then
        return
    end
    local now = os.clock()
    -- Lo que el servidor descartaría por spam ni se manda.
    if now - current.LastPress < CaptureConfig.MinPressInterval then
        return
    end
    current.LastPress = now
    current.LastSent = now
    local step = current.LocalIndex + 1
    Remotes.FireServer("CaptureInput", current.Id, step, key)

    if current.Sequence[step] == key then
        current.LocalIndex = step
        AudioController.Play("StruggleEffort")
        CaptureCamera.Jolt(0.6)
    else
        current.LocalIndex = math.max(0, current.LocalIndex - 1)
        AudioController.Play("StruggleMiss")
        CaptureCamera.Jolt(1.4)
        ui.Hint.Text = "¡No! ¡Esa no era!"
    end
    renderChips()
end

-- Para las pruebas y para otros módulos: la captura propia en curso.
function StruggleUI.Current()
    return current
end

function StruggleUI.Start()
    local root = Theme.Screen("NocturnaStruggle", 44)
    buildVictimPanel(root)
    buildTouchButtons(root)
    buildBanner(root)

    -- Con el mando aparecen los botones del mando; con el teclado, sus letras.
    UserInputService.InputBegan:Connect(function(input)
        local inputType = input.UserInputType
        local newMode = mode
        if inputType == Enum.UserInputType.Gamepad1 then
            newMode = "Gamepad"
        elseif inputType == Enum.UserInputType.Keyboard then
            newMode = "Keyboard"
        elseif inputType == Enum.UserInputType.Touch then
            newMode = "Touch"
        end
        if newMode ~= mode then
            mode = newMode
            renderChips()
            if current then
                showVictim(true)
            end
        end
    end)

    Remotes.OnClient("CaptureUpdate", function(data)
        if typeof(data) ~= "table" or type(data.Id) ~= "number" then
            return
        end
        if data.Victim == player.UserId then
            onVictimUpdate(data)
        else
            onTeammateUpdate(data)
        end
    end)

    RunService.RenderStepped:Connect(function()
        if current then
            renderBars(os.clock())
        end
    end)

    -- Reapareció o se cortó la partida: nada queda en pantalla ni con teclas tomadas.
    player.CharacterAdded:Connect(function()
        if current then
            bindKeys(false)
            current = nil
            showVictim(false)
        end
    end)
end

return StruggleUI
