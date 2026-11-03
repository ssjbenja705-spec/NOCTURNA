-- Puente entre la IA y el motor. La IA sólo conoce esta interfaz, lo que permite
-- reemplazarla por un mundo simulado en las pruebas.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local NoiseService = require(script.Parent.Parent.AI.NoiseService)
local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)
local DamageService = require(script.Parent.Parent.Data.DamageService)
local FlashlightService = require(script.Parent.Parent.Data.FlashlightService)
local DoorService = require(script.Parent.Parent.World.DoorService)
local EnvironmentService = require(script.Parent.Parent.World.EnvironmentService)
local HidingService = require(script.Parent.Parent.World.HidingService)
local WorldService = require(script.Parent.Parent.World.WorldService)

local HIT_GRACE = 1.5

local MonsterWorld = {}
MonsterWorld.__index = MonsterWorld

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

function MonsterWorld.new()
    return setmetatable({
        Nav = GameState.Nav,
        CeilingHeight = GameConfig.Map.WallHeight,
        LastHit = {},
        Cache = nil,
        Random = Random.new(),
    }, MonsterWorld)
end

function MonsterWorld:BeginTick()
    self.Nav = GameState.Nav
    self.Cache = nil

    local excluded = {}
    local monsters = workspace:FindFirstChild("Monsters")
    if monsters then
        table.insert(excluded, monsters)
    end
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(excluded, player.Character)
        end
    end
    rayParams.FilterDescendantsInstances = excluded
end

function MonsterWorld:Players()
    if self.Cache then
        return self.Cache
    end

    local snapshots = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if root and humanoid and humanoid.Health > 0 then
            table.insert(snapshots, {
                Player = player,
                Position = root.Position,
                Look = root.CFrame.LookVector,
                Speed = (root.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude,
                Hidden = HidingService.IsHidden(player),
                HiddenFor = HidingService.HiddenFor(player),
                Flashlight = FlashlightService.IsOn(player),
            })
        end
    end

    self.Cache = snapshots
    return snapshots
end

function MonsterWorld:LineOfSight(from, to)
    local direction = to - from
    if direction.Magnitude < 0.1 then
        return true
    end
    return workspace:Raycast(from, direction, rayParams) == nil
end

function MonsterWorld:Noises()
    return NoiseService.Recent()
end

function MonsterWorld:RandomInt(minimum, maximum)
    return self.Random:NextInteger(minimum, maximum)
end

-- Tiende a merodear cerca del grupo para que la amenaza nunca desaparezca del todo.
function MonsterWorld:PatrolCell(monster)
    local nav = self.Nav
    if not nav then
        return nil
    end

    local origin = nav:CellAt(monster.Position)
    local nearest = monster:NearestPlayer(true)
    if nearest and self.Random:NextNumber() < 0.6 then
        origin = nav:CellAt(nearest.Position)
    end

    local cells = nav:CellsBetween(origin, 1, 3)
    if #cells == 0 then
        return nil
    end
    return cells[self:RandomInt(1, #cells)]
end

function MonsterWorld:OpenDoorsNear(position)
    DoorService.OpenNear(position)
end

function MonsterWorld:SmashDoorsNear(position)
    DoorService.SmashNear(position)
end

function MonsterWorld:IsLit(position)
    return WorldService.IsLit(position)
end

function MonsterWorld:Effect(name, payload, onlyPlayer)
    if onlyPlayer then
        Remotes.FireClient("MonsterEffect", onlyPlayer, name, payload)
    else
        Remotes.FireAll("MonsterEffect", name, payload)
    end
end

-- La voz imita a un compañero; si no hay ninguno, a Alma.
function MonsterWorld:VoiceFor(player)
    local others = {}
    for _, member in ipairs(Players:GetPlayers()) do
        if member ~= player then
            table.insert(others, member.DisplayName)
        end
    end
    if #others == 0 then
        return "Alma"
    end
    return others[self:RandomInt(1, #others)]
end

function MonsterWorld:OnStateChanged(monster, state)
    EventBus.Emit("MonsterStateChanged", monster, state)
end

function MonsterWorld:Encounter(monster, snapshot)
    EventBus.Emit("MonsterEncountered", snapshot.Player, monster.Kind)
end

function MonsterWorld:Damage(monster, snapshot, amount)
    local player = snapshot.Player
    local now = os.clock()
    if now - (self.LastHit[player] or 0) < HIT_GRACE then
        return
    end
    self.LastHit[player] = now

    if DamageService.ApplyDamage(player, math.floor(amount)) then
        Remotes.FireClient("MonsterEffect", player, "Jumpscare", {Kind = monster.Kind})
        EventBus.Emit("PlayerHit", player, monster.Kind)
    end
end

function MonsterWorld:PullOut(_, snapshot)
    HidingService.ForceOut(snapshot.Player)
    self.Cache = nil
end

function MonsterWorld:Quake(position)
    EnvironmentService.Quake(position)
end

function MonsterWorld:Collapse(monster, position)
    EnvironmentService.Collapse(position, monster.Settings.CollapseDuration)
end

return MonsterWorld
