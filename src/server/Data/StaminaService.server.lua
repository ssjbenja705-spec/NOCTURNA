-- NOCTURNA: Server Stamina Service

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CONFIG = {
    Maximum = 100,
    DrainPerSecond = 22,
    RecoveryPerSecond = 16,
    WalkSpeed = 10,
    SprintSpeed = 17,
    ExhaustedRecovery = 2,
}

local states = {}
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local sprintRemote = remotes:FindFirstChild("SprintRequest")

if not sprintRemote then
    sprintRemote = Instance.new("RemoteEvent")
    sprintRemote.Name = "SprintRequest"
    sprintRemote.Parent = remotes
end

local function setupPlayer(player)
    states[player] = {
        stamina = CONFIG.Maximum,
        sprinting = false,
        exhausted = false,
    }

    player:SetAttribute("Stamina", CONFIG.Maximum)
    player:SetAttribute("IsSprinting", false)

    player.CharacterAdded:Connect(function(character)
        local humanoid = character:WaitForChild("Humanoid", 10)
        if humanoid then
            humanoid.WalkSpeed = CONFIG.WalkSpeed
        end
    end)
end

local function updatePlayer(player, deltaTime)
    local state = states[player]
    if not state then return end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        state.sprinting = false
        return
    end

    local moving = humanoid.MoveDirection.Magnitude > 0.05
    if state.sprinting and moving and not state.exhausted then
        state.stamina = math.max(0, state.stamina - CONFIG.DrainPerSecond * deltaTime)
        if state.stamina <= 0 then
            state.exhausted = true
            state.sprinting = false
        end
    else
        local recovery = state.exhausted
            and CONFIG.ExhaustedRecovery
            or CONFIG.RecoveryPerSecond
        state.stamina = math.min(CONFIG.Maximum, state.stamina + recovery * deltaTime)

        if state.stamina >= 25 then
            state.exhausted = false
        end
    end

    humanoid.WalkSpeed = state.sprinting and CONFIG.SprintSpeed or CONFIG.WalkSpeed
    player:SetAttribute("Stamina", math.floor(state.stamina))
    player:SetAttribute("IsSprinting", state.sprinting)
end

sprintRemote.OnServerEvent:Connect(function(player, requested)
    if typeof(requested) ~= "boolean" then return end

    local state = states[player]
    if not state then return end

    if requested and state.stamina > 0 and not state.exhausted then
        state.sprinting = true
    else
        state.sprinting = false
    end
end)

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

print("[NOCTURNA] Sistema de resistencia iniciado.")
