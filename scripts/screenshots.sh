#!/usr/bin/env bash
# Capturas de pantalla de la app en el simulador con datos de demostración (doc. 11 §9.3, RNF-EST-05).
# Uso: scripts/screenshots.sh <ruta/Recupera.app> [carpeta de salida]
set -euo pipefail
APP="$1"
OUT="${2:-screenshots}"
WAIT="${WAIT:-14}"
mkdir -p "$OUT"

BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    if "iOS" not in runtime:
        continue
    for d in items:
        name = d["name"]
        if not name.startswith("iPhone"):
            continue
        score = (runtime, name == "iPhone 17 Pro", "Pro" in name and "Max" not in name)
        if best is None or score > best[0]:
            best = (score, d["udid"], name, runtime)
print(best[1])
print(best[2] + " · " + best[3], file=sys.stderr)
')
echo "Simulador: $UDID"

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"

shoot() {
  local name="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$WAIT"
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null 2>&1
  echo "Captura: $name"
}

# Primero el onboarding (instalación limpia); después cada pantalla con datos de demostración.
shoot 00-onboarding
n=1
for screen in today analysis recovery sleep strain activity health trends runs runs-training runs-workout runs-goal runs-risk runs-performance runs-records runs-segments run run-ai run-charts run-splits run-intervals run-segments run-form coach profile faces face-editor panel plan strength workout breathing alarm vo2 report; do
  shoot "$(printf '%02d' $n)-$screen" -RecuperaScreenshots -RecuperaScreen "$screen"
  n=$((n + 1))
done
shoot "$(printf '%02d' $n)-today-claro" -RecuperaScreenshots -RecuperaScreen today -RecuperaTheme light
xcrun simctl shutdown "$UDID" || true

# Esferas del Apple Watch (doc. 19): la app del reloj en su simulador, cada plantilla con datos de ejemplo a las 10:09:30.
WATCH_APP="$APP/Watch/RecuperaWatch.app"
[ -d "$WATCH_APP" ] || WATCH_APP="$(dirname "$APP")/../Debug-watchsimulator/RecuperaWatch.app"
if [ -d "$WATCH_APP" ]; then
  WUDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    if "watchOS" not in runtime:
        continue
    for d in items:
        name = d["name"]
        score = (runtime, "Series" in name, "46mm" in name or "45mm" in name)
        if best is None or score > best[0]:
            best = (score, d["udid"], name, runtime)
print(best[1] if best else "")
if best: print(best[2] + " · " + best[3], file=sys.stderr)
')
  if [ -n "$WUDID" ]; then
    echo "Simulador del reloj: $WUDID"
    xcrun simctl boot "$WUDID" 2>/dev/null || true
    xcrun simctl bootstatus "$WUDID" -b
    xcrun simctl install "$WUDID" "$WATCH_APP"
    WBUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$WATCH_APP/Info.plist")
    shoot_watch() {
      local name="$1"; shift
      xcrun simctl terminate "$WUDID" "$WBUNDLE" >/dev/null 2>&1 || true
      xcrun simctl launch "$WUDID" "$WBUNDLE" "$@" >/dev/null || { echo "No se pudo abrir la app del reloj ($name)"; return 0; }
      sleep "${WATCH_WAIT:-10}"
      xcrun simctl io "$WUDID" screenshot "$OUT/$name.png" >/dev/null 2>&1 || true
      echo "Captura: $name"
    }
    for face in ultraModular wayfinder recovery analog digital; do
      shoot_watch "watch-$face" -RecuperaScreenshots -RecuperaFace "$face"
    done
    shoot_watch "watch-ultraModular-noche" -RecuperaScreenshots -RecuperaFace ultraModular -RecuperaNight
    shoot_watch "watch-wayfinder-noche" -RecuperaScreenshots -RecuperaFace wayfinder -RecuperaNight
    xcrun simctl shutdown "$WUDID" || true
  else
    echo "No hay simulador de Apple Watch: sin capturas del reloj."
  fi
else
  echo "No está la app del reloj en $WATCH_APP: sin capturas del reloj."
fi
ls -la "$OUT"
