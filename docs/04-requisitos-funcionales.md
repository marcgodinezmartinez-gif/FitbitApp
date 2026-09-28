# 04 · Requisitos funcionales

Convenciones:

- ID `RF-<MÓDULO>-<nn>`. Prioridad MoSCoW: **M** imprescindible · **S** importante · **C** deseable · **W** fuera de alcance por ahora.
- **Fase**: F0–F3 ([doc. 14](14-plan-de-proyecto-y-riesgos.md)).
- **Alg.**: especificación del cálculo en [05-algoritmos-y-metricas.md](05-algoritmos-y-metricas.md).
- Los datos de entrada de cada módulo y su disponibilidad en la Fitbit Air están en [03-dispositivo-y-fuentes-de-datos.md](03-dispositivo-y-fuentes-de-datos.md).
- Los requisitos del Coach IA (`RF-COA-*`) están en [06-coach-ia.md](06-coach-ia.md).

---

## 1. Cuenta y onboarding (ONB)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-ONB-01 | **Sin cuentas propias**: la app es de un solo usuario y sus datos viven en el iPhone; el único inicio de sesión es el de Google para leer los datos de la pulsera (RF-CON-01). | M | F1 |
| RF-ONB-02 | Perfil: fecha de nacimiento, sexo (hombre/mujer/prefiero no decirlo), altura, peso, deportes principales, hora habitual de despertar. Editable en todo momento; los cambios recalculan lo que dependa de ellos (FC máx., coeficientes de carga, necesidad de sueño base). | M | F1 |
| RF-ONB-03 | Aceptación versionada del aviso de bienestar y de la política de privacidad; si cambia la versión, se vuelve a pedir. | M | F1 |
| RF-ONB-04 | Tutorial breve (≤ 4 pantallas, saltable) de Sueño, Recuperación y Carga. | S | F1 |
| RF-ONB-05 | **Restaurar** tras reinstalar o cambiar de iPhone: volver a importar el histórico desde Google y recuperar diario, ajustes y actividades manuales desde una copia exportada (RF-PRI-01). | S | F2 |

## 2. Conexión con Google Health (CON)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-CON-01 | Vincular la cuenta de Google en la que está registrada la Fitbit Air mediante OAuth 2.0 (código de autorización + PKCE, navegador del sistema), pidiendo solo los ámbitos necesarios (RNF-PRI-01, doc. 10 §3). Justo antes, **divulgación destacada** de qué datos se recogen y para qué (RL-43). | M | F1 |
| RF-CON-02 | Estado de la conexión: «Conectado a Google Health» con la hora de la **última sincronización de la pulsera** (`pairedDevices`) y de nuestra última lectura, ámbitos concedidos y errores recientes (RL-46). | M | F1 |
| RF-CON-03 | «Desconectar» accesible en 1–2 toques: revoca el *token* en Google, detiene la sincronización y pregunta si se conservan o borran los datos importados (RL-47). | M | F1 |
| RF-CON-04 | Detectar *token* revocado/caducado o ámbitos retirados ⇒ estado «Reconectar» y aviso NOT-07. | M | F1 |
| RF-CON-05 | Solicitud **incremental** de ámbitos cuando el usuario activa una función que los necesite; si los deniega, la función queda desactivada con explicación. | S | F2 |
| RF-CON-06 | Lectura opcional de **Apple Health** (HealthKit, solo lectura) como respaldo para FC, sueño y entrenamientos si la API no responde (Google Health no escribe allí HRV ni temperatura, así que no sustituye a la API). | C | F3 |
| RF-CON-07 | Información del dispositivo (modelo, última sincronización y batería, si la API lo expone). | C | F2 |
| RF-CON-08 | Si la API responde que el usuario no tiene perfil de Google Health (HTTP 412), guiarle a configurarlo en la app Google Health y reintentar. | M | F1 |

