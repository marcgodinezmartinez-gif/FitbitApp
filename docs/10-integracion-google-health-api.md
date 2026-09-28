# 10 · Integración con la Google Health API

Documento de referencia para implementar el paquete `packages/google-health` (doc. 08 §3.5). Información verificada en la documentación oficial a **28/09/2026**; la API es reciente y ha tenido cambios incompatibles durante 2026, así que **toda la integración pasa por el adaptador y los tests de contrato** (doc. 13 §4).

Documentación oficial: <https://developers.google.com/health>.

---

## 1. Contexto

| Hecho | Detalle | Fuente |
|---|---|---|
| Lanzamiento de la Google Health API | 24/03/2026 | [Notas de versión](https://developers.google.com/health/release-notes) |
| Fitbit Web API antigua | Se desactiva por completo el **30/09/2026**; sin altas de apps nuevas; los *tokens* antiguos no migran | [Hilo oficial](https://support.google.com/googlehealth/thread/439040688), [guía de migración](https://developers.google.com/health/migration) |
| Estilo | REST + JSON, OAuth 2.0 de Google, *webhooks* | [Endpoints](https://developers.google.com/health/endpoints) |
| URL base | `https://health.googleapis.com/v4/` | idem |
| Clasificación de ámbitos | **Todos restringidos** | [About](https://developers.google.com/health/about), [verificación](https://developers.google.com/health/app-verification) |

## 2. Alta del proyecto y modos de uso

### 2.1 Pasos (F0)

1. Crear proyecto en Google Cloud Console (región de despliegue `europe-southwest1`) y anotar el **número de proyecto** (lo exige el registro de *webhooks*).
2. Habilitar la API `health.googleapis.com` ([guía](https://developers.google.com/health/setup)).
3. **Google Auth Platform → Branding**: nombre de la app, logotipo, email de soporte, página de inicio, política de privacidad y condiciones en el **dominio verificado** propio.
4. **Audience**: tipo *External*; añadir la cuenta de Google del propietario como usuario de prueba.
5. **Data Access**: añadir los ámbitos de §3.
6. **Clients**: crear un cliente OAuth de tipo **Aplicación web** para el backend con la URI de redirección exacta (`https://api.<dominio>/connections/google/callback` y la de desarrollo). Los clientes Android/iOS solo se necesitan para *Sign in with Google* en la app, no para la Health API.
7. Crear una **cuenta de servicio** con el rol *Google Health API Editor* (o *Admin*) para gestionar suscriptores de *webhooks* desde Cloud Run (sin claves JSON).

### 2.2 Uso personal frente a producto

| Modo | Límite de usuarios | Caducidad del *refresh token* | Requisitos | Cuándo |
|---|---|---|---|---|
| *Testing* (usuarios de prueba) | Solo los añadidos (≤ 100) | **7 días** ⇒ reconexión semanal | Ninguno adicional | Arranque de F0 |
| *In production* **sin verificar** | 100 usuarios en total | Sin caducidad de 7 días (caduca tras 6 meses sin uso o al revocarse) | El usuario ve la pantalla «Google no ha verificado esta app» | **Recomendado para uso personal (F1–F3)** — [verificar] en el *spike* |
| *In production* verificada | Sin límite de 100 | Normal | Verificación de marca (2–3 días), verificación de ámbitos restringidos (vídeo de demostración en YouTube no listado, justificación por ámbito, dominio verificado, política de privacidad en el mismo dominio) y **evaluación de seguridad CASA anual** (500–4 500 $, 2–6 semanas, laboratorio externo) | F4 |

Fuentes: [verificación de apps](https://developers.google.com/health/app-verification), [verificación de ámbitos restringidos](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification), [OAuth 2.0 de Google](https://developers.google.com/identity/protocols/oauth2).

Requisitos que aplican **en cualquier modo** (RL-40 y siguientes, doc. 12): divulgación en la app antes del consentimiento, política de privacidad con la declaración literal de *Limited Use*, cifrado de datos y *tokens* con KMS/HSM.

## 3. Ámbitos (*scopes*)

Prefijo: `https://www.googleapis.com/auth/googlehealth`. Fuente: [Scopes](https://developers.google.com/health/scopes).

| Ámbito | Datos que habilita (para nuestra app) | Uso | Fase | Justificación para la verificación |
|---|---|---|---|---|
| `.health_metrics_and_measurements.readonly` | FC, FC en reposo, HRV, SpO₂, FR, temperatura del sueño, zonas de FC diarias | **Obligatorio** | F1 | Cálculo de recuperación, carga y monitor de salud |
| `.sleep.readonly` | Sesiones de sueño y fases | **Obligatorio** | F1 | Sueño, necesidad/deuda de sueño, ciclos diarios, recuperación |
| `.activity_and_fitness.readonly` | Pasos, distancia, calorías, minutos activos/AZM, ejercicio, VO₂ máx. | **Obligatorio** | F1 | Entrenamientos, contexto de actividad, exclusión de movimiento en estrés |
| `.settings.readonly` | Zona horaria, dispositivos emparejados y última sincronización | Recomendado | F1 | Ciclos en hora local; estado «última sincronización» |
| `.profile.readonly` | Edad/sexo/altura/peso del perfil de Google Health | Opcional (el usuario puede introducirlos en nuestra app) | F2 | Prefill del perfil |
| `.location.readonly` | GPS de ejercicios (exportación TCX) | **No se pide** | — | Minimización (RNF-PRI-01) |
| `.ecg.readonly`, `.irn.readonly` | ECG, ritmo irregular | **No se piden** | — | Fuera de alcance (RL-03) |
| `*.writeonly` | Escritura en Google Health | **No se piden** | — | La app no escribe datos |

El usuario puede conceder solo algunos ámbitos (consentimiento granular): la app lee los ámbitos concedidos en la respuesta del *token* y degrada según el doc. 03 §6.

## 4. Flujo OAuth

| Parámetro | Valor |
|---|---|
| Autorización | `https://accounts.google.com/o/oauth2/v2/auth` |
| *Token* | `https://oauth2.googleapis.com/token` |
| Revocación | `https://oauth2.googleapis.com/revoke` |
| Tipo | Código de autorización (servidor) con `access_type=offline` para obtener *refresh token*; PKCE (S256) y `state` |
| Navegador | Siempre el del sistema (ASWebAuthenticationSession / Custom Tabs); **nunca WebView** |
| *Access token* | 1 h; se refresca bajo demanda (no en lotes programados) |
| *Refresh token* | Caduca a los 7 días en *Testing*, tras 6 meses sin uso, o al revocarse |
| Identidad | `GET /v4/users/me/identity` ⇒ `healthUserId` (la respuesta del *token* no trae el ID); se guarda como `external_user_id` para enlazar los *webhooks* |
| Errores especiales | **HTTP 412** si el usuario no ha configurado su perfil de Google Health ⇒ mensaje «Configura primero la app Google Health» |

Divulgación previa obligatoria (formato recomendado por Google): «**{Nombre de la app} recopila datos de salud y actividad física para calcular tu recuperación, tu carga diaria y tu sueño, y para ofrecerte recomendaciones personalizadas.**»

## 5. Lectura de datos

### 5.1 Métodos

| Método | Uso en la app |
|---|---|
| `GET users/me/dataTypes/{tipo}/dataPoints` (`list`) | Datos brutos (sueño, ejercicio, muestras) |
| `GET …/dataPoints:reconcile` | Flujo deduplicado entre fuentes; **por defecto** para datos fisiológicos |
| `POST …/dataPoints:rollUp` (`windowSize` ≥ 1 s) | FC por minuto (media/mín./máx.) y otras series agregadas |
| `POST …/dataPoints:dailyRollUp` | Totales diarios (pasos, calorías…) |
| `users/me/settings`, `users/me/pairedDevices`, `users/me/profile` | Zona horaria, última sincronización, perfil |

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

- Paginación: 1 440 puntos por defecto, máx. 10 000; `sleep` y `exercise` devuelven como mucho 25 por página; orden de más reciente a más antiguo; `pageToken` para continuar.
- Filtros AIP-160 sobre el tiempo del dato (físico RFC 3339, civil local o `date` diaria). **No hay filtro por fecha de modificación ni *feed* de cambios**: la sincronización incremental se basa en los intervalos que indican los *webhooks* y en re-consultar ventanas recientes.
- `rollUp`: rango máximo de **14 días** para `heart-rate`, `active-minutes`, `total-calories` y `calories-in-heart-rate-zone`; 90 días para el resto.
- Histórico: sin límite impuesto por la API (sujeto a cuotas).
- Familias de fuentes: `all-sources` (por defecto), `google-wearables` (solo pulseras/relojes de Google), `google-sources`. Para líneas base fisiológicas se usa **`google-wearables`** para no mezclar datos escritos por otras apps; configurable.
- Zonas horarias: los intervalos incluyen desfase UTC y hora civil; los datos diarios se indexan por fecha local (RNF-I18N-03).

### 5.3 Cuotas ([Rate limits](https://developers.google.com/health/rate-limits))

| Límite | Valor |
|---|---|
| Por usuario | **300 peticiones/min** (~5 QPS) |
| Por proyecto | 120 000/min y 86,4 M/día |
| Apps sin verificar | Máx. 250 QPS en total |
| Exceso | HTTP 429 ⇒ *backoff* exponencial con *jitter* (RNF-DIS-04) |

El cliente implementa un *token bucket* por usuario (≤ 4 peticiones/s) y prioriza: primero sueño y vitales de la última noche, luego FC del ciclo actual, luego el resto.

### 5.4 Granularidad y almacenamiento

Las condiciones de la API exigen **guardar los datos con la misma granularidad con la que se obtienen** (p. ej. no convertir datos por minuto en totales diarios). Decisión:

- FC continua: se obtiene con `rollUp` de **60 s** (media, mín., máx.) y se guarda por minuto (`hr_minute`); es la granularidad obtenida.
- FC de **1 s** solo dentro de sesiones de ejercicio (`hr_samples`), para curvas y zonas detalladas.
- Nunca se sustituye un dato guardado por un agregado; la retención borra datos completos, no los «resume» (doc. 09 §6).

## 6. Sincronización

### 6.1 *Backfill* al vincular (RF-SYN-01)

Por tipo de dato, de la fecha más reciente a la más antigua, en trozos que respetan los rangos máximos (14 días para `heart-rate` con `rollUp`). 90 días por defecto ⇒ ~7 peticiones de FC + unas pocas por tipo ⇒ muy por debajo de la cuota por usuario. Primero se importan las **últimas 30 noches** de sueño y vitales para calibrar cuanto antes.

### 6.2 *Webhooks* ([guía](https://developers.google.com/health/webhooks))

- **Registro** (una vez por proyecto, con la cuenta de servicio): `POST https://health.googleapis.com/v4/projects/{número-de-proyecto}/subscribers?subscriberId=<id>` con `endpointUri`, `subscriberConfigs[].dataTypes` + `subscriptionCreatePolicy: AUTOMATIC` (se suscribe automáticamente a todo usuario que conceda los ámbitos) y `endpointAuthorization.secret`.
- **Verificación del endpoint**: Google envía dos POST `{"type":"verification"}` (con y sin el secreto): responder 200/201 al autorizado y 401/403 al otro.
- **Autenticidad** (RNF-SEG-10): comprobar la cabecera `Authorization` (secreto) **y** la firma `GOOGLE-HEALTH-API-SIGNATURE` con Tink (`PublicKeyVerify`, ECDSA P-256/SHA-256) usando el conjunto de claves público de `https://www.gstatic.com/googlehealthapi/webhooks/webhooks_public_keyset.json` (rotación cada 30 días ⇒ caché con refresco).
- **Respuesta**: `204 No Content` inmediato y procesamiento asíncrono (encolar). Si no se responde 204, Google reintenta hasta 7 días con *backoff*.
- **Contenido**: solo notifica (sin valores): `healthUserId`, `operation` (`UPSERT`/`DELETE`), `dataType` e intervalos; hasta 99 mensajes por lote; pueden llegar duplicados ⇒ procesamiento idempotente.
- **Acción**: para cada intervalo notificado, re-consultar ese intervalo del tipo indicado; `DELETE` ⇒ borrar nuestra copia y recalcular.
- **Tipos cubiertos** relevantes: `heart-rate`, `heart-rate-variability`, `daily-heart-rate-variability`, `daily-resting-heart-rate`, `daily-oxygen-saturation`, `daily-respiratory-rate`, `respiratory-rate-sleep-summary`, `daily-sleep-temperature-derivations`, `sleep`, `steps`, `distance`, `exercise`, `active-zone-minutes`, `time-in-heart-rate-zone`, `sedentary-period`, `run-vo2-max`. **No cubiertos**: `oxygen-saturation` (muestras), `vo2-max`, `daily-vo2-max`, `total-calories` ⇒ se leen con el sondeo.
- No se notifican eventos anteriores a la creación del suscriptor ⇒ el *backfill* es imprescindible.

### 6.3 Sondeo de seguridad

Además de los *webhooks* (que pueden perderse si el endpoint falla > 7 días): re-lectura de las últimas 48 h cada 6 h, en la ventana matinal cada 15 min si aún no hay sueño de la noche (doc. 08 §3.3), y al abrir la app (RF-SYN-03). `pairedDevices.lastSyncTime` evita consultas inútiles si la pulsera no ha sincronizado.

### 6.4 Revocación y errores

- `invalid_grant` al refrescar ⇒ conexión `needs_reauth` + aviso NOT-07 (RF-CON-04).
- Los eventos de sistema `user-revoked-access` / `user-deleted` pueden no notificarse; opcionalmente, integrar **RISC (Protección entre cuentas)** de Google para enterarse de revocaciones.
- Al desvincular (RF-CON-03): llamar al endpoint de revocación, borrar los *tokens* y preguntar si se conservan o borran los datos.

## 7. Cumplimiento de políticas (lista de comprobación)

Fuentes: [Términos para desarrolladores](https://developers.google.com/health/policies/health-api-developer-terms-and-conditions), [Política de datos de usuario](https://developers.google.com/health/policies/health-api-developer-user-data-policy), [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), [Promoción y marca](https://developers.google.com/health/promote).

- [ ] Uso solo para funciones de salud y bienestar visibles para el usuario; *Limited Use* también para datos derivados y anonimizados.
- [ ] Prohibido: vender o transferir datos a plataformas publicitarias o *data brokers* (aunque estén anonimizados), publicidad, decisiones de crédito/préstamo, funciones reguladas como producto sanitario, usos críticos para la vida e investigación sin la política específica de investigación.
- [ ] Declaración **literal** en la web o política de privacidad: *«The use of information received from Google Health API and/or Developer Tools will adhere to the Google Health API Developer and User Data Policy, including the Limited Use requirements.»* (con traducción informativa al español al lado).
- [ ] Divulgación destacada en la app justo antes de la pantalla de consentimiento (§4).
- [ ] Política de privacidad que explique qué se comparte, dónde se guarda y qué pasa al borrar; ayuda sobre cómo borrar los datos.
- [ ] Datos y *tokens* cifrados en reposo con claves gestionadas en KMS/HSM (RNF-SEG-04).
- [ ] Granularidad de almacenamiento (§5.4).
- [ ] Marca: escribir «Google Health» / «app Google Health» sin traducir; no usar logotipos antiguos de Fitbit o Google Fit; mostrar «Conectado a Google Health» con la hora de la última sincronización y la opción **Desconectar a 1–2 toques** (RF-CON-02/03).
- [ ] Transferencia al proveedor de IA del Coach: permitida solo como parte de una función visible para el usuario, con consentimiento, y **sin que el proveedor entrene con los datos** — revisión legal antes de F4 (la política no menciona expresamente el entrenamiento de IA).

## 8. Health Connect (Android, F3)

- Google Health (paquete `com.fitbit.FitbitMobile`) escribe en Health Connect: pasos, distancia, ejercicio, sueño con fases, FC, HRV, FC en reposo, FR, temperatura cutánea, VO₂ máx., entre otros; **no escribe SpO₂** ([ayuda](https://support.google.com/googlehealth/answer/14506680)).
- Registros a leer: `HeartRateRecord`, `HeartRateVariabilityRmssdRecord`, `RestingHeartRateRecord`, `RespiratoryRateRecord`, `SkinTemperatureRecord`, `SleepSessionRecord`, `StepsRecord`, `ExerciseSessionRecord`, `Vo2MaxRecord` [verificar densidad de escritura].
- Requisitos: Health Connect en Android 9+ (integrado desde Android 14); permisos de lectura por tipo; `READ_HEALTH_DATA_IN_BACKGROUND` para lecturas en segundo plano; `READ_HEALTH_DATA_HISTORY` para > 30 días; declaración de apps de salud y justificación por permiso en Play Console ([guía](https://developer.android.com/health-and-fitness/health-connect/publish)).
- Los datos de Health Connect se marcan `source = health_connect` y se deduplican con los de la API por intervalo y tipo; la API sigue siendo la fuente de verdad.

## 9. FC en vivo por Bluetooth (opcional, F3+)

Si el usuario activa la emisión de FC en la Fitbit Air, la pulsera usa el perfil estándar de FC de Bluetooth (servicio GATT `0x180D`, característica `0x2A37`). La app podría mostrar FC y zonas en vivo durante un entrenamiento. Es un perfil **estándar** (no propietario, compatible con RL-62). Viabilidad con apps de terceros no listadas por Google: [verificar] en el *spike*.
