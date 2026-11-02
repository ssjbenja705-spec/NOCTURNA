local Config = require(script.Parent:WaitForChild("MapConfig"))
local Generator = require(script.Parent:WaitForChild("RoomGenerator"))

local map = Generator.Generate(Config)

print("[NOCTURNA] Mapa generado correctamente.")
print("[NOCTURNA] Sectores:", map:GetAttribute("SectorCount"))
