local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local maxBattery = Config.Flashlight.BatterySeconds
local battery = maxBattery
local displayedBattery = math.ceil(battery)

if player:GetAttribute("FlashlightEnabled") == nil then
    player:SetAttribute("FlashlightEnabled", false)
end
player:SetAttribute("FlashlightBattery", displayedBattery)

local function toggleFlashlight()
    if battery > 0 then
        player:SetAttribute("FlashlightEnabled", player:GetAttribute("FlashlightEnabled") ~= true)
    end
end

player:GetAttributeChangedSignal("ToggleFlashlight"):Connect(toggleFlashlight)

RunService.Heartbeat:Connect(function(deltaTime)
    if player:GetAttribute("FlashlightEnabled") == true then
        battery = math.max(0, battery - deltaTime)
        if battery <= 0 then
            player:SetAttribute("FlashlightEnabled", false)
        end
    end

    local nextDisplayedBattery = math.ceil(battery)
    if nextDisplayedBattery ~= displayedBattery then
        displayedBattery = nextDisplayedBattery
        player:SetAttribute("FlashlightBattery", displayedBattery)
    end
end)

print("[NOCTURNA] Bateria preparada.")
