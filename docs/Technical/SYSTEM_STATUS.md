# Estado de los sistemas — 6 de noviembre de 2026

Leyenda de verificación:
- **Simulado**: probado con `tests/lune` (motor simulado; valida propiedades y
  clases contra la base de reflexión de Roblox, sin física ni render).
- **Studio**: probado en Roblox Studio 0.745 con `tests/Studio/SmokeTest`.
- **Pendiente**: requiere probarse a mano en Studio o en dispositivos.

| Sistema | Módulos | Verificación |
|---|---|---|
| Arranque único, remotos y orden de servicios | `server/Main`, `shared/Modules/RemoteHelper`, `Events/RemoteNames` | Simulado + Studio (servidor) |
| Mapa procedural de 5 capítulos | `Logic/MazeLayout`, `Logic/LayoutPlanner`, `World/RoomGenerator`, `World/WorldService` | Simulado (2000 mapas) + Studio (5 capítulos, piso, paredes que bloquean la visión) |
| Objetivos y capítulos | `Logic/ObjectiveTracker`, `Story/StoryService`, `Config/ChapterConfig` | Simulado: campaña completa jugada por bots |
| Cinco criaturas | `AI/MonsterController`, `AI/Behaviors/*`, `Monsters/*` | Simulado (comportamientos) + Studio (aparecen, se mueven, extremidades unidas) |
| Modelos 3D de las criaturas | `assets/blender/build_creatures.py`, `assets/models`, `Monsters/MonsterFactory` | Generados y renderizados en Blender 4.5. Simulado (usa las mallas importadas, respeta tamaños y uniones, vuelve a Parts si faltan). Pendiente: importarlos en Studio y comprobar la orientación |
| Criaturas realistas con IA | `assets/models/ai`, `assets/blender/prepare_ai_models.py`, `Monsters/CreatureMeshes` | Las cinco generadas en Meshy desde las láminas de concepto y preparadas en Blender (17.459 triángulos, texturas PBR de 1024 px, cortadas en hombro, cadera y cuello). Simulado (cada pieza en su caja, giro desde arriba, textura compartida, sin ojos de neón). Studio: importadas y subidas, guardadas en `assets/models/rbxm/*.rbxmx`; en Play las cinco se arman con sus mallas y texturas (32 piezas), paradas y mirando al frente. Partida real (lobby → Iniciar → `setchapter` 2 a 5 por el panel de admin): cada capítulo trae su criatura con malla y se mueve sola, sin errores ni avisos de IA |
| Navegación | `Logic/MazeNav` | Simulado + Studio |
| Inventario, objetos, llaves, documentos, baterías | `Logic/InventoryModel`, `Inventory/InventoryService`, `World/InteractionService` | Simulado |
| Linterna con batería | `Data/FlashlightService`, `client/Camera/FirstPerson` | Simulado (servidor). Pendiente: el haz siguiendo la cámara en Studio |
| Puertas, cerraduras, generadores, válvulas, Núcleo | `World/DoorService`, `World/MechanismService` | Simulado |
| Escondites | `World/HidingService` | Simulado. Pendiente: vista por rendijas en Studio |
| Vida, daño, muerte y reaparición | `Data/HealthService`, `Multiplayer/MatchService` | Simulado |
| Resistencia, sprint y sigilo | `Logic/StaminaModel`, `Data/StaminaService` | Simulado |
| Lobby, preparación y cooperativo (1–4) | `Multiplayer/LobbyService`, `Multiplayer/MatchService` | Simulado (2, 3 y 4 jugadores, entrada en curso, abandono) |
| Finales y votación | `Story/EndingService` | Simulado |
| Guardado con DataStore | `Logic/SaveSchema`, `Data/ProgressionService` | Simulado (guarda, recarga, reintenta, no pisa datos si falla la carga). Studio: modo sesión sin API Services |
| Moderación | `Admin/*`, `client/UI/AdminUI` | Simulado |
| Analíticas | `Analytics/*` | Simulado (llamadas registradas). Pendiente: ver el panel de Creator Analytics |
| Antitrampas | `Security/AntiCheat` | Simulado (validación de movimiento). Desactivado en Studio a propósito |
| Interfaz adaptable PC/táctil | `client/UI/*` | Simulado (arranca en PC y móvil, controles funcionan). Pendiente: revisión visual |
| Audio y música | `Config/AudioConfig`, `client/Effects/AudioController` | Pendiente: escuchar en Studio |
| Efectos, cámara, animación de criaturas | `client/Effects/*`, `client/Camera/FirstPerson` | Simulado (sin errores). Pendiente: revisión visual |

