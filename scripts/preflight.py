#!/usr/bin/env python3
"""Comprueba la configuración para compilar e instalar Recupera con TestFlight (doc. 17).

Lee los secretos de las variables de entorno y nunca los imprime. Comprueba el formato de cada uno, que la clave de
App Store Connect funciona, que los dos App IDs existen con sus capacidades, que la app está creada en App Store Connect
y si hay grupo interno de TestFlight. Termina con código 1 si falta algo imprescindible.
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

results = []


def ok(text):
    results.append(("✅", text))


def warn(text):
    results.append(("⚠️", text))


def fail(text):
    results.append(("❌", text))


def env(name):
    return (os.environ.get(name) or "").strip()


bundle = env("APP_BUNDLE_ID")
team = env("APPLE_TEAM_ID")
client = env("GOOGLE_IOS_CLIENT_ID")
reversed_given = env("GOOGLE_REVERSED_CLIENT_ID")
key_id = env("ASC_KEY_ID")
issuer = env("ASC_ISSUER_ID")
p8_raw = env("ASC_KEY_P8")
p8_b64 = env("ASC_KEY_P8_BASE64")

# 1 · Identificador de la app
bundle_ok = False
if not bundle:
    fail("Falta el secreto APP_BUNDLE_ID (tu identificador, p. ej. com.tunombre.recupera).")
elif bundle.startswith("com.example") or not re.fullmatch(r"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+", bundle):
    fail("APP_BUNDLE_ID no es válido: usa uno propio como com.tunombre.recupera (letras, números, puntos y guiones).")
else:
    bundle_ok = True
    ok("APP_BUNDLE_ID con formato correcto (los widgets usan el mismo más «.widgets» y el App Group es «group.» + el mismo).")

# 2 · Equipo de Apple
if not team:
    fail("Falta APPLE_TEAM_ID (developer.apple.com › Account › Membership details › Team ID).")
elif not re.fullmatch(r"[A-Z0-9]{10}", team):
    fail("APPLE_TEAM_ID debe tener 10 caracteres (letras mayúsculas y números).")
else:
    ok("APPLE_TEAM_ID con formato correcto.")

# 3 · Cliente OAuth de Google (tipo iOS)
match = re.fullmatch(r"([0-9]+-[a-z0-9]+)\.apps\.googleusercontent\.com", client)
if not client:
    fail("Falta GOOGLE_IOS_CLIENT_ID (Google Cloud › Google Auth Platform › Clients › cliente de tipo iOS).")
elif not match:
    fail("GOOGLE_IOS_CLIENT_ID no tiene el formato 123456789-abc….apps.googleusercontent.com: ¿has copiado el Client ID del cliente iOS?")
else:
    derived = "com.googleusercontent.apps." + match.group(1)
    if reversed_given and reversed_given != derived:
        fail("GOOGLE_REVERSED_CLIENT_ID no corresponde al Client ID. Puedes borrar ese secreto: la compilación lo calcula sola.")
    else:
        ok("GOOGLE_IOS_CLIENT_ID con formato correcto (el esquema de redirección se calcula solo).")

# 4 · Clave de la API de App Store Connect


def normalize_pem(text):
    """Rehace el PEM aunque se hayan perdido los saltos de línea o sobren espacios al pegarlo."""
    body = re.sub(r"-----(BEGIN|END) PRIVATE KEY-----", "", text)
    body = re.sub(r"\s+", "", body)
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----\n"


key_pem = None
if p8_raw:
    key_pem = normalize_pem(p8_raw)
elif p8_b64:
    if "BEGIN PRIVATE KEY" in p8_b64:
        key_pem = normalize_pem(p8_b64)
    else:
        try:
            key_pem = normalize_pem(base64.b64decode(p8_b64).decode())
        except Exception:
            fail("ASC_KEY_P8_BASE64 no es base64 válido. Más fácil: crea el secreto ASC_KEY_P8 y pega el .p8 tal cual.")
else:
    fail("Falta la clave .p8: crea el secreto ASC_KEY_P8 y pega el contenido completo del archivo AuthKey_XXXXXXXXXX.p8.")
if not key_id:
    fail("Falta ASC_KEY_ID (el Key ID de la clave, en App Store Connect › Integraciones).")
elif not re.fullmatch(r"[A-Z0-9]{10}", key_id):
    fail("ASC_KEY_ID debe tener 10 caracteres (letras mayúsculas y números).")
if not issuer:
    fail("Falta ASC_ISSUER_ID (el Issuer ID, encima de la tabla de claves).")
elif not re.fullmatch(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", issuer.lower()):
    fail("ASC_ISSUER_ID debe ser un UUID como 69a6de8f-1234-…")

token = None
if key_pem and key_id and issuer:
    try:
        import jwt  # PyJWT con cryptography

        now = int(time.time())
        token = jwt.encode({"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}, key_pem,
                           algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})
        ok("La clave .p8 se lee bien.")
    except Exception as e:  # clave mal copiada, cortada, etc.
        fail(f"La clave .p8 no se puede leer ({type(e).__name__}): copia el archivo entero, con las líneas BEGIN y END.")


def api(path, params=None):
    url = "https://api.appstoreconnect.apple.com" + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def apple_detail(error):
    """Mensaje de error de App Store Connect (no contiene secretos)."""
    try:
        body = json.loads(error.read().decode())
        first = (body.get("errors") or [{}])[0]
        return " ".join(x for x in (first.get("title"), first.get("detail")) if x)
    except Exception:
        return ""


def call(label, path, params):
    """Una consulta a App Store Connect; si falla, lo anota y devuelve None sin cortar el resto."""
    try:
        return api(path, params)
    except urllib.error.HTTPError as e:
        detail = apple_detail(e)
        if e.code in (401, 403):
            fail(f"{label}: App Store Connect no deja consultarlo (HTTP {e.code}); revisa ASC_KEY_ID, ASC_ISSUER_ID y que la clave "
                 f"tenga acceso Admin. {detail}".strip())
        else:
            fail(f"{label}: App Store Connect respondió HTTP {e.code}. {detail}".strip())
    except urllib.error.URLError as e:
        warn(f"{label}: no se pudo contactar con App Store Connect ({e.reason}).")
    return None


NAMES = {"HEALTHKIT": "HealthKit", "APP_GROUPS": "App Groups"}


def capabilities_by_identifier(response):
    """{identificador: {capacidades}} a partir de /v1/bundleIds con include=bundleIdCapabilities."""
    caps = {c["id"]: c.get("attributes", {}).get("capabilityType")
            for c in response.get("included", []) if c.get("type") == "bundleIdCapabilities"}
    out = {}
    for item in response.get("data", []):
        rel = item.get("relationships", {}).get("bundleIdCapabilities", {}).get("data") or []
        out[item["attributes"].get("identifier")] = {caps.get(r.get("id")) for r in rel}
    return out


def check_app_ids(found):
    for ident, needs, label in ((bundle, ("HEALTHKIT", "APP_GROUPS"), "App ID de la app"),
                                (bundle + ".widgets", ("APP_GROUPS",), "App ID de los widgets")):
        if ident not in found:
            fail(f"{label} sin registrar: créalo en developer.apple.com › Identifiers (doc. 17, parte A).")
            continue
        missing = [NAMES[c] for c in needs if c not in found[ident]]
        if missing:
            fail(f"{label}: falta activar {', '.join(missing)} en su App ID.")
        else:
            ok(f"{label} registrado con {' y '.join(NAMES[c] for c in needs)}.")


if token and bundle_ok:
    ids = call("App IDs", "/v1/bundleIds", {"filter[identifier]": f"{bundle},{bundle}.widgets", "include": "bundleIdCapabilities",
                                            "fields[bundleIdCapabilities]": "capabilityType", "limit[bundleIdCapabilities]": 50,
                                            "limit": 200})
    if ids is not None:
        ok("App Store Connect acepta la clave.")
        check_app_ids(capabilities_by_identifier(ids))
    apps = call("Ficha de la app", "/v1/apps", {"filter[bundleId]": bundle, "limit": 10})
    if apps is not None:
        app = next((a for a in apps.get("data", []) if a["attributes"].get("bundleId") == bundle), None)
        if not app:
            fail("La app no existe en App Store Connect con ese identificador: créala en Apps › + › Nueva app (parte B).")
        else:
            ok(f"App creada en App Store Connect («{app['attributes'].get('name')}»).")
            groups = call("Grupo de TestFlight", "/v1/betaGroups",
                          {"filter[app]": app["id"], "filter[isInternalGroup]": "true", "limit": 10})
            if groups is not None:
                if groups.get("data"):
                    ok("Grupo interno de TestFlight creado.")
                else:
                    warn("Aún no hay grupo interno de TestFlight: créalo y añádete (se puede hacer tras la primera subida).")

lines = [f"{mark} {text}" for mark, text in results]
failed = any(mark == "❌" for mark, _ in results)
title = "Falta algo por configurar" if failed else "Todo listo para subir a TestFlight"
print(title)
print("\n".join(lines))
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a", encoding="utf-8") as f:
        f.write(f"## {title}\n\n" + "\n".join(f"- {line}" for line in lines) + "\n")
sys.exit(1 if failed else 0)
