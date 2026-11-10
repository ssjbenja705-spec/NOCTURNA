-- Genera assets/materials/*.model.json (un MaterialVariant por textura propia) a
-- partir de src/shared/Config/TextureAssets.lua. Roblox no deja que un script del
-- juego escriba BaseMaterial en tiempo de ejecución, así que las variantes tienen
-- que venir armadas en el lugar: Rojo las mete en MaterialService al compilar.
--
--   lune run tools/gen_materials.luau
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local source = fs.readFile("src/shared/Config/TextureAssets.lua")
local MAPS = {
    {Key = "Color", Property = "ColorMap"},
    {Key = "Normal", Property = "NormalMap"},
    {Key = "Roughness", Property = "RoughnessMap"},
    {Key = "Metalness", Property = "MetalnessMap"},
}

local function rgb(text)
    local r, g, b = string.match(text, "fromRGB%((%d+),%s*(%d+),%s*(%d+)%)")
    if r then
        return {tonumber(r) / 255, tonumber(g) / 255, tonumber(b) / 255}
    end
    if string.find(text, "WHITE") then
        return {1, 1, 1}
    end
    return nil
end

if fs.isDir("assets/materials") then
    for _, name in ipairs(fs.readDir("assets/materials")) do
        if string.match(name, "%.model%.json$") then
            fs.removeFile("assets/materials/" .. name)
        end
    end
else
    fs.writeDir("assets/materials")
end

local count = 0
for name, body in string.gmatch(source, "\n    (Nocturna%w+) = (%b{})") do
    local base = string.match(body, 'BaseMaterial = "(%w+)"')
    local studs = tonumber(string.match(body, "StudsPerTile = ([%d%.]+)"))
    local pattern = string.match(body, 'Pattern = "(%w+)"') or "Regular"
    local color = tonumber(string.match(body, "Color = (%d+)"))
    -- Roblox no admite variantes de Glass: esa superficie queda con su material.
    if base and base ~= "Glass" and color and color > 0 then
        local properties = {
            BaseMaterial = base,
            StudsPerTile = studs or 8,
            MaterialPattern = pattern,
        }
        for _, map in ipairs(MAPS) do
            local id = tonumber(string.match(body, map.Key .. " = (%d+)"))
            if id and id > 0 then
                properties[map.Property] = "rbxassetid://" .. tostring(id)
            end
        end
        local attributes = {NocturnaTexture = true}
        local tint = string.match(body, "Tint = ([^,\n]+%b())") or string.match(body, "Tint = (WHITE)")
        local mean = string.match(body, "Mean = (Color3%.fromRGB%b())")
        if tint and rgb(tint) then
            attributes.NocturnaTint = {Color3 = rgb(tint)}
        end
        if mean and rgb(mean) then
            attributes.NocturnaMean = {Color3 = rgb(mean)}
        end
        fs.writeFile("assets/materials/" .. name .. ".model.json", serde.encode("json", {
            className = "MaterialVariant",
            properties = properties,
            attributes = attributes,
        }, true))
        count += 1
    end
end

print("MaterialVariants generados: " .. count)
