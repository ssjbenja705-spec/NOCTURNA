-- Puertas de cortina metálica. Las normales abren para todos, también para los
-- monstruos; las cerradas bloquean la navegación hasta que el grupo las abre.
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local NoiseService = require(script.Parent.Parent.AI.NoiseService)
local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local InventoryService = require(script.Parent.Parent.Inventory.InventoryService)
local FeatureBuilder = require(script.Parent.FeatureBuilder)
local InteractionService = require(script.Parent.InteractionService)
local RoomGenerator = require(script.Parent.RoomGenerator)

local MAP = GameConfig.Map
local MONSTER_OPEN_DISTANCE = 7
local TWEEN = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local DoorService = {}
local doors = {}

local function playAt(door, soundName)
    Remotes.FireAll("PlaySound", soundName, door.Part.Position)
end

local function setOpen(door, opened)
    if door.Opened == opened then
        return
    end

    door.Opened = opened
    door.Part:SetAttribute("Opened", opened)
    door.Part.CanCollide = not opened
    door.Prompt.ActionText = opened and "Cerrar" or "Abrir"

    local goal = opened and door.Closed + Vector3.new(0, MAP.OpeningHeight - 0.8, 0) or door.Closed
    TweenService:Create(door.Part, TWEEN, {Position = goal}):Play()
end

local function failUnlock(door, player, message)
    playAt(door, "DoorLocked")
    Remotes.FireClient("StoryNotice", player, message)
end

local function unlock(door, player)
    door.Locked = false
    door.Spec.Locked = false
    GameState.Nav:Unblock(door.Spec.A, door.Spec.B)
    door.Prompt.ActionText = "Cerrar"
    door.Prompt.ObjectText = door.Spec.Label or "Puerta"
    setOpen(door, true)
    playAt(door, "DoorSlam")
    Remotes.FireAll("StoryNotice", player.DisplayName .. " abrió: " .. (door.Spec.Label or "una puerta"))
    if door.Spec.Id then
        EventBus.Emit("DoorUnlocked", player, door.Spec.Id)
    end
end

local function tryUnlock(door, player)
    local spec = door.Spec

    if spec.RequiresFlag and not GameState.HasFlag(spec.RequiresFlag) then
        failUnlock(door, player, spec.DeniedText or "No tiene energía.")
        return
    end

    if spec.RequiredItem then
        local amount = spec.Amount or 1
        local name = ItemConfig[spec.RequiredItem].DisplayName
        if not InventoryService.RemoveFromParty(player, spec.RequiredItem, amount) then
            local have = InventoryService.CountParty(spec.RequiredItem)
            failUnlock(door, player, string.format("Necesitás %s (%d/%d).", name, have, amount))
            return
        end
    end

    unlock(door, player)
end

local function interact(door, player)
    if door.Broken then
        return
    end

    if door.Locked then
        tryUnlock(door, player)
        return
    end

    setOpen(door, not door.Opened)
    playAt(door, "DoorOpen")
    NoiseService.Emit(door.Part.Position, GameConfig.Noise.Door, player)
end

local function buildDoor(spec, layout, folder)
    local midpoint, horizontal = RoomGenerator.EdgeInfo(layout, spec.A, spec.B)
    local width = MAP.CorridorWidth
    local height = MAP.OpeningHeight
    local size = horizontal and Vector3.new(width, height, 1) or Vector3.new(1, height, width)
    local closed = midpoint + Vector3.new(0, height / 2, 0)
    local color = spec.Locked and Color3.fromRGB(120, 60, 40) or Color3.fromRGB(78, 80, 84)

    local part = RoomGenerator.CreatePart(folder, spec.Id or "Door", size, closed, color, Enum.Material.CorrodedMetal)
    CollectionService:AddTag(part, "NocturnaDoor")

    -- El prompt queda a la altura del jugador aunque la cortina esté levantada.
    local host = RoomGenerator.CreatePart(folder, "DoorPrompt", Vector3.new(1, 1, 1), midpoint + Vector3.new(0, 3, 0), color)
    host.Transparency = 1
    host.CanCollide = false
    host.CanQuery = false

    local prompt = FeatureBuilder.AddPrompt(host, spec.Locked and "Desbloquear" or "Abrir", spec.Label or "Puerta", spec.Locked and 0.6 or 0.2)
    local door = {
        Spec = spec,
        Part = part,
        Prompt = prompt,
        Closed = closed,
        Opened = false,
        Locked = spec.Locked == true,
        Broken = false,
    }

    InteractionService.Bind(prompt, function(player)
        interact(door, player)
    end)
    return door
end

function DoorService.Populate(plan, map)
    table.clear(doors)

    local folder = Instance.new("Folder")
    folder.Name = "Doors"
    folder.Parent = map

    for _, spec in ipairs(plan.Doors) do
        local door = buildDoor(spec, plan.Layout, folder)
        table.insert(doors, door)
        if door.Locked then
            GameState.Nav:Block(spec.A, spec.B)
        end
    end
end

function DoorService.Clear()
    table.clear(doors)
end

function DoorService.PositionOf(doorId)
    for _, door in ipairs(doors) do
        if door.Spec.Id == doorId then
            return door.Part.Position
        end
    end
    return nil
end

function DoorService.IsLocked(doorId)
    for _, door in ipairs(doors) do
        if door.Spec.Id == doorId then
            return door.Locked
        end
    end
    return false
end

-- Los monstruos abren lo que tienen enfrente, salvo que esté trabado.
function DoorService.OpenNear(position)
    for _, door in ipairs(doors) do
        if not door.Locked and not door.Opened and not door.Broken then
            if (door.Closed - position).Magnitude <= MONSTER_OPEN_DISTANCE + door.Closed.Y then
                setOpen(door, true)
                playAt(door, "DoorOpen")
            end
        end
    end
end

-- El Coloso destroza las puertas comunes que encuentra en su camino.
function DoorService.SmashNear(position)
    for _, door in ipairs(doors) do
        if not door.Locked and not door.Broken then
            if (door.Closed - position).Magnitude <= MONSTER_OPEN_DISTANCE + door.Closed.Y then
                door.Broken = true
                door.Opened = true
                door.Prompt.Enabled = false
                door.Part.CanCollide = false
                door.Part.Transparency = 1
                playAt(door, "Metal")
            end
        end
    end
end

-- Portazo de terror: cierra una puerta común abierta cerca del punto indicado.
function DoorService.SlamNear(position, range)
    for _, door in ipairs(doors) do
        if door.Opened and not door.Locked and not door.Broken then
            if (door.Closed - position).Magnitude <= range then
                setOpen(door, false)
                playAt(door, "DoorSlam")
                return true
            end
        end
    end
    return false
end

return DoorService
