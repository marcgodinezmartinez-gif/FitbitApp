# 01 · Visión y alcance

## 1. Visión

> Una app **para mi iPhone**, **gratis**, que convierta los datos de mi **Google Fitbit Air** en tres respuestas claras cada mañana —**¿cuánto he dormido de lo que necesitaba?, ¿cómo de recuperado estoy?, ¿cuánto debería exigirme hoy?**— con la experiencia de WHOOP y un diseño **mucho más cuidado** que el de la app oficial.

La Fitbit Air es, como WHOOP, una pulsera **sin pantalla** para llevar 24/7. La app oficial (Google Health) ya muestra sus métricas, pero no ofrece el modelo mental de WHOOP —recuperación en %, carga diaria 0–21 con objetivo, necesidad y deuda de sueño con planificador, diario de hábitos con impacto medido, monitor de estrés, coach sobre tus datos— y su funcionalidad avanzada (el coach con Gemini) exige **Google Health Premium** (8,99 €/mes en España). Esta app aporta todo eso **sin cuotas**: los datos brutos de la pulsera son gratuitos y todas las puntuaciones se calculan en el propio iPhone. Y como corres con el **Apple Watch**, sus carreras entran por Salud y se fusionan con los datos de la pulsera sin duplicados (doc. 16).

## 2. Decisiones del propietario (28–29/09/2026)

| # | Decisión | Consecuencia |
|---|---|---|
| D-1 | **Solo para uso personal** | Sin cuentas, sin servidor, sin publicación; casi toda la normativa de apps publicadas no aplica (doc. 12 §0) |
| D-2 | **Solo iPhone** | App nativa **SwiftUI** para iOS 26+ (doc. 08) |
| D-5 | **Sin pagar Google Health Premium** | No hace falta: la API da los datos brutos gratis; las puntuaciones son propias |
| D-6 | **Gratis** | Ningún coste recurrente nuevo (RNF-COS-01); solo costes opcionales y controlados |
| — | **Estética muy superior a la app oficial** | La estética es un requisito de primer nivel (RNF-EST, doc. 11) |
| D-8 | **Sin Mac** | Se compila en la nube con **GitHub Actions** (macOS con Xcode 26); el proyecto se genera con XcodeGen y el diseño se revisa con capturas automáticas (doc. 08 §6) |
| D-9 | **Ya tienes el Apple Developer Program (99 $/año)** | Instalación por **TestFlight**, sin caducidad semanal y con todas las capacidades (*widgets*, AlarmKit…) |
| D-10 | **Sí al Coach IA, con Claude o Gemini** | Proveedor configurable con tu propia clave; con Gemini, solo clave de nivel de pago (doc. 06) |
| D-13 | **También tienes Apple Watch (solo para correr) y quieres fusionar sus datos** | Lectura de Salud (solo lectura) y reglas de fusión sin doble conteo: el Watch manda en sus carreras y la Fitbit Air en el resto y en la noche (doc. 16, RF-FUS) |
| D-14 | **Que todo se sincronice al abrir y poder pedir un análisis del día** | Sincronización de las dos fuentes al abrir (RF-SYN-09) y botón «Analizar mi día», sin IA o con el Coach (RF-ANA) |
| D-16 | **Llevas la Fitbit Air también cuando corres** | Cada carrera la graban los dos: se une siempre en una sola actividad, manda el pulso del Watch (comparado con el de la Fitbit, RF-FUS-10) y la distancia del día usa el GPS del Watch. Además, la primera versión (F1) ya calcula bien la carga de tus carreras solo con la Fitbit |

## 3. Objetivos

