-- Ciclo de vida de la partida: capítulos, muerte, reaparición, fracaso y regreso al lobby.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local ChapterConfig = require(Shared.Config.ChapterConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local Analytics = require(script.Parent.Parent.Analytics.Analytics)
local MatchAnalytics = require(script.Parent.Parent.Analytics.MatchAnalytics)
local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local FlashlightService = require(script.Parent.Parent.Data.FlashlightService)
local ProgressionService = require(script.Parent.Parent.Data.ProgressionService)
local InventoryService = require(script.Parent.Parent.Inventory.InventoryService)
local NoiseService = require(script.Parent.Parent.AI.NoiseService)
local MonsterService = require(script.Parent.Parent.Monsters.MonsterService)
local AntiCheat = require(script.Parent.Parent.Security.AntiCheat)
local EndingService = require(script.Parent.Parent.Story.EndingService)
local StoryService = require(script.Parent.Parent.Story.StoryService)
local HidingService = require(script.Parent.Parent.World.HidingService)
local InteractionService = require(script.Parent.Parent.World.InteractionService)
local LobbyBuilder = require(script.Parent.Parent.World.LobbyBuilder)
local RoomGenerator = require(script.Parent.Parent.World.RoomGenerator)
local WorldService = require(script.Parent.Parent.World.WorldService)
local LobbyService = require(script.Parent.LobbyService)
local FinalChaseService = require(script.Parent.Parent.Final.FinalChaseService)

local CONFIG = GameConfig.Match
local TITLE_CARD_TIME = 4
local PROLOGUE_LINE_TIME = 4.5
local PARTY_UPDATE_INTERVAL = 1
local LOAD_ATTEMPTS = 2

local MatchService = {}
local runToken = 0
local down = {}
local failureToken = 0

local function isAlive(player)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local function teleport(player, cframe)
    local character = player.Character
    if not character then
        return
    end
    AntiCheat.Grace(player, 3)
    character:PivotTo(cframe)
end

local function spawnCFrame(index)
    if GameState.Phase == "Lobby" or not GameState.Layout then
        return LobbyBuilder.SpawnCFrame(index)
    end
    return GameState.Checkpoint or RoomGenerator.StartCFrame(GameState.Layout, index)
end

local function respawn(player, index)
    down[player] = nil
    Remotes.FireClient("DownState", player, {Down = false})
    player:LoadCharacter()
    if player.Parent ~= Players then
        return
    end
    teleport(player, spawnCFrame(index))
end

local function broadcastParty()
    local members = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        table.insert(members, {
            UserId = player.UserId,
            Name = player.DisplayName,
            Health = humanoid and math.ceil(humanoid.Health) or 0,
            Down = down[player] ~= nil,
            Hidden = player:GetAttribute("Hidden") == true,
        })
    end
    Remotes.FireAll("PartyUpdate", members)
end

local function computeLives()
    local extra = math.max(0, #Players:GetPlayers() - 1)
    local lives = CONFIG.LivesPerChapter + extra * CONFIG.LivesPerExtraPlayer
    return math.max(1, lives + GameState.DifficultySettings().ExtraLives)
end

local function setLives(amount)
    GameState.Lives = amount
    GameState.Broadcast()
end

local function clearChapter()
    failureToken += 1
    StoryService.Stop()
    MonsterService.Clear()
    HidingService.Clear()
    NoiseService.Clear()
    table.clear(down)
end

local function returnToLobby()
    runToken += 1
    clearChapter()
    WorldService.Unload()
    GameState.Chapter = 0
    GameState.Lives = 0
    GameState.MaxLives = 0
    GameState.SetPhase("Lobby")
    InventoryService.ClearAll()

    for index, player in ipairs(Players:GetPlayers()) do
        FlashlightService.Reset(player)
        task.spawn(respawn, player, index)
    end

    LobbyService.ResetReady()
    -- En el servidor de una partida esto devuelve al grupo a un lobby público.
    EventBus.Emit("ReturnedToLobby")
end

local function playPrologue(token)
    local duration = #ChapterConfig.Prologue * PROLOGUE_LINE_TIME
    Remotes.FireAll("Cutscene", {
        Kind = "Prologue",
        Lines = ChapterConfig.Prologue,
        LineTime = PROLOGUE_LINE_TIME,
        Duration = duration,
    })
    task.wait(duration)
    return token == runToken
end

local function clearQuestItems()
    for _, player in ipairs(Players:GetPlayers()) do
        InventoryService.TakeQuestItems(player)
    end
end

local function runChapter(chapterIndex, withPrologue)
    runToken += 1
    local token = runToken
    local chapter = ChapterConfig[chapterIndex]

    clearChapter()
    GameState.Chapter = chapterIndex
    GameState.SetPhase("Loading")

    if withPrologue and not playPrologue(token) then
        return
    end

    Remotes.FireAll("Cutscene", {
        Kind = "ChapterTitle",
        Chapter = chapterIndex,
        Name = chapter.Name,
        Count = chapter.Count,
        Description = chapter.Description,
        Duration = TITLE_CARD_TIME,
    })
    task.wait(1)
    if token ~= runToken then
        return
    end

    GameState.ResetChapter()
    GameState.MaxLives = computeLives()
    GameState.Lives = GameState.MaxLives
    clearQuestItems()

    -- Si el mapa no se puede armar se prueba con otra semilla; si vuelve a
    -- fallar, el grupo vuelve al lobby en vez de quedar trabado cargando.
    local plan = nil
    for attempt = 1, LOAD_ATTEMPTS do
        local success, result = pcall(WorldService.LoadChapter, chapterIndex, Random.new():NextInteger(1, 2 ^ 30))
        if success then
            plan = result
            break
        end
        warn("[NOCTURNA] No se pudo cargar el capítulo", chapterIndex, "intento", attempt, result)
        -- Lo que quedó a medio armar se borra antes de volver a intentar.
        pcall(WorldService.Unload)
    end
    if token ~= runToken then
        return
    end
    if not plan then
        Remotes.FireAll("StoryNotice", "No se pudo cargar el capítulo. Volviendo al lobby.")
        returnToLobby()
        return
    end
    GameState.Checkpoint = nil

    for index, player in ipairs(Players:GetPlayers()) do
        FlashlightService.Reset(player)
        ProgressionService.SetCurrentChapter(player, chapterIndex)
        -- Quien cayó justo antes del cambio de capítulo no queda con el aviso puesto.
        Remotes.FireClient("DownState", player, {Down = false})
        task.spawn(function()
            player:LoadCharacter()
            if player.Parent == Players then
                teleport(player, RoomGenerator.StartCFrame(plan.Layout, index))
            end
        end)
    end

    MatchAnalytics.StartChapter(chapterIndex, #Players:GetPlayers())
    Analytics.ChapterStarted(chapterIndex)

    task.wait(TITLE_CARD_TIME - 1)
    if token ~= runToken then
        return
    end

    GameState.SetPhase("Playing")
    StoryService.Begin(chapterIndex)
    broadcastParty()

    task.delay(CONFIG.FirstMonsterDelay, function()
        if token == runToken and GameState.IsPlaying() then
            MonsterService.SpawnChapter(chapterIndex)
        end
    end)
end

local function finishCampaign(token)
    GameState.SetPhase("Ending")
    local endingId = EndingService.RunVote()
    if token ~= runToken then
        return
    end

    Analytics.EndingReached(endingId)
    EndingService.Play(endingId)
    if token ~= runToken then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        ProgressionService.RecordMatchCompleted(player)
        task.spawn(ProgressionService.Save, player)
    end
    returnToLobby()
end

local function onChapterCompleted(chapterIndex)
    if chapterIndex ~= GameState.Chapter or GameState.Phase ~= "Playing" then
        return
    end

    runToken += 1
    local token = runToken
    local chapter = ChapterConfig[chapterIndex]
    local nextChapter = chapterIndex + 1

    GameState.SetPhase("Cutscene")
    MonsterService.Clear()
    HidingService.Clear()

    for _, player in ipairs(Players:GetPlayers()) do
        if nextChapter <= #GameConfig.Chapters then
            ProgressionService.UnlockChapter(player, nextChapter)
            ProgressionService.SetCurrentChapter(player, nextChapter)
        end
        task.spawn(ProgressionService.Save, player)
    end

    Analytics.ChapterCompleted(chapterIndex)
    -- El cierre va detrás de lo que todavía dice el último objetivo: se espera a
    -- que termine todo antes del resumen y del capítulo siguiente.
    StoryService.PlayDialogue(chapter.Outro)
    task.wait(StoryService.RemainingDialogue() + 0.5)
    if token ~= runToken then
        return
    end

    local summary = MatchAnalytics.GetSummary()
    summary.ChapterName = chapter.Name
    summary.Count = chapter.Count
    Remotes.FireAll("ChapterSummary", summary)
    task.wait(CONFIG.SummaryDuration)
    if token ~= runToken then
        return
    end

    if nextChapter <= #GameConfig.Chapters then
        runChapter(nextChapter, false)
    else
        finishCampaign(token)
    end
end

-- Reintento: si el grupo cayó en la persecución final se repite sólo la
-- persecución, desde su largada; si no, el capítulo entero.
local function retryChapter()
    if FinalChaseService.PrepareRetry() then
        runToken += 1
        failureToken += 1
        table.clear(down)
        setLives(GameState.MaxLives)
        GameState.SetPhase("Playing")
        for index, player in ipairs(Players:GetPlayers()) do
            task.spawn(respawn, player, index)
        end
        FinalChaseService.Restart()
        return
    end
    runChapter(GameState.Chapter, false)
end

local function failChapter(reason)
    if not GameState.IsPlaying() then
        return
    end

    failureToken += 1
    local token = failureToken
    MatchAnalytics.RecordFailure()
    Analytics.ChapterFailed(GameState.Chapter)
    MonsterService.Clear()
    HidingService.Clear()
    GameState.SetPhase("Failed")
    Remotes.FireAll("DownState", {Failed = true, Reason = reason, AutoRetry = CONFIG.FailureAutoRetry})

    task.delay(CONFIG.FailureAutoRetry, function()
        if token == failureToken and GameState.Phase == "Failed" then
            task.spawn(retryChapter)
        end
    end)
end

local function checkPartyAlive()
    if not GameState.IsPlaying() or GameState.Lives > 0 then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if isAlive(player) or down[player] == "Respawning" then
            return
        end
    end

    failChapter("No queda nadie en pie.")
end

local function onPlayerDied(player, character)
    local root = character:FindFirstChild("HumanoidRootPart")
    ProgressionService.RecordDeath(player)
    MatchAnalytics.RecordDeath()
    Analytics.PlayerDied(player, GameState.Chapter)

    if not GameState.IsPlaying() then
        if GameState.Phase == "Lobby" then
            task.delay(2, function()
                if player.Parent == Players then
                    respawn(player, 1)
                end
            end)
        end
        return
    end

    InteractionService.DropQuestItems(player, root and root.Position)

    if GameState.Lives > 0 then
        setLives(GameState.Lives - 1)
        down[player] = "Respawning"
        Remotes.FireClient("DownState", player, {Down = true, RespawnIn = CONFIG.RespawnDelay})

        local token = runToken
        task.delay(CONFIG.RespawnDelay, function()
            if token == runToken and player.Parent == Players and GameState.IsPlaying() then
                respawn(player, 1)
            end
        end)
    else
        down[player] = "Spectating"
        Remotes.FireClient("DownState", player, {Down = true, Spectating = true})
        checkPartyAlive()
    end
end

-- Quien muere reaparece en el último objetivo completado por el grupo.
local function onObjectiveCompleted(objective, chapterIndex)
    MatchAnalytics.RecordObjective()
    Analytics.ObjectiveCompleted(chapterIndex, objective.Id)
    MonsterService.SpawnReinforcements(chapterIndex, objective.Id)

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root and isAlive(player) and player:GetAttribute("Hidden") ~= true then
            GameState.Checkpoint = CFrame.new(root.Position + Vector3.new(0, 1, 0))
            return
        end
    end
end

local function onPlayerAdded(player)
    local deadline = os.clock() + 15
    while player.Parent == Players and player:GetAttribute("NocturnaDataLoaded") ~= true and os.clock() < deadline do
        task.wait(0.1)
    end
    if player.Parent ~= Players then
        return
    end

    GameState.Broadcast(player)
    respawn(player, #Players:GetPlayers())
    if GameState.Phase ~= "Lobby" then
        StoryService.Broadcast(player)
    end
end

function MatchService.SetChapter(chapterIndex)
    if not ChapterConfig[chapterIndex] then
        return false
    end
    task.spawn(runChapter, chapterIndex, false)
    return true
end

function MatchService.ReturnToLobby()
    returnToLobby()
end

function MatchService.FailChapter(reason)
    failChapter(reason)
end

function MatchService.Down()
    return down
end

function MatchService.Start()
    LobbyBuilder.Build()

    EventBus.On("MatchRequested", function(chapterIndex, difficulty)
        if GameState.Phase ~= "Lobby" then
            return
        end
        GameState.Difficulty = difficulty
        MatchAnalytics.StartMatch(#Players:GetPlayers())
        InventoryService.ClearAll()
        task.spawn(runChapter, chapterIndex, chapterIndex == 1)
    end)

    EventBus.On("ChapterCompleted", onChapterCompleted)
    EventBus.On("ChapterFailed", failChapter)
    EventBus.On("PlayerDied", onPlayerDied)
    EventBus.On("ObjectiveCompleted", onObjectiveCompleted)
    EventBus.On("MonsterRage", function()
        MonsterService.SetRage(true)
    end)

    EventBus.On("FailureDecision", function(action)
        if action == "Retry" then
            task.spawn(retryChapter)
        else
            returnToLobby()
        end
    end)

    EventBus.On("MonsterEncountered", function(player, kind)
        ProgressionService.RecordMonsterEncounter(player)
        MatchAnalytics.RecordMonster()
        Analytics.MonsterEncountered(player, kind)
    end)

    Players.PlayerAdded:Connect(onPlayerAdded)
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(onPlayerAdded, player)
    end

    Players.PlayerRemoving:Connect(function(player)
        down[player] = nil
        task.defer(function()
            if #Players:GetPlayers() == 0 then
                if GameState.Phase ~= "Lobby" then
                    returnToLobby()
                end
            else
                checkPartyAlive()
            end
        end)
    end)

    local elapsed = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed >= PARTY_UPDATE_INTERVAL then
            elapsed = 0
            if GameState.Phase ~= "Lobby" then
                broadcastParty()
            end
        end
    end)
end

return MatchService
