-- Reglas de cada prueba: arman el estado, validan cada jugada y preparan la vista
-- que recibe el cliente, sin las respuestas. Son funciones puras: no tocan
-- instancias ni remotos, así se pueden probar sin el juego.
--
-- Resultado de una jugada:
--   "Invalid": datos mal formados o trampa; se ignora en silencio.
--   "Blocked": jugada válida que no cambia nada; aviso sin castigo.
--   "Ok": progreso. "Wrong": error con castigo. "Solved": prueba resuelta.
local Shared = game:GetService("ReplicatedStorage").Shared
local PuzzleConfig = require(Shared.Config.PuzzleConfig)

local PuzzleRules = {}

local function isIndex(value, maximum)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= 1 and value <= maximum
end

local function shuffle(list, rng)
    for index = #list, 2, -1 do
        local other = rng:NextInteger(1, index)
        list[index], list[other] = list[other], list[index]
    end
    return list
end

local function range(count)
    local list = {}
    for index = 1, count do
        list[index] = index
    end
    return list
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, inner in pairs(value) do
        copy[key] = deepCopy(inner)
    end
    return copy
end

PuzzleRules.IsIndex = isIndex

-- Cables ------------------------------------------------------------------------

local Wires = {Actions = {Connect = true}}

function Wires.New(spec, rng)
    local count = math.clamp(spec.Count or PuzzleConfig.Wires.Count, 2, #PuzzleConfig.WireColors)
    local left = shuffle(range(count), rng)
    local right = shuffle(range(count), rng)

    -- Si quedaran todos enfrentados no habría nada que pensar.
    local aligned = true
    for index = 1, count do
        if left[index] ~= right[index] then
            aligned = false
        end
    end
    if aligned then
        right[1], right[2] = right[2], right[1]
    end

    return {Count = count, Left = left, Right = right, Links = {}, Used = {}}
end

function Wires.View(state)
    local links = {}
    for leftIndex, rightIndex in pairs(state.Links) do
        table.insert(links, {leftIndex, rightIndex})
    end
    table.sort(links, function(a, b)
        return a[1] < b[1]
    end)
    return {Left = table.clone(state.Left), Right = table.clone(state.Right), Links = links}
end

function Wires.Apply(state, action, leftIndex, rightIndex)
    if action ~= "Connect" or not isIndex(leftIndex, state.Count) or not isIndex(rightIndex, state.Count) then
        return "Invalid"
    end
    if state.Links[leftIndex] or state.Used[rightIndex] then
        return "Blocked", "Ese cable ya está conectado."
    end
    if state.Left[leftIndex] ~= state.Right[rightIndex] then
        return "Wrong", "¡Chispazo! Ese borne no es de ese color."
    end

    state.Links[leftIndex] = rightIndex
    state.Used[rightIndex] = true
    for index = 1, state.Count do
        if not state.Links[index] then
            return "Ok"
        end
    end
    return "Solved"
end

-- Disyuntores -----------------------------------------------------------------

local Breakers = {Actions = {Flip = true}}

function Breakers.New(spec, rng)
    local sequence = spec.Sequence and table.clone(spec.Sequence)
        or shuffle(range(spec.Count or PuzzleConfig.Breakers.Count), rng)
    local on = {}
    for index = 1, #sequence do
        on[index] = false
    end
    return {Count = #sequence, Sequence = sequence, On = on, Progress = 0, Clue = spec.Clue}
end

function Breakers.View(state)
    return {
        Count = state.Count,
        On = table.clone(state.On),
        ClueDocument = state.Clue and state.Clue.Document,
        ClueHint = state.Clue and state.Clue.Hint,
    }
end

function Breakers.Apply(state, action, index)
    if action ~= "Flip" or not isIndex(index, state.Count) then
        return "Invalid"
    end
    if state.On[index] then
        return "Blocked", "Esa térmica ya está arriba."
    end

    if state.Sequence[state.Progress + 1] ~= index then
        for other = 1, state.Count do
            state.On[other] = false
        end
        state.Progress = 0
        return "Wrong", "¡Saltó la térmica! El tablero se reinició."
    end

    state.On[index] = true
    state.Progress += 1
    return state.Progress >= state.Count and "Solved" or "Ok"
end

-- Válvulas de presión ---------------------------------------------------------

local Valves = {Actions = {Turn = true}}

-- Manómetros después de girar una válvula; nil si alguno se pasa de rango.
function PuzzleRules.TurnValve(gauges, effects, maximum, valve, direction)
    local result = table.clone(gauges)
    for gauge, change in ipairs(effects[valve]) do
        result[gauge] += change * direction
        if result[gauge] < 0 or result[gauge] > maximum then
            return nil
        end
    end
    return result
end

local function balanced(state)
    for _, value in ipairs(state.Gauges) do
        if value ~= state.Target then
            return false
        end
    end
    return true
end

function Valves.New(spec, rng)
    local config = PuzzleConfig.Valves
    local state = {
        Count = config.Count,
        Max = config.Max,
        Target = config.Target,
        Effects = deepCopy(config.Effects),
        Gauges = {},
    }
    for index = 1, config.Count do
        state.Gauges[index] = config.Target
    end

    -- Se desordena con jugadas válidas: siempre existe el camino de vuelta.
    local wanted = spec.Scramble or config.Scramble
    local moves, attempts = 0, 0
    while (moves < wanted or balanced(state)) and attempts < 400 do
        attempts += 1
        local valve = rng:NextInteger(1, config.Count)
        local direction = rng:NextInteger(0, 1) == 0 and -1 or 1
        local nextGauges = PuzzleRules.TurnValve(state.Gauges, state.Effects, state.Max, valve, direction)
        if nextGauges then
            state.Gauges = nextGauges
            moves += 1
        end
    end
    return state
end

function Valves.View(state)
    return {
        Gauges = table.clone(state.Gauges),
        Target = state.Target,
        Max = state.Max,
        Effects = deepCopy(state.Effects),
    }
end

function Valves.Apply(state, action, valve, direction)
    if action ~= "Turn" or not isIndex(valve, state.Count) or (direction ~= 1 and direction ~= -1) then
        return "Invalid"
    end
    local nextGauges = PuzzleRules.TurnValve(state.Gauges, state.Effects, state.Max, valve, direction)
    if not nextGauges then
        return "Wrong", "¡Sobrepresión! El caño silba: esa válvula no da más para ese lado."
    end
    state.Gauges = nextGauges
    return balanced(state) and "Solved" or "Ok"
end

-- Cerradura con clave ---------------------------------------------------------

local Keypad = {Actions = {Submit = true}}

function Keypad.New(spec, rng)
    local code = spec.Code
    if not code then
        local digits = {}
        for index = 1, PuzzleConfig.Keypad.Length do
            digits[index] = tostring(rng:NextInteger(index == 1 and 1 or 0, 9))
        end
        code = table.concat(digits)
    end
    return {Length = #code, Code = code, Clue = spec.Clue}
end

-- Locked lo completa PuzzleService para cada jugador: el bloqueo es de quien se
-- equivocó, no del teclado (si no, uno solo lo dejaría trabado para todos).
function Keypad.View(state)
    return {
        Length = state.Length,
        Locked = false,
        ClueDocument = state.Clue and state.Clue.Document,
        ClueHint = state.Clue and state.Clue.Hint,
    }
end

function Keypad.Apply(state, action, code)
    if action ~= "Submit" or type(code) ~= "string" or #code ~= state.Length or not string.match(code, "^%d+$") then
        return "Invalid"
    end
    if code == state.Code then
        return "Solved"
    end
    return "Wrong", "Código incorrecto."
end

-- Texto pintado en la pared para una clave: "4 7 1 9".
function PuzzleRules.SpacedCode(code)
    return (string.gsub(code, "(%d)", "%1 ")):sub(1, -2)
end

-- Tablero de distribución -----------------------------------------------------
-- Lados: 1 norte, 2 este, 3 sur, 4 oeste, en sentido horario. La fila crece hacia el sur.

local Power = {Actions = {Rotate = true}}

local BASE_OPENINGS = PuzzleConfig.Power.Pieces
local STEPS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}
local KINDS = {"I", "L", "T"}

PuzzleRules.PowerSteps = STEPS

function PuzzleRules.Opposite(side)
    return (side + 1) % 4 + 1
end

function PuzzleRules.PowerOpenings(kind, rotation)
    local result = {}
    for _, side in ipairs(BASE_OPENINGS[kind] or {}) do
        result[(side - 1 + rotation) % 4 + 1] = true
    end
    return result
end

local function cellIndex(state, x, y)
    return (y - 1) * state.Columns + x
end

-- Celdas con corriente y si la corriente llega a la salida.
function PuzzleRules.PowerFlow(state)
    local reached = {}
    local tiles = state.Tiles
    local start = cellIndex(state, 1, state.Source)
    if not PuzzleRules.PowerOpenings(tiles[start].Type, tiles[start].Rot)[4] then
        return reached, false
    end

    reached[start] = true
    local queue = {{1, state.Source}}
    local head = 1
    while queue[head] do
        local x, y = queue[head][1], queue[head][2]
        head += 1
        local tile = tiles[cellIndex(state, x, y)]
        for side in pairs(PuzzleRules.PowerOpenings(tile.Type, tile.Rot)) do
            local nx, ny = x + STEPS[side][1], y + STEPS[side][2]
            if nx >= 1 and nx <= state.Columns and ny >= 1 and ny <= state.Rows then
                local index = cellIndex(state, nx, ny)
                local other = tiles[index]
                if not reached[index] and PuzzleRules.PowerOpenings(other.Type, other.Rot)[PuzzleRules.Opposite(side)] then
                    reached[index] = true
                    table.insert(queue, {nx, ny})
                end
            end
        end
    end

    local sink = cellIndex(state, state.Columns, state.Sink)
    local done = reached[sink] == true and PuzzleRules.PowerOpenings(tiles[sink].Type, tiles[sink].Rot)[2] == true
    return reached, done
end

local function randomPath(state, rng)
    local visited = {}
    local path = {}

    local function walk(x, y)
        visited[cellIndex(state, x, y)] = true
        table.insert(path, {x, y})
        if x == state.Columns and y == state.Sink then
            return true
        end
        for _, side in ipairs(shuffle({1, 2, 3, 4}, rng)) do
            local nx, ny = x + STEPS[side][1], y + STEPS[side][2]
            if nx >= 1 and nx <= state.Columns and ny >= 1 and ny <= state.Rows
                and not visited[cellIndex(state, nx, ny)] and walk(nx, ny) then
                return true
            end
        end
        table.remove(path)
        return false
    end

    walk(1, state.Source)
    return path
end

local function sideBetween(from, to)
    for side, step in ipairs(STEPS) do
        if from[1] + step[1] == to[1] and from[2] + step[2] == to[2] then
            return side
        end
    end
    return nil
end

function Power.New(spec, rng)
    local config = PuzzleConfig.Power
    local state = {
        Columns = spec.Columns or config.Columns,
        Rows = spec.Rows or config.Rows,
        Tiles = {},
    }
    state.Source = rng:NextInteger(1, state.Rows)
    state.Sink = rng:NextInteger(1, state.Rows)

    for index = 1, state.Columns * state.Rows do
        state.Tiles[index] = {Type = KINDS[rng:NextInteger(1, #KINDS)], Rot = rng:NextInteger(0, 3)}
    end

    -- El camino garantizado usa sólo rectas y codos; el resto es relleno al azar.
    local path = randomPath(state, rng)
    for step, cell in ipairs(path) do
        local entry = step == 1 and 4 or sideBetween(cell, path[step - 1])
        local exit = step == #path and 2 or sideBetween(cell, path[step + 1])
        local kind = PuzzleRules.Opposite(entry) == exit and "I" or "L"
        state.Tiles[cellIndex(state, cell[1], cell[2])] = {Type = kind, Rot = rng:NextInteger(0, 3)}
    end

    local guard = 0
    while select(2, PuzzleRules.PowerFlow(state)) and guard < 20 do
        guard += 1
        local cell = path[rng:NextInteger(1, #path)]
        local tile = state.Tiles[cellIndex(state, cell[1], cell[2])]
        tile.Rot = (tile.Rot + 1) % 4
    end
    return state
end

function Power.View(state)
    local reached = PuzzleRules.PowerFlow(state)
    local tiles, powered = {}, {}
    for index, tile in ipairs(state.Tiles) do
        tiles[index] = {Type = tile.Type, Rot = tile.Rot}
        powered[index] = reached[index] == true
    end
    return {
        Columns = state.Columns,
        Rows = state.Rows,
        Source = state.Source,
        Sink = state.Sink,
        Tiles = tiles,
        Powered = powered,
    }
end

function Power.Apply(state, action, index)
    if action ~= "Rotate" or not isIndex(index, #state.Tiles) then
        return "Invalid"
    end
    local tile = state.Tiles[index]
    tile.Rot = (tile.Rot + 1) % 4
    local _, done = PuzzleRules.PowerFlow(state)
    return done and "Solved" or "Ok"
end

-- Señal para repetir ----------------------------------------------------------

local Simon = {Actions = {Press = true}}

local function newSignal(state)
    local sequence = {}
    for index = 1, state.Rounds[#state.Rounds] do
        sequence[index] = state.Rng:NextInteger(1, state.Buttons)
    end
    state.Sequence = sequence
    state.Round = 1
    state.Position = 0
end

function Simon.New(spec, rng)
    local state = {
        Rounds = table.clone(spec.Rounds or PuzzleConfig.Simon.Rounds),
        Buttons = #PuzzleConfig.Simon.Buttons,
        Rng = rng,
    }
    newSignal(state)
    return state
end

function Simon.View(state)
    local show = {}
    for index = 1, state.Rounds[state.Round] do
        show[index] = state.Sequence[index]
    end
    return {
        Buttons = state.Buttons,
        Round = state.Round,
        TotalRounds = #state.Rounds,
        Show = show,
        Position = state.Position,
    }
end

function Simon.Apply(state, action, button)
    if action ~= "Press" or not isIndex(button, state.Buttons) then
        return "Invalid"
    end

    if state.Sequence[state.Position + 1] ~= button then
        newSignal(state)
        return "Wrong", "Se perdió la señal. Empezá de nuevo."
    end

    state.Position += 1
    if state.Position < state.Rounds[state.Round] then
        return "Ok"
    end

    if state.Round >= #state.Rounds then
        return "Solved"
    end
    state.Round += 1
    state.Position = 0
    return "Ok", "¡Bien! Escuchá la señal que sigue."
end

-- Pares de recuerdos ----------------------------------------------------------

local Memory = {Actions = {Flip = true}}

function Memory.New(spec, rng)
    local config = PuzzleConfig.Memory
    local count = math.clamp(spec.Pairs or config.Pairs, 2, #config.Symbols)
    local symbols = shuffle(table.clone(config.Symbols), rng)
    local cards = {}
    for index = 1, count do
        table.insert(cards, symbols[index])
        table.insert(cards, symbols[index])
    end
    shuffle(cards, rng)
    return {Cards = cards, Matched = {}, Revealed = {}, MatchedCount = 0}
end

function Memory.View(state)
    local cards = {}
    for index, symbol in ipairs(state.Cards) do
        local matched = state.Matched[index] == true
        local revealed = table.find(state.Revealed, index) ~= nil
        cards[index] = {
            Symbol = (matched or revealed) and symbol or "",
            Matched = matched,
            Revealed = revealed,
        }
    end
    return {Count = #state.Cards, Cards = cards}
end

function Memory.Apply(state, action, index)
    if action ~= "Flip" or not isIndex(index, #state.Cards) then
        return "Invalid"
    end
    if state.Matched[index] or table.find(state.Revealed, index) then
        return "Blocked"
    end

    -- Un par que no coincidió queda a la vista hasta la próxima foto.
    if #state.Revealed >= 2 then
        table.clear(state.Revealed)
    end
    table.insert(state.Revealed, index)
    if #state.Revealed < 2 then
        return "Ok"
    end

    local first, second = state.Revealed[1], state.Revealed[2]
    if state.Cards[first] ~= state.Cards[second] then
        return "Ok", "No coinciden."
    end

    state.Matched[first] = true
    state.Matched[second] = true
    state.MatchedCount += 2
    table.clear(state.Revealed)
    if state.MatchedCount >= #state.Cards then
        return "Solved"
    end
    return "Ok", "¡Un par!"
end

-- Palancas simultáneas --------------------------------------------------------

local Levers = {Actions = {}}

function Levers.New(spec)
    return {Count = spec.Levers or 2, Down = {}}
end

function Levers.View(state, now)
    local down = {}
    for index = 1, state.Count do
        down[index] = (state.Down[index] or 0) > (now or 0)
    end
    return {Count = state.Count, Down = down}
end

function Levers.Apply()
    return "Invalid"
end

-- Baja una palanca, que queda abajo `window` segundos. Se resuelve si todas lo están.
function Levers.Pull(state, lever, now, window)
    if not isIndex(lever, state.Count) then
        return "Invalid"
    end
    state.Down[lever] = now + window
    for index = 1, state.Count do
        if (state.Down[index] or 0) <= now then
            return "Ok"
        end
    end
    return "Solved"
end

-- Errores de cada jugador ------------------------------------------------------
-- Cada jugador lleva su propia cuenta en cada prueba. Quien junta errores queda
-- bloqueado él solo, cada vez más tiempo; los demás siguen jugando.

function PuzzleRules.NewRecord()
    return {Wrongs = 0, Level = 0, Until = 0, Last = -math.huge}
end

-- Segundos que le faltan a ese jugador para poder volver a intentar.
function PuzzleRules.LockedFor(record, now)
    if not record then
        return 0
    end
    return math.max(0, record.Until - now)
end

-- Anota un error. Devuelve los segundos de bloqueo que le tocan (0 si todavía no).
function PuzzleRules.Strike(record, kind, now)
    local config = PuzzleConfig.Lockout
    if now - record.Last > config.Forget then
        record.Wrongs = 0
        record.Level = 0
    end
    record.Last = now
    record.Wrongs += 1
    if record.Wrongs < (config.Strikes[kind] or config.Strikes.Default) then
        return 0
    end

    local base = config.Base[kind] or config.Base.Default
    local seconds = math.min(base * config.Growth ^ record.Level, config.Max)
    record.Wrongs = 0
    record.Level += 1
    record.Until = now + seconds
    return seconds
end

PuzzleRules.Wires = Wires
PuzzleRules.Breakers = Breakers
PuzzleRules.Valves = Valves
PuzzleRules.Keypad = Keypad
PuzzleRules.Power = Power
PuzzleRules.Simon = Simon
PuzzleRules.Memory = Memory
PuzzleRules.Levers = Levers

PuzzleRules.Types = {"Wires", "Breakers", "Valves", "Keypad", "Power", "Simon", "Memory", "Levers"}

function PuzzleRules.New(kind, spec, rng)
    local rules = PuzzleRules[kind]
    assert(rules and rules.New, "[NOCTURNA] Tipo de prueba desconocido: " .. tostring(kind))
    return rules.New(spec, rng)
end

return PuzzleRules
