--!nocheck
-- Jugador simulado: lee el objetivo que le manda el servidor, camina hasta el lugar
-- y usa el prompt que el servidor creó ahí, igual que una persona.
local Bot = {}

local function promptHost(prompt)
    return prompt.Parent
end

local function allPrompts(Engine)
    local prompts = {}
    for _, descendant in ipairs(Engine.Workspace:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") and descendant.Enabled then
            table.insert(prompts, descendant)
        end
    end
    return prompts
end

function Bot.NearestPrompt(Engine, position)
    local best, bestDistance = nil, math.huge
    for _, prompt in ipairs(allPrompts(Engine)) do
        local host = promptHost(prompt)
        if host:IsA("BasePart") then
            local distance = (host.Position - position).Magnitude
            if distance < bestDistance then
                best, bestDistance = prompt, distance
            end
        end
    end
    return best, bestDistance
end

-- El bot se teletransporta: el antitrampas lo trataría (con razón) como un tramposo.
function Bot.MoveTo(Engine, player, position)
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if root then
        Engine.RequireServer("Security.AntiCheat").Grace(player, 3)
        root.CFrame = Engine.Roblox.CFrame.new(position.X, 3, position.Z)
    end
end

function Bot.Use(Engine, player, position)
    Bot.MoveTo(Engine, player, position)
    local prompt = Bot.NearestPrompt(Engine, position)
    if prompt then
        local host = promptHost(prompt)
        Bot.MoveTo(Engine, player, host.Position)
        prompt:Fire(player)
    end
    return prompt
end

-- Un paso de juego para el bot. Devuelve el identificador del objetivo actual.
function Bot.Act(Engine, player)
    local args = Engine.LastSent("ObjectiveUpdate", player)
    local update = args and args[1]
    if not update or update.Finished or not update.Waypoints then
        return nil
    end

    local waypoint = update.Waypoints[1]
    if not waypoint then
        return update.ObjectiveId
    end

    if string.find(update.ObjectiveId, "C1_ENTRY") or update.ObjectiveId == "C4_CORE" or update.ObjectiveId == "C5_FIND" then
        Bot.MoveTo(Engine, player, waypoint)
    else
        Bot.Use(Engine, player, waypoint)
    end
    return update.ObjectiveId
end

return Bot
