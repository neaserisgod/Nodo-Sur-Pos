#!/bin/bash
# Compila el .apk más nuevo de la companion app y lo deja donde el servidor
# embebido de la PC lo busca para ofrecerlo al celular (sistema de
# actualización, 2026-09-07) — al lado de la base real (Documents), NO como
# asset del build de escritorio: un asset es compartido por todas las
# plataformas del proyecto, y el build de Android terminaba incluyéndose a
# sí mismo adentro suyo (bug real, `servidor_companion.dart` tiene el
# detalle). Correr desde la raíz del repo:
#   ./tool/publicar_actualizacion_companion.sh
#
# A propósito SIN --split-per-abi: Flutter le suma a cada arquitectura un
# multiplicador al build number para Play Store (arm64 = 2000 + build real,
# ej. build 3 queda "2003") — comparar esa versión contra la de la PC
# (sin ese multiplicador) siempre daba "distinta" aunque fueran la misma
# (bug real, encontrado por el dueño probando el sistema de actualización el
# mismo día que se armó). Un solo .apk para arm64 (el S24/S26 Ultra de
# El dueño) no tiene ese problema.
#
# El build number de pubspec.yaml se sube solo, acá — antes había que
# acordarse de hacerlo a mano antes de correr el script (El dueño, 2026-09-07:
# paso extra que se olvidaba). Y ya no hace falta reiniciar la app de
# escritorio para que el celular note la diferencia: la versión que
# compara `GET /companion/version` sale de un archivo chico al lado del
# .apk (`la_plazoleta_companion.version`), no de la app de escritorio que
# esté corriendo en ese momento (bug real, el dueño: "no hay manera de lanzar
# actualizaciones sin reiniciar la app desktop" — antes comparaba contra
# `PackageInfo.fromPlatform()` del propio proceso de escritorio, que solo
# cambia reconstruyendo y reiniciando ESE binario, sin relación con qué
# .apk se estaba sirviendo de verdad).
set -e

pubspec="pubspec.yaml"
version_actual=$(grep '^version:' "$pubspec" | sed -E 's/^version:[[:space:]]*//')
nombre="${version_actual%+*}"
build_actual="${version_actual##*+}"
build_nuevo=$((build_actual + 1))
version_nueva="$nombre+$build_nuevo"

sed -i "s/^version:.*/version: $version_nueva/" "$pubspec"

flutter build apk --release --target-platform android-arm64

destino="$USERPROFILE/Documents/la_plazoleta_companion.apk"
cp "build/app/outputs/flutter-apk/app-release.apk" "$destino"

version_destino="$USERPROFILE/Documents/la_plazoleta_companion.version"
printf '%s' "$version_nueva" > "$version_destino"

echo ""
echo "Listo: $destino actualizado a la versión $version_nueva."
echo "El celular ya puede notar la diferencia sin tocar la app de escritorio."
