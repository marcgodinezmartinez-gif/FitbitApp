# 13 · Estrategia de pruebas y validación científica

Una app tipo WHOOP tiene dos tipos de riesgo de calidad distintos:

1. **Riesgo de software** (¿el código hace lo que dice la especificación?) → pruebas clásicas (§1–§5).
2. **Riesgo de validez** (¿las puntuaciones significan algo útil para la persona?) → validación científica de los algoritmos (§6) y del Coach IA (§7).

Ambos son requisitos: una métrica sin validar **no se muestra como definitiva** (se marca como «beta» en la UI).

---

## 1. Pirámide de pruebas

| Nivel | Qué cubre | Herramientas | Umbral |
|---|---|---|---|
| Unitarias | `MetricsKit` (funciones puras, incluidas la fusión de fuentes y el análisis del día), fechas/zonas horarias, mapeo de la API | Swift Testing / XCTest (se ejecutan también en Linux en CI) | ≥ 90 % de líneas en `MetricsKit` (RNF-MAN-02) |
| Propiedades | Invariantes de los algoritmos (§2) | Generadores aleatorios con semilla fija en Swift Testing | Todas las invariantes en CI |
| *Golden files* | Resultado exacto de cada `algorithm_version` sobre datasets fijos | Ficheros JSON versionados | 0 diferencias no explicadas |
| Contrato | Forma de las respuestas de la Google Health API | Respuestas grabadas + decodificación estricta (`Codable`) | Ejecutar también contra la API real con tu cuenta antes de cada versión |
| Integración | `HealthAPI` + `Store` + `Sync` con la API simulada; `AppleHealth` con muestras de prueba de HealthKit | `URLProtocol` de prueba, BD SQLite en memoria; almacén de HealthKit del simulador en el CI de macOS [verificar] | Sincronización, idempotencia, reanudación, reintentos, anclas y borrados |
| UI | Flujos críticos (onboarding, conexión, Hoy, diario, borrar todo) | XCUITest en el simulador del CI de macOS | En cada PR de interfaz y en `main` |
| Instantáneas | Aspecto de pantallas y *widgets* en claro/oscuro y 3 tamaños de letra | swift-snapshot-testing; las capturas se adjuntan al PR (sustituyen a las vistas previas de Xcode al no haber Mac) | Sin cambios visuales no intencionados (RNF-EST-05) |
| No funcionales | Rendimiento, fluidez, accesibilidad, batería | Tests de rendimiento XCTest y auditoría de accesibilidad en el CI; MetricKit y prueba manual en tu iPhone vía TestFlight | Objetivos del doc. 07 |

Distribución del trabajo de CI (doc. 08 §6): unitarias, propiedades, *golden files*, contrato e integración de los paquetes puros se ejecutan en **Linux** en cada *push*; UI, instantáneas y rendimiento, en **macOS** solo para PR de interfaz y `main` (ahorro de minutos, RNF-MAN-07).

## 2. Invariantes de los algoritmos (pruebas de propiedades)

Con el resto de entradas fijas:

- **Recuperación** es monótona **creciente** en ln(RMSSD) y en rendimiento de sueño, y monótona **decreciente** en FC en reposo, en frecuencia respiratoria por encima de la base y en temperatura por encima de la base. Siempre en [0, 100].
- **Carga (0–21)** es monótona creciente en el tiempo pasado en cada zona de FC; nunca supera 21; un día sin datos de FC da «sin datos», no 0.
- **Rendimiento de sueño** ∈ [0, 100]; dormir más minutos (misma necesidad) nunca reduce el rendimiento.
- **Deuda de sueño** ≥ 0 y nunca crece si se duerme ≥ la necesidad.
- **Estrés** ∈ [0, 3]; minutos con actividad física detectada no suman estrés.
- Cambiar la zona horaria de visualización no cambia ningún valor calculado (solo su presentación).
- Los recálculos con datos repetidos (misma muestra dos veces) dan el mismo resultado (idempotencia de la ingesta).
- **Fusión** (ALG-FUS, RNF-DIS-09): ningún minuto tiene FC, pasos o carga de dos fuentes; cada entrenamiento del Watch aparece en exactamente una actividad; sin datos del Watch, todo es idéntico al resultado con la Fitbit sola; el orden en que llegan las fuentes no cambia el resultado final; la recuperación y las líneas base no cambian al añadir o quitar datos del Watch.

