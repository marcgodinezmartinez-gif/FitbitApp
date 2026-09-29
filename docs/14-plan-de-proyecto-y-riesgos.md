# 14 · Plan de proyecto, backlog y riesgos

Proyecto **personal**: app para tu iPhone, sin servidor y sin cuotas. Estimaciones en **semanas de una persona a tiempo completo** (a media jornada, ×2); son órdenes de magnitud, no compromisos. La publicación para terceros queda **fuera de alcance**.

## 1. Fases e hitos

```mermaid
gantt
    dateFormat  YYYY-MM-DD
    axisFormat  %b
    title Plan orientativo (1 persona a tiempo completo)
    section Preparación
    F0 Preparación y spike de datos          :f0, 2026-10-05, 2w
    section App
    F1 MVP: Hoy, Sueño, Recuperación, Carga  :f1, after f0, 6w
    F2 Paridad, Apple Watch, análisis del día :f2, after f1, 9w
    F3 Coach IA, hábitos, edad fisiológica   :f3, after f2, 7w
```

| Hito | Criterio de salida |
|---|---|
| **H0 · Datos reales** (fin F0) | La tubería GitHub Actions → TestFlight funciona y un prototipo instalado en tu iPhone lee por la API y guarda en local: sueño con fases, HRV nocturna, FC en reposo, FC por minuto, SpO₂, FR, temperatura, actividad. Informe del *spike* con granularidad, latencia y huecos (actualiza docs. 03, 09 y 10). Sistema de diseño base aprobado con sus capturas |
| **H1 · Primera mañana** (fin F1) | Durante 7 días seguidos, al abrir la app ves Sueño, Recuperación y Carga calculados en ≤ 3 s, con sus detalles y el aspecto definido en el doc. 11 |
| **H2 · Paridad** (fin F2) | Funciones M y S de F2 del doc. 04 terminadas, incluidos *widgets*, la fusión con el Apple Watch (carreras sin duplicados durante 4 semanas) y «Analizar mi día»; algoritmos `1.0.0` calibrados con ≥ 30 días de tus datos (doc. 13 §6) |
| **H3 · Inteligencia** (fin F3) | Impacto de hábitos, edad fisiológica y Coach IA (Claude y Gemini), incluido el análisis del día con IA, superando su evaluación (doc. 13 §7) |

## 2. Backlog por épicas

| Épica | Contenido (requisitos) | Fase | Esfuerzo |
|---|---|---|---|
| E0 · Preparación y tubería sin Mac | App ID, capacidades y ficha en App Store Connect; clave de API de App Store Connect; `project.yml` de XcodeGen; CI Linux + macOS; subida automática a **TestFlight** con una app «Hola mundo»; proyecto de Google Cloud y cliente OAuth iOS; página de privacidad; *spike* de datos; ADR (doc. 15) | F0 | 2 sem |
| E1 · Sistema de diseño | Tokens, anillos animados, tarjetas, gráficos, icono, estados especiales (doc. 11 §2, §9; RNF-EST) | F0–F1 | 1,5 sem |
| E2 · Conexión y sincronización | RF-CON-01..05/08, RF-SYN-01..07, RF-SYN-09 (parte de Google), RF-SYN-10, Llavero, tareas en segundo plano | F1 | 1,5 sem |
| E3 · Motor de métricas v0 | `MetricsKit`: líneas base, sueño principal, necesidad, suficiencia y rendimiento de sueño, recuperación, carga diaria, zonas (ALG-BAS, SUE-00..02/06/07, REC-01, CAR-01/06) + tests | F1 | 1,5 sem |
| E4 · Hoy y detalles | Anillos, detalle de Sueño/Recuperación/Carga, vitales, estados | F1 | 1 sem |
| E5 · Onboarding, notificaciones y privacidad | RF-ONB-01..04, NOT-01/06/07, RF-PRI-02/03, Face ID | F1 | 0,5 sem |
| E6 · Entrenamientos y carga avanzada | RF-CAR-02..06, RF-ENT-01..04/06 | F2 | 1,5 sem |
| E7 · Sueño avanzado | RF-SUE-06..10 (deuda, constancia, planificador, siestas) | F2 | 1 sem |
| E8 · Estrés y monitor de salud | RF-EST-01..04/06, RF-SAL-02..05 | F2 | 1 sem |
| E9 · Diario, tendencias e informe semanal | RF-DIA-01..05, RF-TEN-01..04, RF-INF-01, RF-PRI-01, RF-ONB-05 | F2 | 1,5 sem |
| E10 · *Widgets* y pantalla de bloqueo | RF-WID-01/02/04 | F2 | 1 sem |
| E11 · Hábitos, plan semanal e informes | RF-DIA-06, RF-PLA-01..03, RF-INF-02/03 | F3 | 1,5 sem |
| E12 · Edad fisiológica, fuerza y respiración | RF-EDA-01/02, RF-ENT-05, RF-EST-05, RF-SAL-06 | F3 | 1,5 sem |
| E13 · Coach IA (Claude y Gemini) | RF-COA-01..23 (incluido el análisis del día con IA, RF-COA-18 y RF-ANA-02): `CoachEngine`, proveedores Anthropic y Gemini, herramientas, seguridad, suite de evaluación con ambos | F3 | 3 sem |
| E14 · FC en vivo, Live Activity y alarma | RF-ENT-07, RF-WID-03, RF-SUE-12 | F3 | 1 sem |
| E15 · Apple Watch y fusión de datos | RF-CON-06/09, RF-SYN-09 (parte de Salud)/11, RF-FUS-01..10, RF-ENT-08, RF-SAL-05: `AppleHealth` (permisos, anclas, entrega en segundo plano), ALG-FUS en `MetricsKit`, detalle de carrera con mapa, Fuentes de datos | F2 | 2 sem |
| E16 · Análisis del día | RF-ANA-01..05 (versión determinista, ALG-ANA-01), NOT-10/12 | F2 | 1 sem |

