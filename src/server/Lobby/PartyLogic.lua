-- Reglas de un grupo de ascensor, sin instancias: quién entra, quién manda y qué
-- se puede elegir. Los miembros se guardan por UserId en orden de llegada.
local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)

local MAX_PLAYERS = GameConfig.MaxPlayers
local CHAPTERS = #GameConfig.Chapters

local PartyLogic = {}

local function isInteger(value, minimum, maximum)
    return type(value) == "number" and value % 1 == 0 and value >= minimum and value <= maximum
end

function PartyLogic.new(id)
    return {
        Id = id,
        Members = {},
        Host = nil,
        MaxPlayers = MAX_PLAYERS,
        Chapter = 1,
        Difficulty = GameConfig.DefaultDifficulty,
        -- Open: se puede entrar. Countdown: puertas cerrándose. Launching: viajando.
        State = "Open",
    }
end

function PartyLogic.Reset(party)
    table.clear(party.Members)
    party.Host = nil
    party.MaxPlayers = MAX_PLAYERS
    party.Chapter = 1
    party.Difficulty = GameConfig.DefaultDifficulty
    party.State = "Open"
end

function PartyLogic.IsMember(party, userId)
    return table.find(party.Members, userId) ~= nil
end

function PartyLogic.IsFull(party)
    return #party.Members >= party.MaxPlayers
end

function PartyLogic.IsEmpty(party)
    return #party.Members == 0
end

-- El primero en entrar a un ascensor vacío es el anfitrión.
function PartyLogic.Join(party, userId)
    if PartyLogic.IsMember(party, userId) then
        return true
    end
    if party.State ~= "Open" then
        return false, "Closed"
    end
    if PartyLogic.IsFull(party) then
        return false, "Full"
    end

    table.insert(party.Members, userId)
    if party.Host == nil then
        party.Host = userId
    end
    return true
end

-- Si se va el anfitrión manda el siguiente en llegar; sin nadie, el grupo se reinicia.
function PartyLogic.Leave(party, userId)
    local index = table.find(party.Members, userId)
    if not index then
        return false
    end

    table.remove(party.Members, index)
    if #party.Members == 0 then
        PartyLogic.Reset(party)
    elseif party.Host == userId then
        party.Host = party.Members[1]
    end
    return true
end

local function canEdit(party, userId)
    return party.Host == userId and party.State == "Open"
end

-- Nunca menos lugares que la gente que ya está adentro.
function PartyLogic.SetMaxPlayers(party, userId, value)
    if not canEdit(party, userId) or not isInteger(value, math.max(1, #party.Members), MAX_PLAYERS) then
        return false
    end
    party.MaxPlayers = value
    return true
end

function PartyLogic.SetDifficulty(party, userId, value)
    if not canEdit(party, userId) or type(value) ~= "string" or not GameConfig.Difficulties[value] then
        return false
    end
    party.Difficulty = value
    return true
end

-- Sólo hasta el capítulo que desbloqueó el anfitrión.
function PartyLogic.SetChapter(party, userId, value, unlocked)
    local limit = math.clamp(tonumber(unlocked) or 1, 1, CHAPTERS)
    if not canEdit(party, userId) or not isInteger(value, 1, limit) then
        return false
    end
    party.Chapter = value
    return true
end

-- Al cambiar de anfitrión el capítulo baja si el nuevo no lo tiene.
function PartyLogic.ClampChapter(party, unlocked)
    local limit = math.clamp(tonumber(unlocked) or 1, 1, CHAPTERS)
    party.Chapter = math.clamp(party.Chapter, 1, limit)
end

function PartyLogic.TeleportData(party)
    return {
        Chapter = party.Chapter,
        Difficulty = party.Difficulty,
        MaxPlayers = party.MaxPlayers,
        Party = table.clone(party.Members),
        Host = party.Host,
    }
end

-- Los datos de viaje pasan por el cliente: se revisa todo y ante la duda se descartan.
function PartyLogic.ParseTeleportData(data)
    if type(data) ~= "table" then
        return nil
    end
    if not isInteger(data.Chapter, 1, CHAPTERS) then
        return nil
    end
    if type(data.Difficulty) ~= "string" or not GameConfig.Difficulties[data.Difficulty] then
        return nil
    end
    if not isInteger(data.MaxPlayers, 1, MAX_PLAYERS) or type(data.Party) ~= "table" then
        return nil
    end

    local members = {}
    for _, userId in ipairs(data.Party) do
        if #members >= data.MaxPlayers then
            break
        end
        if isInteger(userId, 1, math.huge) and not table.find(members, userId) then
            table.insert(members, userId)
        end
    end
    if #members == 0 then
        return nil
    end

    return {
        Chapter = data.Chapter,
        Difficulty = data.Difficulty,
        MaxPlayers = data.MaxPlayers,
        Party = members,
        Host = (data.Host ~= nil and table.find(members, data.Host)) and data.Host or members[1],
        Rejoin = data.Rejoin == true,
    }
end

return PartyLogic
