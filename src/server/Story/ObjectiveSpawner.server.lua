local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local chapters = require(script.Parent:WaitForChild("ChapterConfig"))
local mapConfig = require(script.Parent.Parent.World:WaitForChild("MapConfig"))

local map = Workspace:WaitForChild("NOCTURNA_MAP")
while map:GetAttribute("Generated") ~= true do
    map:GetAttributeChangedSignal("Generated"):Wait()
end

local folder = map:FindFirstChild("StoryObjectives")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name = "StoryObjectives"
folder.Parent = map

local total = 0
for chapterNumber, chapter in ipairs(chapters) do
    for objectiveIndex, objective in ipairs(chapter.Objectives) do
        total += 1
        local cell = total - 1
        local x = cell % mapConfig.Width
        local z = math.floor(cell / mapConfig.Width) % mapConfig.Depth
        local offset = (objectiveIndex - 2) * 10

        local part = Instance.new("Part")
        part.Name = objective.Id
        part.Size = Vector3.new(2.5, 2.5, 2.5)
        part.Position = Vector3.new(x * mapConfig.CellSize + offset, 2, z * mapConfig.CellSize + 8)
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(105, 145, 165)
        part:SetAttribute("ObjectiveId", objective.Id)
        part:SetAttribute("ChapterNumber", chapterNumber)
        part.Parent = folder

        local prompt = Instance.new("ProximityPrompt")
        prompt.ActionText = "Investigar"
        prompt.ObjectText = objective.Name
        prompt.HoldDuration = 0.8
        prompt.MaxActivationDistance = 10
        prompt.RequiresLineOfSight = false
        prompt:SetAttribute("MissionId", "CHAPTER_" .. chapterNumber)
        prompt:SetAttribute("ObjectiveId", objective.Id)
        prompt.Parent = part

        CollectionService:AddTag(prompt, "NocturnaObjective")
    end
end

print("[NOCTURNA] Objetivos de campaña creados:", total)
