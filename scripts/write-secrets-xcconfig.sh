#!/usr/bin/env bash
# Genera Config/Secrets.xcconfig a partir de variables de entorno (secretos de GitHub en CI).
# Sin secretos, usa valores de ejemplo: la app compila y funciona en modo demostración.
set -euo pipefail
cd "$(dirname "$0")/.."
# El esquema de redirección de Google es el Client ID «al revés»: se calcula si no se da.
GOOGLE_REVERSED_CLIENT_ID="${GOOGLE_REVERSED_CLIENT_ID:-}"
if [ -z "$GOOGLE_REVERSED_CLIENT_ID" ] && [ -n "${GOOGLE_IOS_CLIENT_ID:-}" ]; then
  GOOGLE_REVERSED_CLIENT_ID="com.googleusercontent.apps.${GOOGLE_IOS_CLIENT_ID%.apps.googleusercontent.com}"
fi
cat > Config/Secrets.xcconfig <<XCCONFIG
// Generado por scripts/write-secrets-xcconfig.sh (no se versiona).
APP_BUNDLE_ID = ${APP_BUNDLE_ID:-com.example.recupera}
DEVELOPMENT_TEAM = ${APPLE_TEAM_ID:-}
GOOGLE_IOS_CLIENT_ID = ${GOOGLE_IOS_CLIENT_ID:-}
GOOGLE_REVERSED_CLIENT_ID = ${GOOGLE_REVERSED_CLIENT_ID}
XCCONFIG
echo "Config/Secrets.xcconfig generado (bundle ${APP_BUNDLE_ID:-com.example.recupera})."