| ID | Objetivo | Indicador de éxito |
|---|---|---|
| OBJ-1 | Sueño y recuperación listos al empezar el día | ≥ 90 % de las mañanas con recuperación calculada; ≤ 3 s al abrir la app si los datos ya están en Google |
| OBJ-2 | Guía diaria de esfuerzo: carga acumulada y **carga objetivo** según la recuperación | Objetivo visible todos los días calibrados |
| OBJ-3 | Planificación del sueño: necesidad, deuda y hora para acostarse | Recomendación cada noche tras la calibración |
| OBJ-4 | Descubrir qué hábitos afectan a tu recuperación | Tras ≥ 30 días de diario, impacto de ≥ 3 hábitos con intervalo de confianza |
| OBJ-5 | **Sin cuotas nuevas** | Ningún pago recurrente además del Apple Developer Program que ya tienes (sin servidor, sin Premium); el Coach, solo por uso |
| OBJ-6 | **Diseño excelente** | Checklist de diseño (doc. 11 §9.4) superada en todas las pantallas; animaciones sin tirones (RNF-EST-02) |
| OBJ-7 | Privacidad | Datos solo en tu iPhone (y en Google, donde ya estaban); exportación y borrado completos |
| OBJ-8 | Métricas con base científica y validadas con tus datos | Criterios del doc. 13 §6 cumplidos antes de quitar la etiqueta «beta» |
| OBJ-9 | Coach IA opcional y fiable | Umbrales del doc. 13 §7 y gasto bajo tu control |
| OBJ-10 | Fitbit Air y Apple Watch en un solo sitio | 100 % de las carreras del Watch importadas y ninguna duplicada; ningún minuto contado dos veces (tests de invariantes) |
| OBJ-11 | Análisis del día a un toque | Sin IA, en ≤ 1 s; con el Coach, con el mismo formato y cifras verificadas |

## 4. Usuario

Un único usuario: **el propietario**, que lleva la Fitbit Air 24/7 (también al correr), corre con el Apple Watch, usa iPhone y quiere la experiencia de WHOOP sin cuotas y con mejor diseño. Los requisitos se escriben pensando en su día a día (entrenar, dormir mejor, entender su cuerpo).

## 5. Alcance por fases

Detalle en [14-plan-de-proyecto-y-riesgos.md](14-plan-de-proyecto-y-riesgos.md); matriz frente a WHOOP en [02-paridad-con-whoop.md](02-paridad-con-whoop.md).

| Fase | Contenido |
|---|---|
| **F0 · Preparación** (≈ 2 sem) | App ID y ficha en App Store Connect, tubería GitHub Actions → TestFlight, proyecto de Google Cloud y cliente OAuth iOS, página de privacidad, *spike* de datos reales, sistema de diseño base |
| **F1 · MVP** (≈ 6 sem) | Onboarding y conexión con Google; importación y sincronización; calibración; **Sueño, Recuperación y Carga**; pantalla Hoy y detalles; vitales nocturnos; notificación local matinal; privacidad básica |
| **F2 · Paridad** (≈ 9 sem) | Entrenamientos y zonas; **Apple Watch y fusión de datos**; carga objetivo; planificador, deuda y constancia del sueño; estrés; monitor de salud; diario; tendencias y calendario; informe semanal; **análisis del día** (sin IA); exportación; ***widgets* y pantalla de bloqueo** |
| **F3 · Inteligencia** (≈ 7 sem) | Impacto de hábitos; plan semanal; informe mensual; edad fisiológica; fuerza (sRPE); respiración guiada; FC en vivo y Live Activity; alarma (AlarmKit); **Coach IA con Claude o Gemini**, incluido el análisis del día con IA |

### Fuera de alcance

- Publicar la app, cuentas de usuario, servidor propio, notificaciones *push* remotas.
- Funciones clínicas: ECG, avisos de ritmo irregular, tensión arterial, analíticas (equivalentes a *Heart Screener*, *Blood Pressure Insights* y *Advanced Labs* de WHOOP).
- Protocolos propietarios de la pulsera, *firmware* o su vibración (alarma en la muñeca). Solo se contempla leer la emisión **estándar** de FC por Bluetooth (RF-ENT-07).
- Android, app propia para Apple Watch (sus datos sí se importan de Salud), iPad, web.
- Ciclo menstrual, comunidad/equipos e integraciones directas con otras plataformas.

## 6. Supuestos (a verificar en F0)

