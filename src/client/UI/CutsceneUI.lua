-- Escenas a pantalla negra: prólogo, títulos de capítulo, finales y créditos.
-- Cuando termina el título de un capítulo, el negro se corta y el jugador abre los
-- ojos (WakeUp).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local Theme = require(script.Parent.Theme)
local WakeUp = require(script.Parent.WakeUp)

local Colors = Theme.Colors
local TYPE_SPEED = 38

local CutsceneUI = {}
local curtain = nil
local caption = nil
local title = nil
local subtitle = nil
local rule = nil
local token = 0

local function setTexts(titleText, captionText, subtitleText)
    Theme.StopTyping(caption)
    Theme.StopTyping(subtitle)
    title.Text = titleText or ""
    caption.Text = captionText or ""
    subtitle.Text = subtitleText or ""
    rule.Visible = titleText ~= nil and titleText ~= ""
end

local function fadeCurtain(transparency)
    Theme.Tween(curtain, 0.6, {BackgroundTransparency = transparency})
end

-- Cada línea se escribe a máquina, queda un momento y se apaga. Dura "hold".
local function showLine(label, text, hold)
    label.TextTransparency = 0
    Theme.Typewrite(label, text, TYPE_SPEED)
    task.wait(math.max(0.2, hold - 0.8))
    Theme.Tween(label, 0.7, {TextTransparency = 1})
    task.wait(0.8)
end

local function runLines(lines, lineTime, current)
    for _, line in ipairs(lines) do
        if current ~= token then
            return false
        end
        showLine(caption, line, lineTime)
    end
    return true
end

local function finish(current)
    if current == token then
        fadeCurtain(1)
        task.wait(0.6)
        if current == token then
            curtain.Visible = false
            setTexts()
        end
    end
end

local function start()
    token += 1
    WakeUp.Cancel()
    curtain.Visible = true
    curtain.BackgroundTransparency = 0
    title.TextTransparency = 0
    caption.TextTransparency = 0
    subtitle.TextTransparency = 0
    setTexts()
    return token
end

local PLAYERS = {}

function PLAYERS.Prologue(data)
    local current = start()
    if runLines(data.Lines, data.LineTime, current) then
        finish(current)
    end
end

function PLAYERS.ChapterTitle(data)
    local current = start()
    setTexts(data.Name, Theme.Upper("Capítulo " .. tostring(data.Count or "")))
    Theme.Typewrite(subtitle, tostring(data.Description or ""), TYPE_SPEED)
    task.wait(data.Duration)
    if current ~= token then
        return
    end

    -- El negro del título se vuelve el de los ojos cerrados: no hay corte visible.
    if WakeUp.Play() then
        curtain.Visible = false
        setTexts()
    else
        finish(current)
    end
end

function PLAYERS.Ending(data)
    local current = start()
    if not runLines(data.Lines, data.LineTime, current) then
        return
    end

    setTexts(data.Title, "FINAL", "NOCTURNA: EL ÚLTIMO RECUERDO\nGracias por no dejarla sola.")
    task.wait(math.max(0, data.Duration - #data.Lines * data.LineTime))
    finish(current)
end

function CutsceneUI.Start()
    local root = Theme.Screen("NocturnaCutscene", 50, true)

    curtain = Theme.New("Frame", {
        Name = "Curtain",
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Colors.Black,
        BorderSizePixel = 0,
        Visible = false,
    }, root)

    -- Un resplandor rojo muy apagado desde abajo, como una luz de emergencia.
    local glow = Theme.New("Frame", {
        Name = "Glow",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 0.45),
        BackgroundColor3 = Colors.Blood,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
    }, curtain)
    Theme.New("UIGradient", {
        Rotation = -90,
        Transparency = NumberSequence.new(0, 1),
    }, glow)

    caption = Theme.Label(curtain, {
        Name = "Caption",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.36),
        Size = UDim2.new(0.8, 0, 0, 96),
        TextSize = 21,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    title = Theme.Title(curtain, {
        Name = "Title",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.92, 0, 0, 130),
        TextSize = 62,
        TextColor3 = Colors.Danger,
        TextStrokeColor3 = Colors.Black,
        TextStrokeTransparency = 0.4,
    })
    rule = Theme.Rule(curtain, UDim2.new(0.3, 0, 0.6, 0), UDim2.new(0.4, 0, 0, 6))
    rule.Visible = false
    subtitle = Theme.Label(curtain, {
        Name = "Subtitle",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.64),
        Size = UDim2.new(0.74, 0, 0, 70),
        TextSize = 17,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
    })

    Theme.Grain(curtain, 16, function()
        return curtain.Visible
    end)

    Remotes.OnClient("Cutscene", function(data)
        local run = typeof(data) == "table" and PLAYERS[data.Kind]
        if run then
            task.spawn(run, data)
        end
    end)
end

return CutsceneUI
