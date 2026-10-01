# Publica una versión nueva de escritorio: sube el build, arma y firma el
# instalador, lo firma para el actualizador (DSA) y lo sube al servidor.
#
#   .\tool\publicar_release.ps1 -Notas "Arqueos opcionales"
#   .\tool\publicar_release.ps1 -Notas "..." -Rollout 50
#   .\tool\publicar_release.ps1 -Notas "..." -Canal beta -Rollout 100   # solo la ven las cuentas de administrador (tu PC)
#   .\tool\publicar_release.ps1 -DryRun            # todo menos subir y subir el build
#
# Variables de entorno (NINGUNA se imprime ni se guarda):
#   RELEASE_TOKEN        token del servidor de actualizaciones. Lo lee
#                        publicar-release.mjs del entorno; nunca va por
#                        argumento (se vería en la lista de procesos).
#   NODOSUR_SCRIPTS      carpeta scripts\ del repo del sitio (NodoSurPage),
#                        donde está publicar-release.mjs. Sin valor por defecto.
#   DSA_PRIVATE_KEY_PATH (opcional) clave privada DSA. Default:
#                        Documents\la_plazoleta_claves\dsa_priv.pem — FUERA del
#                        repo. Si se pierde, las PC ya instaladas NO pueden
#                        recibir más actualizaciones: respaldala (ver ESTADO.md).
#   Las de firma de código de tool\crear_instalador.ps1 (SIGN_PFX_*, etc.).
#
# -DryRun: compila, firma y arma el instalador con la versión ACTUAL (no sube
# el build), firma para el actualizador e IMPRIME el comando de subida sin
# ejecutarlo. Sirve para probar la cadena entera sin publicar nada.
param(
    [string]$Notas = "",
    [ValidateRange(1, 100)]
    [int]$Rollout = 10,
    [ValidateSet("stable", "beta")]
    [string]$Canal = "stable",
    [switch]$DryRun,
    [switch]$CertificadoDePrueba
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_version.ps1"

$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

# --- Validaciones antes de tocar nada (un build subido en vano no se recupera) ---
if (-not $env:NODOSUR_SCRIPTS) {
    throw "Falta la variable NODOSUR_SCRIPTS: la carpeta 'scripts' del repo del sitio (neaserisgod/NodoSurPage), donde está publicar-release.mjs. Ej: `$env:NODOSUR_SCRIPTS = 'C:\ruta\NodoSurPage\scripts'"
}
$scriptPublicar = Join-Path $env:NODOSUR_SCRIPTS "publicar-release.mjs"
if (-not (Test-Path $scriptPublicar)) {
    throw "NODOSUR_SCRIPTS apunta a '$env:NODOSUR_SCRIPTS' pero ahí no está publicar-release.mjs."
}
if (-not $env:RELEASE_TOKEN -and -not $DryRun) {
    throw "Falta la variable RELEASE_TOKEN (token del servidor de actualizaciones)."
}
$clavePrivada = if ($env:DSA_PRIVATE_KEY_PATH) { $env:DSA_PRIVATE_KEY_PATH } else { Join-Path $env:USERPROFILE "Documents\la_plazoleta_claves\dsa_priv.pem" }
if (-not (Test-Path $clavePrivada)) {
    throw "No encuentro la clave privada DSA en '$clavePrivada'. Definí DSA_PRIVATE_KEY_PATH o generala con tool\generar_claves_actualizacion.ps1."
}
if ((Resolve-Path $clavePrivada).Path.StartsWith($raiz, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "La clave privada está DENTRO del repo ($clavePrivada). Movela afuera: nunca se versiona."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "No encuentro node en el PATH (lo necesita publicar-release.mjs)." }

# sign_update del paquete llama a `openssl`. Git for Windows trae uno.
if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    $openssl = "${env:ProgramFiles}\Git\usr\bin"
    if (Test-Path "$openssl\openssl.exe") { $env:PATH = "$openssl;$env:PATH" }
    else { throw "No encuentro openssl (lo necesita sign_update). Instalá Git for Windows o agregalo al PATH." }
}

# --- 1. Build number ---
if ($DryRun) {
    $version = Get-VersionPubspec
    Write-Output "[DryRun] No se sube el build. Versión actual: $($version.Completa)"
} else {
    $version = Step-BuildPubspec
    Write-Output "Build subido: $($version.Completa)"
}

# --- 2. Instalador (compila, firma el .exe y el instalador) ---
# Hashtable, no array: con un array el switch se pasaría como argumento
# posicional y crear_instalador.ps1 nunca lo vería.
$argsInstalador = @{}
if ($CertificadoDePrueba) { $argsInstalador["CertificadoDePrueba"] = $true }
& "$PSScriptRoot\crear_instalador.ps1" @argsInstalador

$archivo = Join-Path $raiz "dist\LaPlazoleta-Setup-$($version.Feed).exe"
if (-not (Test-Path $archivo)) { throw "No encuentro el instalador $archivo" }

# --- 3. Firma para el actualizador (sign_update del paquete auto_updater) ---
# Va DESPUÉS de firmar el instalador: la firma DSA es sobre el archivo final.
Write-Output "Firmando para el actualizador (DSA)..."
$salida = & dart run auto_updater:sign_update $archivo $clavePrivada
if ($LASTEXITCODE -ne 0) { throw "sign_update falló" }
$coincidencia = [regex]::Match(($salida -join "`n"), 'sparkle:dsaSignature="([^"]+)"')
if (-not $coincidencia.Success -or $coincidencia.Groups[1].Value.Length -lt 40) {
    throw "No pude leer la firma DSA de la salida de sign_update."
}
$firma = $coincidencia.Groups[1].Value

# Verifica la firma contra la PÚBLICA que lleva embebida el .exe (dsa_pub.pem). Si la privada
# (p. ej. el secreto DSA_PRIVATE_KEY) no es la pareja de esa pública, WinSparkle en la PC del
# cliente dice "La actualización no está firmada adecuadamente": mejor cortar acá, antes de subir.
$publica = Join-Path $raiz "dsa_pub.pem"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("firma-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    [IO.File]::WriteAllBytes((Join-Path $tmp "firma.bin"), [Convert]::FromBase64String($firma))
    $sha1 = [Security.Cryptography.SHA1]::Create()
    $stream = [IO.File]::OpenRead($archivo)
    try { [IO.File]::WriteAllBytes((Join-Path $tmp "digest.bin"), $sha1.ComputeHash($stream)) } finally { $stream.Dispose() }
    $verif = & openssl dgst -sha1 -verify $publica -signature (Join-Path $tmp "firma.bin") (Join-Path $tmp "digest.bin") 2>&1
    if ($LASTEXITCODE -ne 0 -or ($verif -join " ") -notmatch "Verified OK") {
        throw "La firma DSA NO verifica contra dsa_pub.pem: la clave privada usada no es la pareja de la pública embebida en la app. No se publica. ($($verif -join ' '))"
    }
    Write-Output "Firma DSA verificada contra dsa_pub.pem."
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

# --- 4. Subida ---
$argumentos = @(
    $scriptPublicar,
    "--file", $archivo,
    "--platform", "windows",
    "--channel", $Canal,
    "--version", $version.Feed,
    "--signature", $firma,
    "--signature-type", "dsa",
    "--notes", $Notas,
    "--rollout", "$Rollout"
)
if ($DryRun) {
    Write-Output ""
    Write-Output "[DryRun] No se sube nada. El comando sería (RELEASE_TOKEN va por entorno, no se muestra):"
    Write-Output ("node " + (($argumentos | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { $_ } }) -join " "))
    return
}

Write-Output "Subiendo $($version.Feed) al servidor (canal $Canal, rollout $Rollout%)..."
& node @argumentos
if ($LASTEXITCODE -ne 0) { throw "publicar-release.mjs falló (código $LASTEXITCODE)" }
Write-Output ""
Write-Output "Publicado: $($version.Completa) (canal $Canal) al $Rollout% de las PC."
