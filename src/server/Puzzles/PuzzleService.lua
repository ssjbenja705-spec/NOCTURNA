-- Pruebas interactivas del capítulo. El cliente sólo manda jugadas ("conectá el
-- cable 2 con el borne 4"); el servidor valida cada una contra el estado real y
-- decide cuándo la prueba está resuelta. Nadie puede avisar "ya la resolví".
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local PuzzleConfig = require(Shared.Config.PuzzleConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local NoiseService = require(script.Parent.Parent.AI.NoiseService)
local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local InteractionService = require(script.Parent.Parent.World.InteractionService)
local GateService = require(script.Parent.GateService)
local PuzzleProps = require(script.Parent.PuzzleProps)
local PuzzleRules = require(script.Parent.PuzzleRules)

local MAX_ID_LENGTH = 64
local MAX_ACTION_LENGTH = 16
local MAX_TEXT_ARGUMENT = 8
local LEVER_DOWN_COLOR = Color3.fromRGB(226, 160, 40)

local PuzzleService = {}
local puzzles = {}
local sessions = {}
local cluesRead = {}
local solvedHandlers = {}
local rng = nil

function PuzzleService.KeyFor(feature)
    return feature.Link or feature.Id
end

local function titleOf(puzzle)
    return puzzle.Spec.Label or PuzzleConfig.Types[puzzle.Type].Title
end

local function viewOf(puzzle)
    return PuzzleRules[puzzle.Type].View(puzzle.State, os.clock())
end

local function send(player, puzzle, event, message)
    local definition = PuzzleConfig.Types[puzzle.Type]
    Remotes.FireClient("PuzzleUpdate", player, {
        Event = event,
        Id = puzzle.Key,
        Type = puzzle.Type,
        Title = titleOf(puzzle),
        Instructions = definition.Instructions,
        View = viewOf(puzzle),
        Message = message,
    })
end

local function broadcast(puzzle, event, message)
    for viewer in pairs(puzzle.Viewers) do
        local session = sessions[viewer]
        if session and session.Puzzle == puzzle then
            send(viewer, puzzle, event, message)
        else
            puzzle.Viewers[viewer] = nil
        end
    end
end

local function close(player, message)
    local session = sessions[player]
    if not session then
        return
    end
    sessions[player] = nil
    session.Puzzle.Viewers[player] = nil
    Remotes.FireClient("PuzzleUpdate", player, {Event = "Close", Id = session.Puzzle.Key, Message = message})
end

local function penalty(puzzle, player)
    local position = puzzle.Position
    if position then
        NoiseService.Emit(position, GameConfig.Noise.Door, player)
        Remotes.FireAll("PlaySound", "DoorLocked", position)
    end
end

local function solve(puzzle, player)
    if puzzle.Solved then
        return
    end
    puzzle.Solved = true

    for viewer in pairs(puzzle.Viewers) do
        if sessions[viewer] and sessions[viewer].Puzzle == puzzle then
            sessions[viewer] = nil
            send(viewer, puzzle, "Solved", "¡Listo!")
        end
    end
    table.clear(puzzle.Viewers)

    for _, light in ipairs(puzzle.Lights) do
        PuzzleProps.SetLamp(light, PuzzleProps.DoneColor)
    end
    for _, lever in pairs(puzzle.Levers) do
        PuzzleProps.SetLever(lever.Handle, true)
    end
    if puzzle.Position then
        Remotes.FireAll("PlaySound", "MachineStart", puzzle.Position)
    end
    Remotes.FireAll("StoryNotice", player.DisplayName .. " resolvió: " .. titleOf(puzzle))

    for _, handler in ipairs(solvedHandlers) do
        handler(puzzle.Key, player)
    end
end

local function alivePlayers()
    local count = 0
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            count += 1
        end
    end
    return count
end

-- Con compañeros vivos, las palancas tienen que bajarse casi a la vez; quien
-- juega solo tiene tiempo de correr de una a la otra.
local function pullLever(puzzle, feature, player)
    local config = PuzzleConfig.Levers
    local index = feature.Lever or 1
    local now = os.clock()
    puzzle.FirstPull = puzzle.FirstPull or now
    local team = alivePlayers() >= 2 and now - puzzle.FirstPull < config.TeamGrace
    local window = team and config.TeamWindow or config.SoloWindow

    local outcome = PuzzleRules.Levers.Pull(puzzle.State, index, now, window)
    if outcome == "Invalid" then
        return
    end

    local lever = puzzle.Levers[index]
    if lever then
        PuzzleProps.SetLever(lever.Handle, true)
        PuzzleProps.SetLamp(lever.Light, LEVER_DOWN_COLOR)
        Remotes.FireAll("PlaySound", "Metal", lever.Position)
    end

    if outcome == "Solved" then
        solve(puzzle, player)
        return
    end

    Remotes.FireClient("StoryNotice", player, team
        and "Palanca abajo. ¡Alguien tiene que bajar la otra al mismo tiempo!"
        or "La palanca quedó trabada unos segundos. ¡Corré a la otra!")

    puzzle.LeverTokens[index] = now
    task.delay(window, function()
        if puzzle.Solved or puzzle.LeverTokens[index] ~= now then
            return
        end
        if lever and lever.Handle.Parent then
            PuzzleProps.SetLever(lever.Handle, false)
            PuzzleProps.SetLamp(lever.Light, PuzzleProps.PendingColor)
        end
        Remotes.FireClient("StoryNotice", player, "La palanca volvió a subir.")
    end)
end

local function simpleArgument(value)
    local kind = typeof(value)
    return value == nil or kind == "number" or (kind == "string" and #value <= MAX_TEXT_ARGUMENT)
end

local function handleAction(player, puzzleId, action, first, second)
    if typeof(puzzleId) ~= "string" or #puzzleId > MAX_ID_LENGTH then
        return
    end
    if typeof(action) ~= "string" or #action > MAX_ACTION_LENGTH then
        return
    end

    local session = sessions[player]
    if not session or session.Puzzle.Key ~= puzzleId then
        return
    end
    if action == "Close" then
        close(player)
        return
    end

    local puzzle = session.Puzzle
    if puzzle.Solved or not GameState.IsPlaying() then
        close(player)
        return
    end
    -- Se revalida la distancia en cada jugada: nadie resuelve un panel desde lejos.
    if not InteractionService.CanInteract(player, session.Prompt) then
        close(player, "Te alejaste del panel.")
        return
    end

    local rules = PuzzleRules[puzzle.Type]
    if not rules.Actions[action] or not simpleArgument(first) or not simpleArgument(second) then
        return
    end

    local outcome, message = rules.Apply(puzzle.State, action, first, second, os.clock())
    if outcome == "Solved" then
        solve(puzzle, player)
    elseif outcome == "Wrong" then
        penalty(puzzle, player)
        broadcast(puzzle, "Wrong", message)
    elseif outcome == "Ok" then
        broadcast(puzzle, "State", message)
    elseif outcome == "Blocked" then
        send(player, puzzle, "State", message)
    end
end

-- Arma el estado de todas las pruebas del plan antes de construir el mapa, para
-- que las pistas pintadas ya conozcan su clave.
function PuzzleService.Prepare(plan)
    PuzzleService.Clear()
    -- Claves y secuencias nuevas en cada capítulo, sembradas con la hora del servidor.
    rng = Random.new(math.floor(workspace:GetServerTimeNow() * 1000) % 2147483646 + 1)
    for _, feature in ipairs(plan.Features) do
        if feature.Kind == "Puzzle" then
            local key = PuzzleService.KeyFor(feature)
            if not puzzles[key] then
                puzzles[key] = {
                    Key = key,
                    Type = feature.Puzzle,
                    Spec = feature,
                    State = PuzzleRules.New(feature.Puzzle, feature, rng),
                    Solved = false,
                    Viewers = {},
                    Lights = {},
                    Levers = {},
                    LeverTokens = {},
                }
            end
        end
    end
end

function PuzzleService.Build(folder, feature, cframe)
    local puzzle = puzzles[PuzzleService.KeyFor(feature)]
    local holder, prompt, light, extra = PuzzleProps.Build(folder, feature, cframe)
    holder:SetAttribute("NocturnaPuzzleId", PuzzleService.KeyFor(feature))

    if puzzle then
        puzzle.Position = puzzle.Position or holder.PrimaryPart.Position
        table.insert(puzzle.Lights, light)
        if feature.Puzzle == "Levers" then
            puzzle.Levers[feature.Lever or 1] = {Handle = extra, Light = light, Position = holder.PrimaryPart.Position}
        end
    end
    return holder, prompt, light
end

function PuzzleService.ClueText(key)
    local puzzle = puzzles[key]
    if not puzzle then
        return "???"
    end
    if puzzle.Type == "Keypad" then
        return PuzzleRules.SpacedCode(puzzle.State.Code)
    elseif puzzle.Type == "Breakers" then
        return table.concat(puzzle.State.Sequence, " - ")
    end
    return "???"
end

function PuzzleService.BuildClue(folder, feature, cframe)
    return PuzzleProps.Clue(folder, feature, cframe, PuzzleService.ClueText(feature.For))
end

-- Quien examina la pista la ve de cerca; el grupo se entera de que alguien la tiene.
function PuzzleService.ReadClue(player, feature)
    local puzzle = puzzles[feature.For]
    if not puzzle then
        return
    end

    local text = PuzzleService.ClueText(puzzle.Key)
    Remotes.FireClient("PuzzleUpdate", player, {
        Event = "Clue",
        Id = puzzle.Key,
        Title = feature.Label or "Algo escrito en la pared",
        Text = text,
        Code = puzzle.Type == "Keypad" and puzzle.State.Code or nil,
    })

    if not cluesRead[puzzle.Key] then
        cluesRead[puzzle.Key] = true
        Remotes.FireAll("StoryNotice", player.DisplayName .. " encontró algo escrito en la pared.")
        EventBus.Emit("PuzzleClueRead", puzzle.Key, player)
    end
end

function PuzzleService.IsClueRead(key)
    return cluesRead[key] == true
end

-- Abre el panel de la prueba para este jugador, o baja una palanca.
function PuzzleService.Interact(player, feature, prompt)
    local puzzle = puzzles[PuzzleService.KeyFor(feature)]
    if not puzzle or puzzle.Solved then
        return
    end

    if puzzle.Type == "Levers" then
        pullLever(puzzle, feature, player)
        return
    end

    local previous = sessions[player]
    if previous and previous.Puzzle ~= puzzle then
        close(player)
    end
    sessions[player] = {Puzzle = puzzle, Prompt = prompt}
    puzzle.Viewers[player] = true
    send(player, puzzle, "Open")
end

function PuzzleService.OnSolved(handler)
    table.insert(solvedHandlers, handler)
end

function PuzzleService.Get(key)
    return puzzles[key]
end

function PuzzleService.IsSolved(key)
    local puzzle = puzzles[key]
    return puzzle ~= nil and puzzle.Solved
end

function PuzzleService.SessionOf(player)
    local session = sessions[player]
    return session and session.Puzzle.Key
end

function PuzzleService.Clear()
    for player, session in pairs(sessions) do
        Remotes.FireClient("PuzzleUpdate", player, {Event = "Close", Id = session.Puzzle.Key})
    end
    table.clear(sessions)
    table.clear(puzzles)
    table.clear(cluesRead)
end

function PuzzleService.Start()
    GateService.Start()

    Remotes.OnServer("PuzzleAction", PuzzleConfig.ActionsPerSecond, handleAction)

    Players.PlayerRemoving:Connect(function(player)
        local session = sessions[player]
        if session then
            session.Puzzle.Viewers[player] = nil
            sessions[player] = nil
        end
    end)
end

return PuzzleService
