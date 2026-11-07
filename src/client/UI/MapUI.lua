-- Plano del capítulo, como un plano viejo y manchado. Sólo muestra lo que el grupo
-- ya recorrió (el servidor manda cada sala recién cuando alguien la pisa): niebla
-- en lo demás, el jugador y sus compañeros, el objetivo, objetos, documentos,
-- escondites, máquinas, puertas y la salida. Botón MAPA o tecla M.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local ClientState = require(script.Parent.Parent.Core.ClientState)
local HUD = require(script.Parent.HUD)
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local player = Players.LocalPlayer
local Colors = Theme.Colors

local CELL_SIZE = GameConfig.Map.CellSize
local SLOT_OFFSET = (CELL_SIZE / 2 - GameConfig.Map.SlotInset) / CELL_SIZE
local WINDOW_WIDTH = 760
local WINDOW_HEIGHT = 450
local LEGEND_WIDTH = 168
local REFRESH_INTERVAL = 0.1
local REQUEST_COOLDOWN = 2
local MAX_OBJECTIVES = 6

local Z_FOG, Z_CELL, Z_DOOR, Z_MARKER, Z_OBJECTIVE, Z_PLAYER = 1, 2, 3, 4, 5, 6

local MARKER_ICONS = {Document = "Document", Hide = "Locker", Mechanism = "Mechanism", Exit = "Exit"}

local LEGEND = {
    {"You", "Vos"},
    {"Teammate", "Tu grupo"},
    {"Objective", "Objetivo"},
    {"Fuse", "Objeto"},
    {"Document", "Documento"},
    {"Locker", "Escondite"},
    {"Mechanism", "Máquina"},
    {"DoorLocked", "Puerta trabada"},
    {"Door", "Puerta"},
    {"Exit", "Salida"},
}

local MapUI = {}

local panel = nil
local board = nil
local grid = nil
local coverage = nil
local emptyLabel = nil
local heading = nil
local actionButton = nil

local data = nil
local cellPx = 40
local boardSize = Vector2.new(WINDOW_WIDTH - LEGEND_WIDTH - 44, WINDOW_HEIGHT - 104)
local views = {Fog = {}, Cells = {}, Doors = {}, Markers = {}, Players = {}, Objectives = {}}
local refreshClock = 0
local lastRequest = -math.huge
local generation = 0
local seenAt = {}

local function coords(index)
    local width = data.Width
    return (index - 1) % width + 1, math.floor((index - 1) / width) + 1
end

local function requestSnapshot()
    local now = os.clock()
    if now - lastRequest < REQUEST_COOLDOWN then
        return
    end
    lastRequest = now
    Remotes.FireServer("MapRequest")
end

local function frame(parent, properties)
    local merged = {BorderSizePixel = 0}
    for key, value in pairs(properties) do
        merged[key] = value
    end
    return Theme.New("Frame", merged, parent)
end

-- Dibujo ------------------------------------------------------------------------

local function wall(parent, x, y, width, height, thickness)
    return frame(parent, {
        Name = "Wall",
        Position = UDim2.new(x, x >= 1 and -thickness or 0, y, y >= 1 and -thickness or 0),
        Size = UDim2.new(width, width == 0 and thickness or 0, height, height == 0 and thickness or 0),
        BackgroundColor3 = Colors.BlueprintLine,
        ZIndex = Z_CELL,
    })
end

