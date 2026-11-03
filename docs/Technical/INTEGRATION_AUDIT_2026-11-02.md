# Auditoría de integración — 2 de noviembre de 2026

## Alcance verificado

Se revisaron los archivos disponibles en la rama `main` del repositorio. Esta auditoría confirma:

- El proyecto se llama **NOCTURNA: EL ÚLTIMO RECUERDO**.
- Utiliza Rojo y `default.project.json` para mapear `src/shared`, `src/server`, `src/client` y `tests/Server`.
- La configuración general declara juego en primera persona, máximo 4 jugadores, movimiento con sprint, linterna y cinco capítulos.
- El README y el documento `SYSTEM_STATUS.md` describen el código como una base de desarrollo, no como un juego terminado.

## Estado real

La existencia de scripts y configuraciones no demuestra que los sistemas funcionen juntos. No se debe considerar terminado ni probado hasta sincronizar el proyecto con Roblox Studio y ejecutar pruebas dentro del motor.

## Pendientes antes de publicar

1. Revisar todos los scripts y resolver referencias a RemoteEvents/RemoteFunctions que no coincidan entre cliente y servidor.
2. Comprobar que cada servicio se inicialice una sola vez y que no haya controladores duplicados de cámara, linterna o IA.
3. Validar rutas de módulos `require`, nombres y ubicaciones que espera Rojo.
4. Completar y conectar mapa, monstruos, animaciones, audio, objetivos, inventario y cinemáticas.
5. Verificar guardado de datos y validar en servidor todas las acciones recibidas por RemoteEvents.
6. Probar cooperativo con 2–4 jugadores, controles táctiles, rendimiento móvil y reconexión.
7. Ejecutar pruebas en Roblox Studio y corregir errores de Output antes de publicar.

## Limitación de esta entrega

Esta auditoría se hizo sobre los archivos que se pudieron leer del repositorio. No se ejecutó Roblox Studio ni se simuló una sesión multijugador. Por lo tanto, no certifica funcionamiento en tiempo de ejecución ni reemplaza las pruebas del juego.
