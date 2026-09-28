# 07 · Requisitos no funcionales

Convenciones: `RNF-<CATEGORÍA>-<nn>`. Prioridad MoSCoW: **M** (imprescindible), **S** (importante), **C** (deseable). Fase: F0–F4 (ver [14-plan-de-proyecto-y-riesgos.md](14-plan-de-proyecto-y-riesgos.md)).

Los valores numéricos son **objetivos verificables**: cada uno indica cómo se mide. Si durante la implementación un objetivo resulta irreal, se cambia aquí (con fecha y motivo), no se ignora en silencio.

---

## 1. Rendimiento (REN)

| ID | Requisito | Medición | Prioridad | Fase |
|---|---|---|---|---|
| RNF-REN-01 | Arranque en frío de la app ≤ 2,5 s hasta la pantalla «Hoy» con datos en caché, en un móvil de gama media (p. ej. Pixel 7a / iPhone 13). | Traza de arranque en build de *release*, mediana de 10 arranques. | M | F1 |
| RNF-REN-02 | Cambio entre pestañas y apertura de pantallas de detalle ≤ 300 ms (p95) con datos locales. | Profiler de la app (Flipper/Perfetto/Instruments). | S | F1 |
| RNF-REN-03 | Gráficos de tendencias de 1 año (365 puntos por serie) renderizados en ≤ 500 ms y desplazamiento a ≥ 55 fps. | Profiler, dispositivo de gama media. | S | F2 |
| RNF-REN-04 | Desde que la Google Health API expone datos nuevos (notificación o sondeo) hasta que las puntuaciones del día están recalculadas: ≤ 2 min (p95). | Métrica `sync_to_score_latency_seconds`. | M | F1 |
| RNF-REN-05 | Cálculo completo de un ciclo diario (recuperación + carga + sueño + estrés) ≤ 2 s de CPU en el servidor. | Test de rendimiento del paquete de métricas con un día sintético de datos intradía de 1 s. | M | F1 |
| RNF-REN-06 | Backfill inicial de 90 días de historial terminado en ≤ 15 min respetando las cuotas de la API, con progreso visible. | Log del job de backfill. | S | F1 |
| RNF-REN-07 | Primera palabra de respuesta del Coach IA (streaming) en ≤ 4 s (p90). | Métrica `coach_ttft_seconds`. | S | F3 |
| RNF-REN-08 | Endpoints de lectura de la API propia: p95 ≤ 300 ms, p99 ≤ 800 ms (sin contar el Coach). | APM / trazas. | S | F1 |

## 2. Disponibilidad y fiabilidad (DIS)

| ID | Requisito | Medición | Prioridad | Fase |
|---|---|---|---|---|
| RNF-DIS-01 | Disponibilidad mensual del backend ≥ 99,5 % (uso personal) y ≥ 99,9 % si se publica para terceros. | Uptime check externo cada minuto. | S | F1 |
| RNF-DIS-02 | La app es **utilizable sin conexión**: muestra los últimos datos sincronizados, el diario se puede rellenar y se envía al recuperar la red. | Prueba E2E en modo avión. | M | F1 |
| RNF-DIS-03 | Ningún dato se pierde si falla la sincronización: los trabajos son **idempotentes** y reintentables (clave natural por usuario + tipo + intervalo temporal). | Tests de integración que repiten el mismo lote 3 veces sin duplicados. | M | F1 |
| RNF-DIS-04 | Reintentos con *backoff* exponencial y *jitter* ante 429/5xx de la Google Health API; respeto de `Retry-After`. Tras N fallos, el usuario ve el estado «sincronización con problemas». | Test con API simulada que devuelve 429/503. | M | F1 |
| RNF-DIS-05 | Si un proveedor externo (Google Health API, Anthropic) no está disponible, el resto de la app sigue funcionando (degradación elegante). | *Chaos test* desactivando cada proveedor. | M | F1 |
| RNF-DIS-06 | Copias de seguridad diarias de la base de datos, retención 30 días, cifradas; **RPO ≤ 24 h, RTO ≤ 4 h**. Restauración probada al menos una vez por trimestre. | Registro de la prueba de restauración. | S | F1 |
| RNF-DIS-07 | Los recálculos son **deterministas**: mismos datos de entrada + misma `algorithm_version` ⇒ mismo resultado bit a bit. | Test de regresión con *golden files*. | M | F1 |

