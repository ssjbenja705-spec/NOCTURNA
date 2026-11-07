# Donaciones (y los servidores de las partidas)

En el lobby, a la derecha del mostrador, está el **rincón de los mecenas**: tres
podios con la estatua (el avatar) de los tres jugadores que más donaron, con su
nombre y su total, y una **urna**. Al acercarse a la urna y tocar **Donar** se abre
un panel con un botón por monto: 100 R$ y después de 200 a 10.000 R$, de 200 en 200
(51 montos).

Cada botón es un **producto de desarrollador** de Roblox. El juego ya está listo;
falta que crees los productos en Creator Hub y pegues sus ids. **Un monto con id 0
no aparece en el juego**, así que podés crear sólo algunos y agregar el resto
después.

## 1. Crear los productos

1. Entrá a <https://create.roblox.com> → **Creaciones** → NOCTURNA.
2. Menú de la izquierda: **Monetización → Productos de desarrollador**.
3. **Crear un producto de desarrollador** y completá con una fila de la tabla:
   - **Nombre**: el de la tabla (por ejemplo `Donación 200 R$`).
   - **Descripción**: `Una donación para mantener viva la Fundación Leteo. ¡Gracias!`
   - **Precio en Robux**: el de la tabla. **Tiene que ser exactamente ese**: el
     podio suma el monto de la tabla, no el que cobre Roblox.
   - Ícono: opcional (sirve el ícono del juego).
4. Guardá. En la lista de productos, en los tres puntos del producto, elegí
   **Copiar ID del recurso** (Copy Asset ID).
5. Repetí con cada fila.

## 2. Pegar los ids

Abrí `src/shared/Config/DonationConfig.lua`. Hay una línea por monto, en el mismo
orden que la tabla:

```lua
    {Robux = 200, ProductId = 0},
```

Reemplazá el `0` por el id que copiaste:

```lua
    {Robux = 200, ProductId = 1234567890},
```

Después sincronizá con Rojo (o `rojo build`) y publicá el lugar. Sólo aparecen los
botones de los montos con id.

## 3. Tabla de productos

| # | Nombre | Precio (R$) | Línea en `DonationConfig.lua` |
|---|---|---|---|
| 1 | Donación 100 R$ | 100 | 7 |
| 2 | Donación 200 R$ | 200 | 8 |
| 3 | Donación 400 R$ | 400 | 9 |
| 4 | Donación 600 R$ | 600 | 10 |
| 5 | Donación 800 R$ | 800 | 11 |
| 6 | Donación 1.000 R$ | 1000 | 12 |
| 7 | Donación 1.200 R$ | 1200 | 13 |
| 8 | Donación 1.400 R$ | 1400 | 14 |
| 9 | Donación 1.600 R$ | 1600 | 15 |
| 10 | Donación 1.800 R$ | 1800 | 16 |
| 11 | Donación 2.000 R$ | 2000 | 17 |
| 12 | Donación 2.200 R$ | 2200 | 18 |
| 13 | Donación 2.400 R$ | 2400 | 19 |
| 14 | Donación 2.600 R$ | 2600 | 20 |
| 15 | Donación 2.800 R$ | 2800 | 21 |
| 16 | Donación 3.000 R$ | 3000 | 22 |
| 17 | Donación 3.200 R$ | 3200 | 23 |
| 18 | Donación 3.400 R$ | 3400 | 24 |
| 19 | Donación 3.600 R$ | 3600 | 25 |
| 20 | Donación 3.800 R$ | 3800 | 26 |
| 21 | Donación 4.000 R$ | 4000 | 27 |
| 22 | Donación 4.200 R$ | 4200 | 28 |
| 23 | Donación 4.400 R$ | 4400 | 29 |
| 24 | Donación 4.600 R$ | 4600 | 30 |
| 25 | Donación 4.800 R$ | 4800 | 31 |
| 26 | Donación 5.000 R$ | 5000 | 32 |
| 27 | Donación 5.200 R$ | 5200 | 33 |
| 28 | Donación 5.400 R$ | 5400 | 34 |
| 29 | Donación 5.600 R$ | 5600 | 35 |
| 30 | Donación 5.800 R$ | 5800 | 36 |
| 31 | Donación 6.000 R$ | 6000 | 37 |
| 32 | Donación 6.200 R$ | 6200 | 38 |
| 33 | Donación 6.400 R$ | 6400 | 39 |
| 34 | Donación 6.600 R$ | 6600 | 40 |
| 35 | Donación 6.800 R$ | 6800 | 41 |
| 36 | Donación 7.000 R$ | 7000 | 42 |
| 37 | Donación 7.200 R$ | 7200 | 43 |
| 38 | Donación 7.400 R$ | 7400 | 44 |
| 39 | Donación 7.600 R$ | 7600 | 45 |
| 40 | Donación 7.800 R$ | 7800 | 46 |
| 41 | Donación 8.000 R$ | 8000 | 47 |
| 42 | Donación 8.200 R$ | 8200 | 48 |
| 43 | Donación 8.400 R$ | 8400 | 49 |
| 44 | Donación 8.600 R$ | 8600 | 50 |
| 45 | Donación 8.800 R$ | 8800 | 51 |
| 46 | Donación 9.000 R$ | 9000 | 52 |
| 47 | Donación 9.200 R$ | 9200 | 53 |
| 48 | Donación 9.400 R$ | 9400 | 54 |
| 49 | Donación 9.600 R$ | 9600 | 55 |
| 50 | Donación 9.800 R$ | 9800 | 56 |
| 51 | Donación 10.000 R$ | 10000 | 57 |

