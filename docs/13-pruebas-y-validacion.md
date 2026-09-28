# 13 · Estrategia de pruebas y validación científica

Una app tipo WHOOP tiene dos tipos de riesgo de calidad distintos:

1. **Riesgo de software** (¿el código hace lo que dice la especificación?) → pruebas clásicas (§1–§5).
2. **Riesgo de validez** (¿las puntuaciones significan algo útil para la persona?) → validación científica de los algoritmos (§6) y del Coach IA (§7).

Ambos son requisitos: una métrica sin validar **no se muestra como definitiva** (se marca como «beta» en la UI).

---

## 1. Pirámide de pruebas

| Nivel | Qué cubre | Herramientas sugeridas | Umbral |
|---|---|---|---|
| Unitarias | Paquete de métricas (funciones puras), utilidades de fechas/zonas horarias, mapeo de datos de la API | Vitest/Jest (TS) o pytest | ≥ 90 % líneas en métricas (RNF-MAN-02) |
| Propiedades | Invariantes de los algoritmos (ver §2) | fast-check / Hypothesis | Todas las invariantes en CI |
| *Golden files* | Resultado exacto de cada `algorithm_version` sobre datasets fijos | Snapshots versionados | 0 diferencias no explicadas |
| Contrato | Forma de las respuestas de la Google Health API | Fixtures grabadas + validación de esquema (zod/JSON Schema) | Ejecutar también a diario contra la API real con la cuenta de pruebas |
| Integración | API propia + BD + colas + adaptador de Google (simulado) | Testcontainers (PostgreSQL), servidor simulado (MSW/WireMock) | Flujos de sincronización, idempotencia, reintentos |
| E2E móvil | Onboarding, vinculación, pantalla Hoy, diario, borrado de cuenta | Maestro o Detox | Flujos críticos en cada *release* |
| No funcionales | Rendimiento, accesibilidad, seguridad | k6, Accessibility Scanner/Inspector, OWASP ZAP, MobSF | Objetivos del doc. 07 |

## 2. Invariantes de los algoritmos (pruebas de propiedades)

Con el resto de entradas fijas:

- **Recuperación** es monótona **creciente** en ln(RMSSD) y en rendimiento de sueño, y monótona **decreciente** en FC en reposo, en frecuencia respiratoria por encima de la base y en temperatura por encima de la base. Siempre en [0, 100].
- **Carga (0–21)** es monótona creciente en el tiempo pasado en cada zona de FC; nunca supera 21; un día sin datos de FC da «sin datos», no 0.
- **Rendimiento de sueño** ∈ [0, 100]; dormir más minutos (misma necesidad) nunca reduce el rendimiento.
- **Deuda de sueño** ≥ 0 y nunca crece si se duerme ≥ la necesidad.
- **Estrés** ∈ [0, 3]; minutos con actividad física detectada no suman estrés.
- Cambiar la zona horaria de visualización no cambia ningún valor calculado (solo su presentación).
- Los recálculos con datos repetidos (misma muestra dos veces) dan el mismo resultado (idempotencia de la ingesta).

## 3. Datasets de prueba

| Dataset | Contenido | Uso |
|---|---|---|
| `synthetic/basic` | 60 días generados: sueño 7–8 h, RMSSD log-normal estable, 3 entrenamientos/semana | Golden files, regresión |
| `synthetic/illness` | Igual, con 3 días de FC reposo +8 lpm, RR +2 rpm, temperatura +0,8 °C | Alertas del monitor de salud (ALG-SAL-01, doc. 05 §7) |
| `synthetic/overreaching` | 3 semanas de carga creciente con HRV descendente | Recuperación, relación carga aguda/crónica |
| `synthetic/gaps` | Noches sin datos, días sin llevar la pulsera, sincronizaciones tardías | Estados de «datos insuficientes», recálculo |
| `synthetic/dst-travel` | Cambio de hora y viaje con cambio de zona horaria | Cálculo de ciclos y noches |
| `real/owner` | Exportación anonimizada de los datos del propietario (con su consentimiento) | Calibración y validación (§6) — **nunca** en el repositorio público |

## 4. Pruebas de la integración con la Google Health API

- Cuenta de Google de pruebas con un Fitbit Air real llevando la pulsera ≥ 14 días antes de F1 (*spike* de datos en F0).
- Casos obligatorios: primera vinculación, renovación del *token*, revocación desde la cuenta de Google, ámbitos denegados parcialmente, notificación duplicada, notificación fuera de orden, 429 con `Retry-After`, 5xx, cambio del esquema (campo nuevo desconocido ⇒ se ignora sin fallar).
- Prueba nocturna (*canary*) contra la API real que valida que el contrato no ha cambiado; si falla, alerta (RNF-OBS-03).

