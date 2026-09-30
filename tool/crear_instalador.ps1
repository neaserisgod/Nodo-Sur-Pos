# Compila la app en release, la firma, arma el instalador de Inno Setup y lo
# deja en dist\LaPlazoleta-Setup-<version>.exe (imprime el SHA-256).
#
# Corré desde la raíz del repo:
#   .\tool\crear_instalador.ps1
#   .\tool\crear_instalador.ps1 -CertificadoDePrueba   # firma autofirmada, solo para probar
#   .\tool\crear_instalador.ps1 -SinBuild              # reusa build\...\Release ya compilado
#
# NO sube el build number (eso lo hace tool\publicar_release.ps1).
#
# FIRMA DE CÓDIGO — sin guardar secretos en el repo, todo por variables de
# entorno. Se elige la primera que esté configurada:
#   (a) Azure Trusted Signing:
#         AZURE_SIGN_DLIB      ruta a Azure.CodeSigning.Dlib.dll
#         AZURE_SIGN_METADATA  ruta al metadata.json (endpoint, cuenta, perfil)
#       más las credenciales de Azure que use tu cuenta (AZURE_CLIENT_ID,
#       AZURE_TENANT_ID, AZURE_CLIENT_SECRET, o `az login`).
#   (b) Certificado .pfx:
#         SIGN_PFX_PATH        ruta al .pfx
#         SIGN_PFX_PASSWORD    su contraseña
#         SIGN_TIMESTAMP_URL   (opcional) default http://timestamp.digicert.com
#   (c) -CertificadoDePrueba: crea un certificado autofirmado en el almacén del
#       usuario y firma con ese. Sirve para probar el flujo; Windows NO lo
#       considera confiable.
# Sin nada de eso el instalador sale SIN firmar y Windows SmartScreen va a
# advertir al instalarlo.
param(
    [switch]$CertificadoDePrueba,
    [switch]$SinBuild
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_version.ps1"

$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

$version = Get-VersionPubspec
$carpetaBuild = Join-Path $raiz "build\windows\x64\runner\Release"
$exeApp = Join-Path $carpetaBuild "la_plazoleta.exe"
$instalador = Join-Path $raiz "dist\LaPlazoleta-Setup-$($version.Feed).exe"
$urlTimestamp = if ($env:SIGN_TIMESTAMP_URL) { $env:SIGN_TIMESTAMP_URL } else { "http://timestamp.digicert.com" }

function Find-Signtool {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $kits = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    $candidatos = Get-ChildItem "$kits\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
        Sort-Object { [version]($_.Directory.Parent.Name) } -Descending
    if ($candidatos) { return @($candidatos)[0].FullName }
    return $null
}

function Find-Iscc {
    $cmd = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($ruta in @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe")) {
        if (Test-Path $ruta) { return $ruta }
    }
    return $null
}

# Decide el modo de firma UNA vez. Devuelve $null si no hay nada configurado.
function Get-ModoFirma {
    if ($env:AZURE_SIGN_DLIB -and $env:AZURE_SIGN_METADATA) { return "azure" }
    if ($env:SIGN_PFX_PATH) { return "pfx" }
    if ($CertificadoDePrueba) { return "prueba" }
    return $null
}

function New-CertificadoDePrueba {
    $asunto = "CN=La Plazoleta (PRUEBA - no usar en produccion)"
    $existente = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
        Where-Object { $_.Subject -eq $asunto -and $_.NotAfter -gt (Get-Date).AddDays(7) } |
        Select-Object -First 1
    if ($existente) { return $existente }
    Write-Output "Creando certificado autofirmado de prueba en el almacén del usuario..."
    New-SelfSignedCertificate -Type CodeSigningCert -Subject $asunto `
        -CertStoreLocation Cert:\CurrentUser\My -NotAfter (Get-Date).AddYears(1)
}

$script:modoFirma = Get-ModoFirma
$script:signtool = $null

function Invoke-Firma {
    param([string]$Archivo)
    if (-not $script:modoFirma) { return }
    if (-not $script:signtool) {
        $script:signtool = Find-Signtool
        if (-not $script:signtool) {
            throw "Hay firma configurada pero no encuentro signtool.exe. Instalá el Windows SDK (componente 'Signing Tools for Desktop Apps') o agregalo al PATH."
        }
    }
    Write-Output "Firmando $(Split-Path -Leaf $Archivo) ($($script:modoFirma))..."
    switch ($script:modoFirma) {
        "azure" {
            & $script:signtool sign /v /fd SHA256 /tr "http://timestamp.acs.microsoft.com" /td SHA256 `
                /dlib $env:AZURE_SIGN_DLIB /dmdf $env:AZURE_SIGN_METADATA $Archivo
        }
        "pfx" {
            if (-not (Test-Path $env:SIGN_PFX_PATH)) { throw "SIGN_PFX_PATH apunta a un archivo que no existe: $env:SIGN_PFX_PATH" }
            # La contraseña va por argumento de signtool, nunca a la salida.
            $argsFirma = @("sign", "/fd", "SHA256", "/tr", $urlTimestamp, "/td", "SHA256", "/f", $env:SIGN_PFX_PATH)
            if ($env:SIGN_PFX_PASSWORD) { $argsFirma += @("/p", $env:SIGN_PFX_PASSWORD) }
            & $script:signtool @argsFirma $Archivo
        }
        "prueba" {
            $cert = New-CertificadoDePrueba
            & $script:signtool sign /fd SHA256 /sha1 $cert.Thumbprint $Archivo
        }
    }
    if ($LASTEXITCODE -ne 0) { throw "signtool falló firmando $Archivo (código $LASTEXITCODE)" }
}

$iscc = Find-Iscc
if (-not $iscc) {
    throw "No encuentro ISCC.exe (Inno Setup 6). Instalalo desde https://jrsoftware.org/isdl.php o agregalo al PATH."
}

if (-not $script:modoFirma) {
    Write-Host ""
    Write-Host "ATENCION: sin certificado de firma de código configurado." -ForegroundColor Red
    Write-Host "El instalador se genera SIN firmar: Windows SmartScreen va a advertir al instalarlo." -ForegroundColor Red
    Write-Host "Configurá SIGN_PFX_PATH/SIGN_PFX_PASSWORD o Azure Trusted Signing (ver el encabezado de este script)." -ForegroundColor Red
    Write-Host ""
} elseif ($script:modoFirma -eq "prueba") {
    Write-Host "Firmando con un certificado AUTOFIRMADO de prueba: Windows no lo va a considerar confiable." -ForegroundColor Yellow
}

if (-not $SinBuild) {
    Write-Output "Compilando la versión $($version.Completa)..."
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows --release falló" }
}
if (-not (Test-Path $exeApp)) { throw "No existe $exeApp — compilá primero (sin -SinBuild)." }

Invoke-Firma $exeApp

Write-Output "Armando el instalador con Inno Setup..."
& $iscc "/DMyAppVersion=$($version.Feed)" "/DSourceDir=$carpetaBuild" (Join-Path $raiz "installer\la_plazoleta.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC falló (código $LASTEXITCODE)" }
if (-not (Test-Path $instalador)) { throw "El instalador no quedó en $instalador" }

Invoke-Firma $instalador

# El hash se calcula al final, con el instalador ya firmado: firmar cambia el
# archivo, y es ESE el que se sube y se firma para el actualizador.
$hash = (Get-FileHash $instalador -Algorithm SHA256).Hash
Write-Output ""
Write-Output "Listo: $instalador"
Write-Output "Versión: $($version.Completa)  (feed: $($version.Feed))"
Write-Output "SHA-256: $hash"
