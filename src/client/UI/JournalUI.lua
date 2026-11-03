-- Lector de documentos y diario con todo lo encontrado en la campaña.
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DocumentConfig = require(Shared.Config.DocumentConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)

local Colors = Theme.Colors

local JournalUI = {}
local reader = nil
local listPanel = nil
local titleLabel = nil
local bodyLabel = nil
local listFrame = nil
local rendered = 0

local function formatBody(text)
    return (string.gsub(text, "~~(.-)~~", "<s>%1</s>"))
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

local function renderList(profile)
    for _, child in ipairs(listFrame:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    rendered = 0
    for _, id in ipairs(sortedIds()) do
        local document = DocumentConfig[id]
        local found = profile.Documents[id] == true
        local button = Theme.Button(listFrame, found and document.Title or "— sin encontrar —", {
            Size = UDim2.new(1, -8, 0, 42),
            BackgroundColor3 = found and Colors.Button or Colors.PanelLight,
            TextColor3 = found and Colors.Text or Colors.TextDim,
            TextSize = 12,
            LayoutOrder = rendered,
        })
        rendered += 1

        if found then
            button.Activated:Connect(function()
                JournalUI.OpenDocument(id)
            end)
        end
    end

    listFrame.CanvasSize = UDim2.fromOffset(0, rendered * 48)
end

local function buildReader(root)
    reader = Theme.New("Frame", {
        Name = "Reader",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(560, 430),
        BackgroundColor3 = Colors.Paper,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 5,
    }, root)
    Theme.Corner(reader, 4)

    titleLabel = Theme.Label(reader, {
        Position = UDim2.fromOffset(24, 18),
        Size = UDim2.new(1, -84, 0, 30),
        TextColor3 = Colors.Ink,
        Font = Enum.Font.SpecialElite,
        TextSize = 20,
        ZIndex = 6,
    })

    local scroller = Theme.New("ScrollingFrame", {
        Position = UDim2.fromOffset(24, 56),
        Size = UDim2.new(1, -48, 1, -72),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ZIndex = 6,
    }, reader)

    bodyLabel = Theme.Label(scroller, {
        RichText = true,
        Size = UDim2.new(1, -10, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextColor3 = Colors.Ink,
        Font = Enum.Font.SpecialElite,
        TextSize = 16,
        ZIndex = 6,
    })

    local close = Theme.Button(reader, "X", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 10),
        Size = UDim2.fromOffset(44, 44),
        ZIndex = 7,
    })
    close.Activated:Connect(closeReader)
end

local function buildJournal(root)
    listPanel = Theme.Panel(root, {
        Name = "Journal",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(420, 430),
        BackgroundTransparency = 0.05,
        Visible = false,
    })

    local heading = Theme.Label(listPanel, {
        Position = UDim2.fromOffset(16, 12),
        Size = UDim2.new(1, -70, 0, 24),
        Font = Enum.Font.GothamBold,
        TextSize = 16,
        Text = "DIARIO",
    })

    local close = Theme.Button(listPanel, "X", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(40, 40),
    })
    close.Activated:Connect(function()
        setJournalOpen(false)
    end)

    listFrame = Theme.New("ScrollingFrame", {
        Position = UDim2.fromOffset(12, 54),
        Size = UDim2.new(1, -24, 1, -66),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 5,
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
        heading.Text = string.format("DIARIO  %d / %d", found, GameConfig.Match.MaxDocuments)
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
