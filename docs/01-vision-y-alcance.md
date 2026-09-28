# 01 · Visión y alcance

## 1. Visión

> Convertir los datos de la **Google Fitbit Air** en tres respuestas claras cada mañana —**¿cuánto he dormido de lo que necesitaba?, ¿cómo de recuperado estoy?, ¿cuánto debería exigirme hoy?**— con la experiencia de uso de WHOOP, sin cuota obligatoria de hardware y con los datos bajo control del usuario.

La Fitbit Air es, como WHOOP, una pulsera **sin pantalla** pensada para llevarse 24/7. La app oficial (Google Health) ya muestra sus propias métricas, pero no ofrece el modelo mental de WHOOP: recuperación en %, carga diaria 0–21 con objetivo según la recuperación, necesidad y deuda de sueño con planificador de hora de acostarse, diario de hábitos con impacto medido sobre la recuperación, monitor de estrés y coach conversacional sobre tus propios datos. Esta app aporta esa capa de análisis y coaching.

## 2. Objetivos

| ID | Objetivo | Indicador de éxito |
|---|---|---|
| OBJ-1 | Puntuaciones de sueño y recuperación disponibles cada mañana poco después de que la pulsera sincronice | ≥ 90 % de las mañanas con recuperación calculada en ≤ 10 min desde la sincronización |
| OBJ-2 | Guía diaria de esfuerzo: carga acumulada y **carga objetivo** según la recuperación | Carga visible con retraso ≤ el de la sincronización de Google; objetivo mostrado todos los días calibrados |
| OBJ-3 | Planificación del sueño: necesidad, deuda y hora recomendada para acostarse | Recomendación disponible cada noche a partir de la calibración |
| OBJ-4 | Descubrir qué hábitos afectan a la recuperación del usuario | Tras ≥ 30 días de diario, informe de impacto de al menos 3 comportamientos con intervalo de confianza |
| OBJ-5 | Coach IA fiable que responde con los datos del usuario | Umbrales de evaluación del doc. 13 §7 superados |
| OBJ-6 | Privacidad por diseño | Datos en la UE, exportación y borrado completos, sin datos de salud en logs |
| OBJ-7 | Métricas con base científica y validadas con los datos del propietario | Criterios del doc. 13 §6 cumplidos antes de quitar la etiqueta «beta» |

## 3. Usuarios

| Perfil | Descripción | Necesidades clave |
|---|---|---|
| **Propietario** (usuario principal del MVP) | Persona que lleva la Fitbit Air y quiere la experiencia WHOOP con su pulsera | Todas las del producto; control total de sus datos |
| Deportista amateur | Entrena 3–6 días/semana (carrera, ciclismo, gimnasio, deportes de equipo) | Saber cuándo apretar y cuándo descansar; carga objetivo; zonas de FC |
| Persona centrada en salud y hábitos | Quiere dormir mejor y reducir estrés | Necesidad/deuda de sueño, constancia, estrés, efecto de alcohol/cafeína/pantallas |
| Persona con agenda exigente | Poco tiempo, quiere una respuesta rápida | Un vistazo de 10 s a la pantalla «Hoy» y un resumen claro |

Fuera de público objetivo: menores de 18 años, pacientes que buscan seguimiento de una enfermedad (la app no es un producto sanitario, doc. 12).

## 4. Alcance por fases

Detalle y calendario en [14-plan-de-proyecto-y-riesgos.md](14-plan-de-proyecto-y-riesgos.md); matriz completa frente a WHOOP en [02-paridad-con-whoop.md](02-paridad-con-whoop.md).

| Fase | Contenido |
|---|---|
| **F0 · Preparación** | Cuentas, proyecto de Google Cloud, acceso a la Google Health API, *spike* de datos reales de la Fitbit Air, repositorio y CI, diseño visual base, borrador de política de privacidad |
| **F1 · MVP** | Registro y vinculación con Google; *backfill* e ingesta incremental; calibración y líneas base; **Sueño, Recuperación y Carga diaria**; pantalla Hoy y detalles; vitales nocturnos; notificación matinal; ajustes; exportación y borrado básicos |
| **F2 · Paridad funcional** | Entrenamientos con carga de actividad y zonas; carga objetivo; planificador de sueño; deuda y constancia del sueño; monitor de estrés; monitor de salud (rangos y avisos); diario de hábitos; tendencias y calendario; informe semanal; exportación |
| **F3 · Inteligencia** | Coach IA; impacto de comportamientos; plan semanal; informe mensual; edad fisiológica y ritmo de envejecimiento; registro de fuerza (sRPE); Health Connect; *widgets*; FC en vivo por Bluetooth (si es viable) |
| **F4 · Producto** (opcional) | Multiusuario abierto, verificación de Google (y CASA si aplica), publicación en tiendas, cumplimiento RGPD completo, suscripción, comunidad/equipos |

### Fuera de alcance (en cualquier fase, salvo decisión explícita)

