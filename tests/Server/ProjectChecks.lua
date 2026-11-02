local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function check(name, callback)
    local success, result = pcall(callback)

    if success and result then
        print("[TEST PASS]", name)
    else
        warn("[TEST FAIL]", name, result)
    end
end

check("GameConfig", function()
    local config = require(ReplicatedStorage.Shared.Config.GameConfig)
    return config.MaxPlayers == 4 and #config.Chapters == 5
end)

check("MonsterConfig", function()
    local config = require(ReplicatedStorage.Shared.Config.MonsterConfig)
    return config.Oyente ~= nil
        and config.Imitador ~= nil
        and config.Quieto ~= nil
        and config.Trepador ~= nil
        and config.Coloso ~= nil
end)

check("ItemConfig", function()
    local config = require(ReplicatedStorage.Shared.Config.ItemConfig)
    return config.Battery ~= nil and config.Keycard ~= nil
end)

check("ObjectiveConfig", function()
    local config = require(ReplicatedStorage.Shared.Config.ObjectiveConfig)
    return #config.Chapters == 5
end)

return true