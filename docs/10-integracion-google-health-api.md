# 10 · Integración con la Google Health API

Referencia para implementar el paquete `HealthAPI` (doc. 08 §3), que la app usa **directamente desde el iPhone** (sin servidor). Información verificada en la documentación oficial a **28/09/2026**; la API es reciente y ha tenido cambios incompatibles durante 2026, así que todo pasa por el adaptador y los tests de contrato (doc. 13 §4).

Documentación oficial: <https://developers.google.com/health>.

---

## 1. Contexto

| Hecho | Detalle | Fuente |
|---|---|---|
| Lanzamiento de la Google Health API | 24/03/2026 | [Notas de versión](https://developers.google.com/health/release-notes) |
| Fitbit Web API antigua | Se desactiva el **30/09/2026**; sin altas nuevas; los *tokens* antiguos no migran | [Hilo oficial](https://support.google.com/googlehealth/thread/439040688), [migración](https://developers.google.com/health/migration) |
| Estilo | REST + JSON con OAuth 2.0 de Google | [Endpoints](https://developers.google.com/health/endpoints) |
| URL base | `https://health.googleapis.com/v4/` | idem |
| Clasificación de ámbitos | **Todos restringidos** | [About](https://developers.google.com/health/about), [verificación](https://developers.google.com/health/app-verification) |
| Premium | **No hace falta**: los datos brutos se leen sin suscripción; las puntuaciones de Google no están en la API | Doc. 03 §2 |

## 2. Alta del proyecto (F0, gratis)

### 2.1 Pasos

1. Crear un proyecto en Google Cloud Console con la misma cuenta de Google de la Fitbit Air (o con otra y añadirla como usuaria de prueba). En principio no hace falta activar la facturación para esta API [verificar].
2. Habilitar la API `health.googleapis.com` ([guía](https://developers.google.com/health/setup)).
3. **Google Auth Platform → Branding**: nombre de la app, email de soporte y, recomendado, enlace a una página de privacidad (puede ser una página gratuita en GitHub Pages con la declaración de RL-42).
4. **Audience**: tipo *External*; añadir tu cuenta de Google como **usuario de prueba**.
5. **Data Access**: añadir los ámbitos de §3.
6. **Clients**: crear un cliente OAuth de tipo **iOS** con el *bundle ID* de la app. Google genera el *client ID* y el esquema de URL invertido para la redirección (se copian a `Config/Secrets.xcconfig`, doc. 15).

### 2.2 Modo de publicación del consentimiento

| Modo | Usuarios | Caducidad del *refresh token* | Lo que verás | Recomendación |
|---|---|---|---|---|
| *Testing* | Solo usuarios de prueba (≤ 100) | **7 días** ⇒ reconectar cada semana (1 toque) | Consentimiento normal | Para empezar (F0) |
| *In production* **sin verificar** | 100 en total | Sin caducidad de 7 días (caduca tras 6 meses sin uso o al revocarse) | Aviso «Google no ha verificado esta app» al conectar (se acepta una vez) | **Para el día a día**, tras comprobarlo en el *spike* (D-7) |
| *In production* verificada | Sin límite | Normal | — | Solo si se publicara: exige verificación de ámbitos restringidos y evaluación CASA anual (500–4 500 $) |

Fuentes: [verificación de apps](https://developers.google.com/health/app-verification), [OAuth 2.0 de Google](https://developers.google.com/identity/protocols/oauth2).

## 3. Ámbitos (*scopes*)

Prefijo: `https://www.googleapis.com/auth/googlehealth`. Fuente: [Scopes](https://developers.google.com/health/scopes).

| Ámbito | Datos que habilita | Uso | Fase |
|---|---|---|---|
| `.health_metrics_and_measurements.readonly` | FC, FC en reposo, HRV, SpO₂, FR, temperatura del sueño, zonas de FC diarias | **Obligatorio** | F1 |
| `.sleep.readonly` | Sesiones de sueño y fases | **Obligatorio** | F1 |
| `.activity_and_fitness.readonly` | Pasos, distancia, calorías, minutos activos/AZM, ejercicio, VO₂ máx. | **Obligatorio** | F1 |
| `.settings.readonly` | Zona horaria, dispositivos emparejados y última sincronización | Recomendado | F1 |
| `.profile.readonly` | Datos del perfil de Google Health | Opcional (el perfil se puede rellenar en la app) | F2 |
| `.location.readonly`, `.ecg.readonly`, `.irn.readonly`, `*.writeonly` | GPS, ECG, ritmo irregular, escritura | **No se piden** | — |

Google permite conceder solo algunos ámbitos: la app lee los concedidos y degrada según el doc. 03 §6.

## 4. OAuth en iOS

| Parámetro | Valor |
|---|---|
| Librería | Implementado sin dependencias (`HealthAPI/OAuth.swift` + `GoogleAuthSession` en la app): el mismo flujo que hace **AppAuth-iOS** (navegador del sistema con `ASWebAuthenticationSession`, PKCE S256 y `state`). Si en el *spike* Google lo rechazara, se sustituye por AppAuth-iOS o Google Sign-In sin tocar el resto |
| Flujo | Código de autorización con **PKCE (S256)** en `ASWebAuthenticationSession`; **nunca WebView** |
| Endpoints | Autorización `https://accounts.google.com/o/oauth2/v2/auth` · *token* `https://oauth2.googleapis.com/token` · revocación `https://oauth2.googleapis.com/revoke` |
| Redirección | Esquema de URL invertido del *client ID* de iOS (lo gestiona la librería) |
| *Access token* | 1 h; se refresca bajo demanda justo antes de sincronizar |
| *Refresh token* | Llavero del iPhone (RNF-SEG-02); caduca a los 7 días en *Testing*, tras 6 meses sin uso o al revocarse |
| Identidad | `GET /v4/users/me/identity` ⇒ `healthUserId` (se guarda en `connection`) |
| Errores especiales | **HTTP 412**: no hay perfil de Google Health ⇒ «Configura primero la app Google Health» (RF-CON-08); `invalid_grant` al refrescar ⇒ estado «Reconectar» (RF-CON-04) |

Divulgación previa a la conexión (RL-43): «**{Nombre de la app} recopila datos de salud y actividad física de tu cuenta de Google Health para calcular tu recuperación, tu carga diaria y tu sueño en este iPhone.**»

## 5. Lectura de datos

### 5.1 Métodos

| Método | Uso en la app |
|---|---|
| `GET users/me/dataTypes/{tipo}/dataPoints` (`list`) | Datos brutos (sueño, ejercicio, muestras) |
| `GET …/dataPoints:reconcile` | Flujo deduplicado entre fuentes; **por defecto** para datos fisiológicos |
| `POST …/dataPoints:rollUp` (`windowSize` ≥ 1 s) | FC por minuto (media/mín./máx.) |
| `POST …/dataPoints:dailyRollUp` | Totales diarios (pasos, calorías…) |
| `users/me/settings`, `users/me/pairedDevices`, `users/me/profile` | Zona horaria, última sincronización de la pulsera, perfil |

Ejemplos:

```http
GET https://health.googleapis.com/v4/users/me/dataTypes/sleep/dataPoints:reconcile
    ?dataSourceFamily=users/me/dataSourceFamilies/google-wearables
    &filter=sleep.interval.civil_end_time >= "2026-09-27"

POST https://health.googleapis.com/v4/users/me/dataTypes/heart-rate/dataPoints:rollUp
{ "range": { "startTime": "2026-09-27T00:00:00Z", "endTime": "2026-09-28T00:00:00Z" },
  "windowSize": "60s", "pageSize": 1440,
  "dataSourceFamily": "users/me/dataSourceFamilies/google-wearables" }
```

### 5.2 Reglas y límites

- Paginación: 1 440 puntos por defecto, máx. 10 000; `sleep` y `exercise` devuelven como mucho 25 por página; de más reciente a más antiguo; `pageToken` para continuar.
- Filtros AIP-160 sobre el tiempo del dato (físico RFC 3339, civil local o `date`). **No hay filtro por fecha de modificación ni *feed* de cambios**: se re-consultan ventanas recientes.
- `rollUp`: rango máximo de **14 días** para `heart-rate`, `active-minutes`, `total-calories` y `calories-in-heart-rate-zone`; 90 días para el resto.
- Histórico: sin límite impuesto por la API.
- Familias de fuentes (`dataSourceFamily`, en `reconcile`, `rollUp` y `dailyRollUp`): `all-sources` (por defecto: todas, incluidas las de terceros), `google-wearables` (solo pulseras y relojes de Google y Fitbit, sin registros manuales ni estimaciones del móvil) y `google-sources` (pulseras, Health Connect y registros manuales en apps de Google). La app usa **`google-wearables` en todas las lecturas**: líneas base coherentes y sin las copias que Google importa de Salud (§8).
- Zonas horarias: los intervalos incluyen desfase UTC y hora civil; los datos diarios se indexan por fecha local.

### 5.3 Cuotas ([Rate limits](https://developers.google.com/health/rate-limits))

300 peticiones/min por usuario (~5 QPS); las apps sin verificar, máx. 250 QPS en total. Una sincronización típica hace 10–20 peticiones, así que las cuotas no son un problema; aun así el cliente limita a ≤ 4 peticiones/s y aplica *backoff* ante 429 (RNF-DIS-04).

### 5.4 Granularidad y almacenamiento

Las condiciones exigen **guardar los datos con la misma granularidad con la que se obtienen** (p. ej. no convertir datos por minuto en totales diarios) (RL-44):

- FC continua: se obtiene con `rollUp` de **60 s** y se guarda por minuto (`hr_minute`).
- FC de **1 s** solo dentro de entrenamientos (`hr_samples`).
- Nunca se sustituye un dato guardado por un agregado; la retención borra datos completos.

## 6. Sincronización desde el iPhone

| Momento | Mecanismo | Qué hace |
|---|---|---|
| Al conectar | Primer plano + `BGProcessingTask` | Importación de **180 días** por fases, recalculando tras cada una: 1) sueño, vitales diarios, entrenamientos, VO₂ máx. y totales de todo el periodo (pocas peticiones: sueño y recuperación en segundos); 2) FC y pasos por minuto de los últimos 14 días; 3) el resto, en tramos de 14 días del más reciente al más antiguo, con barra de progreso en Hoy |
| Al abrir la app y *pull-to-refresh* | Primer plano | Últimas 48 h de cada tipo + huecos desde `sync_state.synced_until` |
| Mañana | `BGAppRefreshTask` programada para la hora habitual de despertar (reprogramada si aún no hay sueño) | Sueño y vitales de la noche ⇒ recuperación ⇒ notificación local |
| Noche | `BGProcessingTask` (cargando y con Wi-Fi) | Revisión de 7 días (datos editados o tardíos) y recálculo de líneas base |

- Antes de consultar, `pairedDevices.lastSyncTime` (ámbito `.settings.readonly`) indica si la pulsera ha subido algo nuevo. La app no puede forzar la sincronización de la pulsera; el botón «Abrir Google Health» usa el enlace universal documentado `https://www.fitbit.com/in-app/today` ([enlaces universales](https://developers.google.com/health/universal-app-links)), y Google Health sincroniza la pulsera al abrirse si está cerca ([ayuda](https://support.google.com/googlehealth/answer/14237221)).
- iOS decide cuándo ejecuta las tareas en segundo plano (mejor cuanto más se usa la app); por eso el refresco al abrir es el camino principal y debe ser rápido (RNF-REN-04).
- Sin servidor no hay *webhooks* ni *push*: es una limitación aceptada (doc. 08 ADR 002).

## 7. Cumplimiento de políticas (también en uso personal)

Fuentes: [Términos para desarrolladores](https://developers.google.com/health/policies/health-api-developer-terms-and-conditions), [Política de datos de usuario](https://developers.google.com/health/policies/health-api-developer-user-data-policy), [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), [Promoción y marca](https://developers.google.com/health/promote).

- [ ] Uso solo para funciones de salud y bienestar visibles para ti; nada de publicidad, venta ni cesión de datos (*Limited Use*, también para datos derivados).
- [ ] Declaración literal en la página de privacidad: *«The use of information received from Google Health API and/or Developer Tools will adhere to the Google Health API Developer and User Data Policy, including the Limited Use requirements.»*
- [ ] Divulgación en la app antes del consentimiento (§4).
- [ ] Datos y *tokens* cifrados en reposo con claves protegidas por hardware (Llavero + protección de datos de iOS).
- [ ] Granularidad de almacenamiento (§5.4).
- [ ] Marca: «Google Health» sin traducir; estado «Conectado a Google Health» con la última sincronización y «Desconectar» a 1–2 toques; sin logotipos antiguos de Fitbit/Google Fit.
- [ ] Al desconectar: revocar el *token*, borrarlo y preguntar si se conservan los datos (RL-47).
- [ ] Coach IA: los datos de la API solo van al proveedor de IA como parte de esa función, activada por ti, y sin entrenamiento de modelos (RL-48).

## 8. Apple Health y el Apple Watch

Los datos del Apple Watch se leen directamente de Salud (HealthKit) en el iPhone ([doc. 16](16-apple-watch-y-fusion-de-datos.md)). Del lado de Google importa esto:

- La app Google Health puede **conectarse con Salud en los dos sentidos** (iOS 16.4+): **lee** de Salud pasos, VO₂ máx., pisos, calorías activas, distancia, ejercicio y rutas, sueño, temperatura, FC, VFC, SpO₂, FR, FC en reposo, etc. (hasta 3 meses de historial), y **escribe** en Salud casi lo mismo, salvo VFC y temperatura ([ayuda](https://support.google.com/googlehealth/answer/17037331)). Lo importado de Salud se guarda en tu cuenta de Google Health.
- Por eso todas las lecturas de la API usan la familia **`google-wearables`** («datos grabados por pulseras y relojes de Google y Fitbit»; excluye lo registrado a mano y lo estimado por el móvil), y así las carreras del Watch no vuelven por Google [verificar en el *spike*]. `dataSourceFamily` solo está publicado para `reconcile`, `rollUp` y `dailyRollUp`; si un tipo se lee con `list`, se descartan en la app los puntos cuyo `dataSource.platform` sea `HEALTH_KIT` (ALG-FUS-08). Cada punto trae `dataSource` con `platform` (`FITBIT`, `HEALTH_KIT`, `HEALTH_CONNECT`…), `recordingMethod`, `device` (`formFactor`, `manufacturer`, `displayName`) y `application` ([referencia](https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints)).
- La Fitbit Air **detecta sola las carreras** (SmartTrack; en `pairedDevices`, la función `AUTORUN`), así que la misma carrera puede llegar por Google y por Salud: se fusionan por solape (ALG-FUS-02) ([ayuda](https://support.google.com/googlehealth/answer/14236510)).
- Salud **no sustituye** a la API: Google Health no escribe allí ni VFC ni temperatura, así que sin la API no habría recuperación.

## 9. FC en vivo por Bluetooth (opcional, F3)

Si activas la emisión de FC en la Fitbit Air, la pulsera usa el **perfil estándar de FC** de Bluetooth (servicio GATT `0x180D`, característica `0x2A37`). La app puede leerla con CoreBluetooth para mostrar FC y zona en vivo en un entrenamiento y en la Live Activity (RF-ENT-07, RF-WID-03). Es un perfil estándar (compatible con RL-62); la viabilidad con apps no listadas por Google se comprueba en el *spike*.

## Anexo · *Webhooks* (solo si algún día hubiera servidor)

La API ofrece suscriptores por proyecto (`POST https://health.googleapis.com/v4/projects/{número-de-proyecto}/subscribers`) que avisan de datos nuevos o borrados con una notificación firmada (cabecera `GOOGLE-HEALTH-API-SIGNATURE`, verificable con Tink) y reintentos durante 7 días. Requieren un servidor público y una cuenta de servicio, así que **no se usan** en la versión personal (doc. 08 §7).
