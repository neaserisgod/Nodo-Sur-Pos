# Corré esto UNA VEZ, como administrador (clic derecho -> "Ejecutar con PowerShell"
# desde una consola de administrador, o `powershell -File tool\permitir_firewall_companion.ps1`
# desde una consola ya elevada), después de instalar la app en la PC del local.
#
# Por qué hace falta: la primera vez que la app abre el puerto de la companion
# app, Windows puede crear una regla de firewall que solo cubre el perfil de
# red que esté activo en ESE momento (ej. "Pública") — si el local usa una
# red categorizada distinto (ej. "Privada"), un celular de verdad puede
# quedar bloqueado sin ningún aviso visible. Esto agrega una regla explícita
# que cubre los tres perfiles de una sola vez, para no depender de eso.

$ErrorActionPreference = 'Stop'

$rutaExe = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\la_plazoleta.exe'
if (-not (Test-Path $rutaExe)) {
    Write-Error "No se encontró $rutaExe -- corré 'flutter build windows' antes, o ajustá la ruta si la app está instalada en otro lado."
}

netsh advfirewall firewall add rule `
    name="La Plazoleta (companion, todas las redes)" `
    dir=in action=allow `
    program="$rutaExe" `
    protocol=TCP localport=8099 `
    profile=any

Write-Host "Listo. Regla de firewall agregada para los tres perfiles de red."
