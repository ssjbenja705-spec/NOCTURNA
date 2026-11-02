local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function check(path, name)
    local current = game

    for _, part in ipairs(string.split(path, ".")) do
        current = current:WaitForChild(part, 10)
        if not current then
            warn("[NOCTURNA] FALTA: " .. name)
            return
        end
    end

    print("[NOCTURNA] OK: " .. name)
end

check("ReplicatedStorage.NocturnaRemotes", "Carpeta de eventos")
check("ReplicatedStorage.Shared", "Módulos compartidos")
check("ServerScriptService.Server", "Scripts del servidor")

print("[NOCTURNA] Comprobaciones iniciales terminadas.")