## 3. Sincronización de datos (SYN)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-SYN-01 | Al vincular, importar el historial de **90 días** (configurable hasta el máximo que permita la API) de todos los tipos de datos autorizados, con progreso visible; si se cierra la app, la importación continúa en segundo plano. | M | F1 |
| RF-SYN-02 | Sincronización incremental al abrir la app, en segundo plano (`BGAppRefreshTask` programada para la hora habitual de despertar y `BGProcessingTask` nocturna) y bajo demanda, re-consultando las últimas 48 h y los huecos (doc. 08 §4.4, doc. 10 §6). | M | F1 |
| RF-SYN-03 | *Pull-to-refresh* en la app fuerza una sincronización incremental (máx. 1/min por usuario). | M | F1 |
| RF-SYN-04 | Normalizar todos los datos al modelo interno (doc. 09) guardando UTC + desfase horario de cada muestra. | M | F1 |
| RF-SYN-05 | Ingesta idempotente y sin duplicados (misma muestra recibida varias veces ⇒ una fila). | M | F1 |
| RF-SYN-06 | Datos tardíos o modificados en origen (p. ej. el usuario edita su sueño en Google Health) ⇒ recálculo automático de los ciclos y líneas base afectados. | M | F1 |
| RF-SYN-07 | Indicador global «Actualizado hace X» y estado de sincronización en la pantalla Hoy. | M | F1 |
| RF-SYN-08 | Registrar lagunas de datos con su causa probable (sin pulsera, sin sincronizar, dato no disponible) para mostrarlas en la UI. | S | F2 |

## 4. Sueño (SUE)

| ID | Requisito | Prio. | Fase | Alg. |
|---|---|---|---|---|
| RF-SUE-01 | Mostrar la sesión de sueño principal: inicio, fin, tiempo en cama, tiempo dormido, tiempo despierto, fases (ligero, profundo, REM, despierto) e hipnograma. | M | F1 | — |
| RF-SUE-02 | Clasificar sesiones en **sueño principal** y **siestas** (usando el indicador de la API si existe; si no, reglas de ALG-SUE-00). | M | F1 | SUE-00 |
| RF-SUE-03 | Calcular la **necesidad de sueño** de cada noche con su desglose (base + carga + deuda − siestas). | M | F1 | SUE-01 |
| RF-SUE-04 | Calcular la **suficiencia** (horas dormidas / necesidad) y el **rendimiento de sueño** (0–100 %, dial) compuesto por suficiencia, eficiencia y constancia, con bandas óptimo (≥ 85) / suficiente (70–84) / bajo (< 70) para el total y cada submétrica. | M | F1 (constancia desde F2) | SUE-02, SUE-07 |
| RF-SUE-05 | Mostrar eficiencia, despertares, % de sueño reparador (profundo + REM) y latencia si está disponible. | M | F1 | SUE-06 |
| RF-SUE-06 | Calcular y mostrar la **deuda de sueño** acumulada. | S | F2 | SUE-03 |
| RF-SUE-07 | Calcular la **constancia** del sueño (índice de regularidad de 7 días). | S | F2 | SUE-04 |
| RF-SUE-08 | **Planificador** con dos modos: «Alcanzar mi necesidad» (hora recomendada para acostarse según hora de despertar y objetivo 100 % / 85 % / 70 %) y «Mejorar mi constancia» (acerca la hora de acostarse a la habitual en pasos de ≤ 15 min por noche). | S | F2 | SUE-05 |
| RF-SUE-09 | Recordatorio de hora de acostarse (NOT-02). | S | F2 | — |
| RF-SUE-10 | Las siestas se muestran aparte y reducen la necesidad de la noche siguiente. | S | F2 | SUE-01 |
| RF-SUE-11 | Mostrar en el detalle del sueño la FR, SpO₂ y desviación de temperatura de la noche. | M | F1 | — |
| RF-SUE-12 | «Alarma por necesidad cumplida» en el **iPhone** con AlarmKit (iOS 26, suena aunque esté en silencio; [verificar] si la capacidad exige cuenta de pago): indicas «me voy a dormir» y una ventana de despertar; suena cuando se estima cumplida la necesidad dentro de la ventana (no hay fases en tiempo real ni vibración de la pulsera). | C | F3 | SUE-05 |

