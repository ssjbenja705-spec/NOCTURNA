-- Herramientas de moderación por chat (!comando) y por panel. Cada acción se vuelve
-- a validar en el servidor y queda registrada.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = game:GetService("ReplicatedStorage").Shared
local ItemConfig = require(Shared.Config.ItemConfig)
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Remotes = require(Shared.Modules.RemoteHelper)

local Analytics = require(script.Parent.Parent.Analytics.Analytics)
local GameState = require(script.Parent.Parent.Core.GameState)
local DamageService = require(script.Parent.Parent.Data.DamageService)
local InventoryService = require(script.Parent.Parent.Inventory.InventoryService)
local MonsterService = require(script.Parent.Parent.Monsters.MonsterService)
local MatchService = require(script.Parent.Parent.Multiplayer.MatchService)
local StoryService = require(script.Parent.Parent.Story.StoryService)
local Config = require(script.Parent.AdminConfig)
local ModerationStore = require(script.Parent.ModerationStore)

local AdminService = {}
local admins = {}
local adminCache = {}
local log = {}

for _, userId in ipairs(Config.AdminUserIds) do
    if typeof(userId) == "number" and userId > 0 then
        admins[userId] = true
    end
end

local function checkGroup(player)
    if game.CreatorType ~= Enum.CreatorType.Group then
        return false
    end

    local success, rank = pcall(function()
        return player:GetRankInGroup(game.CreatorId)
    end)
    if not success then
        return false
    end
    return rank >= (Config.MinimumGroupRank or 255)
end

function AdminService.IsAdmin(player)
    if admins[player.UserId] then
        return true
    end
    if Config.AllowInStudio and RunService:IsStudio() then
        return true
    end

    local cached = adminCache[player]
    if cached ~= nil then
        return cached
    end

    local result = false
    if Config.AllowCreator then
        result = (game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId)
            or checkGroup(player)
    end
    adminCache[player] = result
    return result
end

local function record(moderator, action, detail)
    table.insert(log, 1, {
        Time = os.time(),
        Moderator = moderator.Name,
        Action = action,
        Detail = detail or "",
    })
    if #log > Config.MaxLogEntries then
        table.remove(log)
    end
end

local function filterForBroadcast(text, player)
    local success, filtered = pcall(function()
        return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForBroadcastAsync()
    end)
    return success and filtered or nil
end

local function findPlayer(name)
    if typeof(name) ~= "string" or name == "" then
        return nil
    end
    local lowered = string.lower(name)
    for _, player in ipairs(Players:GetPlayers()) do
        if string.lower(player.Name) == lowered or string.lower(player.DisplayName) == lowered then
            return player
        end
    end
    return nil
end

local function toUserId(value)
    local player = findPlayer(value)
    if player then
        return player.UserId
    end

    local number = tonumber(value)
    if number and number > 0 and number % 1 == 0 then
        return number
    end
    return nil
end

local ACTIONS = {}

function ACTIONS.announce(moderator, args)
    local text = table.concat(args, " "):sub(1, 180)
    local filtered = text ~= "" and filterForBroadcast(text, moderator)
    if not filtered then
        return false, "No se pudo enviar el anuncio."
    end
    Remotes.FireAll("AdminMessage", filtered)
    return true, text
end

function ACTIONS.heal(moderator, args)
    local target = findPlayer(args[1]) or moderator
    local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false, "Sin personaje."
    end
    humanoid.Health = humanoid.MaxHealth
    return true, target.Name
end

function ACTIONS.kill(_, args)
    local target = findPlayer(args[1])
    if not target then
        return false, "Jugador no encontrado."
    end
    DamageService.ApplyDamage(target, 100)
    return true, target.Name
end

function ACTIONS.give(moderator, args)
    local target = findPlayer(args[2]) or moderator
    local itemId = args[1]
    if not ItemConfig[itemId] then
        return false, "Objeto desconocido."
    end
    return InventoryService.AddItem(target, itemId, 1), itemId .. " para " .. target.Name
end

function ACTIONS.setchapter(_, args)
    local chapter = tonumber(args[1])
    if not chapter or GameState.Phase == "Lobby" or not MatchService.SetChapter(chapter) then
        return false, "Capítulo inválido o partida no iniciada."
    end
    return true, tostring(chapter)
end

function ACTIONS.skip()
    local objective = StoryService.SkipObjective()
    if not objective then
        return false, "No hay objetivo activo."
    end
    return true, objective.Id
end

function ACTIONS.lobby()
    MatchService.ReturnToLobby()
    return true