## 3. Seguridad (SEG)

| ID | Requisito | Medición | Prioridad | Fase |
|---|---|---|---|---|
| RNF-SEG-01 | App móvil conforme a **OWASP MASVS v2** (controles STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, PRIVACY) con el perfil para datos sensibles. | Checklist MASTG antes de cada publicación. | M | F1 |
| RNF-SEG-02 | Backend conforme a **OWASP ASVS 5.0 nivel 2**. | Checklist + SAST/DAST en CI. | M | F1 |
| RNF-SEG-03 | Todo el tráfico con TLS ≥ 1.2 (preferible 1.3), HSTS en dominios web. Sin excepciones de ATS (iOS) ni `cleartextTrafficPermitted` (Android). | Escaneo TLS + revisión de configuración. | M | F1 |
| RNF-SEG-04 | Los *tokens* OAuth de Google (acceso y refresco) se guardan **solo en el backend**, cifrados con cifrado de sobre (DEK por registro, KEK en Cloud KMS/HSM, como exige la política de la Google Health API). Nunca en la app ni en logs. La base de datos entera está cifrada en reposo. | Revisión de código + test que busca patrones de token en logs. | M | F1 |
| RNF-SEG-05 | Flujo OAuth 2.0 *authorization code* con **PKCE** y parámetro `state` anti-CSRF; `redirect_uri` exactas registradas. | Test E2E del flujo de vinculación. | M | F1 |
| RNF-SEG-06 | Autenticación de usuarios de la app mediante proveedor gestionado (Sign in with Google / Apple / passkeys). Sesiones con *access token* corto (≤ 15 min) y *refresh token* rotatorio almacenado en Keychain / Android Keystore. | Revisión + test. | M | F1 |
| RNF-SEG-07 | Bloqueo opcional de la app con biometría (Face ID / huella) y ocultación del contenido en el selector de apps. | Prueba manual en ambos SO. | S | F2 |
| RNF-SEG-08 | Aislamiento por usuario en la base de datos (*row-level security* o filtro obligatorio por `user_id` verificado en tests). | Tests que intentan leer datos de otro usuario (deben fallar). | M | F1 |
| RNF-SEG-09 | Secretos (claves de API, credenciales OAuth, claves de firma de webhooks) en un gestor de secretos, nunca en el repositorio. Escaneo de secretos en CI (p. ej. gitleaks) y *push protection* en GitHub. | CI verde + alerta en PR. | M | F0 |
| RNF-SEG-10 | Verificación de autenticidad de las notificaciones entrantes (*webhooks*): secreto en la cabecera `Authorization` **y** firma `GOOGLE-HEALTH-API-SIGNATURE` verificada con Tink contra el conjunto de claves públicas de Google (doc. 10 §6.2); procesamiento idempotente frente a duplicados y reintentos. | Test con notificación falsificada o con firma inválida (debe rechazarse). | M | F1 |
| RNF-SEG-11 | Dependencias con escaneo de vulnerabilidades (Dependabot/Renovate + `npm audit`/OSV) y política de parches: críticas ≤ 7 días, altas ≤ 30 días. | Informe semanal. | S | F1 |
| RNF-SEG-12 | Protección del Coach IA frente a *prompt injection*: los datos del usuario y los textos libres del diario se tratan como datos, no como instrucciones; las herramientas del Coach son de **solo lectura** sobre los datos del propio usuario. | Suite de pruebas adversarias del Coach (ver doc. 13). | M | F3 |
| RNF-SEG-13 | Registro de auditoría inmutable de accesos administrativos y de operaciones sensibles (exportación, borrado, vinculación/desvinculación). | Revisión de la tabla `audit_log`. | S | F1 |
| RNF-SEG-14 | Prueba de penetración externa antes de abrir la app a usuarios distintos del propietario (y, si aplica, evaluación **CASA** exigida por Google para ámbitos restringidos). | Informe del pentest / carta de validación CASA. | M | F4 |

