local Players = game:GetService("Players")

local sessionStarts = {}

Players.PlayerAdded:Connect(function(player)
    sessionStarts[player.UserId] = os.time()
    print("[NOCTURNA ANALYTICS] Entró:", player.Name, player.UserId)
end)

Players.PlayerRemoving:Connect(function(player)
    local started = sessionStarts[player.UserId]
    if started then
        print("[NOCTURNA ANALYTICS] Sesión:", player.Name, os.time() - started, "segundos")
    end
    sessionStarts[player.UserId] = nil
end)
