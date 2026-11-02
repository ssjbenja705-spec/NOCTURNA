# Pruebas

Los archivos de esta carpeta contienen comprobaciones iniciales.

La carpeta `tests/Server` se monta en `ServerScriptService.Tests` mediante Rojo.
En Roblox Studio, ejecuta desde la barra de comandos del servidor:

```lua
require(game:GetService("ServerScriptService").Tests.ProjectChecks)
```

La existencia del archivo no significa que las pruebas ya se hayan ejecutado.