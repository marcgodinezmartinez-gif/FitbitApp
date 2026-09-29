# 17 · Puesta en marcha paso a paso

Todo lo que tienes que hacer tú para tener **Recupera en tu iPhone con tus datos reales**. No hace falta Mac: basta un navegador (ordenador o iPad) y el iPhone. Son cuentas y permisos que solo puedes crear tú; el código ya está listo.

**Tiempo:** ≈ 45 min de clics y ≈ 30–45 min de espera (compilación y procesado de TestFlight).

**Antes de empezar:**

- iPhone con iOS 26 o posterior y la app **TestFlight** (App Store).
- Fitbit Air emparejada en la app **Google Health** y sincronizada; Apple Watch grabando tus carreras (opcional).
- Tu cuenta de **Apple Developer** y la cuenta de **Google** de la Fitbit Air.

## Paso 0 · Elige tu identificador

Inventa el identificador de la app (*bundle ID*) y úsalo **igual en todas partes**: `com.<tunombre>.recupera` (solo minúsculas, números, puntos y guiones; p. ej. `com.marcgodinez.recupera`).

De él salen otros dos:

| Para | Valor |
|---|---|
| App | `com.<tunombre>.recupera` |
| *Widgets* | `com.<tunombre>.recupera.widgets` |
| App Group (datos compartidos con los *widgets*) | `group.com.<tunombre>.recupera` |

## Parte A · Apple Developer (≈ 10 min)

