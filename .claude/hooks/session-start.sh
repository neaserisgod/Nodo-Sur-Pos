#!/bin/bash
# Deja Flutter listo en las sesiones de Claude en la nube (el contenedor no lo trae). La versión sale de
# .github/workflows/tests.yml, así CI y la sesión usan siempre la misma. Idempotente: si ya está, solo hace pub get.
set -euo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
VERSION=$(grep -m1 -oP 'flutter-version:\s*\K[0-9.]+' .github/workflows/tests.yml)
DESTINO="$HOME/flutter-$VERSION"

if [ ! -x "$DESTINO/bin/flutter" ]; then
  echo "Instalando Flutter $VERSION..." >&2
  TMP=$(mktemp -d)
  curl -sSfL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${VERSION}-stable.tar.xz" \
    | tar -xJ -C "$TMP"
  mv "$TMP/flutter" "$DESTINO"
  rmdir "$TMP"
  git config --global --add safe.directory "$DESTINO"
fi

export PATH="$DESTINO/bin:$PATH"
[ -n "${CLAUDE_ENV_FILE:-}" ] && echo "export PATH=\"$DESTINO/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"

flutter config --no-analytics >/dev/null 2>&1 || true
flutter --suppress-analytics pub get >/dev/null
echo "Flutter $VERSION listo." >&2
