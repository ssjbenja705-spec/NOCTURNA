-- Estado replicado desde el servidor. Los controladores se suscriben acá en vez de
-- escuchar cada uno los mismos remotos.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Modules.RemoteHelper)

local ClientState = {
    Values = {
        Game = {Phase = "Lobby", Chapter = 0, Lives = 0, MaxLives = 0, ShowCompass = true},
        Lobby = nil,
        Profile = nil,
        Inventory = {},
        Objective = nil,
        Party = {},
    },
}

local listeners = {}

function ClientState.Get(key)
    return ClientState.Values[key]
end

function ClientState.Set(key, value)
    ClientState.Values[key] = value
    for _, listener in ipairs(listeners[key] or {}) do
        task.spawn(listener, value)
    end
end

-- Llama de inmediato con el valor actual y después con cada cambio.
function ClientState.Subscribe(key, listener)
    listeners[key] = listeners[key] or {}
    table.insert(listeners[key], listener)
    if ClientState.Values[key] ~= nil then
        task.spawn(listener, ClientState.Values[key])
    end
end

function ClientState.Connect()
    local bindings = {
        GameState = "Game",
        LobbyUpdate = "Lobby",
        ProfileUpdate = "Profile",
        InventoryUpdate = "Inventory",
        ObjectiveUpdate = "Objective",
        PartyUpdate = "Party",
    }

    for remote, key in pairs(bindings) do
        Remotes.OnClient(remote, function(value)
            ClientState.Set(key, value)
        end)
    end
end

return ClientState