## 4. Privacidad (PRI)

| ID | Requisito | Medición | Prioridad | Fase |
|---|---|---|---|---|
| RNF-PRI-01 | **Minimización**: solo se solicitan los ámbitos (*scopes*) de la Google Health API estrictamente necesarios para las funciones activas; los ámbitos opcionales se piden de forma incremental cuando el usuario activa la función. | Revisión de la pantalla de consentimiento. | M | F1 |
| RNF-PRI-02 | Ningún dato de salud en logs, trazas, analítica de producto ni informes de errores (Sentry/Crashlytics con *scrubbing*). | Test automático de *scrubbing* + revisión. | M | F1 |
| RNF-PRI-03 | Retención configurable: datos intradía (FC por minuto, FC de 1 s en entrenamientos, pasos por minuto, muestras de HRV) 24 meses por defecto; datos diarios y puntuaciones mientras la cuenta exista; conversaciones del Coach 12 meses (borrables en cualquier momento). Al vencer se borra el dato, **nunca se sustituye por un agregado** (RL-44). | Job de purga + test. | S | F2 |
| RNF-PRI-04 | Borrado completo de la cuenta (datos, tokens revocados en Google, conversaciones, copias) en ≤ 30 días; eliminación de la vista del usuario inmediata. | Test E2E de borrado + verificación en BD. | M | F1 |
| RNF-PRI-05 | Exportación de todos los datos del usuario en formato abierto (JSON + CSV) en ≤ 24 h. | Test E2E. | M | F2 |
| RNF-PRI-06 | La analítica de producto (si existe) es opcional (*opt-in*), seudonimizada y sin datos de salud. | Revisión del plan de eventos. | S | F2 |
| RNF-PRI-07 | Alojamiento de datos en la **UE** (p. ej. región `europe-southwest1` Madrid o `europe-west1`). Las transferencias fuera del EEE (p. ej. al proveedor del LLM) quedan documentadas con su base legal. | Revisión de infraestructura + registro de actividades. | M | F1 |
| RNF-PRI-08 | Al Coach IA solo se envían los datos necesarios para responder, seudonimizados (sin nombre, email ni identificadores de Google). | Revisión de las funciones de herramientas y test de contenido. | M | F3 |

## 5. Usabilidad y accesibilidad (ACC)

| ID | Requisito | Medición | Prioridad | Fase |
|---|---|---|---|---|
| RNF-ACC-01 | Cumplir **WCAG 2.2 nivel AA** en la app y la web. | Auditoría con Accessibility Scanner (Android), Accessibility Inspector (iOS) y revisión manual. | M | F2 |
| RNF-ACC-02 | El color **nunca** es el único portador de información: las zonas verde/amarilla/roja van siempre acompañadas de texto («Alta», «Media», «Baja») e iconografía; paleta segura para daltonismo. | Revisión con simulador de daltonismo. | M | F1 |
| RNF-ACC-03 | Contraste ≥ 4,5:1 en texto y ≥ 3:1 en elementos gráficos significativos, en tema claro y oscuro. | Herramienta de contraste. | M | F1 |
| RNF-ACC-04 | Soporte de tamaño de letra dinámico hasta 200 % sin pérdida de contenido; objetivos táctiles ≥ 44×44 pt. | Prueba manual. | M | F2 |
| RNF-ACC-05 | Lectores de pantalla (VoiceOver/TalkBack): los diales y gráficos tienen descripción textual equivalente (p. ej. «Recuperación 72 %, zona alta, 8 puntos por encima de tu media semanal»). | Prueba manual con lector. | M | F2 |
| RNF-ACC-06 | Un usuario nuevo completa la vinculación con su cuenta de Google y ve su primer dato en ≤ 3 min sin ayuda. | Prueba de usabilidad con 5 personas. | S | F1 |
| RNF-ACC-07 | Toda métrica tiene una explicación accesible en ≤ 2 toques («¿Qué es esto?» / «¿Cómo se calcula?»). | Revisión de pantallas. | S | F1 |

