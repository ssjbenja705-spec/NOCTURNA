-- Crea en MaterialService los MaterialVariant de las texturas propias a partir de
-- TextureAssets: no hace falta ningún paso en Studio más que subir las imágenes y
-- pegar sus números. Una fila sin Color (0) no se crea y el juego sigue con el
-- material de Roblox. MaterialService se replica: los clientes las ven solas.
--
-- Si Roblox rechaza algo (por ejemplo, un BaseMaterial que no admite variantes),
-- esa fila se salta con un aviso y las demás siguen.
local MaterialService = game:GetService("MaterialService")

local Shared = game:GetService("ReplicatedStorage").Shared
local TextureAssets = require(Shared.Config.TextureAssets)

local MaterialLibrary = {}

-- Atributos que lee PropKit al aplicar la variante.
MaterialLibrary.TINT = "NocturnaTint"
MaterialLibrary.MEAN = "NocturnaMean"
MaterialLibrary.OWNED = "NocturnaTexture"

local warned = {}

local function warnOnce(name, message)
    if not warned[name] then
        warned[name] = true
        warn("[NOCTURNA] Textura " .. name .. ": " .. tostring(message))
    end
end

local function configure(variant, name, entry)
    variant.Name = name
    variant.BaseMaterial = (Enum.Material :: any)[entry.BaseMaterial]
    variant.StudsPerTile = entry.StudsPerTile or 8
    variant.MaterialPattern = entry.Pattern == "Organic" and Enum.MaterialPattern.Organic or Enum.MaterialPattern.Regular
    for _, map in ipairs(TextureAssets.Maps) do
        (variant :: any)[map.Property] = TextureAssets.Url(entry[map.Key]) or ""
    end
end

-- Crea o actualiza las variantes listas; borra las propias que ya no lo están
-- (si alguien vuelve un número a 0). Devuelve cuántas quedaron.
function MaterialLibrary.Ensure(assets)
    assets = assets or TextureAssets
    local count = 0
    for name, entry in pairs(assets.Variants) do
        local existing = MaterialService:FindFirstChild(name)
        local ours = existing and existing:IsA("MaterialVariant") and existing:GetAttribute(MaterialLibrary.OWNED) == true
        if TextureAssets.Url(entry.Color) then
            if existing and not ours then
                -- Una variante hecha a mano en Studio con el mismo nombre manda.
                count += 1
            else
                local variant = existing or Instance.new("MaterialVariant")
                local ok, err = pcall(configure, variant, name, entry)
                if ok then
                    variant:SetAttribute(MaterialLibrary.OWNED, true)
                    variant:SetAttribute(MaterialLibrary.TINT, entry.Tint)
                    variant:SetAttribute(MaterialLibrary.MEAN, entry.Mean)
                    variant.Parent = MaterialService
                    count += 1
                else
                    warnOnce(name, err)
                    variant:Destroy()
                end
            end
        elseif ours and existing then
            existing:Destroy()
        end
    end
    return count
end

-- Las variantes creadas por este módulo (para pruebas y diagnóstico).
function MaterialLibrary.Created()
    local list = {}
    for _, child in ipairs(MaterialService:GetChildren()) do
        if child:IsA("MaterialVariant") and child:GetAttribute(MaterialLibrary.OWNED) == true then
            table.insert(list, child)
        end
    end
    return list
end

return MaterialLibrary
