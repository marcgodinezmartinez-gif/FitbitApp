# 07 · Requisitos no funcionales

Contexto: app **personal**, **solo iPhone**, **sin servidor** y **gratuita** (doc. 08). Convenciones: `RNF-<CATEGORÍA>-<nn>`; prioridad **M/S/C**; fase F0–F3 ([doc. 14](14-plan-de-proyecto-y-riesgos.md)).

Los valores numéricos son **objetivos verificables**: cada uno indica cómo se mide. Si un objetivo resulta irreal, se cambia aquí (con fecha y motivo), no se ignora.

---

## 1. Estética y calidad visual (EST)

La estética es un objetivo de primer nivel (el motivo principal para no usar la app oficial). Detalle de diseño en el [doc. 11](11-ux-y-pantallas.md).

| ID | Requisito | Medición | Prio. | Fase |
|---|---|---|---|---|
| RNF-EST-01 | Todas las pantallas usan exclusivamente los **tokens del sistema de diseño** (colores, tipografía, espaciado en retícula de 4/8 pt, radios, sombras); ningún valor «mágico» en las vistas. | Revisión de código + SwiftLint con reglas propias | M | F1 |
| RNF-EST-02 | Animaciones fluidas: **120 fps en pantallas ProMotion** (60 fps en el resto) en transiciones, llenado de anillos y desplazamiento de gráficos; ningún fotograma perdido perceptible. | Instruments (Animation Hitches) en dispositivo | M | F1 |
| RNF-EST-03 | Diseño nativo de iOS 26 (**Liquid Glass** en barras, hojas y controles), SF Symbols, tipografía del sistema con cifras tabulares y soporte completo de modo oscuro (por defecto) y claro. | Revisión de diseño (checklist doc. 11 §9) | M | F1 |
| RNF-EST-04 | Micro-interacciones: transición numérica de las cifras, háptica del iPhone en hitos (recuperación lista, objetivo de carga alcanzado), estados vacíos y de carga diseñados (nunca pantallas en blanco). | Revisión de diseño | S | F1 |
| RNF-EST-05 | Tests de instantánea (*snapshot*) de las pantallas y *widgets* principales en claro/oscuro y en 3 tamaños de letra, para que ningún cambio rompa el diseño sin darse cuenta. | CI | S | F2 |
| RNF-EST-06 | Icono de app propio, pantalla de lanzamiento y *widgets* coherentes con el sistema de diseño. | Revisión de diseño | S | F2 |

## 2. Rendimiento (REN)

| ID | Requisito | Medición | Prio. | Fase |
|---|---|---|---|---|
| RNF-REN-01 | Arranque en frío ≤ 1,5 s hasta la pantalla «Hoy» con datos locales (iPhone 13 o posterior). | Instruments (App Launch), mediana de 10 | M | F1 |
| RNF-REN-02 | Apertura de pantallas de detalle ≤ 200 ms (p95) con datos locales. | Instruments | S | F1 |
| RNF-REN-03 | Gráficos de 1 año (365 puntos por serie) en ≤ 300 ms y desplazamiento sin tirones (RNF-EST-02). | Instruments | S | F2 |
| RNF-REN-04 | Refresco al abrir la app: ≤ 3 s desde que se abre hasta ver las puntuaciones del día, si los datos ya están en la API. | Registro local de tiempos | M | F1 |
| RNF-REN-05 | Cálculo completo de un ciclo (recuperación, carga, sueño, estrés) ≤ 200 ms en el iPhone. | Test de rendimiento de `MetricsKit` | M | F1 |
| RNF-REN-06 | Importación inicial de 90 días ≤ 5 min con la app abierta (continúa en segundo plano si se cierra). | Registro local | S | F1 |
| RNF-REN-07 | Primera palabra del Coach IA (*streaming*) ≤ 4 s (p90). | Registro local | S | F3 |

## 3. Fiabilidad (DIS)

| ID | Requisito | Medición | Prio. | Fase |
|---|---|---|---|---|
| RNF-DIS-01 | La app funciona **sin conexión** con los últimos datos; el diario y las actividades manuales se guardan en local sin depender de la red. | Prueba en modo avión | M | F1 |
| RNF-DIS-02 | La sincronización es **reanudable**: si se interrumpe (app cerrada, sin red, límite de tiempo en segundo plano), continúa donde se quedó. | Test de integración con interrupciones | M | F1 |
| RNF-DIS-03 | Ingesta **idempotente**: la misma muestra descargada varias veces produce una sola fila (claves únicas por tipo e instante/intervalo). | Test repitiendo el mismo lote 3 veces | M | F1 |
| RNF-DIS-04 | Reintentos con *backoff* exponencial y *jitter* ante 429/5xx, respetando `Retry-After`; tras varios fallos, estado visible «Sincronización con problemas». | Test con API simulada | M | F1 |
| RNF-DIS-05 | Si Google o Anthropic no responden, el resto de la app sigue funcionando. | Prueba desactivando cada servicio | M | F1 |
| RNF-DIS-06 | Recuperación ante pérdida del iPhone: todo lo procedente de Google se vuelve a descargar; diario, ajustes y actividades manuales se restauran desde la copia exportada (RF-ONB-05). | Prueba de restauración en otro dispositivo o tras reinstalar | S | F2 |
| RNF-DIS-07 | Cálculos **deterministas**: mismas entradas + misma `algorithm_version` ⇒ mismo resultado. | *Golden files* | M | F1 |
| RNF-DIS-08 | Migraciones de la BD local versionadas, probadas y sin pérdida de datos. | Test de migración desde cada versión anterior | M | F1 |

