-- Subtítulos de radio y susurros, avisos breves y anuncios de administración.
-- Cada línea queda 10 segundos en pantalla (o hasta que se la toca) para que dé
-- tiempo a leerla en un teléfono, aunque el servidor mande la siguiente antes:
-- en ese caso se apilan hasta tres.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local IsTouch = Theme.IsTouch

local LINE_TIME = 10
local FADE_TIME = 0.5
local MAX_LINES = 3
local LINE_WIDTH = 580
local BACKING = 0.3

-- Cómo suena cada voz: la radio con estática, Alma y lo desconocido en susurros.
local STYLES = {
    Vos = {Tag = "VOS", Color = Color3.fromRGB(214, 206, 190)},
    Radio = {Tag = "RADIO", Color = Colors.Radio, Text = Color3.fromRGB(196, 222, 186), Italic = true, Static = true},
    Alma = {Tag = "ALMA", Color = Color3.fromRGB(232, 182, 124), Text = Color3.fromRGB(240, 214, 182), Italic = true},
    ["Dra. Vega"] = {Tag = "DRA. VEGA · GRABACIÓN", Color = Color3.fromRGB(172, 178, 206), Static = true},
    ["???"] = {Tag = "???", Color = Color3.fromRGB(198, 54, 46), Text = Color3.fromRGB(222, 150, 140), Italic = true},
}

local StoryUI = {}
StoryUI.LineTime = LINE_TIME

local subtitlesEnabled = true
local slots = {}
local order = 0
local showNotice = nil

local function styleFor(speaker)
    local style = STYLES[speaker]
    if style then
        return style
    end
    return {Tag = Theme.Upper(speaker or ""), Color = Colors.Accent}
end

local function hideSlot(slot)
    slot.Token += 1
    slot.Button.Visible = false
end

local function fadeSlot(slot, token)
    if slot.Token ~= token then
        return
    end
    Theme.Tween(slot.Button, FADE_TIME, {BackgroundTransparency = 1})
    Theme.Tween(slot.Text, FADE_TIME, {TextTransparency = 1})
    Theme.Tween(slot.Tag, FADE_TIME, {TextTransparency = 1})
    task.delay(FADE_TIME, function()
        if slot.Token == token then
            hideSlot(slot)
        end
    end)
end

local function pickSlot()
    local oldest = nil
    for _, slot in ipairs(slots) do
        if not slot.Button.Visible then
            return slot
        end
        if not oldest or slot.Button.LayoutOrder < oldest.Button.LayoutOrder then
            oldest = slot
        end
    end
    return oldest
end

function StoryUI.ShowLine(data)
    if not subtitlesEnabled or typeof(data) ~= "table" or #slots == 0 then
        return
    end

    local slot = pickSlot()
    order += 1
    slot.Token += 1
    local token = slot.Token

    local style = styleFor(data.Speaker)
    local text = Theme.Escape(data.Text)
    if style.Italic then
        text = "<i>" .. text .. "</i>"
    end

    slot.Tag.Text = style.Tag
    slot.Tag.TextColor3 = style.Color
    slot.Text.Text = text
    slot.Text.TextColor3 = style.Text or Colors.Text
    slot.Accent.BackgroundColor3 = style.Color
    slot.Static.Visible = style.Static == true
    for _, bar in ipairs(slot.Static:GetChildren()) do
        bar.BackgroundColor3 = style.Color
    end

    slot.Button.LayoutOrder = order
    slot.Button.BackgroundTransparency = BACKING
    slot.Text.TextTransparency = 0
    slot.Tag.TextTransparency = 0
    slot.Button.Visible = true

    -- La rayita de abajo se acorta mientras la línea sigue en pantalla.
    slot.Timer.BackgroundColor3 = style.Color
    slot.Timer.Size = UDim2.new(1, 0, 0, 2)
    Theme.Tween(slot.Timer, LINE_TIME, {Size = UDim2.new(0, 0, 0, 2)}, Enum.EasingStyle.Linear)

    task.delay(LINE_TIME, fadeSlot, slot, token)
end

function StoryUI.Clear()
    for _, slot in ipairs(slots) do
        hideSlot(slot)
    end
end

function StoryUI.Notice(text, duration)
    if showNotice then
        showNotice(text, duration or 3.5)
    end
end

