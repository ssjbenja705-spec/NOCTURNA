local Players = game:GetService("Players")

local PartyService = {}
local parties = {}
local playerParty = {}

function PartyService.Create(player)
    if playerParty[player] then return false end

    local party = {
        Leader = player,
        Members = {player},
        MaxPlayers = 4,
    }

    table.insert(parties, party)
    playerParty[player] = party

    return true
end

function PartyService.Join(player, leader)
    local party = playerParty[leader]

    if not party or playerParty[player] then return false end
    if #party.Members >= party.MaxPlayers then return false end

    table.insert(party.Members, player)
    playerParty[player] = party

    return true
end

function PartyService.Leave(player)
    local party = playerParty[player]
    if not party then return false end

    for index, member in ipairs(party.Members) do
        if member == player then
            table.remove(party.Members, index)
            break
        end
    end

    playerParty[player] = nil

    if #party.Members == 0 then
        table.remove(parties, table.find(parties, party))
    elseif party.Leader == player then
        party.Leader = party.Members[1]
    end

    return true
end

Players.PlayerRemoving:Connect(function(player)
    PartyService.Leave(player)
end)

return PartyService