local function drawRoom(view, open, thickness)
    local inset = 0.07
    local floor = frame(view, {
        Name = "Floor",
        Position = UDim2.fromScale(inset, inset),
        Size = UDim2.fromScale(1 - inset * 2, 1 - inset * 2),
        BackgroundColor3 = Colors.BlueprintFloor,
        BackgroundTransparency = 0.1,
        ZIndex = Z_CELL,
    })
    -- Cada lado: pared entera, o dos tramos con la abertura en el medio y un pasillo
    -- corto que se une con el de la sala vecina.
    local gapFrom, gapTo = 0.33, 0.67
    local sides = {
        N = {Horizontal = true, Edge = 0},
        S = {Horizontal = true, Edge = 1},
        W = {Horizontal = false, Edge = 0},
        E = {Horizontal = false, Edge = 1},
    }
    for direction, side in pairs(sides) do
        local spans = string.find(open, direction, 1, true) and {{0, gapFrom}, {gapTo, 1}} or {{0, 1}}
        for _, span in ipairs(spans) do
            if side.Horizontal then
                wall(floor, span[1], side.Edge, span[2] - span[1], 0, thickness)
            else
                wall(floor, side.Edge, span[1], 0, span[2] - span[1], thickness)
            end
        end
        if string.find(open, direction, 1, true) then
            local outward = side.Edge == 0 and 0 or 1 - inset
            frame(view, {
                Name = "Passage",
                Position = side.Horizontal and UDim2.fromScale(gapFrom, outward) or UDim2.fromScale(outward, gapFrom),
                Size = side.Horizontal and UDim2.fromScale(gapTo - gapFrom, inset) or UDim2.fromScale(inset, gapTo - gapFrom),
                BackgroundColor3 = Colors.BlueprintFloor,
                BackgroundTransparency = 0.1,
                ZIndex = Z_CELL,
            })
        end
    end
end

-- Pasillo angosto: un centro y brazos hacia cada abertura.
local function drawCorridor(view, open)
    local from, to = 0.36, 0.64
    local function piece(x, y, width, height)
        local piece_ = frame(view, {
            Name = "Corridor",
            Position = UDim2.fromScale(x, y),
            Size = UDim2.fromScale(width, height),
            BackgroundColor3 = Colors.BlueprintFloor,
            BackgroundTransparency = 0.1,
            ZIndex = Z_CELL,
        })
        Theme.Stroke(piece_, Colors.BlueprintLine, 1, 0.55)
    end
    piece(from, from, to - from, to - from)
    if string.find(open, "N", 1, true) then
        piece(from, 0, to - from, from)
    end
    if string.find(open, "S", 1, true) then
        piece(from, to, to - from, 1 - to)
    end
    if string.find(open, "W", 1, true) then
        piece(0, from, from, to - from)
    end
    if string.find(open, "E", 1, true) then
        piece(to, from, 1 - to, to - from)
    end
end

local function cellLabel(view, text, color)
    Theme.Label(view, {
        Name = "Label",
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -2),
        Size = UDim2.new(1, -4, 0, 14),
        Text = text,
        TextSize = 12,
        TextScaled = cellPx < 44,
        TextWrapped = false,
        TextColor3 = color,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = Z_MARKER,
    })
end

local function drawCell(cell)
    local fog = views.Fog[cell.I]
    if fog then
        fog.Visible = false
    end
    local old = views.Cells[cell.I]
    if old then
        old:Destroy()
    end

    local view = frame(grid, {
        Name = "Cell" .. cell.I,
        Position = UDim2.fromOffset((cell.X - 1) * cellPx, (cell.Z - 1) * cellPx),
        Size = UDim2.fromOffset(cellPx, cellPx),
        BackgroundTransparency = 1,
        ZIndex = Z_CELL,
    })
    local open = typeof(cell.Open) == "string" and cell.Open or ""
    if cell.Role == "Corridor" then
        drawCorridor(view, open)
    else
        drawRoom(view, open, math.max(2, math.floor(cellPx * 0.05)))
    end
    if cell.Role == "Start" then
        cellLabel(view, "inicio", Colors.TextDim)
    end
    views.Cells[cell.I] = view
end

