# 12 · Privacidad, seguridad y marco legal

> **Aviso**: este documento recoge requisitos derivados de la normativa aplicable según el análisis del equipo; **no es asesoramiento jurídico**. Antes de publicar la app para terceros (fase F4) debe revisarlo un profesional (protección de datos y producto sanitario).

Convención de IDs: `RL-<nn>`. Columna **Cuándo**: `F1` = obligatorio ya en uso personal; `F4` = obligatorio antes de abrir la app a otras personas o publicarla en tiendas.

---

## 1. Dos escenarios con obligaciones muy distintas

| Escenario | Descripción | Consecuencia principal |
|---|---|---|
| **A. Uso personal** (MVP) | Solo el propietario usa la app con sus propios datos. | El RGPD no se aplica a tratamientos «efectuados por una persona física en el ejercicio de actividades exclusivamente personales o domésticas» (art. 2.2.c RGPD). Siguen aplicando las condiciones de Google (API y OAuth) —incluso sin verificar, la app puede tener hasta 100 usuarios— y de los proveedores (Anthropic, cloud). |
| **B. Producto para terceros** | Otras personas crean cuenta y vinculan su Fitbit Air. | El desarrollador pasa a ser **responsable del tratamiento** de datos de salud (categoría especial, art. 9 RGPD) con todas las obligaciones de §3, más políticas de tiendas y verificación de Google. |

La arquitectura se diseña desde el principio para el escenario B (privacidad desde el diseño, art. 25 RGPD), aunque el lanzamiento sea A.

## 2. Posicionamiento regulatorio: bienestar, no producto sanitario

El Reglamento (UE) 2017/745 (MDR) considera producto sanitario el software destinado por su fabricante a diagnóstico, prevención, seguimiento, predicción, pronóstico o tratamiento de enfermedades. La regla 11 del anexo VIII clasifica como **clase IIa** (o superior) el software destinado a monitorizar procesos fisiológicos con esa finalidad, lo que exigiría marcado CE con organismo notificado. La finalidad prevista se deduce de **todo lo que el fabricante dice** (textos de la app, tiendas, web, publicidad).

| ID | Requisito | Cuándo |
|---|---|---|
| RL-01 | Finalidad prevista declarada: **bienestar general, hábitos de sueño y rendimiento deportivo**. Ningún texto, notificación o respuesta del Coach afirma diagnosticar, detectar, prevenir o tratar enfermedades. | F1 |
| RL-02 | Lista de **expresiones prohibidas** en la UI y el marketing (p. ej. «detecta enfermedades», «alerta de COVID/infección», «diagnóstico», «arritmia», «apnea», «fibrilación auricular», «presión arterial») y lista de alternativas permitidas («tus métricas nocturnas están fuera de tu rango habitual», «considera descansar», «si te encuentras mal, consulta a un profesional sanitario»). Revisión obligatoria de textos antes de cada *release*. | F1 |
| RL-03 | No se replican funciones clínicas de Google o WHOOP que sí son producto sanitario (ECG, notificaciones de ritmo irregular/FA, estimación de presión arterial). Si el usuario las tiene en la app Google Health, nuestra app **no** las reinterpreta. | F1 |
| RL-04 | Descargo visible en el onboarding, en «Acerca de» y en cada pantalla de métricas de salud: «No es un producto sanitario. No sustituye el consejo médico.» | F1 |
| RL-05 | Antes de F4: análisis documentado de calificación del software según la guía MDCG 2019-11 (rev. vigente) firmado por quien corresponda. | F4 |

## 3. Protección de datos (RGPD + LOPDGDD) — escenario B

