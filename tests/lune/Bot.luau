--!nocheck
-- Jugador simulado: lee el objetivo que le manda el servidor, camina hasta el lugar
-- y usa el prompt que el servidor creó ahí, igual que una persona. Las pruebas las
-- resuelve con el mismo remoto que usa el panel del cliente, mirando sólo lo que
-- ve un jugador: el panel, las pistas pintadas y los documentos.
local Bot = {}

local ACTIONS_PER_STEP = 3
local SESSION_WINDOW = 800
local SESSION_EVENTS = {Open = true, State = true, Wrong = true, Solved = true, Close = true}

local memories = setmetatable({}, {__mode = "k"})

local function memoryFor(player)
    local memory = memories[player]
    if not memory then
        memory = {Codes = {}, Cards = {}}
        memories[player] = memory
    end
    return memory
end

local function promptHost(prompt)
    return prompt.Parent
end

local function allPrompts(Engine)
    local prompts = {}
    for _, descendant in ipairs(Engine.Workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") and descendant.Enabled then
            table.insert(prompts, descendant)
        end
    end
    return prompts
end

function Bot.NearestPrompt(Engine, position)
    local best, bestDistance = nil, math.huge
    for _, prompt in ipairs(allPrompts(Engine)) do
        local host = promptHost(prompt)
        if host:IsA("BasePart") then
            local distance = (host.Position - position).Magnitude
            if distance < bestDistance then
                best, bestDistance = prompt, distance
            end
        end
    end
    return best, bestDistance
end

-- El bot se teletransporta: el antitrampas lo trataría (con razón) como un tramposo.
function Bot.MoveTo(Engine, player, position)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if root then
        Engine.RequireServer("Security.AntiCheat").Grace(player, 3)
        root.CFrame = Engine.Roblox.CFrame.new(position.X, 3, position.Z)
    end
end

function Bot.Use(Engine, player, position)
    Bot.MoveTo(Engine, player, position)
    local prompt = Bot.NearestPrompt(Engine, position)
    if prompt then
        local host = promptHost(prompt)
        Bot.MoveTo(Engine, player, host.Position)
        prompt:Fire(player)
    end
    return prompt
end

-- Manda un remoto como si lo mandara el cliente de ese jugador.
function Bot.Fire(Engine, player, name, ...)
    local remote = Engine.Services.ReplicatedStorage:FindFirstChild("NocturnaRemotes"):FindFirstChild(name)
    local saved = Engine.LocalPlayer
    Engine.LocalPlayer = player
    remote:FireServer(...)
    Engine.LocalPlayer = saved
end

-- Último estado del panel de una prueba que recibió este jugador.
function Bot.PuzzleSession(Engine, player, puzzleId)
    local sent = Engine.Sent
    for index = #sent, math.max(1, #sent - SESSION_WINDOW), -1 do
        local entry = sent[index]
        if entry.Name == "PuzzleUpdate" and entry.Player == player then
            local data = entry.Args[1]
            if data and data.Id == puzzleId and SESSION_EVENTS[data.Event] then
                return data
            end
        end
    end
    return nil
end

local function lastClue(Engine, player, puzzleId)
    local sent = Engine.Sent
    for index = #sent, math.max(1, #sent - SESSION_WINDOW), -1 do
        local entry = sent[index]
        if entry.Name == "PuzzleUpdate" and entry.Player == player then
            local data = entry.Args[1]
            if data and data.Id == puzzleId and data.Event == "Clue" then
                return data
            end
        end
    end
    return nil
end

local function act(Engine, player, puzzleId, action, first, second)
    Bot.Fire(Engine, player, "PuzzleAction", puzzleId, action, first, second)
    return Bot.PuzzleSession(Engine, player, puzzleId)
end

local function isOpen(session)
    return session ~= nil and (session.Event == "Open" or session.Event == "State" or session.Event == "Wrong")
end

-- Clave escrita en un documento con puntos medios: "3 · 1 · 4 · 2".
function Bot.DocumentCode(Engine, documentId)
    local document = Engine.RequireShared("Config.DocumentConfig")[documentId]
    if not document then
        return nil
    end
    local start = string.find(document.Body, "%d ·")
    if not start then
        return nil
    end
    local digits = {}
    for digit in string.gmatch(string.match(document.Body, "^[%d ·]+", start), "%d") do
        table.insert(digits, tonumber(digit))
    end
    return digits
end

local function findClue(Engine, puzzleId)
    for _, descendant in ipairs(Engine.Workspace:GetDescendants()) do
        if descendant:IsA("Model") and descendant:GetAttribute("NocturnaClueFor") == puzzleId and descendant.PrimaryPart then
            return descendant.PrimaryPart.Position
        end
    end
    return nil
end

-- Resolución de cada tipo ---------------------------------------------------------

local Solvers = {}

function Solvers.Wires(Engine, player, session)
    for _ = 1, ACTIONS_PER_STEP do
        local view = session.View
        local linked, used = {}, {}
        for _, link in ipairs(view.Links) do
            linked[link[1]] = true
            used[link[2]] = true
        end
        local done = true
        for left, color in ipairs(view.Left) do
            if not linked[left] then
                done = false
                for right, other in ipairs(view.Right) do
                    if other == color and not used[right] then
                        session = act(Engine, player, session.Id, "Connect", left, right)
                        break
                    end
                end
                break
            end
        end
        if done or not isOpen(session) then
            return
        end
    end
end

function Solvers.Breakers(Engine, player, session)
    local order = Bot.DocumentCode(Engine, session.View.ClueDocument)
    if not order then
        return
    end
    for _ = 1, ACTIONS_PER_STEP do
        local progress = 0
        for _, on in ipairs(session.View.On) do
            if on then
                progress += 1
            end
        end
        session = act(Engine, player, session.Id, "Flip", order[progress + 1])
        if not isOpen(session) then
            return
        end
    end
end

-- Camino más corto de giros hasta dejar todos los manómetros en la marca.
function Bot.ValveMoves(view)
    local function key(gauges)
        return table.concat(gauges, ",")
    end
    local function balanced(gauges)
        for _, value in ipairs(gauges) do
            if value ~= view.Target then
                return false
            end
        end
        return true
    end

    local queue = {{Gauges = view.Gauges, Moves = {}}}
    local seen = {[key(view.Gauges)] = true}
    local head = 1
    while queue[head] do
        local node = queue[head]
        head += 1
        if balanced(node.Gauges) then
            return node.Moves
        end
        for valve, effects in ipairs(view.Effects) do
            for _, direction in ipairs({1, -1}) do
                local nextGauges = table.clone(node.Gauges)
                local valid = true
                for gauge, change in ipairs(effects) do
                    nextGauges[gauge] += change * direction
                    if nextGauges[gauge] < 0 or nextGauges[gauge] > view.Max then
                        valid = false
                    end
                end
                if valid and not seen[key(nextGauges)] then
                    seen[key(nextGauges)] = true
                    local moves = table.clone(node.Moves)
                    table.insert(moves, {valve, direction})
                    table.insert(queue, {Gauges = nextGauges, Moves = moves})
                end
            end
        end
    end
    return nil
end

function Solvers.Valves(Engine, player, session)
    local moves = Bot.ValveMoves(session.View)
    if not moves then
        return
    end
    for index = 1, math.min(ACTIONS_PER_STEP, #moves) do
        session = act(Engine, player, session.Id, "Turn", moves[index][1], moves[index][2])
        if not isOpen(session) then
            return
        end
    end
end

function Solvers.Keypad(Engine, player, session, memory)
    local code = memory.Codes[session.Id]
    if not code and session.View.ClueDocument then
        local digits = Bot.DocumentCode(Engine, session.View.ClueDocument)
        code = digits and table.concat(digits)
    end
    -- Si el teclado sigue bloqueado, el servidor lo dice y se reintenta en el próximo paso.
    if code then
        act(Engine, player, session.Id, "Submit", code)
    end
end

local function opposite(side)
    return (side + 1) % 4 + 1
end

local STEPS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

-- Rotación que necesita cada pieza del camino de la entrada a la salida.
function Bot.PowerTargets(Engine, view)
    local pieces = Engine.RequireShared("Config.PuzzleConfig").Power.Pieces
    local function openings(kind, rotation)
        local result = {}
        for _, side in ipairs(pieces[kind]) do
            result[(side - 1 + rotation) % 4 + 1] = true
        end
        return result
    end
    local function canJoin(kind, entry, exit)
        if kind == "I" then
            return opposite(entry) == exit
        elseif kind == "L" then
            return opposite(entry) ~= exit
        end
        return true
    end

    local columns, rows = view.Columns, view.Rows
    local function index(x, y)
        return (y - 1) * columns + x
    end
    local visited, path = {}, {}

    local function walk(x, y, entry)
        local cell = index(x, y)
        visited[cell] = true
        local kind = view.Tiles[cell].Type
        for exit = 1, 4 do
            if exit ~= entry and canJoin(kind, entry, exit) then
                if x == columns and y == view.Sink and exit == 2 then
                    table.insert(path, {cell, entry, exit})
                    return true
                end
                local nx, ny = x + STEPS[exit][1], y + STEPS[exit][2]
                if nx >= 1 and nx <= columns and ny >= 1 and ny <= rows and not visited[index(nx, ny)] then
                    table.insert(path, {cell, entry, exit})
                    if walk(nx, ny, opposite(exit)) then
                        return true
                    end
                    table.remove(path)
                end
            end
        end
        visited[cell] = nil
        return false
    end

    if not walk(1, view.Source, 4) then
        return nil
    end
    local targets = {}
    for _, step in ipairs(path) do
        local cell, entry, exit = step[1], step[2], step[3]
        for rotation = 0, 3 do
            local open = openings(view.Tiles[cell].Type, rotation)
            if open[entry] and open[exit] then
                targets[cell] = rotation
                break
            end
        end
    end
    return targets
end

function Solvers.Power(Engine, player, session)
    local targets = Bot.PowerTargets(Engine, session.View)
    if not targets then
        return
    end
    local sent = 0
    for cell, rotation in pairs(targets) do
        local taps = (rotation - session.View.Tiles[cell].Rot) % 4
        for _ = 1, taps do
            if sent >= ACTIONS_PER_STEP + 1 then
                return
            end
            sent += 1
            session = act(Engine, player, session.Id, "Rotate", cell)
            if not isOpen(session) then
                return
            end
        end
    end
end

function Solvers.Simon(Engine, player, session)
    for _ = 1, ACTIONS_PER_STEP + 1 do
        local view = session.View
        session = act(Engine, player, session.Id, "Press", view.Show[view.Position + 1])
        if not isOpen(session) then
            return
        end
    end
end

local function nextMemoryCard(view, known)
    for index, card in ipairs(view.Cards) do
        if card.Symbol ~= "" then
            known[index] = card.Symbol
        end
    end

    local revealed = {}
    for index, card in ipairs(view.Cards) do
        if card.Revealed and not card.Matched then
            table.insert(revealed, index)
        end
    end
    local function free(index)
        local card = view.Cards[index]
        return not card.Matched and not (#revealed == 2 and card.Revealed)
    end

    if #revealed == 1 then
        local first = revealed[1]
        for index, symbol in pairs(known) do
            if index ~= first and symbol == known[first] and not view.Cards[index].Matched then
                return index
            end
        end
    else
        for index, symbol in pairs(known) do
            for other, otherSymbol in pairs(known) do
                if index < other and symbol == otherSymbol and free(index) and free(other) then
                    return index
                end
            end
        end
    end

    for index, card in ipairs(view.Cards) do
        if known[index] == nil and not card.Revealed and not card.Matched then
            return index
        end
    end
    for index, card in ipairs(view.Cards) do
        if not card.Revealed and not card.Matched then
            return index
        end
    end
    return nil
end

function Solvers.Memory(Engine, player, session, memory)
    memory.Cards[session.Id] = memory.Cards[session.Id] or {}
    local known = memory.Cards[session.Id]
    for _ = 1, ACTIONS_PER_STEP + 1 do
        local card = nextMemoryCard(session.View, known)
        if not card then
            return
        end
        session = act(Engine, player, session.Id, "Flip", card)
        if not isOpen(session) then
            return
        end
        nextMemoryCard(session.View, known)
    end
end

-- Palancas: con un compañero vivo, cada uno baja una a la vez; solo, corre de una a otra.
function Bot.PullLevers(Engine, player, update)
    local waypoints = update.Waypoints or {}
    if #waypoints == 0 then
        return
    end
    local mate = nil
    for _, other in ipairs(Engine.Services.Players:GetPlayers()) do
        local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
        if other ~= player and humanoid and humanoid.Health > 0 then
            mate = other
            break
        end
    end
    Bot.Use(Engine, player, waypoints[1])
    if waypoints[2] then
        Bot.Use(Engine, mate or player, waypoints[2])
    end
end

-- Un paso sobre la prueba del objetivo actual: abrirla, buscar su pista o jugar.
function Bot.SolvePuzzle(Engine, player, update)
    local kind, puzzleId = update.Puzzle, update.PuzzleId
    if kind == "Levers" then
        Bot.PullLevers(Engine, player, update)
        return
    end

    local memory = memoryFor(player)
    local waypoints = update.Waypoints or {}

    -- La clave pintada en una pared: primero hay que ir a leerla.
    if kind == "Keypad" and not memory.Codes[puzzleId] then
        local cluePosition = findClue(Engine, puzzleId)
        if cluePosition then
            Bot.Use(Engine, player, cluePosition)
            local clue = lastClue(Engine, player, puzzleId)
            if clue and clue.Code then
                memory.Codes[puzzleId] = clue.Code
            end
            return
        end
    end

    local session = Bot.PuzzleSession(Engine, player, puzzleId)
    if not isOpen(session) then
        local target = waypoints[#waypoints]
        if not target then
            return
        end
        Bot.Use(Engine, player, target)
        session = Bot.PuzzleSession(Engine, player, puzzleId)
        if not isOpen(session) then
            return
        end
    end

    local solver = Solvers[kind]
    if solver then
        solver(Engine, player, session, memory)
    end
end

-- Un paso de juego para el bot. Devuelve el identificador del objetivo actual.
function Bot.Act(Engine, player)
    local args = Engine.LastSent("ObjectiveUpdate", player)
    local update = args and args[1]
    if not update or update.Finished or not update.Waypoints then
        return nil
    end

    if update.Puzzle and update.PuzzleId then
        Bot.SolvePuzzle(Engine, player, update)
        return update.ObjectiveId
    end

    local waypoint = update.Waypoints[1]
    if not waypoint then
        return update.ObjectiveId
    end

    if update.Type == "Reach" then
        Bot.MoveTo(Engine, player, waypoint)
    else
        Bot.Use(Engine, player, waypoint)
    end
    return update.ObjectiveId
end

return Bot
