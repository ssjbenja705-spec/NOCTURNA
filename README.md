# NOCTURNA — Starter técnico

Este paquete es el punto de partida del proyecto Roblox. Incluye estructura Rojo y scripts iniciales de cámara, linterna y ambiente.
**No es todavía un juego completo ni ha sido probado dentro de Roblox Studio.** La validación final requiere Roblox Studio en Windows o macOS.

## Archivos
- `default.project.json`: configuración Rojo.
- `src/client/FirstPerson.client.lua`: primera persona y controles básicos.
- `src/client/Flashlight.client.lua`: linterna con botón táctil y tecla F.
- `src/server/Lighting.server.lua`: iluminación atmosférica inicial.
- `src/shared/Config.lua`: configuración central.
- `docs/ROADMAP.md`: siguientes hitos.

## Importante para el flujo solo Android
Puedes guardar y editar este repositorio desde GitHub móvil o un navegador. GitHub Codespaces ofrece una cuota mensual gratuita para cuentas personales, pero **no ejecuta Roblox Studio**. Roblox Studio solo está disponible oficialmente en Windows y macOS.
Cuando tengas acceso a una PC compatible, instala Rojo y Roblox Studio, abre este proyecto y sincronízalo.

## Sincronización cuando tengas Roblox Studio
1. Instala Roblox Studio en Windows/macOS.
2. Instala Rojo siguiendo la documentación oficial: https://rojo.space/
3. En la carpeta del proyecto ejecuta `rojo serve`.
4. En Roblox Studio instala el plugin Rojo y conecta el proyecto.
5. Prueba en Play y revisa Output antes de publicar.

No compartas cookies, contraseñas ni tokens de Roblox con ninguna herramienta.
