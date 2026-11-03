-- Escenas a pantalla negra: prólogo, títulos de capítulo, finales y créditos.
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local FADE = TweenInfo.new(0.8)

local CutsceneUI = {}
local curtain = nil
local caption = nil
local title = nil
local subtitle = nil
local token = 0

local function setTexts(titleText, captionText, subtitleText)
    title.Text = titleText or ""
    caption.Text = captionText or ""
    subtitle.Text = subtitleText or ""
end

local function fadeCurtain(transparency)
    TweenService:Create(curtain, TweenInfo.new(0.6), {BackgroundTransparency = transparency}):Play()
end

local function showLine(label, text, hold)
    label.Text = text
    label.TextTransparency = 1
    TweenService:Create(label, FADE, {TextTransparency = 0}):Play()
    task.wait(hold - 0.8)
    TweenService:Create(label, FADE, {TextTransparency = 1}):Play()
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
    setTexts(data.Name, string.upper(data.Count or ""), data.Description)
    task.wait(data.Duration)
    finish(current)
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
    local root = Theme.Screen("NocturnaCutscene", 50)

    curtain = Theme.New("Frame", {
        Name = "Curtain",
        Position = UDim2.fromScale(0, 0),
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        Visible = false,
    }, root)

    caption = Theme.Label(curtain, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.42),
        Size = UDim2.new(0.8, 0, 0, 90),
        TextSize = 20,
        Font = Enum.Font.GothamMedium,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    title = Theme.Label(curtain, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.53),
        Size = UDim2.new(0.9, 0, 0, 56),
        TextSize = 38,
        Font = Enum.Font.GothamBold,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    subtitle = Theme.Label(curtain, {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.65),
        Size = UDim2.new(0.8, 0, 0, 56),
        TextSize = 15,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    Remotes.OnClient("Cutscene", function(data)
        local run = typeof(data) == "table" and PLAYERS[data.Kind]
        if run then
            task.spawn(run, data)
        end
    end)
end

return CutsceneUI
