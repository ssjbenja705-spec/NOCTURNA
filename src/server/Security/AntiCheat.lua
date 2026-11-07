-- Detección básica de movimiento imposible. Devuelve al personaje al último punto
-- válido en lugar de expulsar: un pico de latencia no debe castigar a nadie.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)

local GameState = require(script.Parent.Parent.Core.GameState)

local SAMPLE_INTERVAL = 0.5
-- Margen sobre la velocidad de carrera para la latencia, más unos studs fijos
-- por muestra: alcanza para cualquier movimiento legítimo y frena el speed hack.
local SPEED_MARGIN = 1.3
local FLAT_ALLOWANCE = 3
local MAX_HEIGHT = GameConfig.Map.WallHeight + 4
local MIN_HEIGHT = -15
local WARNINGS_BEFORE_KICK = 25
-- Cada tanto sin infracciones se perdona una: un jugador con mala conexión no
-- termina expulsado tras una hora de pequeños tirones.
local FORGIVE_AFTER = 30

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
    local allowed = GameConfig.Player.SprintSpeed * SPEED_MARGIN * elapsed + FLAT_ALLOWANCE
    if flat > allowed then
        return false
    end

    return current.Y <= MAX_HEIGHT and current.Y >= MIN_HEIGHT
end

AntiCheat.IsMovementValid = isMovementValid

-- Muebles, máquinas y escondites no cuentan como paredes: rodearlos caminando no
-- es atravesarlos, aunque la recta entre dos muestras corte una esquina.
local FURNISHING = {"Decor", "Props", "Hides", "Objects", "Mannequins"}

local function crossedWall(previous, current)
    local characters = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(characters, player.Character)
        end
    end
    local map = workspace:FindFirstChild("NOCTURNA_MAP")
    if map then
        for _, name in ipairs(FURNISHING) do
            local folder = map:FindFirstChild(name)
            if folder then
                table.insert(characters, folder)
            end
        end
        -- Las máquinas tampoco, pero las compuertas de las pruebas sí son paredes:
        -- si no, se podría atravesar una cerrada y saltear la prueba.
        local machines = map:FindFirstChild("Mechanisms")
        if machines then
            for _, machine in ipairs(machines:GetChildren()) do
                if machine:GetAttribute("NocturnaGate") ~= true then
                    table.insert(characters, machine)
                end
            end
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
        state.LastWarning = os.clock()
        state.GraceUntil = os.clock() + 0.5
        root.CFrame = CFrame.new(previous)
        root.AssemblyLinearVelocity = Vector3.zero

        if state.Warnings >= WARNINGS_BEFORE_KICK then
            player:Kick("Movimiento inválido detectado.")
        end
        return
    end

    if state.Warnings > 0 and os.clock() - state.LastWarning > FORGIVE_AFTER then
        state.Warnings -= 1
        state.LastWarning = os.clock()
    end
    state.LastPosition = current
end

local function setupPlayer(player)
    states[player] = {LastPosition = nil, GraceUntil = os.clock() + 5, Warnings = 0, LastWarning = 0}
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