## 5. Recuperación (REC)

| ID | Requisito | Prio. | Fase | Alg. |
|---|---|---|---|---|
| RF-REC-01 | Calcular la **recuperación diaria (0–100 %)** en cuanto se dispone del sueño principal y la HRV de la noche. | M | F1 | REC-01 |
| RF-REC-02 | Clasificar en zonas **alta (67–100)**, **media (34–66)** y **baja (0–33)** con color + etiqueta + icono. | M | F1 | REC-01 |
| RF-REC-03 | **Calibración**: no mostrar la puntuación hasta tener 4 noches válidas; confianza «media» hasta 14 noches; «alta» después (si la cobertura de la noche es buena). | M | F1 | BAS-01 |
| RF-REC-04 | Desglose de la contribución de cada componente (HRV, FC en reposo, sueño, FR, temperatura, SpO₂) frente a la línea base personal, en lenguaje natural («Tu VFC está un 12 % por encima de tu media»). | M | F1 | REC-01 |
| RF-REC-05 | Si faltan componentes secundarios (FR, temperatura, SpO₂) se calcula con los disponibles (re-ponderación) y baja la confianza; **sin HRV nocturna no se calcula** y se muestra «Datos insuficientes». | M | F1 | REC-01 |
| RF-REC-06 | Recalcular la recuperación si llegan datos tardíos de la misma noche (y registrar el cambio). | M | F1 | — |
| RF-REC-07 | Tendencia de recuperación de 7/30/90 días con media móvil. | S | F2 | — |

## 6. Carga («Strain») y entrenamientos (CAR, ENT)

| ID | Requisito | Prio. | Fase | Alg. |
|---|---|---|---|---|
| RF-CAR-01 | Calcular la **carga del ciclo (0–21)** a partir de la FC intradía, actualizada en cada sincronización. | M | F1 | CAR-01 |
| RF-CAR-02 | Calcular la **carga de cada actividad** (0–21) con la FC del intervalo de la actividad. | S | F2 | CAR-02 |
| RF-CAR-03 | Zonas de FC (5 zonas) por % de FC de reserva por defecto, o % de FC máx., o personalizadas; minutos en cada zona por ciclo y actividad. | S | F2 | CAR-06 |
| RF-CAR-04 | **Carga objetivo** del día en función de la recuperación (banda mostrada en el dial), con estado «por debajo / en objetivo / por encima» durante el día y ajuste manual del modo (Mantener, Progresar, Descargar). | S | F2 | CAR-03 |
| RF-CAR-05 | Aviso opcional al alcanzar la carga objetivo (NOT-03). | C | F2 | — |
| RF-CAR-06 | Carga semanal, carga crónica y relación aguda/crónica (solo como indicador de cambios bruscos). | S | F2 | CAR-04 |
| RF-CAR-07 | FC máxima estimada por edad, sustituible por la máxima observada validada o por un valor manual. | M | F1 | CAR-06 |
| RF-CAR-08 | Mostrar pasos, distancia y calorías del día como contexto (tal como los proporciona Google). | S | F1 | — |
| RF-ENT-01 | Listar entrenamientos (automáticos o registrados en Google Health) con tipo, hora, duración, FC media/máx., calorías y distancia si existe. | S | F2 | — |
| RF-ENT-02 | Detalle del entrenamiento con curva de FC coloreada por zonas y carga de actividad. | S | F2 | CAR-02 |
| RF-ENT-03 | Preguntar el **esfuerzo percibido (RPE 0–10)** tras cada entrenamiento y guardar el sRPE. | S | F2 | CAR-05 |
| RF-ENT-04 | Crear una actividad manual (tipo, inicio, fin, RPE); su carga se calcula con la FC registrada en ese intervalo. | S | F2 | CAR-02 |
| RF-ENT-05 | **Registro de fuerza**: ejercicios, series, repeticiones y peso (volumen) + RPE; carga muscular estimada por sRPE, mostrada junto a la cardiovascular. | C | F3 | CAR-05 |
| RF-ENT-06 | Editar el tipo o el nombre de una actividad detectada. | C | F2 | — |
| RF-ENT-07 | **FC en vivo** durante un entrenamiento iniciado en la app, leyendo la emisión estándar de FC por Bluetooth de la Fitbit Air (CoreBluetooth; si el *spike* confirma que es viable, doc. 10 §9), con Live Activity en la pantalla de bloqueo y la Dynamic Island (RF-WID-03). | C | F3 | CAR-06 |