| ID | Requisito | Base | Cuándo |
|---|---|---|---|
| RL-10 | **Consentimiento explícito** y separado para tratar datos de salud (art. 9.2.a RGPD), granular por finalidad: (1) cálculo de métricas, (2) Coach IA con envío a proveedor de IA, (3) analítica de producto opcional. Revocable en cualquier momento con el mismo esfuerzo que se otorgó. | Art. 7 y 9 RGPD | F4 |
| RL-11 | Registro versionado de consentimientos (qué versión del texto, cuándo, cómo, revocaciones). | Art. 7.1 RGPD | F4 (diseño en F1) |
| RL-12 | Política de privacidad clara en español e inglés (arts. 13–14): responsable, finalidades, bases jurídicas, destinatarios (Google, cloud, proveedor de IA), transferencias internacionales, plazos de conservación, derechos, reclamación ante la **AEPD**. Enlazada desde la app, las tiendas y la pantalla de consentimiento OAuth de Google. | Arts. 12–14 RGPD | F1 (Google la exige para configurar OAuth) |
| RL-13 | Derechos del interesado desde la propia app: acceso y **portabilidad** (exportación JSON/CSV, RNF-PRI-05), rectificación (perfil), **supresión** (borrado de cuenta, RNF-PRI-04), oposición/limitación (desactivar funciones). Respuesta ≤ 1 mes. | Arts. 15–21 RGPD | F4 (funcionalidad en F1–F2) |
| RL-14 | **Evaluación de impacto (EIPD/DPIA)** antes del lanzamiento: se tratan categorías especiales, se evalúa/perfila a personas y se usa IA; encaja en la lista de tratamientos que requieren EIPD publicada por la AEPD. | Art. 35 RGPD | F4 |
| RL-15 | **Registro de actividades de tratamiento** (RAT). | Art. 30 RGPD | F4 |
| RL-16 | **Contratos de encargado** (DPA, art. 28) con cada proveedor que trate datos: hosting/BD, proveedor de IA, notificaciones *push*, *crash reporting*, email. | Art. 28 RGPD | F4 |
| RL-17 | **Transferencias internacionales** documentadas: datos alojados en la UE (RNF-PRI-07); para proveedores fuera del EEE, comprobar certificación en el EU-US Data Privacy Framework o firmar cláusulas contractuales tipo + evaluación de impacto de la transferencia. Preferir opciones con procesamiento en la UE cuando existan (ver doc. 06). | Cap. V RGPD | F4 |
| RL-18 | Procedimiento de **brechas de seguridad**: notificación a la AEPD en ≤ 72 h y a los afectados cuando haya alto riesgo; registro interno de incidentes. | Arts. 33–34 RGPD | F4 |
| RL-19 | **Edad mínima**: 18 años (recomendado; en ningún caso < 14, art. 7 LOPDGDD). Verificación declarativa en el registro. | LOPDGDD | F4 |
| RL-20 | Las decisiones automatizadas (puntuaciones, recomendaciones) **no producen efectos jurídicos** ni afectan significativamente al usuario; se explica su lógica en la app («¿Cómo se calcula?»). | Art. 22 RGPD, transparencia | F2 |
| RL-21 | Web pública con aviso legal y política de cookies (solo cookies técnicas salvo consentimiento). | LSSI-CE (Ley 34/2002) | F4 |

## 4. Inteligencia artificial (Coach IA)

