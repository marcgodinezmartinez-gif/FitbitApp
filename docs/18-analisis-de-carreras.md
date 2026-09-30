# 18 · Análisis de carreras

La pestaña **Correr** reúne todas tus carreras y abre cada una con **todo lo que registran el Apple Watch y la Fitbit Air**. El cálculo vive en el módulo `RunKit` del paquete, sin interfaz y con pruebas en Linux. La importación ampliada está en `SyncKit` y en `HealthKitProvider`, y las pantallas en `App/Features/Runs`.

## 0. En resumen

- **Cada carrera, segundo a segundo.** Se reconstruye uniendo las dos fuentes:
  - distancia del GPS del Watch, de sus muestras (en cinta) o de los parciales de la Fitbit;
  - FC del Watch, con la de la Fitbit donde falte;
  - altitud y pendiente, cadencia, potencia y dinámica de carrera.
- **El análisis de cada carrera** incluye:
  - parciales y vueltas;
  - ritmo ajustado por pendiente;
  - zonas de FC, ritmo y potencia;
  - mejores marcas y récords;
  - curvas de ritmo y potencia y subidas;
  - carga (TRIMP y rTSS) y VO₂ máx. estimado;
  - eficiencia, desacoplamiento aeróbico y deriva de FC;
  - técnica con valoración;
  - Apple Watch frente a Fitbit;
  - tiempo y carreras parecidas;
  - series detectadas aunque no marcaras vueltas;
  - tus segmentos, con tu posición en cada uno;
  - RPE, zapatillas y exportación GPX.
- **La pestaña Correr** muestra:
  - tu plan de entrenamiento y la carrera objetivo con su predicción ajustada al desnivel y al calor;
  - volumen por semanas, meses y años, y racha;
  - forma, fatiga y frescura, y el riesgo de lesión;
  - VDOT, predicciones y ritmos de entrenamiento;
  - VO₂ máx. de las tres fuentes;
  - récords, segmentos y tendencias (6 meses, un año o todo);
  - tus zonas y tus zapatillas.
- **Entrenos en el Apple Watch.** Cada sesión del plan (o un entreno suelto) se manda al reloj con WorkoutKit, con sus pasos y avisos de ritmo.
- **Historial completo.** Además de los 6 meses de la primera importación, se traen todas tus carreras antiguas de las dos fuentes (§1).
- **Análisis del entrenador con IA.** Es opcional, se hace con tu clave y nunca recibe coordenadas.
- **Rendimiento.** El análisis de cada carrera se guarda en caché (`run_summary`), así que la pestaña abre al instante. Solo se recalcula si cambia la carrera (por ejemplo, si llega su parte de la Fitbit) o la versión del análisis.

## 1. Datos de cada dispositivo

| Dato | Apple Watch (Salud) | Fitbit Air (Google Health API) |
|---|---|---|
| Ruta GPS con altitud | Sí | No (la pulsera no tiene GPS) |
| Distancia | Ruta o muestras por tramos (cinta) | Parciales por km y total |
| FC | Muestras cada ~5 s | Muestras cada 1–5 s |
| Velocidad y potencia | Series | — |
| Zancada, oscilación vertical, contacto con el suelo | Series | Medias de la carrera y de cada parcial |
| Cadencia | Serie (pasos por tramo) | Media y por parcial |
| Pausas | Manuales y automáticas | Manuales y automáticas |
| Vueltas, segmentos, intervalos | Vueltas, segmentos y actividades del entreno | Vueltas (`splitSummaries`) |
| Tiempo, humedad, estado del cielo | Sí | — |
| Desnivel positivo y negativo | Sí | Positivo |
| Otros | FC de recuperación a 1 min, esfuerzo (1–10), METs | Tiempo en zonas de Fitbit, minutos en zona activa, VO₂ máx. de la carrera |

**Importación:**

