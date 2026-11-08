-- Puertas comunes y trabadas del capítulo. Las normales abren para todos, también
-- para los monstruos; las trabadas bloquean la navegación hasta que el grupo las abre.
--
-- Cada capítulo tiene su propia puerta (DoorModels, según ThemeConfig.DoorStyle):
-- cortina de túnel, puerta de clínica, esclusa, bóveda o puerta de casa. Lo que
-- choca es una pieza invisible que tapa el vano (`door.Part`); las hojas se animan
-- aparte. Al cerrar, el vano sólo vuelve a ser sólido cuando no queda ningún jugador
-- adentro: una puerta nunca deja a nadie trabado dentro de la pared.
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local ItemConfig = require(Shared.Config.ItemConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local NoiseService = require(script.Parent.Parent.AI.NoiseService)
local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local InventoryService = require(script.Parent.Parent.Inventory.InventoryService)
local DoorModels = require(script.Parent.DoorModels)
local FeatureBuilder = require(script.Parent.FeatureBuilder)
local InteractionService = require(script.Parent.InteractionService)
local RoomGenerator = require(script.Parent.RoomGenerator)

local MAP = GameConfig.Map
local MONSTER_OPEN_DISTANCE = 7
local TOGGLE_COOLDOWN = 1
-- Cada cuánto se vuelve a probar si el vano quedó libre para hacerlo sólido.
local SOLID_RETRY = 0.25
-- Margen alrededor del vano en el que un jugador cuenta como "adentro".
local DOORWAY_MARGIN = 1.6

local DoorService = {}
local doors = {}

local function playAt(door, soundName)
    Remotes.FireAll("PlaySound", soundName, door.Part.Position)
end

local function setLamp(door, state)
    local lamp = door.Model.Lamp
    if lamp then
        lamp.Color = DoorModels.LampColors[state]
    end
end

-- ¿Hay algún jugador vivo parado dentro del vano (o rozándolo)?
local function playerInDoorway(door)
    local blocker = door.Part
    local half = blocker.Size / 2 + Vector3.new(DOORWAY_MARGIN, 0, DOORWAY_MARGIN)
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if root then
            local offset = blocker.CFrame:PointToObjectSpace(root.Position)
            if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y + 3 and math.abs(offset.Z) <= half.Z then
                return true
            end
        end
    end
    return false
end

-- Vuelve sólido el vano cuando termina de cerrarse y no queda nadie adentro.
local function solidifyWhenClear(door, token)
    task.delay(door.Model.CloseTime, function()
        while door.Token == token and not door.Opened and not door.Broken and door.Part.Parent do
            if not playerInDoorway(door) then
                door.Part.CanCollide = true
                door.Part.CanQuery = true
                return
            end
            task.wait(SOLID_RETRY)
        end
    end)
end

local function animate(door, opened, fast)
    local model = door.Model
    local duration = opened and model.OpenTime or model.CloseTime
    if fast then
        duration = math.min(duration, 0.35)
    end
    -- Las pesadas rebotan apenas al tocar el tope; las livianas frenan suave.
    local info = opened and TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
        or TweenInfo.new(duration, model.Heavy and Enum.EasingStyle.Bounce or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    for _, leaf in ipairs(model.Leaves) do
        if leaf.Root.Parent then
            TweenService:Create(leaf.Root, info, {CFrame = opened and leaf.Open or leaf.Closed}):Play()
        end
    end
end

local function setOpen(door, opened, fast)
    if door.Opened == opened then
        return
    end

    door.Opened = opened
    door.Token += 1
    door.Part:SetAttribute("Opened", opened)
    door.Prompt.ActionText = opened and "Cerrar" or "Abrir"
    animate(door, opened, fast)

    if opened then
        -- Abrir libera el paso enseguida: nadie choca con una hoja a medio abrir.
        door.Part.CanCollide = false
        door.Part.CanQuery = false
        setLamp(door, "Open")
    else
        setLamp(door, door.Locked and "Locked" or "Closed")
        solidifyWhenClear(door, door.Token)
    end
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
    -- El candado y la barra se caen antes de que la hoja se mueva.
    for _, piece in ipairs(door.Model.LockParts) do
        piece:Destroy()
    end
    playAt(door, "DoorLocked")
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

-- Sonido mecánico de cada puerta: chirrido al abrir; al cerrar, las pesadas golpean.
local function playToggle(door, opened)
    if opened then
        playAt(door, "DoorOpen")
    elseif door.Model.Heavy then
        playAt(door, "Metal")
    else
        playAt(door, "DoorOpen")
    end
end

local function interact(door, player)
    if door.Broken then
        return
    end

    if door.Locked then
        tryUnlock(door, player)
        return
    end

    -- Abrir y cerrar sin parar haría ruido constante para atraer a las criaturas.
    local now = os.clock()
    if door.LastToggle and now - door.LastToggle < TOGGLE_COOLDOWN then
        return
    end
    door.LastToggle = now

    setOpen(door, not door.Opened)
    playToggle(door, door.Opened)
    NoiseService.Emit(door.Part.Position, GameConfig.Noise.Door, player)
end

local function buildDoor(spec, layout, folder, theme)
    local midpoint, horizontal = RoomGenerator.EdgeInfo(layout, spec.A, spec.B)
    local width = MAP.CorridorWidth
    local height = MAP.OpeningHeight
    local frame = CFrame.new(midpoint) * CFrame.Angles(0, horizontal and 0 or math.rad(90), 0)
    local closed = midpoint + Vector3.new(0, height / 2, 0)

    -- El vano: invisible, sólido mientras está cerrado y tapa la vista de la IA.
    local part = RoomGenerator.CreatePart(folder, spec.Id or "Door", Vector3.new(width, height, 1), closed, Color3.new(), Enum.Material.SmoothPlastic)
    part.CFrame = frame * CFrame.new(0, height / 2, 0)
    part.Transparency = 1
    part.CastShadow = false
    CollectionService:AddTag(part, "NocturnaDoor")

    local model = DoorModels.Build(folder, spec, frame, width, height, MAP.WallThickness, theme)
    part:SetAttribute("DoorStyle", model.Style)

    -- El prompt queda a la altura del jugador aunque la hoja esté abierta.
    local host = RoomGenerator.CreatePart(folder, "DoorPrompt", Vector3.new(1, 1, 1), midpoint + Vector3.new(0, 3, 0), Color3.new())
    host.Transparency = 1
    host.CanCollide = false
    host.CanQuery = false

    local prompt = FeatureBuilder.AddPrompt(host, spec.Locked and "Desbloquear" or "Abrir", spec.Label or "Puerta", spec.Locked and 0.6 or 0.2)
    local door = {
        Spec = spec,
        Part = part,
        Model = model,
        Prompt = prompt,
        Closed = closed,
        Opened = false,
        Locked = spec.Locked == true,
        Broken = false,
        Token = 0,
    }
    setLamp(door, door.Locked and "Locked" or "Closed")

    InteractionService.Bind(prompt, function(player)
        interact(door, player)
    end)
    return door
end

function DoorService.Populate(plan, map, theme)
    table.clear(doors)

    local folder = Instance.new("Folder")
    folder.Name = "Doors"
    folder.Parent = map

    for _, spec in ipairs(plan.Doors) do
        local door = buildDoor(spec, plan.Layout, folder, theme or {})
        table.insert(doors, door)
        if door.Locked then
            GameState.Nav:Block(spec.A, spec.B)
        end
    end
end

function DoorService.Clear()
    -- Las esperas pendientes (vano que se vuelve sólido) quedan sin efecto.
    for _, door in ipairs(doors) do
        door.Token += 1
    end
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

-- Alma también abre las puertas que tiene enfrente. Lo pide por el bus porque no
-- puede requerir este módulo sin formar un ciclo (FeatureBuilder la arma).
EventBus.On("OpenDoorsNear", function(position)
    if typeof(position) == "Vector3" then
        DoorService.OpenNear(position)
    end
end)

-- El Coloso destroza las puertas comunes que encuentra en su camino: las hojas
-- quedan arrancadas, tiradas en el piso al costado del vano.
function DoorService.SmashNear(position)
    for _, door in ipairs(doors) do
        if not door.Locked and not door.Broken then
            if (door.Closed - position).Magnitude <= MONSTER_OPEN_DISTANCE + door.Closed.Y then
                door.Broken = true
                door.Opened = true
                door.Token += 1
                door.Prompt.Enabled = false
                door.Part.CanCollide = false
                door.Part.CanQuery = false
                door.Part.Transparency = 1
                door.Part:SetAttribute("Opened", true)
                door.Part:SetAttribute("Broken", true)
                for index, leaf in ipairs(door.Model.Leaves) do
                    local root = leaf.Root
                    if root.Parent then
                        local side = index % 2 == 0 and 1 or -1
                        local fallen = door.Part.CFrame * CFrame.new(side * 2.5, -MAP.OpeningHeight / 2 + 0.4, -3)
                            * CFrame.Angles(math.rad(88), math.rad(side * 25), 0)
                        TweenService:Create(root, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {CFrame = fallen}):Play()
                    end
                end
                if door.Model.Lamp then
                    door.Model.Lamp.Color = Color3.fromRGB(30, 30, 30)
                end
                playAt(door, "Metal")
            end
        end
    end
end

-- Portazo de terror: cierra de golpe una puerta común abierta cerca del punto.
function DoorService.SlamNear(position, range)
    for _, door in ipairs(doors) do
        if door.Opened and not door.Locked and not door.Broken then
            if (door.Closed - position).Magnitude <= range then
                setOpen(door, false, true)
                playAt(door, "DoorSlam")
                return true
            end
        end
    end
    return false
end

return DoorService
