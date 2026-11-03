# Pruebas

## Automáticas (sin Roblox)

```bash
lune run tests/lune/run.luau
lune run tests/lune/run.luau "campaña completa"
```

El segundo comando corre sólo las pruebas cuyo nombre contiene ese texto.

`Engine.luau` simula lo necesario para ejecutar el código real del juego:
reloj virtual, instancias, señales, remotos, personajes, DataStore y la
CollectionService. Cada instancia se valida contra la base de reflexión de
Roblox, así que una propiedad inexistente o de tipo incorrecto falla igual que
en el motor. No simula física, render, red ni rayos contra la geometría (los
rayos siempre llegan).

`Bot.luau` juega como una persona: lee el objetivo que manda el servidor, va
hasta el lugar y usa el prompt que encuentra.

Cubre la estructura del proyecto (remotos, puntos de entrada, módulos), los datos
del juego, 2000 mapas generados, la lógica pura, la IA de las cinco criaturas, una
campaña completa, la muerte y la reaparición, el cooperativo, la reconexión, los
controles de PC y táctiles, el guardado, la seguridad, la moderación y las analíticas.

## En el motor real

```bash
rojo build test.project.json -o NOCTURNA_TEST.rbxlx
```

Abrirlo en Roblox Studio y presionar Play. `tests/Studio/SmokeTest.server.lua`
recorre los cinco capítulos y escribe `[NOCTURNA TEST]` en Output. Comprueba el
piso bajo el jugador, las paredes que bloquean la visión, la orientación de los
objetos y que las cinco criaturas aparezcan con su cuerpo unido y se muevan.
También confirmar que el cliente muestre `[NOCTURNA] Cliente iniciado.`

Esta prueba no se incluye en `default.project.json`, el proyecto que se publica.
