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
for screen in today analysis recovery sleep strain activity health trends runs runs-training runs-workout runs-goal runs-risk runs-performance runs-records runs-segments run run-ai run-charts run-splits run-intervals run-segments run-form coach profile panel plan strength workout breathing alarm vo2 report; do
  shoot "$(printf '%02d' $n)-$screen" -RecuperaScreenshots -RecuperaScreen "$screen"
  n=$((n + 1))
done
shoot "$(printf '%02d' $n)-today-claro" -RecuperaScreenshots -RecuperaScreen today -RecuperaTheme light
xcrun simctl shutdown "$UDID" || true
ls -la "$OUT"
