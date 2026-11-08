-- Texturas PBR propias (horneadas en Blender: assets/blender/bake_textures.py).
--
-- Cada mapa es una imagen PNG de assets/textures/<Nombre>/ que hay que subir a
-- Roblox. Pegá acá el NÚMERO del asset subido (sin "rbxassetid://"): la tabla de
-- assets/textures/UPLOAD.md dice qué archivo va en cada campo.
--
-- Con 0 el mapa no existe. El servidor (MaterialLibrary) crea en MaterialService
-- un MaterialVariant por fila apenas tiene su Color; los demás mapas son
-- opcionales (sin Metalness, Roblox lo toma como no metálico). Mientras todo esté
-- en 0 el juego usa los materiales de Roblox de siempre, sin ningún cambio.
--
-- Campos de cada fila:
--   BaseMaterial  material de Roblox sobre el que se monta la variante.
--   StudsPerTile  cuántos studs ocupa un mosaico de la textura.
--   Pattern       Regular (repite tal cual: ladrillo, baldosa, tablas) u Organic
--                 (Roblox rompe la repetición: hormigón, revoque, tejido).
--   Mean          color medio del albedo (lo calcula el horneado, stats.json). En la
--                 utilería el color de la pieza se divide por este valor para que la
--                 textura no la oscurezca: el tinte de cada mueble se conserva.
--   Tint          (opcional) color de las paredes, pisos y techos que usan la
--                 variante: la textura ya trae su color, así que la pieza pasa a este
--                 tono (blanco = la textura tal cual).
local TextureAssets = {}

local WHITE = Color3.fromRGB(255, 255, 255)

TextureAssets.Variants = {
    -- Superficies de las salas (ThemeConfig.<Tema>.Surfaces.Wall/Floor/Ceiling) ------
    NocturnaTunnelBrick = {
        BaseMaterial = "Brick", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(77, 50, 40),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaWetConcrete = {
        BaseMaterial = "Concrete", StudsPerTile = 12, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(80, 78, 72),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaStainedConcrete = {
        BaseMaterial = "Concrete", StudsPerTile = 12, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(96, 90, 80),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaPeelingPlaster = {
        BaseMaterial = "Plaster", StudsPerTile = 10, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(110, 128, 110),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaDirtyTiles = {
        BaseMaterial = "CeramicTiles", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(140, 136, 124),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaStainedPlaster = {
        BaseMaterial = "Plaster", StudsPerTile = 10, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(160, 152, 134),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaFleshWall = {
        BaseMaterial = "Pebble", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(100, 60, 56),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaStainedSlate = {
        BaseMaterial = "Slate", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(52, 54, 52),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaFleshCeiling = {
        BaseMaterial = "Slate", StudsPerTile = 8, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(80, 40, 42),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaScratchedSteel = {
        BaseMaterial = "Metal", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(76, 80, 84),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaWornPlate = {
        BaseMaterial = "DiamondPlate", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(96, 96, 96),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaTornWallpaper = {
        BaseMaterial = "Fabric", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(130, 112, 92),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaScuffedOak = {
        BaseMaterial = "WoodPlanks", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(104, 76, 50),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },

    -- Utilería y puertas (casi neutras: las tiñe el color de cada pieza) -------------
    NocturnaRottenWood = {
        BaseMaterial = "Wood", StudsPerTile = 4, Pattern = "Regular",
        Mean = Color3.fromRGB(180, 168, 152),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaRustedSheet = {
        BaseMaterial = "CorrodedMetal", StudsPerTile = 6, Pattern = "Regular",
        Mean = Color3.fromRGB(170, 150, 130),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaGrimyMetal = {
        BaseMaterial = "Metal", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(190, 190, 186),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaWornFabric = {
        BaseMaterial = "Fabric", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(190, 182, 168),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaBookCloth = {
        BaseMaterial = "Leather", StudsPerTile = 2, Pattern = "Organic",
        Mean = Color3.fromRGB(176, 164, 148),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaDirtyGlass = {
        BaseMaterial = "Glass", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(220, 218, 212),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaAgedPaper = {
        BaseMaterial = "Cardboard", StudsPerTile = 2, Pattern = "Organic",
        Mean = Color3.fromRGB(200, 186, 160),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
}

-- Material de Roblox de una pieza de utilería o puerta → clave de
-- ThemeConfig.<Tema>.Surfaces con la variante que le toca en ese capítulo.
TextureAssets.PropMaterials = {
    Wood = "Wood",
    WoodPlanks = "Wood",
    Metal = "Metal",
    CorrodedMetal = "Rust",
    DiamondPlate = "Plate",
    Fabric = "Fabric",
    Leather = "Leather",
    Cardboard = "Paper",
    Glass = "Glass",
}

-- Los cuatro mapas de cada fila, con la propiedad de MaterialVariant que llenan.
TextureAssets.Maps = {
    {Key = "Color", Property = "ColorMap", Suffix = "_Color.png"},
    {Key = "Normal", Property = "NormalMap", Suffix = "_Normal.png"},
    {Key = "Roughness", Property = "RoughnessMap", Suffix = "_Roughness.png"},
    {Key = "Metalness", Property = "MetalnessMap", Suffix = "_Metalness.png"},
}

-- "rbxassetid://N" para un número (o texto con el número) válido; nil si es 0.
function TextureAssets.Url(id)
    if type(id) == "string" then
        local digits = string.match(id, "(%d+)%s*$")
        id = digits and tonumber(digits) or 0
    end
    if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then
        return nil
    end
    return "rbxassetid://" .. string.format("%d", id)
end

-- ¿Ya se puede crear la variante? (hace falta al menos el mapa de color).
function TextureAssets.Ready(name)
    local entry = TextureAssets.Variants[name]
    return entry ~= nil and TextureAssets.Url(entry.Color) ~= nil
end

return TextureAssets
