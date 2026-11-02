local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent:WaitForChild("MonsterConfig"))
local AI = require(script.Parent.Parent.AI:WaitForChild("MonsterAI"))
local remotes = ReplicatedStorage:WaitForChild("NocturnaRemotes")
local effectRemote = remotes:WaitForChild("MonsterEffect")

local monsterFolder = workspace:FindFirstChild("Monsters")
if not monsterFolder then
    monsterFolder = Instance.new("Folder")
    monsterFolder.Name = "Monsters"
    monsterFolder.Parent = workspace
end

local aliases = {
    Oyente = "ElOyente",
    Imitador = "ElImitador",
    Quieto = "ElQuieto",
    Trepador = "ElTrepador",
    Coloso = "ElColoso",
}
local lastPath = {}
local lastColossusEvent = {}
local lastImitation = {}
local started = {}

local function getNoiseTarget(monster, settings)
    local root = monster:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    local noises = _G.NocturnaRecentNoise or {}
    local bestNoise
    local bestScore = -math.huge

    for _, noise in ipairs(noises) do
        local age = os.clock() - noise.Time
        local distance = (noise.Position - root.Position).Magnitude
        if age < 5 and distance < settings.HearingRange then
            local score = noise.Intensity - distance * 0.4 - age * 8
            if score > bestScore then
                bestScore = score
                bestNoise = noise
            end
        end
    end

    return bestNoise
end

local function getMonsterTarget(monster, monsterType, settings)
    local root = monster:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    if monsterType == "ElOyente" then
        local noise = getNoiseTarget(monster, settings)
        if noise then
            return noise.Position, noise.Player
        end
    end

    if monsterType == "ElQuieto" then
        for _, player in ipairs(Players:GetPlayers()) do
            if AI.IsBeingWatched(monster, player) then
                return nil, nil, true
            end
        end
    end

    local player = AI.GetNearestPlayer(root.Position, settings.DetectionRange)
    if player and player.Character then
        local playerRoot = player.Character:FindFirstChild("HumanoidRootPart")
        if playerRoot then
            return playerRoot.Position, player
        end
    end

    if monsterType == "ElImitador" then
        local noise = getNoiseTarget(monster, settings)
        if noise then
            return noise.Position, noise.Player
        end
    end

    return nil
end

local function runMonster(monster)
    if not monster:IsA("Model") or started[monster] then return end

    local humanoid = monster:FindFirstChildOfClass("Humanoid")
    local root = monster:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        warn("[NOCTURNA] El monstruo necesita Humanoid y HumanoidRootPart:", monster.Name)
        return
    end

    local requestedType = monster:GetAttribute("MonsterType") or monster.Name
    local monsterType = aliases[requestedType] or requestedType
    local settings = Config[monsterType]
    if not settings then
        warn("[NOCTURNA] Tipo de monstruo desconocido:", requestedType)
        return
    end

    started[monster] = true
    pcall(function()
        root:SetNetworkOwner(nil)
    end)
    lastPath[monster] = 0

    task.spawn(function()
        while monster.Parent and humanoid.Health > 0 do
            local destination, targetPlayer, frozen = getMonsterTarget(monster, monsterType, settings)

            if frozen then
                humanoid:MoveTo(root.Position)
                humanoid.WalkSpeed = 0
            else
                humanoid.WalkSpeed = settings.Speed
                if destination then
                    local now = os.clock()
                    if now - (lastPath[monster] or 0) >= settings.RepathTime then
                        lastPath[monster] = now
                        AI.MoveTo(monster, destination, settings.Speed)
                    end

                    if targetPlayer then
                        AI.Attack(monster, targetPlayer, settings.Damage, settings.AttackRange)
                    end

                    if monsterType == "ElColoso" and now - (lastColossusEvent[monster] or 0) > 12 then
                        lastColossusEvent[monster] = now
                        for _, player in ipairs(Players:GetPlayers()) do
                            effectRemote:FireClient(player, "COLOSSUS_NEAR")
                        end
                    end
                else
                    humanoid:MoveTo(root.Position)
                end
            end

            if monsterType == "ElImitador" then
                local now = os.clock()
                if now - (lastImitation[monster] or 0) > 25 then
                    lastImitation[monster] = now
                    for _, player in ipairs(Players:GetPlayers()) do
                        effectRemote:FireClient(player, "IMITATOR_CALL")
                    end
                end
            end

            task.wait(0.25)
        end

        lastPath[monster] = nil
        lastColossusEvent[monster] = nil
        lastImitation[monster] = nil
        started[monster] = nil
    end)
end

for _, monster in ipairs(monsterFolder:GetChildren()) do
    runMonster(monster)
end
monsterFolder.ChildAdded:Connect(function(monster)
    task.wait(1)
    runMonster(monster)
end)

print("[NOCTURNA] Controlador de monstruos iniciado.")
