-- Récords: victorias y mejores tiempos, con la estética de NOCTURNA (un informe
-- viejo manchado). Tres pestañas: lo personal, los mejores de este servidor y la
-- clasificación global por capítulo. Además el aviso de récord al terminar.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)
local HUD = require(script.Parent.HUD)
local Theme = require(script.Parent.Theme)
local AudioController = require(script.Parent.Parent.Effects.AudioController)

local Colors = Theme.Colors
local player = Players.LocalPlayer

local RecordsUI = {}
local data = nil
local tab = "Personal"
local chapter = 1

function RecordsUI.FormatTime(seconds)
    if typeof(seconds) ~= "number" then
        return "—"
    end
    local minutes = math.floor(seconds / 60)
    local rest = seconds - minutes * 60
    return string.format("%d:%04.1f", minutes, rest)
end
local formatTime = RecordsUI.FormatTime

local function chapterName(index)
    local names = data and data.Chapters
    return string.format("Capítulo %d%s", index, names and names[index] and (" · " .. names[index]) or "")
end

-- Texto de cada pestaña (lo prueba el motor de pruebas sin interfaz).
function RecordsUI.Lines(snapshot, which, index)
    local lines = {}
    if not snapshot then
        return {"Cargando..."}
    end
    if which == "Personal" then
        local personal = snapshot.Personal or {}
        table.insert(lines, string.format("Victorias totales: %d", personal.Wins or 0))
        local completed = 0
        for _ in pairs(personal.ChapterWins or {}) do
            completed += 1
        end
        table.insert(lines, string.format("Niveles completados: %d de %d", completed, #(snapshot.Chapters or {})))
        local best, bestChapter = nil, nil
        for key, time in pairs(personal.BestTimes or {}) do
            if not best or time < best then
                best, bestChapter = time, tonumber(key)
            end
        end
        table.insert(lines, best and string.format("Mejor tiempo: %s (capítulo %d)", formatTime(best), bestChapter) or "Mejor tiempo: —")
        local last = personal.LastWin
        table.insert(lines, last and string.format("Última victoria: capítulo %d en %s", last.Chapter, formatTime(last.Time)) or "Última victoria: —")
        table.insert(lines, string.format("Tiempo sobreviviendo: %d min", math.floor((personal.PlayTime or 0) / 60)))
        table.insert(lines, "")
        for chapterIndex = 1, #(snapshot.Chapters or {}) do
            local time = (personal.BestTimes or {})[chapterIndex] or (personal.BestTimes or {})[tostring(chapterIndex)]
            local wins = (personal.ChapterWins or {})[chapterIndex] or (personal.ChapterWins or {})[tostring(chapterIndex)] or 0
            table.insert(lines, string.format("%d. %s   récord %s   (%d)", chapterIndex, snapshot.Chapters[chapterIndex], formatTime(time), wins))
        end
        return lines
    end

    local list = (which == "Server" and snapshot.Server or snapshot.Global or {})[index] or {}
    if #list == 0 then
        table.insert(lines, which == "Server" and "Nadie terminó este capítulo en este servidor todavía." or "Sin tiempos todavía.")
        return lines
    end
    for position, entry in ipairs(list) do
        local mark = player and entry.UserId == player.UserId and "  ◄ vos" or ""
        table.insert(lines, string.format("%2d.  %-18s %s%s", position, tostring(entry.Name), formatTime(entry.Time), mark))
    end
    return lines
end

function RecordsUI.Start()
    local root = Theme.Screen("NocturnaRecords", 12)
    local panel, _, closeButton = Theme.Window(root, "Records", "RÉCORDS", 520, 420)

    local tabs = {}
    local tabNames = {{"Personal", "PERSONAL"}, {"Server", "SERVIDOR"}, {"Global", "GLOBAL"}}
    for index, info in ipairs(tabNames) do
        tabs[info[1]] = Theme.Button(panel, info[2], {
            Position = UDim2.new((index - 1) / 3, index == 1 and 14 or 4, 0, 56),
            Size = UDim2.new(1 / 3, -18, 0, 36),
            TextSize = 15,
        })
    end

    local chapterRow = Theme.New("Frame", {
        Name = "Chapter",
        Position = UDim2.fromOffset(14, 98),
        Size = UDim2.new(1, -28, 0, 34),
        BackgroundTransparency = 1,
    }, panel)
    local previous = Theme.Button(chapterRow, "<", {Size = UDim2.fromOffset(40, 34), TextSize = 18})
    local nextButton = Theme.Button(chapterRow, ">", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(40, 34),
        TextSize = 18,
    })
    local chapterLabel = Theme.Label(chapterRow, {
        Position = UDim2.fromOffset(48, 0),
        Size = UDim2.new(1, -96, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextColor3 = Colors.Accent,
        TextSize = 16,
    })

    local body = Theme.New("ScrollingFrame", {
        Name = "Body",
        Position = UDim2.fromOffset(14, 138),
        Size = UDim2.new(1, -28, 1, -150),
        BackgroundColor3 = Colors.Track,
        BackgroundTransparency = 0.3,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
    }, panel)
    local text = Theme.Label(body, {
        Name = "Text",
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextSize = 15,
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        Font = Theme.Fonts.Mono,
    })

    local function render()
        for name, button in pairs(tabs) do
            button.BackgroundColor3 = name == tab and Colors.ButtonActive or Colors.Button
        end
        chapterRow.Visible = tab ~= "Personal"
        body.Position = UDim2.fromOffset(14, tab == "Personal" and 98 or 138)
        body.Size = UDim2.new(1, -28, 1, tab == "Personal" and -110 or -150)
        chapterLabel.Text = chapterName(chapter)
        text.Text = table.concat(RecordsUI.Lines(data, tab, chapter), "\n")
    end

    for name, button in pairs(tabs) do
        button.Activated:Connect(function()
            tab = name
            render()
        end)
    end
    previous.Activated:Connect(function()
        local count = data and #(data.Chapters or {}) or 5
        chapter = chapter > 1 and chapter - 1 or count
        render()
    end)
    nextButton.Activated:Connect(function()
        local count = data and #(data.Chapters or {}) or 5
        chapter = chapter < count and chapter + 1 or 1
        render()
    end)

    local function close()
        panel.Visible = false
        Theme.SetModal("Records", false)
    end
    closeButton.Activated:Connect(close)

    HUD.AddAction("Records", "RÉCORDS", 6, function()
        if panel.Visible then
            close()
            return
        end
        panel.Visible = true
        Theme.SetModal("Records", true)
        render()
        Remotes.FireServer("RecordsRequest")
    end)

    Remotes.OnClient("RecordsData", function(snapshot)
        data = snapshot
        render()
    end)

    -- Aviso al terminar un capítulo: récord personal y, más grande, mejor del mundo.
    local banner = Theme.Panel(root, {
        Name = "RecordBanner",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, -120),
        Size = UDim2.fromOffset(460, 96),
        Visible = false,
    })
    local bannerTitle = Theme.Label(banner, {
        Position = UDim2.fromOffset(16, 8),
        Size = UDim2.new(1, -32, 0, 44),
        Font = Theme.Fonts.Display,
        TextSize = 34,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextColor3 = Colors.Accent,
    })
    local bannerBody = Theme.Label(banner, {
        Position = UDim2.fromOffset(16, 54),
        Size = UDim2.new(1, -32, 0, 30),
        TextSize = 16,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local bannerToken = 0
    Remotes.OnClient("RecordResult", function(result)
        if type(result) ~= "table" or not (result.PersonalBest or result.GlobalBest) then
            return
        end
        bannerToken += 1
        local mine = bannerToken
        if result.GlobalBest then
            bannerTitle.Text = "¡MEJOR TIEMPO DEL MUNDO!"
            bannerTitle.TextColor3 = Colors.Danger
            banner.Size = UDim2.fromOffset(520, 110)
        else
            bannerTitle.Text = "NUEVO RÉCORD PERSONAL"
            bannerTitle.TextColor3 = Colors.Accent
            banner.Size = UDim2.fromOffset(460, 96)
        end
        bannerBody.Text = string.format("Capítulo %d en %s%s%s", result.Chapter or 0, formatTime(result.Time),
            result.Previous and ("  (antes " .. formatTime(result.Previous) .. ")") or "",
            result.GlobalRank and ("  ·  puesto " .. result.GlobalRank .. " global") or "")
        banner.Visible = true
        AudioController.Play("ObjectiveDone")
        TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Back), {Position = UDim2.new(0.5, 0, 0, 70)}):Play()
        task.delay(result.GlobalBest and 7 or 5, function()
            if mine ~= bannerToken then
                return
            end
            local away = TweenService:Create(banner, TweenInfo.new(0.4), {Position = UDim2.new(0.5, 0, 0, -120)})
            away.Completed:Connect(function()
                if mine == bannerToken then
                    banner.Visible = false
                end
            end)
            away:Play()
        end)
    end)
end

return RecordsUI