- **Watch.** La primera vez que se abre esta versión, los entrenos ya importados se releen una vez para completar estos datos (`apple_detail_version`).
- **Fitbit.** Se descarga la FC segundo a segundo de todas las carreras que aún no la tienen, con un tope de 60 por sincronización.
- **Historial completo.** Después de la primera importación, `SyncEngine.importHistory` sigue hacia atrás hasta el primer dato de cada fuente (doc. 10 §6): los entrenos del Watch con su ruta y series, y los de la Fitbit con sus parciales y su FC. La biblioteca de carreras (`RunLibrary.allRuns`) fusiona también las anteriores a la ventana del motor, así que récords, volumen, tendencias y segmentos cubren toda tu vida de corredor.

## 2. La carrera segundo a segundo (`RunSeriesBuilder`)

1. **Distancia**, por este orden de preferencia:
   1. GPS del Watch: sin puntos imprecisos (> 50 m), sin saltos imposibles (> 12 m/s) y sin lo recorrido en pausa. Se escala a la distancia oficial del entreno si difiere menos de un 15 %.
   2. Muestras de distancia del Watch (cinta o sin GPS).
   3. Velocidad del Watch.
   4. Parciales de la Fitbit.
   5. Ritmo medio.
2. **Velocidad.** La del reloj cuando no hay GPS; si no, la derivada de la distancia en ~15 s de tiempo activo (junto a una pausa no se frena de mentira).
3. **En movimiento.** Sin pausa y sin estar parado más de 10 s seguidos.
4. **FC.** La del Watch si cubre al menos un 30 % de la carrera, completando con la de la Fitbit donde falte; si no, la de la Fitbit.
5. **Altitud** suavizada ~30 s y pendiente sobre ~20 s de recorrido. **Ritmo ajustado (GAP)** con el coste energético de Minetti.
6. **Cadencia, potencia y dinámica** interpoladas en huecos cortos. Sin cadencia del reloj, se usa la de cada parcial de la Fitbit.

## 3. Fórmulas (`RunPhysiology`)

| Cálculo | Fórmula | Referencia |
|---|---|---|
| VDOT | VO₂(v) / %VO₂(t), con VO₂(v) = −4,60 + 0,182258·v + 0,000104·v² (v en m/min) y %VO₂(t) = 0,8 + 0,1894393·e^(−0,012778·t) + 0,2989558·e^(−0,1932605·t) | Daniels y Gilbert (1979) |
| Predicciones | Tiempo que da ese VDOT en cada distancia (bisección) | Daniels |
| Ritmos | E 62–70 %, M ritmo de maratón previsto, T 88 %, I 97,5 %, R 105 % del VDOT | *Daniels' Running Formula* |
| Riegel | T₂ = T₁ · (D₂/D₁)^1,06 | Riegel (1981) |
| GAP | C(i) = 155,4i⁵ − 30,4i⁴ − 43,3i³ + 46,3i² + 19,5i + 3,6 J/kg/m | Minetti et al. (2002) |
| VO₂ máx. estimado | VO₂(v_GAP) / ((FC/FCmáx − 0,37) / 0,64), solo con 12 min o más en movimiento y FC entre el 65 y el 98 % de la máxima | Swain et al. (1994) |
| TRIMP | Banister segundo a segundo con los coeficientes por sexo del motor (ALG-CAR) | Banister (1991) |
| rTSS e intensidad | IF = GAP medio / velocidad de umbral (T); rTSS = horas · IF² · 100 | Coggan, adaptado a carrera |
| Forma, fatiga y frescura | CTL (media exponencial 42 días) y ATL (7 días) del TRIMP diario de las carreras; TSB = CTL − ATL | Banister, Coggan |
| Eficiencia | GAP (m/min) / FC media | Friel |
| Desacoplamiento | (EF 1.ª mitad − EF 2.ª mitad) / EF 1.ª mitad, con 20 min o más y FC en al menos el 70 % del tiempo | Friel |
| Potencia crítica | 95 % de la mejor media de 20 min (o 90 % de la de 10 min) de los últimos 90 días | — |

**VDOT actual.** Es la mejor marca de 3 km o más de los últimos 120 días. Si la mediana de los VO₂ máx. estimados de tus últimas carreras es más alta, se usa la media de los dos: las marcas de entrenamiento lo infravaloran. La tarjeta dice de dónde sale (la marca, con su fecha, y si se ha promediado con lo estimado).