| ID | Requisito | Base | Cuándo |
|---|---|---|---|
| RL-30 | Informar de forma clara de que se está **interactuando con un sistema de IA** (etiqueta permanente en el chat y en los textos generados, p. ej. informes). | Art. 50 del Reglamento (UE) 2024/1689 (Ley de IA), aplicable desde el 2 de agosto de 2026; el paquete «Digital Omnibus» (en vigor desde el 27/07/2026) aplazó las obligaciones de alto riesgo, **no** las de transparencia del art. 50 | F3 |
| RL-31 | El Coach **no** se usa para fines que harían el sistema de alto riesgo (p. ej. componente de seguridad de un producto sanitario, decisiones sobre acceso a seguros/empleo). | Ley de IA, art. 6 y anexo III | F3 |
| RL-32 | Consentimiento específico antes de enviar datos al proveedor de IA, identificando al proveedor. Apple exige además revelar y obtener permiso explícito **antes** de compartir datos personales con IA de terceros ([App Review Guideline 5.1.2(i)](https://developer.apple.com/news/?id=ey6d8onl), actualización del 13/11/2025). | RGPD art. 9; App Store | F3 (uso personal: aviso), F4 (terceros) |
| RL-33 | Configurar el proveedor de IA para que **no entrene** con los datos y con la retención mínima disponible (valorar retención cero si se contrata). Documentar la región de procesamiento. | RGPD arts. 5, 28 | F3 |
| RL-34 | Salvaguardas de contenido: el Coach no diagnostica, no prescribe medicación ni dietas extremas, detecta señales de urgencia y deriva (112 en España) — ver doc. 06. | Prudencia / RL-01 | F3 |

## 5. Condiciones de Google (Google Health API, OAuth y marcas)

Detalle técnico y lista de comprobación en [doc. 10 §7](10-integracion-google-health-api.md#7-cumplimiento-de-políticas-lista-de-comprobación). Fuentes: [Términos para desarrolladores de la Google Health API](https://developers.google.com/health/policies/health-api-developer-terms-and-conditions), [Política de datos de usuario de la Google Health API](https://developers.google.com/health/policies/health-api-developer-user-data-policy), [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), [verificación](https://developers.google.com/health/app-verification), [marca](https://developers.google.com/health/promote).

| ID | Requisito | Cuándo |
|---|---|---|
| RL-40 | **Uso Limitado** (*Limited Use*), también para datos derivados y anonimizados: solo funciones de salud y bienestar visibles para el usuario; prohibido vender o transferir datos a plataformas publicitarias o *data brokers*, usarlos para publicidad, para decisiones de crédito o préstamo, para funciones reguladas como producto sanitario, para usos críticos para la vida o para investigación fuera de la política de investigación de Google; ninguna persona los lee salvo consentimiento, seguridad u obligación legal. | F1 |
| RL-41 | Pantalla de consentimiento OAuth con nombre, logotipo, email de soporte, dominio verificado, página de inicio y política de privacidad **en el mismo dominio**, y condiciones de servicio. | F1 |
| RL-42 | Declaración **literal** en la web o en la política de privacidad: *«The use of information received from Google Health API and/or Developer Tools will adhere to the Google Health API Developer and User Data Policy, including the Limited Use requirements.»* | F1 |
| RL-43 | **Divulgación destacada en la app** justo antes de pedir el consentimiento de Google, indicando qué datos se recogen y para qué funciones (texto en doc. 10 §4). | F1 |
| RL-44 | Guardar los datos con la **misma granularidad** con la que se obtienen (doc. 10 §5.4) y cifrar datos y *tokens* en reposo con claves gestionadas en KMS/HSM. | F1 |
| RL-45 | Todos los ámbitos de la Google Health API son **restringidos**: sin verificación, máximo 100 usuarios; para superar ese límite, verificación de marca y de ámbitos (vídeo de demostración, justificación por ámbito) y **evaluación CASA anual** por un laboratorio externo (500–4 500 $). | F4 |
| RL-46 | Marca: «Google Health» sin traducir; sin logotipos antiguos de Fitbit/Google Fit; estado «Conectado a Google Health» con la última sincronización y «Desconectar» a 1–2 toques; referencias a «Google Fitbit Air» solo de forma nominativa («Compatible con…»), sin sugerir patrocinio. | F1 |
| RL-47 | Al desvincular o borrar la cuenta: revocar el *token*, borrar los *tokens* revocados y preguntar si se conservan o eliminan los datos ya importados; documentación de ayuda sobre cómo borrar los datos. | F1 |
| RL-48 | Envío de datos al proveedor de IA del Coach solo como parte de una función visible para el usuario, con consentimiento y sin entrenamiento de modelos con esos datos; la política no regula expresamente el entrenamiento de IA ⇒ **revisión jurídica antes de F4**. | F3/F4 |

## 6. Tiendas de aplicaciones

| ID | Requisito | Cuándo |
|---|---|---|
| RL-50 | **App Store**: guía 5.1.1 (recogida y almacenamiento, borrado de cuenta desde la app), 5.1.2 (uso y compartición, incluida IA de terceros), 5.1.3 (datos de salud: prohibido usarlos para publicidad o minería de datos; no guardar información sanitaria personal en iCloud), 1.4.1 (apps de salud: no afirmar mediciones que el dispositivo no hace y explicar la metodología). Etiquetas de privacidad (*nutrition labels*) completas. | F4 |
| RL-51 | **Google Play**: política de apps de salud y formulario de **declaración de apps de salud** en Play Console, sección de **Seguridad de los datos**, borrado de cuenta desde la app y desde una URL web, y (si se usa Health Connect) declaración y justificación de cada permiso de Health Connect. La publicación en Google Play **no** sustituye a la verificación de la Google Health API (RL-45). | F4 |
| RL-52 | Cuentas de desarrollador a nombre del responsable legal (persona física o sociedad), coherentes con el responsable del tratamiento de la política de privacidad. | F4 |

## 7. Propiedad intelectual y marcas

| ID | Requisito | Cuándo |
|---|---|---|
| RL-60 | El nombre comercial, el icono y los textos **no** usan «WHOOP», «Fitbit» ni «Google» ni nombres distintivos de funciones de WHOOP (p. ej. *Strain Coach*, *WHOOP Age*, *Healthspan*). Se usan nombres propios (Recuperación, Carga, Sueño, Estrés, Edad fisiológica). | F1 |
| RL-61 | Diseño visual propio: se toma la **idea funcional** (diales diarios, zonas por colores), no la imagen de marca, tipografías, iconografía ni capturas de WHOOP. | F1 |
| RL-62 | Los algoritmos se implementan a partir de **literatura científica pública** (doc. 05 y referencias), no de ingeniería inversa de software o firmware de terceros. No se accede al dispositivo por Bluetooth con protocolos propietarios. | F1 |
| RL-63 | Licencias de terceros compatibles y listadas (fichero de avisos/NOTICE en la app). | F2 |

## 8. Consumo y comunicación comercial (escenario B)

| ID | Requisito | Cuándo |
|---|---|---|
| RL-70 | Condiciones de servicio con limitación de uso a bienestar, requisitos de edad, política de suscripción/cancelación (si la hay) y derecho de desistimiento según la normativa de consumo. | F4 |
| RL-71 | Afirmaciones comerciales veraces y demostrables: no «tan preciso como…», no promesas de resultados de salud. | F4 |
| RL-72 | Valorar la aplicabilidad de la Ley Europea de Accesibilidad (Directiva (UE) 2019/882) si se venden servicios digitales en la app; en todo caso se cumple WCAG 2.2 AA (RNF-ACC-01). | F4 |