local function drawDoor(door)
    local old = views.Doors[door.Key]
    if old then
        old:Destroy()
    end
    local ax, az = coords(door.A)
    local bx, bz = coords(door.B)
    -- Vecinas en X: la puerta es una línea vertical sobre el borde compartido.
    local sideBySide = az == bz
    local x = sideBySide and (math.max(ax, bx) - 1) * cellPx or (ax - 0.5) * cellPx
    local y = sideBySide and (az - 0.5) * cellPx or (math.max(az, bz) - 1) * cellPx
    local long = math.max(8, math.floor(cellPx * 0.36))
    local thick = math.max(3, math.floor(cellPx * (door.Locked and 0.1 or 0.06)))

    local view = frame(grid, {
        Name = "Door",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(x, y),
        Size = sideBySide and UDim2.fromOffset(thick, long) or UDim2.fromOffset(long, thick),
        BackgroundColor3 = door.Locked and Colors.Danger or Colors.Accent,
        BackgroundTransparency = door.Locked and 0 or 0.25,
        ZIndex = Z_DOOR,
    })
    if door.Locked then
        -- Candado: aro y cuerpo.
        local size = math.max(7, math.floor(cellPx * 0.14))
        local lock = frame(view, {
            Name = "Lock",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = Colors.Text,
            ZIndex = Z_DOOR,
        })
        Theme.Stroke(lock, Colors.Black, 1, 0)
    end
    views.Doors[door.Key] = view
end

local function markerPosition(marker)
    local x, z = coords(marker.Cell)
    local fx, fz = x - 0.5, z - 0.5
    if typeof(marker.Slot) == "string" then
        fx += (string.find(marker.Slot, "E", 1, true) and 1 or -1) * SLOT_OFFSET
        fz += (string.find(marker.Slot, "S", 1, true) and 1 or -1) * SLOT_OFFSET
    end
    return UDim2.fromOffset(fx * cellPx, fz * cellPx)
end

local function checkMark(parent)
    local mark = frame(parent, {
        Name = "Done",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromScale(1.15, 1.1),
        Size = UDim2.fromScale(0.5, 0.5),
        BackgroundColor3 = Colors.Exit,
        ZIndex = Z_MARKER,
    })
    Theme.New("UICorner", {CornerRadius = UDim.new(0.5, 0)}, mark)
    Theme.Stroke(mark, Colors.Black, 1, 0)
end

local function documentRead(marker)
    local profile = ClientState.Get("Profile")
    return profile ~= nil and profile.Documents ~= nil and profile.Documents[marker.Document] == true
end

local function drawMarker(marker)
    local old = views.Markers[marker.Id]
    if old then
        old:Destroy()
        views.Markers[marker.Id] = nil
    end
    if marker.Type == "Item" and marker.Done then
        return
    end

    local kind = marker.Type == "Item" and marker.Item or MARKER_ICONS[marker.Type]
    local size = math.clamp(math.floor(cellPx * (marker.Type == "Exit" and 0.4 or 0.3)), 12, 28)
    local icon = Icons.Draw(kind, grid, {
        Name = "Marker",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = markerPosition(marker),
        Size = UDim2.fromOffset(size, size),
        ZIndex = Z_MARKER,
    })
    if (marker.Type == "Mechanism" and marker.Done) or (marker.Type == "Document" and documentRead(marker)) then
        checkMark(icon)
    end
    if marker.Type == "Exit" then
        Theme.Label(icon, {
            Name = "ExitLabel",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 1, 1),
            Size = UDim2.fromOffset(70, 14),
            Text = "SALIDA",
            TextSize = 12,
            TextColor3 = Colors.Exit,
            TextStrokeTransparency = 0.3,
            TextXAlignment = Enum.TextXAlignment.Center,
            ZIndex = Z_MARKER,
        })
    end
    views.Markers[marker.Id] = icon
end

local function updateCoverage()
    if not data then
        coverage.Text = ""
        return
    end
    local known = 0
    for _ in pairs(data.Cells) do
        known += 1
    end
    coverage.Text = string.format("Recorrido: %d de %d salas", known, data.Width * data.Depth)
end

local function clearViews()
    for _, group in pairs(views) do
        for key, view in pairs(group) do
            view:Destroy()
            group[key] = nil
        end
    end
end

