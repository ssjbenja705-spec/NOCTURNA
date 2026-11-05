# NOCTURNA — antes de publicar

El código del juego está completo. Estos pasos sólo se pueden hacer desde Roblox
Studio o el panel de creador.

## Obligatorio

1. **Publicar y activar API Services** (Game Settings → Security → *Enable Studio
   Access to API Services*). Sin esto el guardado funciona en modo sesión y el lobby lo avisa.
2. **Máximo de jugadores = 4** (Game Settings → Places). El servidor ya rechaza al
   quinto, pero Roblox debe saber que el servidor es de cuatro.
3. **Administradores**: el dueño de la experiencia (o el rango 255 del grupo) ya
   es administrador. Para sumar a otros, agregar su UserId en
   `src/server/Admin/AdminConfig.lua`.
4. **Jugar una partida con 2 o más clientes** (Test → Clients and Servers) y una
   en el emulador de dispositivos (teléfono y tablet).

## Revisión recomendada

- Ver a las criaturas caminar y atacar en una partida real (ya están importadas
  y se ven bien quietas).
- Poner el crédito *"Modelos de criaturas creados con Meshy (CC BY 4.0)"* en la
  descripción de la experiencia: los modelos salieron del plan gratis.
- Escuchar la mezcla de audio y ajustar volúmenes en `src/shared/Config/AudioConfig.lua`.
- Mirar los cinco temas visuales con luz y sin luz; ajustar `ThemeConfig.lua`.
- Ajustar dificultad (`MonsterConfig.lua`, `GameConfig.Match`) con jugadores reales.
- Comprobar que los comandos `!` del chat llegan con TextChatService.
- Icono, miniaturas, descripción y cuestionario de clasificación de edad (terror).
- Publicar primero como privada o beta.

## Verificación ya realizada

- `lune run tests/lune/run.luau`: 81 pruebas, todas correctas, incluida una
  campaña completa de 5 capítulos jugada por bots, guardado y recarga.
- `luau-lsp analyze` con las definiciones oficiales de la API: sin errores.
- `rojo build`: compila.
- Roblox Studio 0.745 (Play Solo, servidor): 49 de 49 comprobaciones de
  `tests/Studio/SmokeTest` correctas.
- Roblox Studio, 4 de noviembre: las cinco criaturas realistas importadas en
  `ServerStorage/NocturnaModels`. En Play arrancan servidor y cliente
  (`[NOCTURNA] Cliente iniciado.`), aparece el lobby y `MonsterFactory.Build`
  arma las cinco con sus mallas y texturas.
