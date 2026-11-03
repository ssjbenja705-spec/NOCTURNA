-- Estado de la partida actual, compartido entre servicios del servidor.
-- Fases: Lobby, Loading, Playing, Cutscene, Failed, Ending.
local Shared = game:GetService("ReplicatedStorage").Shared
local GameConfig = require(Shared.Config.GameConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local GameState = {
    Phase = "Lobby",
    Chapter = 0,
    Difficulty = GameConfig.DefaultDifficulty,
    Lives = 0,
    MaxLives = 0,
    Flags = {},
    Layout = nil,
    Plan = nil,
    Nav = nil,
    Tracker = nil,
    Checkpoint = nil,
    Powered = true,
}

function GameState.IsPlaying()
    return GameState.Phase == "Playing"
end

function GameState.DifficultySettings()
    return GameConfig.Difficulties[GameState.Difficulty] or GameConfig.Difficulties[GameConfig.DefaultDifficulty]
end

function GameState.Snapshot()
    return {
        Phase = GameState.Phase,
        Chapter = GameState.Chapter,
        ChapterName = GameConfig.Chapters[GameState.Chapter],
        Difficulty = GameState.Difficulty,
        Lives = GameState.Lives,
        MaxLives = GameState.MaxLives,
        ShowCompass = GameState.DifficultySettings().ShowCompass,
    }
end

function GameState.Broadcast(player)
    if player then
        Remotes.FireClient("GameState", player, GameState.Snapshot())
    else
        Remotes.FireAll("GameState", GameState.Snapshot())
    end
end

function GameState.SetPhase(phase)
    GameState.Phase = phase
    GameState.Broadcast()
end

function GameState.SetFlag(name)
    GameState.Flags[name] = true
end

function GameState.HasFlag(name)
    return GameState.Flags[name] == true
end

function GameState.ResetChapter()
    GameState.Flags = {}
    GameState.Layout = nil
    GameState.Plan = nil
    GameState.Nav = nil
    GameState.Tracker = nil
    GameState.Checkpoint = nil
end

return GameState
