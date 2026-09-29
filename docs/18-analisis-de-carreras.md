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
  - RPE, zapatillas y exportación GPX.
- **La pestaña Correr** muestra:
  - volumen por semanas y meses, y racha;
  - forma, fatiga y frescura;
  - VDOT, predicciones y ritmos de entrenamiento;
  - VO₂ máx. de las tres fuentes;
  - récords y tendencias;
  - tus zonas y tus zapatillas.
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

## 2. La carrera segundo a segundo (`RunSeriesBuilder`)

1. **Distancia**, por este orden de preferencia:
   1. GPS del Watch: sin puntos imprecisos (> 50 m), sin saltos imposibles (> 12 m/s) y sin lo recorrido en pausa. Se escala a la distancia oficial del entreno si difiere menos de un 15 %.
   2. Muestras de distancia del Watch (cinta o sin GPS).
   3. Velocidad del Watch.
   4. Parciales de la Fitbit.
   5. Ritmo medio.
2. **Velocidad.** La del reloj cuando no hay GPS; si no, la derivada de la distancia en ~15 s.
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

**VDOT actual.** Es la mejor marca de 3 km o más de los últimos 120 días. Si la mediana de los VO₂ máx. estimados de tus últimas carreras es más alta, se usa la media de los dos: las marcas de entrenamiento lo infravaloran.

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

**Tramos:**

- **Parciales por km:** ritmo, GAP, FC y desnivel.
- **Vueltas o intervalos:** los del Watch o, si no hay, los de la Fitbit.

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

**Volumen:**

- Esta semana y el año, con la racha de semanas corriendo.
- Volumen de las últimas 12 semanas o meses.

**Forma:**

- Forma, fatiga y frescura, con consejo y aviso si la forma sube demasiado deprisa (> 6 en una semana).

**Rendimiento:**

- VDOT, predicciones de 5 km a maratón y ritmos de entrenamiento con su propósito.
- VO₂ máx. de 6 meses: el del Watch, el de la Fitbit (diario y por carrera) y el estimado por la app.

**Marcas y tendencias:**

- Récords y tirada más larga.
- Tendencias de 6 meses: ritmo, eficiencia, VO₂ máx., FC, cadencia, zancada, contacto, oscilación, potencia y desacoplamiento, con la mejora o el empeoramiento.

**Configuración:**

- Tus zonas de FC, ritmo y potencia.
- Zapatillas: km por par con barra hasta el límite. Se gestionan en su propia pantalla (añadir, predeterminadas, retirar y borrar).

**Lista de carreras:**

- Todas, por meses, con su marca de récord.

## 6. Zapatillas

**Cuántos km lleva un par:**

- Los que ya tenían al añadirlas más los de sus carreras.
- En cada carrera cuenta el par elegido o, si no hay, el predeterminado que ya tenías ese día.
- El límite por defecto es de 700 km.

**Dónde se guardan:**

- La lista va en `app_state` (`shoes`).
- La elección de cada carrera va en su anotación (`shoeID`).

## 7. Análisis con IA

**Cómo funciona:**

- Es una sola petición, con salida estructurada:
  - titular y resumen;
  - 2–3 puntos fuertes;
  - 1–3 aspectos a mejorar con una acción cada uno;
  - la próxima sesión.
- Sus hechos se calculan con `RunFacts`:
  - la carrera: cifras, parciales, vueltas, marcas y récords nuevos, subidas, técnica, tiempo y comparación de dispositivos;
  - el contexto: VDOT y ritmos, km de las últimas 4 semanas, forma y fatiga;
  - lo tuyo: la recuperación de ese día, tu RPE y tus notas, marcadas como dato.

**Privacidad:**

- **Nunca se envían coordenadas.**
- El resultado se guarda en `report` (`ai_run`) y no se repite salvo que pidas volver a analizar.
- En el modo demostración se muestra un texto de ejemplo sin llamar a ninguna IA.

## 8. Privacidad

**Qué sale del iPhone:**

- La ruta y los datos de cada carrera no salen de él.
- Excepto el GPX, que exportas tú.

**La salida de cada carrera:**

- Se guarda redondeada (~100 m) en la caché, solo para encontrar carreras por la misma zona.

## 9. Limitaciones

**Estimaciones y valoraciones:**

- El VO₂ máx. estimado y el VDOT son estimaciones: mejoran con carreras de ritmo constante y con alguna marca a tope.
- Las valoraciones de técnica son orientativas. Dependen de la talla y del ritmo, así que conviene compararlas contigo mismo en «Tendencias» y «Carreras parecidas».

**Datos que dependen de la fuente:**

- Sin el Watch no hay mapa, altitud ni series de dinámica: se usan los parciales y medias de la Fitbit.
- El tiempo solo llega en entrenos al aire libre del Watch.

## 10. Siguientes pasos posibles

**Entrenamiento:**

- Planes con entrenos estructurados enviados al Watch (WorkoutKit), con los ritmos del VDOT.
- Detección automática de series sin vueltas marcadas.

**Comparar y predecir:**

- Comparación por tramos de una misma ruta (segmentos propios).
- Predicciones ajustadas al desnivel y al calor de la carrera objetivo.

**Prevención de lesiones:**

- Aviso de carga (ACWR) con la carga de todo el día, no solo de las carreras.
