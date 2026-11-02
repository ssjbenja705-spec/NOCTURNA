-- NOCTURNA: Advanced Monster Registry

local Workspace = game:GetService("Workspace")

local Controller = require(script.Parent:WaitForChild("AdvancedMonsterController"))
local map = Workspace:WaitForChild("NOCTURNA_MAP")

while map:GetAttribute("Generated") ~= true do
    map:GetAttributeChangedSignal("Generated"):Wait()
end

local monstersFolder = map:WaitForChild("Monsters")
local controllers = {}

local function registerMonster(monster)
    if not monster:IsA("Model") or controllers[monster] then
        return
    end

    local monsterType = monster:GetAttribute("MonsterType")
    if typeof(monsterType) ~= "string" then
        warn("[NOCTURNA] Monstruo sin atributo MonsterType:", monster.Name)
        return
    end

    local success, controller = pcall(function()
        return Controller.new(monster, monsterType)
    end)
    if not success then
        warn("[NOCTURNA] No se pudo iniciar:", monster.Name, controller)
        return
    end

    controllers[monster] = controller
    controller:Start()
    print("[NOCTURNA] IA avanzada iniciada:", monster.Name, monsterType)

    monster.Destroying:Connect(function()
        controller:Stop()
        controllers[monster] = nil
    end)
end

for _, monster in ipairs(monstersFolder:GetChildren()) do
    registerMonster(monster)
end

monstersFolder.ChildAdded:Connect(function(monster)
    task.wait(0.5)
    registerMonster(monster)
end)

print("[NOCTURNA] Registro de monstruos preparado.")