### Historias de usuario representativas

- **E2** — *Como* usuario de Fitbit Air, *quiero* conectar mi cuenta de Google una sola vez *para* que mis datos aparezcan solos al abrir la app.
- **E1/E4** — *Como* usuario exigente con el diseño, *quiero* una pantalla «Hoy» bonita y clara *para* disfrutar mirándola cada mañana.
- **E3** — *Como* deportista, *quiero* un % de recuperación comparado con mi propia normalidad *para* decidir si entreno fuerte hoy.
- **E6** — *Como* corredor, *quiero* saber cuánta carga llevo y cuál es mi objetivo *para* no pasarme ni quedarme corto.
- **E7** — *Como* persona que duerme poco, *quiero* saber a qué hora acostarme *para* pagar mi deuda de sueño.
- **E10** — *Como* usuario de iPhone, *quiero* ver mis tres anillos en la pantalla de bloqueo *para* no tener ni que abrir la app.
- **E15** — *Como* corredor con Apple Watch, *quiero* que mis carreras aparezcan con su mapa y su ritmo junto a mi recuperación, sin duplicados, *para* tenerlo todo en un solo sitio.
- **E16** — *Como* usuario, *quiero* pedir un análisis de mi día *para* entender en 30 segundos qué hice bien y qué ajustar.

## 3. Organización del trabajo

- Iteraciones de 2 semanas; al final de cada una, una *build* nueva en **TestFlight** con tus datos reales.
- *Diseño primero* sin Mac: cada pantalla se construye con datos de ejemplo y sus **capturas automáticas** (tests de instantánea del CI, en claro/oscuro y varios tamaños de letra) se revisan en el PR con la checklist del doc. 11 §9.4; después se prueba en el iPhone vía TestFlight antes de conectarla a datos reales.
- Flujo diario: editas (en cualquier ordenador o con Claude Code) → PR → CI Linux (siempre) y macOS (si toca interfaz) → *merge* a `main` → TestFlight.
- Tablero (GitHub Projects) con una tarjeta por requisito; cada PR referencia sus IDs.
- *Definition of Done* en doc. 13 §8. Los cambios de requisitos se hacen en estos documentos en la misma PR.

## 4. Riesgos

Probabilidad (P) e impacto (I): A alta, M media, B baja.

