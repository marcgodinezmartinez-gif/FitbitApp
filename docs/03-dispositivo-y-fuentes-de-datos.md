# 03 · La Google Fitbit Air y las fuentes de datos

Estado de la información: **28/09/2026**. Fuentes oficiales de Google salvo que se indique «reseña». Lo marcado como **[verificar]** debe confirmarse en el *spike* de F0 (hito H0).

---

## 1. La pulsera

| Aspecto | Dato | Fuente |
|---|---|---|
| Lanzamiento | Anunciada el 07/05/2026; a la venta desde el 26/05/2026 | [Blog de Google](https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/), [Android Central](https://www.androidcentral.com/wearables/fitbit/google-fitbit-air-launch-specs-price) |
| Precio | 99,99 $ / **99,99 €** en la Google Store de España; sin suscripción obligatoria | [Google Store ES](https://store.google.com/es/product/google_fitbit_air?hl=es) |
| Formato | «Pebble» sin pantalla ni botones que se encaja en correas intercambiables; 5,2 g (12 g con correa); 34,9 × 17 × 8,3 mm; LED de estado con doble toque | [Especificaciones](https://store.google.com/us/product/google_fitbit_air_specs), [ayuda](https://support.google.com/googlehealth/answer/17033101) |
| Sensores | FC óptica (PPG), sensores rojo e infrarrojo (SpO₂), acelerómetro y giroscopio de 3 ejes, sensor de temperatura del dispositivo (variación de temperatura cutánea), **motor de vibración** | [Especificaciones](https://store.google.com/us/product/google_fitbit_air_specs) |
| No tiene | Altímetro, ECG, EDA, GPS (usa el del móvil), NFC | Especificaciones; reseña de [9to5Google](https://9to5google.com/2026/05/28/fitbit-air-review/) |
| Batería | Hasta 7 días (menos con SpO₂); carga completa en 90 min, 5 min ≈ 1 día | [Google Store](https://store.google.com/us/product/google_fitbit_air) |
| Resistencia al agua | 50 m | Especificaciones |
| Conectividad | Bluetooth 5.0 | Especificaciones |
| Memoria interna | 7 días de datos de movimiento por minuto, 30 días de totales diarios, FC cada 2 s, 1 día de entrenamiento; lo no sincronizado en 7 días puede perderse | [Especificaciones UK](https://store.google.com/gb/product/google_fitbit_air_specs), [ayuda](https://support.google.com/googlehealth/answer/14236719) |
| FC en vivo por Bluetooth | Emite FC con el **perfil estándar de FC de Bluetooth** hacia apps/equipos compatibles (Peloton, Zwift, Wahoo, Strava) | [Ayuda](https://support.google.com/googlehealth/answer/14236705) |
| Requisitos del móvil | Android 11+ o iOS 16.4+ con la app **Google Health** | [Blog de Google](https://blog.google/products-and-platforms/devices/fitbit/fitbit-air/) |

**App oficial**: la app Fitbit pasó a llamarse **Google Health** a partir del 19/05/2026 (y Fitbit Premium → **Google Health Premium**); requiere cuenta de Google ([ayuda](https://support.google.com/googlehealth/answer/17068213)).

## 2. Lo que ya ofrece Google Health con la Fitbit Air

| Función oficial | ¿Gratis? | ¿Accesible para nuestra app? | Comentario |
|---|---|---|---|
| FC 24/7, FC en reposo, HRV (RMSSD del sueño más largo > 3 h), SpO₂ nocturna, frecuencia respiratoria, variación de temperatura (requiere 3 noches) | Sí | **Sí** (API) | Base de nuestras métricas |
| Fases del sueño | Sí | **Sí** (API) | |
| *Sleep Score* (0–100) | Sí | **No** (no está en la API) | Calculamos el nuestro |
| *Daily Readiness* (1–100; HRV + FCR + sueño; 7 noches de base) | Sí | **No** | Nuestra «Recuperación» es el equivalente |
| *Cardio Load* (modelo TRIMP) y *Target Load* semanal | Sí | **No** | Nuestra «Carga» es el equivalente |
| *Resilience* (estrés: óptimo/equilibrado/bajo) | Sí | **No** | Nuestro «Estrés» es independiente |
| Minutos en Zona Activa, pasos, distancia, calorías | Sí | **Sí** | Contexto de actividad |
| Detección automática de ejercicio (andar, correr, bici, deportes, elíptica, remo, bici estática) | Sí | **Sí** (sesiones `exercise`) | Base de entrenamientos |
| VO₂ máx. (solo carreras al aire libre con GPS del móvil) | Sí | **Sí** | Irregular para quien no corre |
| Notificaciones de ritmo irregular (FA) y alertas de FC alta/baja | Sí | Fuera de alcance (RL-03) | Producto sanitario |
| *Smart Wake* y alarma silenciosa con vibración | Sí | **No** (no hay API para la vibración) | RF-W-04 |
| Coach con Gemini, planes, informes | **Premium** (8,99 €/mes en España) | No | Nuestro Coach IA (doc. 06) |

Fuentes: [Readiness](https://support.google.com/googlehealth/answer/14236710), [Cardio Load](https://support.google.com/googlehealth/answer/15402655), [sueño](https://support.google.com/googlehealth/answer/14236513), [vitales](https://support.google.com/googlehealth/answer/14236917), [HRV](https://support.google.com/googlehealth/answer/14237938), [VO₂ máx.](https://support.google.com/googlehealth/answer/14237924), [alarmas](https://support.google.com/googlehealth/answer/14226604), [Premium](https://support.google.com/googlehealth/answer/14237941).

**Conclusión**: los datos brutos que necesitamos son gratuitos y accesibles; las puntuaciones de Google no se exponen, así que **todas nuestras puntuaciones se calculan en nuestro backend** (doc. 05). La suscripción Premium no es necesaria (resuelve el supuesto SUP-4, pendiente de confirmación empírica).

## 3. Canales de acceso a los datos

| Canal | Plataforma | Qué ofrece | Limitaciones | Uso en la app |
|---|---|---|---|---|
| **Google Health API** (REST v4) | Cualquiera (servidor) | Todos los datos de la tabla §4, histórico sin límite, notificaciones *webhook* | Ámbitos **restringidos**: > 100 usuarios exige verificación + evaluación CASA anual; cuotas | **Fuente principal** (ADR 001, doc. 10) |
| Health Connect | Android 9+ (en el dispositivo) | Google Health escribe pasos, distancia, ejercicio, sueño con fases, FC, HRV, FC en reposo, FR, temperatura cutánea, VO₂ máx.… | **No escribe SpO₂**; sin histórico > 30 días sin permiso adicional; solo Android | Complementaria en Android (F3, ADR 002) |
| Apple Health (HealthKit) | iOS | Google Health escribe pasos, ejercicio, sueño con fases, FC, **SpO₂**, FR, FC en reposo… | **No escribe HRV ni temperatura cutánea** ⇒ insuficiente para la recuperación | No se usa |
| Perfil de FC de Bluetooth (GATT estándar) | iOS/Android | FC en vivo mientras la emisión está activada | Solo en vivo, sin HRV; [verificar] compatibilidad con apps de terceros no listadas | Opcional F3+: FC en vivo durante entrenamientos |
| Google Takeout | Manual | Exportación completa de la cuenta | Manual, formato propio | Solo para análisis/calibración puntual |
| Agregadores (p. ej. Junction, que ya lista `google_health`; Open Wearables, *open source* MIT y autoalojado) | Servidor | Abstracción multi-dispositivo | Coste (p. ej. Junction desde 300 $/mes) o mantenimiento propio | Plan B (RSK-02) |
| Fitbit Web API (antigua) | — | — | **Se apaga el 30/09/2026**; sin altas nuevas | No se usa |

Fuentes: [Health Connect](https://support.google.com/googlehealth/answer/14506680), [Apple Health](https://support.google.com/googlehealth/answer/17037331), [FC por Bluetooth](https://support.google.com/googlehealth/answer/14236705), [exportación](https://support.google.com/googlehealth/answer/14236615), [Junction](https://docs.junction.com/wearables/providers/introduction), [Open Wearables](https://github.com/the-momentum/open-wearables), [fin de la Fitbit Web API](https://support.google.com/googlehealth/thread/439040688).

## 4. Catálogo de datos de la Fitbit Air en la Google Health API

Tipos compatibles con la Fitbit Air según la [tabla de compatibilidad](https://developers.google.com/health/data-types/device-compatibility) y el [catálogo de tipos](https://developers.google.com/health/data-types). Ámbitos con prefijo `https://www.googleapis.com/auth/googlehealth`.

| Tipo (`dataType`) | Contenido | Resolución / registro | Ámbito | *Webhook* | Uso en la app |
|---|---|---|---|---|---|
| `heart-rate` | FC | Muestras, almacenamiento a **1 s** | `.health_metrics_and_measurements.readonly` | Sí | Carga, zonas, estrés, curvas |
| `daily-resting-heart-rate` | FC en reposo diaria | Diario | idem | Sí | Recuperación, líneas base, carga |
| `heart-rate-variability` | Muestras nocturnas de RMSSD (y SDNN) | Muestras [verificar cadencia; la API antigua daba 5 min] | idem | Sí | HRV detallada, cobertura |
| `daily-heart-rate-variability` | RMSSD medio de la noche, RMSSD en sueño profundo, FC no-REM, entropía | Diario | idem | Sí | **Recuperación** (componente principal) |
| `oxygen-saturation` / `daily-oxygen-saturation` | SpO₂ nocturna (muestras / media y límites) | Muestras / diario | idem | Solo el diario | Recuperación (penalización), monitor de salud |
| `daily-respiratory-rate` / `respiratory-rate-sleep-summary` | FR nocturna (diaria / por fase) | Diario / resumen | idem | Sí | Recuperación, monitor de salud |
| `daily-sleep-temperature-derivations` | Temperatura cutánea nocturna absoluta, base de 30 días y su desviación típica | Diario | idem | Sí | Recuperación, monitor de salud |
| `sleep` | Sesiones con fases (ligero, profundo, REM, despierto), despertares breves, resumen | Sesión, 1 min | `.sleep.readonly` | Sí | **Sueño**, ciclos |
| `steps`, `distance`, `total-calories` | Actividad | Intervalos de 1 min | `.activity_and_fitness.readonly` | Sí (calorías: no) | Contexto, exclusión de movimiento en estrés |
| `active-minutes`, `active-zone-minutes`, `time-in-heart-rate-zone`, `sedentary-period`, `activity-level` | Actividad por intensidad | 1 min | idem | Mayoría sí | Contexto, edad fisiológica |
| `exercise` | Sesiones de ejercicio: tipo, FC media, tiempo por zonas, AZM, VO₂ máx. de carrera | Sesión | idem | Sí | **Entrenamientos** |
| `vo2-max`, `daily-vo2-max`, `run-vo2-max` | VO₂ máx. estimado | Muestra / diario | idem | Solo `run-vo2-max` | Monitor de salud, edad fisiológica |
| Perfil (`users/me/profile`), ajustes (`settings`: zona horaria), dispositivos (`pairedDevices`: última sincronización) | Contexto | — | `.profile.readonly`, `.settings.readonly` | — | Edad, zona horaria, estado de sincronización |

No disponibles en la API: *Readiness*, *Sleep Score*, *Cardio Load*, *Resilience*/estrés; datos menstruales (solo escritura); pisos y altitud (la Air no tiene altímetro). La tabla de compatibilidad también cita `respiratory-rate` y `skin-temperature` para la Air, pero aún no figuran en el catálogo principal (la temperatura granular está en la hoja de ruta) [verificar].

## 5. Brechas frente a WHOOP y cómo se cubren

| Brecha | Impacto | Solución en la app |
|---|---|---|
| HRV **solo nocturna** (no hay HRV diurna) | No se puede estimar el estrés diurno por HRV como hacen algunos dispositivos | Estrés basado en FC + movimiento, etiquetado «beta» (ALG-EST-01) |
| Sin datos en tiempo real desde la nube: dependen de que la pulsera sincronice con la app Google Health | La recuperación puede llegar tarde si no se abre Google Health | Sondeo en ventana matinal + *webhooks* + atajo «Abrir Google Health» (doc. 11 §6) |
| Batería de 7 días (WHOOP ≈ 14) y carga fuera de la muñeca | Huecos de datos | Recordatorio de cargar de día (p. ej. durante la ducha); tratamiento explícito de huecos |
| Sin acelerómetro bruto ni detección de series | No hay «carga muscular» automática | sRPE y registro manual de fuerza (ALG-CAR-05) |
| Detección automática de 7 tipos de ejercicio (WHOOP 45+) | Entrenamientos mal etiquetados | Edición del tipo y creación manual (RF-ENT-04/06) |
| VO₂ máx. solo con carreras al aire libre y GPS del móvil | Edad fisiológica incompleta para quien no corre | Estimación sin ejercicio a partir de perfil y FCR como alternativa marcada (ALG-EDA-01) [verificar referencia] |
| Precisión de FC variable en algunos entrenamientos (reseñas: picos de +20–40 lpm) y HRV que lee más baja que otros dispositivos | Carga inflada puntualmente; valores absolutos no comparables con WHOOP | Filtros de artefactos (ALG-VAL); todo relativo a la línea base propia; edición de actividades |
| Alarma con vibración solo desde la app oficial | Sin alarma háptica propia | Alarma del móvil por necesidad de sueño (RF-SUE-12, «C») |

Reseñas: [DC Rainmaker, Fitbit Air vs WHOOP](https://www.dcrainmaker.com/2026/05/fitbit-review-vs-whoop.html), [comparativa de precisión (ago. 2026)](https://www.dcrainmaker.com/2026/08/accuracy-deep-dive-garmin-cirqa-whoop-fitbit-air-amazfit-helio-polar-loop-testing.html), [Android Authority](https://www.androidauthority.com/google-fitbit-air-review-3671325/).

## 6. Degradación según los datos disponibles

| Falta | Efecto |
|---|---|
| HRV de la noche | Sin recuperación ese día («Datos insuficientes»); sueño y carga siguen funcionando |
| Sesión de sueño | Sin sueño ni recuperación; ciclo de reserva 04:00–04:00 |
| FR, SpO₂ o temperatura | Recuperación calculada sin ese componente y con confianza reducida |
| FC intradía de un periodo | Carga y estrés parciales con confianza baja; se indica el hueco |
| Ámbito `.sleep.readonly` denegado | Sin sueño ni recuperación: la app lo explica y ofrece conceder el permiso |
| Ámbito `.activity_and_fitness.readonly` denegado | Sin entrenamientos ni pasos; la carga sigue (usa FC) pero sin actividades |
| Ámbito `.health_metrics_and_measurements.readonly` denegado | Sin FC, HRV ni vitales: la app no puede ofrecer su propuesta principal |

## 7. Qué debe medir el *spike* de F0

1. Frecuencia real de las muestras de `heart-rate` en reposo, en ejercicio y durante el sueño.
2. Cadencia y cobertura de `heart-rate-variability` durante la noche; campos exactos de `daily-heart-rate-variability`.
3. Latencia entre la sincronización de la pulsera (`pairedDevices.lastSyncTime`) y la disponibilidad en la API, y entre ésta y la llegada del *webhook*.
4. Estructura de `sleep` (fases, despertares breves, sueño principal vs siestas) y si incluye latencia de inicio.
5. Campos de `daily-sleep-temperature-derivations`, `daily-respiratory-rate` y `daily-oxygen-saturation`.
6. Qué ocurre con los datos durante la carga de la batería y con sincronizaciones tras varios días sin conexión.
7. Comportamiento del *token* en modo *Testing* (caducidad de 7 días) frente a app sin verificar en producción (doc. 10 §2).
8. Si la emisión de FC por Bluetooth es accesible desde una app propia.