## 4. Análisis de una carrera

**Cabecera y cifras:**

- Récords de la carrera.
- Distancia, tiempo en movimiento y total, ritmo medio y GAP.
- FC media y máxima, ritmo más rápido y desnivel.
- Cadencia, potencia, zancada y calorías.
- TRIMP, rTSS y VO₂ máx. estimado.
- Recuperación de FC y esfuerzo de Apple.

**Mapa.** Coloreado por ritmo, FC, altitud, potencia o cadencia (quintiles), con marcas de cada km, salida y llegada.

**Gráficas:**

- Ritmo con GAP, FC con las dos fuentes, altitud, cadencia, potencia, zancada, oscilación y contacto.
- Por distancia o por tiempo, con selección al deslizar el dedo.
- La escala no se deja aplastar por un pico suelto (un parón, un salto del GPS): se dibuja entre los percentiles 2 y 98. El ritmo va con lo rápido arriba y marcas cada medio minuto.

**Tramos:**

- **Parciales por km:** ritmo, GAP, FC y desnivel.
- **Vueltas o intervalos:** los del Watch o, si no hay, los de la Fitbit.
- **Series detectadas** (`IntervalDetector`), aunque no marcaras vueltas:
  - la velocidad ajustada por pendiente, suavizada ~16 s, se parte en dos grupos (k-medias) que tienen que diferir al menos un 15 %; si la mitad rápida vuelve a partirse en dos escalones claros (calentamiento suave, series y trote aún más lento), las series son solo el de arriba;
  - con histéresis: una serie empieza al pasar el corte y no acaba hasta bajar a medio camino del ritmo de abajo, así que una bajada o un bache de ritmo no la parten en dos;
  - los tramos de menos de 12 s se funden con los vecinos; una serie es un tramo rápido de 30 s y 100 m o más. Las series cuentan el tiempo activo; la recuperación, también el tiempo parado con el reloj en pausa;
  - hacen falta 3 series, que las recuperaciones vayan al menos un 25 % más lentas que las series (o parado), que lo rápido y lo lento no vayan con el terreno (eso son las cuestas de un rodaje) y que lo rápido sea entre el 10 y el 70 % del tiempo en movimiento (un rodaje con paradas no cuenta);
  - nombre: primero las distancias y tiempos de siempre (400 m, 1 km, 3 min…); si no, «6 × 750 m» si las distancias son parecidas y redondas, «5 × 3 min» si lo son los tiempos, y si no «n cambios de ritmo»;
  - de cada una, distancia, tiempo, ritmo, FC y recuperación; del conjunto, ritmo medio, recuperación media, caída (última frente a primera) y regularidad.
- **Segmentos:** tus tramos por los que pasa esta carrera, con el tiempo y la posición entre todas tus pasadas; desde aquí se crean (§9).
- **Aviso de pico:** si la carrera fue más de un 10 % más larga que la más larga de los 30 días anteriores (§6).

**Zonas:**

- FC: Z1–Z5 del motor.
- Ritmo: recuperación, E, M, T, I, R, con el VDOT.
- Potencia: cinco zonas con la potencia crítica.

**Rendimiento dentro de la carrera:**

- Mejores marcas (400 m a maratón) y curvas de ritmo y de potencia.
- Subidas: de 15 m o más, con al menos un 3 % de pendiente y 150 m de longitud; con su VAM.
- Eficiencia aeróbica, con la interpretación del desacoplamiento: menos de un 5 % es buena base, de 5 a 10 % hay algo de deriva y más de un 10 % es mucha deriva.

**Técnica (valoración orientativa):**

| Métrica | Excelente | Buena | Mejorable | A trabajar |
|---|---|---|---|---|
| Cadencia | — | 170–192 ppm | 162–169 | < 162 |
| Contacto con el suelo | < 240 ms | 240–259 | 260–289 | ≥ 290 |
| Oscilación vertical | < 6,5 cm | 6,5–8,4 | 8,5–10,4 | ≥ 10,5 |
| Ratio vertical | < 6,1 % | 6,1–7,4 | 7,5–8,6 | ≥ 8,7 |

