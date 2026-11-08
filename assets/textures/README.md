# Texturas PBR propias (todavía no existen)

**Estado actual:** NOCTURNA no tiene ninguna textura propia subida a Roblox. Todas
las paredes, pisos, techos, muebles, puertas y daños usan los **materiales que trae
Roblox** (Brick, Concrete, Plaster, Fabric, WoodPlanks, CorrodedMetal, DiamondPlate,
Slate, Leather, Glass, etc.), con capas de color, geometría (zarpazos tallados en
cuña, grietas, descascarado, charcos de tres capas), reflectancia y luz. No hay
mapas de color, normales, rugosidad ni metalicidad hechos para el juego.

El juego ya está preparado para usarlos: cuando existan, se enchufan **sin tocar
código**.

## Cómo se enchufan

1. Conseguí o pintá los mapas de la tabla (PNG, potencia de 2, sin compresión con
   pérdida para normal/rugosidad/metal).
2. Subilos a Roblox (Creator Hub → Development Items → Images, o el Asset Manager
   de Studio). Cada mapa queda con un `rbxassetid://...`.
3. En Studio, dentro de **MaterialService**, creá un `MaterialVariant` por fila con
   **exactamente el nombre de la tabla**, elegí su `BaseMaterial` y cargá
   `ColorMap`, `NormalMap`, `RoughnessMap` y `MetalnessMap` con esos ids. Ajustá
   `StudsPerTile` (sugerido abajo).
4. Guardá el lugar. `PropKit.Surface` (en `src/server/World/PropKit.lua`) busca el
   nombre que pide `ThemeConfig.<Tema>.Surfaces` al armar cada capítulo; si lo
   encuentra, la pieza usa ese `MaterialVariant`. Si no está, sigue con el material
   de Roblox de siempre.

`default.project.json` deja `MaterialService.Use2022Materials = true` para que los
materiales de Roblox sean los realistas de 2022 aunque el lugar sea viejo.

## Mapas que faltan

Resolución sugerida: **1024 × 1024** (512 alcanza en celulares; Roblox baja la
resolución sola según el equipo). Cada fila necesita los cuatro mapas:
`_color` (sRGB), `_normal` (OpenGL, Y+), `_roughness` y `_metalness` (lineales,
escala de grises).

| MaterialVariant          | Superficie                         | Capítulo | BaseMaterial  | StudsPerTile | Qué tiene que mostrar |
|--------------------------|------------------------------------|----------|---------------|--------------|-----------------------|
| `NocturnaTunnelBrick`    | Paredes y bloques de pasillo       | 1 Túneles | Brick        | 8            | Ladrillo húmedo, juntas con salitre, hollín abajo |
| `NocturnaWetConcrete`    | Piso                               | 1 Túneles | Concrete     | 12           | Hormigón gastado, partes mojadas (rugosidad baja en manchas) |
| `NocturnaStainedConcrete`| Techo                              | 1 y 4    | Concrete      | 12           | Hormigón con manchas de goteras y óxido |
| `NocturnaPeelingPlaster` | Paredes                            | 2 Oficinas | Plaster     | 10           | Pintura verde clínica descascarada, revoque abajo |
| `NocturnaDirtyTiles`     | Piso                               | 2 Oficinas | CeramicTiles | 6            | Baldosas con juntas negras, algunas rajadas |
| `NocturnaStainedPlaster` | Techo                              | 2 y 5    | Plaster       | 10           | Cielorraso con aureolas de humedad |
| `NocturnaFleshWall`      | Paredes                            | 3 Organismo | Pebble      | 6            | Tejido orgánico húmedo sobre azulejo (rugosidad baja, normal marcada) |
| `NocturnaStainedSlate`   | Piso                               | 3 Organismo | Slate       | 8            | Piso de laboratorio con fluidos secos |
| `NocturnaFleshCeiling`   | Techo                              | 3 Organismo | Slate       | 8            | Membrana con venas oscuras |
| `NocturnaScratchedSteel` | Paredes                            | 4 Archivo | Metal         | 8            | Paneles de chapa pintada con rayones y óxido en bordes (metalness alta) |
| `NocturnaWornPlate`      | Piso                               | 4 Archivo | DiamondPlate  | 6            | Chapa semillada gastada en el centro |
| `NocturnaTornWallpaper`  | Paredes                            | 5 Recuerdo | Fabric      | 6            | Empapelado floral desteñido, arrancado en partes |
| `NocturnaScuffedOak`     | Piso                               | 5 Recuerdo | WoodPlanks  | 8            | Parquet de roble con marcas y polvo en las juntas |

Opcionales (no los pide el código todavía, pero mejorarían mucho el detalle si se
agrega una clave más a `Surfaces` y se aplica con `PropKit.Surface`):

| Nombre sugerido        | Superficie                         | Notas |
|------------------------|------------------------------------|-------|
| `NocturnaBookCloth`    | Lomos de libros y carpetas         | Tela/cuero gastado, 512² |
| `NocturnaRustedSheet`  | Puertas de cortina, barriles       | Óxido con pintura saltada, 1024² |
| `NocturnaDirtyGlass`   | Vidrios de puertas, tanques        | Sólo `ColorMap` con alfa de mugre + rugosidad |

## Licencias

- Usá sólo mapas **propios** o con licencia que permita uso comercial **sin
  atribución obligatoria dentro del juego** (por ejemplo CC0: ambientCG,
  Poly Haven, TextureCan). Anotá la fuente de cada mapa en esta carpeta
  (`fuentes.txt`) antes de subirlo.
- No uses texturas "free" de sitios sin licencia clara ni capturas de otros juegos.
- Lo que se sube a Roblox pasa por su moderación: evitá sangre demasiado explícita
  en los `ColorMap` (la sangre del juego es geometría oscura, no una foto).

## Lo que NO necesita texturas

Los zarpazos, grietas, descascarado, humedad, moho, sangre, charcos, polvo, haces
de luz y las puertas temáticas ya están hechos con geometría, materiales de Roblox,
partículas con texturas que vienen con el cliente (`rbxasset://textures/particles/...`)
y luz. Las texturas PBR sólo suben el detalle fino de las superficies grandes.