## 7. Estrés (EST)

| ID | Requisito | Prio. | Fase | Alg. |
|---|---|---|---|---|
| RF-EST-01 | Estimar el **estrés (0–3)** en ventanas de 5 min durante la vigilia a partir de la FC y la actividad. | S | F2 | EST-01 |
| RF-EST-02 | Línea temporal del día, nivel medio y tiempo en bajo (0–1), medio (1–2) y alto (2–3). | S | F2 | EST-01 |
| RF-EST-03 | Excluir del estrés los periodos de sueño, entrenamiento y movimiento (pasos). | S | F2 | EST-01 |
| RF-EST-04 | Aviso opcional de estrés alto sostenido (NOT-09) con acceso a respiración guiada. | C | F2 | — |
| RF-EST-05 | **Respiración guiada** en el móvil (respiración lenta ~6/min o suspiro cíclico) con temporizador y háptica del teléfono. | C | F3 | — |
| RF-EST-06 | Resumen de estrés al final del día (notificación opcional) con tiempo por nivel y comparación con la media. | C | F2 | EST-01 |

## 8. Monitor de salud (SAL)

| ID | Requisito | Prio. | Fase | Alg. |
|---|---|---|---|---|
| RF-SAL-01 | Mostrar los vitales nocturnos (HRV, FC en reposo, FR, SpO₂, temperatura cutánea) con su valor de hoy. | M | F1 | — |
| RF-SAL-02 | Mostrar el **rango habitual personal** de cada vital (banda) y marcar valores fuera de rango. | S | F2 | SAL-01 |
| RF-SAL-03 | Aviso combinado cuando ≥ 2 vitales están fuera de rango en la misma noche, con texto de bienestar (RL-02) y sin mencionar enfermedades. | S | F2 | SAL-01 |
| RF-SAL-04 | Historial de vitales (7/30/90/365 días). | S | F2 | — |
| RF-SAL-05 | VO₂ máx. y su tendencia: el de Google (solo se actualiza con carreras al aire libre con GPS del móvil) y, si no hay, una estimación propia sin ejercicio marcada como tal. | C | F2 | EDA-02 |
| RF-SAL-06 | **Informe de salud** en PDF (30 y 180 días) con vitales, rangos y tendencias, para compartir por decisión del usuario. | C | F3 | SAL-01 |

## 9. Diario de hábitos (DIA)