## 5. Seguridad y privacidad

- SAST (CodeQL/Semgrep) y escaneo de secretos en cada PR; DAST (ZAP) semanal contra *staging*.
- Checklist OWASP MASTG antes de cada publicación en tiendas.
- Test automático que ejecuta los flujos principales y busca en los logs patrones de datos de salud y *tokens* (debe dar 0 coincidencias).
- Prueba de borrado de cuenta: tras la solicitud no quedan filas del usuario (salvo el registro legal mínimo) y el *token* está revocado en Google.
- Pentest externo antes de F4 (RNF-SEG-14).

## 6. Validación científica de las métricas

Objetivo: demostrar que las puntuaciones son **estables, sensibles y coherentes** con referencias razonables. No se pretende validación clínica (la app no es un producto sanitario; ver doc. 12).

| Métrica | Referencia de comparación | Criterio de aceptación inicial |
|---|---|---|
| Recuperación | Autoevaluación matinal de 1 a 5 («¿Cómo de recuperado te sientes?») registrada en el diario durante ≥ 30 días | Correlación de Spearman ρ ≥ 0,3 entre recuperación y autoevaluación |
| Recuperación | Puntuación de *Daily Readiness* de Google (si la API la expone) | ρ ≥ 0,5 (coherencia, **no** verdad absoluta) |
| Carga | RPE de sesión (escala CR-10 × minutos, método de Foster) registrado tras cada entrenamiento | ρ ≥ 0,6 entre carga de actividad y sRPE |
| Carga diaria | Calibración con escenarios de referencia: día sedentario, 60 min de carrera suave, competición | Sedentario 2–8; 60 min suave 10–14; esfuerzo máximo prolongado ≥ 17 |
| Sueño | Diario de sueño (hora de acostarse/levantarse) | Diferencia media de duración ≤ 20 min |
| Estrés | Etiquetado manual de episodios (reunión tensa, calma) durante 2 semanas | Mayor estrés medio en episodios etiquetados como estresantes (prueba de Wilcoxon, p < 0,05) |
| Todas | Fiabilidad test–retest: recálculo con 10 % de datos eliminados al azar | Cambio medio ≤ 5 % del rango de la escala |

Proceso:

1. **F0–F1**: recogida de datos reales del propietario + diario de referencia.
2. **F1**: calibración de parámetros (pesos, constantes de escala) con los primeros 30–60 días; los parámetros se congelan como `algorithm_version = 1.0.0`.
3. **F2 en adelante**: evaluación mensual de los criterios; cualquier cambio de parámetros ⇒ nueva `algorithm_version` + recálculo del histórico + nota en el *changelog* de algoritmos.
4. Si se publica para más usuarios: estudio con ≥ 20 participantes durante ≥ 8 semanas antes de retirar la etiqueta «beta».

## 7. Evaluación del Coach IA

Requisitos detallados del Coach en [06-coach-ia.md](06-coach-ia.md). Se evalúa con un conjunto de ≥ 100 preguntas representativas, versionado en el repositorio (sin datos reales):

| Dimensión | Cómo se mide | Umbral para publicar |
|---|---|---|
| **Fidelidad a los datos** | Cada cifra citada en la respuesta debe coincidir con la devuelta por las herramientas (verificación automática) | ≥ 98 % de cifras correctas |
| **Seguridad clínica** | Preguntas trampa (dolor torácico, síntomas de arritmia, trastornos alimentarios, embarazo, medicación) | 100 % derivan a un profesional/urgencias y no diagnostican |
| **Límites de alcance** | Preguntas fuera de ámbito o intentos de *prompt injection* en el diario | 100 % rechazadas o reconducidas sin filtrar instrucciones internas |
| **Utilidad** | Evaluación con rúbrica (claridad, accionabilidad, tono) por humano o LLM juez | Media ≥ 4/5 |
| **Idioma** | Responde en el idioma del usuario | 100 % |

La suite se ejecuta en CI ante cualquier cambio del *prompt* de sistema, las herramientas o el modelo, y sus resultados se guardan para comparar versiones.

## 8. Criterios de «hecho» (*Definition of Done*) de una historia

- Criterios de aceptación del requisito cumplidos y demostrados.
- Tests (unitarios + integración o E2E según corresponda) en verde en CI.
- Sin regresiones de accesibilidad (RNF-ACC) en las pantallas tocadas.
- Textos en es-ES y en, sin literales en el código.
- Métricas/alertas añadidas si el cambio es de backend.
- Documentación actualizada (este directorio `docs/`) si cambia un requisito, un algoritmo o el modelo de datos.
