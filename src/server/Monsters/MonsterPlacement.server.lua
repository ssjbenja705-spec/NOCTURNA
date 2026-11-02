local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local map = Workspace:WaitForChild("NOCTURNA_MAP")
while map:GetAttribute("Generated") ~= true do
    map:GetAttributeChangedSignal("Generated"):Wait()
end

local markers = map:WaitForChild("MonsterSpawns")
local assets = ServerStorage:FindFirstChild("MonsterModels")

if not assets then
    warn("[NOCTURNA] Crea ServerStorage/MonsterModels y coloca los modelos.")
    return
end

local activeFolder = Workspace:FindFirstChild("Monsters")
if not activeFolder then
    activeFolder = Instance.new("Folder")
    activeFolder.Name = "Monsters"
    activeFolder.Parent = Workspace
end

for _, marker in ipairs(markers:GetChildren()) do
    local monsterType = marker:GetAttribute("MonsterType")
    local template = monsterType and assets:FindFirstChild(monsterType)

    if template and template:IsA("Model") then
        if not template:FindFirstChildOfClass("Humanoid")
            or not template:FindFirstChild("HumanoidRootPart") then
            warn("[NOCTURNA] Modelo incompleto:", monsterType)
        elseif not activeFolder:FindFirstChild(monsterType) then
            local monster = template:Clone()
            monster.Name = monsterType
            monster:SetAttribute("MonsterType", monsterType)
            monster.Parent = activeFolder
            monster:PivotTo(marker.CFrame + Vector3.new(0, 3, 0))

            print("[NOCTURNA] Monstruo colocado:", monsterType)
        end
    else
        warn("[NOCTURNA] Falta el modelo:", monsterType)
    end
end
