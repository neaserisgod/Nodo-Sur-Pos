# Genera el par de claves DSA con las que se firman las actualizaciones, con
# el generate_keys del paquete auto_updater (README oficial), pero dejando la
# PRIVADA fuera del repo: Documents\la_plazoleta_claves\.
#
#   .\tool\generar_claves_actualizacion.ps1
#
# Se corre UNA vez en la vida del proyecto. La pública (dsa_pub.pem) se copia
# a la raíz del repo y va embebida en el .exe (windows\runner\Runner.rc). Si se
# pierde la privada, las PC ya instaladas no pueden recibir más
# actualizaciones: hay que respaldarla (ver ESTADO.md).
$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
$carpeta = Join-Path $env:USERPROFILE "Documents\la_plazoleta_claves"
$bat = Join-Path $raiz "windows\flutter\ephemeral\.plugin_symlinks\auto_updater_windows\windows\WinSparkle-0.8.1\bin\generate_keys.bat"

if (Test-Path (Join-Path $carpeta "dsa_priv.pem")) {
    throw "Ya hay claves en $carpeta. No las piso: si querés rotarlas, movelas a mano (y leé el aviso del Runner.rc antes)."
}
if (-not (Test-Path $bat)) { throw "No encuentro $bat — corré 'flutter pub get' primero." }
if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    $openssl = "${env:ProgramFiles}\Git\usr\bin"
    if (Test-Path "$openssl\openssl.exe") { $env:PATH = "$openssl;$env:PATH" }
    else { throw "No encuentro openssl. Instalá Git for Windows o agregalo al PATH." }
}

New-Item -ItemType Directory -Force $carpeta | Out-Null
Push-Location $carpeta
try { & $bat } finally { Pop-Location }
Copy-Item (Join-Path $carpeta "dsa_pub.pem") (Join-Path $raiz "dsa_pub.pem")
Write-Output "Privada: $carpeta\dsa_priv.pem  (RESPALDAR — nunca al repo)"
Write-Output "Pública copiada a: $raiz\dsa_pub.pem"
