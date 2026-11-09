# Subir las texturas a Roblox y pegar los números

Las imágenes de esta carpeta las hornea `assets/blender/bake_textures.py` (ver
`README.md`). Para que el juego las use no hace falta tocar nada en Studio:

1. Subí cada PNG de la tabla (Creator Hub → Development Items → Decals/Images, o el
   **Asset Manager** de Studio → *Bulk Import*, que acepta varios a la vez).
   Usá el nombre del archivo como nombre del asset.
2. Copiá el número del asset (el de `rbxassetid://NÚMERO`; si Roblox te da el id
   de un *Decal*, abrilo en Studio y usá el id de su *Image*, que es otro número).
3. Pegalo en `src/shared/Config/TextureAssets.lua`, en el campo de la columna
   **Dónde pegar** (por ejemplo `NocturnaTunnelBrick.Color = 0` →
   `NocturnaTunnelBrick.Color = 1234567890`).
4. Publicá. Al cargar cada capítulo el servidor crea los `MaterialVariant` en
   `MaterialService` (sólo los que ya tienen su `Color`) y los aplica a paredes,
   pisos, techos, muebles, utilería y puertas. Con un número en 0 ese mapa no se
   usa; si `Color` está en 0 la superficie sigue con el material de Roblox.

Los mapas `_Metalness` sólo existen para los materiales con metal; los demás no
llevan mapa de metalicidad (Roblox los toma como no metálicos) y su campo
`Metalness` queda en 0.