## 6. Internacionalización (I18N)

| ID | Requisito | Prioridad | Fase |
|---|---|---|---|
| RNF-I18N-01 | Idioma por defecto **español (es-ES)**; inglés (en) como segundo idioma. Todos los textos en ficheros de traducción (ningún literal en el código). | M | F1 |
| RNF-I18N-02 | Sistema métrico por defecto (kg, km, °C), con opción imperial. Formato 24 h y fechas `dd/mm/aaaa` según configuración regional. | M | F1 |
| RNF-I18N-03 | Todas las marcas de tiempo se almacenan en UTC con el **desfase horario local de cada muestra**; los «días» y ciclos se calculan en la zona horaria del usuario en ese momento (viajes, cambios de horario de verano). | M | F1 |
| RNF-I18N-04 | Las noches que cruzan un cambio de hora (último domingo de marzo/octubre en España) se calculan con duraciones reales, no de reloj. | M | F1 |

## 7. Compatibilidad (COM)

| ID | Requisito | Prioridad | Fase |
|---|---|---|---|
| RNF-COM-01 | Versiones mínimas alineadas con la Fitbit Air (que exige Android 11+ o iOS 16.4+ para la app Google Health): **Android 11 (API 30)+** e **iOS 17+** (o el mínimo superior que imponga la versión de Expo/React Native usada). Health Connect: disponible desde Android 9, integrado en el sistema desde Android 14. | M | F1 |
| RNF-COM-02 | Teléfonos y tabletas en orientación vertical; tabletas en horizontal: C. | M/C | F1 |
| RNF-COM-03 | La app funciona con cualquier dispositivo que publique datos en la Google Health API (Fitbit Air, otros Fitbit, Pixel Watch), pero **solo se garantiza** con Fitbit Air; las funciones que dependan de datos no disponibles se ocultan en lugar de mostrar valores vacíos. | S | F2 |

## 8. Calidad de datos (CAL)

| ID | Requisito | Prioridad | Fase |
|---|---|---|---|
| RNF-CAL-01 | Cada puntuación indica su **confianza** (alta/media/baja) según cobertura de datos (p. ej. % de minutos con FC durante el sueño, noches disponibles para la línea base). | M | F1 |
| RNF-CAL-02 | Con datos insuficientes no se muestra una cifra inventada: se muestra el estado «Calibrando (n/4 noches)» o «Datos insuficientes» y el motivo. | M | F1 |
| RNF-CAL-03 | Detección y descarte de artefactos: FC fuera de [25, 230] lpm, saltos imposibles, periodos sin llevar la pulsera (*off-wrist*). | M | F1 |
| RNF-CAL-04 | Los datos que lleguen tarde (sincronización retrasada) provocan el recálculo de los días afectados y de las líneas base dependientes, sin intervención manual. | M | F1 |
| RNF-CAL-05 | Cada valor derivado guarda `algorithm_version` y los parámetros usados para permitir auditoría y recálculo. | M | F1 |

## 9. Mantenibilidad y calidad del código (MAN)

