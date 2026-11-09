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
        Color = 86592556816786, Normal = 108756295237978, Roughness = 127632798226887, Metalness = 0,
    },
    NocturnaWetConcrete = {
        BaseMaterial = "Concrete", StudsPerTile = 12, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(89, 87, 81),
        Color = 125001835297678, Normal = 140702473517480, Roughness = 128334651781701, Metalness = 0,
    },
    NocturnaStainedConcrete = {
        BaseMaterial = "Concrete", StudsPerTile = 12, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(104, 100, 92),
        Color = 76811597972832, Normal = 71678841120169, Roughness = 82455481645879, Metalness = 0,
    },
    NocturnaPeelingPlaster = {
        BaseMaterial = "Plaster", StudsPerTile = 10, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(128, 140, 121),
        Color = 72705602825394, Normal = 96880619696942, Roughness = 108909095235477, Metalness = 0,
    },
    NocturnaDirtyTiles = {
        BaseMaterial = "CeramicTiles", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(146, 143, 130),
        Color = 108909992635695, Normal = 107893304959124, Roughness = 71131875048737, Metalness = 0,
    },
    NocturnaStainedPlaster = {
        BaseMaterial = "Plaster", StudsPerTile = 10, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(171, 163, 145),
        Color = 71599657425870, Normal = 140160376971291, Roughness = 92946102615219, Metalness = 0,
    },
    NocturnaFleshWall = {
        BaseMaterial = "Pebble", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(101, 62, 53),
        Color = 108353415000971, Normal = 96093031651746, Roughness = 97113485542318, Metalness = 0,
    },
    NocturnaStainedSlate = {
        BaseMaterial = "Slate", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(51, 53, 46),
        Color = 115909867396741, Normal = 74585257290861, Roughness = 137690940375819, Metalness = 0,
    },
    NocturnaFleshCeiling = {
        BaseMaterial = "Slate", StudsPerTile = 8, Pattern = "Organic", Tint = WHITE,
        Mean = Color3.fromRGB(85, 34, 38),
        Color = 81493325488739, Normal = 113003152442506, Roughness = 92962746358189, Metalness = 0,
    },
    NocturnaScratchedSteel = {
        BaseMaterial = "Metal", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(71, 76, 82),
        Color = 122742281460641, Normal = 108213306906049, Roughness = 105849911253470, Metalness = 140121161397226,
    },
    NocturnaWornPlate = {
        BaseMaterial = "DiamondPlate", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(79, 80, 81),
        Color = 89158576000002, Normal = 107764431844756, Roughness = 104473178254774, Metalness = 73378791712108,
    },
    NocturnaTornWallpaper = {
        BaseMaterial = "Fabric", StudsPerTile = 6, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(147, 128, 107),
        Color = 119287965015417, Normal = 140660690026426, Roughness = 94406534323600, Metalness = 0,
    },
    NocturnaScuffedOak = {
        BaseMaterial = "WoodPlanks", StudsPerTile = 8, Pattern = "Regular", Tint = WHITE,
        Mean = Color3.fromRGB(111, 81, 51),
        Color = 132501673884844, Normal = 126282891581890, Roughness = 95003942156316, Metalness = 0,
    },

    -- Utilería y puertas (casi neutras: las tiñe el color de cada pieza) -------------
    NocturnaRottenWood = {
        BaseMaterial = "Wood", StudsPerTile = 4, Pattern = "Regular",
        Mean = Color3.fromRGB(191, 180, 160),
        Color = 129555526954530, Normal = 103604085558918, Roughness = 78005751941068, Metalness = 0,
    },
    NocturnaRustedSheet = {
        BaseMaterial = "CorrodedMetal", StudsPerTile = 6, Pattern = "Regular",
        Mean = Color3.fromRGB(179, 177, 171),
        Color = 74259547594346, Normal = 102804596588842, Roughness = 129626375772633, Metalness = 100682214566235,
    },
    NocturnaGrimyMetal = {
        BaseMaterial = "Metal", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(193, 194, 193),
        Color = 102184257351092, Normal = 97139330641258, Roughness = 97859927358231, Metalness = 72481891725341,
    },
    NocturnaWornFabric = {
        BaseMaterial = "Fabric", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(177, 169, 157),
        Color = 137756609099709, Normal = 120924771613323, Roughness = 101354594010261, Metalness = 0,
    },
    NocturnaBookCloth = {
        BaseMaterial = "Leather", StudsPerTile = 2, Pattern = "Organic",
        Mean = Color3.fromRGB(172, 160, 144),
        Color = 94476153760511, Normal = 135972455748559, Roughness = 96894773398065, Metalness = 0,
    },
    NocturnaDirtyGlass = {
        BaseMaterial = "Glass", StudsPerTile = 4, Pattern = "Organic",
        Mean = Color3.fromRGB(233, 233, 229),
        Color = 126028710520638, Normal = 93542032078421, Roughness = 131959079529715, Metalness = 0,
    },
    NocturnaAgedPaper = {
        BaseMaterial = "Cardboard", StudsPerTile = 2, Pattern = "Organic",
        Mean = Color3.fromRGB(208, 199, 175),
        Color = 106178313079830, Normal = 90250730320676, Roughness = 103371930648136, Metalness = 0,
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