## 4. Seguridad (SEG)

| ID | Requisito | Medición | Prio. | Fase |
|---|---|---|---|---|
| RNF-SEG-01 | App conforme a **OWASP MASVS v2** en lo aplicable (STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, PRIVACY). | Checklist MASTG | M | F2 |
| RNF-SEG-02 | *Tokens* de Google y clave de la API de IA **solo en el Llavero** (accesibles tras el primer desbloqueo, sin sincronizar con iCloud); nunca en la BD, en `UserDefaults` ni en logs. | Revisión + test que busca patrones de *token* en logs | M | F1 |
| RNF-SEG-03 | BD y ficheros con **protección de datos de iOS** (clase «completa hasta el primer desbloqueo» para permitir el refresco en segundo plano), cifrados por hardware. | Revisión de configuración | M | F1 |
| RNF-SEG-04 | OAuth 2.0 con PKCE en el navegador del sistema (`ASWebAuthenticationSession`), nunca en un WebView; `state` anti-CSRF. | Revisión + prueba del flujo | M | F1 |
| RNF-SEG-05 | Solo HTTPS con TLS ≥ 1.2 y sin excepciones de App Transport Security. | Revisión de `Info.plist` | M | F1 |
| RNF-SEG-06 | Bloqueo opcional con Face ID / código y contenido oculto en el selector de apps (RF-PER-05). | Prueba manual | S | F2 |
| RNF-SEG-07 | Ningún secreto en el repositorio: la configuración usa `Config/Secrets.xcconfig` ignorado por Git; escaneo de secretos (gitleaks) en CI y *push protection* en GitHub. | CI | M | F0 |
| RNF-SEG-08 | Dependencias mínimas y revisadas (sin SDK de analítica ni publicidad); actualizaciones de seguridad aplicadas en ≤ 30 días. | Revisión de `Package.resolved` | M | F1 |
| RNF-SEG-09 | Coach IA protegido frente a *prompt injection*: los textos libres del diario se tratan como datos; las herramientas del Coach son **de solo lectura** sobre la BD local. | Suite de pruebas adversarias (doc. 13 §7) | M | F3 |

## 5. Privacidad (PRI)

| ID | Requisito | Medición | Prio. | Fase |
|---|---|---|---|---|
| RNF-PRI-01 | **Minimización**: solo los ámbitos de Google imprescindibles (doc. 10 §3); los opcionales se piden al activar la función. | Revisión de la pantalla de consentimiento | M | F1 |
| RNF-PRI-02 | **Sin telemetría ni analítica** de terceros. Los registros de diagnóstico son locales y sin datos de salud. | Revisión de dependencias y tráfico de red | M | F1 |
| RNF-PRI-03 | Los datos de salud solo salen del iPhone hacia Google (lectura) y, si el Coach está activado, hacia el proveedor de IA con lo mínimo necesario (doc. 06 §7). | Inspección del tráfico (proxy) | M | F1 |
| RNF-PRI-04 | «Borrar todos los datos» elimina BD, instantánea de *widgets*, conversaciones y *tokens*, y revoca el acceso en Google (RF-PRI-02). | Test E2E | M | F1 |
| RNF-PRI-05 | Exportación completa en formato abierto (JSON + CSV) (RF-PRI-01). | Test E2E | M | F2 |
| RNF-PRI-06 | Retención configurable de datos intradía (24 meses por defecto); al vencer se **borra** el dato, nunca se sustituye por un agregado (RL-44). | Test del purgado | S | F2 |

## 6. Accesibilidad (ACC)

| ID | Requisito | Medición | Prio. | Fase |
|---|---|---|---|---|
| RNF-ACC-01 | Pautas **WCAG 2.2 AA** y guías de accesibilidad de Apple. | Accessibility Inspector + revisión manual | S | F2 |
| RNF-ACC-02 | El color **nunca** es el único portador de información: zonas con texto («Alta/Media/Baja») e icono; paleta segura para daltonismo. | Simulador de daltonismo | M | F1 |
| RNF-ACC-03 | Contraste ≥ 4,5:1 en texto y ≥ 3:1 en gráficos significativos, en claro y oscuro. | Herramienta de contraste | M | F1 |
| RNF-ACC-04 | Tipo dinámico hasta los tamaños de accesibilidad sin perder contenido; objetivos táctiles ≥ 44×44 pt. | Prueba manual | S | F2 |
| RNF-ACC-05 | VoiceOver: anillos y gráficos con descripción equivalente («Recuperación 72 %, zona alta, 8 puntos sobre tu media semanal»); Swift Charts con *audio graphs*. | Prueba con VoiceOver | S | F2 |
| RNF-ACC-06 | Respeta «Reducir movimiento» y «Reducir transparencia». | Prueba manual | S | F2 |
| RNF-ACC-07 | Toda métrica tiene explicación a ≤ 2 toques («¿Qué es?» / «¿Por qué hoy es así?»). | Revisión de pantallas | S | F1 |
| RNF-ACC-08 | El onboarding completo (incluida la conexión con Google) se hace en ≤ 3 min. | Prueba cronometrada | S | F1 |

