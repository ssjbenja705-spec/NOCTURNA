-- Lector de documentos (papel viejo, escrito a máquina) y diario con todo lo
-- encontrado en la campaña, ordenado por capítulo.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DocumentConfig = require(Shared.Config.DocumentConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors
local ENTRY_HEIGHT = Theme.IsTouch and 46 or 40

local JournalUI = {}
local reader = nil
local listPanel = nil
local titleLabel = nil
local bodyLabel = nil
local listFrame = nil

local function formatBody(text)
    return (string.gsub(Theme.Escape(text), "~~(.-)~~", "<s>%1</s>"))
end

function JournalUI.OpenDocument(documentId)
    local document = DocumentConfig[documentId]
    if not document then
        return
    end

    titleLabel.Text = document.Title
    bodyLabel.Text = formatBody(document.Body)
    reader.Visible = true
    Theme.SetModal("Reader", true)
end

local function closeReader()
    reader.Visible = false
    Theme.SetModal("Reader", false)
end

local function setJournalOpen(open)
    listPanel.Visible = open
    Theme.SetModal("Journal", open)
end

local function sortedIds()
    local ids = {}
    for id in pairs(DocumentConfig) do
        table.insert(ids, id)
    end
    table.sort(ids)
    return ids
end

local function chapterOf(id)
    return tonumber(string.match(id, "(%d)")) or 0
end

local function renderList(profile)
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    local order = 0
    local height = 0
    local lastChapter = nil
    for number, id in ipairs(sortedIds()) do
        local chapter = chapterOf(id)
        if chapter ~= lastChapter then
            lastChapter = chapter
            order += 1
            Theme.Label(listFrame, {
                Name = "Chapter",
                Size = UDim2.new(1, -8, 0, 22),
                Text = Theme.Upper(string.format("Capítulo %d · %s", chapter, GameConfig.Chapters[chapter] or "")),
                TextSize = 13,
                TextColor3 = Colors.Accent,
                TextYAlignment = Enum.TextYAlignment.Bottom,
                LayoutOrder = order,
            })
            height += 22 + 6
        end

        local document = DocumentConfig[id]
        local found = profile.Documents[id] == true
        order += 1
        local button = Theme.Button(listFrame, string.format("Nº %02d   %s", number, found and document.Title or "— sin encontrar —"), {
            Name = "Entry",
            Size = UDim2.new(1, -8, 0, ENTRY_HEIGHT),
            BackgroundColor3 = found and Colors.Button or Colors.Track,
            TextColor3 = found and Colors.Text or Colors.TextDim,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            AutoButtonColor = found,
            LayoutOrder = order,
        })
        Theme.New("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8)}, button)
        height += ENTRY_HEIGHT + 6

        if found then
            button.Activated:Connect(function()
                JournalUI.OpenDocument(id)
            end)
        end
    end

    listFrame.CanvasSize = UDim2.fromOffset(0, height)
end

-- Hoja de papel con manchas de café, cinta en las esquinas y letra de máquina.
local function buildReader(root)
    reader = Theme.New("Frame", {
        Name = "Reader",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(580, 440),
        BackgroundColor3 = Colors.Paper,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 5,
    }, root)
    Theme.Corner(reader, 2)

    titleLabel = Theme.Label(reader, {
        Name = "Title",
        Position = UDim2.fromOffset(28, 22),
        Size = UDim2.new(1, -96, 0, 30),
        TextColor3 = Colors.Ink,
        Font = Theme.Fonts.Title,
        TextSize = 22,
        ZIndex = 6,
    })

    Theme.New("UIGradient", {
        Rotation = 70,
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 225, 205)),
            ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 250, 240)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 170, 130)),
        }),
    }, reader)

    -- Aros de café y una mancha de óxido.
    for _, stain in ipairs({{0.82, 0.78, 84}, {0.12, 0.88, 46}}) do
        local ring = Theme.New("Frame", {
            Name = "CoffeeRing",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(stain[1], stain[2]),
            Size = UDim2.fromOffset(stain[3], stain[3]),
            BackgroundTransparency = 1,
            ZIndex = 5,
        }, reader)
        Theme.New("UICorner", {CornerRadius = UDim.new(0.5, 0)}, ring)
        Theme.Stroke(ring, Colors.Grime, 3, 0.75)
    end
    Theme.Wear(reader, "lector", 2)

    -- Cinta de papel amarillenta sujetando la hoja.
    for _, tape in ipairs({{0, -14}, {1, 14}}) do
        Theme.New("Frame", {
            Name = "Tape",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(tape[1], tape[1] == 0 and 26 or -26, 0, 4),
            Size = UDim2.fromOffset(70, 20),
            Rotation = tape[2],
            BackgroundColor3 = Color3.fromRGB(226, 214, 160),
            BackgroundTransparency = 0.3,
            BorderSizePixel = 0,
            ZIndex = 7,
        }, reader)
    end

    Theme.New("Frame", {
        Name = "Line",
        Position = UDim2.fromOffset(28, 56),
        Size = UDim2.new(1, -56, 0, 1),
        BackgroundColor3 = Colors.Ink,
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        ZIndex = 6,
    }, reader)

    local scroller = Theme.New("ScrollingFrame", {
        Name = "Body",
        Position = UDim2.fromOffset(28, 64),
        Size = UDim2.new(1, -56, 1, -82),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Colors.Ink,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ZIndex = 6,
    }, reader)

    bodyLabel = Theme.Label(scroller, {
        Name = "Text",
        RichText = true,
        Size = UDim2.new(1, -10, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextColor3 = Colors.Ink,
        Font = Theme.Fonts.Body,
        TextSize = 17,
        LineHeight = 1.1,
        ZIndex = 6,
    })

    local close = Theme.CloseButton(reader, {
        Position = UDim2.new(1, -10, 0, 12),
        BackgroundColor3 = Colors.Ink,
        TextColor3 = Colors.Paper,
        ZIndex = 8,
    })
    close.Activated:Connect(closeReader)

    Theme.OnLayout(function(safe)
        reader.Size = UDim2.fromOffset(math.floor(math.min(580, safe.X - 16)), math.floor(math.min(440, safe.Y - 12)))
    end)
end

local function buildJournal(root)
    local panel, heading, close = Theme.Window(root, "Journal", "DIARIO", 460, 450)
    listPanel = panel
    close.Activated:Connect(function()
        setJournalOpen(false)
    end)

    listFrame = Theme.New("ScrollingFrame", {
        Name = "List",
        Position = UDim2.fromOffset(14, 58),
        Size = UDim2.new(1, -28, 1, -70),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        ScrollBarImageColor3 = Colors.Stroke,
        CanvasSize = UDim2.new(),
    }, listPanel)

    Theme.New("UIListLayout", {
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, listFrame)

    return heading
end

function JournalUI.Start()
    local root = Theme.Screen("NocturnaJournal", 11)
    buildReader(root)
    local heading = buildJournal(root)

    ClientState.Subscribe("Profile", function(profile)
        local found = 0
        for _ in pairs(profile.Documents) do
            found += 1
        end
        heading.Text = string.format("DIARIO  ·  %d / %d", found, GameConfig.Match.MaxDocuments)
        renderList(profile)
    end)

    Remotes.OnClient("DocumentOpen", JournalUI.OpenDocument)
    HUD.AddAction("Journal", "DIARIO", 2, function()
        setJournalOpen(not listPanel.Visible)
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then
            return
        end
        if input.KeyCode == Enum.KeyCode.J then
            setJournalOpen(not listPanel.Visible)
        end
    end)
end

return JournalUI
