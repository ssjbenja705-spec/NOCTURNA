-- Director de terror: alterna calma y sustos según el tiempo y la tensión del grupo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local DoorService = require(script.Parent.Parent.World.DoorService)
local EnvironmentService = require(script.Parent.Parent.World.EnvironmentService)
local WorldService = require(script.Parent.Parent.World.WorldService)

local MIN_INTERVAL = 40
local MAX_INTERVAL = 85
local BLACKOUT_TIME = 9

local AMBIENT_EVENTS = {
    "LIGHTS_FLICKER",
    "DISTANT_SOUND",
    "WHISPER",
    "FALSE_ALARM",
    "ENVIRONMENT_WARNING",
    "DOOR_SLAM",
}

local TerrorDirector = {}
local random = Random.new()
local nextEvent = math.huge

local function schedule(now)
    nextEvent = now + random:NextNumber(MIN_INTERVAL, MAX_INTERVAL)
end

local function randomPlayerPosition()
    local candidates = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            table.insert(candidates, root.Position)
        end
    end
    if #candidates == 0 then
        return nil
    end
    return candidates[random:NextInteger(1, #candidates)]
end

local function blackout()
    local wasPowered = GameState.Powered
    WorldService.SetPower(false)
    Remotes.FireAll("HorrorEvent", "BLACKOUT", {Duration = BLACKOUT_TIME})

    local chapter = GameState.Chapter
    task.delay(BLACKOUT_TIME, function()
        if GameState.Chapter == chapter and GameState.IsPlaying() then
            WorldService.SetPower(wasPowered)
        end
    end)
end

function TerrorDirector.Trigger(name)
    if name == "BLACKOUT" then
        blackout()
    elseif name == "QUAKE" then
        local position = randomPlayerPosition()
        if position then
            EnvironmentService.Quake(position)
        end
    elseif name == "DOOR_SLAM" then
        local position = randomPlayerPosition()
        if position and not DoorService.SlamNear(position, 45) then
            Remotes.FireAll("HorrorEvent", "DISTANT_SOUND")
        end
    else
        Remotes.FireAll("HorrorEvent", name)
    end
end

function TerrorDirector.Start()
    EventBus.On("ScriptedHorror", TerrorDirector.Trigger)

    -- Un golpe fuerte da un respiro: nada de sustos encima de un ataque.
    EventBus.On("PlayerHit", function()
        nextEvent = math.max(nextEvent, os.clock() + MIN_INTERVAL)
    end)

    RunService.Heartbeat:Connect(function()
        if not GameState.IsPlaying() then
            nextEvent = math.huge
            return
        end

        local now = os.clock()
        if nextEvent == math.huge then
            schedule(now)
        elseif now >= nextEvent then
            schedule(now)
            TerrorDirector.Trigger(AMBIENT_EVENTS[random:NextInteger(1, #AMBIENT_EVENTS)])
        end
    end)
end

return TerrorDirector
