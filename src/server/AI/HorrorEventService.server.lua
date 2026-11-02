local Players = game:GetService("Players")

local events = {
    "LightsFlicker",
    "MetalNoise",
    "DoorSlams",
    "MonsterNearby",
    "FalseAlarm",
}

local function triggerEvent()
    local selected = events[math.random(1, #events)]

    for _, player in ipairs(Players:GetPlayers()) do
        player:SetAttribute("HorrorEvent", selected)
        player:SetAttribute("HorrorEventTime", os.clock())
    end

    print("[NOCTURNA HORROR]", selected)
end


while true do
    task.wait(math.random(35, 75))

    if #Players:GetPlayers() > 0 then
        triggerEvent()
    end
end