| ID | Riesgo | P | I | Mitigación | Plan B |
|---|---|---|---|---|---|
| RSK-01 | La API no expone algún dato clave de la Fitbit Air o lo hace con menor granularidad | B | A | *Spike* en F0 (la documentación ya lo confirma) | Degradar la métrica (doc. 03 §6) |
| RSK-02 | Caducidad del *refresh token* a los 7 días en modo *Testing* | A | M | Pasar la app de Google a *In production* sin verificar tras validarlo (D-7) | Reconexión guiada en 1 toque (RF-CON-04) |
| RSK-03 | Se agotan los ≈ 200 minutos mensuales de macOS del plan gratuito de GitHub | M | M | Todo lo posible en Linux, caché, macOS solo para interfaz y `main` (RNF-MAN-07) | Repositorio público, minutos de pago o Xcode Cloud (D-11) |
| RSK-04 | Sin Mac: ciclo de prueba de interfaz más lento y sin depurador ni Instruments | A | M | Capturas automáticas en cada PR, TestFlight en ≈ 20–30 min, registros locales, informes de TestFlight y MetricKit | Mac alquilado por horas para depuraciones puntuales |
| RSK-15 | La firma en la nube o la subida a TestFlight desde CI falla por configuración | M | M | Montarla en F0 con una app mínima (E0) y documentarla en un ADR | fastlane como alternativa |
| RSK-05 | iOS no ejecuta la tarea en segundo plano a tiempo | M | B | Refresco rápido al abrir (≤ 3 s) como camino principal | Abrir la app al despertar |
| RSK-06 | Latencia: la pulsera no sincroniza hasta que se abre Google Health | M | M | Mensaje y atajo «Abrir Google Health» | — |
| RSK-07 | API nueva con cambios de contrato | M | M | Adaptador aislado + tests de contrato (doc. 13 §4) | Parche rápido del adaptador |
| RSK-08 | Las puntuaciones no reflejan cómo te sientes | M | A | Validación con autoevaluación (doc. 13 §6); parámetros versionados | Recalibrar; etiqueta «beta» |
| RSK-09 | Precisión de la Fitbit Air inferior a la de WHOOP en algunos entrenamientos y en HRV absoluta | M | M | Todo relativo a tu línea base; filtros; confianza visible | Explicarlo en «Cómo calculamos» |
| RSK-10 | El Coach IA da consejos inseguros o inventa cifras | M | A | Herramientas, verificación de cifras, filtros y evaluación (doc. 06 §6) | Desactivarlo |
| RSK-11 | Gasto del Coach por encima de lo esperado | B | M | Límite de gasto en la consola del proveedor + límite diario en la app + contador de gasto | Cambiar a Gemini, modo solo educativo o desactivarlo |
| RSK-14 | Usar sin querer una clave de Gemini del nivel gratuito (Google podría usar y revisar tus datos de salud) | M | A | Confirmación obligatoria de nivel de pago (RF-COA-23) y guía de configuración (doc. 15) | Usar Claude |
| RSK-12 | Dedicación (proyecto personal) | A | M | Fases con valor propio: F1 ya es usable | Congelar F3 |
| RSK-13 | Google cambia sus políticas o restringe el acceso a la API para apps no verificadas | B | A | Cumplir las políticas (doc. 10 §7) | Exportación de Google Takeout + importación manual |
| RSK-16 | Datos contados dos veces o carreras duplicadas al combinar la Fitbit Air, el Apple Watch y la conexión Google Health ↔ Salud | M | A | Reglas ALG-FUS con tests de invariantes; `google-wearables` y filtro de origen en Salud; *spike* con tus carreras (doc. 16 §9) | Desactivar una de las dos fuentes en Ajustes |
| RSK-17 | iOS no despierta la app al terminar la carrera o el iPhone está bloqueado (Salud protegida) | M | B | La importación al abrir (≤ 1 s) es el camino principal; reintento al desbloquear | — |
| RSK-18 | La FC del Apple Watch y la de la Fitbit Air discrepan en carrera | M | M | Aviso «las fuentes no coinciden», preferencia configurable y validación Bland-Altman (doc. 13 §6) | Usar la Fitbit como preferente en entrenamientos |

## 5. Indicadores

| Tipo | Indicador | Objetivo |
|---|---|---|
| Uso | Días/semana que abres la app | ≥ 5 |
| Datos | % de mañanas con recuperación calculada | ≥ 90 % |
| Datos | Carreras del Apple Watch importadas / duplicadas | 100 % / 0 |
| Rendimiento | Tiempo desde abrir la app hasta ver el día | ≤ 3 s |
| Calidad | Cierres inesperados | 0 por semana |
| Validez | Criterios del doc. 13 §6 | Cumplidos para quitar «beta» |
| Coste | Gasto recurrente nuevo | **0 €** (Apple Developer ya pagado; Coach IA por uso) |
| Entrega | Tiempo desde *merge* a `main` hasta tenerla en TestFlight | ≤ 30 min |