| ID | Requisito | Prioridad | Fase |
|---|---|---|---|
| RNF-MAN-01 | Monorepo con paquetes separados: app, API, *workers*, paquete de métricas puro (sin E/S) y cliente de la Google Health API detrás de una interfaz (*adapter*) para poder cambiar de fuente de datos. | M | F0 |
| RNF-MAN-02 | Cobertura de tests ≥ 90 % en el paquete de métricas y ≥ 70 % en el resto del backend. | M | F1 |
| RNF-MAN-03 | CI en cada PR: lint, formato, *typecheck*, tests, build de la app, escaneo de secretos y dependencias. Rama principal protegida. | M | F0 |
| RNF-MAN-04 | Versionado semántico de la app y de `algorithm_version`; *changelog* de algoritmos visible para el usuario («Hemos mejorado el cálculo de…»). | S | F2 |
| RNF-MAN-05 | *Feature flags* para activar funciones por usuario (p. ej. Coach IA, edad fisiológica) sin publicar una nueva versión. | S | F2 |
| RNF-MAN-06 | Decisiones de arquitectura registradas como ADR en `docs/adr/`. | S | F0 |
| RNF-MAN-07 | Infraestructura como código (Terraform/Pulumi) para todos los recursos cloud. | C | F2 |

## 10. Observabilidad (OBS)

| ID | Requisito | Prioridad | Fase |
|---|---|---|---|
| RNF-OBS-01 | Logs estructurados (JSON) con `request_id`/`trace_id`, sin datos de salud (ver RNF-PRI-02). | M | F1 |
| RNF-OBS-02 | Métricas técnicas mínimas: latencia de sincronización, tasa de errores por endpoint de la Google Health API, cuota consumida, *tokens* caducados/revocados, coste y latencia del Coach IA. | M | F1 |
| RNF-OBS-03 | Alertas: fallo de sincronización > 6 h para cualquier usuario activo, tasa de 5xx > 2 % durante 10 min, cuota de API > 80 %, gasto diario del LLM > umbral. | S | F1 |
| RNF-OBS-04 | *Crash reporting* en la app con tasa de sesiones sin fallos ≥ 99,5 %. | S | F1 |

## 11. Escalabilidad y coste (ESC)

| ID | Requisito | Prioridad | Fase |
|---|---|---|---|
| RNF-ESC-01 | Diseño multiusuario desde el primer día (aunque el MVP tenga un solo usuario): todas las tablas llevan `user_id`, sin estado en memoria entre peticiones. | M | F1 |
| RNF-ESC-02 | Soportar 10 000 usuarios activos con un aumento lineal de coste y sin rediseño: ~1 440 filas de FC por minuto/usuario/día + FC de 1 s en entrenamientos ⇒ tablas particionadas por tiempo (o TimescaleDB). Respetar las cuotas de la Google Health API (300 peticiones/min por usuario, 120 000/min por proyecto) con limitación por usuario. | S | F4 |
| RNF-ESC-03 | Coste de infraestructura para uso personal ≤ 25 €/mes (sin contar dispositivo ni suscripciones de tiendas). | S | F1 |
| RNF-ESC-04 | Límite de uso del Coach IA por usuario y día configurable (mensajes y tokens) para acotar coste. | M | F3 |

## 12. Energía y datos móviles (ENE)

| ID | Requisito | Prioridad | Fase |
|---|---|---|---|
| RNF-ENE-01 | La app no hace sondeo continuo en segundo plano: el refresco lo dispara el backend mediante notificaciones *push* silenciosas o al abrir la app. | M | F1 |
| RNF-ENE-02 | Consumo de la app en segundo plano < 1 % de batería/día en las herramientas del sistema. | S | F2 |
| RNF-ENE-03 | La app descarga del backend series por minuto o por ventana según el zoom del gráfico; la FC de 1 s solo al abrir el detalle de un entrenamiento. | S | F1 |

## 13. Conformidad (resumen)

Los requisitos legales detallados están en [12-privacidad-seguridad-y-legal.md](12-privacidad-seguridad-y-legal.md). Como RNF transversal: **ninguna funcionalidad se publica sin haber pasado la lista de verificación legal** de ese documento (RL-*).
