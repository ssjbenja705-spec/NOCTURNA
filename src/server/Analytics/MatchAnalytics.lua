local Analytics = {}

Analytics.Match = {
    StartedAt = 0,
    ChapterStartedAt = 0,
    Chapter = 0,
    Players = 0,
    MonstersEncountered = 0,
    ObjectivesCompleted = 0,
    Deaths = 0,
    Failures = 0,
}

function Analytics.StartMatch(playerCount)
    Analytics.Match.StartedAt = os.time()
    Analytics.Match.Players = playerCount
end

function Analytics.StartChapter(chapter, playerCount)
    Analytics.Match.Chapter = chapter
    Analytics.Match.ChapterStartedAt = os.time()
    Analytics.Match.Players = playerCount
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

function Analytics.RecordFailure()
    Analytics.Match.Failures += 1
end

function Analytics.GetSummary()
    return {
        Duration = os.time() - Analytics.Match.ChapterStartedAt,
        Players = Analytics.Match.Players,
        Monsters = Analytics.Match.MonstersEncountered,
        Objectives = Analytics.Match.ObjectivesCompleted,
        Deaths = Analytics.Match.Deaths,
        Failures = Analytics.Match.Failures,
    }
end

return Analytics
