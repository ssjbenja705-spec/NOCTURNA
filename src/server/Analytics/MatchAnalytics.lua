local Analytics = {}

Analytics.Match = {
    StartedAt = 0,
    Players = 0,
    MonstersEncountered = 0,
    ObjectivesCompleted = 0,
    Deaths = 0,
}

function Analytics.Start()
    Analytics.Match.StartedAt = os.time()
    Analytics.Match.Players = 0
    Analytics.Match.MonstersEncountered = 0
    Analytics.Match.ObjectivesCompleted = 0
    Analytics.Match.Deaths = 0
end

function Analytics.RecordDeath()
    Analytics.Match.Deaths += 1
end

function Analytics.RecordObjective()
    Analytics.Match.ObjectivesCompleted += 1
end

function Analytics.RecordMonster()
    Analytics.Match.MonstersEncountered += 1
end

function Analytics.GetSummary()
    return {
        Duration = os.time() - Analytics.Match.StartedAt,
        Players = Analytics.Match.Players,
        Monsters = Analytics.Match.MonstersEncountered,
        Objectives = Analytics.Match.ObjectivesCompleted,
        Deaths = Analytics.Match.Deaths,
    }
end

return Analytics
