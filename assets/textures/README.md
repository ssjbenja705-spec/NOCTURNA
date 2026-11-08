# Texturas PBR propias

NOCTURNA tiene sus propias texturas PBR, hechas **proceduralmente en Blender**
(nada bajado de internet, sin licencias de terceros): `assets/blender/bake_textures.py`
arma cada material con nodos (ruido fractal, voronoi, ruido "ridged", ladrillos,
baldosas y tablas hechos con matemática de UV; desgaste en bordes, mugre,
manchas de humedad, grietas, óxido) y los hornea con Cycles.

`preview.png` es la hoja de muestra: cada textura repetida 2×2 (así se ve que no
tiene costuras) con luz rasante.

**Para que el juego las use hay que subirlas a Roblox y pegar los números:** ver
[`UPLOAD.md`](UPLOAD.md). Mientras los números estén en 0 todo sigue con los
materiales de Roblox de siempre.

## Cómo se usan

- `src/shared/Config/TextureAssets.lua`: una fila por textura con su
  `BaseMaterial`, `StudsPerTile`, patrón y el número de cada mapa (0 = sin subir).
- `src/server/World/MaterialLibrary.lua`: al cargar cada capítulo crea en
  `MaterialService` un `MaterialVariant` por fila que ya tenga su `Color` (no hace
  falta ningún paso en Studio). Si alguien vuelve un número a 0, la variante se
  borra. Una variante hecha a mano en Studio con el mismo nombre tiene prioridad.
- `ThemeConfig.<Tema>.Surfaces`: qué textura usa cada capítulo.
  - `Wall`, `Floor`, `Ceiling`: paredes, pisos y techos (`PropKit.Surface`). Estas
    texturas traen su propio color: la pieza pasa a blanco (con la misma variación
    de brillo entre salas) para que se vean tal cual.
  - `Wood`, `Metal`, `Rust`, `Plate`, `Fabric`, `Leather`, `Paper`, `Glass`: muebles,
    utilería, escondites y puertas según su material de Roblox
    (`TextureAssets.PropMaterials`, aplicado por `PropKit.SurfaceProps` al final de
    `WorldService.LoadChapter`). Estas son casi neutras: el color de cada pieza
    las tiñe y se divide por el color medio de la textura (`Mean`) para que nada
    se oscurezca. Los daños (`Weathering`), luces y mallas con textura propia no
    se tocan.

`default.project.json` deja `MaterialService.Use2022Materials = true`.

## Texturas

Todas de 1024 × 1024, enroscables sin costura. `_Color` es sRGB; `_Normal` es
tangente **OpenGL (Y+, verde hacia arriba)**, el formato de Roblox; `_Roughness` y
`_Metalness` son lineales en gris.

| MaterialVariant          | Superficie                         | Capítulo | BaseMaterial  | StudsPerTile | Qué muestra |
|--------------------------|------------------------------------|----------|---------------|--------------|-------------|
| `NocturnaTunnelBrick`    | Paredes y bloques de pasillo       | 1 Túneles | Brick        | 8            | Ladrillo húmedo con cantos astillados, juntas con salitre, hollín y chorreaduras mojadas |
| `NocturnaWetConcrete`    | Piso                               | 1 Túneles | Concrete     | 12           | Hormigón gastado con áridos, grietas, manchas de aceite y partes mojadas casi espejadas |
| `NocturnaStainedConcrete`| Techo                              | 1 y 4    | Concrete      | 12           | Hormigón de encofrado con aureolas de goteras y chorreaduras de óxido |
| `NocturnaPeelingPlaster` | Paredes                            | 2 Oficinas | Plaster     | 10           | Pintura verde clínica descascarada (borde levantado), revoque abajo, grietas |
| `NocturnaDirtyTiles`     | Piso                               | 2 Oficinas | CeramicTiles | 6            | Baldosas con juntas negras, mugre en los bordes, algunas rajadas |
| `NocturnaStainedPlaster` | Techo                              | 2 y 5    | Plaster       | 10           | Cielorraso con aureolas de humedad y moho |
| `NocturnaFleshWall`      | Paredes                            | 3 Organismo | Pebble      | 6            | Tejido húmedo con venas creciendo sobre azulejo sucio |
| `NocturnaStainedSlate`   | Piso                               | 3 Organismo | Slate       | 8            | Pizarra de laboratorio con fluidos secos y rayones |
| `NocturnaFleshCeiling`   | Techo                              | 3 Organismo | Slate       | 8            | Membrana con venas oscuras en varias escalas |
| `NocturnaScratchedSteel` | Paredes                            | 4 Archivo | Metal         | 8            | Paneles de chapa pintada con remaches, rayones al metal y óxido en los bordes |
| `NocturnaWornPlate`      | Piso                               | 4 Archivo | DiamondPlate  | 6            | Chapa semillada gastada en los relieves, mugre en los valles y óxido |
| `NocturnaTornWallpaper`  | Paredes                            | 5 Recuerdo | Fabric      | 6            | Empapelado floral desteñido, arrancado en partes con humedad |
| `NocturnaScuffedOak`     | Piso                               | 5 Recuerdo | WoodPlanks  | 8            | Parquet de roble con marcas, desgaste y polvo en las juntas |
| `NocturnaRottenWood`     | Muebles y puertas de madera        | todos    | Wood          | 4            | Madera con veta, rajaduras, podrida y con moho (neutra, se tiñe) |
| `NocturnaRustedSheet`    | Cortinas, barriles                 | todos    | CorrodedMetal | 6            | Chapa ondulada con pintura saltada y óxido |
| `NocturnaGrimyMetal`     | Utilería de metal, esclusas        | todos    | Metal         | 4            | Metal cepillado con rayones, huellas, abolladuras y mugre |
| `NocturnaWornFabric`     | Sillones, camas, cortinas          | todos    | Fabric        | 4            | Tela tejida gastada con manchas |
| `NocturnaBookCloth`      | Lomos de libros, cuero             | todos    | Leather       | 2            | Cuero cuarteado con roces |
| `NocturnaDirtyGlass`     | Vidrios                            | todos    | Glass         | 4            | Vidrio con manchas y chorreaduras (rugosidad) |
| `NocturnaAgedPaper`      | Papeles, cajas, carpetas           | todos    | Cardboard     | 2            | Papel viejo con manchas de óxido, marcas de humedad y dobleces |

`stats.json` guarda, por textura, el color medio, la rugosidad y metalicidad
medias y el salto en el borde del mosaico (≈1 o menos = sin costura).

## Volver a hornear

```bash
blender -b --factory-startup -P assets/blender/bake_textures.py -- --out C:/tmp/ntx --preview
blender -b --factory-startup -P assets/blender/bake_textures.py -- --out C:/tmp/ntx NocturnaTunnelBrick
```

En Windows usá una carpeta de salida corta (`--out`) y copiá el resultado acá:
la ruta del repositorio puede pasar el límite de 260 caracteres. Si cambia el
color medio de una textura de utilería, copiá el `Mean` de `stats.json` a
`TextureAssets.lua`. Al volver a subir una imagen cambia su número: hay que
pegarlo otra vez.

## Notas

- Lo que se sube a Roblox pasa por su moderación: los `_Color` no tienen sangre
  explícita (el tejido orgánico es carne oscura y venas, sin charcos rojos).
- Si Roblox no aceptara alguna variante (por ejemplo vidrio), el servidor la
  salta con un aviso y esa pieza sigue con su material de Roblox.
- Los zarpazos, grietas, descascarado, humedad, sangre, charcos, polvo y haces de
  luz siguen siendo geometría y partículas: las texturas suben el detalle fino de
  las superficies grandes.
