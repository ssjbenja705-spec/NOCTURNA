-- Ambiente del lobby en el cliente: los tubos marcados titilan de vez en cuando.
-- Corre sólo en la fase de lobby y no manda nada por la red.
local CollectionService = game:GetService("CollectionService")

local ClientState = require(script.Parent.Parent.Core.ClientState)

local TAG = "NocturnaLobbyFlicker"

local LobbyAmbience = {}

local function flicker(fixture, random)
    local light = fixture:FindFirstChildWhichIsA("Light")
    local material = fixture.Material
    for _ = 1, random:NextInteger(2, 5) do
        if light then
            light.Enabled = false
        end
        fixture.Material = Enum.Material.Glass
        task.wait(random:NextNumber(0.04, 0.12))
        if fixture.Parent == nil then
            return
        end
        if light then
            light.Enabled = true
        end
        fixture.Material = material
        task.wait(random:NextNumber(0.05, 0.25))
    end
end

function LobbyAmbience.Start()
    local random = Random.new()
    task.spawn(function()
        while true do
            task.wait(random:NextNumber(1.2, 3.5))
            local state = ClientState.Get("Game")
            if state and state.Phase == "Lobby" then
                local fixtures = CollectionService:GetTagged(TAG)
                if #fixtures > 0 then
                    local fixture = fixtures[random:NextInteger(1, #fixtures)]
                    if fixture:IsA("BasePart") and fixture.Parent then
                        flicker(fixture, random)
                    end
                end
            end
        end
    end)
end

return LobbyAmbience
