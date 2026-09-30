# Comprobación de la clave de firma de actualizaciones (DSA), compartida por tool\publicar_release.ps1 y el flujo de
# GitHub `publicar-beta`. Se carga con `. "$PSScriptRoot\_firma.ps1"`.
#
# Por qué existe: `sign_update` (paquete auto_updater) NO avisa cuando la clave privada no sirve. Su último comando
# termina "bien" con la salida vacía y solo dice "Failed to sign update", sin el mensaje real de OpenSSL. Peor aún: una
# clave válida pero de OTRO par firma sin error y las PC instaladas rechazan la actualización. Por eso se comprueba antes
# de compilar: que la clave se pueda leer, y que sea la que corresponde a la pública (dsa_pub.pem) que lleva el .exe.

function Test-ClaveDsa {
    param(
        [Parameter(Mandatory)][string]$ClavePrivada,
        [Parameter(Mandatory)][string]$ClavePublica
    )
    if (-not (Test-Path $ClavePrivada)) { throw "No existe la clave privada DSA: $ClavePrivada" }
    if (-not (Test-Path $ClavePublica)) { throw "No existe la clave pública del repo: $ClavePublica" }

    # Las salidas de OpenSSL van a stderr: con $ErrorActionPreference = "Stop" Windows PowerShell 5.1 las toma por error.
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $lectura = & openssl dsa -in $ClavePrivada -noout 2>&1
        $codigoLectura = $LASTEXITCODE
        $derivada = & openssl dsa -in $ClavePrivada -pubout 2>$null
        $codigoDerivada = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $anterior
    }

    if ($codigoLectura -ne 0 -or $codigoDerivada -ne 0) {
        $detalle = ($lectura | ForEach-Object { "$_" }) -join " "
        throw ("La clave privada no se puede leer como una clave DSA. OpenSSL dijo: $detalle`n" +
            "Revisá que el secreto DSA_PRIVATE_KEY (o el archivo) sea el contenido COMPLETO de dsa_priv.pem, con las líneas " +
            "'-----BEGIN ... PRIVATE KEY-----' y '-----END ... PRIVATE KEY-----', y que no sea la clave pública.")
    }

    $compacta = { param($t) (($t | ForEach-Object { "$_" }) -join "") -replace "\s", "" }
    $deLaPrivada = & $compacta $derivada
    $delRepo = & $compacta (Get-Content $ClavePublica)
    if ($deLaPrivada -ne $delRepo) {
        throw ("La clave privada es válida pero NO corresponde a dsa_pub.pem del repo. Si publicás así, las PC instaladas " +
            "rechazan la actualización. Usá la privada de ese mismo par, o generá un par nuevo y commiteá el dsa_pub.pem nuevo " +
            "ANTES de publicar (el instalador lleva la pública adentro).")
    }
}
