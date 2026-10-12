#!/usr/bin/env bash
# Baja los dos archivos que necesita la base de datos en el navegador (Nodo Sur Servicios web, `docs/PLAN-WEB-SERVICIOS.md`):
# SQLite compilado a WebAssembly y el worker de drift. Tienen que ser de la MISMA versión que los paquetes `sqlite3` y `drift`
# de pubspec.lock (si no, la base no abre), por eso se leen de ahí y no se guardan en el repo. Correr antes de
# `flutter build web` (el workflow de publicación lo hace solo).
set -euo pipefail
cd "$(dirname "$0")/.."
version() { awk -v p="$1" '$0 ~ "^  "p":$" {f=1} f && /version:/ {gsub(/"/, "", $2); print $2; exit}' pubspec.lock; }
SQLITE=$(version sqlite3); DRIFT=$(version drift)
[ -n "$SQLITE" ] && [ -n "$DRIFT" ] || { echo "No encontré las versiones de sqlite3/drift en pubspec.lock" >&2; exit 1; }
curl -fsSL -o web/sqlite3.wasm "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE/sqlite3.wasm"
curl -fsSL -o web/drift_worker.js "https://github.com/simolus3/drift/releases/download/drift-$DRIFT/drift_worker.js"
echo "web/sqlite3.wasm ($SQLITE) y web/drift_worker.js ($DRIFT) listos."