**Apple Watch frente a Fitbit Air:**

- Distancia, FC media, cadencia, calorías y VO₂ máx.
- Diferencia media de FC y límites de concordancia al 95 %, en los segundos que tienen las dos.

**Contexto de la carrera:**

- Tiempo, con aviso si hacía calor.
- Carreras parecidas: salida a menos de 300 m y distancia ±15 %; si no hay, por distancia. Con la diferencia de ritmo y de eficiencia.

**Lo que añades tú:**

- RPE, zapatillas y exportación **GPX**, con FC y cadencia en la extensión de Garmin, para llevarla a otras apps.

## 5. Pestaña Correr

**Entrenamiento:**

- Tu plan: semana y fase, sesiones de la semana con su estado (hecha, a medias, saltada, hoy, pendiente) y porcentaje de sesiones hechas (§8).
- Carrera objetivo con su predicción ajustada (§7) y entrenos sueltos para el Watch.

**Volumen:**

- Esta semana y el año, con la racha de semanas corriendo, y lo de siempre si tienes historial de más de un año.
- Volumen de las últimas 12 semanas o meses, o de todos los años.

**Forma:**

- Forma, fatiga y frescura, con consejo y aviso si la forma sube demasiado deprisa (> 6 en una semana).
- Riesgo de lesión (§6).

**Rendimiento:**

- VDOT, predicciones de 5 km a maratón y ritmos de entrenamiento con su propósito.
- VO₂ máx. de 6 meses, un año o todo: el del Watch, el de la Fitbit (el diario o, si no llega, el de cada carrera) y el estimado por la app. Los valores de cada carrera se ven como puntos, con una línea que es su media móvil de cinco carreras, y arriba el último valor de cada fuente.

**Marcas y tendencias:**

- Récords (1 km, milla, 3, 5 y 10 km, media y maratón), tirada más larga y carrera con más desnivel; cada fila abre su carrera.
- Segmentos: tus tramos con tu mejor tiempo y cuántas pasadas llevas (§9).
- Tendencias de 6 meses, un año o todo: ritmo, eficiencia, VO₂ máx., FC, cadencia, zancada, contacto, oscilación, potencia y desacoplamiento, con la mejora o el empeoramiento. Cada carrera es un punto y la línea es la media móvil de cinco.

**Configuración:**

- Tus zonas de FC, ritmo y potencia.
- Zapatillas: km por par con barra hasta el límite. Se gestionan en su propia pantalla (añadir, predeterminadas, retirar y borrar).

**Lista de carreras:**

- Las de los últimos tres meses, con su marca de récord y el nombre de las series («6 × 800 m»).
- «Todas tus carreras»: por meses y con filtro por año; se carga al desplazarte, aunque sean años de historial.

## 6. Riesgo de lesión (`InjuryRisk`)

**Cociente de carga aguda y crónica (ACWR):**

- Con la **carga de todo el día** que calcula el motor (TRIMP del día entero: carreras, fuerza, bici, caminar…), no solo la de las carreras.
- Medias exponenciales de 7 y 28 días (λ = 2 / (N + 1); Williams et al., 2017 [R13]); hacen falta 28 días de datos.
- Zonas (Gabbett, 2016 [R14]): < 0,8 carga baja, 0,8–1,3 zona óptima, 1,3–1,5 precaución y > 1,5 riesgo alto. Tarjeta con el valor, su gráfica de 8 semanas y un consejo.

**Picos de distancia en una sola carrera** (Frandsen et al., 2025 [R76]):

- Cada carrera de las últimas 4 semanas frente a la más larga de sus 30 días anteriores: más de un 10 % es un pico moderado; más de un 30 %, alto; más del doble, muy alto. Sin carreras en esos 30 días, «vuelta tras un parón».
- La tarjeta dice hasta dónde alargar la próxima tirada (+10 % sobre la más larga del mes) y la carrera muestra un aviso si fue un pico.
- También se compara el volumen de los últimos 7 días con la media semanal de los 21 anteriores.