| ID | Requisito | Prio. | Fase | Alg. |
|---|---|---|---|---|
| RF-DIA-01 | Catálogo de ~30 preguntas de hábitos (alcohol, cafeína después de las 14:00, cena tardía, pantallas en la cama, estrés laboral, viaje, enfermedad, meditación, estiramientos, sauna, suplementos genéricos…); el usuario activa las que quiera y puede crear preguntas propias. | S | F2 | — |
| RF-DIA-02 | Responder en ≤ 30 s (sí/no, cantidad o escala 1–5) sobre el día anterior; se puede responder hasta 3 días después. | S | F2 | — |
| RF-DIA-03 | Autoevaluación diaria de recuperación/energía (1–5), usada también para validar las métricas (doc. 13). | S | F2 | — |
| RF-DIA-04 | Recordatorio opcional (NOT-08). | C | F2 | — |
| RF-DIA-05 | Notas libres por día (tratadas como datos no confiables para el Coach, RNF-SEG-09). | C | F2 | — |
| RF-DIA-06 | **Impacto de hábitos**: efecto estimado de cada hábito sobre la recuperación del día siguiente, con intervalo de confianza y nº de días; solo se muestra con ≥ 5 días «sí» y ≥ 5 días «no». | S | F3 | DIA-01 |

## 10. Tendencias e informes (TEN, INF)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-TEN-01 | Gráfico de cualquier métrica diaria con periodos 7 d / 30 d / 90 d / 6 meses / 1 año y media móvil. | S | F2 |
| RF-TEN-02 | Superponer dos métricas (p. ej. carga del día vs recuperación del día siguiente). | C | F2 |
| RF-TEN-03 | **Calendario** mensual con cada día coloreado por su zona de recuperación. | S | F2 |
| RF-TEN-04 | Rachas (días seguidos con datos completos o con el diario respondido). | C | F2 |
| RF-INF-01 | **Informe semanal** automático (lunes por la mañana): medias, récords, sueño vs necesidad, distribución de zonas de recuperación, carga total, comparación con la semana anterior, 3 recomendaciones. | S | F2 |
| RF-INF-02 | **Informe mensual** con las mismas secciones y tendencias de vitales. | C | F3 |
| RF-INF-03 | Compartir un informe o un día como imagen sin datos identificativos. | C | F3 |
| RF-INF-04 | **Resumen anual** (con ≥ 60 días de datos). | C | F3 |

## 10 bis. Plan semanal (PLA)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-PLA-01 | Plan de lunes a domingo con objetivos elegidos por el usuario (horas de sueño, carga, minutos en zonas, días de actividad, hábitos del diario, pasos, tiempo de fuerza) o con plantillas («Mejorar forma», «Sentirme mejor», «Dormir más profundo»). Disponible tras 7 noches con datos. | C | F3 |
| RF-PLA-02 | Barra de progreso semanal (todos los objetivos pesan igual) y tarjeta en «Hoy». | C | F3 |
| RF-PLA-03 | Revisión a mitad de semana (viernes) y resumen del lunes (integrado en el informe semanal). | C | F3 |

## 11. Edad fisiológica (EDA)

| ID | Requisito | Prio. | Fase | Alg. |
|---|---|---|---|---|
| RF-EDA-01 | Estimar semanalmente una **edad fisiológica** con medias de 6 meses de VO₂ máx., FC en reposo, pasos diarios, minutos semanales en zonas moderadas y altas, tiempo de fuerza, duración y regularidad del sueño, mostrando cuántos años suma o resta cada factor, y el **ritmo de envejecimiento** de los últimos 30 días. | C | F3 | EDA-01 |
| RF-EDA-02 | Disponible tras ≥ 21 días con datos válidos en 31; «calibrada» a los 90 días; siempre con aviso de incertidumbre e intervalo. Sin VO₂ máx. de Google se usa la estimación sin ejercicio (ALG-EDA-02) y se indica. | C | F3 | EDA-01, EDA-02 |

## 12. Notificaciones (NOT)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-NOT-01 | Implementar el catálogo del [doc. 11 §8](11-ux-y-pantallas.md#8-notificaciones-locales) con **notificaciones locales** (sin servidor), configurable una a una. Las que dependen de datos nuevos (p. ej. NOT-01) se lanzan al terminar una sincronización en segundo plano o al abrir la app. | M | F1 (NOT-01, 06, 07) / F2–F3 (resto) |
| RF-NOT-02 | Horas de silencio y límite de 3 notificaciones no críticas/día. | S | F2 |
| RF-NOT-03 | Sin cifras de salud en la pantalla de bloqueo salvo activación expresa. | M | F1 |

