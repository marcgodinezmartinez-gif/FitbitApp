# Glosario

| Término | Definición |
|---|---|
| **ACWR** | *Acute:Chronic Workload Ratio*. Cociente entre la carga reciente (≈7 días) y la carga crónica (≈28 días). Útil como indicador de cambios bruscos de carga; su valor predictivo de lesiones es discutido. |
| **AlarmKit** | Marco de iOS 26 que permite a una app programar alarmas que suenan aunque el iPhone esté en silencio. |
| **AZM** | *Active Zone Minutes* (Minutos en Zona Activa) de Google/Fitbit: minutos en zonas de FC moderada o alta, con doble valor en zonas altas. |
| **Backfill** | Importación inicial del historial de datos al conectar Google Health. |
| **Calibración** | Periodo inicial (≥ 4 noches válidas) antes de mostrar la recuperación; la línea base se considera estable a partir de 14 noches. Calendario completo en el doc. 05 §11. |
| **Carga (Strain)** | Nuestra medida del estrés cardiovascular acumulado en un ciclo o actividad, en escala 0–21. Equivalente funcional del *Strain* de WHOOP. |
| **CASA** | *Cloud Application Security Assessment*: evaluación de seguridad que Google exige a apps que usan ámbitos OAuth restringidos. |
| **Ciclo fisiológico** | Periodo entre dos despertares del sueño principal. Unidad temporal de la app (doc. 08 §4.3). |
| **Confianza** | Indicador alta/media/baja de la calidad de datos detrás de una puntuación (RNF-CAL-01). |
| **Deuda de sueño** | Acumulado ponderado de la diferencia entre necesidad de sueño y sueño real de las noches recientes. |
| **DPA** | *Data Processing Agreement*: contrato de encargado del tratamiento (art. 28 RGPD). |
| **Eficiencia del sueño** | Tiempo dormido / tiempo en cama × 100. |
| **EIPD / DPIA** | Evaluación de impacto relativa a la protección de datos (art. 35 RGPD). |
| **Estrés (0–3)** | Nuestra estimación de la activación fisiológica diurna no explicada por actividad física, a partir de la FC. |
| **FC / HR** | Frecuencia cardiaca, en latidos por minuto (lpm). |
| **FC máx. / HRmax** | Frecuencia cardiaca máxima (estimada por edad o medida). |
| **FCR / RHR** | Frecuencia cardiaca en reposo. |
| **FCRes / HRR** | Frecuencia cardiaca de reserva: FC máx. − FC en reposo (método de Karvonen). |
| **FR / RR** | Frecuencia respiratoria nocturna, en respiraciones por minuto (rpm). |
| **Google Health (app)** | App oficial de Google con la que se empareja y sincroniza la Fitbit Air. |
| **Google Health API** | API REST de Google para que apps de terceros lean (y en algunos casos escriban) datos de salud y actividad de los usuarios; sustituye a la Fitbit Web API. |
| **Health Connect** | Almacén de datos de salud en el propio dispositivo Android, compartido entre apps con permiso del usuario. |
| **HealthKit** | Equivalente de Apple en iOS. |
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
| **SideStore** | Herramienta para instalar y re-firmar apps propias en el iPhone con un Apple ID gratuito, sin Mac. |
| **SpO₂** | Saturación periférica de oxígeno. |
| **SRI** | *Sleep Regularity Index*: probabilidad de estar en el mismo estado (dormido/despierto) en dos instantes separados 24 h (0–100). |
| **Sueño reparador** | Tiempo en sueño profundo + REM. |
| **Suficiencia de sueño** | Sueño real / necesidad de sueño × 100 (máx. 100 %). |
| **Tarea en segundo plano** | `BGAppRefreshTask` / `BGProcessingTask`: trabajo que iOS ejecuta con la app cerrada cuando lo considera oportuno. |
| **Temperatura cutánea (desviación)** | Diferencia de la temperatura de la piel durante el sueño respecto a la línea base personal. |
| **TRIMP** | *Training Impulse*: carga de entrenamiento basada en duración × intensidad de FC (Banister, Edwards…). |
| **Vitales nocturnos** | HRV, FC en reposo, FR, SpO₂ y temperatura cutánea medidos durante el sueño. |
| **VO₂ máx.** | Consumo máximo de oxígeno estimado (en Google Health se actualiza con carreras al aire libre con GPS). |
| **Webhook** | Aviso HTTP que la Google Health API puede enviar a un servidor cuando hay datos nuevos; no se usa en la versión personal (sin servidor). |
| **Widget** | Vista resumida de la app en la pantalla de inicio, de bloqueo o en StandBy. |
| **z-score** | (valor − media) / desviación típica: número de desviaciones respecto a la línea base. |
| **Zona (verde/amarilla/roja)** | Rango de recuperación: 67–100 % alta, 34–66 % media, 0–33 % baja. |