-- Arma todo de nuevo: al llegar el plano o si cambia el tamaño de la pantalla.
local function rebuild()
    clearViews()
    emptyLabel.Visible = data == nil
    if not data then
        grid.Visible = false
        updateCoverage()
        return
    end

    cellPx = math.clamp(math.floor(math.min(boardSize.X / data.Width, boardSize.Y / data.Depth)), 18, 96)
    grid.Size = UDim2.fromOffset(cellPx * data.Width, cellPx * data.Depth)
    grid.Visible = true

    local rng = Random.new(data.Chapter * 97 + data.Width)
    for index = 1, data.Width * data.Depth do
        local x, z = coords(index)
        views.Fog[index] = frame(grid, {
            Name = "Fog",
            Position = UDim2.fromOffset((x - 1) * cellPx, (z - 1) * cellPx),
            Size = UDim2.fromOffset(cellPx, cellPx),
            BackgroundColor3 = Color3.fromRGB(7, 9, 11),
            BackgroundTransparency = rng:NextNumber(0.05, 0.3),
            ZIndex = Z_FOG,
        })
    end

    for _, cell in pairs(data.Cells) do
        drawCell(cell)
    end
    for _, door in pairs(data.Doors) do
        drawDoor(door)
    end
    for _, marker in pairs(data.Markers) do
        drawMarker(marker)
    end
    updateCoverage()
end

-- Datos del servidor -------------------------------------------------------------

local function validIndex(value)
    return typeof(value) == "number" and data ~= nil and value >= 1 and value <= data.Width * data.Depth
end

local function merge(payload, draw)
    for _, cell in ipairs(typeof(payload.Cells) == "table" and payload.Cells or {}) do
        if typeof(cell) == "table" and validIndex(cell.I) then
            data.Cells[cell.I] = cell
            if draw then
                drawCell(cell)
            end
        end
    end
    for _, door in ipairs(typeof(payload.Doors) == "table" and payload.Doors or {}) do
        if typeof(door) == "table" and typeof(door.Key) == "string" and validIndex(door.A) and validIndex(door.B) then
            data.Doors[door.Key] = door
            if draw then
                drawDoor(door)
            end
        end
    end
    for _, marker in ipairs(typeof(payload.Markers) == "table" and payload.Markers or {}) do
        if typeof(marker) == "table" and typeof(marker.Id) == "string" and validIndex(marker.Cell) then
            data.Markers[marker.Id] = marker
            if draw then
                drawMarker(marker)
            end
        end
    end
end

local function onUpdate(payload)
    if typeof(payload) ~= "table" then
        return
    end
    if payload.Kind == "Clear" then
        data = nil
        rebuild()
        return
    end
    if payload.Kind == "Layout" then
        if typeof(payload.Width) ~= "number" or typeof(payload.Depth) ~= "number" then
            return
        end
        data = {
            Chapter = payload.Chapter or 0,
            Width = payload.Width,
            Depth = payload.Depth,
            Cells = {},
            Doors = {},
            Markers = {},
        }
        merge(payload, false)
        heading.Text = Theme.Upper(string.format(
            "Plano · Capítulo %d — %s",
            data.Chapter,
            GameConfig.Chapters[data.Chapter] or ""
        ))
        rebuild()
        return
    end
    if payload.Kind == "Reveal" then
        if not data or payload.Chapter ~= data.Chapter then
            -- Llegó una novedad de un plano que no conocemos: se pide entero.
            requestSnapshot()
            return
        end
        merge(payload, true)
        updateCoverage()
    end
end

-- Jugadores y objetivo -------------------------------------------------------------

local function playerView(other)
    local view = views.Players[other]
    if view then
        return view
    end
    if other == player then
        view = Icons.Draw("You", grid, {
            Name = "You",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(18, 18),
            ZIndex = Z_PLAYER,
        })
    else
        view = Icons.Draw("Teammate", grid, {
            Name = "Mate",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(18, 18),
            ZIndex = Z_PLAYER,
        })
        Theme.Label(view, {
            Name = "Initial",
            Size = UDim2.fromScale(1, 1),
            Text = Theme.Upper(string.sub(other.DisplayName, 1, 1)),
            TextSize = 12,
            TextColor3 = Colors.Black,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            ZIndex = Z_PLAYER,
        })
    end
    views.Players[other] = view
    return view
