# Compila la app de escritorio en release y la copia a una ubicación
# estable fuera del repo (Bruno, 2026-09-14: "si yo no abro el acceso
# directo la companion no funciona" — la companion solo tiene con quién
# hablar mientras la app de escritorio está abierta, así que la app tiene
# que arrancar sola con Windows en vez de depender de que alguien se
# acuerde de abrirla a mano).
#
# Cierra el gap que ya marcaba el README ("no hay un script de build+copia
# todavía"): antes de esto, lanzar la app significaba correr el .exe
# directo desde build\windows\x64\runner\Release\, una carpeta que
# `flutter build`/`flutter clean` pueden pisar o vaciar mientras la app
# está corriendo — mala base para un acceso directo de inicio de Windows.
#
# Corré desde la raíz del repo:
#   .\tool\publicar_actualizacion_desktop.ps1
#
# Con -SinAccesoDirecto se salta la creación/actualización del acceso
# directo de inicio (por si alguna vez hace falta solo recompilar y
# copiar, sin tocar el arranque de Windows).
param(
    [switch]$SinAccesoDirecto
)

$ErrorActionPreference = "Stop"

$carpetaInstalada = "C:\LaPlazoleta\app"
$origen = "build\windows\x64\runner\Release"
$exeInstalado = Join-Path $carpetaInstalada "la_plazoleta.exe"

Write-Output "Compilando..."
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows --release falló" }

Write-Output "Copiando a $carpetaInstalada..."
# robocopy con /MIR: la carpeta instalada queda IDÉNTICA a la recién
# compilada (borra lo que ya no exista, ej. un asset viejo) — no un merge
# que puede ir acumulando basura de versiones anteriores. Códigos de
# salida 0-7 de robocopy son éxito (copió algo); 8+ es error real.
robocopy $origen $carpetaInstalada /MIR /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falló (código $LASTEXITCODE)" }

if (-not $SinAccesoDirecto) {
    $shell = New-Object -ComObject WScript.Shell

    $carpetaInicio = [Environment]::GetFolderPath("Startup")
    $rutaAccesoInicio = Join-Path $carpetaInicio "La Plazoleta.lnk"
    Write-Output "Creando/actualizando el acceso directo de inicio: $rutaAccesoInicio"
    $accesoInicio = $shell.CreateShortcut($rutaAccesoInicio)
    $accesoInicio.TargetPath = $exeInstalado
    $accesoInicio.WorkingDirectory = $carpetaInstalada
    $accesoInicio.Description = "La Plazoleta"
    $accesoInicio.Save()

    # El acceso directo del escritorio que Bruno ya usaba a mano
    # ("la_plazoleta - Acceso directo.lnk") apuntaba directo a
    # build\windows\x64\runner\Release\ del repo — se actualiza acá para
    # que apunte a la copia estable en vez de quedar huérfano o roto la
    # próxima vez que esa carpeta de build cambie.
    $rutaAccesoEscritorio = "$env:USERPROFILE\Desktop\la_plazoleta - Acceso directo.lnk"
    if (Test-Path $rutaAccesoEscritorio) {
        Write-Output "Actualizando el acceso directo del escritorio: $rutaAccesoEscritorio"
        $accesoEscritorio = $shell.CreateShortcut($rutaAccesoEscritorio)
        $accesoEscritorio.TargetPath = $exeInstalado
        $accesoEscritorio.WorkingDirectory = $carpetaInstalada
        $accesoEscritorio.Save()
    }
}

Write-Output ""
Write-Output "Listo: $exeInstalado actualizado."
if (-not $SinAccesoDirecto) {
    Write-Output "Arranca sola con Windows — para desactivarlo, borrar el .lnk de la carpeta de inicio."
}
