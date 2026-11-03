-- Casilleros para esconderse. Mientras dure, el personaje queda fijo adentro y los
-- monstruos no lo perciben, salvo que lo hayan visto entrar.
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage").Shared
local Remotes = require(Shared.Modules.RemoteHelper)

local EventBus = require(script.Parent.Parent.Core.EventBus)
local FlashlightService = require(script.Parent.Parent.Data.FlashlightService)
local FeatureBuilder = require(script.Parent.FeatureBuilder)
local InteractionService = require(script.Parent.InteractionService)
local RoomGenerator = require(script.Parent.RoomGenerator)

local HidingService = {}
local lockers = {}
local hiddenPlayers = {}

local function release(player, ejected)
    local state = hiddenPlayers[player]
    if not state then
        return
    end

    hiddenPlayers[player] = nil
    state.Locker.Occupant = nil
    state.Locker.Prompt.Enabled = true
    player:SetAttribute("Hidden", false)

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if root then
        root.Anchored = false
        root.CFrame = state.Locker.ExitCFrame
    end

    Remotes.FireClient("HideState", player, false, nil, ejected == true)
end

local function enter(locker, player)
    if locker.Occupant or hiddenPlayers[player] then
        return
    end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end

    locker.Occupant = player
    locker.Prompt.Enabled = false
    hiddenPlayers[player] = {Locker = locker, Since = os.clock()}

    FlashlightService.SetEnabled(player, false)
    player:SetAttribute("Hidden", true)
    root.Anchored = true
    root.CFrame = locker.InsideCFrame

    Remotes.FireClient("HideState", player, true, locker.CameraCFrame, false)
end

function HidingService.Populate(plan, map)
    HidingService.Clear()

    local folder = Instance.new("Folder")
    folder.Name = "Hides"
    folder.Parent = map

    for _, spot in ipairs(plan.Hides) do
        local cframe = RoomGenerator.SlotCFrame(plan.Layout, spot.Cell, spot.Slot)
        local _, prompt = FeatureBuilder.Locker(folder, cframe)
        local locker = {
            Prompt = prompt,
            InsideCFrame = cframe * CFrame.new(0, 3, 0.3),
            -- La cámara queda a la altura de las rendijas, mirando hacia la sala.
            CameraCFrame = cframe * CFrame.new(0, 5.8, -2.05),
            ExitCFrame = cframe * CFrame.new(0, 3, -4.5),
            Occupant = nil,
        }
        table.insert(lockers, locker)

        InteractionService.Bind(prompt, function(player)
            enter(locker, player)
        end)
    end
end

function HidingService.Clear()
    for player in pairs(hiddenPlayers) do
        release(player, false)
    end
    table.clear(lockers)
end

function HidingService.IsHidden(player)
    return hiddenPlayers[player] ~= nil
end

function HidingService.HiddenFor(player)
    local state = hiddenPlayers[player]
    return state and os.clock() - state.Since or 0
end

function HidingService.ForceOut(player)
    release(player, true)
end

function HidingService.Start()
    Remotes.OnServer("ExitHiding", 4, function(player)
        release(player, false)
    end)

    EventBus.On("PlayerDied", function(player)
        release(player, false)
    end)

    Players.PlayerRemoving:Connect(function(player)
        local state = hiddenPlayers[player]
        if state then
            state.Locker.Occupant = nil
            state.Locker.Prompt.Enabled = true
            hiddenPlayers[player] = nil
        end
    end)
end

return HidingService
