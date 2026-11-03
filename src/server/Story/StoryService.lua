-- Conduce los objetivos del capítulo actual. El progreso es compartido por el grupo:
-- lo que hace un jugador cuenta para todos.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local ChapterConfig = require(Shared.Config.ChapterConfig)
local ObjectiveTracker = require(Shared.Logic.ObjectiveTracker)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local DoorService = require(script.Parent.Parent.World.DoorService)
local InteractionService = require(script.Parent.Parent.World.InteractionService)
local MechanismService = require(script.Parent.Parent.World.MechanismService)

local DIALOGUE_LINE_TIME = 3.8
local ZONE_CHECK_INTERVAL = 0.4

local StoryService = {}
local tracker = nil
local chapterIndex = 0
local readDocuments = {}
local deadline = nil
local dialogueQueue = {}
local dialogueRunning = false
local sessionToken = 0

local function zonePosition(zoneId)
    local layout = GameState.Layout
    local nav = GameState.Nav
    for _, cell in ipairs(layout.Cells) do
        if cell.Zone == zoneId then
            return nav:Center(cell.Index, 3)
        end
    end
    return nil
end

-- Puntos a los que apunta la señal de la radio para el objetivo actual.
local function currentWaypoints(objective)
    if objective.Type == "Reach" then
        local position = zonePosition(objective.Target)
        return position and {position} or {}
    elseif objective.Type == "Collect" then
        return InteractionService.ItemPositions(objective.Target)
    elseif objective.Type == "Activate" then
        return MechanismService.PositionsFor(objective.Target)
    elseif objective.Type == "Unlock" then
        local position = DoorService.PositionOf(objective.Target)
        return position and {position} or {}
    elseif objective.Type == "Read" then
        return InteractionService.DocumentPositions(objective.Target, readDocuments)
    end
    return {}
end

local function buildUpdate()
    local chapter = ChapterConfig[chapterIndex]
    local objective = tracker and tracker:Current()

    if not objective then
        return {
            Chapter = chapterIndex,
            ChapterName = chapter and chapter.Name or "",
            Finished = true,
        }
    end

    local count, total = tracker:Progress()
    return {
        Chapter = chapterIndex,
        ChapterName = chapter.Name,
        ObjectiveId = objective.Id,
        Objective = objective.Name,
        Count = count,
        Total = total,
        Index = tracker.Index,
        TotalObjectives = #tracker.Objectives,
        Waypoints = currentWaypoints(objective),
        Deadline = deadline,
        Finished = false,
    }
end

function StoryService.Broadcast(player)
    if chapterIndex == 0 or not tracker then
        return
    end

    if player then
        Remotes.FireClient("ObjectiveUpdate", player, buildUpdate())
    else
        Remotes.FireAll("ObjectiveUpdate", buildUpdate())
    end
end

local function runDialogue(token)
    dialogueRunning = true
    while #dialogueQueue > 0 and token == sessionToken do
        local line = table.remove(dialogueQueue, 1)
        Remotes.FireAll("StoryDialogue", line)
        task.wait(DIALOGUE_LINE_TIME)
    end
    dialogueRunning = false
end

function StoryService.PlayDialogue(lines)
    for _, line in ipairs(lines or {}) do
        table.insert(dialogueQueue, line)
    end
    if not dialogueRunning then
        task.spawn(runDialogue, sessionToken)
    end
end

function StoryService.DialogueDuration(lines)
    return #(lines or {}) * DIALOGUE_LINE_TIME
end

local function armDeadline()
    local objective = tracker and tracker:Current()
    if objective and objective.TimeLimit then
        deadline = workspace:GetServerTimeNow() + objective.TimeLimit
    else
        deadline = nil
    end
end

local function applyCompletion(objective)
    EventBus.Emit("ObjectiveCompleted", objective, chapterIndex)
    Remotes.FireAll("PlaySound", "ObjectiveDone")

    local effects = objective.OnComplete
    if not effects then
        return
    end

    StoryService.PlayDialogue(effects.Dialogue)
    if effects.Horror then
        EventBus.Emit("ScriptedHorror", effects.Horror)
    end
    if effects.MonsterRage then
        EventBus.Emit("MonsterRage")
    end
end

local function handleCompleted(completed)
    if #completed == 0 then
        StoryService.Broadcast()
        return
    end

    for _, objective in ipairs(completed) do
        applyCompletion(objective)
    end
    armDeadline()
    StoryService.Broadcast()

    if tracker:IsFinished() then
        EventBus.Emit("ChapterCompleted", chapterIndex)
    end
end

local function signal(kind, target, unique)
    if not tracker or tracker:IsFinished() or not GameState.IsPlaying() then
        return
    end
    handleCompleted(tracker:Signal(kind, target, unique))
end

function StoryService.Begin(index)
    sessionToken += 1
    chapterIndex = index
    tracker = ObjectiveTracker.new(ChapterConfig[index].Objectives)
    GameState.Tracker = tracker
    table.clear(readDocuments)
    table.clear(dialogueQueue)
    deadline = nil
    dialogueRunning = false

    armDeadline()
    StoryService.Broadcast()
    StoryService.PlayDialogue(ChapterConfig[index].Intro)
end

function StoryService.Stop()
    sessionToken += 1
    tracker = nil
    chapterIndex = 0
    deadline = nil
    GameState.Tracker = nil
    table.clear(dialogueQueue)
    dialogueRunning = false
end

function StoryService.SkipObjective()
    if not tracker or tracker:IsFinished() then
        return nil
    end
    local objective = tracker:Skip()
    handleCompleted({objective})
    return objective
end

local function checkZones()
    local nav = GameState.Nav
    local layout = GameState.Layout
    if not nav or not layout then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if root and humanoid and humanoid.Health > 0 then
            local zone = layout.Cells[nav:CellAt(root.Position)].Zone
            if zone then
                signal("Reach", zone, zone)
            end
        end
    end
end

function StoryService.Start()
    EventBus.On("ItemPicked", function(_, itemId, key, dropped)
        if dropped then
            StoryService.Broadcast()
        else
            signal("Collect", itemId, key)
        end
    end)

    EventBus.On("DocumentRead", function(_, documentId, group)
        readDocuments[documentId] = true
        if group then
            signal("Read", group, documentId)
        end
        signal("Read", documentId, documentId)
    end)

    EventBus.On("DoorUnlocked", function(_, doorId)
        signal("Unlock", doorId, doorId)
    end)

    EventBus.On("FeatureActivated", function(_, feature)
        signal("Activate", feature.Id, feature.Id)
        if feature.Group then
            signal("Activate", feature.Group, feature.Id)
        end
    end)

    local elapsed = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        if not GameState.IsPlaying() or not tracker then
            return
        end

        elapsed += deltaTime
        if elapsed >= ZONE_CHECK_INTERVAL then
            elapsed = 0
            checkZones()
        end

        if deadline and workspace:GetServerTimeNow() >= deadline then
            deadline = nil
            EventBus.Emit("ChapterFailed", "Se acabó el tiempo.")
        end
    end)
end

return StoryService
