#!/usr/bin/env python3
"""Espera a que App Store Connect procese una build y la deja lista en TestFlight (doc. 17, parte E).

Busca la build por su número (BUILD_NUMBER; si no se da, la última subida), espera a que termine el procesado (hasta
WAIT_MINUTES) y la añade a los grupos internos de TestFlight que no reciben las builds solos. Lee los secretos de las
variables de entorno y nunca los imprime. Termina con código 1 si Apple rechaza la build.
"""
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt  # PyJWT con cryptography


def env(name):
    return (os.environ.get(name) or "").strip()


def normalize_pem(text):
    """Rehace el PEM aunque se hayan perdido los saltos de línea al pegarlo (igual que preflight.py)."""
    body = re.sub(r"\s+", "", re.sub(r"-----(BEGIN|END) PRIVATE KEY-----", "", text))
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----\n"


bundle = env("APP_BUNDLE_ID")
key_id = env("ASC_KEY_ID")
issuer = env("ASC_ISSUER_ID")
p8 = env("ASC_KEY_P8") or env("ASC_KEY_P8_BASE64")
if p8 and "BEGIN PRIVATE KEY" not in p8:
    p8 = base64.b64decode(p8).decode()
build_number = env("BUILD_NUMBER")
wait_minutes = int(env("WAIT_MINUTES") or "40")
if not (bundle and key_id and issuer and p8):
    sys.exit("Faltan secretos: ejecuta «Comprobar configuración».")
key_pem = normalize_pem(p8)


def token():
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}, key_pem,
                      algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})


def api(path, params=None, body=None, attempts=4):
    """Una consulta a App Store Connect; reintenta los fallos pasajeros y corta con el mensaje de Apple si no."""
    url = "https://api.appstoreconnect.apple.com" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    for attempt in range(attempts):
        request = urllib.request.Request(url, method="POST" if body is not None else "GET",
                                         data=json.dumps(body).encode() if body is not None else None,
                                         headers={"Authorization": f"Bearer {token()}",
                                                  "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < attempts - 1:
                time.sleep(10 * 2 ** attempt)
                continue
            try:
                first = (json.loads(e.read().decode()).get("errors") or [{}])[0]
                detail = " ".join(x for x in (first.get("title"), first.get("detail")) if x)
            except Exception:
                detail = ""
            sys.exit(f"App Store Connect respondió HTTP {e.code} en {path}. {detail}".strip())
        except urllib.error.URLError as e:
            if attempt < attempts - 1:
                time.sleep(10 * 2 ** attempt)
                continue
            sys.exit(f"No se pudo contactar con App Store Connect ({e.reason}).")


def report(title, lines, code=0):
    print(title)
    print("\n".join(lines))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"## {title}\n\n" + "\n".join(f"- {line}" for line in lines) + "\n")
    sys.exit(code)


apps = api("/v1/apps", {"filter[bundleId]": bundle, "limit": 10}).get("data", [])
app = next((a for a in apps if a["attributes"].get("bundleId") == bundle), None)
if not app:
    report("❌ La app no existe en App Store Connect", ["Créala en Apps › + › Nueva app (doc. 17, parte B)."], 1)

# 1 · Esperar a que la build aparezca y Apple termine de procesarla
label = f"build {build_number}" if build_number else "última build"
deadline = time.time() + wait_minutes * 60
while True:
    params = {"filter[app]": app["id"], "sort": "-uploadedDate", "limit": 1, "include": "buildBetaDetail",
              "fields[buildBetaDetails]": "internalBuildState"}
    if build_number:
        params["filter[version]"] = build_number
    response = api("/v1/builds", params)
    build = next(iter(response.get("data", [])), None)
    beta = next((i["attributes"] for i in response.get("included", []) if i.get("type") == "buildBetaDetails"), {})
    state = build["attributes"].get("processingState") if build else "AÚN NO REGISTRADA"
    print(f"{time.strftime('%H:%M:%S')} {label}: {state}", flush=True)
    if build and state != "PROCESSING":
        break
    if time.time() > deadline:
        print("::warning::Apple sigue procesando la build")
        report(f"⚠️ La {label} aún no está lista",
               [f"Tras {wait_minutes} min sigue en «{state}»: Apple tiene cola. Te llegará un email cuando acabe; "
                "después lanza «Estado de TestFlight» para añadirla a tu grupo."])
    time.sleep(60)

attrs = build["attributes"]
name = f"{app['attributes'].get('name')} {attrs.get('version')}"
if attrs.get("processingState") != "VALID":
    report(f"❌ Apple no ha aceptado la build {attrs.get('version')}",
           [f"Estado «{attrs.get('processingState')}». El motivo está en el email de App Store Connect."], 1)

# 2 · Añadirla a los grupos internos que no reciben todas las builds solos
done, todo = [f"✅ {name} procesada por Apple."], []
if beta.get("internalBuildState") == "MISSING_EXPORT_COMPLIANCE":
    todo.append("⚠️ Apple pide la declaración de cifrado: App Store Connect › TestFlight › la build › «Gestionar».")
groups = api("/v1/betaGroups", {"filter[app]": app["id"], "filter[isInternalGroup]": "true", "limit": 10}).get("data", [])
if not groups:
    todo.append("⚠️ No hay grupo interno: créalo en App Store Connect › TestFlight › Pruebas internas, añádete y "
                "vuelve a lanzar «Estado de TestFlight».")
for group in groups:
    group_name = group["attributes"].get("name")
    if group["attributes"].get("hasAccessToAllBuilds"):
        done.append(f"✅ El grupo «{group_name}» recibe todas las builds.")
    else:
        linked = api(f"/v1/betaGroups/{group['id']}/relationships/builds", {"limit": 200}).get("data", [])
        if all(item["id"] != build["id"] for item in linked):
            api(f"/v1/betaGroups/{group['id']}/relationships/builds", body={"data": [{"type": "builds", "id": build["id"]}]})
        done.append(f"✅ Build añadida al grupo «{group_name}».")
    testers = api(f"/v1/betaGroups/{group['id']}/betaTesters", {"limit": 200, "fields[betaTesters]": "email"}).get("data", [])
    if not testers:
        todo.append(f"⚠️ El grupo «{group_name}» no tiene probadores: añádete en App Store Connect › TestFlight › "
                    f"{group_name}.")

if todo:
    report(f"⚠️ {name} procesada: falta un paso en TestFlight", done + todo)
report(f"{name} en TestFlight", done + ["Instálala desde la app TestFlight del iPhone (doc. 17, parte F)."])