## 7. Carrera objetivo (`RacePredictor`)

**Lo que pones:** nombre, día y hora, distancia, desnivel positivo y negativo o el **GPX del recorrido**, temperatura y humedad, y tu objetivo de tiempo (opcional).

**Predicción:**

1. Tiempo en llano con tu VDOT.
2. **Desnivel:** distancia equivalente en llano sumando cada tramo por su coste (Minetti et al., 2002 [R75]); bajando se gana como mucho un 12 %. Sin GPX, el desnivel se reparte en subidas y bajadas del 4 %.
3. **Calor:** temperatura + punto de rocío (Magnus; Alduchov y Eskridge [R78]) en °F y la tabla habitual de los entrenadores (hasta 100 °F nada; 150 °F, un 4,5 %; 180 °F, un 10 %; más, no correr a tope). En carreras de menos de 20 min cuenta la mitad; de 60 min o más, entera: el calor penaliza más cuanto más larga es la carrera (Ely et al., 2007 [R77]).
4. Con el GPX, **ritmo por km a esfuerzo constante**: el tiempo de cada km es proporcional a su coste.

**El tiempo del día de la carrera:** buscas la ciudad y la app usa Open-Meteo: la previsión si faltan 16 días o menos; si no, la media de ese día y hora en los tres años anteriores. Solo se envía la ciudad, nunca tu ubicación.

## 8. Plan de entrenamiento y entrenos en el Watch (`PlanBuilder`, `WorkoutLibrary`)

**Cómo se construye el plan:**

- Hasta 24 semanas, de la actual a la de la carrera (si falta más, empieza más tarde), con 3 a 6 días por semana y el día de la tirada larga que elijas.
- Parte de tu volumen de las últimas 4 semanas: +5 % la primera, +8 % por semana después, una semana de descarga (−20 %) cada cuatro y un techo según la distancia (p. ej. 10K: ×1,25 y al menos 32 km).
- Fases: base (40 %), desarrollo (40 %), específica (20 %), afinamiento (una semana; dos para el maratón) y semana de la carrera.
- Tirada larga: un 28–35 % del volumen, con techo por distancia (14, 18, 21 y 32 km) y **sin subir nunca más de un 10 %** sobre la más larga reciente (§6).
- Calidad según fase y distancia: cuestas, fartlek y tempo en la base; series a ritmo I y umbral en desarrollo; repeticiones, ritmo de carrera y ritmo M en la específica; tramos cortos a ritmo en el afinamiento. Se alargan semana a semana.
- La semana de la carrera: un trote corto la víspera, nada el día antes y la carrera.
- Cada sesión se marca como hecha (una carrera ese día con al menos el 70 % de la distancia prevista), a medias, saltada, hoy o pendiente.

**Entrenos estructurados:**

- Calentamiento, bloques que se repiten (trabajo y recuperación) y vuelta a la calma, con objetivo de distancia o de tiempo.
- Cada paso lleva un rango de ritmo (±5 s/km) de tus ritmos del VDOT o una zona de FC; el ritmo de carrera sale de la predicción o de tu objetivo.
- **En el Watch (WorkoutKit):** «Mandar al Apple Watch» programa el entreno para su día en Entreno › Programados, con avisos de ritmo (rango de velocidad) o de zona. Desde el plan se mandan las sesiones de las dos próximas semanas. «Vista previa» enseña cómo quedará en el reloj.
- También hay entrenos sueltos con tus ritmos: rodajes, tirada larga, tempo, umbral, series, repeticiones, cuestas, fartlek, progresivo y ritmo M.

## 9. Segmentos propios (`SegmentMatcher`)

**Crear uno:** en una carrera con GPS, eliges el inicio y el final (al menos 200 m) sobre el mapa y le pones nombre. Se guarda su trazado (un punto cada 10 m), longitud y desnivel.

**Pasadas:**

