# NOCTURNA — cierre de desarrollo y publicación

Este documento separa lo que está en el repositorio de lo que aún requiere contenido o ejecución real en Roblox Studio.

## Qué hay en la rama main

- Proyecto Rojo con mapeo de Shared, Server, Client y tests.
- Configuración de juego, capítulos, objetos y mapa.
- Generador procedural de laberinto/sectores.
- Servicios iniciales de historia, inventario, puertas, interacción y guardado.
- IA base de monstruos, detección de ruido y efectos.
- Cámara en primera persona, linterna y controles táctiles iniciales.
- Compatibilidad del servidor para los dos nombres de evento de ruido: `PlayerNoise` y `NoiseEvent`.

## Bloqueadores de publicación

### 1. Contenido del juego
- Modelos finales de los cinco monstruos, con Humanoid y HumanoidRootPart.
- Modelos, texturas, animaciones, audio y efectos propios.
- Mapa narrativo diseñado; el generador actual crea una base procedural, no los cinco capítulos terminados.
- Colocar y etiquetar objetivos con `NocturnaObjective` y el atributo `ObjectiveId` que corresponda a ChapterConfig.
- Colocar puertas con tag `NocturnaDoor`; para cerraduras, definir `RequiredItem`.

### 2. Cliente e interfaz
- Confirmar que existe y se crea `PlayerGui.NocturnaHUD` antes de que los scripts móviles lo esperen.
- Completar HUD de objetivos, diálogo, inventario, salud, batería y avisos.
- Confirmar que cada control táctil tenga un botón visible y que no se superponga con controles Roblox.
- Verificar que la linterna no tenga dos controladores activos.

### 3. Servidor y cooperativo
- Auditar que cada RemoteEvent tenga el mismo nombre y contrato en cliente y servidor.
- Validar todas las peticiones del cliente en servidor; nunca confiar en posiciones, daño, objetos o progreso enviados por el cliente.
- Decidir si el progreso de capítulo es compartido por toda la partida o individual.
- Probar la carga/guardado de DataStore con API Services habilitado en una experiencia publicada de prueba.
- Probar entrada, salida, muerte, respawn y reconexión de 2 a 4 jugadores.

### 4. IA
- El Oyente: probar audición, distancia, enfriamiento y pérdida del rastro.
- El Imitador: reemplazar el efecto de llamada provisional por audio espacial real y señuelos funcionales.
- El Quieto: probar congelación sólo cuando un jugador lo mira y reanudación al perder contacto visual.
- El Trepador: implementar desplazamiento real por paredes/techos; la configuración actual no lo demuestra.
- El Coloso: implementar eventos ambientales reales, no sólo avisos visuales al cliente.

## Orden recomendado para cerrar

1. Abrir el proyecto en Roblox Studio con Rojo y resolver errores de Output.
2. Confirmar estructura y remotos con una partida local de un jugador.
3. Completar HUD y recoger/usar objetos; probar puertas y objetivos.
4. Añadir los cinco modelos y validar navegación/ataques de IA.
5. Probar dos y cuatro clientes en servidor local.
6. Probar móvil real o emulación táctil y optimizar.
7. Activar DataStore en experiencia de prueba, reiniciar servidor y verificar persistencia.
8. Revisar permisos, privacidad, miniatura, icono, descripción y configuración de publicación.
9. Publicar primero una versión privada/beta; abrir al público sólo tras superar las pruebas.

## Verificación realizada desde GitHub

Se inspeccionaron archivos fuente y configuración de la rama main y se corrigió la compatibilidad del evento de ruido en `MonsterSignals.server.lua`. No se ejecutó Roblox Studio, no se compiló el proyecto con Rojo y no se realizó una sesión multijugador. Por ello no se afirma que el juego esté terminado ni que esté libre de errores.