local function buildLine(parent, index)
    local button = Theme.New("TextButton", {
        Name = "Line",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Colors.Black,
        BackgroundTransparency = BACKING,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Visible = false,
        LayoutOrder = index,
    }, parent)
    Theme.Corner(button, 3)
    Theme.New("UIPadding", {
        PaddingTop = UDim.new(0, 6),
        PaddingBottom = UDim.new(0, 9),
        PaddingLeft = UDim.new(0, 16),
        PaddingRight = UDim.new(0, 14),
    }, button)
    Theme.New("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.75, 0.1),
            NumberSequenceKeypoint.new(1, 0.6),
        }),
    }, button)

    local accent = Theme.New("Frame", {
        Name = "Accent",
        Position = UDim2.new(0, -12, 0, 2),
        Size = UDim2.new(0, 3, 1, -2),
        BorderSizePixel = 0,
    }, button)

    -- Tres barritas de estática para la radio y las grabaciones.
    local static = Theme.New("Frame", {
        Name = "Static",
        Size = UDim2.fromOffset(16, 14),
        BackgroundTransparency = 1,
        Visible = false,
    }, button)
    for bar, height in ipairs({0.45, 1, 0.7}) do
        Theme.New("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new((bar - 1) * 0.36, 0, 1, 0),
            Size = UDim2.new(0, 3, height, 0),
            BorderSizePixel = 0,
        }, static)
    end

    local tag = Theme.Label(button, {
        Name = "Tag",
        Position = UDim2.fromOffset(22, 0),
        Size = UDim2.new(1, -22, 0, 16),
        TextSize = 13,
        TextWrapped = false,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    local text = Theme.Label(button, {
        Name = "Body",
        RichText = true,
        Position = UDim2.fromOffset(0, 19),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextSize = 18,
        LineHeight = 1.05,
    })
    local timer = Theme.New("Frame", {
        Name = "Timer",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 6),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundTransparency = 0.4,
        BorderSizePixel = 0,
    }, button)

    local slot = {
        Button = button,
        Tag = tag,
        Text = text,
        Accent = accent,
        Static = static,
        Timer = timer,
        Token = 0,
    }
    -- Tocar (o hacer clic en) la línea la cierra sólo para este jugador.
    button.Activated:Connect(function()
        hideSlot(slot)
    end)
    return slot
end

local function fader(label, backing)
    local token = 0
    return function(text, duration)
        token += 1
        local current = token
        label.Text = text
        label.TextTransparency = 0
        backing.BackgroundTransparency = 0.35
        backing.Visible = true

        task.delay(duration, function()
            if current ~= token then
                return
            end
            Theme.Tween(label, 0.5, {TextTransparency = 1})
            Theme.Tween(backing, 0.5, {BackgroundTransparency = 1})
            task.delay(0.5, function()
                if current == token then
                    backing.Visible = false
                end
            end)
        end)
    end
end

function StoryUI.Start()
    local root = Theme.Screen("NocturnaStory", 46)

    local stack = Theme.New("Frame", {
        Name = "Subtitles",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, IsTouch and -112 or -26),
        Size = UDim2.fromOffset(LINE_WIDTH, 260),
        BackgroundTransparency = 1,
    }, root)
    Theme.New("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
    }, stack)
    for index = 1, MAX_LINES do
        slots[index] = buildLine(stack, index)
    end

    Theme.OnLayout(function(safe)
        stack.Size = UDim2.fromOffset(math.min(LINE_WIDTH, math.floor(safe.X - 40)), 260)
    end)

    local backing = Theme.New("Frame", {
        Name = "NoticeBacking",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 116),
        Size = UDim2.fromOffset(540, 40),
        BackgroundColor3 = Colors.Black,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
    }, root)
    Theme.New("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.2, 0),
            NumberSequenceKeypoint.new(0.8, 0),
            NumberSequenceKeypoint.new(1, 1),
        }),
    }, backing)
    local notice = Theme.Label(backing, {
        Name = "Notice",
        Size = UDim2.fromScale(1, 1),
        TextSize = 15,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTransparency = 1,
    })
    showNotice = fader(notice, backing)

    Remotes.OnClient("StoryDialogue", StoryUI.ShowLine)
    Remotes.OnClient("StoryNotice", function(text)
        showNotice(tostring(text), 3.5)
    end)
    Remotes.OnClient("AdminMessage", function(text)
        showNotice("ANUNCIO · " .. tostring(text), 5)
    end)

    ClientState.Subscribe("Profile", function(profile)
        subtitlesEnabled = profile.Settings.Subtitles
        if not subtitlesEnabled then
            StoryUI.Clear()
        end
    end)
end

return StoryUI