end

function ACTIONS.spawn(_, args)
    local kind = args[1]
    if not MonsterConfig[kind] or not GameState.IsPlaying() then
        return false, "Criatura inválida o partida no iniciada."
    end
    return MonsterService.Spawn(kind) ~= nil, kind
end

function ACTIONS.clearmonsters()
    MonsterService.Clear()
    return true
end

function ACTIONS.freeze()
    local paused = not MonsterService.IsPaused()
    MonsterService.SetPaused(paused)
    return true, paused and "IA detenida" or "IA activa"
end

function ACTIONS.kick(moderator, args)
    local target = findPlayer(args[1])
    if not target or target == moderator then
        return false, "Jugador no válido."
    end
    target:Kick("Expulsado por un administrador.")
    return true, target.Name
end

function ACTIONS.ban(moderator, args)
    local userId = toUserId(args[1])
    if not userId or userId == moderator.UserId then
        return false, "Uso: ban <jugador o UserId> <días, 0 = permanente> <motivo>"
    end

    local days = math.clamp(tonumber(args[2]) or 0, 0, Config.MaxBanDays)
    local reason = table.concat(args, " ", 3):sub(1, 120)
    ModerationStore.Ban(userId, days > 0 and days or nil, reason, moderator.UserId)

    local target = Players:GetPlayerByUserId(userId)
    if target then
        target:Kick("Fuiste sancionado. Motivo: " .. (reason ~= "" and reason or "Incumplir las reglas."))
    end
    return true, string.format("%d (%d días)", userId, days)
end

function ACTIONS.unban(_, args)
    local userId = toUserId(args[1])
    if not userId then
        return false, "UserId inválido."
    end
    ModerationStore.Unban(userId)
    return true, tostring(userId)
end

local function buildPanel()
    local members = {}
    for _, player in ipairs(Players:GetPlayers()) do
        table.insert(members, {Name = player.Name, DisplayName = player.DisplayName, UserId = player.UserId})
    end

    return {
        Players = members,
        Phase = GameState.Phase,
        Chapter = GameState.Chapter,
        Lives = GameState.Lives,
        Monsters = #MonsterService.Active(),
        AiPaused = MonsterService.IsPaused(),
        Log = log,
        Counters = Analytics.GetCounters(),
    }
end

local function sendPanel(player)
    Remotes.FireClient("AdminData", player, buildPanel())
end

function AdminService.Execute(moderator, action, args)
    if not AdminService.IsAdmin(moderator) then
        return false
    end

    local handler = ACTIONS[action]
    if not handler then
        return false
    end

    local success, detail = handler(moderator, args)
    if success then
        record(moderator, action, detail)
    else
        Remotes.FireClient("StoryNotice", moderator, tostring(detail or "No se pudo completar."))
    end
    sendPanel(moderator)
    return success
end

local function handleChat(player, message)
    if message:sub(1, 1) ~= "!" or not AdminService.IsAdmin(player) then
        return
    end

    local args = string.split(message:sub(2), " ")
    local action = string.lower(table.remove(args, 1) or "")
    AdminService.Execute(player, action, args)
end

local function setupPlayer(player)
    task.spawn(function()
        local ban = ModerationStore.GetActiveBan(player.UserId)
        if ban and player.Parent == Players then
            player:Kick("Estás sancionado. Motivo: " .. tostring(ban.Reason ~= "" and ban.Reason or "Incumplir las reglas."))
            return
        end

        player:SetAttribute("IsNocturnaAdmin", AdminService.IsAdmin(player))
    end)

    player.Chatted:Connect(function(message)
        handleChat(player, message)
    end)
end

function AdminService.Start()
    Remotes.OnServer("AdminAction", 5, function(player, action, args)
        if not AdminService.IsAdmin(player) then
            return
        end

        if action == "Refresh" then
            sendPanel(player)
            return
        end

        if typeof(action) ~= "string" or typeof(args) ~= "table" then
            return
        end

        local clean = {}
        for index = 1, math.min(#args, 12) do
            local value = args[index]
            if typeof(value) == "string" then
                clean[index] = value:sub(1, 200)
            else
                return
            end
        end
        AdminService.Execute(player, string.lower(action), clean)
    end)

    Players.PlayerAdded:Connect(setupPlayer)
    Players.PlayerRemoving:Connect(function(player)
        adminCache[player] = nil
    end)
    for _, player in ipairs(Players:GetPlayers()) do
        setupPlayer(player)
    end
end

return AdminService