## 7. Internacionalización (I18N)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RNF-I18N-01 | Español (es-ES) por defecto con catálogo de cadenas (String Catalog); inglés opcional. | M | F1 |
| RNF-I18N-02 | Sistema métrico, 24 h y formatos según la configuración regional del iPhone. | M | F1 |
| RNF-I18N-03 | Marcas de tiempo en UTC con el desfase de cada muestra; días y ciclos en la zona horaria vigente en cada momento (viajes, horario de verano). | M | F1 |
| RNF-I18N-04 | Las noches con cambio de hora se calculan con duraciones reales. | M | F1 |

## 8. Compatibilidad (COM)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RNF-COM-01 | **iOS 26 o posterior** (iPhone 11 o posterior); se adopta cada nueva versión mayor de iOS en ≤ 2 meses. | M | F1 |
| RNF-COM-02 | Solo iPhone y orientación vertical. | M | F1 |
| RNF-COM-03 | Funciona con cualquier dispositivo que publique en la Google Health API, pero solo se garantiza con la Fitbit Air; las funciones sin datos se ocultan en lugar de mostrar vacíos. | S | F2 |

## 9. Calidad de datos (CAL)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RNF-CAL-01 | Cada puntuación indica su **confianza** (alta/media/baja) según la cobertura de datos. | M | F1 |
| RNF-CAL-02 | Sin datos suficientes no hay cifra inventada: «Calibrando (n/4 noches)» o «Datos insuficientes» con el motivo. | M | F1 |
| RNF-CAL-03 | Detección y descarte de artefactos (FC fuera de [25, 230] lpm, saltos imposibles, sin pulsera). | M | F1 |
| RNF-CAL-04 | Datos tardíos o editados en Google ⇒ recálculo automático de los días afectados y de las líneas base. | M | F1 |
| RNF-CAL-05 | Cada valor derivado guarda `algorithm_version` y parámetros. | M | F1 |

## 10. Mantenibilidad (MAN)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RNF-MAN-01 | Paquetes Swift separados (doc. 08 §3); `MetricsKit` y `HealthAPI` sin dependencias de UI. | M | F0 |
| RNF-MAN-02 | Cobertura de tests ≥ 90 % en `MetricsKit` y ≥ 70 % en `HealthAPI`, `Store` y `Sync`. | M | F1 |
| RNF-MAN-03 | CI en GitHub Actions: formato, *lint*, tests de paquetes (Linux y macOS), escaneo de secretos; *build* de la app en macOS si hay minutos disponibles. | M | F0 |
| RNF-MAN-04 | Versionado semántico de la app y de `algorithm_version`, con *changelog* de algoritmos visible en «Cómo calculamos». | S | F2 |
| RNF-MAN-05 | Decisiones de arquitectura como ADR en `docs/adr/`. | S | F0 |
| RNF-MAN-06 | Proyecto de Xcode generado desde un fichero legible (XcodeGen o Tuist) para evitar conflictos en `project.pbxproj`. | C | F0 |

## 11. Energía y datos (ENE)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RNF-ENE-01 | Sin sondeo continuo: solo sincronización al abrir, manual y en tareas en segundo plano que gestiona iOS. | M | F1 |
| RNF-ENE-02 | Consumo en segundo plano < 1 % de batería/día (Ajustes › Batería). | S | F2 |
| RNF-ENE-03 | Las tareas pesadas (importación, recálculo de líneas base) se ejecutan como `BGProcessingTask` cuando el iPhone está cargando. | S | F1 |

## 12. Coste (COS)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RNF-COS-01 | **Coste recurrente obligatorio: 0 €**. Sin servidor, sin suscripciones y sin Google Health Premium. | M | F0 |
| RNF-COS-02 | Costes opcionales explícitos y bajo control del usuario: Apple Developer Program (99 $/año, solo por comodidad de instalación) y Coach IA (pago por uso con límite de gasto en la consola de Anthropic y límite diario en la app). | M | F3 |

## 13. Conformidad

Los requisitos legales están en [12-privacidad-seguridad-y-legal.md](12-privacidad-seguridad-y-legal.md). Para uso personal, lo que aplica son sobre todo las **condiciones de la Google Health API** (RL-40 a RL-48).
