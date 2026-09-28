# FitbitApp — app de recuperación y rendimiento tipo WHOOP para la Google Fitbit Air

Especificación completa de requisitos para construir una app que ofrezca con la **Google Fitbit Air** la experiencia de la app de **WHOOP**: cada mañana tu **Sueño**, tu **Recuperación** y tu **Carga** objetivo del día, con monitor de estrés y de salud, diario de hábitos, tendencias, informes y un **Coach IA** que conoce tus datos.

> Estado: **requisitos (fase F0)** — aún no hay código. Información verificada a 28/09/2026.
> Nombre comercial pendiente (no puede usar «WHOOP», «Fitbit» ni «Google», ver RL-60).

## Resumen en 10 puntos

1. **Los datos se leen con la nueva Google Health API** (REST v4, OAuth 2.0 de Google, *webhooks*). La antigua Fitbit Web API se apaga el **30/09/2026**. No hay acceso Bluetooth propietario a la pulsera.
2. La Fitbit Air entrega todo lo necesario: FC (almacenada a 1 s), HRV nocturna (RMSSD), FC en reposo, sueño con fases, SpO₂, frecuencia respiratoria, temperatura cutánea nocturna, pasos, actividad y entrenamientos.
3. Las puntuaciones de Google (*Readiness*, *Sleep Score*, *Cardio Load*) **no están en la API**: todas las puntuaciones se calculan en nuestro backend con **algoritmos abiertos** basados en literatura científica.
4. **Recuperación 0–100 %** (HRV, FC en reposo y sueño frente a tu línea base; zonas 67/34), **Carga 0–21** (TRIMP de Banister en escala saturante), **Sueño** (necesidad, suficiencia, eficiencia, constancia, deuda, planificador) y **Estrés 0–3**.
5. Todos los ámbitos de la API son **restringidos**: para uso personal basta el modo sin verificar (hasta 100 usuarios); publicar la app exige verificación de Google y una **evaluación CASA anual**.
6. Arquitectura: app **React Native + Expo** (iOS y Android), backend **TypeScript/Node.js** en **Google Cloud (Madrid)** con PostgreSQL, *workers* y *webhooks*; paquete de métricas puro y versionado.
7. **Coach IA** con la API de Claude (`claude-opus-5`), con herramientas de solo lectura sobre tus datos, salvaguardas clínicas y modo «solo educativo».
8. Posicionamiento de **bienestar, no producto sanitario** (MDR); privacidad por diseño (RGPD, datos en la UE, exportación y borrado).
9. Plan por fases: **F0** preparación (2 sem) → **F1** MVP (8) → **F2** paridad (8) → **F3** inteligencia (8) → **F4** publicación opcional.
10. Coste orientativo de uso personal: **~20–45 €/mes** con Coach IA (~10–20 € sin él), además de la pulsera (99,99 €).

## Documentos

| # | Documento | Contenido |
|---|---|---|
| 01 | [Visión y alcance](docs/01-vision-y-alcance.md) | Objetivos, usuarios, fases, supuestos, restricciones, **decisiones abiertas** |
| 02 | [Paridad con WHOOP](docs/02-paridad-con-whoop.md) | Inventario de funciones de WHOOP y su equivalente con la Fitbit Air |
| 03 | [Dispositivo y fuentes de datos](docs/03-dispositivo-y-fuentes-de-datos.md) | Fitbit Air, app Google Health, canales de datos, catálogo de datos, brechas |
| 04 | [Requisitos funcionales](docs/04-requisitos-funcionales.md) | RF por módulo con prioridad, fase y criterios de aceptación |
| 05 | [Algoritmos y métricas](docs/05-algoritmos-y-metricas.md) | Fórmulas de recuperación, carga, sueño, estrés, salud, hábitos, edad fisiológica |
| 06 | [Coach IA](docs/06-coach-ia.md) | Requisitos, arquitectura, herramientas, seguridad, privacidad y coste |
| 07 | [Requisitos no funcionales](docs/07-requisitos-no-funcionales.md) | Rendimiento, seguridad, privacidad, accesibilidad, calidad de datos… |
| 08 | [Arquitectura técnica](docs/08-arquitectura-tecnica.md) | Componentes, ADR, flujos, repositorio, entornos |
| 09 | [Modelo de datos](docs/09-modelo-de-datos.md) | Tablas, retención, exportación |
| 10 | [Integración con la Google Health API](docs/10-integracion-google-health-api.md) | Alta, ámbitos, OAuth, endpoints, *webhooks*, cuotas, políticas |
| 11 | [UX y pantallas](docs/11-ux-y-pantallas.md) | Navegación, pantallas, onboarding, estados, notificaciones, sistema visual |
| 12 | [Privacidad, seguridad y legal](docs/12-privacidad-seguridad-y-legal.md) | RGPD, MDR, Ley de IA, políticas de Google y tiendas, marcas |
| 13 | [Pruebas y validación](docs/13-pruebas-y-validacion.md) | Estrategia de pruebas y validación científica de las métricas y del Coach |
| 14 | [Plan de proyecto y riesgos](docs/14-plan-de-proyecto-y-riesgos.md) | Hitos, épicas, riesgos, indicadores |
| 15 | [Entorno y prerrequisitos](docs/15-entorno-y-prerrequisitos.md) | Cuentas, herramientas, variables de entorno, lista de tareas de F0, costes |
| — | [Glosario](docs/glosario.md) · [Referencias](docs/referencias.md) | Términos y bibliografía científica |

Plantilla de configuración: [`.env.example`](.env.example).

## Qué necesitas para empezar (resumen de F0)

1. Fitbit Air emparejada con la app **Google Health** y llevándola día y noche.
2. Proyecto de **Google Cloud** con la Google Health API habilitada, pantalla de consentimiento y cliente OAuth ([doc. 10 §2](docs/10-integracion-google-health-api.md#2-alta-del-proyecto-y-modos-de-uso)).
3. Dominio propio con página de inicio y **política de privacidad** (Google la exige).
4. Herramientas: Node.js 24 LTS, pnpm, Docker, Android Studio y/o Xcode, cuenta de Expo; cuenta de Apple Developer si usas iPhone.
5. Clave de la API de Anthropic cuando se llegue al Coach (F3).
6. Hacer el ***spike* de datos** con tu propia cuenta (hito H0) antes de construir nada más.

Lista completa en [docs/15-entorno-y-prerrequisitos.md](docs/15-entorno-y-prerrequisitos.md).

## Decisiones que debes confirmar

Ver [doc. 01 §8](docs/01-vision-y-alcance.md#8-decisiones-abiertas-para-el-propietario): uso personal o publicación, iPhone/Android, nombre, deportes principales, suscripción Premium, presupuesto y modo de la app en Google Cloud.

## Convenciones de la especificación

- IDs trazables: `RF-*` (funcionales), `RNF-*` (no funcionales), `RL-*` (legales), `ALG-*` (algoritmos), `RSK-*` (riesgos), `OBJ-*`, `SUP-*`, `D-*`.
- Prioridad MoSCoW (M/S/C/W) y fase (F0–F4) en cada requisito.
- Cualquier cambio de requisitos se hace en estos documentos dentro de la misma PR que el código.
