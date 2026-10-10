#!/usr/bin/env bash
# Prueba: el bot de WhatsApp adentro del APK, sin Termux (El dueño, 2026-10-10).
#
# Arma lo que el APK necesita para correr Node en el celular:
#  * android/app/src/main/jniLibs/arm64-v8a/libns_*.so: el Node 24 que Termux compila para Android (aarch64) y sus librerías.
#    Android solo empaqueta archivos `lib*.so`, y solo deja ejecutar lo que queda en la carpeta de librerías de la app: por eso el
#    ejecutable se llama libns_node.so y a las librerías se les cambia el nombre (sin versión, con prefijo ns_ para no chocar con
#    las de otros plugins) y se les saca la ruta de Termux (patchelf).
#  * assets/bot/bot.zip: el JavaScript (Baileys y el script de prueba), que la app descomprime la primera vez (Dart, `archive`).
#
# Nada de esto va al repo (.gitignore): pesa ~110 MB. Lo corre el workflow antes de compilar, o a mano para compilar local.
# Necesita: curl, ar, tar, zip, npm y patchelf (apt install patchelf o pip install patchelf).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=https://packages.termux.dev/apt/termux-main
TMP=$(mktemp -d)
LIBS=android/app/src/main/jniLibs/arm64-v8a
ASSETS=assets/bot
rm -rf "$LIBS" && mkdir -p "$LIBS" "$ASSETS"

curl -fsSL -o "$TMP/Packages" "$REPO/dists/stable/main/binary-aarch64/Packages"
for p in nodejs-lts libc++ openssl c-ares libicu libsqlite zlib; do
  f=$(awk -v p="$p" '$0=="Package: "p{f=1} f&&/^Filename:/{print $2; exit}' "$TMP/Packages")
  echo "Bajando $p ($f)"
  curl -fsSL -o "$TMP/$p.deb" "$REPO/$f"
  mkdir -p "$TMP/x/$p" && (cd "$TMP/x/$p" && ar x "../../$p.deb" && tar xf data.tar.*)
done
P=data/data/com.termux/files/usr

# nombre original (DT_NEEDED de Termux) → nombre en el APK, y de qué paquete sale
declare -A NUEVO=( [libz.so.1]=libns_z.so [libcares.so]=libns_cares.so [libsqlite3.so]=libns_sqlite3.so [libcrypto.so.3]=libns_crypto.so
  [libssl.so.3]=libns_ssl.so [libicui18n.so.78]=libns_icui18n.so [libicuuc.so.78]=libns_icuuc.so [libicudata.so.78]=libns_icudata.so
  [libc++_shared.so]=libns_cxx.so )
declare -A PAQUETE=( [libz.so.1]=zlib [libcares.so]=c-ares [libsqlite3.so]=libsqlite [libcrypto.so.3]=openssl [libssl.so.3]=openssl
  [libicui18n.so.78]=libicu [libicuuc.so.78]=libicu [libicudata.so.78]=libicu [libc++_shared.so]=libc++ )
for k in "${!NUEVO[@]}"; do
  [ -e "$TMP/x/${PAQUETE[$k]}/$P/lib/$k" ] || { echo "Falta $k: ¿cambió la versión en Termux? Actualizá la tabla de este script."; exit 1; }
  cp -L "$TMP/x/${PAQUETE[$k]}/$P/lib/$k" "$LIBS/${NUEVO[$k]}"
done
cp "$TMP/x/nodejs-lts/$P/bin/node" "$LIBS/libns_node.so"
for f in "$LIBS"/*.so; do
  patchelf --remove-rpath "$f"
  [ "$(basename "$f")" = libns_node.so ] || patchelf --set-soname "$(basename "$f")" "$f"
  for k in "${!NUEVO[@]}"; do
    if readelf -d "$f" | grep -q "NEEDED.*\[$k\]"; then patchelf --replace-needed "$k" "${NUEVO[$k]}" "$f"; fi
  done
done
# Ninguna librería puede seguir pidiendo un nombre de Termux.
if readelf -d "$LIBS"/*.so | grep -E "NEEDED" | grep -vE "\[(libc|libm|libdl|liblog|libns_[a-z0-9_]+)\.so\]"; then
  echo "Quedó una dependencia sin renombrar (arriba)"; exit 1
fi

# El JavaScript: Baileys y el script de prueba, sin dependencias opcionales (son nativas y no hacen falta).
rm -rf "$TMP/js" && mkdir -p "$TMP/js" && cp tool/bot_android/package.json tool/bot_android/package-lock.json tool/bot_android/prueba.js "$TMP/js/"
(cd "$TMP/js" && npm ci --omit=optional --omit=dev --no-audit --no-fund >/dev/null)
rm -f "$ASSETS/bot.zip" && (cd "$TMP/js" && zip -qr - prueba.js package.json node_modules) > "$ASSETS/bot.zip"
du -sh "$LIBS" "$ASSETS/bot.zip"
rm -rf "$TMP"
