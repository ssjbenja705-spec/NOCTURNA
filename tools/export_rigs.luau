-- Copia los esqueletos importados en Studio (ServerStorage.NocturnaModels.<Criatura>Rig)
-- del lugar guardado a assets/models/rbxm/<Criatura>Rig.rbxmx, para que Rojo los
-- incluya en cada compilación.
--
--   lune run tools/export_rigs.luau NOCTURNA.rbxlx
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local placePath = process.args[1] or "NOCTURNA.rbxlx"
local game = roblox.deserializePlace(fs.readFile(placePath))
local storage = game:GetService("ServerStorage")
local folder = storage:FindFirstChild("NocturnaModels")
assert(folder, "No hay ServerStorage.NocturnaModels en " .. placePath)

local exported = {}
for _, child in ipairs(folder:GetChildren()) do
    if string.match(child.Name, "Rig$") then
        local bones = 0
        for _, descendant in ipairs(child:GetDescendants()) do
            if descendant.ClassName == "Bone" then
                bones += 1
            end
        end
        fs.writeFile("assets/models/rbxm/" .. child.Name .. ".rbxmx", roblox.serializeModel({child}, true))
        table.insert(exported, child.Name .. " (" .. bones .. " huesos)")
    end
end
print("Exportados: " .. (#exported > 0 and table.concat(exported, ", ") or "ninguno"))