## 13. Perfil y ajustes (PER)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-PER-01 | Unidades (métrico/imperial), idioma (es/en), tema (oscuro/claro/sistema), formato horario. | M | F1 |
| RF-PER-05 | Bloqueo opcional de la app con Face ID / código y ocultación del contenido en el selector de apps. | S | F2 |
| RF-PER-02 | Zonas de FC y FC máx. manuales. | S | F2 |
| RF-PER-03 | Objetivos del usuario (horas de sueño, días de entrenamiento, objetivo principal) usados por el planificador y el Coach. | S | F2 |
| RF-PER-04 | Sección **«Cómo calculamos»**: explicación de cada métrica, referencias científicas y versión de los algoritmos en uso. | S | F1 |

## 14. Privacidad y datos del usuario (PRI)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-PRI-01 | Exportar todos los datos (brutos normalizados, puntuaciones, diario, ajustes, actividades manuales, conversaciones del Coach) en JSON + CSV con la hoja de compartir de iOS (Archivos, iCloud Drive, AirDrop), y copia de seguridad del diario y ajustes restaurable (RF-ONB-05). | M | F2 |
| RF-PRI-02 | **Borrar todos los datos** del iPhone y desconectar Google (revocando el *token*), con confirmación (RNF-PRI-04). | M | F1 |
| RF-PRI-03 | Ajustes de privacidad: activar/desactivar el Coach IA y el envío de datos al proveedor de IA, cifras en la pantalla de bloqueo y en *widgets*, y exclusión opcional de la BD de las copias de iCloud. | M | F1 |
| RF-PRI-04 | Registro local de eventos de privacidad (vinculaciones, exportaciones, borrados, activación del Coach). | C | F3 |

## 14 bis. *Widgets*, pantalla de bloqueo y Live Activities (WID)

| ID | Requisito | Prio. | Fase |
|---|---|---|---|
| RF-WID-01 | *Widgets* de pantalla de inicio: pequeño (tres anillos: Sueño, Recuperación, Carga) y mediano (anillos + recomendación del día); se actualizan tras cada sincronización. | S | F2 |
| RF-WID-02 | *Widgets* de **pantalla de bloqueo** (circular de recuperación, rectangular con los tres valores) y modo StandBy. | S | F2 |
| RF-WID-03 | **Live Activity** y Dynamic Island durante un entrenamiento iniciado en la app: tiempo, zona y FC en vivo (si RF-ENT-07 es viable) o carga acumulada. | C | F3 |
| RF-WID-04 | Los *widgets* respetan el ajuste de privacidad de la pantalla de bloqueo (RF-PRI-03). | M | F2 |

## 15. Fuera de alcance explícito (W)

| ID | Función de WHOOP | Motivo |
|---|---|---|
| RF-W-01 | ECG / *Heart Screener*, notificaciones de ritmo irregular | Producto sanitario; el hardware de Fitbit Air lo resuelve (si aplica) en la app oficial (RL-03) |
| RF-W-02 | *Blood Pressure Insights* | Sin sensor ni base validada; producto sanitario |
| RF-W-03 | *Advanced Labs* (analíticas de sangre) | Fuera del ámbito de la pulsera |
| RF-W-04 | Alarma háptica en la muñeca | Sin API para controlar la vibración de la pulsera |
| RF-W-05 | Comunidad, equipos y clasificaciones | App de uso personal |
| RF-W-06 | Seguimiento del ciclo menstrual y embarazo (y su efecto en recuperación y objetivos) | La Google Health API solo permite **escribir** datos menstruales, no leerlos; se podría añadir un registro propio en la app si se desea |
| RF-W-07 | Integraciones directas con Strava, Peloton, TrainingPeaks, etc. | Google Health ya agrega datos de otras apps |
| RF-W-08 | Publicación en la App Store, cuentas de usuario y servidor | App de uso personal (doc. 08 §7) |