En [developer.apple.com/account](https://developer.apple.com/account):

1. **Team ID**: *Membership details* → copia el **Team ID** (10 caracteres).
2. **App Group**: *Certificates, Identifiers & Profiles* → *Identifiers* → **+** → *App Groups* → descripción «Recupera», identificador `group.com.<tunombre>.recupera` → *Continue* → *Register*.
3. **App ID de la app**: *Identifiers* → **+** → *App IDs* → *App* → descripción «Recupera», *Bundle ID* **Explicit** `com.<tunombre>.recupera` → en *Capabilities* marca **App Groups** y **HealthKit** → *Continue* → *Register*. Después ábrelo, en *App Groups* pulsa **Configure**, marca tu grupo y guarda (*Save*).
4. **App ID de los *widgets***: igual, con descripción «Recupera Widgets», *Bundle ID* `com.<tunombre>.recupera.widgets` y solo **App Groups** (configurado con el mismo grupo).

No hay que activar nada para la Live Activity, AlarmKit ni los avisos: van en el propio código.

## Parte B · App Store Connect (≈ 10 min)

En [appstoreconnect.apple.com](https://appstoreconnect.apple.com):

1. **Crear la app**: *Apps* → **+** → *Nueva app* → plataforma **iOS**; nombre «Recupera» (si está cogido, cualquier otro: en tu iPhone se seguirá llamando Recupera); idioma principal **Español (España)**; *Bundle ID* el tuyo (aparece en la lista tras la parte A); SKU `recupera`; acceso completo → *Crear*.
2. **Clave de API para GitHub**: *Usuarios y acceso* → *Integraciones* → *App Store Connect API* (la primera vez, *Solicitar acceso*) → *Claves del equipo* → **+** → nombre «GitHub», acceso **Admin** → *Generar*.
   - **Descarga el archivo `.p8`**: solo se puede descargar una vez; guárdalo bien.
   - Apunta el **Key ID** (en la tabla) y el **Issuer ID** (encima de la tabla).
   - Por qué Admin: la compilación en la nube crea sola los certificados y perfiles de firma.
3. **Grupo de pruebas** (se puede hacer después de la primera subida): tu app → *TestFlight* → *Pruebas internas* → **+** → grupo «Yo» → añádete y activa la distribución automática.

## Parte C · Google Cloud (≈ 15 min)

En [console.cloud.google.com](https://console.cloud.google.com), **con la cuenta de Google de tu Fitbit Air**:

1. Crea un proyecto llamado «Recupera».
2. *APIs y servicios* → *Biblioteca* → busca **Google Health API** → *Habilitar*.
3. *Google Auth Platform* → *Comenzar* → **Branding**: nombre «Recupera», tu email de asistencia y de contacto → *Guardar*.
4. **Audience** (público): tipo **Externo**, estado **Prueba** (*Testing*) → *Usuarios de prueba* → **+** → añade tu Gmail de la Fitbit Air.
5. **Data Access** (acceso a datos): *Añadir o quitar permisos* → *Añadir permisos manualmente* → pega estas cinco líneas → *Añadir a la tabla* → *Actualizar* → *Guardar*:

   ```
   https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
   https://www.googleapis.com/auth/googlehealth.sleep.readonly
   https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly
   https://www.googleapis.com/auth/googlehealth.profile.readonly
   https://www.googleapis.com/auth/googlehealth.settings.readonly
   ```

6. **Clients** (clientes): **+ Crear cliente** → tipo **iOS** → nombre «Recupera iOS» → *Bundle ID* `com.<tunombre>.recupera` → *Crear*. Deja vacíos el **ID de App Store** (solo existe si la app se publica en la App Store; la tuya va por TestFlight) y el **Team ID** (no lo usa este inicio de sesión). Copia el **Client ID** (termina en `.apps.googleusercontent.com`).

En modo *Prueba*, Google pide volver a conectar cada 7 días (un toque en la app). Cuando todo funcione puedes pasarla a producción sin verificar (paso G2).

## Parte D · GitHub (≈ 5 min)

1. En el repositorio: *Settings* → *Secrets and variables* → *Actions* → **New repository secret**, uno por fila:

   | Nombre | Valor |
   |---|---|
   | `APP_BUNDLE_ID` | tu *bundle ID* (paso 0) |
   | `APPLE_TEAM_ID` | Team ID (A1) |
   | `ASC_KEY_ID` | Key ID (B2) |
   | `ASC_ISSUER_ID` | Issuer ID (B2) |
   | `ASC_KEY_P8` | el contenido completo del `.p8`: ábrelo con cualquier editor de texto y pégalo, incluidas las líneas `BEGIN` y `END` |
   | `GOOGLE_IOS_CLIENT_ID` | Client ID (C6) |

   El esquema de redirección de Google (`GOOGLE_REVERSED_CLIENT_ID`) ya no hace falta: se calcula solo.

2. **Comprobar**: *Actions* → **Comprobar configuración** → *Run workflow*. En 1–2 min (en Linux, sin gastar minutos de macOS) verás una lista con ✅ y ❌. Revisa el formato de cada secreto, la clave de App Store Connect, los dos App IDs con sus capacidades, la ficha de la app y el grupo de TestFlight. Corrige lo que salga en ❌ y vuelve a lanzarlo.

## Parte E · Compilar y subir a TestFlight (≈ 30 min de espera)

1. *Actions* → **iOS** → *Run workflow* → deja la rama que sale (`claude/whoop-like-fitbit-air-app-q7no7j`, la única del repositorio) → marca **«Firmar y subir a TestFlight»** → *Run workflow*.
2. En ≈ 5 min compila, firma y sube la app. Después, el paso **Estado de TestFlight** (en Linux) espera a que Apple procese la *build* (10–30 min; te llega un email) y la añade a tu grupo interno. Cuando todo esté en verde, ya puedes instalarla.
3. Si su resumen dice ⚠️ «aún no está lista», espera el email de Apple y lanza *Actions* → **Estado de TestFlight** → *Run workflow*.

Cada subida gasta ≈ 6 min de los ≈ 200 minutos de macOS gratis al mes (la espera va en Linux).

## Parte F · En tu iPhone (≈ 5 min)

1. Abre **TestFlight** → acepta la invitación → *Instalar* Recupera.
2. Abre la app y completa el perfil: fecha de nacimiento, sexo, altura, peso y hora de despertar. La cintura y el cuestionario de actividad son opcionales y sirven para el VO₂ máx. sin ejercicio.
3. **Conectar Google Health**: entra con la cuenta de la Fitbit Air y **marca todos los permisos**.
4. **Conectar Apple Health**: *Activar todo* → *Permitir*.
5. Empieza la importación de **6 meses**. Primero aparecen tus noches y tu recuperación, luego el pulso de los últimos 14 días y después el resto, con una barra de progreso en Hoy. Puedes usar la app mientras tanto.
6. Permite los avisos y añade los *widgets* (mantén pulsada la pantalla de inicio → **+** → Recupera).

## Parte G · Opcional

1. **Coach IA**:
   - Crea una clave en [console.anthropic.com](https://console.anthropic.com) (*API Keys*) y pon un límite de gasto mensual en *Billing*.
   - En la app: *Perfil › Coach IA* → pega la clave → *Probar conexión*.
   - Activa el resumen matinal y el informe semanal si los quieres.
   - Con Gemini: clave de un proyecto **con facturación activada**.
2. **Evitar reconectar cada semana**: cuando todo funcione, en *Google Auth Platform* → *Audience* → **Publicar aplicación**. Al conectar verás una vez el aviso «Google no ha verificado esta app»: pulsa *Configuración avanzada* → *Ir a Recupera*. Solo la usas tú.

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| «Comprobar configuración» con ❌ | Corrige lo que indica esa línea y vuelve a lanzarlo |
| «Estado de TestFlight» con ⚠️ o ❌ | Haz lo que indica su resumen; si Apple no acepta la *build*, el motivo llega por email |
| El *workflow* iOS falla en «Archivar» | Casi siempre es un App ID o una capacidad; ejecuta «Comprobar configuración» y, si todo sale ✅, pásame el error |
| Google: «Acceso bloqueado» | Tu Gmail no está en *Usuarios de prueba* (C4) o entraste con otra cuenta |
| Google: «Error 400: redirect_uri_mismatch» | El cliente no es de tipo iOS o su *bundle ID* no coincide (C6) |
| La app dice «Configura primero la app Google Health» | Abre Google Health en el iPhone y termina su configuración |
| No aparecen entrenamientos del Watch | App Salud → tu foto (arriba a la derecha) → *Apps* → Recupera → *Activar todo* |
| A la semana pide «Reconectar» Google | Es el modo *Prueba*: toca Reconectar o haz G2 |
