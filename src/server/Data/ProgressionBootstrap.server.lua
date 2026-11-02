local Players = game:GetService("Players")

local Progression = require(script.Parent:WaitForChild("ProgressionService"))

local AUTOSAVE_INTERVAL = 60
local shuttingDown = false

local function loadPlayer(player)
    player:SetAttribute("NocturnaDataLoaded", false)

    local loaded = Progression.Load(player)
    if not loaded then
        player:Kick(
            "No se pudieron cargar tus datos de NOCTURNA. " ..
            "Vuelve a intentarlo para proteger tu progreso."
        )
    end
end

Players.PlayerAdded:Connect(loadPlayer)

for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(loadPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
    Progression.Save(player)
    Progression.Remove(player)
end)

task.spawn(function()
    while not shuttingDown do
        task.wait(AUTOSAVE_INTERVAL)

        for _, player in ipairs(Players:GetPlayers()) do
            task.spawn(function()
                Progression.Save(player)
            end)
        end
    end
end)

game:BindToClose(function()
    shuttingDown = true

    local remaining = #Players:GetPlayers()
    local finished = Instance.new("BindableEvent")
    if remaining == 0 then
        finished:Destroy()
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            Progression.Save(player)
            remaining -= 1
            if remaining <= 0 then
                finished:Fire()
            end
        end)
    end

    finished.Event:Wait()
    finished:Destroy()
end)
