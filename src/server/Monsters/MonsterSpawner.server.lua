local Brain = require(script.Parent.Parent.AI.MonsterBrain)

local folder = workspace:FindFirstChild("Monsters")
if not folder then
    folder = Instance.new("Folder")
    folder.Name = "Monsters"
    folder.Parent = workspace
end

local settings = {
    Oyente = {DetectionRange = 90, Speed = 11, ChaseSpeed = 19, Damage = 35},
    Imitador = {DetectionRange = 65, Speed = 10, ChaseSpeed = 18, Damage = 30},
    Quieto = {DetectionRange = 70, Speed = 14, ChaseSpeed = 22, Damage = 40},
    Trepador = {DetectionRange = 75, Speed = 13, ChaseSpeed = 21, Damage = 35},
    Coloso = {DetectionRange = 100, Speed = 8, ChaseSpeed = 16, Damage = 60},
}
local started = {}

local function register(monster)
    if not monster:IsA("Model") or started[monster] then return end
    local key = monster:GetAttribute("MonsterType") or monster.Name
    local config = settings[key]
    if not config then
        warn("[NOCTURNA] Tipo de monstruo desconocido:", key)
        return
    end

    started[monster] = true
    Brain.Start(monster, config)
    print("[NOCTURNA] IA iniciada:", monster.Name)
end

for _, monster in ipairs(folder:GetChildren()) do
    register(monster)
end
folder.ChildAdded:Connect(function(monster)
    task.wait(1)
    register(monster)
end)

print("[NOCTURNA] Registro de criaturas activo.")