- En el sentido en que lo corriste: pasar a menos de 30 m de la salida y después de la llegada, recorriendo entre el 80 y el 130 % de su longitud, y sin separarte más de 40 m del tramo (se toleran fallos del GPS en un 10 % de los puntos de control, uno cada 50 m).
- De cada pasada: tiempo, ritmo y FC media. En el segmento, tus 10 mejores y la evolución; en cada carrera, tu posición y lo que te separa de tu mejor.
- Solo se lee la ruta de las carreras cuyo recuadro contiene el segmento, y cada carrera se revisa una vez por segmento (`segment_scan`); al crearlo se buscan en todo el historial.

## 10. Zapatillas

**Cuántos km lleva un par:**

- Los que ya tenían al añadirlas más los de sus carreras.
- En cada carrera cuenta el par elegido o, si no hay, el predeterminado que ya tenías ese día.
- El límite por defecto es de 700 km.

**Dónde se guardan:**

- La lista va en `app_state` (`shoes`).
- La elección de cada carrera va en su anotación (`shoeID`).

## 11. Análisis con IA

**Cómo funciona:**

- Es una sola petición, con salida estructurada:
  - titular y resumen;
  - 2–3 puntos fuertes;
  - 1–3 aspectos a mejorar con una acción cada uno;
  - la próxima sesión.
- Sus hechos se calculan con `RunFacts`:
  - la carrera: cifras, parciales, vueltas, series detectadas, marcas y récords nuevos, subidas, técnica, tiempo y comparación de dispositivos;
  - el contexto: VDOT y ritmos, km de las últimas 4 semanas, forma y fatiga;
  - lo tuyo: la recuperación de ese día, tu RPE y tus notas, marcadas como dato.

**Privacidad:**

- **Nunca se envían coordenadas.**
- El resultado se guarda en `report` (`ai_run`) y no se repite salvo que pidas volver a analizar.
- En el modo demostración se muestra un texto de ejemplo sin llamar a ninguna IA.

## 12. Privacidad

**Qué sale del iPhone:**

- La ruta y los datos de cada carrera no salen de él.
- Excepto el GPX, que exportas tú.
- Para el tiempo de la carrera objetivo, el nombre de la ciudad (a la búsqueda de Open-Meteo) y sus coordenadas con la fecha (a su previsión o archivo). Nunca tu ubicación.
- Los entrenos que mandas al Watch van a tu reloj (WorkoutKit), no a ningún servidor.

**La salida de cada carrera:**

- Se guarda redondeada (~100 m) en la caché, solo para encontrar carreras por la misma zona.

## 13. Limitaciones

**Estimaciones y valoraciones:**

- El VO₂ máx. estimado y el VDOT son estimaciones: mejoran con carreras de ritmo constante y con alguna marca a tope.
- Las valoraciones de técnica son orientativas. Dependen de la talla y del ritmo, así que conviene compararlas contigo mismo en «Tendencias» y «Carreras parecidas».
- La predicción con calor usa una tabla empírica; la de desnivel, el coste energético con un tope en las bajadas. Son una guía para repartir el esfuerzo, no una garantía.
- El plan es una propuesta genérica bien construida, no un entrenador: si te duele algo o duermes mal varios días, manda la recuperación.
- La detección de series necesita que los tramos rápidos se distingan claramente (recuperaciones al menos un 25 % más lentas); un fartlek muy suave o series con recuperación flotante pueden no detectarse. Una pausa larga en mitad de una serie la parte en dos.

**Datos que dependen de la fuente:**

- Sin el Watch no hay mapa, altitud ni series de dinámica: se usan los parciales y medias de la Fitbit.
- El tiempo solo llega en entrenos al aire libre del Watch.

## 14. Siguientes pasos posibles

**Entrenamiento:**

- Ajustar el plan solo según cómo vas (sesiones saltadas, recuperación baja, riesgo alto).
- Entrenos de fuerza y movilidad para corredores dentro del plan.

**Comparar y predecir:**

- Predicción con el viento previsto y la altitud de la carrera.
- Segmentos sugeridos: los tramos que más repites, sin tener que crearlos.

**Prevención de lesiones:**

- Aviso en Hoy (y notificación) cuando el cociente de carga pasa de 1,5 o hay un pico de distancia.