---

## 16. Criterios de aceptación de los requisitos críticos

**RF-CON-01 · Vinculación**

```gherkin
Dado que abro la app por primera vez y no he conectado Google Health
Cuando pulso «Conectar Google Health», leo la divulgación, inicio sesión y acepto los permisos
Entonces vuelvo a la app en menos de 5 s tras aceptar
Y veo «Conectado a Google Health» con la última sincronización y los ámbitos concedidos
Y comienza la importación del historial con barra de progreso
Y los tokens solo existen en el Llavero del iPhone (nunca en la BD ni en logs)
```

```gherkin
Dado un usuario que deniega algún ámbito opcional
Cuando termina el flujo de consentimiento
Entonces la vinculación se completa
Y las funciones que dependen de ese ámbito aparecen como «desactivadas: falta permiso» con opción de concederlo
```

**RF-SYN-02 · Ingesta incremental**

```gherkin
Dado que estoy conectado y tengo datos hasta ayer
Cuando la pulsera ya ha sincronizado la noche con Google Health y abro la app
Entonces en ≤ 3 s veo el sueño, los vitales y la recuperación de hoy
Y si repito la sincronización no se crean datos duplicados
```

**RF-REC-01 / RF-REC-03 · Recuperación y calibración**

```gherkin
Dado un usuario con 3 noches válidas desde que empezó a usar la app
Cuando se sincroniza su cuarta noche válida con HRV
Entonces se muestra por primera vez su recuperación con confianza «media»
Y el detalle indica «Línea base en construcción: 4/14 noches»
```

```gherkin
Dado un usuario calibrado cuya noche no tiene HRV
Cuando se sincroniza el sueño
Entonces no se muestra recuperación
Y se muestra «Datos insuficientes: no hay variabilidad cardiaca de esta noche»
```

**RF-CAR-01 · Carga del ciclo**

```gherkin
Dado un ciclo iniciado al despertar a las 07:00
Cuando se sincronizan datos de FC hasta las 13:00 que incluyen una carrera de 45 min
Entonces la carga del ciclo se actualiza, es ≤ 21 y es mayor que antes de la carrera
Y la carrera aparece como actividad con su propia carga
```

**RF-SUE-08 · Planificador**

```gherkin
Dado un usuario con necesidad de sueño esta noche de 8 h 20 min, eficiencia habitual del 90 %
Y modo «Alcanzar mi necesidad», hora de despertar deseada 07:00 y objetivo «Máximo (100 %)»
Cuando abre el planificador
Entonces la hora recomendada para acostarse es 07:00 − (8 h 20 min / 0,90) − latencia habitual (redondeada a 5 min)
Y puede cambiar el objetivo a 85 % o 70 % y la hora se recalcula al instante
```

**RF-PRI-02 · Borrar todos los datos**

```gherkin
Dado que tengo datos importados, diario y conversaciones del Coach en el iPhone
Cuando elijo «Borrar todos los datos» y confirmo con Face ID
Entonces el token de Google se revoca y se elimina del Llavero
Y la base de datos local, la instantánea de los widgets y las conversaciones se eliminan
Y la app vuelve a la pantalla de bienvenida
```

**RF-DIA-06 · Impacto de hábitos**

```gherkin
Dado un usuario con 8 días «alcohol: sí» y 20 días «alcohol: no» con recuperación calculada al día siguiente
Cuando abre «Impacto de hábitos»
Entonces ve el efecto estimado (p. ej. «−9 puntos de recuperación, IC 95 % −15 a −3, 28 días»)
Y los hábitos con menos de 5 días en alguno de los grupos aparecen como «Necesitamos más datos»
```