## Revisión del 6 de noviembre (agentes del plugin ecc)

Cuatro revisores (seguridad, lógica, fallos silenciosos y rendimiento) leyeron
todo el código. Cada hallazgo se comprobó en el código antes de corregirlo.

- **Arranque**: un servicio del servidor o un módulo del cliente que falla ya no
  frena a los demás; se avisa en Output con su nombre.
- **Carga de capítulo**: si el mapa no se puede armar se prueba otra semilla y,
  si vuelve a fallar, el grupo vuelve al lobby (antes quedaba trabado en
  "Cargando" para siempre).
- **Criaturas**: cada una se actualiza por separado; la que falla seguido se
  retira sin congelar a las demás. Si falla al crearse no deja un cuerpo quieto.
  Si falta un modelo realista se avisa una vez.
- **Guardado**: si DataStore no responde al entrar, se reintenta cada 30 s y al
  volver se suma lo jugado en la sesión. Los guardados de un jugador van de a
  uno (al salir y al cerrar el servidor) y la carga ya no espera 6 s de más.
- **Sanciones**: se reintentan y, si no quedan guardadas, el panel avisa que sólo
  valen en ese servidor. Un administrador no puede expulsar ni sancionar a otro.
  Una falla de red al leer el rango del grupo ya no quita permisos toda la sesión.
- **Partida**: el aviso "CAÍSTE" ya no queda pegado en el capítulo siguiente; el
  espectador pasa al siguiente compañero con vida; el diálogo no se duplica tras
  un reintento; el resumen no arrastra fallos de la partida anterior; el voto del
  final se actualiza cuando alguien se va y el final se anota al empezar la escena.
- **Seguridad**: el botón de reiniciar está desactivado (gastaba los reintentos
  del grupo). Antitrampas más ajustado (1,3 × carrera), con límite bajo el piso y
  perdón de avisos viejos para no expulsar a quien tiene mala conexión. Las
  puertas tienen 1 s de espera entre usos y `RequestUpdate` responde sólo a quien
  lo pide.
- **Rendimiento**: la lista de ruidos ya no crece sin límite (unos 5 MB por hora);
  en bajo consumo sólo quedan prendidas las 8 luces más cercanas; los sonidos
  lejanos no se crean; el desenfoque se apaga entre pulsos; la resistencia se
  replica hasta 10 veces por segundo.
- **Luces**: el parpadeo de terror ya no prende las luces que el servidor apagó.

Quedan como mejoras menores sin hacer: exigir línea de vista y tiempo de
pulsación en los prompts del servidor, y no descontar reintentos por muertes sin
daño previo (sólo posibles con trampas, ahora que no hay botón de reinicio).

## Lo que se encontró y corrigió al probar

- En Studio el cliente fallaba al iniciar porque `PlayerScripts` todavía no tenía
  sus módulos: ahora `Main.client` espera cada uno. Comprobado en Studio el 4 de
  noviembre: el cliente imprime `[NOCTURNA] Cliente iniciado.` y el lobby aparece.
- Los bots quedaban trabados en el capítulo 4: faltaba el objetivo de juntar los
  fusibles antes de los generadores.
- Al desconectarse, un jugador perdía sus objetos de misión en vez de soltarlos.

## Limitaciones conocidas

- Las criaturas usan los modelos realistas de Meshy (`assets/models/rbxm`). Si
  falta una malla, el juego vuelve a las piezas simples.
- Las animaciones de las criaturas son procedurales (balanceo de extremidades),
  y los objetos del escenario (`FeatureBuilder`) se arman con piezas simples. Los
  sonidos son internos de Roblox deformados (`AudioConfig`).
- El chat `!comando` depende de `Player.Chatted`. Si con TextChatService no
  llegara, el panel ADMIN ofrece las mismas acciones.
