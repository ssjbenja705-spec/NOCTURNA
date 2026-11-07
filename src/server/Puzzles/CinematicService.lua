-- Cinemática corta cuando una prueba u objetivo abre una puerta o compuerta: la
-- cámara de quienes están cerca encuadra la apertura y vuelve sola. Durante la
-- escena las criaturas se quedan quietas y nadie recibe daño.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local PuzzleConfig = require(Shared.Config.PuzzleConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local MonsterService = require(script.Parent.Parent.Monsters.MonsterService)
local RoomGenerator = require(script.Parent.Parent.World.RoomGenerator)

local CONFIG = PuzzleConfig.Cinematic
local FOCUS_HEIGHT = 4.5
local SHIELD_NAME = "NocturnaCinematicShield"

local CinematicService = {}
local holds = 0
local pausedByScene = false
local started = false

-- Encuadre: la cámara se ubica del lado de la celda A (por donde llega el grupo),
-- arranca lejos y se acerca a la abertura.
function CinematicService.Frame(layout, a, b)
    local midpoint = RoomGenerator.EdgeInfo(layout, a, b)
    local cell = layout.Cells[a]
    local size = GameConfig.Map.CellSize
    local center = Vector3.new((cell.X - 1) * size, 0, (cell.Z - 1) * size)

    local away = Vector3.new(center.X - midpoint.X, 0, center.Z - midpoint.Z)
    away = away.Magnitude > 0.01 and away.Unit or Vector3.new(0, 0, 1)
    local side = Vector3.new(-away.Z, 0, away.X)

    local focus = midpoint + Vector3.new(0, FOCUS_HEIGHT, 0)
    local from = focus + away * 22 + side * 2.5 + Vector3.new(0, 5, 0)
    local to = focus + away * 12 + side * 1 + Vector3.new(0, 1.5, 0)
    return focus, from, to
end

local function rootOf(player)
    local character = player and player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
        return nil
    end
    return root
end

-- Las criaturas se pausan; si ya estaban pausadas (por un administrador) no se tocan.
local function holdMonsters(duration)
    if holds == 0 and not MonsterService.IsPaused() then
        pausedByScene = true
        MonsterService.SetPaused(true)
    end
    holds += 1

    task.delay(duration, function()
        holds -= 1
        if holds <= 0 then
            holds = 0
            if pausedByScene then
                pausedByScene = false
                MonsterService.SetPaused(false)
            end
        end
    end)
end

local function shield(player, duration)
    local character = player.Character
    if not character or character:FindFirstChild(SHIELD_NAME) then
        return
    end
    local field = Instance.new("ForceField")
    field.Name = SHIELD_NAME
    field.Visible = false
    field.Parent = character
    task.delay(duration, function()
        if field.Parent then
            field:Destroy()
        end
    end)
end

-- Reproduce la escena de una abertura entre las celdas a y b. Devuelve a quiénes llegó.
function CinematicService.PlayDoor(a, b, label, trigger)
    local layout = GameState.Layout
    if not GameState.IsPlaying() or not layout or not layout.Cells[a] or not layout.Cells[b] then
        return {}
    end

    local focus, from, to = CinematicService.Frame(layout, a, b)
    local triggerRoot = rootOf(trigger)
    local recipients = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local root = rootOf(player)
        if root and player:GetAttribute("Hidden") ~= true then
            local near = (root.Position - focus).Magnitude <= CONFIG.Range
            if not near and triggerRoot then
                near = (root.Position - triggerRoot.Position).Magnitude <= CONFIG.Range
            end
            if near then
                table.insert(recipients, player)
            end
        end
    end
    if #recipients == 0 then
        return recipients
    end

    local payload = {
        Kind = "DoorOpen",
        Focus = focus,
        From = from,
        To = to,
        Duration = CONFIG.Duration,
        Label = label,
    }
    local safeTime = CONFIG.Duration + 0.6
    holdMonsters(safeTime)
    for _, player in ipairs(recipients) do
        shield(player, safeTime)
        Remotes.FireClient("Cinematic", player, payload)
    end
    EventBus.Emit("CinematicPlayed", payload, recipients)
    return recipients
end

local function doorSpec(doorId)
    local plan = GameState.Plan
    for _, door in ipairs(plan and plan.Doors or {}) do
        if door.Id == doorId then
            return door
        end
    end
    return nil
end

function CinematicService.Start()
    if started then
        return
    end
    started = true

    -- Puertas comunes con llave o tarjeta: las abre un objetivo.
    EventBus.On("DoorUnlocked", function(player, doorId)
        local spec = doorSpec(doorId)
        if spec then
            CinematicService.PlayDoor(spec.A, spec.B, spec.Label, player)
        end
    end)

    -- Compuertas que abre una prueba resuelta.
    EventBus.On("GateOpened", function(spec, player)
        CinematicService.PlayDoor(spec.A, spec.B, spec.Label, player)
    end)
end

return CinematicService
