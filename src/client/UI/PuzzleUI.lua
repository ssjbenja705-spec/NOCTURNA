-- Paneles de las pruebas. Funcionan con mouse y con toques: todo se hace con
-- botones grandes, y los cables además se pueden arrastrar. El cliente sólo
-- manda jugadas; el servidor responde con el estado real de la prueba.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local DocumentConfig = require(Shared.Config.DocumentConfig)
local PuzzleConfig = require(Shared.Config.PuzzleConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local PANEL_SIZE = Vector2.new(640, 430)
local BOARD_SIZE = Vector2.new(600, 270)
local CLUE_TIME = 7
local SIMON_FLASH = 0.5
local SIMON_GAP = 0.18
local DONE_COLOR = Color3.fromRGB(70, 170, 100)
local POWER_ON = Color3.fromRGB(236, 196, 80)
local POWER_OFF = Color3.fromRGB(96, 100, 108)

local PuzzleUI = {}
local renderers = {}
local panel, titleLabel, instructionsLabel, board, messageLabel, hintLabel
local clueCard, clueTitle, clueText
local current = nil
local cluesKnown = {}
local keypadBuffer = ""
local selectedWire = nil
local rightButtons = {}
local drag = nil
local simonButtons = {}
local simonShowing = false
local simonToken = 0
local clueToken = 0

local function send(action, first, second)
    if current then
        Remotes.FireServer("PuzzleAction", current.Id, action, first, second)
    end
end

local function offset(x, y)
    return UDim2.fromOffset(x, y)
end

local function button(parent, name, text, position, size, color)
    local item = Theme.Button(parent, text, {
        Name = name,
        Position = position,
        Size = size,
        TextSize = 16,
        TextWrapped = true,
    })
    if color then
        item.BackgroundColor3 = color
    end
    return item
end

local function contrastText(color)
    local luminance = color.R * 0.299 + color.G * 0.587 + color.B * 0.114
    return luminance > 0.6 and Colors.Ink or Colors.Text
end

local function drawLine(parent, from, to, color, thickness, name)
    local delta = to - from
    return Theme.New("Frame", {
        Name = name or "Line",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = offset((from.X + to.X) / 2, (from.Y + to.Y) / 2),
        Size = offset(delta.Magnitude, thickness),
        Rotation = math.deg(math.atan2(delta.Y, delta.X)),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, parent)
end

local function setMessage(text, color)
    messageLabel.Text = text or ""
    messageLabel.TextColor3 = color or Colors.Accent
end

local function render()
    if not current then
        return
    end
    board:ClearAllChildren()
    table.clear(rightButtons)
    table.clear(simonButtons)
    local renderer = renderers[current.Type]
    if renderer then
        renderer(current.View or {})
    end
end

local function closeLocal()
    current = nil
    drag = nil
    selectedWire = nil
    simonToken += 1
    simonShowing = false
    panel.Visible = false
    Theme.SetModal("Puzzle", false)
end

function PuzzleUI.Close()
    if current then
        send("Close")
    end
    closeLocal()
end

function PuzzleUI.Current()
    return current
end

-- Cables -------------------------------------------------------------------------

local WIRE_BUTTON = Vector2.new(170, 50)

local function wireRow(index, count)
    local spacing = math.min(64, (BOARD_SIZE.Y - WIRE_BUTTON.Y) / math.max(1, count - 1))
    return 4 + (index - 1) * spacing
end

-- Posición del puntero en coordenadas del tablero.
local function boardPoint(input)
    local inset = GuiService:GetGuiInset()
    local absolute = Vector2.new(input.Position.X, input.Position.Y) + inset
    local scale = board.AbsoluteSize.X > 0 and board.AbsoluteSize.X / BOARD_SIZE.X or 1
    return (absolute - board.AbsolutePosition) / scale, absolute
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

function renderers.Wires(view)
    local count = #(view.Left or {})
    local leftX, rightX = 20, BOARD_SIZE.X - 20 - WIRE_BUTTON.X
    local linkedLeft, linkedRight = {}, {}
    for _, link in ipairs(view.Links or {}) do
        linkedLeft[link[1]] = link[2]
        linkedRight[link[2]] = link[1]
        local wire = PuzzleConfig.WireColors[view.Left[link[1]]]
        drawLine(
            board,
            Vector2.new(leftX + WIRE_BUTTON.X, wireRow(link[1], count) + WIRE_BUTTON.Y / 2),
            Vector2.new(rightX, wireRow(link[2], count) + WIRE_BUTTON.Y / 2),
            wire and wire.Color or Colors.Text,
            8,
            "Link"
        )
    end

    for index, colorId in ipairs(view.Left or {}) do
        local wire = PuzzleConfig.WireColors[colorId]
        local done = linkedLeft[index] ~= nil
        local text = string.format("%s (%s)%s", wire.Name, wire.Letter, done and " - listo" or "")
        local item = button(board, "Left" .. index, text, offset(leftX, wireRow(index, count)), offset(WIRE_BUTTON.X, WIRE_BUTTON.Y), wire.Color)
        item.TextColor3 = contrastText(wire.Color)
        if selectedWire == index then
            Theme.New("UIStroke", {
                Color = Colors.Text,
                Thickness = 3,
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
            }, item)
        end
        item.Activated:Connect(function()
            if not done then
                selectedWire = index
                setMessage("Ahora tocá el borne " .. string.lower(wire.Name) .. ".")
                render()
            end
        end)
        item.InputBegan:Connect(function(input)
            if not done and isPress(input) then
                drag = {Left = index, Color = wire.Color, Origin = Vector2.new(leftX + WIRE_BUTTON.X, wireRow(index, count) + WIRE_BUTTON.Y / 2)}
            end
        end)
    end

    for index, colorId in ipairs(view.Right or {}) do
        local wire = PuzzleConfig.WireColors[colorId]
        local done = linkedRight[index] ~= nil
        local item = button(board, "Right" .. index, string.format("Borne %s (%s)", wire.Name, wire.Letter), offset(rightX, wireRow(index, count)), offset(WIRE_BUTTON.X, WIRE_BUTTON.Y), Colors.PanelLight)
        Theme.New("Frame", {
            Name = "Swatch",
            Position = offset(0, 0),
            Size = UDim2.new(0, 10, 1, 0),
            BackgroundColor3 = wire.Color,
            BorderSizePixel = 0,
        }, item)
        rightButtons[index] = item
        item.Activated:Connect(function()
            if selectedWire and not done then
                send("Connect", selectedWire, index)
                selectedWire = nil
            end
        end)
    end
end

local function updateDrag(input)
    if not drag or not current or current.Type ~= "Wires" then
        return
    end
    local point = boardPoint(input)
    if drag.Line then
        drag.Line:Destroy()
    end
    drag.Line = drawLine(board, drag.Origin, point, drag.Color, 6, "DragLine")
end

local function finishDrag(input)
    local active = drag
    drag = nil
    if not active then
        return
    end
    if active.Line then
        active.Line:Destroy()
    end
    if not current or current.Type ~= "Wires" then
        return
    end

    local _, absolute = boardPoint(input)
    for index, item in pairs(rightButtons) do
        local position, size = item.AbsolutePosition, item.AbsoluteSize
        if absolute.X >= position.X and absolute.X <= position.X + size.X
            and absolute.Y >= position.Y and absolute.Y <= position.Y + size.Y then
            selectedWire = nil
            send("Connect", active.Left, index)
            return
        end
    end
end

-- Disyuntores --------------------------------------------------------------------

function renderers.Breakers(view)
    local count = view.Count or 0
    local width = 110
    local gap = 26
    local startX = (BOARD_SIZE.X - (count * width + (count - 1) * gap)) / 2
    for index = 1, count do
        local on = view.On and view.On[index]
        local item = button(
            board,
            "Switch" .. index,
            string.format("%d\n%s", index, on and "ARRIBA" or "ABAJO"),
            offset(startX + (index - 1) * (width + gap), 40),
            offset(width, 170),
            on and DONE_COLOR or Colors.Button
        )
        item.TextSize = 22
        item.Activated:Connect(function()
            send("Flip", index)
        end)
    end
end

-- Válvulas -----------------------------------------------------------------------

function renderers.Valves(view)
    local gauges = view.Gauges or {}
    local maximum = view.Max or 1
    local names = PuzzleConfig.Valves.Names
    local columnWidth = BOARD_SIZE.X / math.max(1, #gauges)

    for index, value in ipairs(gauges) do
        local centerX = (index - 0.5) * columnWidth
        local gauge = Theme.New("Frame", {
            Name = "Gauge" .. index,
            Position = offset(centerX - 70, 4),
            Size = offset(40, 130),
            BackgroundColor3 = Colors.PanelLight,
            BorderSizePixel = 0,
        }, board)
        local fill = value / maximum
        Theme.New("Frame", {
            Name = "Fill",
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.fromScale(1, fill),
            BackgroundColor3 = value == view.Target and DONE_COLOR or Colors.Danger,
            BorderSizePixel = 0,
        }, gauge)
        Theme.New("Frame", {
            Name = "Mark",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(-0.2, 0, 1 - (view.Target or 0) / maximum, 0),
            Size = UDim2.new(1.4, 0, 0, 3),
            BackgroundColor3 = DONE_COLOR,
            BorderSizePixel = 0,
        }, gauge)
        Theme.Label(board, {
            Name = "GaugeLabel" .. index,
            Position = offset(centerX - 24, 40),
            Size = offset(100, 60),
            TextSize = 15,
            Text = string.format("Manómetro %d\n%d / %d", index, value, view.Target or 0),
        })

        local effects = view.Effects and view.Effects[index] or {}
        local parts = {}
        for gaugeIndex, change in ipairs(effects) do
            if change ~= 0 then
                table.insert(parts, string.format("M%d %s%d", gaugeIndex, change > 0 and "+" or "", change))
            end
        end
        Theme.Label(board, {
            Name = "ValveLabel" .. index,
            Position = offset(centerX - 90, 142),
            Size = offset(180, 40),
            TextSize = 13,
            TextColor3 = Colors.TextDim,
            TextXAlignment = Enum.TextXAlignment.Center,
            Text = string.format("Válvula %s: %s", names[index] or tostring(index), table.concat(parts, ", ")),
        })
        local minus = button(board, "Close" .. index, "-", offset(centerX - 74, 190), offset(70, 54))
        local plus = button(board, "Open" .. index, "+", offset(centerX + 4, 190), offset(70, 54))
        minus.TextSize = 26
        plus.TextSize = 26
        minus.Activated:Connect(function()
            send("Turn", index, -1)
        end)
        plus.Activated:Connect(function()
            send("Turn", index, 1)
        end)
    end
end

-- Cerradura con clave ------------------------------------------------------------

local KEYPAD_KEYS = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "Borrar", "0", "OK"}

function renderers.Keypad(view)
    local length = view.Length or PuzzleConfig.Keypad.Length
    local shown = {}
    for index = 1, length do
        shown[index] = string.sub(keypadBuffer, index, index) ~= "" and string.sub(keypadBuffer, index, index) or "_"
    end
    Theme.Label(board, {
        Name = "Display",
        Position = offset(20, 0),
        Size = offset(250, 40),
        TextSize = 30,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = table.concat(shown, " "),
    })

    for index, key in ipairs(KEYPAD_KEYS) do
        local column = (index - 1) % 3
        local row = math.floor((index - 1) / 3)
        local item = button(board, "Key" .. key, key, offset(20 + column * 86, 46 + row * 56), offset(78, 50))
        item.TextSize = key == "Borrar" and 15 or 22
        item.Activated:Connect(function()
            if key == "Borrar" then
                keypadBuffer = ""
            elseif key == "OK" then
                if #keypadBuffer == length then
                    send("Submit", keypadBuffer)
                    keypadBuffer = ""
                else
                    setMessage("Faltan números.")
                end
            elseif #keypadBuffer < length then
                keypadBuffer ..= key
            end
            render()
        end)
    end

    local notes = {}
    local known = current and cluesKnown[current.Id]
    if known then
        table.insert(notes, "Anotaste: " .. known)
    end
    if view.ClueHint then
        table.insert(notes, view.ClueHint)
    end
    if view.Locked then
        table.insert(notes, "Bloqueado por unos segundos.")
    end
    Theme.Label(board, {
        Name = "Notes",
        Position = offset(310, 10),
        Size = offset(270, 240),
        TextSize = 16,
        Text = table.concat(notes, "\n\n"),
    })
end

-- Tablero de distribución --------------------------------------------------------

local TILE = 68
local TILE_GAP = 4
local ARM = 12

local function openings(kind, rotation)
    local result = {}
    for _, side in ipairs(PuzzleConfig.Power.Pieces[kind] or {}) do
        result[(side - 1 + rotation) % 4 + 1] = true
    end
    return result
end

local function drawPiece(item, kind, rotation, color)
    local half = TILE / 2
    Theme.New("Frame", {
        Name = "Hub",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = offset(half, half),
        Size = offset(ARM + 4, ARM + 4),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, item)
    local arms = {
        [1] = {offset(half - ARM / 2, 0), offset(ARM, half)},
        [2] = {offset(half, half - ARM / 2), offset(half, ARM)},
        [3] = {offset(half - ARM / 2, half), offset(ARM, half)},
        [4] = {offset(0, half - ARM / 2), offset(half, ARM)},
    }
    for side in pairs(openings(kind, rotation)) do
        Theme.New("Frame", {
            Name = "Arm" .. side,
            Position = arms[side][1],
            Size = arms[side][2],
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, item)
    end
end

function renderers.Power(view)
    local columns, rows = view.Columns or 0, view.Rows or 0
    local width = columns * (TILE + TILE_GAP)
    local startX = (BOARD_SIZE.X - width) / 2
    local startY = math.max(0, (BOARD_SIZE.Y - rows * (TILE + TILE_GAP)) / 2)

    Theme.Label(board, {
        Name = "Source",
        Position = offset(startX - 92, startY + ((view.Source or 1) - 1) * (TILE + TILE_GAP) + TILE / 2 - 12),
        Size = offset(86, 24),
        TextSize = 14,
        TextColor3 = POWER_ON,
        TextXAlignment = Enum.TextXAlignment.Right,
        Text = "ENTRADA >",
    })
    Theme.Label(board, {
        Name = "Sink",
        Position = offset(startX + width + 6, startY + ((view.Sink or 1) - 1) * (TILE + TILE_GAP) + TILE / 2 - 12),
        Size = offset(86, 24),
        TextSize = 14,
        TextColor3 = Colors.Accent,
        Text = "> SALIDA",
    })

    for row = 1, rows do
        for column = 1, columns do
            local index = (row - 1) * columns + column
            local tile = view.Tiles[index]
            local item = button(
                board,
                "Tile" .. index,
                "",
                offset(startX + (column - 1) * (TILE + TILE_GAP), startY + (row - 1) * (TILE + TILE_GAP)),
                offset(TILE, TILE),
                Colors.PanelLight
            )
            drawPiece(item, tile.Type, tile.Rot, view.Powered and view.Powered[index] and POWER_ON or POWER_OFF)
            item.Activated:Connect(function()
                send("Rotate", index)
            end)
        end
    end
end

-- Señal para repetir -------------------------------------------------------------

local function flashSimon(index, lit)
    local item = simonButtons[index]
    if item then
        item.BackgroundTransparency = lit and 0 or 0.55
    end
end

local function playSignal(sequence)
    simonToken += 1
    local token = simonToken
    simonShowing = true
    task.spawn(function()
        task.wait(0.6)
        for _, index in ipairs(sequence or {}) do
            if token ~= simonToken then
                return
            end
            flashSimon(index, true)
            task.wait(SIMON_FLASH)
            flashSimon(index, false)
            task.wait(SIMON_GAP)
        end
        if token == simonToken then
            simonShowing = false
            setMessage("Tu turno: repetí la señal.")
        end
    end)
end

function renderers.Simon(view)
    local count = view.Buttons or #PuzzleConfig.Simon.Buttons
    local size = 118
    local gap = 22
    local startX = (BOARD_SIZE.X - (count * size + (count - 1) * gap)) / 2
    for index = 1, count do
        local definition = PuzzleConfig.Simon.Buttons[index]
        local item = button(board, "Signal" .. index, definition.Name, offset(startX + (index - 1) * (size + gap), 30), offset(size, size), definition.Color)
        item.BackgroundTransparency = 0.55
        item.TextColor3 = contrastText(definition.Color)
        simonButtons[index] = item
        item.Activated:Connect(function()
            if simonShowing then
                return
            end
            flashSimon(index, true)
            task.delay(0.2, function()
                flashSimon(index, false)
            end)
            send("Press", index)
        end)
    end

    Theme.Label(board, {
        Name = "Round",
        Position = offset(20, 170),
        Size = offset(260, 30),
        TextSize = 16,
        Text = string.format("Señal %d de %d — vas %d de %d", view.Round or 1, view.TotalRounds or 1, view.Position or 0, #(view.Show or {})),
    })
    local replay = button(board, "Replay", "Escuchar de nuevo", offset(BOARD_SIZE.X - 220, 166), offset(200, 48))
    replay.Activated:Connect(function()
        if current and current.View then
            playSignal(current.View.Show)
        end
    end)
end

-- Recuerdos ----------------------------------------------------------------------

function renderers.Memory(view)
    local count = view.Count or 0
    local columns = 4
    local width, height, gap = 134, 76, 10
    local rows = math.ceil(count / columns)
    local startX = (BOARD_SIZE.X - (columns * width + (columns - 1) * gap)) / 2
    local startY = math.max(0, (BOARD_SIZE.Y - (rows * height + (rows - 1) * gap)) / 2)

    for index = 1, count do
        local card = view.Cards[index]
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local faceUp = card.Matched or card.Revealed
        local item = button(
            board,
            "Card" .. index,
            faceUp and card.Symbol or "?",
            offset(startX + column * (width + gap), startY + row * (height + gap)),
            offset(width, height),
            card.Matched and DONE_COLOR or (card.Revealed and Colors.Paper or Colors.Button)
        )
        item.TextColor3 = card.Revealed and not card.Matched and Colors.Ink or Colors.Text
        item.Activated:Connect(function()
            if not card.Matched and not card.Revealed then
                send("Flip", index)
            end
        end)
    end
end

-- Eventos del servidor -----------------------------------------------------------

local function showClue(data)
    clueToken += 1
    local token = clueToken
    clueTitle.Text = typeof(data.Title) == "string" and data.Title or "Pista"
    clueText.Text = typeof(data.Text) == "string" and data.Text or ""
    clueCard.Visible = true
    task.delay(CLUE_TIME, function()
        if token == clueToken then
            clueCard.Visible = false
        end
    end)
end

local function hintFor(view)
    local document = view and view.ClueDocument and DocumentConfig[view.ClueDocument]
    if document then
        return "Pista: «" .. document.Title .. "»"
    end
    local objective = ClientState.Get("Objective")
    return objective and objective.Hint or ""
end

local function onUpdate(data)
    if typeof(data) ~= "table" or typeof(data.Id) ~= "string" then
        return
    end

    if data.Event == "Clue" then
        if typeof(data.Code) == "string" then
            cluesKnown[data.Id] = data.Code
        end
        showClue(data)
        if current and current.Id == data.Id then
            render()
        end
        return
    end

    if data.Event == "Open" then
        local previousType = current and current.Id == data.Id and current.Type
        current = {Id = data.Id, Type = data.Type, View = data.View}
        keypadBuffer = ""
        selectedWire = nil
        titleLabel.Text = data.Title or ""
        instructionsLabel.Text = data.Instructions or ""
        hintLabel.Text = hintFor(data.View)
        setMessage(data.Message)
        panel.Visible = true
        Theme.SetModal("Puzzle", true)
        render()
        if data.Type == "Simon" and previousType ~= "Simon" then
            playSignal(data.View and data.View.Show)
        end
        return
    end

    if not current or current.Id ~= data.Id then
        return
    end

    if data.Event == "State" or data.Event == "Wrong" then
        local previousRound = current.View and current.View.Round
        current.View = data.View
        render()
        setMessage(data.Message, data.Event == "Wrong" and Colors.Danger or nil)
        if current.Type == "Simon" and (data.Event == "Wrong" or (data.View and data.View.Round ~= previousRound)) then
            playSignal(data.View and data.View.Show)
        end
    elseif data.Event == "Solved" then
        current.View = data.View
        render()
        setMessage(data.Message or "¡Listo!", DONE_COLOR)
        local solvedId = current.Id
        task.delay(1.2, function()
            if current and current.Id == solvedId then
                closeLocal()
            end
        end)
    elseif data.Event == "Close" then
        closeLocal()
    end
end

function PuzzleUI.Start()
    local root = Theme.Screen("NocturnaPuzzle", 30)

    panel = Theme.Panel(root, {
        Name = "PuzzlePanel",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = offset(PANEL_SIZE.X, PANEL_SIZE.Y),
        BackgroundTransparency = 0.08,
        Visible = false,
    })
    titleLabel = Theme.Label(panel, {
        Name = "Title",
        Position = offset(20, 12),
        Size = offset(480, 28),
        TextSize = 21,
        Font = Enum.Font.GothamBold,
        TextColor3 = Colors.Accent,
    })
    instructionsLabel = Theme.Label(panel, {
        Name = "Instructions",
        Position = offset(20, 42),
        Size = offset(600, 36),
        TextSize = 14,
        TextColor3 = Colors.TextDim,
    })
    board = Theme.New("Frame", {
        Name = "Board",
        Position = offset(20, 82),
        Size = offset(BOARD_SIZE.X, BOARD_SIZE.Y),
        BackgroundTransparency = 1,
    }, panel)
    messageLabel = Theme.Label(panel, {
        Name = "Message",
        Position = offset(20, 358),
        Size = offset(600, 26),
        TextSize = 16,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    hintLabel = Theme.Label(panel, {
        Name = "Hint",
        Position = offset(20, 388),
        Size = offset(600, 34),
        TextSize = 14,
        TextColor3 = Colors.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local closeButton = button(panel, "Close", "CERRAR", offset(PANEL_SIZE.X - 128, 10), offset(110, 40))
    closeButton.Activated:Connect(PuzzleUI.Close)

    clueCard = Theme.Panel(root, {
        Name = "ClueCard",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 140),
        Size = offset(440, 150),
        Visible = false,
    })
    clueTitle = Theme.Label(clueCard, {
        Name = "Title",
        Position = offset(16, 10),
        Size = offset(408, 26),
        TextSize = 16,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    clueText = Theme.Label(clueCard, {
        Name = "Text",
        Position = offset(16, 44),
        Size = offset(408, 90),
        TextSize = 44,
        Font = Enum.Font.GothamBold,
        TextColor3 = Colors.Danger,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    Remotes.OnClient("PuzzleUpdate", onUpdate)

    UserInputService.InputChanged:Connect(function(input)
        if drag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateDrag(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if drag and isPress(input) then
            finishDrag(input)
        end
    end)

    -- Fuera de la partida, al reaparecer o al caer, el panel se cierra.
    ClientState.Subscribe("Game", function(state)
        if state.Phase ~= "Playing" and current then
            closeLocal()
        end
    end)
    player.CharacterAdded:Connect(function()
        if current then
            closeLocal()
        end
    end)
    Remotes.OnClient("DownState", function(data)
        if typeof(data) == "table" and (data.Down or data.Failed) and current then
            closeLocal()
        end
    end)
end

return PuzzleUI
