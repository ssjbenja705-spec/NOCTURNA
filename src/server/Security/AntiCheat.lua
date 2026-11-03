-- Detección básica de movimiento imposible. Devuelve al personaje al último punto
-- válido en lugar de expulsar: un pico de latencia no debe castigar a nadie.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)

local GameState = require(script.Parent.Parent.Core.GameState)

local SAMPLE_INTERVAL = 0.5
local SPEED_MARGIN = 1.7
local FLAT_TOLERANCE = 12
local MAX_HEIGHT = GameConfig.Map.WallHeight + 4
local WARNINGS_BEFORE_KICK = 25

local AntiCheat = {}
local states = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

function AntiCheat.Grace(player, seconds)
    local state = states[player]
    if state then
        state.GraceUntil = os.clock() + seconds
        state.LastPosition = nil
    end
end

local function isMovementValid(previous, current, elapsed)
    local offset = current - previous
    local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
    local allowed = GameConfig.Player.SprintSpeed * SPEED_MARGIN * elapsed + FLAT_TOLERANCE * elapsed
    if flat > allowed then
        return false
    end

    return current.Y <= MAX_HEIGHT
end

AntiCheat.IsMovementValid = isMovementValid

local function crossedWall(previous, current)
    local characters = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(characters, player.Character)
        end
    end

    rayParams.FilterDescendantsInstances = characters
    return workspace:Raycast(previous, current - previous, rayParams) ~= nil
end

local function checkPlayer(player, state, elapsed)
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")

    if not root or not humanoid or humanoid.Health <= 0 or root.Anchored then
        state.LastPosition = nil
        return
    end

    if os.clock() < state.GraceUntil or not GameState.IsPlaying() then
        state.LastPosition = nil
        return
    end

    local current = root.Position
    local previous = state.LastPosition

    if previous and (not isMovementValid(previous, current, elapsed) or crossedWall(previous, current)) then
        state.Warnings += 1
        state.GraceUntil = os.clock() + 0.5
        root.CFrame = CFrame.new(previous)
        root.AssemblyLinearVelocity = Vector3.zero

        if state.Warnings >= WARNINGS_BEFORE_KICK then
            player:Kick("Movimiento inválido detectado.")
        end
        return
    end

    state.LastPosition = current
end

local function setupPlayer(player)
    states[player] = {LastPosition = nil, GraceUntil = os.clock() + 5, Warnings = 0}
end

function AntiCheat.Start()
    Players.PlayerAdded:Connect(setupPlayer)
    Players.PlayerRemoving:Connect(function(player)
        states[player] = nil
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end

    -- En Studio no se corrige a nadie, para poder probar con herramientas de desarrollo.
    if RunService:IsStudio() then
        return
    end

    local elapsed = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed < SAMPLE_INTERVAL then
            return
        end

        local step = elapsed
        elapsed = 0
        for player, state in pairs(states) do
            checkPlayer(player, state, step)
        end
    end)
end

return AntiCheat