| ID | Supuesto | Estado a 28/09/2026 | Cómo se verifica | Si resulta falso |
|---|---|---|---|---|
| SUP-1 | La Google Health API expone para Fitbit Air: FC intradía, HRV nocturna, sueño con fases, SpO₂, FR, temperatura, actividad y entrenamientos | **Confirmado en la documentación** (doc. 03 §4) | *Spike* F0 (granularidad real) | Degradar la métrica (doc. 03 §6) |
| SUP-2 | Se puede usar la API con tu propia cuenta sin aprobación de Google | **Confirmado**: hasta 100 usuarios sin verificar; en *Testing* el *token* caduca cada 7 días (doc. 10 §2.2) | Alta en Google Cloud en F0 | Reconexión semanal o app sin verificar en producción |
| SUP-3 | Los datos aparecen en la API pocos minutos después de que la pulsera sincronice | Sin documentar | Medición en el *spike* | Reforzar el aviso «Abre Google Health» |
| SUP-4 | Los datos brutos no requieren Google Health Premium | **Confirmado en la práctica**: Premium solo cubre el coach y contenidos (doc. 03 §2) | *Spike* sin suscripción | — |
| SUP-5 | Llevas la pulsera también de noche ≥ 5 noches/semana | — | Uso real | Sin sueño no hay recuperación: recordatorios de uso y de carga diurna |
| SUP-6 | iOS ejecuta la tarea en segundo plano de la mañana con regularidad | Depende del uso | Uso real | El refresco al abrir la app (≤ 3 s) es el camino principal |
| SUP-7 | La familia `google-wearables` excluye lo que Google Health importa de Salud (tus carreras del Watch) | Se deduce de su definición en la API (doc. 10 §8) | *Spike* F0 | Filtrar en la app por `dataSource.platform` (ALG-FUS-08) |
| SUP-8 | Las carreras del Watch llegan a Salud del iPhone en minutos y con FC de alta frecuencia | Documentado por Apple sin cifra exacta | *Spike* F0 con tus carreras | Con pocas muestras manda la Fitbit (ALG-FUS-03) |

## 7. Restricciones

- **R-TEC-1**: Solo vías oficiales de acceso a datos (Google Health API y Salud/HealthKit).
- **R-TEC-2**: Sin servidor: sin *webhooks* ni *push* remotas (doc. 08 ADR 002).
- **R-TEC-3**: iOS 26+ y un solo usuario.
- **R-LEG-1**: Condiciones de la Google Health API (doc. 10 §7, doc. 12 §5).
- **R-TEC-4**: Sin Mac: compilación, pruebas de interfaz y firma solo en CI de macOS (doc. 08 §6).
- **R-ECO-1**: Ningún coste recurrente nuevo (RNF-COS-01).

## 8. Decisiones abiertas para el propietario

| # | Decisión | Recomendación asumida | Afecta a |
|---|---|---|---|
| D-3 | Nombre de la app | Pendiente (sin «WHOOP», «Fitbit» ni «Google» en el nombre) | 11 |
| D-4 | Deportes principales | Carrera, ciclismo, fuerza y caminar | 04, 05 |
| D-7 | Modo de la app en Google Cloud: *Testing* (reconectar cada 7 días) o producción sin verificar (aviso de «app no verificada» una vez) | Producción sin verificar, tras comprobarlo en el *spike* | 10 |
| D-11 | Si los ≈ 200 minutos mensuales de macOS del plan gratuito de GitHub se quedan cortos: hacer público el repositorio, pagar minutos o pasar a Xcode Cloud | Empezar con el plan gratuito y ahorrar minutos (doc. 08 §6) | 08, 15 |
| D-12 | Proveedor por defecto del Coach | El que gane la suite de evaluación del doc. 13 §7 con tus preguntas (Claude o Gemini) | 06 |
| D-15 | ¿Adelantar el Apple Watch y el análisis del día a F1? | Mantenerlos en F2: F1 ya funciona solo con la Fitbit, que llevas también al correr y registra el pulso de tus carreras (D-16), y sale antes | 01, 14 |
