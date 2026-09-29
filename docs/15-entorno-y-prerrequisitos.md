# 15 · Entorno de desarrollo y prerrequisitos

Todo lo necesario **antes de escribir la primera línea de código** (fase F0) para tu caso: app personal para iPhone, **sin Mac**, con **Apple Developer Program** (TestFlight) y Coach IA con **Claude o Gemini**. Marca cada casilla al completarla.

## 1. Hardware

- [ ] **Google Fitbit Air** emparejada con la app **Google Health** y llevándola día y noche (idealmente ≥ 14 días antes de F1 para tener historial con el que calibrar).
- [ ] **iPhone con iOS 26 o posterior** con las apps Google Health y **TestFlight**.
- [ ] **Apple Watch** (opcional, para correr) grabando tus carreras con la app Entreno u otra que guarde en Salud.
- [ ] **Cualquier ordenador** (Windows, Linux o Mac) con navegador y editor de código. No hace falta Mac: la compilación de iOS se hace en GitHub Actions (doc. 08 §6).

## 2. Cuentas y servicios

| # | Cuenta / servicio | Para qué | Coste | Cuándo |
|---|---|---|---|---|
| 1 | Cuenta de Google (la de la Fitbit Air) | Fuente de datos | 0 € | F0 |
| 2 | **Apple Developer Program** ✅ (ya lo tienes) | App ID y capacidades (incluida **HealthKit** con entrega en segundo plano, para el Apple Watch), App Store Connect, **TestFlight**, clave de API para firmar y subir desde CI | 99 $/año (ya pagado) | F0 |
| 3 | **GitHub** (este repositorio, privado) | Código, PR, **GitHub Actions** (Linux y `macos-26` con Xcode 26) | 0 € con ≈ 200 min/mes de macOS (doc. 08 §6) | F0 |
| 4 | **Proyecto de Google Cloud** con la Google Health API, *Branding*/*Audience*/*Data Access* y **cliente OAuth de tipo iOS** | Leer los datos de la pulsera (doc. 10 §2) | 0 € (en principio sin facturación [verificar]) | F0 |
| 5 | Página de privacidad (p. ej. GitHub Pages) | Consentimiento de Google y declaración de *Limited Use* (RL-42) | 0 € | F0 |
| 6a | **Consola de Anthropic** (Claude): clave de API + límite de gasto | Coach IA con Claude | Pago por uso (doc. 06 §8) | F3 |
| 6b | **Google AI Studio / Google Cloud**: clave de la API de Gemini en un proyecto **con facturación activada** (nivel de pago) + límite de gasto + restricción de la clave a la API de Gemini | Coach IA con Gemini | Pago por uso (doc. 06 §8) | F3 |

Basta con una de las dos claves de IA (6a o 6b); con las dos puedes compararlas con la suite de evaluación. **No uses una clave de Gemini del nivel gratuito**: Google podría usar y revisar tus datos de salud (doc. 06 §7, RL-35).

**No hace falta**: Mac, Google Health Premium, servidores, bases de datos en la nube, dominio de pago ni analítica. Tampoco cambiar la conexión de Google Health con Salud si la tienes: la app evita los duplicados (doc. 16 §5).

## 3. Herramientas

| Herramienta | Dónde | Uso |
|---|---|---|
| VS Code o Cursor + extensión de Swift (o Claude Code) | Tu ordenador / la nube | Editar código; compilar y probar los paquetes puros (`MetricsKit`, lógica de `HealthAPI`) en Linux o Windows |
| Swift 6 (toolchain) | Tu ordenador (opcional) y CI | Tests de paquetes fuera de macOS |
| **XcodeGen** | CI de macOS | Generar el proyecto de Xcode desde `project.yml` (RNF-MAN-06) |
| Xcode 26 | Solo en el CI (`macos-26`) | Compilar, simulador, tests de UI e instantáneas, archivo y subida a TestFlight |
| SwiftLint + SwiftFormat | CI | Estilo y reglas del sistema de diseño (RNF-EST-01) |
| gitleaks | CI | Escaneo de secretos (RNF-SEG-07) |
| fastlane (opcional) | CI | Alternativa para firmar y subir a TestFlight si la vía con `xcodebuild` da problemas (RSK-15) |
| Python + Jupyter + pandas (opcional) | Tu ordenador | Analizar tus datos exportados para calibrar algoritmos |

Dependencias Swift previstas (licencia permisiva, a confirmar en F0): **GRDB** (SQLite), **Google Sign-In para iOS** o **AppAuth-iOS** (OAuth) y, para tests, **swift-snapshot-testing**. Sin SDK de analítica ni publicidad (RNF-PRI-02).

## 4. Configuración y secretos

**En la app** — plantilla [`Config/Secrets.example.xcconfig`](../Config/Secrets.example.xcconfig). En CI, [`scripts/write-secrets-xcconfig.sh`](../scripts/write-secrets-xcconfig.sh) genera `Config/Secrets.xcconfig` a partir de los secretos de GitHub (sin ellos usa valores de ejemplo y la app funciona en modo demostración); nunca se versiona.

