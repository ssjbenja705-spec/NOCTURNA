local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("GameConfig"))

local currentChapter = 1

workspace:SetAttribute("NocturnaChapter", currentChapter)
workspace:SetAttribute("NocturnaChapterName", Config.Chapters[currentChapter])

local function setChapter(index)
    if index < 1 or index > #Config.Chapters then return false end
    currentChapter = index
    workspace:SetAttribute("NocturnaChapter", index)
    workspace:SetAttribute("NocturnaChapterName", Config.Chapters[index])
    print("[NOCTURNA] Capítulo activo: " .. Config.Chapters[index])
    return true
end

_G.NocturnaSetChapter = setChapter
print("[NOCTURNA] Sistema de capítulos preparado.")
