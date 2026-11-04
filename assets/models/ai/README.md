# Criaturas realistas generadas con IA

Los modelos se generan en [Meshy](https://www.meshy.ai) con tu cuenta. El plan
gratis da 100 créditos por mes y licencia CC BY 4.0, que permite uso comercial
dando crédito a Meshy. Después el script `assets/blender/prepare_ai_models.py`
los deja listos para Roblox.

## 1. Generar en Meshy

En **Text to 3D**, para cada criatura:

| Opción | Valor |
|---|---|
| Modelo | **Meshy 6 Lite**: el plan gratis sólo deja descargar los modelos de esta versión |
| Simetría | Activada (salvo en El Trepador, si no sale bien) |
| Pose | De pie, normal; **no** en T: los brazos tienen que colgar a los costados |
| Textura | Activada, PBR si aparece la opción |
| Polígonos | Lo que venga por defecto; el script los reduce |

Cada criatura gasta unos 20 créditos (10 de forma y 10 de textura), así que las
cinco usan los 100 del mes. Si alguna sale mal, se puede repetir en
[Tripo](https://www.tripo3d.ai) con el mismo texto.

Los textos van en inglés porque los generadores responden mejor así.

### ElOyente — ciego, se guía por el ruido

```text
Photorealistic horror creature, full body, standing upright. Gaunt emaciated humanoid, pale grey cracked skin stretched over visible ribs and spine. Eyeless smooth elongated head with a wide lipless mouth full of thin teeth. Two huge bat-like ears with veined translucent membranes. Very long thin arms hanging down past the knees, three long clawed fingers. Thin digitigrade legs. Slightly hunched. Symmetrical, neutral pose, no clothes, no base.
```

### ElImitador — imita voces

```text
Photorealistic horror creature, full body, standing upright. Tall thin humanoid shadow made of matted wet black fur and torn black skin. Featureless black head with a vertical split jaw opening into a red glistening mouth lined with needle teeth. Long arms hanging at its sides with four elongated black fingers. Symmetrical, neutral pose, no base.
```

### ElQuieto — maniquí que se mueve en la oscuridad

```text
Photorealistic old department store mannequin, full body, standing upright. Cracked off-white plastic with yellowed stains, dirt and chipped paint. Smooth faceless egg-shaped head with two small black hollow eye holes. Visible joint seams at shoulders, elbows, hips and knees. Arms hanging straight at its sides. Unsettling, symmetrical, no clothes, no base.
```

### ElTrepador — anda por el techo

```text
Photorealistic horror creature, full body. Large spider-like creature made of raw skinless flesh, six long jointed legs spread wide. Dark crimson body with exposed muscle and veins, segmented abdomen with bone spikes along the back. Small head with two glowing yellow eyes and sharp mandibles. Symmetrical, seen from above it is wide and flat, no base.
```

### ElColoso — enorme, rompe puertas

```text
Photorealistic horror creature, full body, standing. Massive hulking titan like a giant gorilla. Dark grey scarred hide with thick rusted iron armor plates fused into its back and shoulders. Small head sunk between the shoulders with two glowing orange eyes and broken horns. Enormous long arms with huge knuckles hanging at its sides, short thick legs. Symmetrical, neutral pose, no base.
```

## 2. Descargar

Bajá cada modelo en formato **GLB** y guardalo en esta carpeta con el nombre exacto:

```text
assets/models/ai/ElOyente.glb
assets/models/ai/ElImitador.glb
assets/models/ai/ElQuieto.glb
assets/models/ai/ElTrepador.glb
assets/models/ai/ElColoso.glb
```

También sirven `.fbx` u `.obj` con el mismo nombre.

## 3. Preparar para Roblox

```bash
blender --background --factory-startup --python assets/blender/prepare_ai_models.py -- assets/models
```

Por cada criatura que encuentre:

- Reduce la malla a 18.000 triángulos como máximo y las texturas a 1024 px, los
  límites de Roblox.
- La pone a la escala de la criatura del juego, con los pies en el piso.
- La corta en las mismas piezas que anima el juego (torso, cabeza, brazos,
  piernas...). Cada corte va a la pieza más cercana, así se siguen moviendo las
  extremidades.
- Escribe `fbx/<Criatura>_AI.fbx` con las texturas adentro, una vista previa en
  `previews/<Criatura>_AI.png` y las medidas en
  `src/server/Monsters/CreatureMeshes.lua`.

## 4. Importar en Studio

Igual que los otros modelos (`assets/models/README.md`), pero con el archivo
`fbx/<Criatura>_AI.fbx`. El modelo importado va en
`ServerStorage/NocturnaModels/<Criatura>` y reemplaza al anterior. El juego
reconoce las piezas cortadas (`Torso1`, `Arm1`, `Arm2`...) y usa sus medidas
reales en lugar de estirarlas. Con un modelo realista importado, los ojos de neón
de la versión simple ya no se agregan.

**Si el importador no aplica las texturas**, agregá una sola
**SurfaceAppearance** dentro de `NocturnaModels/<Criatura>` y cargale los cuatro
mapas de `assets/models/ai_textures/<Criatura>/`:

| Propiedad | Archivo |
|---|---|
| ColorMap | `<Criatura>_Color.png` |
| NormalMap | `<Criatura>_Normal.png` |
| RoughnessMap | `<Criatura>_Roughness.png` |
| MetalnessMap | `<Criatura>_Metalness.png` |

El juego la copia a todas las piezas de esa criatura.

Al cortar el modelo puede verse una costura donde se separan las piezas cuando
se mueven las extremidades. Si molesta en alguna criatura, se puede reducir el
balanceo (`SwingAmount`) de esa pieza en `MonsterFactory`.

## Crédito obligatorio

Con el plan gratis hay que dar crédito, por ejemplo en la descripción de la
experiencia: *"Modelos de criaturas creados con Meshy (CC BY 4.0)"*.