| Clave | Descripción |
|---|---|
| `APP_BUNDLE_ID` | Identificador de la app (p. ej. `com.tunombre.recupera`) |
| `DEVELOPMENT_TEAM` | *Team ID* de tu cuenta de Apple Developer |
| `GOOGLE_IOS_CLIENT_ID` | *Client ID* del cliente OAuth de tipo iOS |
| `GOOGLE_REVERSED_CLIENT_ID` | Esquema de URL para la redirección OAuth |

**En GitHub Actions** — *Settings › Secrets and variables › Actions* (RNF-SEG-10):

| Secreto | Descripción |
|---|---|
| `ASC_KEY_ID` | ID de la clave de API de App Store Connect |
| `ASC_ISSUER_ID` | ID del emisor de la clave |
| `ASC_KEY_P8` | Contenido de la clave `.p8` tal cual, con las líneas `BEGIN` y `END` (también vale `ASC_KEY_P8_BASE64` con el archivo en base64) |
| `APPLE_TEAM_ID` | *Team ID* |
| `APP_BUNDLE_ID`, `GOOGLE_IOS_CLIENT_ID` | Para generar `Secrets.xcconfig`; `GOOGLE_REVERSED_CLIENT_ID` es opcional (se calcula a partir del *client ID*) |

El *workflow* **Comprobar configuración** (`preflight.yml`, en Linux) revisa todos estos secretos sin compilar: formato, que la clave de App Store Connect funciona, los dos App IDs con HealthKit y App Groups, la ficha de la app y el grupo de TestFlight. La guía completa, paso a paso, está en el [doc. 17](17-puesta-en-marcha.md).

**Claves de IA**: no van en ningún fichero ni secreto de CI. Las pegas en Ajustes de la app (Claude, Gemini o ambas) y se guardan en el Llavero (doc. 06 §3). Para la suite de evaluación (doc. 13 §7) se leen de variables de entorno locales o de secretos de CI solo al lanzarla a mano. Los *tokens* de Google viven solo en el Llavero.

## 5. Lista de tareas de F0 (en orden)

> Para instalar la app ya hecha, sigue el [doc. 17](17-puesta-en-marcha.md), que concreta los pasos 2–4 y 6 con cada pantalla y cada secreto.

1. [ ] Llevar la Fitbit Air 24/7 y comprobar en Google Health que aparecen sueño con fases, VFC, FC en reposo, SpO₂, frecuencia respiratoria y temperatura.
2. [ ] En **developer.apple.com**: crear el App ID con su *bundle ID* y las capacidades (App Groups con el grupo `group.<bundle ID>`; **HealthKit** con entrega en segundo plano, `com.apple.developer.healthkit.background-delivery`; AlarmKit si se usa [verificar requisitos de AlarmKit]), y un segundo App ID `<bundle ID>.widgets` para la extensión de *widgets* con el mismo App Group. Con la firma automática en la nube, Xcode puede crearlos solo si la clave de API tiene permisos suficientes.
3. [ ] En **App Store Connect**: crear la ficha de la app, añadirte como **probador interno** y crear una **clave de API** (rol mínimo que permita firmar y subir [verificar]); instalar la app **TestFlight** en el iPhone.
4. [ ] En **GitHub**: guardar los secretos del §4 y crear los *workflows* `ci-linux.yml` e `ios.yml` (doc. 08 §6) con una app mínima generada por XcodeGen. **Criterio**: un *merge* a `main` produce una *build* instalable en TestFlight.
5. [ ] Publicar la página de privacidad mínima (declaración de *Limited Use*, RL-42).
6. [ ] En **Google Cloud**: habilitar `health.googleapis.com`; completar *Branding*, *Audience* (*External*, *Testing*, tu cuenta como usuaria de prueba) y *Data Access* (ámbitos del doc. 10 §3); crear el cliente OAuth **iOS** con tu *bundle ID*.
7. [ ] ***Spike* de datos** en el iPhone (vía TestFlight): OAuth, descarga de 30 días de cada tipo, guardado local y exportación de un informe; lectura de Salud con 2–3 carreras reales del Apple Watch (corriendo también con la Fitbit Air); responder a las preguntas del doc. 03 §7 y del doc. 16 §9; probar el modo *In production* sin verificar (D-7) y la librería OAuth (doc. 10 §4). **Hito H0.**
8. [ ] Escribir los ADR 001–012 (doc. 08 §2) confirmando o ajustando cada decisión tras el *spike*.
9. [ ] Sistema de diseño base (tokens, anillos animados, tarjetas) con sus capturas automáticas revisadas con la checklist del doc. 11 §9.4.
10. [ ] Resolver las decisiones abiertas (doc. 01 §8).

## 6. Coste

| Concepto | Coste |
|---|---|
| Servidor, base de datos, Google Health Premium | **0 €** (no se usan) |
| Google Cloud y Google Health API | 0 € |
| Apple Developer Program (TestFlight) | 99 $/año (ya lo tienes) |
| GitHub Actions | 0 € dentro del cupo gratuito (≈ 200 min/mes de macOS); si no llega, ver D-11 |
| Coach IA | Pago por uso: con Gemini ≈ 0,5–1 $/mes y con Claude Opus 5.5 ≈ 2,7 $/mes haciendo una pregunta al día (doc. 06 §8) |
| **Coste nuevo obligatorio** | **0 €/mes** |