end

local function downedUsers()
    local result = {}
    for _, member in ipairs(ClientState.Get("Party") or {}) do
        if member.Down then
            result[member.UserId] = true
        end
    end
    return result
end

local function updatePlayers()
    generation += 1
    local downed = downedUsers()
    for _, other in ipairs(Players:GetPlayers()) do
        local character = other.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        if rootPart then
            local view = playerView(other)
            local position = rootPart.Position
            local fx = position.X / CELL_SIZE + 0.5
            local fz = position.Z / CELL_SIZE + 0.5
            local inside = fx >= 0 and fz >= 0 and fx <= data.Width and fz <= data.Depth
            view.Visible = inside
            view.Position = UDim2.fromOffset(fx * cellPx, fz * cellPx)
            seenAt[other] = generation
            if other == player then
                local camera = workspace.CurrentCamera
                if camera then
                    local look = camera.CFrame.LookVector
                    view.Rotation = math.deg(math.atan2(look.X, -look.Z))
                end
            else
                local disc = view:FindFirstChild("Shape")
                if disc then
                    disc.BackgroundColor3 = downed[other.UserId] and Colors.Danger or Colors.Text
                end
            end
        end
    end
    for other, view in pairs(views.Players) do
        if seenAt[other] ~= generation then
            view:Destroy()
            views.Players[other] = nil
            seenAt[other] = nil
        end
    end
end

local function objectiveView(index)
    local view = views.Objectives[index]
    if not view then
        view = Icons.Draw("Objective", grid, {
            Name = "Objective",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(22, 22),
            ZIndex = Z_OBJECTIVE,
        })
        views.Objectives[index] = view
    end
    return view
end

-- El objetivo se marca si la dificultad muestra la señal de la radio o si su sala
-- ya fue recorrida; en Pesadilla no se regala lo inexplorado.
local function updateObjectives()
    local objective = ClientState.Get("Objective")
    local state = ClientState.Get("Game")
    local showAll = state ~= nil and state.ShowCompass == true
    local waypoints = objective and not objective.Finished and objective.Waypoints or nil
    local used = 0

    if waypoints then
        for _, position in ipairs(waypoints) do
            if typeof(position) == "Vector3" and used < MAX_OBJECTIVES then
                local x = math.floor(position.X / CELL_SIZE + 0.5) + 1
                local z = math.floor(position.Z / CELL_SIZE + 0.5) + 1
                local inside = x >= 1 and z >= 1 and x <= data.Width and z <= data.Depth
                if inside and (showAll or data.Cells[(z - 1) * data.Width + x]) then
                    used += 1
                    local view = objectiveView(used)
                    view.Position = UDim2.fromOffset((position.X / CELL_SIZE + 0.5) * cellPx, (position.Z / CELL_SIZE + 0.5) * cellPx)
                    view.Visible = true
                end
            end
        end
    end
    for index = used + 1, #views.Objectives do
        views.Objectives[index].Visible = false
    end
end

local function refreshLive()
    if data and grid.Visible then
        updatePlayers()
        updateObjectives()
    end
end

-- Ventana --------------------------------------------------------------------------

function MapUI.IsOpen()
    return panel ~= nil and panel.Visible
end

function MapUI.SetOpen(open)
    panel.Visible = open
    Theme.SetModal("Map", open)
    if open then
        if not data then
            requestSnapshot()
        end
        refreshLive()
    end
end

function MapUI.Toggle()
    MapUI.SetOpen(not panel.Visible)
end

