# 15 · Entorno de desarrollo y prerrequisitos

Todo lo necesario **antes de escribir la primera línea de código** (fase F0), pensado para una app **personal para iPhone y sin coste mensual**. Marca cada casilla al completarla.

## 1. Hardware

- [ ] **Google Fitbit Air** emparejada con la app **Google Health** y llevándola día y noche (idealmente ≥ 14 días antes de F1 para tener historial con el que calibrar).
- [ ] **iPhone con iOS 26 o posterior** (iPhone 11 o posterior) con la app Google Health.
- [ ] **Mac con Apple Silicon** y Xcode para compilar y probar (recomendado). Sin Mac: ver la opción C del doc. 08 §6 (compilación en GitHub Actions + SideStore).

## 2. Cuentas y servicios

| # | Cuenta / servicio | Para qué | Coste | Cuándo |
|---|---|---|---|---|
| 1 | Cuenta de Google (la de la Fitbit Air) | Fuente de datos | 0 € | F0 |
| 2 | **Proyecto de Google Cloud** con la Google Health API habilitada, *Branding*/*Audience*/*Data Access* configurados y **cliente OAuth de tipo iOS** | Leer los datos de la pulsera desde la app (doc. 10 §2) | 0 € (en principio sin facturación [verificar]) | F0 |
| 3 | Página de privacidad (p. ej. GitHub Pages) | Enlace en la pantalla de consentimiento y declaración de *Limited Use* (RL-42) | 0 € | F0 |
| 4 | **Apple ID** (gratuito) **o Apple Developer Program** | Instalar la app en tu iPhone: gratis con reinstalación cada 7 días, o 99 $/año sin caducidad semanal (doc. 08 §6) | 0 € o 99 $/año | F0 |
| 5 | GitHub (este repositorio) | Código, CI (Actions), tablero | 0 € | F0 |
| 6 | Anthropic Console + clave de API + límite de gasto | Coach IA (**opcional**) | Pago por uso (~2 $/mes con 1 pregunta al día, doc. 06 §8) | F3 |

**No hace falta**: Google Health Premium, servidores, bases de datos en la nube, dominio de pago ni cuentas de analítica.

## 3. Herramientas

| Herramienta | Versión | Uso |
|---|---|---|
| **Xcode** | 26 o posterior | Compilar, simulador, SwiftUI Previews, Instruments |
| Swift | 6 (concurrencia estricta) | Lenguaje |
| XcodeGen o Tuist | reciente (opcional) | Generar el proyecto desde `project.yml` (RNF-MAN-06) |
| SwiftLint + SwiftFormat | reciente | Estilo y reglas del sistema de diseño (RNF-EST-01) |
| App **SF Symbols** | reciente | Iconografía |
| Git + gitleaks + pre-commit | reciente | Control de versiones y escaneo de secretos (RNF-SEG-07) |
| Python + Jupyter + pandas | 3.12+ (opcional) | Análisis de tus datos exportados para calibrar algoritmos |

Dependencias Swift previstas (todas con licencia permisiva, a confirmar en F0): **GRDB** (SQLite), **Google Sign-In para iOS** o **AppAuth-iOS** (OAuth), y para tests **swift-snapshot-testing**. Nada de SDK de analítica o publicidad (RNF-PRI-02).

## 4. Configuración y secretos

Plantilla en [`Config/Secrets.example.xcconfig`](../Config/Secrets.example.xcconfig); la copia real `Config/Secrets.xcconfig` está en `.gitignore`.

| Clave | Descripción | ¿Secreta? |
|---|---|---|
| `APP_BUNDLE_ID` | Identificador de la app (p. ej. `com.tunombre.recupera`) | No |
| `DEVELOPMENT_TEAM` | *Team ID* de tu cuenta de Apple | No |
| `GOOGLE_IOS_CLIENT_ID` | *Client ID* del cliente OAuth de tipo iOS | No (los clientes iOS son públicos), pero no se sube por limpieza |
| `GOOGLE_REVERSED_CLIENT_ID` | Esquema de URL para la redirección OAuth | No |

La **clave de la API de Anthropic** no va en ningún fichero: la pegas en Ajustes de la app y se guarda en el Llavero (doc. 06 §3). Los *tokens* de Google también viven solo en el Llavero.

## 5. Lista de tareas de F0 (en orden)

1. [ ] Llevar la Fitbit Air 24/7 y comprobar en Google Health que aparecen sueño con fases, VFC, FC en reposo, SpO₂, frecuencia respiratoria y temperatura.
2. [ ] Instalar Xcode (o preparar la opción sin Mac) y comprobar que puedes instalar una app de prueba en tu iPhone con tu Apple ID.
3. [ ] Publicar la página de privacidad mínima (con la declaración de *Limited Use*, RL-42).
4. [ ] Crear el proyecto de Google Cloud, habilitar `health.googleapis.com`, completar *Branding*, *Audience* (*External*, *Testing*, tu cuenta como usuaria de prueba) y *Data Access* (ámbitos del doc. 10 §3), y crear el cliente OAuth **iOS** con tu *bundle ID*.
5. [ ] ***Spike* de datos**: prototipo mínimo en el iPhone que haga el OAuth, descargue 30 días de cada tipo y los guarde en local; medir granularidad, latencia y huecos y responder a las preguntas del doc. 03 §7. Probar el modo *In production* sin verificar (D-7) y la librería OAuth (doc. 10 §4). **Hito H0.**
6. [ ] Crear la estructura del repositorio (doc. 08 §5), CI con tests de `MetricsKit` y gitleaks, y plantilla de PR con referencias a requisitos.
7. [ ] Escribir los ADR 001–010 (doc. 08 §2) confirmando o ajustando cada decisión tras el *spike*.
8. [ ] Construir el sistema de diseño base (tokens, anillos animados, tarjetas) y validarlo con la checklist del doc. 11 §9.4.
9. [ ] Resolver las decisiones abiertas (doc. 01 §8).

## 6. Coste

| Concepto | Coste |
|---|---|
| Servidor, base de datos, Google Health Premium | **0 €** (no se usan) |
| Proyecto de Google Cloud y Google Health API | 0 € |
| Instalación en tu iPhone | 0 € (reinstalar cada 7 días) **o** 99 $/año (Apple Developer Program) |
| Coach IA (opcional) | Pago por uso: ~2 $/mes con 1 pregunta al día; 0 € si no se activa |
| **Total obligatorio** | **0 €/mes** |
