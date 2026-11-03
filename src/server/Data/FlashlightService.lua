-- Linterna autoritativa: la batería vive en el servidor y la luz la ve todo el grupo.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)
local EventBus = require(script.Parent.Parent.Core.EventBus)
local GameState = require(script.Parent.Parent.Core.GameState)

local CONFIG = GameConfig.Flashlight

local FlashlightService = {}
local states = {}

local function publish(player, state)
    player:SetAttribute("FlashlightEnabled", state.Enabled)
    player:SetAttribute("FlashlightBattery", math.ceil(state.Battery))
end

local function getLight(player)
    local character = player.Character
    local head = character and character:FindFirstChild("Head")
    if not head then
        return nil
    end

    local attachment = head:FindFirstChild("NocturnaFlashlightAttachment")
    if not attachment then
        attachment = Instance.new("Attachment")
        attachment.Name = "NocturnaFlashlightAttachment"
        attachment.Parent = head
    end

    local light = attachment:FindFirstChild("NocturnaFlashlight")
    if not light then
        light = Instance.new("SpotLight")
        light.Name = "NocturnaFlashlight"
        light.Face = Enum.NormalId.Front
        light.Brightness = CONFIG.Brightness
        light.Range = CONFIG.Range
        light.Angle = CONFIG.Angle
        light.Shadows = false
        light.Enabled = false
        light.Parent = attachment
    end
    return light
end

local function apply(player, state)
    local light = getLight(player)
    if light then
        light.Enabled = state.Enabled and state.Battery > 0
    end
    publish(player, state)
end

local function setupPlayer(player)
    states[player] = {Enabled = false, Battery = 100}
    publish(player, states[player])
end

function FlashlightService.IsOn(player)
    local state = states[player]
    return state ~= nil and state.Enabled and state.Battery > 0
end

function FlashlightService.SetEnabled(player, enabled)
    local state = states[player]
    if not state then
        return
    end
    state.Enabled = enabled and state.Battery > 0
    apply(player, state)
end

function FlashlightService.Recharge(player)
    local state = states[player]
    if not state or state.Battery >= 100 then
        return false
    end
    state.Battery = math.min(100, state.Battery + CONFIG.BatteryRecharge)
    publish(player, state)
    return true
end

function FlashlightService.Reset(player)
    if states[player] then
        states[player] = {Enabled = false, Battery = 100}
        apply(player, states[player])
    end
end

function FlashlightService.Start()
    Remotes.OnServer("FlashlightToggle", 6, function(player)
        local state = states[player]
        if not state or player:GetAttribute("Hidden") == true then
            return
        end
        FlashlightService.SetEnabled(player, not state.Enabled)
    end)

    EventBus.On("CharacterReady", function(player)
        local state = states[player]
        if state then
            apply(player, state)
        end
    end)

    Players.PlayerAdded:Connect(setupPlayer)
    Players.PlayerRemoving:Connect(function(player)
        states[player] = nil
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end

    local elapsed = 0
    RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed < 0.5 then
            return
        end

        local step = elapsed
        elapsed = 0
        local drain = 100 / CONFIG.BatterySeconds * GameState.DifficultySettings().BatteryDrain

        for player, state in pairs(states) do
            if state.Enabled then
                state.Battery = math.max(0, state.Battery - step * drain)
                if state.Battery <= 0 then
                    state.Enabled = false
                    apply(player, state)
                else
                    publish(player, state)
                end
            end
        end
    end)
end

return FlashlightService
