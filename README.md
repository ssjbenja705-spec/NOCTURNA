# NOCTURNA: EL ÚLTIMO RECUERDO

Juego cooperativo de terror en primera persona para Roblox, de 1 a 4 jugadores,
para PC, celulares y tablets.

Tu hermana Alma desapareció hace tres años en una instalación de la Fundación
Leteo. Anoche su voz salió de la radio de casa. Cinco capítulos, cinco
criaturas, quince documentos y tres finales.

## Cómo abrirlo

El proyecto usa [Rojo](https://rojo.space) 7.

```bash
rojo build default.project.json -o NOCTURNA.rbxlx
```

Abrí `NOCTURNA.rbxlx` en Roblox Studio y presioná Play. Para trabajar en vivo:
`rojo serve` y conectá el plugin de Rojo.

Todo (mapa, criaturas, interfaz y sonido) se genera por código: no hace falta
importar modelos ni audio.

## Controles

| Acción | PC | Mando | Táctil |
|---|---|---|---|
| Correr | Shift (mantener) | L3 | Botón CORRER (mantener) |
| Sigilo | C o Ctrl | R3 | Botón SIGILO |
| Linterna | F | X | Botón LUZ |
| Interactuar | E (mantener si hace falta) | según el prompt | tocar el prompt |
| Inventario | I o Tab | — | botón OBJETOS |
| Diario | J | — | botón DIARIO |
| Ajustes | P | — | botón AJUSTES |
| Usar batería / botiquín | R / H | — | desde el inventario |

## Estructura

- `src/shared`: configuración, historia, textos y lógica pura (mapa, objetivos,
  inventario, guardado). La usan servidor, cliente y pruebas.
- `src/server`: un único `Main.server.lua` que inicia todos los servicios en orden.
- `src/client`: un único `Main.client.lua` que inicia la interfaz, la cámara, el audio y los efectos.
- `tests/lune`: pruebas automáticas fuera de Roblox, con un motor simulado.
- `tests/Studio`: prueba dentro del motor real (`test.project.json`).
- `docs`: diseño y estado técnico.

## Pruebas

```bash
lune run tests/lune/run.luau
```

Necesita [Lune](https://github.com/lune-org/lune) 0.10.x. La versión 0.11.1 se
cerraba al iniciar en el equipo donde se desarrolló. Para la prueba en el motor
real:

```bash
rojo build test.project.json -o NOCTURNA_TEST.rbxlx
```

Abrilo en Studio, presioná Play y revisá las líneas `[NOCTURNA TEST]` en Output.
Detalles en `tests/README.md`.

## Antes de publicar

Ver `docs/Technical/RELEASE_READINESS.md`: hay pasos que sólo se pueden hacer
desde Roblox Studio o el panel de creador (API Services, cantidad máxima de
jugadores, administradores, icono).