| Archivo | Dónde pegar (`TextureAssets.Variants.…`) | Uso |
|---------|-------------------------------------------|-----|
| `NocturnaTunnelBrick/NocturnaTunnelBrick_Color.png` | `NocturnaTunnelBrick.Color` | Paredes cap. 1 |
| `NocturnaTunnelBrick/NocturnaTunnelBrick_Normal.png` | `NocturnaTunnelBrick.Normal` | Paredes cap. 1 |
| `NocturnaTunnelBrick/NocturnaTunnelBrick_Roughness.png` | `NocturnaTunnelBrick.Roughness` | Paredes cap. 1 |
| `NocturnaWetConcrete/NocturnaWetConcrete_Color.png` | `NocturnaWetConcrete.Color` | Piso cap. 1 |
| `NocturnaWetConcrete/NocturnaWetConcrete_Normal.png` | `NocturnaWetConcrete.Normal` | Piso cap. 1 |
| `NocturnaWetConcrete/NocturnaWetConcrete_Roughness.png` | `NocturnaWetConcrete.Roughness` | Piso cap. 1 |
| `NocturnaStainedConcrete/NocturnaStainedConcrete_Color.png` | `NocturnaStainedConcrete.Color` | Techo cap. 1 y 4 |
| `NocturnaStainedConcrete/NocturnaStainedConcrete_Normal.png` | `NocturnaStainedConcrete.Normal` | Techo cap. 1 y 4 |
| `NocturnaStainedConcrete/NocturnaStainedConcrete_Roughness.png` | `NocturnaStainedConcrete.Roughness` | Techo cap. 1 y 4 |
| `NocturnaPeelingPlaster/NocturnaPeelingPlaster_Color.png` | `NocturnaPeelingPlaster.Color` | Paredes cap. 2 |
| `NocturnaPeelingPlaster/NocturnaPeelingPlaster_Normal.png` | `NocturnaPeelingPlaster.Normal` | Paredes cap. 2 |
| `NocturnaPeelingPlaster/NocturnaPeelingPlaster_Roughness.png` | `NocturnaPeelingPlaster.Roughness` | Paredes cap. 2 |
| `NocturnaDirtyTiles/NocturnaDirtyTiles_Color.png` | `NocturnaDirtyTiles.Color` | Piso cap. 2 |
| `NocturnaDirtyTiles/NocturnaDirtyTiles_Normal.png` | `NocturnaDirtyTiles.Normal` | Piso cap. 2 |
| `NocturnaDirtyTiles/NocturnaDirtyTiles_Roughness.png` | `NocturnaDirtyTiles.Roughness` | Piso cap. 2 |
| `NocturnaStainedPlaster/NocturnaStainedPlaster_Color.png` | `NocturnaStainedPlaster.Color` | Techo cap. 2 y 5 |
| `NocturnaStainedPlaster/NocturnaStainedPlaster_Normal.png` | `NocturnaStainedPlaster.Normal` | Techo cap. 2 y 5 |
| `NocturnaStainedPlaster/NocturnaStainedPlaster_Roughness.png` | `NocturnaStainedPlaster.Roughness` | Techo cap. 2 y 5 |
| `NocturnaFleshWall/NocturnaFleshWall_Color.png` | `NocturnaFleshWall.Color` | Paredes cap. 3 |
| `NocturnaFleshWall/NocturnaFleshWall_Normal.png` | `NocturnaFleshWall.Normal` | Paredes cap. 3 |
| `NocturnaFleshWall/NocturnaFleshWall_Roughness.png` | `NocturnaFleshWall.Roughness` | Paredes cap. 3 |
| `NocturnaStainedSlate/NocturnaStainedSlate_Color.png` | `NocturnaStainedSlate.Color` | Piso cap. 3 |
| `NocturnaStainedSlate/NocturnaStainedSlate_Normal.png` | `NocturnaStainedSlate.Normal` | Piso cap. 3 |
| `NocturnaStainedSlate/NocturnaStainedSlate_Roughness.png` | `NocturnaStainedSlate.Roughness` | Piso cap. 3 |
| `NocturnaFleshCeiling/NocturnaFleshCeiling_Color.png` | `NocturnaFleshCeiling.Color` | Techo cap. 3 |
| `NocturnaFleshCeiling/NocturnaFleshCeiling_Normal.png` | `NocturnaFleshCeiling.Normal` | Techo cap. 3 |
| `NocturnaFleshCeiling/NocturnaFleshCeiling_Roughness.png` | `NocturnaFleshCeiling.Roughness` | Techo cap. 3 |
| `NocturnaScratchedSteel/NocturnaScratchedSteel_Color.png` | `NocturnaScratchedSteel.Color` | Paredes cap. 4 |
| `NocturnaScratchedSteel/NocturnaScratchedSteel_Normal.png` | `NocturnaScratchedSteel.Normal` | Paredes cap. 4 |
| `NocturnaScratchedSteel/NocturnaScratchedSteel_Roughness.png` | `NocturnaScratchedSteel.Roughness` | Paredes cap. 4 |
| `NocturnaScratchedSteel/NocturnaScratchedSteel_Metalness.png` | `NocturnaScratchedSteel.Metalness` | Paredes cap. 4 |
| `NocturnaWornPlate/NocturnaWornPlate_Color.png` | `NocturnaWornPlate.Color` | Piso cap. 4, puertas bóveda |
| `NocturnaWornPlate/NocturnaWornPlate_Normal.png` | `NocturnaWornPlate.Normal` | Piso cap. 4, puertas bóveda |
| `NocturnaWornPlate/NocturnaWornPlate_Roughness.png` | `NocturnaWornPlate.Roughness` | Piso cap. 4, puertas bóveda |
| `NocturnaWornPlate/NocturnaWornPlate_Metalness.png` | `NocturnaWornPlate.Metalness` | Piso cap. 4, puertas bóveda |
| `NocturnaTornWallpaper/NocturnaTornWallpaper_Color.png` | `NocturnaTornWallpaper.Color` | Paredes cap. 5 |
| `NocturnaTornWallpaper/NocturnaTornWallpaper_Normal.png` | `NocturnaTornWallpaper.Normal` | Paredes cap. 5 |
| `NocturnaTornWallpaper/NocturnaTornWallpaper_Roughness.png` | `NocturnaTornWallpaper.Roughness` | Paredes cap. 5 |
| `NocturnaScuffedOak/NocturnaScuffedOak_Color.png` | `NocturnaScuffedOak.Color` | Piso cap. 5 |
| `NocturnaScuffedOak/NocturnaScuffedOak_Normal.png` | `NocturnaScuffedOak.Normal` | Piso cap. 5 |
| `NocturnaScuffedOak/NocturnaScuffedOak_Roughness.png` | `NocturnaScuffedOak.Roughness` | Piso cap. 5 |
| `NocturnaRottenWood/NocturnaRottenWood_Color.png` | `NocturnaRottenWood.Color` | Muebles y puertas de madera |
| `NocturnaRottenWood/NocturnaRottenWood_Normal.png` | `NocturnaRottenWood.Normal` | Muebles y puertas de madera |
| `NocturnaRottenWood/NocturnaRottenWood_Roughness.png` | `NocturnaRottenWood.Roughness` | Muebles y puertas de madera |
| `NocturnaRustedSheet/NocturnaRustedSheet_Color.png` | `NocturnaRustedSheet.Color` | Cortinas, barriles (CorrodedMetal) |
| `NocturnaRustedSheet/NocturnaRustedSheet_Normal.png` | `NocturnaRustedSheet.Normal` | Cortinas, barriles (CorrodedMetal) |
| `NocturnaRustedSheet/NocturnaRustedSheet_Roughness.png` | `NocturnaRustedSheet.Roughness` | Cortinas, barriles (CorrodedMetal) |
| `NocturnaRustedSheet/NocturnaRustedSheet_Metalness.png` | `NocturnaRustedSheet.Metalness` | Cortinas, barriles (CorrodedMetal) |
| `NocturnaGrimyMetal/NocturnaGrimyMetal_Color.png` | `NocturnaGrimyMetal.Color` | Utilería de metal, esclusas |
| `NocturnaGrimyMetal/NocturnaGrimyMetal_Normal.png` | `NocturnaGrimyMetal.Normal` | Utilería de metal, esclusas |
| `NocturnaGrimyMetal/NocturnaGrimyMetal_Roughness.png` | `NocturnaGrimyMetal.Roughness` | Utilería de metal, esclusas |
| `NocturnaGrimyMetal/NocturnaGrimyMetal_Metalness.png` | `NocturnaGrimyMetal.Metalness` | Utilería de metal, esclusas |
| `NocturnaWornFabric/NocturnaWornFabric_Color.png` | `NocturnaWornFabric.Color` | Sillones, camas, telas |
| `NocturnaWornFabric/NocturnaWornFabric_Normal.png` | `NocturnaWornFabric.Normal` | Sillones, camas, telas |
| `NocturnaWornFabric/NocturnaWornFabric_Roughness.png` | `NocturnaWornFabric.Roughness` | Sillones, camas, telas |
| `NocturnaBookCloth/NocturnaBookCloth_Color.png` | `NocturnaBookCloth.Color` | Lomos de libros, cuero |
| `NocturnaBookCloth/NocturnaBookCloth_Normal.png` | `NocturnaBookCloth.Normal` | Lomos de libros, cuero |
| `NocturnaBookCloth/NocturnaBookCloth_Roughness.png` | `NocturnaBookCloth.Roughness` | Lomos de libros, cuero |
| `NocturnaDirtyGlass/NocturnaDirtyGlass_Color.png` | `NocturnaDirtyGlass.Color` | Vidrios |
| `NocturnaDirtyGlass/NocturnaDirtyGlass_Normal.png` | `NocturnaDirtyGlass.Normal` | Vidrios |
| `NocturnaDirtyGlass/NocturnaDirtyGlass_Roughness.png` | `NocturnaDirtyGlass.Roughness` | Vidrios |
| `NocturnaAgedPaper/NocturnaAgedPaper_Color.png` | `NocturnaAgedPaper.Color` | Papeles, cajas, carpetas |
| `NocturnaAgedPaper/NocturnaAgedPaper_Normal.png` | `NocturnaAgedPaper.Normal` | Papeles, cajas, carpetas |
| `NocturnaAgedPaper/NocturnaAgedPaper_Roughness.png` | `NocturnaAgedPaper.Roughness` | Papeles, cajas, carpetas |