## 4. Probar

- En **Configuración del juego → Seguridad** activá *Enable Studio Access to API
  Services*: las donaciones se guardan en DataStore y sin eso no se acreditan.
- En Studio las compras son de prueba (no cobran Robux). Tocá la urna, comprá un
  monto y fijate que aparezca el agradecimiento y que, unos segundos después, tu
  avatar suba al podio.
- El podio se actualiza a los 3 segundos de cada donación y, además, cada minuto
  (así se ven también las donaciones hechas en otros servidores).

## Cómo funciona (por si lo necesitás)

- Roblox avisa cada compra a `MarketplaceService.ProcessReceipt`
  (`src/server/Lobby/DonationService.lua`) y la repite hasta que el juego
  confirma. Cada compra se cuenta **una sola vez**: el total del donante y las
  compras ya procesadas se guardan juntos, en una sola escritura.
  - `NOCTURNA_DONATIONS_V1` → `DONOR_<userId>`: total donado y últimas compras.
  - `NOCTURNA_DONATION_RANKING_V1` (OrderedDataStore) → total por usuario, para el
    podio.
- El monto sale siempre de `DonationConfig.lua` según el id del producto; el
  cliente nunca dice cuánto donó.
- Si el guardado falla, el juego le pide a Roblox que reintente más tarde
  (`NotProcessedYet`) y no se pierde la donación.
- Sólo puede haber un `ProcessReceipt` por juego. Si algún día agregás otros
  productos (por ejemplo, objetos), hay que atenderlos en ese mismo archivo: un
  producto que no está en `DonationConfig.lua` queda sin procesar.
- Si un avatar no se puede cargar, el podio muestra una silueta oscura.

## Servidores de las partidas (ascensores)

Al fondo del lobby hay cuatro ascensores. El primero que entra a uno vacío es el
anfitrión: elige cantidad de jugadores (1 a 4), dificultad y capítulo (hasta el
último que desbloqueó) y toca **EMPEZAR**; también arranca solo cuando se llena.
Las puertas se cierran y el grupo viaja junto a un **servidor nuevo y propio del
mismo lugar** (servidor reservado). Al terminar la partida todos vuelven a un lobby
público. Quien se desconecta en plena partida puede volver desde el lobby durante
3 horas.

Qué hay que hacer en Creator Hub:

- **Nada que crear**: el lobby y las partidas son el mismo lugar, así que no hace
  falta un segundo lugar ni activar viajes a juegos de terceros.
- **Lugares → Cantidad máxima de jugadores: 12**. Es el tamaño de cada lobby
  (`LobbyCapacity` en `src/shared/Config/LobbyConfig.lua`); si cambiás uno, cambiá
  el otro. Las partidas nunca pasan de 4 aunque el lugar admita más.
- Tener activado el acceso a DataStore (el mismo ajuste de arriba).

Para probar los viajes hay que **publicar** y entrar desde la web o la app con dos
cuentas: Roblox no permite viajar entre servidores desde Studio. En Studio (o si
ponés `Teleport.Enabled = false` en `LobbyConfig.lua`) la partida se juega en el
mismo servidor, como antes, para poder probar todo sin publicar.