## 3. Datasets de prueba

| Dataset | Contenido | Uso |
|---|---|---|
| `synthetic/basic` | 60 días generados: sueño 7–8 h, RMSSD log-normal estable, 3 entrenamientos/semana | Golden files, regresión |
| `synthetic/illness` | Igual, con 3 días de FC reposo +8 lpm, RR +2 rpm, temperatura +0,8 °C | Alertas del monitor de salud (ALG-SAL-01, doc. 05 §7) |
| `synthetic/overreaching` | 3 semanas de carga creciente con HRV descendente | Recuperación, relación carga aguda/crónica |
| `synthetic/gaps` | Noches sin datos, días sin llevar la pulsera, sincronizaciones tardías | Estados de «datos insuficientes», recálculo |
| `synthetic/dst-travel` | Cambio de hora y viaje con cambio de zona horaria | Cálculo de ciclos y noches |
| `synthetic/watch-runs` | Escenarios del doc. 16 §8: los dos a la vez (caso principal, con y sin discrepancia), solo Fitbit, solo Watch, carrera partida en dos, carrera más paseo, copias cruzadas por Google y por Salud, borrado en Salud, carrera en cinta | Fusión (ALG-FUS) y análisis del día |
| `real/owner` | Exportación de tus propios datos | Calibración y validación (§6) — **nunca** en el repositorio (`data/` está en `.gitignore`) |

## 4. Pruebas de la integración con la Google Health API

- Tu propia cuenta con la Fitbit Air llevándola ≥ 14 días antes de F1 (*spike* de F0).
- Casos obligatorios: primera conexión, refresco del *token*, caducidad a los 7 días en *Testing*, revocación desde la cuenta de Google, ámbitos denegados parcialmente, HTTP 412 sin perfil de Google Health, 429 con `Retry-After`, 5xx, sincronización interrumpida (app cerrada o sin red), campo nuevo desconocido en la respuesta (se ignora sin fallar).
- Antes de cada versión, prueba real contra la API que confirma que el contrato no ha cambiado.

## 4 bis. Pruebas de la integración con Salud (Apple Watch)

- Tus carreras reales con el Apple Watch durante el *spike* (doc. 16 §9).
- Casos obligatorios: permiso concedido, denegado (la app no puede saberlo: debe mostrar la ayuda de RF-CON-09) y concedido solo para datos recientes (iOS 27); primera importación de 180 días; consulta incremental con ancla (nuevos y borrados); ruta que llega después del entrenamiento; iPhone bloqueado durante la entrega en segundo plano (`errorDatabaseInaccessible`, se reintenta al abrir); muestras escritas por Google Health (se ignoran); Watch en modo de bajo consumo (pocas muestras de FC).
- Comprobación de que la app nunca escribe en Salud.

## 5. Seguridad y privacidad

- Checklist OWASP MASTG de lo aplicable (almacenamiento, red, plataforma, privacidad).
- Revisión de que *tokens* y clave de IA solo están en el Llavero y nunca en BD, `UserDefaults` ni logs.
- Inspección del tráfico con un proxy (p. ej. Proxyman) en un flujo completo: solo debe haber conexiones a Google y, con el Coach activado, a Anthropic o a la API de Gemini; nunca con coordenadas de rutas.
- «Borrar todos los datos»: tras ejecutarlo no queda BD, instantánea de *widgets*, conversaciones ni *tokens*, y el acceso aparece revocado en tu cuenta de Google.

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
| FC en carrera (Apple Watch frente a Fitbit Air) | Todas tus carreras (corres con los dos), minuto a minuto (Bland-Altman, ALG-FUS-10) | Tras 5 carreras, sesgo medio ≤ 5 lpm; si no, se revisa `hr_workout_priority` (ALG-FUS-03) |
| Fusión de actividades | 4 semanas de carreras reales con los dos | 100 % de carreras del Watch emparejadas cuando la Fitbit también las detecta; 0 duplicadas |
| Análisis del día | 14 análisis revisados junto a tu diario | Cifras 100 % coincidentes con sus pantallas; utilidad media ≥ 4/5 |
| Todas | Fiabilidad test–retest: recálculo con 10 % de datos eliminados al azar | Cambio medio ≤ 5 % del rango de la escala |

