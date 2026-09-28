# 15 · Entorno de desarrollo y prerrequisitos

Todo lo que hay que tener **antes de escribir la primera línea de código** (fase F0), con su coste aproximado. Marca cada casilla al completarla.

## 1. Hardware

- [ ] **Google Fitbit Air** emparejada con la app **Google Health** y llevándose día y noche (idealmente ≥ 14 días antes de F1 para tener historial con el que calibrar).
- [ ] **Teléfono** iOS o Android con la app Google Health (el mismo en el que se probará nuestra app; si se quiere Health Connect, Android).
- [ ] **Ordenador**: Linux/Windows/macOS para backend y Android. Para compilar iOS en local hace falta **macOS con Xcode**; alternativa sin Mac: compilación en la nube con **EAS Build**.

## 2. Cuentas y servicios

| # | Cuenta / servicio | Para qué | Coste aprox. | Obligatorio en |
|---|---|---|---|---|
| 1 | Cuenta de Google (la vinculada a la Fitbit Air) | Fuente de datos y usuario de pruebas | 0 € | F0 |
| 2 | **Proyecto de Google Cloud** con facturación activada | Habilitar la Google Health API, credenciales OAuth, alojamiento (Cloud Run, Cloud SQL, KMS…) | Uso personal: nivel gratuito + ~10–25 €/mes por Cloud SQL | F0 |
| 3 | **Google Health API** (`health.googleapis.com`) habilitada + Google Auth Platform (*Branding*, *Audience*, *Data Access*) + cliente OAuth web + cuenta de servicio para *webhooks* | Leer los datos de la pulsera (detalle en [doc. 10](10-integracion-google-health-api.md)). Sin verificación: máx. 100 usuarios | 0 € (la verificación CASA para publicar cuesta 500–4 500 $/año, solo F4) | F0 |
| 4 | Dominio propio (p. ej. `miapp.es`) + web estática | Dominio autorizado de OAuth, página de inicio, política de privacidad y condiciones (Google las exige en la pantalla de consentimiento) | ~10–15 €/año; hosting estático gratuito (GitHub Pages, Cloudflare Pages, Firebase Hosting) | F0 |
| 5 | **Anthropic Console** (organización + clave de API + límite de gasto) | Coach IA | Pago por uso (~8–25 $/mes personal, doc. 06 §8) | F3 |
| 6 | **Apple Developer Program** | TestFlight, App Store, Sign in with Apple, instalar la app en el iPhone sin caducidad de 7 días | 99 $/año | F1 si se usa iPhone |
| 7 | **Google Play Console** | Pista de pruebas internas y publicación | 25 $ pago único (para uso personal basta instalar el APK) | F1 (opcional) / F4 |
| 8 | Cuenta de **Expo** (EAS) | Builds en la nube, actualizaciones, notificaciones *push* | Plan gratuito suficiente al inicio | F1 |
| 9 | GitHub (este repositorio) | Código, CI (Actions), *issues*, proyectos | Gratuito | F0 |
| 10 | Sentry (u otro) | *Crash reporting* y errores (con *scrubbing* de datos de salud) | Plan gratuito | F1 |

> La **suscripción Google Health Premium** no se asume necesaria para leer los datos brutos; se confirmará en el *spike* (SUP-4 del doc. 01).

## 3. Herramientas locales

| Herramienta | Versión recomendada | Uso |
|---|---|---|
| Git | reciente | Control de versiones |
| **Node.js** | 24 LTS | Backend, herramientas, app |
| **pnpm** | 10.x | Gestor de paquetes del monorepo |
| **Docker** (Desktop o Engine) + Compose | reciente | PostgreSQL y servicios locales |
| **PostgreSQL** | 17 o 18 (en Docker) | Base de datos |
| Expo CLI / EAS CLI | últimas (`npx expo`, `npm i -g eas-cli`) | App móvil |
| **Android Studio** + SDK + emulador | última estable | Compilar/probar Android; Health Connect en emulador |
| **Xcode** (solo macOS) | última estable | Compilar/probar iOS en local |
| Google Cloud CLI (`gcloud`) | reciente | Proyecto, despliegues, secretos |
| Terraform | ≥ 1.9 (opcional) | Infraestructura como código (RNF-MAN-07) |
| Python + Jupyter + pandas | 3.12+ (opcional) | Análisis exploratorio y calibración de algoritmos con datos exportados |
| gitleaks + pre-commit | reciente | Evitar subir secretos (RNF-SEG-09) |
| Editor (VS Code o similar) + ESLint/Prettier | — | Desarrollo |
| Maestro | reciente | Pruebas E2E móviles |

## 4. Variables de entorno

Plantilla en [`.env.example`](../.env.example). Nunca se suben valores reales al repositorio.

