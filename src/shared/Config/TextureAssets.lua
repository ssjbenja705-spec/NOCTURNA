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
        Mean = Color3.fromRGB(79, 56, 46),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaWetConcrete = {
        BaseMaterial = "Concrete", StudsPerTile = 12, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(89, 87, 81),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaStainedConcrete = {
        BaseMaterial = "Concrete", StudsPerTile = 12, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(104, 100, 92),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaPeelingPlaster = {
        BaseMaterial = "Plaster", StudsPerTile = 10, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(128, 140, 121),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaDirtyTiles = {
        BaseMaterial = "CeramicTiles", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(146, 143, 130),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaStainedPlaster = {
        BaseMaterial = "Plaster", StudsPerTile = 10, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(171, 163, 145),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaFleshWall = {
        BaseMaterial = "Pebble", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(101, 62, 53),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaStainedSlate = {
        BaseMaterial = "Slate", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(51, 53, 46),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaFleshCeiling = {
        BaseMaterial = "Slate", StudsPerTile = 8, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(85, 34, 38),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaScratchedSteel = {
        BaseMaterial = "Metal", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(71, 76, 82),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaWornPlate = {
        BaseMaterial = "DiamondPlate", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(79, 80, 81),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaTornWallpaper = {
        BaseMaterial = "Fabric", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(147, 128, 107),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaScuffedOak = {
        BaseMaterial = "WoodPlanks", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(111, 81, 51),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },

    -- Utilería y puertas (casi neutras: las tiñe el color de cada pieza) -------------
    NocturnaRottenWood = {
        BaseMaterial = "Wood", StudsPerTile = 4, Pattern = "Regular",
        Mean = Color3.fromRGB(191, 180, 160),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaRustedSheet = {
        BaseMaterial = "CorrodedMetal", StudsPerTile = 6, Pattern = "Regular",
        Mean = Color3.fromRGB(179, 177, 171),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaGrimyMetal = {
        BaseMaterial = "Metal", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(193, 194, 193),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaWornFabric = {
        BaseMaterial = "Fabric", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(177, 169, 157),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaBookCloth = {
        BaseMaterial = "Leather", StudsPerTile = 2, Pattern = "Organic",
        Mean = Color3.fromRGB(172, 160, 144),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaDirtyGlass = {
        BaseMaterial = "Glass", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(233, 233, 229),
        Color = 0, Normal = 0, Roughness = 0, Metalness = 0,
    },
    NocturnaAgedPaper = {
        BaseMaterial = "Cardboard", StudsPerTile = 2, Pattern = "Organic",
        Mean = Color3.fromRGB(208, 199, 175),
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
