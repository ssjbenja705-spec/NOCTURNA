# NOCTURNA — antes de publicar

El código del juego está completo. Estos pasos sólo se pueden hacer desde Roblox
Studio o el panel de creador.

## Obligatorio

1. **Probar el cliente en Studio.** Construir `test.project.json`, dar Play y
   confirmar en Output que aparece `[NOCTURNA] Cliente iniciado.` sin errores.
   Esa corrección (`Main.client` esperando sus módulos) se verificó en el
   simulador, no en Studio.
2. **Publicar y activar API Services** (Game Settings → Security → *Enable Studio
   Access to API Services*). Sin esto el guardado funciona en modo sesión y el lobby lo avisa.
3. **Máximo de jugadores = 4** (Game Settings → Places). El servidor ya rechaza al
   quinto, pero Roblox debe saber que el servidor es de cuatro.
4. **Administradores**: el dueño de la experiencia (o el rango 255 del grupo) ya
   es administrador. Para sumar a otros, agregar su UserId en
   `src/server/Admin/AdminConfig.lua`.
5. **Jugar una partida con 2 o más clientes** (Test → Clients and Servers) y una
   en el emulador de dispositivos (teléfono y tablet).

## Revisión recomendada

- Escuchar la mezcla de audio y ajustar volúmenes en `src/shared/Config/AudioConfig.lua`.
- Mirar los cinco temas visuales con luz y sin luz; ajustar `ThemeConfig.lua`.
- Ajustar dificultad (`MonsterConfig.lua`, `GameConfig.Match`) con jugadores reales.
- Comprobar que los comandos `!` del chat llegan con TextChatService.
- Icono, miniaturas, descripción y cuestionario de clasificación de edad (terror).
- Publicar primero como privada o beta.

## Verificación ya realizada

- `lune run tests/lune/run.luau`: 79 pruebas, todas correctas, incluida una
  campaña completa de 5 capítulos jugada por bots, guardado y recarga.
- `luau-lsp analyze` con las definiciones oficiales de la API: sin errores.
- `rojo build`: compila.
- Roblox Studio 0.745 (Play Solo, servidor): 49 de 49 comprobaciones de
  `tests/Studio/SmokeTest` correctas.
