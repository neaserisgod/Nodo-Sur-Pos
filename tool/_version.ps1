# Helpers de versión compartidos por los scripts de publicación (se cargan
# con `. "$PSScriptRoot\_version.ps1"`). La versión vive en UN solo lugar,
# pubspec.yaml ("1.0.0+2098"); acá solo se lee y se sube el build.
#
# Formato para el actualizador: nombre.build con puntos ("1.0.0.2098"). Es el
# que lleva ProductVersion del .exe (windows/runner/Runner.rc) y el
# sparkle:version del feed — con "+" WinSparkle ofrecía actualizar en bucle
# (DECISIONES.md, spike 2026-09-30).

function Get-VersionPubspec {
    param([string]$Ruta = "pubspec.yaml")
    $linea = Select-String -Path $Ruta -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$' | Select-Object -First 1
    if (-not $linea) { throw "No pude leer 'version: X.Y.Z+N' de $Ruta" }
    $nombre = $linea.Matches[0].Groups[1].Value
    $build = [int]$linea.Matches[0].Groups[2].Value
    [pscustomobject]@{
        Nombre   = $nombre
        Build    = $build
        Completa = "$nombre+$build"
        Feed     = "$nombre.$build"
    }
}

# Sube el build number en 1 y devuelve la versión nueva. Mismo efecto que el
# `sed` de tool/publicar_actualizacion_companion.sh, que comparte pubspec.yaml:
# el build tiene que ser MAYOR para que el actualizador ofrezca la versión.
function Step-BuildPubspec {
    param([string]$Ruta = "pubspec.yaml")
    $actual = Get-VersionPubspec -Ruta $Ruta
    $nueva = "$($actual.Nombre)+$($actual.Build + 1)"
    $utf8SinBom = New-Object System.Text.UTF8Encoding($false)
    $completa = (Resolve-Path $Ruta).Path
    $texto = [System.IO.File]::ReadAllText($completa, $utf8SinBom)
    $texto = [regex]::Replace($texto, '(?m)^version:.*$', "version: $nueva", 1)
    [System.IO.File]::WriteAllText($completa, $texto, $utf8SinBom)
    Get-VersionPubspec -Ruta $Ruta
}
