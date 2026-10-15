# El bot de WhatsApp adentro de Nodo Sur Servicios para Windows (El dueño, 2026-10-15, docs/PLAN-ESCRITORIO-SERVICIOS.md).
# Arma en build\bot-windows lo que el instalador de Servicios lleva en <app>\bot (lo copia tool\crear_instalador.ps1):
#  * node.exe: el Node oficial de Windows (x64), de una versión fija y verificado contra el SHA-256 publicado por nodejs.org;
#  * bot.zip: el bot (repo botdemo, $env:BOT_DIR, por defecto ..\botdemo), igual que el del Android: sin dependencias opcionales
#    (whatsapp-web.js arrastra Chromium y better-sqlite3 hay que compilarlo); sin ellas usa el SQLite que trae Node.
# El supervisor (windows\bot\supervisor.js) está en el repo. Nada de esto se sube al repo: build\ está ignorada.
#
#   $env:BOT_DIR = "C:\ruta\botdemo"; .\tool\preparar_bot_windows.ps1
$ErrorActionPreference = "Stop"

# Versión fija de Node (LTS). Para cambiarla: la versión y el SHA-256 de win-x64/node.exe de
# https://nodejs.org/dist/v<versión>/SHASUMS256.txt. Tiene que ser 22.5 o más nueva (el SQLite incorporado).
$versionNode = "24.21.0"
$shaNode = "ba4e6d110e8c1592a1ecd390f6b05f3da124b13871a5be62b341a07a853c6c32"

$raiz = Split-Path -Parent $PSScriptRoot
$salida = Join-Path $raiz "build\bot-windows"
$botDir = if ($env:BOT_DIR) { $env:BOT_DIR } else { Join-Path (Split-Path -Parent $raiz) "botdemo" }
$botDir = (Resolve-Path $botDir).Path
if (-not (Test-Path (Join-Path $botDir "src\index.js"))) { throw "No encuentro el bot en $botDir (BOT_DIR=ruta al repo botdemo)" }

Remove-Item -Recurse -Force $salida -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $salida | Out-Null

Write-Output "Bajando Node $versionNode para Windows..."
$node = Join-Path $salida "node.exe"
Invoke-WebRequest -Uri "https://nodejs.org/dist/v$versionNode/win-x64/node.exe" -OutFile $node -UseBasicParsing
$sha = (Get-FileHash $node -Algorithm SHA256).Hash.ToLower()
if ($sha -ne $shaNode) { throw "node.exe no coincide con el publicado ($sha). No se usa." }

Write-Output "Armando el bot desde $botDir..."
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("bot-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
    Copy-Item -Recurse (Join-Path $botDir "src") $tmp
    foreach ($f in "package.json", "package-lock.json", "config.example.json") { Copy-Item (Join-Path $botDir $f) $tmp }
    Push-Location $tmp
    try {
        npm ci --omit=optional --omit=dev --no-audit --no-fund | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "npm ci falló" }
        # El tar de Windows (bsdtar) arma el zip con barras normales, como el del Android. Con la ruta entera: el de Git (GNU tar,
        # que también puede estar en el PATH) no sabe armar zip.
        & (Join-Path $env:SystemRoot "System32\tar.exe") -a -c -f (Join-Path $salida "bot.zip") src package.json config.example.json node_modules
        if ($LASTEXITCODE -ne 0) { throw "No se pudo armar bot.zip" }
    } finally { Pop-Location }
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }

# Que el bot cargue con este Node antes de dar el paquete por bueno: la base (SQLite incorporado) y la librería de WhatsApp.
Write-Output "Probando que el bot cargue con este Node..."
$prueba = Join-Path ([IO.Path]::GetTempPath()) ("bot-prueba-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $prueba | Out-Null
try {
    & (Join-Path $env:SystemRoot "System32\tar.exe") -x -f (Join-Path $salida "bot.zip") -C $prueba
    $js = @'
const path = require('path');
const { pathToFileURL } = require('url');
const dir = process.argv[2];
const db = require(path.join(dir, 'src', 'db', 'motor.js')).abrirBase(':memory:');
import(pathToFileURL(path.join(dir, 'node_modules', '@whiskeysockets', 'baileys', 'lib', 'index.js')).href)
  .then(() => console.log('El bot carga con Node ' + process.version + ' (base: ' + db.motor + ')'))
  .catch((e) => { console.error(e); process.exit(1); });
'@
    Set-Content -Path (Join-Path $prueba "probar.js") -Value $js -Encoding utf8
    & $node (Join-Path $prueba "probar.js") $prueba
    if ($LASTEXITCODE -ne 0) { throw "El bot no carga con el Node de Windows" }
} finally { Remove-Item -Recurse -Force $prueba -ErrorAction SilentlyContinue }

Get-ChildItem $salida | ForEach-Object { Write-Output ("{0}  {1:N1} MB" -f $_.Name, ($_.Length / 1MB)) }
