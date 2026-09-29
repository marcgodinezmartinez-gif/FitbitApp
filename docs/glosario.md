# Glosario

| Término | Definición |
|---|---|
| **ACWR** | *Acute:Chronic Workload Ratio*. Cociente entre la carga reciente (≈7 días) y la carga crónica (≈28 días). Útil como indicador de cambios bruscos de carga; su valor predictivo de lesiones es discutido. |
| **AlarmKit** | Marco de iOS 26 que permite a una app programar alarmas que suenan aunque el iPhone esté en silencio. |
| **Análisis del día** | Resumen de tu ciclo en 3–5 claves con recomendaciones para esta noche y mañana, a petición («Analizar mi día»); sin IA o redactado por el Coach (RF-ANA, ALG-ANA-01). |
| **Ancla (HealthKit)** | Marca que guarda hasta dónde se ha leído cada tipo de dato de Salud, para pedir después solo lo nuevo y lo borrado (`HKAnchoredObjectQuery`). |
| **API de Gemini** | API de Google para usar los modelos Gemini (alternativa a la de Claude para el Coach). Para datos de salud, solo con el nivel de pago. |
| **App Store Connect** | Portal web de Apple para gestionar la app, sus *builds* de TestFlight y las claves de API que usa el CI. |
| **Apple Health (Salud)** | App de salud de Apple en el iPhone, donde el Apple Watch guarda sus datos; las apps la leen con HealthKit. |
| **AZM** | *Active Zone Minutes* (Minutos en Zona Activa) de Google/Fitbit: minutos en zonas de FC moderada o alta, con doble valor en zonas altas. |
| **Backfill** | Importación inicial del historial de datos al conectar Google Health. |
| **Calibración** | Periodo inicial (≥ 4 noches válidas) antes de mostrar la recuperación; la línea base se considera estable a partir de 14 noches. Calendario completo en el doc. 05 §11. |
| **Carga (Strain)** | Nuestra medida del estrés cardiovascular acumulado en un ciclo o actividad, en escala 0–21. Equivalente funcional del *Strain* de WHOOP. |
| **CASA** | *Cloud Application Security Assessment*: evaluación de seguridad que Google exige a apps que usan ámbitos OAuth restringidos. |
| **Ciclo fisiológico** | Periodo entre dos despertares del sueño principal. Unidad temporal de la app (doc. 08 §4.3). |
| **Concordancia (Bland-Altman)** | Forma de comparar dos medidores de lo mismo: diferencia media entre ellos (sesgo) y rango en el que caen el 95 % de las diferencias. La app la usa para comparar el pulso del Apple Watch y el de la Fitbit Air. |
| **Confianza** | Indicador alta/media/baja de la calidad de datos detrás de una puntuación (RNF-CAL-01). |
| **Deuda de sueño** | Acumulado ponderado de la diferencia entre necesidad de sueño y sueño real de las noches recientes. |
| **Dinámica de carrera** | Métricas del Apple Watch al correr: potencia, velocidad, longitud de zancada, oscilación vertical y tiempo de contacto con el suelo. |
| **DPA** | *Data Processing Agreement*: contrato de encargado del tratamiento (art. 28 RGPD). |
| **Eficiencia del sueño** | Tiempo dormido / tiempo en cama × 100. |
| **EIPD / DPIA** | Evaluación de impacto relativa a la protección de datos (art. 35 RGPD). |
| **Entrega en segundo plano (HealthKit)** | Aviso con el que iOS despierta la app cuando se guarda un dato nuevo en Salud (p. ej. una carrera del Watch); requiere un permiso especial de la app. |
| **Estrés (0–3)** | Nuestra estimación de la activación fisiológica diurna no explicada por actividad física, a partir de la FC. |
| **Familia de fuentes** | Filtro de la Google Health API por origen de los datos: `all-sources`, `google-sources` o `google-wearables` (solo pulseras y relojes de Google y Fitbit, la que usa la app). |
| **FC / HR** | Frecuencia cardiaca, en latidos por minuto (lpm). |
| **FC de recuperación** | Cuánto baja la FC en el minuto siguiente a terminar un entrenamiento; la mide el Apple Watch. |
| **FC máx. / HRmax** | Frecuencia cardiaca máxima (estimada por edad o medida). |
| **FCR / RHR** | Frecuencia cardiaca en reposo. |
| **FCRes / HRR** | Frecuencia cardiaca de reserva: FC máx. − FC en reposo (método de Karvonen). |
| **FR / RR** | Frecuencia respiratoria nocturna, en respiraciones por minuto (rpm). |
| **Fusión de fuentes** | Reglas que combinan los datos de la Fitbit Air y del Apple Watch sin contar nada dos veces (ALG-FUS, doc. 16). |
| **GitHub Actions** | Servicio de integración continua de GitHub; aquí compila la app en máquinas macOS en la nube (sin Mac propio) y la sube a TestFlight. |
| **Google Health (app)** | App oficial de Google con la que se empareja y sincroniza la Fitbit Air. |
| **Google Health API** | API REST de Google para que apps de terceros lean (y en algunos casos escriban) datos de salud y actividad de los usuarios; sustituye a la Fitbit Web API. |
| **Health Connect** | Almacén de datos de salud en el propio dispositivo Android, compartido entre apps con permiso del usuario. |
| **HealthKit** | Marco de iOS con el que las apps leen (y, si se les permite, escriben) datos de Salud; esta app solo lee. |
| **healthUserId** | Identificador del usuario en la Google Health API. |
| **HRV / VFC** | Variabilidad de la frecuencia cardiaca. En esta app, **RMSSD** nocturno. |
| **Limited Use** | Requisitos de «Uso Limitado» de la política de datos de usuario de las APIs de Google. |
| **Línea base** | Media y dispersión personales de una métrica en una ventana móvil (p. ej. 30 o 60 noches). |
| **Liquid Glass** | Lenguaje visual de iOS 26 con materiales translúcidos en barras, controles y hojas. |
| **Live Activity** | Actividad en curso visible en la pantalla de bloqueo y en la Dynamic Island (p. ej. un entrenamiento). |
| **Llavero (Keychain)** | Almacén cifrado de iOS para secretos (tokens de Google, clave de la API de IA). |
| **lnRMSSD** | Logaritmo natural del RMSSD; se usa porque su distribución es más simétrica y estable. |
| **Local-first** | Arquitectura en la que los datos y los cálculos viven en el dispositivo, sin servidor propio. |
| **MDR** | Reglamento (UE) 2017/745 sobre productos sanitarios. |
| **Necesidad de sueño** | Horas de sueño recomendadas para una noche concreta: base personal + ajuste por carga + ajuste por deuda − siestas. |
| **PKCE** | *Proof Key for Code Exchange*: extensión de OAuth 2.0 que protege el intercambio del código de autorización. |
| **PPG** | Fotopletismografía: técnica óptica con la que la pulsera mide el pulso. |
| **Recuperación** | Nuestra puntuación diaria 0–100 % de preparación fisiológica basada en HRV, FC en reposo, sueño y otras señales nocturnas respecto a la línea base personal. |
| **Rendimiento de sueño** | Puntuación del dial de sueño (0–100 %): combinación de suficiencia, eficiencia y constancia (ALG-SUE-07). |
| **Ritmo de envejecimiento** | Velocidad a la que cambia la edad fisiológica respecto al calendario (1,0 = normal; negativo = disminuye). |
| **RMSSD** | Raíz cuadrática media de las diferencias sucesivas entre intervalos RR; refleja la actividad parasimpática. |
| **RPE / sRPE** | Esfuerzo percibido (escala CR-10) y su producto por la duración de la sesión (método de Foster). |
| **SDNN** | Desviación típica de los intervalos entre latidos; es la VFC que guarda Salud, no comparable con el RMSSD de la Fitbit Air. |
| **SpO₂** | Saturación periférica de oxígeno. |
| **SRI** | *Sleep Regularity Index*: probabilidad de estar en el mismo estado (dormido/despierto) en dos instantes separados 24 h (0–100). |
| **Sueño reparador** | Tiempo en sueño profundo + REM. |
| **Suficiencia de sueño** | Sueño real / necesidad de sueño × 100 (máx. 100 %). |
| **Tarea en segundo plano** | `BGAppRefreshTask` / `BGProcessingTask`: trabajo que iOS ejecuta con la app cerrada cuando lo considera oportuno. |
| **Temperatura cutánea (desviación)** | Diferencia de la temperatura de la piel durante el sueño respecto a la línea base personal. |
| **Test de instantánea (*snapshot*)** | Test que genera una captura de una pantalla y la compara con la aprobada; sin Mac, es la forma de ver el diseño desde el PR. |
| **TestFlight** | Servicio de Apple para instalar *builds* de prueba en el iPhone; cada *build* dura 90 días. |
| **TRIMP** | *Training Impulse*: carga de entrenamiento basada en duración × intensidad de FC (Banister, Edwards…). |
| **Vitales nocturnos** | HRV, FC en reposo, FR, SpO₂ y temperatura cutánea medidos durante el sueño. |
| **VO₂ máx.** | Consumo máximo de oxígeno estimado (en Google Health se actualiza con carreras al aire libre con GPS). |
| **Webhook** | Aviso HTTP que la Google Health API puede enviar a un servidor cuando hay datos nuevos; no se usa en la versión personal (sin servidor). |
| **Widget** | Vista resumida de la app en la pantalla de inicio, de bloqueo o en StandBy. |
| **XcodeGen** | Herramienta que genera el proyecto de Xcode a partir de un fichero `project.yml` legible. |
| **z-score** | (valor − media) / desviación típica: número de desviaciones respecto a la línea base. |
| **Zona (verde/amarilla/roja)** | Rango de recuperación: 67–100 % alta, 34–66 % media, 0–33 % baja. |
