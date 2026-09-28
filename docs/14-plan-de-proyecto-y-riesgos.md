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
    F2 Paridad WHOOP + widgets               :f2, after f1, 6w
    F3 Coach IA, hábitos, edad fisiológica   :f3, after f2, 6w
```

| Hito | Criterio de salida |
|---|---|
| **H0 · Datos reales** (fin F0) | Desde el iPhone (o un prototipo) se leen por la API y se guardan en local: sueño con fases, HRV nocturna, FC en reposo, FC por minuto, SpO₂, FR, temperatura, actividad. Informe del *spike* con granularidad, latencia y huecos (actualiza docs. 03, 09 y 10). Sistema de diseño base aprobado |
| **H1 · Primera mañana** (fin F1) | Durante 7 días seguidos, al abrir la app ves Sueño, Recuperación y Carga calculados en ≤ 3 s, con sus detalles y el aspecto definido en el doc. 11 |
| **H2 · Paridad** (fin F2) | Funciones M y S de F2 del doc. 04 terminadas, incluidos *widgets*; algoritmos `1.0.0` calibrados con ≥ 30 días de tus datos (doc. 13 §6) |
| **H3 · Inteligencia** (fin F3) | Impacto de hábitos, edad fisiológica y, si lo quieres, Coach IA superando su evaluación (doc. 13 §7) |

## 2. Backlog por épicas

| Épica | Contenido (requisitos) | Fase | Esfuerzo |
|---|---|---|---|
| E0 · Preparación | Apple ID / cuenta de desarrollador, Xcode, proyecto de Google Cloud y cliente OAuth iOS, página de privacidad, *spike* de datos, repositorio y CI, ADR (doc. 15) | F0 | 1,5 sem |
| E1 · Sistema de diseño | Tokens, anillos animados, tarjetas, gráficos, icono, estados especiales (doc. 11 §2, §9; RNF-EST) | F0–F1 | 1,5 sem |
| E2 · Conexión y sincronización | RF-CON-01..05/08, RF-SYN-01..07, Llavero, tareas en segundo plano | F1 | 1,5 sem |
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
| E13 · Coach IA (opcional) | RF-COA-01..20, suite de evaluación | F3 | 2 sem |
| E14 · FC en vivo, Live Activity, alarma y Apple Health | RF-ENT-07, RF-WID-03, RF-SUE-12, RF-CON-06 | F3 | 1 sem |

### Historias de usuario representativas

- **E2** — *Como* usuario de Fitbit Air, *quiero* conectar mi cuenta de Google una sola vez *para* que mis datos aparezcan solos al abrir la app.
- **E1/E4** — *Como* usuario exigente con el diseño, *quiero* una pantalla «Hoy» bonita y clara *para* disfrutar mirándola cada mañana.
- **E3** — *Como* deportista, *quiero* un % de recuperación comparado con mi propia normalidad *para* decidir si entreno fuerte hoy.
- **E6** — *Como* corredor, *quiero* saber cuánta carga llevo y cuál es mi objetivo *para* no pasarme ni quedarme corto.
- **E7** — *Como* persona que duerme poco, *quiero* saber a qué hora acostarme *para* pagar mi deuda de sueño.
- **E10** — *Como* usuario de iPhone, *quiero* ver mis tres anillos en la pantalla de bloqueo *para* no tener ni que abrir la app.

## 3. Organización del trabajo

- Iteraciones de 2 semanas; al final de cada una, la app instalada en tu iPhone con tus datos reales.
- *Diseño primero*: cada pantalla se maqueta en SwiftUI Previews con datos de ejemplo y pasa la checklist del doc. 11 §9.4 antes de conectarla a datos reales.
- Tablero (GitHub Projects) con una tarjeta por requisito; cada PR referencia sus IDs.
- *Definition of Done* en doc. 13 §8. Los cambios de requisitos se hacen en estos documentos en la misma PR.

## 4. Riesgos

Probabilidad (P) e impacto (I): A alta, M media, B baja.

| ID | Riesgo | P | I | Mitigación | Plan B |
|---|---|---|---|---|---|
| RSK-01 | La API no expone algún dato clave de la Fitbit Air o lo hace con menor granularidad | B | A | *Spike* en F0 (la documentación ya lo confirma) | Degradar la métrica (doc. 03 §6); Apple Health para FC/sueño |
| RSK-02 | Caducidad del *refresh token* a los 7 días en modo *Testing* | A | M | Pasar la app de Google a *In production* sin verificar tras validarlo (D-7) | Reconexión guiada en 1 toque (RF-CON-04) |
| RSK-03 | Con cuenta gratuita de Apple la app caduca cada 7 días | A | M | Reinstalar desde Xcode o re-firmar con SideStore (doc. 08 §6) | Apple Developer Program (99 $/año) |
| RSK-04 | No tener Mac | ? | M | Compilación en GitHub Actions (macOS) + SideStore; tests de `MetricsKit` en Linux | Mac de segunda mano o Mac en la nube por horas |
| RSK-05 | iOS no ejecuta la tarea en segundo plano a tiempo | M | B | Refresco rápido al abrir (≤ 3 s) como camino principal | Abrir la app al despertar |
| RSK-06 | Latencia: la pulsera no sincroniza hasta que se abre Google Health | M | M | Mensaje y atajo «Abrir Google Health» | — |
| RSK-07 | API nueva con cambios de contrato | M | M | Adaptador aislado + tests de contrato (doc. 13 §4) | Parche rápido del adaptador |
| RSK-08 | Las puntuaciones no reflejan cómo te sientes | M | A | Validación con autoevaluación (doc. 13 §6); parámetros versionados | Recalibrar; etiqueta «beta» |
| RSK-09 | Precisión de la Fitbit Air inferior a la de WHOOP en algunos entrenamientos y en HRV absoluta | M | M | Todo relativo a tu línea base; filtros; confianza visible | Explicarlo en «Cómo calculamos» |
| RSK-10 | El Coach IA da consejos inseguros o inventa cifras | M | A | Herramientas, verificación de cifras, filtros y evaluación (doc. 06 §6) | Desactivarlo |
| RSK-11 | Gasto del Coach por encima de lo esperado | B | M | Límite de gasto en Anthropic + límite diario en la app + contador de gasto | Modo solo educativo o desactivarlo |
| RSK-12 | Dedicación (proyecto personal) | A | M | Fases con valor propio: F1 ya es usable | Congelar F3 |
| RSK-13 | Google cambia sus políticas o restringe el acceso a la API para apps no verificadas | B | A | Cumplir las políticas (doc. 10 §7) | Exportación de Google Takeout + importación manual |

## 5. Indicadores

| Tipo | Indicador | Objetivo |
|---|---|---|
| Uso | Días/semana que abres la app | ≥ 5 |
| Datos | % de mañanas con recuperación calculada | ≥ 90 % |
| Rendimiento | Tiempo desde abrir la app hasta ver el día | ≤ 3 s |
| Calidad | Cierres inesperados | 0 por semana |
| Validez | Criterios del doc. 13 §6 | Cumplidos para quitar «beta» |
| Coste | Gasto recurrente obligatorio | **0 €** (opcionales: Apple 99 $/año, Coach por uso) |
