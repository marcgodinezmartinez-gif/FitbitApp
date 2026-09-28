# 02 · Paridad funcional con WHOOP

Inventario de la app de WHOOP a **septiembre de 2026** (WHOOP 5.0 / MG) y su equivalente en nuestra app con la Fitbit Air. Fuentes: artículos de soporte de WHOOP (support.whoop.com), *The Locker* (whoop.com/thelocker), la [API para desarrolladores de WHOOP](https://developer.whoop.com/api/) y reseñas; ver la lista al final.

Leyenda de viabilidad: ✅ equivalente completo · 🟡 equivalente parcial (limitación de datos del dispositivo o de la API) · ❌ no viable o fuera de alcance.

## 1. Contexto: qué es WHOOP hoy

- **Hardware**: pulsera sin pantalla (PPG, acelerómetro, giroscopio, temperatura cutánea; ~14 días de batería); la versión MG añade ECG en el cierre.
- **Modelo de negocio**: el hardware va incluido en una membresía anual — One 199 $, Peak 239 $, Life 359 $ (MG). La Fitbit Air cuesta 99,99 € en un único pago.
- **Navegación de la app**: pestañas *Home*, *Health*, *Community* y *More*, un botón de IA y un botón «+» de acciones (iniciar actividad, Strength Trainer, diario, sueño manual).
- **Pantalla *Home***: tres diales (Sueño a la izquierda, Recuperación en el centro con verde/amarillo/rojo, Strain a la derecha con su objetivo), perspectiva del día del Coach, «Mi día» (actividades, siestas, sueño de esta noche → planificador), plan semanal, diario, panel de métricas personalizable, tarjetas de estrés y salud, y un calendario coloreado por recuperación.

## 2. Matriz de paridad

| # | Función de WHOOP (nivel) | Qué hace en WHOOP | Nuestro equivalente | Datos de la Fitbit Air | Viab. | Prio. / Fase |
|---|---|---|---|---|---|---|
| 1 | **Recovery** (todos) | 0–100 %; verde ≥ 67, amarillo 34–66, rojo ≤ 33; media de los miembros ≈ 58 %; entradas principales HRV (RMSSD en sueño) y FC en reposo, además de FR, sueño, temperatura y SpO₂ frente a una base de ~30 días; color tras 3 recuperaciones | **Recuperación** (ALG-REC-01) | HRV nocturna, FCR, FR, SpO₂, temperatura, sueño | ✅ | M / F1 |
| 2 | **Day Strain** (todos) | 0–21 logarítmica (ligera 0–9, moderada 10–13, alta 14–17, máxima 18–21); carga cardiovascular por FC relativa a FC máx. y en reposo | **Carga del ciclo** (ALG-CAR-01) | FC a 1 s (usamos 1 min) | ✅ | M / F1 |
| 3 | Activity Strain | Carga por actividad; no se suman linealmente | **Carga de actividad** (ALG-CAR-02) | Sesiones `exercise` + FC | ✅ | S / F2 |
| 4 | **Strain Target** (antes *Strain Coach*) | Objetivo diario según recuperación, carga acumulada, sueño y fase del ciclo; estados óptimo/sobrecarga/restaurador; ajustable; aviso al alcanzarlo | **Carga objetivo** (ALG-CAR-03) con modos Mantener/Progresar/Descargar | Derivado | ✅ | S / F2 |
| 5 | Carga muscular y *Strength Trainer* | Carga muscular estimada por tipo × duración o por series/repeticiones/peso registrados; récords | **sRPE + registro de fuerza** (ALG-CAR-05, RF-ENT-05) | No hay acelerómetro bruto en la API | 🟡 | C / F3 |
| 6 | Zonas de FC 0–5 | Por FC de reserva; FC máx. por fórmula de Gellish ajustada por picos observados | **Zonas de FC** (ALG-CAR-06) | FC | ✅ | S / F2 |
| 7 | Detección automática de actividades | 45 tipos automáticos, mínimo 10 min, fusión de fragmentos, recorte en el gráfico | Actividades detectadas por Google (andar, correr, bici, deportes, elíptica, remo, bici estática) + edición y creación manual | `exercise` | 🟡 | S / F2 |
| 8 | Pasos y calorías | Pasos por acelerómetro; calorías = metabolismo basal + gasto activo por FC | Pasos, distancia y calorías de Google | `steps`, `distance`, `total-calories` | ✅ | S / F1 |
| 9 | **Sleep Performance** (rediseño 05/2025) | Combinación ponderada de suficiencia (horas vs necesidad), constancia, eficiencia y estrés durante el sueño; bandas óptimo/suficiente/bajo | **Rendimiento de sueño** compuesto (ALG-SUE-07) con suficiencia, eficiencia y constancia | Sueño con fases | ✅ (estrés en sueño 🟡) | M / F1 (constancia en F2) |
| 10 | Fases, perturbaciones, ciclos, FR del sueño | Hipnograma, despertares, nº de ciclos, FR mediana | Detalle de sueño (RF-SUE-01/05/11) | `sleep`, FR | ✅ | M / F1 |
| 11 | **Sleep Need** | Base aprendida + carga reciente + deuda − siestas | **Necesidad de sueño** (ALG-SUE-01) | Derivado | ✅ | M / F1 |
| 12 | Deuda de sueño | Parte de la necesidad | **Deuda de sueño** (ALG-SUE-03) | Derivado | ✅ | S / F2 |
| 13 | **Sleep Planner** | «Alcanzar necesidad» (70/85/100 %) o «Mejorar mi sueño» (cambios graduales de horario); aviso de hora de acostarse | **Planificador** (ALG-SUE-05) con ambos modos | Derivado | ✅ | S / F2 |
| 14 | Alarma háptica | Hora exacta, objetivo de sueño o «en verde»; vibra en la muñeca | Alarma **del móvil** por necesidad cumplida | Sin API para la vibración de la pulsera | 🟡 | C / F3 |
| 15 | **Stress Monitor** (Peak/Life) | 0–3 en vivo con FC y HRV frente a base de 14 días, descontando movimiento; respiración guiada (relajación/activación); resumen nocturno | **Estrés** (ALG-EST-01) + respiración guiada | Solo FC diurna (HRV solo nocturna) | 🟡 | S / F2 |
| 16 | **Health Monitor** (Peak/Life) | Vitales de la noche frente a la base con indicador verde/naranja/rojo; informe PDF de 30/180 días | **Monitor de salud** (ALG-SAL-01) + informe PDF | Vitales nocturnos | ✅ | S / F2 (PDF: C / F3) |
| 17 | **Healthspan / WHOOP Age / Pace of Aging** (Peak/Life) | Edad a partir de medias de 6 meses de 9 métricas (horas y constancia del sueño, tiempo en zonas 1–3 y 4–5, fuerza, pasos, FCR, VO₂ máx., masa magra) convertidas con razones de riesgo de mortalidad y corrección de solapamiento (Gompertz); ritmo de envejecimiento de 30 días; semanal | **Edad fisiológica** y ritmo de envejecimiento (ALG-EDA-01) | Pasos, zonas, sueño, FCR, VO₂ máx. (solo con carreras con GPS); sin masa magra | 🟡 | C / F3 |
| 18 | VO₂ máx. | Estimación semanal con FCR, HRV, ejercicio, carreras GPS y perfil | VO₂ máx. de Google + estimación propia sin ejercicio como alternativa | `vo2-max`, `run-vo2-max` | 🟡 | C / F2 |
| 19 | *Heart Screener* (ECG) y notificaciones de ritmo irregular (Life/MG) | ECG de 30 s con autorización FDA; cribado pasivo de FA | — (la app Google Health ya ofrece avisos de ritmo irregular con la Air) | Sin ECG | ❌ | W (RL-03) |
| 20 | *Blood Pressure Insights* (Life/MG) | Estimación matinal de tensión calibrada con tensiómetro; carta de advertencia de la FDA (07/2025) cerrada en 06/2026 tras cambiar la presentación | — | — | ❌ | W |
| 21 | *Advanced Labs* y registros médicos | Analíticas de sangre (EE. UU.) y subida de resultados; importación de historia clínica | — | — | ❌ | W |
| 22 | **Journal** + *Behavior Insights* | 160+ hábitos en 9 categorías; pregunta matinal; hábitos propios; voz; impacto sobre la recuperación con ≥ 5 «sí» y ≥ 5 «no» | **Diario** + **impacto de hábitos** (ALG-DIA-01) | Derivado + respuestas | ✅ | S / F2–F3 |
| 23 | *Weekly Plan* | Planes predefinidos u objetivos propios (sueño, carga, minutos en zona, frecuencia, hábitos, pasos, fuerza); revisión el viernes y resumen el lunes | **Plan semanal** (RF-PLA) | Derivado | ✅ | C / F3 |
| 24 | *Trends* | Vistas semanal/mensual/6 meses con resumen IA | **Tendencias** (RF-TEN) + resumen IA | Derivado | ✅ | S / F2 |
| 25 | Informes | Las evaluaciones semanales/mensuales en la app se retiraron en 05/2025; ahora «Month in Review» por email y resumen anual | **Informes semanal y mensual en la app** + resumen anual | Derivado | ✅ | S / F2–F3 |
| 26 | **WHOOP AI** | Chat con contexto de pantalla, perspectiva matinal, revisión del día con franja para acostarse, análisis de actividades, creación de entrenamientos y hábitos, gráficos, *jet lag*, avisos proactivos; memoria editable; modo «solo educativo» | **Coach IA** con Claude (doc. 06) | Derivado | ✅ | S / F3 |
| 27 | Salud femenina | Fases del ciclo (registro + FCR + temperatura), síntomas, embarazo/posparto; ajusta recuperación y objetivos | — | La API solo permite **escribir** datos menstruales | ❌ (por ahora) | W / F4 |
| 28 | Comunidad | Equipos, clasificaciones, chat, rachas | Rachas (C); equipos: W | — | 🟡 | C / F2; W |
| 29 | Integraciones | Apple Health, Health Connect, Strava, Peloton, TrainingPeaks… | Google Health ya agrega datos de otras apps (Health Connect) | — | 🟡 | W / F4 |
| 30 | Emisión de FC en vivo | La pulsera emite FC por Bluetooth | La Air ya la emite; nuestra app puede mostrar FC en vivo | Perfil estándar de FC | 🟡 | C / F3+ |
| 31 | *Widgets* y Live Activities | iOS (inicio, bloqueo, Live Activities) y Android | *Widgets* de diales | Derivado | ✅ | C / F3 |
| 32 | Exportación | CSV por email en 24 h | Exportación JSON + CSV (RF-PRI-01) | — | ✅ | M / F2 |
| 33 | Calendario coloreado por recuperación | En *Home* | Calendario en Tendencias/Hoy | Derivado | ✅ | S / F2 |
| 34 | Calibración escalonada | Color de recuperación tras 3; constancia tras 3–5; temperatura/monitor tras 7; VO₂ máx. 14 en 21 días; *Healthspan* 21 en 31 (completo a 90) | Calendario de calibración propio (doc. 05 §11) | — | ✅ | M / F1 |

## 3. Qué aportamos que WHOOP no tiene

- **Sin cuota**: Fitbit Air (pago único) + coste de operación propio (doc. 15 §6).
- **Algoritmos abiertos y explicados** con referencias científicas y versión visible (RF-PER-04).
- **Informes semanales y mensuales dentro de la app** (WHOOP los pasó a email).
- **Datos en la UE**, exportación completa y borrado inmediato.
- **Coach con «Datos usados»** visible bajo cada respuesta y modo solo educativo.

## 4. Diferencias de datos que hay que asumir

1. Estrés diurno sin HRV (solo FC) ⇒ métrica «beta».
2. Sin carga muscular automática ⇒ sRPE y registro manual.
3. Sin alarma háptica propia ⇒ alarma del móvil.
4. Latencia: los datos llegan cuando la pulsera sincroniza con Google Health, no en tiempo real.
5. Menos tipos de actividad detectados automáticamente ⇒ edición sencilla.

## 5. Referencia de esquema: API de WHOOP

La [API v2 de WHOOP](https://developer.whoop.com/api/) organiza los datos en *Cycle*, *Recovery*, *Sleep* y *Workout*. Nuestro modelo (doc. 09) mantiene una estructura análoga para facilitar comparaciones:

| WHOOP (campo) | Nuestro modelo |
|---|---|
| `cycle.score.strain`, `kilojoule`, `average_heart_rate`, `max_heart_rate` | `strain_scores.strain`, `daily_source_metrics.calories_kcal`, agregados de `hr_minute` |
| `recovery.score.recovery_score`, `resting_heart_rate`, `hrv_rmssd_milli`, `spo2_percentage`, `skin_temp_celsius`, `user_calibrating` | `recovery_scores.score`, `components`, `confidence` |
| `sleep.score.stage_summary.*` (en cama, despierto, ligero, profundo, REM, ciclos, perturbaciones) | `sleep_sessions`, `sleep_stages`, `sleep_scores` |
| `sleep.score.sleep_needed.{baseline, need_from_sleep_debt, need_from_recent_strain, need_from_recent_nap}` | `sleep_scores.need_breakdown` |
| `sleep_performance_percentage`, `sleep_consistency_percentage`, `sleep_efficiency_percentage`, `respiratory_rate` | `sleep_scores.performance`, `sri_7d`, `efficiency`, FR diaria |
| `workout.score.strain`, `zone_durations.zone_zero…zone_five` | `activity_strain.strain`, `zone_minutes` |

## Fuentes principales

- Soporte de WHOOP: [Recovery](https://support.whoop.com/s/article/WHOOP-Recovery), [Strain](https://support.whoop.com/s/article/WHOOP-Strain), [Sleep](https://support.whoop.com/s/article/WHOOP-Sleep), [Stress Monitor](https://support.whoop.com/s/article/Get-to-Know-the-Stress-Monitor), [Health Monitor](https://support.whoop.com/s/article/WHOOP-Health-Monitor-Report), [Healthspan](https://support.whoop.com/s/article/Healthspan-WHOOP-Age-Pace-of-Aging-Guide), [Journal](https://support.whoop.com/s/article/WHOOP-Journal-Overview), [Weekly Plan](https://support.whoop.com/s/article/Weekly-Plan), [calibración](https://support.whoop.com/s/article/Calibration-Timeline), [precios](https://support.whoop.com/s/article/Membership-Pricing), [navegación](https://support.whoop.com/s/article/Navigating-the-WHOOP-Mobile-App), [Coach IA](https://support.whoop.com/s/article/How-to-Use-the-AI-Powered-WHOOP-Coach).
- *The Locker*: [cómo funciona Recovery](https://www.whoop.com/us/en/thelocker/how-does-whoop-recovery-work-101/), [cómo funciona Strain](https://www.whoop.com/us/en/thelocker/how-does-whoop-strain-work-101/), [carga muscular](https://www.whoop.com/us/en/thelocker/how-whoop-measures-muscular-load/), [Healthspan](https://www.whoop.com/us/en/thelocker/healthspan/), [novedades 2026](https://www.whoop.com/us/en/thelocker/2026-whats-new/).
- Desarrolladores: [API](https://developer.whoop.com/api/), [webhooks](https://developer.whoop.com/docs/developing/webhooks).
- Terceros: [FDA — carta de advertencia (07/2025)](https://www.fda.gov/inspections-compliance-enforcement-and-criminal-investigations/warning-letters/whoop-inc-709755-07142025), [validación de HRV de WHOOP (PMC8160717)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8160717/), [DC Rainmaker: Fitbit Air vs WHOOP](https://www.dcrainmaker.com/2026/05/fitbit-review-vs-whoop.html).