| Variable | Descripción | Dónde vive en producción |
|---|---|---|
| `NODE_ENV` / `APP_ENV` | Entorno (`local`, `staging`, `production`) | Config. de Cloud Run |
| `API_BASE_URL` | URL pública del backend | Config. |
| `DATABASE_URL` | Cadena de conexión a PostgreSQL | Secret Manager |
| `GOOGLE_CLOUD_PROJECT` / `GOOGLE_CLOUD_REGION` | Proyecto y región (`europe-southwest1`) | Config. |
| `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET` | Cliente OAuth (tipo aplicación web) para la Google Health API | Secret Manager |
| `GOOGLE_OAUTH_REDIRECT_URI` | `https://<API_BASE_URL>/connections/google/callback` | Config. |
| `GOOGLE_HEALTH_API_BASE_URL` | `https://health.googleapis.com/v4` | Config. |
| `GOOGLE_HEALTH_SCOPES` | Ámbitos mínimos separados por espacios (doc. 10 §3) | Config. |
| `GOOGLE_CLOUD_PROJECT_NUMBER` | Número de proyecto (registro del suscriptor de *webhooks*) | Config. |
| `GOOGLE_HEALTH_WEBHOOK_SECRET` | Secreto que Google envía en la cabecera `Authorization` de cada *webhook* | Secret Manager |
| `GOOGLE_HEALTH_WEBHOOK_KEYSET_URL` | Conjunto de claves públicas para verificar la firma (`https://www.gstatic.com/googlehealthapi/webhooks/webhooks_public_keyset.json`) | Config. |
| `TOKEN_ENCRYPTION_KMS_KEY` | Nombre de la clave KMS para cifrar *tokens* (en local: `TOKEN_ENCRYPTION_LOCAL_KEY`) | KMS |
| `SESSION_JWT_SECRET` (o claves asimétricas) | Firma de sesiones de nuestra app | Secret Manager |
| `APPLE_SIGNIN_*` | Credenciales de Sign in with Apple | Secret Manager |
| `EXPO_ACCESS_TOKEN` | Envío de notificaciones *push* con Expo | Secret Manager |
| `ANTHROPIC_API_KEY` | Clave de la API de Claude (solo backend) | Secret Manager |
| `ANTHROPIC_MODEL` | Modelo del Coach (`claude-opus-5` por defecto) | Config. |
| `COACH_DAILY_MESSAGE_LIMIT` / `COACH_DAILY_TOKEN_LIMIT` | Límites por usuario (RNF-ESC-04) | Config. |
| `SENTRY_DSN` | *Crash reporting* | Config. |
| `EXPO_PUBLIC_API_BASE_URL` | URL del backend para la app (pública, no secreta) | EAS |

## 5. Lista de tareas de F0 (en orden)

1. [ ] Llevar la Fitbit Air 24/7 y comprobar en Google Health que aparecen sueño con fases, VFC, FC en reposo, SpO₂, frecuencia respiratoria y temperatura.
2. [ ] Crear el proyecto de Google Cloud (`europe-southwest1`), activar facturación con **alertas de presupuesto** (p. ej. 25 €).
3. [ ] Registrar el dominio y publicar una web mínima con la política de privacidad (incluida la declaración literal de *Limited Use*, RL-42) y las condiciones (borrador del doc. 12). Google la exige para configurar el consentimiento.
4. [ ] Habilitar `health.googleapis.com`; en **Google Auth Platform** completar *Branding* (nombre, logo, soporte, dominio verificado, URLs), *Audience* (*External*, *Testing*, tu cuenta como usuario de prueba) y *Data Access* (ámbitos de doc. 10 §3); crear el cliente OAuth **Aplicación web** con las URI de redirección; anotar el **número de proyecto** (doc. 10 §2.1).
5. [ ] Crear la cuenta de servicio con rol *Google Health API Editor* para registrar el suscriptor de *webhooks* (doc. 10 §6.2).
6. [ ] ***Spike* de datos**: script que haga el flujo OAuth con tu cuenta y descargue 30 días de cada tipo de dato a ficheros JSON locales (fuera del repositorio), registre un *webhook* de prueba y mida latencias. Responder a las preguntas del doc. 03 §7 → actualizar docs. 03, 09 y 10. **Hito H0.**
7. [ ] Crear la estructura del monorepo (doc. 08 §5), CI (lint, tests, gitleaks), protección de rama y plantilla de PR con referencias a requisitos.
8. [ ] Escribir los ADR 001–010 (doc. 08 §2) confirmando o cambiando cada decisión con lo aprendido en el *spike*.
9. [ ] Definir los tokens de diseño (doc. 11 §8) y validar contrastes.
10. [ ] Resolver las decisiones abiertas D-1 a D-7 (doc. 01 §8).

## 6. Coste mensual orientativo (uso personal)

| Concepto | Coste |
|---|---|
| Cloud Run (API + workers, escala a cero) | 0–3 € (nivel gratuito) |
| Cloud SQL PostgreSQL (instancia mínima) | ~10–25 € |
| Cloud Scheduler, Tasks, KMS, Secret Manager | < 2 € |
| Coach IA (F3) | ~8–25 $ |
| Dominio | ~1 € (prorrateado) |
| Apple Developer (si iPhone) | ~8 $ (prorrateado) |
| **Total** | **~25–60 €/mes** (≈ 12–30 € sin Coach IA ni Apple) |

Alternativa más barata para la BD: PostgreSQL gestionado con nivel gratuito en la UE (p. ej. Supabase o Neon) — comprobar límites de almacenamiento frente al volumen de FC intradía (doc. 09 §6).