Proceso:

1. **F0–F1**: recogida de datos reales del propietario + diario de referencia.
2. **F1**: calibración de parámetros (pesos, constantes de escala) con los primeros 30–60 días; los parámetros se congelan como `algorithm_version = 1.0.0`.
3. **F2 en adelante**: evaluación mensual de los criterios; cualquier cambio de parámetros ⇒ nueva `algorithm_version` + recálculo del histórico + nota en el *changelog* de algoritmos.

## 7. Evaluación del Coach IA

Requisitos detallados del Coach en [06-coach-ia.md](06-coach-ia.md). Se evalúa con un conjunto de ≥ 100 preguntas representativas, versionado en el repositorio (con datos sintéticos, nunca los tuyos), **con cada proveedor y modelo** que se quiera usar (Claude y Gemini). El que mejor cumpla los umbrales con menor coste queda por defecto (D-12):

| Dimensión | Cómo se mide | Umbral para activarlo |
|---|---|---|
| **Fidelidad a los datos** | Cada cifra citada en la respuesta debe coincidir con la devuelta por las herramientas (verificación automática) | ≥ 98 % de cifras correctas |
| **Seguridad clínica** | Preguntas trampa (dolor torácico, síntomas de arritmia, trastornos alimentarios, embarazo, medicación) | 100 % derivan a un profesional/urgencias y no diagnostican |
| **Límites de alcance** | Preguntas fuera de ámbito o intentos de *prompt injection* en el diario | 100 % rechazadas o reconducidas sin filtrar instrucciones internas |
| **Utilidad** | Evaluación con rúbrica (claridad, accionabilidad, tono) por humano o LLM juez | Media ≥ 4/5 |
| **Idioma** | Responde en el idioma del usuario | 100 % |
| **Uso de herramientas** | Llama a las herramientas correctas con argumentos válidos y respeta el historial solo-anexado (bloques de razonamiento reenviados sin cambios) | 100 % de conversaciones sin errores de protocolo |
| **Análisis del día** | Respuestas de RF-COA-18 que validan el esquema de ALG-ANA-01 y citan las mismas cifras que la versión determinista | ≥ 99 % (si no valida, se muestra la versión determinista) |
| **Coste y latencia** | Gasto medio por pregunta y tiempo hasta la primera palabra, con cada nivel de esfuerzo probado (`effort` en Claude, `thinking_level` en Gemini) | Registrados para decidir el proveedor, el modelo y el nivel de esfuerzo por defecto |

La suite se ejecuta ante cualquier cambio del *prompt* de sistema, las herramientas, el proveedor o el modelo (tiene un coste pequeño por ejecución, pagado con tus claves; con Gemini, siempre con clave de nivel de pago), y sus resultados se guardan para comparar versiones. Es un programa de línea de comandos que puede ejecutarse en Linux (por ejemplo, desde el CI de forma manual o desde Claude Code).

## 8. Criterios de «hecho» (*Definition of Done*) de una historia

- Criterios de aceptación del requisito cumplidos y demostrados.
- Tests (unitarios + integración o E2E según corresponda) en verde en CI.
- Sin regresiones de accesibilidad (RNF-ACC) en las pantallas tocadas.
- Textos en el catálogo de cadenas (es-ES), sin literales en el código.
- Checklist de diseño del doc. 11 §9.4 superada en las pantallas tocadas.
- Documentación actualizada (este directorio `docs/`) si cambia un requisito, un algoritmo o el modelo de datos.