local function buildLegend()
    local legend = frame(panel, {
        Name = "Legend",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 60),
        Size = UDim2.new(0, LEGEND_WIDTH, 1, -100),
        BackgroundTransparency = 1,
    })
    Theme.New("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, legend)

    for index, entry in ipairs(LEGEND) do
        local row = frame(legend, {
            Name = "Entry",
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
            LayoutOrder = index,
        })
        Icons.Draw(entry[1], row, {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(18, 18),
        })
        Theme.Label(row, {
            Position = UDim2.fromOffset(26, 0),
            Size = UDim2.new(1, -26, 1, 0),
            Text = entry[2],
            TextSize = 14,
            TextColor3 = Colors.TextDim,
            TextWrapped = false,
            TextYAlignment = Enum.TextYAlignment.Center,
        })
    end
end

function MapUI.Start()
    local root = Theme.Screen("NocturnaMap", 13)
    local close
    panel, heading, close = Theme.Window(root, "Map", "PLANO", WINDOW_WIDTH, WINDOW_HEIGHT, {
        BackgroundColor3 = Colors.Blueprint,
    })
    close.Activated:Connect(function()
        MapUI.SetOpen(false)
    end)

    board = frame(panel, {
        Name = "Board",
        Position = UDim2.fromOffset(16, 60),
        Size = UDim2.new(1, -(LEGEND_WIDTH + 44), 1, -100),
        BackgroundColor3 = Color3.fromRGB(10, 14, 18),
        BackgroundTransparency = 0.1,
        ClipsDescendants = true,
    })
    Theme.Stroke(board, Colors.BlueprintLine, 1, 0.7)
    Theme.Wear(board, "plano", 3)

    grid = frame(board, {
        Name = "Grid",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(100, 100),
        BackgroundTransparency = 1,
        Visible = false,
    })

    emptyLabel = Theme.Label(board, {
        Name = "Empty",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0.8, 0, 0, 60),
        Text = "Todavía no hay plano: bajá al capítulo y recorrelo con tu grupo.",
        TextSize = 16,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Center,
    })

    coverage = Theme.Label(panel, {
        Name = "Coverage",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 18, 1, -10),
        Size = UDim2.new(0.5, 0, 0, 20),
        TextSize = 14,
        TextColor3 = Colors.Accent,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    Theme.Label(panel, {
        Name = "Hint",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, -10),
        Size = UDim2.new(0.5, -24, 0, 20),
        Text = "Sólo aparece lo que tu grupo ya recorrió.",
        TextSize = 13,
        TextColor3 = Colors.TextDim,
        TextXAlignment = Enum.TextXAlignment.Right,
        TextYAlignment = Enum.TextYAlignment.Center,
    })
    buildLegend()

    Theme.OnLayout(function(safe)
        local width = math.min(WINDOW_WIDTH, safe.X - 16)
        local height = math.min(WINDOW_HEIGHT, safe.Y - 12)
        local nextSize = Vector2.new(width - LEGEND_WIDTH - 44, height - 100)
        if nextSize ~= boardSize then
            boardSize = nextSize
            rebuild()
        end
    end)

    Remotes.OnClient("MapUpdate", onUpdate)

    actionButton = HUD.AddAction("Map", "MAPA", 3, MapUI.Toggle)

    ClientState.Subscribe("Game", function(state)
        local inMatch = state.Phase ~= "Lobby"
        actionButton.Visible = inMatch
        if not inMatch and panel.Visible then
            MapUI.SetOpen(false)
        end
    end)

    ClientState.Subscribe("Objective", function()
        if panel.Visible then
            refreshLive()
        end
    end)

    -- Los documentos que ya leíste aparecen tildados.
    ClientState.Subscribe("Profile", function()
        if data then
            for _, marker in pairs(data.Markers) do
                if marker.Type == "Document" then
                    drawMarker(marker)
                end
            end
        end
    end)

    RunService.Heartbeat:Connect(function(deltaTime)
        if not panel.Visible then
            return
        end
        refreshClock += deltaTime
        if refreshClock >= REFRESH_INTERVAL then
            refreshClock = 0
            refreshLive()
        end
    end)

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed or input.KeyCode ~= Enum.KeyCode.M then
            return
        end
        if actionButton.Visible or panel.Visible then
            MapUI.Toggle()
        end
    end)

    requestSnapshot()
end

return MapUI
