-- Sprint y sigilo autoritativos: el cliente sólo pide, el servidor decide la velocidad.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local StaminaModel = require(Shared.Logic.StaminaModel)
local Remotes = require(Shared.Modules.RemoteHelper)
local EventBus = require(script.Parent.Parent.Core.EventBus)

local CONFIG = GameConfig.Player
local STAMINA_PUBLISH_INTERVAL = 0.1

local StaminaService = {}
local states = {}

local function setupPlayer(player)
    states[player] = StaminaModel.new(CONFIG)
    states[player].Crouching = false
    player:SetAttribute("Stamina", CONFIG.MaxStamina)
    player:SetAttribute("IsSprinting", false)
    player:SetAttribute("IsCrouching", false)
end

function StaminaService.Reset(player)
    if states[player] then
        setupPlayer(player)
    end
end

local function updatePlayer(player, deltaTime)
    local state = states[player]
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        state.Sprinting = false
        return
    end

    StaminaModel.Step(state, deltaTime, humanoid.MoveDirection.Magnitude > 0.05, CONFIG)
    local frozen = player:GetAttribute("Hidden") == true
    local speed = frozen and 0 or StaminaModel.Speed(state, state.Crouching, CONFIG)
    -- Un tropezón (persecución final) frena por un momento, sin tocar el AIRE.
    if state.StaggerUntil and os.clock() < state.StaggerUntil then
        speed *= state.StaggerFactor
    end
    if humanoid.WalkSpeed ~= speed then
        humanoid.WalkSpeed = speed
    end

    -- Hasta 10 veces por segundo (y siempre al llegar a 0 o 100): suficiente para
    -- una barra suave sin replicar un atributo en cada cuadro.
    local stamina = math.floor(state.Stamina)
    local now = os.clock()
    if player:GetAttribute("Stamina") ~= stamina
        and (now - (state.LastPublished or 0) >= STAMINA_PUBLISH_INTERVAL
            or stamina <= 0 or stamina >= CONFIG.MaxStamina) then
        state.LastPublished = now
        player:SetAttribute("Stamina", stamina)
    end
    if player:GetAttribute("IsSprinting") ~= state.Sprinting then
        player:SetAttribute("IsSprinting", state.Sprinting)
    end
end

-- Tropezón de la persecución final: durante duration segundos corre a factor de
-- su velocidad normal. Lo pide el servidor, nunca el cliente.
function StaminaService.Stagger(player, duration, factor)
    local state = states[player]
    if not state or typeof(duration) ~= "number" or typeof(factor) ~= "number" then
        return false
    end
    state.StaggerUntil = os.clock() + math.clamp(duration, 0, 5)
    state.StaggerFactor = math.clamp(factor, 0.1, 1)
    return true
end

function StaminaService.IsStaggered(player)
    local state = states[player]
    return state ~= nil and state.StaggerUntil ~= nil and os.clock() < state.StaggerUntil
end

function StaminaService.Start()
    Remotes.OnServer("SprintRequest", 10, function(player, requested)
        local state = states[player]
        if state and typeof(requested) == "boolean" then
            if requested then
                state.Crouching = false
                player:SetAttribute("IsCrouching", false)
            end
            StaminaModel.Request(state, requested)
        end
    end)

    Remotes.OnServer("CrouchRequest", 10, function(player, requested)
        local state = states[player]
        if state and typeof(requested) == "boolean" then
            state.Crouching = requested
            if requested then
                state.Sprinting = false
            end
            player:SetAttribute("IsCrouching", requested)
        end
    end)

    EventBus.On("CharacterReady", StaminaService.Reset)

    Players.PlayerAdded:Connect(setupPlayer)
    Players.PlayerRemoving:Connect(function(player)
        states[player] = nil
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end

    RunService.Heartbeat:Connect(function(deltaTime)
        for player in pairs(states) do
            if player.Parent == Players then
                updatePlayer(player, deltaTime)
            end
        end
    end)
end

return StaminaService