- Funciones clínicas: ECG, notificaciones de ritmo irregular/fibrilación auricular, estimación de presión arterial, analíticas de sangre (equivalentes a *Heart Screener*, *Blood Pressure Insights* y *Advanced Labs* de WHOOP).
- Comunicación Bluetooth con protocolos propietarios de la pulsera, *firmware* propio o control de la vibración de la pulsera (p. ej. alarma háptica en la muñeca). Solo se contempla leer la emisión **estándar** de FC por Bluetooth (RF-ENT-07).
- Seguimiento del ciclo menstrual, comunidad/equipos e integraciones directas con otras plataformas (reconsiderar en F4).
- Datos de otros *wearables* distintos de los que publiquen en la Google Health API (se evalúa en F4).

## 5. Supuestos (a verificar en F0)

| ID | Supuesto | Estado a 28/09/2026 | Cómo se verifica | Si resulta falso |
|---|---|---|---|---|
| SUP-1 | La Google Health API expone para Fitbit Air: FC intradía, HRV nocturna, sueño con fases, SpO₂, FR, temperatura cutánea, actividad y entrenamientos | **Confirmado en la documentación** (tabla de compatibilidad, doc. 03 §4) | *Spike* F0 con la cuenta del propietario (granularidad real) | Degradar las métricas afectadas (doc. 03 §6) o complementar con Health Connect |
| SUP-2 | Un desarrollador individual puede usar la API con su propia cuenta sin un proceso de aprobación largo | **Confirmado**: sin verificación se admiten hasta 100 usuarios; en modo *Testing* el *token* caduca cada 7 días (doc. 10 §2.2) | Alta en Google Cloud en F0 | Reconexión semanal o app sin verificar en producción |
| SUP-3 | Los datos aparecen en la API pocos minutos después de que la pulsera sincronice | Sin documentar | Medición en el *spike* | Ajustar expectativas de OBJ-1 y reforzar mensajes de «sincroniza Google Health» |
| SUP-4 | Los datos brutos no requieren la suscripción de pago de Google | **Probable**: Premium solo cubre el Coach y contenidos (doc. 03 §2) | *Spike* sin suscripción | Documentarlo como requisito del usuario |
| SUP-5 | El propietario lleva la pulsera también de noche ≥ 5 noches/semana | — | Uso real | Sin sueño no hay recuperación: recordatorios de uso y de carga diurna |

## 6. Restricciones

- **R-TEC-1**: Solo vías oficiales de acceso a datos (Google Health API; Health Connect/HealthKit si están disponibles).
- **R-TEC-2**: Cuotas y límites de la Google Health API.
- **R-LEG-1**: Posicionamiento de bienestar (no producto sanitario) y cumplimiento de las políticas de datos de Google (doc. 12).
- **R-LEG-2**: Sin marcas ni diseño distintivo de WHOOP (RL-60, RL-61).
- **R-ECO-1**: Coste de infraestructura personal ≤ 25 €/mes (RNF-ESC-03) + coste del Coach IA acotado.

## 7. Partes interesadas

| Parte | Interés |
|---|---|
| Propietario / *product owner* | Define prioridades y valida las métricas con sus datos |
| Desarrollo | Implementación y operación |
| Google (proveedor de datos y plataforma) | Cumplimiento de términos de la API, OAuth y marcas |
| Anthropic (proveedor de IA) | Cumplimiento de términos de uso |
| Usuarios futuros (F4) | Privacidad, utilidad, fiabilidad |
| AEPD (autoridad de control) | Cumplimiento del RGPD en el escenario B |

## 8. Decisiones abiertas para el propietario

Las recomendaciones marcadas se han usado como supuesto en toda la especificación; cambiar cualquiera de ellas implica revisar los documentos indicados.

| # | Decisión | Recomendación asumida | Afecta a |
|---|---|---|---|
| D-1 | ¿Solo uso personal o se publicará para terceros? | Personal primero, arquitectura preparada para publicar | 12, 14 |
| D-2 | ¿iPhone, Android o ambos? | Ambos (React Native + Expo). Si es solo Android, se puede adelantar Health Connect a F1 | 03, 08 |
| D-3 | Nombre comercial de la app | Pendiente (sin «WHOOP», «Fitbit» ni «Google») | 11, 12 |
| D-4 | Deportes principales | Carrera, ciclismo, fuerza y caminar como tipos de actividad prioritarios | 04, 05 |
| D-5 | ¿Tienes suscripción Google Health Premium? | No se asume ni se necesita (las puntuaciones de Google no están en la API de todos modos) | 03 |
| D-7 | Modo de la app en Google Cloud para uso personal: *Testing* (reconectar cada 7 días) o producción sin verificar (aviso de «app no verificada», máx. 100 usuarios) | Producción sin verificar, tras comprobarlo en el *spike* | 10, 12 |
| D-6 | Presupuesto mensual (infraestructura + IA) | ≤ 25 € + ≤ 15 $ de IA | 06, 08 |
