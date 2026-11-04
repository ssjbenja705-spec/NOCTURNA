-- Prueba dentro del motor real. Sólo existe en test.project.json, nunca en el juego
-- publicado. Al darle Play en Studio recorre los cinco capítulos y escribe en Output
-- una línea [NOCTURNA TEST] por cada comprobación.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService:WaitForChild("Server")
local EventBus = require(Server.Core.EventBus)
local GameState = require(Server.Core.GameState)
local MatchService = require(Server.Multiplayer.MatchService)
local MonsterService = require(Server.Monsters.MonsterService)
local RoomGenerator = require(Server.World.RoomGenerator)

local passed, failed = 0, 0

local function check(name, condition, detail)
    if condition then
        passed += 1
        print("[NOCTURNA TEST] OK   ", name)
    else
        failed += 1
        warn("[NOCTURNA TEST] FALLA", name, detail or "")
    end
end

local function waitFor(condition, timeout)
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        if condition() then
            return true
        end
        task.wait(0.1)
    end
    return condition()
end

local function countParts(folder)
    local count = 0
    for _, item in ipairs(folder:GetDescendants()) do
        if item:IsA("BasePart") then
            count += 1
        end
    end
    return count
end

local function runChapterChecks(player, chapter)
    if chapter == 1 then
        EventBus.Emit("MatchRequested", 1, "Normal")
    else
        MatchService.SetChapter(chapter)
    end

    local started = waitFor(function()
        return GameState.Phase == "Playing" and GameState.Chapter == chapter
    end, 60)
    check("capítulo " .. chapter .. " inicia", started, GameState.Phase)
    if not started then
        return
    end

    local map = workspace:FindFirstChild("NOCTURNA_MAP")
    check("capítulo " .. chapter .. " tiene mapa", map ~= nil)
    print("[NOCTURNA TEST] piezas del mapa:", countParts(map), "luces:", #CollectionService:GetTagged("NocturnaLight"))

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    check("capítulo " .. chapter .. " personaje presente", root ~= nil)

    task.wait(1)
    local floor = root and workspace:Raycast(root.Position, Vector3.new(0, -12, 0), RaycastParams.new())
    check("capítulo " .. chapter .. " personaje sobre el piso", floor ~= nil)

    local layout = GameState.Layout
    local slot = RoomGenerator.SlotCFrame(layout, GameState.Plan.Hides[1].Cell, GameState.Plan.Hides[1].Slot)
    local center = GameState.Nav:Center(GameState.Plan.Hides[1].Cell, 0)
    check("los rincones miran a la sala", (center - slot.Position).Unit:Dot(slot.LookVector) > 0.99)

    -- Dos celdas vecinas sin abertura: el rayo debe chocar con la pared.
    for _, cell in ipairs(layout.Cells) do
        if not cell.Open.E and cell.X < layout.Width then
            local from = GameState.Nav:Center(cell.Index, 3)
            local to = GameState.Nav:Center(cell.Index + 1, 3)
            local blockedRay = workspace:Raycast(from, to - from)
            check("las paredes bloquean la visión", blockedRay ~= nil)
            break
        end
    end
end

local function runMonsterChecks()
    for _, kind in ipairs({"ElOyente", "ElImitador", "ElQuieto", "ElTrepador", "ElColoso"}) do
        local entry = MonsterService.Spawn(kind)
        check(kind .. " aparece", entry ~= nil)

        if entry then
            local before = entry.Root.Position
            local limbs = 0
            for _, part in ipairs(entry.Model:GetDescendants()) do
                if part:IsA("Motor6D") then
                    limbs += 1
                    local rest = part.Part0.CFrame * part.C0 * part.Transform * part.C1:Inverse()
                    local gap = (part.Part1.Position - rest.Position).Magnitude
                    if gap > 0.1 then
                        check(kind .. " extremidad unida", false, part.Name .. " separada " .. gap)
                    end
                end
            end
            check(kind .. " tiene cuerpo", limbs >= 4, limbs)

            task.wait(4)
            check(kind .. " sigue activo", entry.Model.Parent ~= nil)
            print("[NOCTURNA TEST]", kind, "estado", entry.Controller.State, "movió", (entry.Root.Position - before).Magnitude)
        end
    end
end

local function run()
    local player = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
    task.wait(3)

    check("lobby construido", workspace:FindFirstChild("NOCTURNA_LOBBY") ~= nil)
    check("remotos creados", game:GetService("ReplicatedStorage"):FindFirstChild("NocturnaRemotes") ~= nil)
    check("personaje cargado", waitFor(function()
        return player.Character ~= nil
    end, 20))
    print("[NOCTURNA TEST] guardado sin conexión:", player:GetAttribute("NocturnaSaveOffline"))

    for chapter = 1, 5 do
        runChapterChecks(player, chapter)
    end

    runMonsterChecks()

    MatchService.ReturnToLobby()
    check("regresa al lobby", waitFor(function()
        return GameState.Phase == "Lobby"
    end, 10))

    print(string.format("[NOCTURNA TEST] FIN: %d correctas, %d fallidas", passed, failed))
end

task.spawn(run)
