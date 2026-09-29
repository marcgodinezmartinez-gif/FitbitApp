# 05 · Algoritmos y métricas

Especificación de **cómo se calcula cada puntuación**. Todo se calcula **en el iPhone**, dentro del paquete Swift `MetricsKit` (funciones puras, sin red ni base de datos; doc. 08). Los algoritmos de WHOOP son propietarios y no se copian (RL-62): aquí se definen equivalentes funcionales **abiertos**, construidos con métodos publicados (referencias en [referencias.md](referencias.md), citadas como [R#]; todos los DOI se comprobaron en Crossref el 28/09/2026).

Principios:

1. **Personalización**: casi todo se compara con la **línea base del propio usuario**, no con medias poblacionales. Así los sesgos constantes del sensor se cancelan en gran medida.
2. **Transparencia**: cada puntuación guarda sus componentes y se explica en la app (RF-REC-04, RF-PER-04).
3. **Parámetros calibrables y versionados**: todo valor marcado como *parámetro* vive en `algorithm_params` (doc. 09) y se ajusta con la validación del doc. 13 §6. La versión inicial es `0.x` (calibración) y se congela como `1.0.0` al cumplir H2. Los valores marcados **[heurístico]** son propuestas razonadas sin validación publicada: se ajustan con tus datos.
4. **Sin cifras inventadas**: si faltan datos, estado «Calibrando» o «Datos insuficientes» (RNF-CAL-02).
5. **Determinismo**: mismas entradas + misma versión ⇒ mismo resultado (RNF-DIS-07). Como el histórico de Google se puede volver a descargar, todas las puntuaciones se pueden recalcular desde cero.

Notación: `clip(x, a, b)` limita x al intervalo [a, b]; `Φ` es la función de distribución normal estándar; `ln` logaritmo natural.

---

## 0. Validez de datos (ALG-VAL)

| Regla | Valor inicial (*parámetro*) |
|---|---|
| Muestra de FC válida | 25 ≤ lpm ≤ 230; se descartan saltos > 40 lpm en ≤ 2 s sin continuidad (artefactos) |
| Minuto con FC válida | Valor del `rollUp` de 60 s con ≥ 50 % de muestras |
| Noche válida para líneas base | Sueño principal con ≥ 180 min dormidos y HRV presente |
| Cobertura de FC nocturna | Minutos con FC válida / minutos dormidos |
| Día válido para carga | ≥ 10 h de FC válida en el ciclo (si no, confianza baja) |

## 0 bis. Fusión de fuentes (ALG-FUS)

Dos fuentes: **`fitbit`** (Fitbit Air vía Google Health API, llevada 24/7, también al correr) y **`watch`** (Apple Watch vía Apple Health, solo al correr), así que cada carrera la graban las dos. Los datos brutos de cada fuente se guardan intactos; la fusión es un dato **derivado**, determinista y recalculable, que se rehace para la ventana afectada en cada sincronización (doc. 16). **Nunca se promedian dos fuentes**: en cada dato y minuto manda una.

| Regla | Especificación |
|---|---|
| **ALG-FUS-01 · Prioridades** | Noche y vitales (sueño, VFC, FC en reposo, SpO₂, FR, temperatura) → `fitbit`. FC dentro de un entrenamiento del Watch → `watch` (*parámetro* `hr_workout_priority`); fuera → `fitbit`. Totales diarios de pasos, distancia y calorías → `fitbit`, con relleno de huecos del `watch`. Datos propios del entrenamiento (ruta, distancia, ritmo, dinámica de carrera, calorías) → `watch`. Tabla completa en el doc. 16 §5. |
| **ALG-FUS-02 · Emparejar actividades** | Una sesión de la Fitbit F (detección automática) y un entrenamiento del Watch W son la misma actividad si `solape(F, W) / min(duración F, duración W) ≥ 0,5` (*parámetro* `match_overlap`), sea cual sea el tipo detectado. La actividad fusionada toma de W el intervalo, el tipo, la ruta, la distancia, el ritmo, las calorías y la dinámica de carrera, y guarda F como fuente secundaria. Si F se sale de W ≥ 10 min (*parámetro* `min_leftover_min`), esa parte queda como actividad aparte; si no, se absorbe. Una F puede emparejar con varios W y al revés (p. ej., la pulsera partió la carrera en dos). El identificador estable es el del entrenamiento del Watch, así que el RPE y las notas se conservan al re-sincronizar. Las actividades creadas a mano en la app nunca se fusionan solas. |
| **ALG-FUS-03 · FC por minuto fusionada** | Para cada minuto m: si m cae dentro de un entrenamiento del Watch y el Watch tiene minuto válido (≥ 2 muestras válidas, ALG-VAL; *parámetro* `watch_min_samples`) ⇒ media del Watch; si no, la FC de la Fitbit si su minuto es válido; si no, la del Watch si existe (pulsera no puesta); si no, hueco. Si las dos fuentes son válidas y difieren > 15 lpm durante ≥ 5 min seguidos (*parámetros* `disagreement_bpm`, `disagreement_min`), la actividad se marca «las fuentes no coinciden» y se sigue la preferencia. Es la serie que usan la carga (ALG-CAR), las zonas y el estrés (ALG-EST-01). La preferencia por el Watch en carrera se apoya en que el Apple Watch fue el reloj con menor error de FC en un estudio de laboratorio con siete dispositivos [R73]; se valida con tus carreras (doc. 13 §6). |
| **ALG-FUS-04 · Pasos, distancia y calorías** | Pasos y calorías del día: los de la Fitbit (Google). **Distancia del día**: la de la Fitbit, salvo en los minutos de un entrenamiento del Watch **con ruta GPS**, donde la distancia de la Fitbit (estimada por la zancada) se sustituye por la del GPS del Watch, para que la distancia del día cuadre con la de tu carrera (*parámetro* `gps_distance_override`). Si durante un entrenamiento del Watch la Fitbit no registra ni FC ni pasos (no la llevabas, p. ej. porque estaba cargando), se suman los pasos, la distancia y la energía activa del Watch de esos minutos. La distancia, el ritmo y las calorías **del entrenamiento** son siempre los del Watch. |
| **ALG-FUS-05 · Noche y líneas base** | Solo `fitbit`. La VFC del Watch (SDNN, no RMSSD), su FC en reposo y su sueño no entran en la recuperación ni en las líneas base: mezclar dispositivos rompería la comparación con tu propia normalidad. |
| **ALG-FUS-06 · VO₂ máx.** | Una serie por fuente, nunca promediadas. Valor principal: el del Watch si tiene < 60 días; si no, el de Google. La edad fisiológica usa una sola fuente en su ventana de 180 días (la que tenga más valores) e indica cuál. |
| **ALG-FUS-07 · FC máxima observada** | ALG-CAR-06 con los entrenamientos de las dos fuentes (tras sus filtros de artefactos); la propuesta indica de qué dispositivo y fecha procede. |
| **ALG-FUS-08 · Copias entre Google Health y Apple Health** | La app Google Health puede copiar datos en los dos sentidos (doc. 10 §8). En Apple Health solo se leen muestras **registradas por un Apple Watch** (doc. 16 §4); lo que escriben Google Health u otras apps se ignora. De Google se lee la familia de fuentes `google-wearables` (solo pulseras de Google y Fitbit); si algún tipo se lee con `list`, se descartan los puntos cuyo `dataSource.platform` sea `HEALTH_KIT`. Red de seguridad: un entrenamiento del Watch que llegara también por Google se fusiona por solape (ALG-FUS-02). |
| **ALG-FUS-09 · Fuentes ausentes** | Sin Watch, todo funciona solo con la Fitbit. Si falta la Fitbit en un periodo, la FC, los pasos y la energía del Watch lo cubren; la confianza del ciclo refleja las horas sin datos (ALG-VAL). |
| **ALG-FUS-10 · Concordancia de FC entre fuentes** | En cada actividad grabada por los dos, sobre los minutos con FC válida en ambos: diferencia media Watch − Fitbit (sesgo) y límites de concordancia al 95 % (media ± 1,96 · DE de las diferencias), como en el método de Bland y Altman [R74]. Se muestra por carrera y como resumen de tus últimas 10 (*parámetro* `agreement_window_runs`). No dice cuál acierta (no hay una referencia como una banda de pecho), solo cuánto se parecen; sirve para elegir la preferencia de RF-FUS-07. |

## 1. Ciclo fisiológico (ALG-CIC-01)

Un ciclo va del **fin del sueño principal** de una noche al fin del sueño principal de la siguiente (doc. 08 §4). El ciclo «abierto» es el actual. Si no se detecta sueño principal en 30 h, se crea un ciclo de reserva 04:00–04:00 hora local (`is_fallback = true`). Siestas y actividades pertenecen al ciclo en el que empiezan.

## 2. Líneas base (ALG-BAS-01)

**Entradas nocturnas** (tipos de la Google Health API, doc. 03 §4):

| Métrica | Origen | Nota |
|---|---|---|
| RMSSD | `daily-heart-rate-variability`: RMSSD en **sueño profundo** si hay ≥ 20 min de sueño profundo; si no, RMSSD medio de la noche (*parámetro* `hrv_source`) | El sueño profundo es la condición más estable (WHOOP también pondera el sueño de ondas lentas); en la calibración se elige la variante con menor coeficiente de variación |
| FCR | `daily-resting-heart-rate` | Diaria |
| FR | `daily-respiratory-rate` | Nocturna |
| Temp | `daily-sleep-temperature-derivations` (temperatura nocturna absoluta) | Línea base propia; la de Google (30 días) se guarda solo como referencia |
| SpO₂ | `daily-oxygen-saturation` (media nocturna) | Solo tendencia (§10) |

Para cada métrica `m ∈ {lnRMSSD, FCR, FR, Temp, SpO₂}` y cada noche `t`:

- Ventana **corta**: 30 noches válidas anteriores a `t` (sin incluir `t`). Ventana **larga**: 60 noches (rangos del monitor de salud).
- Estadísticos **robustos**: `μ = mediana`, `σ = 1,4826 · MAD`, con **suelo** (*parámetros*): lnRMSSD 0,05; FCR 1 lpm; FR 0,3 rpm; Temp 0,1 °C; SpO₂ 0,5 %.
- Calibración: **n < 4** ⇒ sin línea base (sin recuperación); **4 ≤ n < 14** ⇒ confianza como máximo «media»; **n ≥ 14** ⇒ plena.
- Tendencia: media móvil de 7 noches de lnRMSSD (exige ≥ 3–4 noches válidas en la semana) y su coeficiente de variación `CV₇ = 100 · DE/media`.

Justificación:

- **ln(RMSSD)**: el RMSSD es el índice parasimpático estándar de la HRV [R39]; su logaritmo estabiliza la varianza y es la práctica habitual [R1][R2][R40].
- **Ventanas**: los ensayos de entrenamiento guiado por HRV compararon la media de 7 días con una referencia de 3–4 semanas [R4][R5] o con la media de 10 días [R3]; Nuuttila et al. usaron 4 semanas móviles ± 0,5 DE y recomiendan combinar una referencia corta y otra larga (~8 semanas) para que la banda no «derive» [R46]. Las ventanas de 30/60 noches siguen ese criterio pero **no están validadas como tales** ⇒ se revisan en la calibración.
- **Medias semanales**: la media de 7 días de lnRMSSD refleja los cambios de forma (r ≈ 0,72–0,76) mucho mejor que los valores de un solo día [R45]; por eso existe el término de tendencia (§3) y el Coach habla de tendencias semanales.
- **Cambio relevante**: la media semanal fuera de «μ ± 0,5 σ» (cambio mínimo relevante [R41]). Por debajo ⇒ reducir intensidad; por encima suele ser benigno.
- **CV₇**: se interpreta **junto** a la media: una media y un CV que bajan a la vez precedieron a un sobreentrenamiento funcional en una triatleta de élite [R71], mientras que un CV que baja pronto indicó buena adaptación en futbolistas [R72].
- **Expectativas realistas**: el entrenamiento guiado por HRV mejora la modulación vagal (DME 0,50), pero sus mejoras de VO₂ máx. y rendimiento son pequeñas y no significativas (DME ≈ 0,20) [R47]. La app no promete rendimiento.

## 3. Recuperación (ALG-REC-01)

Entradas de la noche `t`: RMSSD nocturno (ms), FC en reposo (lpm), **suficiencia** de sueño SP (%, ALG-SUE-02), FR (rpm), temperatura cutánea nocturna (°C), SpO₂ media (%).

**Paso 1 — puntuaciones z frente a la línea base corta**:

| Componente | Fórmula | Sentido |
|---|---|---|
| HRV | `z_hrv = clip((ln RMSSD_t − μ) / σ, −3, +1)` | Más alto = mejor, con techo en +1: valores muy altos pueden reflejar saturación vagal en personas muy entrenadas [R1][R2] |
| FC en reposo | `z_fcr = clip(−(FCR_t − μ) / σ, −3, 3)` | Más baja = mejor |
| Sueño | `z_sue = clip((SP_t − 85) / 10, −3, 1,5)` | Suficiencia absoluta (la necesidad ya es personal): 85 % neutro |
| FR | `z_fr = −clip((FR_t − μ) / σ, 0, 3)` | Solo penaliza subidas |
| Temperatura | `z_tmp = −clip((Temp_t − μ) / σ, 0, 3)` | Solo penaliza subidas |
| SpO₂ | `z_spo2 = −clip(−(SpO₂_t − μ) / σ, 0, 3)` | Solo penaliza bajadas |

**Paso 2 — compuesto** (pesos = *parámetros* **[heurístico]**):

```
C = 0,55·z_hrv + 0,25·z_fcr + 0,20·z_sue  +  0,10·(z_fr + z_tmp + z_spo2)
```

HRV y FC en reposo son los marcadores con más respaldo para la preparación diaria [R1][R3][R4][R5]; el sueño pesa menos que la HRV (como en WHOOP); FR, temperatura y SpO₂ solo restan (señales de posible sobrecarga o malestar [R21][R22][R23]). Si falta un componente secundario su término vale 0 y la confianza baja un nivel; si falta el sueño su peso se reparte entre HRV y FCR; **sin HRV no hay recuperación** (RF-REC-05).

**Paso 3 — escala 0–100**:

```
Recuperación = round( 100 · Φ( (C − c₀) / s ) )
```

- `c₀ = −0,15` (*parámetro*): un día «normal» (C ≈ 0) da ≈ 57 %, cerca de la media publicada de los miembros de WHOOP (≈ 58 %).
- `s`: mientras haya < 30 noches, `s = 0,8`; después, `s = √(wᵀ R w)`, con `w` los pesos de los tres componentes principales y `R` la matriz de correlación **personal** de sus z; así C/s se comporta como una normal estándar y las zonas son estables [heurístico].
- Con Φ(±0,44) = 33/67 %, los cortes de zona reproducen los de WHOOP: **alta 67–100 · media 34–66 · baja 0–33**.

**Confianza**: alta si n ≥ 14, cobertura de FC nocturna ≥ 70 % y los 3 componentes principales presentes; media si 4 ≤ n < 14 o falta un secundario; baja si cobertura < 50 % o < 4 h dormidas.

**Explicación en la app** (RF-REC-04): cada `z` se traduce a lenguaje natural («Tu VFC está un 12 % por encima de tu media», con `exp(ln RMSSD_t − μ) − 1`). Para contextualizar, efectos medios observados en 28 175 usuarios [R48]:

| Factor | FC | rMSSD |
|---|---|---|
| Entrenamiento duro | +1,3 % | −4,6 % |
| Alcohol | +6 % | −12 % |
| Enfermedad | +6 % | −10 % |
| Fase lútea frente a folicular | +1,6 % | −3,2 % |

**Extensión v1.1**: término de tendencia `z_tend = (media₇ lnRMSSD − μ₆₀) / σ₆₀` para detectar fatiga acumulada que un solo día no refleja [R45][R46].

## 4. Carga — «Strain» (ALG-CAR)

### ALG-CAR-06 · FC máxima, FC de reserva y zonas

- FC máx.: preferentemente la **máxima observada robusta** (mediana móvil de 30 s de la FC de alta resolución —1 s en la Fitbit, cada pocos segundos en el Apple Watch— en ≥ 2 entrenamientos distintos de los últimos 180 días, de cualquiera de las dos fuentes, confirmada por el usuario; ALG-FUS-07) o un valor manual. Sin ella: `208 − 0,7·edad` [R10] por defecto; alternativas `207 − 0,7·edad` (Gellish, la que usa WHOOP) [R42], `211 − 0,64·edad` [R49] y, en mujeres, `206 − 0,88·edad` [R50].
- `FCR_ref` = media de 7 días de la FC en reposo.
- Fracción de FC de reserva de cada minuto (Karvonen [R11]): `x = clip((FC − FCR_ref) / (FCmáx − FCR_ref), 0, 1)`.
- Zonas por defecto (% de FC de reserva): Z1 50–60 · Z2 60–70 · Z3 70–80 · Z4 80–90 · Z5 90–100; alternativa por % de FC máx. o personalizada (RF-CAR-03).

### ALG-CAR-01 · Carga del ciclo (0–21)

1. **Impulso por minuto** (TRIMP de Banister [R6][R7]):

   ```
   y = x · a · e^(b·x)     si x ≥ x_min,   si no 0
   ```

   `(a, b) = (0,64; 1,92)` en hombres y `(0,86; 1,67)` en mujeres [R7]; sexo no indicado: `(0,75; 1,795)`. Google usa `(0,64; 1,92)` para todos en su *Cardio Load* [R51] (*parámetro* `banister_mode`). `x_min = 0,30`: como el *Cardio Load* de Google, que no acumula carga por debajo del 30 % de la FC de reserva [R51], para que la vigilia sedentaria no sume. Alternativas evaluables: TRIMP por zonas de Edwards [R8] o por umbrales de Lucía [R9].

2. **Carga bruta** `L = Σ y` sobre los minutos del ciclo (FC media de cada minuto de la serie fusionada, ALG-FUS-03; solo Fitbit si no hay Apple Watch). A diferencia del *Cardio Load*, **no** se exige movimiento: como el *Day Strain* de WHOOP, la carga del día incluye también la activación no deportiva (*parámetro* `require_motion = false`).

3. **Escala 0–21** (no lineal, «cuesta más pasar de 16 a 17 que de 4 a 5», como la escala de WHOOP inspirada en la de esfuerzo percibido de Borg [R52]) **[heurístico]**:

   ```
   Carga = 21 · (1 − e^(−(L / τ)^γ)),   τ = 100,  γ = 0,8
   ```

   Anclajes (FCR 55, FCmáx 185, hombre):

   | Sesión / día | L (TRIMP) | Carga |
   |---|---|---|
   | Día sedentario con 60 min de paseo | ≈ 25–35 | ≈ 6–7 |
   | Carrera de 45 min a 150 lpm | ≈ 85 | ≈ 12,3 |
   | 60 min al 70 % de FC de reserva | ≈ 103 | ≈ 13,5 |
   | Carrera dura de 60 min a 165 lpm | ≈ 165 | ≈ 16,3 |
   | Maratón (3 h 30 a 160 lpm) | ≈ 510 | ≈ 20,5 (WHOOP publica ≈ 20,4 para un maratón) |

   Alternativa a evaluar en la calibración: `Carga = min(21; 3,65 · ln(1 + L/3))` [heurístico], más generosa en cargas bajas y menos saturada arriba. Ambas se ajustan con el esfuerzo percibido de sesión (doc. 13 §6).

4. Se muestra con 1 decimal. Rangos: 0–9 ligera · 10–13 moderada · 14–17 alta · 18–21 máxima. Las **calorías no intervienen** (su estimación por pulsera es poco fiable, §10).

### ALG-CAR-02 · Carga de actividad

Mismo cálculo limitado a los minutos de la actividad. Por la escala no lineal, las cargas de actividad **no se suman** para dar la del ciclo (se suma `L`, no la puntuación).

### ALG-CAR-05 · Carga muscular (fuerza) con sRPE

Para actividades de fuerza con esfuerzo percibido: `sRPE = RPE (0–10) × minutos` [R12]. Carga bruta de la actividad `L_act = max(L_cardio_act, κ · sRPE)` con `κ = 0,2` (*parámetro*); al ciclo se añade `max(0, κ · sRPE − L_cardio_act)`. Una sesión de fuerza de 60 min con RPE 7 suma ≈ 84 TRIMP (≈ 12 de carga) aunque la FC haya sido moderada.

### ALG-CAR-03 · Carga objetivo

```
centro = S̄₂₈ + k · (Recuperación − 50) / 50        k = 3 (parámetro)
banda  = [centro − 1,5 ; centro + 1,5] ∩ [4 ; 19]
```

`S̄₂₈` = media de la carga diaria de los últimos 28 ciclos. Modos del usuario: «Mantener» (0), «Progresar» (+1), «Descargar» (−2). Ejemplo: media 11 y recuperación 90 % ⇒ 11,9–14,9; recuperación 20 % ⇒ 7,7–10,7.

### ALG-CAR-04 · Carga aguda y crónica

Medias móviles exponenciales de la carga bruta diaria [R13]: `λ = 2/(N+1)` con N = 7 (aguda, λ = 0,25) y N = 28 (crónica, λ ≈ 0,069); `EWMA_t = λ·L_t + (1−λ)·EWMA_{t−1}`.

- Se muestran **la carga aguda y la crónica por separado**. El cociente (ACWR) solo aparece como dato secundario («aumento brusco» si > 1,5) y **nunca** como predictor de lesiones: la literatura reciente recomienda abandonarlo por sus artefactos estadísticos [R14][R15][R53].
- Opcional (F3): curva forma–fatiga con constantes poblacionales de 42 y 7 días; no se ajustan por persona porque ese ajuste es inestable [R54].

## 5. Sueño (ALG-SUE)

### ALG-SUE-00 · Sueño principal y siestas

Si la API marca el sueño principal, se usa. Si no: la sesión más larga con ≥ 180 min dormidos que termina entre las 03:00 y las 15:00 locales; el resto de sesiones ≥ 15 min son siestas.

### ALG-SUE-01 · Necesidad de sueño

```
necesidad = base + ajuste_carga + ajuste_deuda − crédito_siestas
```

| Término | Definición (valores iniciales = *parámetros*) |
|---|---|
| `base` | Por edad según el consenso (7–9 h en adultos de 18–64; 7–8 h desde los 65) [R16][R17]: 8 h hasta los 64 años y 7 h 30 después. En laboratorio, la duración óptima individual media fue de 8,4 h (rango 7,3–9,3) [R55]. Editable. Personalización (F3): tras ≥ 8 noches «libres» (antes de días sin hora de despertar fijada), `base = 0,5·base₀ + 0,5·mediana(sueño en noches libres)`, recortada a [6 h 30, 9 h 30] |
| `ajuste_carga` | `5 min × max(0, Carga_ciclo_anterior − S̄₂₈)`, máx. 45 min [heurístico, como el componente «carga reciente» de WHOOP] |
| `ajuste_deuda` | `0,25 × deuda_actual`, máx. 60 min |
| `crédito_siestas` | Minutos dormidos en siestas del ciclo, máx. 60 min |

### ALG-SUE-02 · Suficiencia de sueño

`SP = min(100, 100 · minutos_dormidos / necesidad)`, con minutos dormidos = ligero + profundo + REM. Es la entrada de sueño de la recuperación (ALG-REC-01).

### ALG-SUE-03 · Deuda de sueño

```
deuda_t = clip( ρ · deuda_{t−1} + (necesidad_sin_deuda_t − dormido_t), 0, 600 min )
```

`ρ = 0,85` (semivida ≈ 4 noches: en laboratorio, recuperar 1 h de deuda latente llevó unos 4 días [R55]; los déficits se acumulan de forma dosis-dependiente [R56]); `necesidad_sin_deuda = base + ajuste_carga − crédito_siestas` (evita contar la deuda dos veces).

### ALG-SUE-04 · Constancia (índice de regularidad del sueño, SRI)

Índice de Phillips et al. [R18] sobre los últimos 7 días, con estado dormido/despierto por minuto (incluidas siestas):

```
SRI = −100 + (200 / (M · (N − 1))) · Σ_{i=1}^{N−1} Σ_{j=1}^{M} δ(s_{i,j}, s_{i+1,j})
```

`M` = 1 440 min/día, `N` = días, `δ = 1` si el estado coincide 24 h después; solo pares de minutos con dato en ambos días. Se muestra 0–100 (negativo ⇒ 0) con ≥ 5 pares de días válidos. En el UK Biobank la mediana fue 81, y los cuatro quintiles más regulares tuvieron un 20–48 % menos de mortalidad que el menos regular [R19].

### ALG-SUE-05 · Planificador y alarma por necesidad

```
hora_acostarse = hora_despertar − (necesidad · f) / eficiencia_habitual − latencia_habitual
```

- `f ∈ {1,00 «Máximo»; 0,85 «Rendir»; 0,70 «Mínimo»}`; eficiencia y latencia habituales = medianas de 30 noches (latencia por defecto 15 min). Redondeo a 5 min.
- Modo «Mejorar mi constancia»: `hora_acostarse_t = hora_habitual + clip(objetivo − hora_habitual, −15 min, +15 min)` (mediana de 14 noches).
- Alarma del iPhone (RF-SUE-12): `hora = clip(hora_declarada_de_dormir + latencia + necesidad / eficiencia, inicio_ventana, fin_ventana)`.

### ALG-SUE-06 · Otras métricas

- Eficiencia = dormido / tiempo en cama × 100. **Aviso**: las sesiones de Fitbit empiezan cerca del inicio detectado del sueño, así que la eficiencia sale alta; se usa sobre todo de forma relativa.
- Latencia (desde el inicio de la sesión hasta la primera fase no «despierto»), despertares (segmentos «despierto» ≥ 5 min) y vigilia intra-sueño.
- Marcadores de buena calidad de la National Sleep Foundation: eficiencia ≥ 85 %, latencia ≤ 30 min, ≤ 1 despertar > 5 min, vigilia intra-sueño ≤ 20 min [R57].
- Sueño reparador = profundo + REM (min y %). Normas por edad solo como contexto [R20]; las fases pesan **como mucho un 10–15 %** en cualquier puntuación por su exactitud limitada (§10).

### ALG-SUE-07 · Rendimiento de sueño (dial)

Como el rediseño de WHOOP de 2025, el dial combina varias dimensiones (pesos = *parámetros*):

```
Rendimiento = 0,70 · Suficiencia + 0,15 · Eficiencia_esc + 0,15 · Constancia
Eficiencia_esc = clip( (Eficiencia − 70) / (95 − 70) · 100, 0, 100 )
Constancia = SRI de 7 días (ALG-SUE-04), 0–100
```

Sin constancia disponible (F1 o < 5 pares de días): `0,82 · Suficiencia + 0,18 · Eficiencia_esc`. Bandas para el total y cada submétrica: **óptimo ≥ 85**, **suficiente 70–84**, **bajo < 70** (eficiencia: ≥ 90 / 80–89 / < 80 %; constancia: ≥ 80 / 70–79 / < 70).

## 6. Estrés (ALG-EST-01)

La Fitbit Air calcula la HRV **solo durante el sueño**; de día hay FC y pasos, pero no intervalos latido a latido, así que índices como el de Baevsky o el de Firstbeat/Garmin (que necesitan HRV latido a latido [R34][R35]) no son calculables. Se usa la **FC «no metabólica»** (FC por encima de lo esperable sin movimiento), un enfoque con respaldo en psicofisiología ambulatoria [R58][R59] — métrica «beta» [heurístico].

Por cada ventana de 5 min en vigilia:

1. **Elegible** si: 0 pasos en la ventana y en los 12 min previos (misma definición de reposo que usa [R22]); fuera del sueño; > 120 min después de un entrenamiento (*parámetros*).
2. `FC_calma` = percentil 10 de la FC de ventanas elegibles de los últimos 14 días. (v1.1: `FC_esperada(hora del día)` aprendida en días tranquilos, para descontar el ritmo circadiano.)
3. `Δ_ref = max(15 lpm, 0,25 · (FCmáx − FCR_ref))`.
4. `estrés = clip(3 · (mediana_FC_ventana − FC_calma) / Δ_ref, 0, 3)`.

Niveles (como WHOOP): 0–1 bajo · 1–2 medio · 2–3 alto. Resumen diario: media y minutos por nivel. Estrés alto sostenido: ≥ 30 min seguidos ≥ 2,5. Se valida contra autoevaluaciones puntuales (doc. 13 §6).

## 7. Monitor de salud (ALG-SAL-01)

- Rango habitual de cada vital = `μ₆₀ ± 2·σ₆₀` (robustos). **Fuera de rango** si `|z| > 2` en la dirección desfavorable (HRV baja, FCR alta, FR alta, temperatura alta, SpO₂ baja).
- **Aviso combinado** («Fisiología inusual») cuando se cumplen **≥ 2** de estas señales [heurístico, a partir de R21–R25, R60, R61]:
  - FC en reposo ≥ 4 lpm sobre su línea base **dos noches seguidas** (regla del sistema NightSignal [R60]);
  - FR ≥ 3 rpm sobre la base o `z ≥ 2` [R61];
  - temperatura `z ≥ 2`;
  - lnRMSSD `z ≤ −1,5`.
- Estas desviaciones preceden a menudo a infecciones [R21][R22][R23][R24][R25][R60], pero también las provocan el alcohol, el estrés o los viajes (≈ 1,2 días de alerta por persona sin infección en NightSignal [R60]). Por eso el mensaje nunca menciona enfermedades (RL-02): «Tus métricas nocturnas están fuera de tu rango habitual. Puede deberse a alcohol, estrés, poco descanso o un viaje. Tómatelo con calma y, si te encuentras mal, consulta a un profesional sanitario.»

## 8. Impacto de hábitos (ALG-DIA-01)

Para cada hábito `h` con respuestas en los últimos 180 días:

```
Recuperación_{t+1} = β₀ + β_h · h_t + β_c · Carga_t + β_f · FinDeSemana_t + ε
```

Mínimos cuadrados; `β_h` = efecto en puntos de recuperación; IC 95 % por *bootstrap* por bloques de 7 días (1 000 remuestreos). Solo con ≥ 5 días «sí» y ≥ 5 «no» (mismo umbral que WHOOP). Si el IC incluye 0: «Sin efecto claro todavía». No se ajusta por el sueño de esa noche porque es parte del mecanismo. Es una asociación personal, no causalidad. Los efectos medios de [R48] sirven de referencia en los textos («en otras personas el alcohol reduce la VFC en torno a un 12 %»).

## 8 bis. Análisis del día (ALG-ANA-01)

Versión **determinista** (sin IA) del análisis que pides con «Analizar mi día» (RF-ANA-01). Si el Coach está activado, recibe los mismos hechos y devuelve el mismo formato (RF-COA-18).

1. **Hechos del ciclo**, cada uno con valor, referencia (tu línea base o tu objetivo), desviación y fuente: sueño (rendimiento, suficiencia frente a la necesidad, deuda); recuperación (zona y los 2 componentes que más la mueven); carga frente a la banda objetivo; cada actividad (carga y duración y, en las carreras del Watch, distancia, ritmo frente a la mediana de tus carreras de distancia parecida —±20 %— de los últimos 60 días, FC media y minutos en Z4–Z5); estrés medio frente a tu base; vitales fuera de rango (ALG-SAL-01); hábitos del diario respondidos, con su impacto si ya se conoce (ALG-DIA-01).
2. **Relevancia**: `|z|` frente a tu base, o distancia al objetivo medida en anchos de banda. Se descartan los hechos con confianza baja.
3. **Claves**: la más relevante de cada bloque (sueño, recuperación, carga y actividad) y hasta 2 más, entre 3 y 5 en total; al menos una positiva si la hay (principio «sin culpa», doc. 11 §1).
4. **Recomendaciones por reglas**. *Esta noche*: la hora de acostarse del planificador (ALG-SUE-05), adelantada 15–30 min si la carga superó el objetivo o la deuda pasa de 60 min. *Mañana*: «suave o descanso» si la carga superó la banda o hay vitales fuera de rango; «margen para apretar» si la recuperación fue alta y la carga quedó por debajo; «mantener» en el resto.
5. **Salida**: un JSON con esquema fijo, el mismo con el que se valida la respuesta del Coach. Cada cifra procede de un hecho (RNF-CAL-02):

```json
{ "titular": "…", "datos_hasta": "2026-09-29T18:40:00+02:00",
  "claves": [ { "tono": "positivo | a_vigilar | neutro", "texto": "…", "metricas": ["sleep_performance"] } ],
  "actividades": [ { "tipo": "carrera", "distancia_km": 8.2, "ritmo_min_km": "5:12", "carga": 13.4,
                     "fuentes": ["apple_watch", "fitbit_air"] } ],
  "esta_noche": "…", "manana": "…",
  "datos_usados": [ { "metrica": "hrv_rmssd", "fecha": "2026-09-29", "fuente": "fitbit_air" } ] }
```

## 9. Edad fisiológica y ritmo de envejecimiento (ALG-EDA)

### ALG-EDA-01 · Edad fisiológica

Estimación orientativa (F3, «beta») de cuántos años «suma o resta» cada factor, convirtiendo razones de riesgo (HR) de mortalidad por cualquier causa en años con la ley de Gompertz: la mortalidad adulta se duplica aproximadamente cada 8 años [R33]. Es el mismo enfoque general que describe WHOOP para *WHOOP Age*, con fuentes abiertas [heurístico]:

```
Δaños_i = 8 · log₂(HR_i)            (p. ej. +10 lpm de FCR ≈ +1,0 año; +1 MET ≈ −1,6 años)
Δaños_i ← clip(0,5 · Δaños_i, −5, +5)          (encogimiento por solapamiento y confusión)
Edad fisiológica = edad cronológica + clip(Σ Δaños_i, −10, +10)
```

Medias de **180 días**, recalculada **cada semana**; disponible con ≥ 21 días válidos de los últimos 31 y «calibrada» a los 90 días (RF-EDA-02). La HRV no se usa (depende mucho del dispositivo y no hay razones de riesgo comparables para RMSSD nocturno de muñeca).

| Factor | Dato de la app | Relación de referencia |
|---|---|---|
| Forma cardiorrespiratoria | VO₂ máx. frente a la referencia de su edad y sexo | Cada MET (3,5 ml/kg/min) adicional ⇒ ≈ 13 % menos mortalidad (RR 0,87) [R28]; forma élite vs baja HR 0,20, sin techo [R27] |
| Pasos diarios | Media de pasos/día | HR 0,60 / 0,55 / 0,47 para los cuartiles 2–4 frente al 1; meseta en 6 000–8 000 pasos (≥ 60 años) u 8 000–10 000 (< 60) [R29] |
| FC en reposo | Media de FCR | RR 1,09 por cada +10 lpm [R30] |
| Actividad moderada y vigorosa | Minutos/semana en zonas 1–3 y 4–5 | Mayor beneficio al cumplir 150–300 min moderados o 75–150 vigorosos, y más [R32] |
| Fuerza | Minutos/semana de fuerza registrados | Beneficio máximo con 30–60 min/semana [R43] |
| Duración del sueño | Media de horas dormidas | Curva en U: RR 1,12 (corto) y 1,30 (largo) [R31] |
| Regularidad del sueño | SRI medio | Más regularidad ⇒ menos mortalidad, más que la duración [R19] |

Además se muestra la **«edad de forma física»** clásica: la edad a la que el VO₂ máx. de referencia de su sexo iguala al del usuario, interpolando las tablas de referencia del estudio HUNT (p. ej. 54,4 y 43,0 ml/kg/min a los 20–29 años en hombres y mujeres, con un descenso de unos 3,5 por década) [R62][R26].

**Incertidumbre**: los VO₂ máx. estimados por *wearables* tienen límites de concordancia de ≈ ±10 ml/kg/min [R69], lo que equivale a decenas de años de «edad de forma física» para una sola persona. Por eso se muestran **bandas y tendencias**, nunca una cifra aislada como verdad.

Alternativa futura: edad biológica de Klemera–Doubal [R63] (requiere regresiones de referencia poblacional para cada biomarcador).

### ALG-EDA-02 · VO₂ máx. estimado sin ejercicio

El Apple Watch estima el VO₂ máx. en carreras y caminatas al aire libre, y Google solo con carreras al aire libre con GPS. Si no hay valor de ninguno de los dos en 180 días (ALG-FUS-06), se puede usar el modelo sin ejercicio del estudio HUNT [R44], que necesita **perímetro de cintura** y un **índice de actividad física** autodeclarado (frecuencia, duración e intensidad) además de edad, sexo y FC en reposo. Esos dos datos son **opcionales** en el perfil (F3); si faltan, el factor de forma física se omite y se indica.

> **Estado (v0.1.0):** no implementado. No se pudieron verificar los coeficientes publicados del modelo HUNT, así que, sin VO₂ máx. del Apple Watch ni de Google, la edad fisiológica omite el factor de forma física y lo indica (`omittedFitness`). Se añadirá cuando se validen los coeficientes.

### ALG-EDA-03 · Ritmo de envejecimiento

```
Ritmo = (EdadF(t) − EdadF(t − 30 días)) / (30 / 365)
```

1,0 = la edad fisiológica avanza al ritmo del calendario; 0 = se mantiene; negativo = disminuye (concepto de ritmo de envejecimiento como pendiente de la edad biológica [R64]). Se muestra recortado a [−3, 3] y suavizado (media de 4 semanas).

## 10. Exactitud esperable de las entradas

No hay aún validaciones publicadas de la **Fitbit Air** en concreto; lo siguiente procede de otros modelos Fitbit y de *wearables* similares:

| Dato | Evidencia | Consecuencia de diseño |
|---|---|---|
| Sueño/vigilia | Fitbit con fases vs polisomnografía: sin sesgo significativo en tiempo total, eficiencia ni vigilia; sensibilidad 0,95–0,96, especificidad 0,58–0,69 [R37]; los dispositivos empeoran en noches alteradas [R36] | La duración es fiable; la vigilia intra-sueño, menos |
| Fases | Charge 2: ligero 0,81, profundo 0,49, REM 0,74; sobreestima ligero (+34 min) e infraestima profundo (−24 min) [R38]; algoritmo de Fitbit: 69 % de acierto por época, κ 0,52 [R65] | Fases con peso ≤ 10–15 %; sin «notas» por fase |
| FC | Error ≈ 30 % mayor en actividad que en reposo [R66] | Filtros de artefactos; edición de actividades |
| FC del Apple Watch en ejercicio | El de menor error de FC (y de gasto energético) entre siete relojes y pulseras en laboratorio, aunque ninguno midió bien el gasto (error > 20 %) [R73] | Manda en sus entrenamientos (ALG-FUS-03), validado con tus carreras |
| HRV | La variabilidad del pulso óptico es adecuada en reposo y sueño, no en movimiento [R67] | HRV solo nocturna y relativa a la base |
| SpO₂ | Fitbit Sense 2 en pacientes: sesgo +1,7 %, CCI 0,47 [R70]; la oximetría falla más en pieles oscuras [R68] | SpO₂ solo como tendencia y con peso mínimo |
| VO₂ máx. | Límites de concordancia ≈ ±10 ml/kg/min [R69] | Bandas y tendencias (ALG-EDA-01) |
| Calorías | Error ≥ 20 % habitual | Fuera de la carga |

Por todo ello, cada puntuación muestra su **confianza** (RNF-CAL-01), todo es relativo a la línea base propia y la validación con tus propios datos (doc. 13 §6) es parte del producto.

## 11. Calendario de calibración

| Función | Disponible con | Confianza plena con |
|---|---|---|
| Vitales de la noche (valores) | 1 noche | — |
| Suficiencia, eficiencia, fases | 1 noche | — |
| **Recuperación** (número y zona) | 4 noches válidas | 14 noches |
| Constancia (SRI) y rendimiento de sueño completo | 5 pares de días (≈ 6 días) | 7 días |
| Carga del ciclo | 1 ciclo (con FC en reposo de Google) | 7 ciclos |
| Carga objetivo | 7 ciclos | 28 ciclos |
| Estrés | 3 días de vigilia con FC | 14 días |
| Rangos del monitor de salud | 14 noches | 60 noches |
| Necesidad de sueño personalizada | 8 noches «libres» | 30 noches |
| Carga aguda/crónica | 28 días | — |
| Impacto de hábitos | ≥ 5 días «sí» y ≥ 5 «no» | ≥ 20 y ≥ 20 |
| Edad fisiológica | 21 días válidos en 31 | 90 días |

Con la importación inicial de 90 días de historial (RF-SYN-01), si ya llevabas la pulsera casi todo está calibrado desde el primer día.

## 12. Parámetros iniciales (`algorithm_version = 0.1.0`)

```json
{
  "baseline": { "short_window": 30, "long_window": 60, "min_nights": 4, "full_nights": 14,
                "hrv_source": "deep_if_min_20_else_avg",
                "sd_floor": { "ln_rmssd": 0.05, "rhr": 1.0, "resp_rate": 0.3, "skin_temp": 0.1, "spo2": 0.5 } },
  "recovery": { "w_hrv": 0.55, "w_rhr": 0.25, "w_sleep": 0.20, "w_penalties": 0.10,
                "hrv_z_cap_high": 1.0, "sleep_anchor": 85, "sleep_scale": 10,
                "c0": -0.15, "s_initial": 0.8, "s_method": "sqrt_wRw_after_30_nights",
                "zones": { "high": 67, "low": 33 } },
  "strain": { "x_min": 0.30, "require_motion": false, "tau": 100, "gamma": 0.8,
              "banister_mode": "sex_specific",
              "banister": { "male": [0.64, 1.92], "female": [0.86, 1.67], "unspecified": [0.75, 1.795] },
              "kappa_srpe": 0.2, "target_k": 3, "target_half_width": 1.5, "target_bounds": [4, 19],
              "ewma_acute_days": 7, "ewma_chronic_days": 28 },
  "sleep": { "base_by_age": { "18-64": 480, "65+": 450 },
             "strain_adj_per_point": 5, "strain_adj_max": 45,
             "debt_repay_fraction": 0.25, "debt_repay_max": 60, "nap_credit_max": 60,
             "debt_decay": 0.85, "debt_cap": 600, "planner_factors": [1.0, 0.85, 0.70],
             "consistency_step_max_min": 15,
             "performance_weights": { "sufficiency": 0.70, "efficiency": 0.15, "consistency": 0.15 },
             "efficiency_scale": [70, 95], "bands": { "optimal": 85, "sufficient": 70 } },
  "stress": { "window_min": 5, "zero_steps_lookback_min": 12, "post_exercise_exclusion_min": 120,
              "calm_percentile": 10, "baseline_days": 14,
              "delta_ref_min_bpm": 15, "delta_ref_hrr_fraction": 0.25,
              "sustained_high": { "level": 2.5, "minutes": 30 } },
  "health_monitor": { "z_threshold": 2.0, "min_signals_for_alert": 2,
                      "rhr_delta_bpm": 4, "rhr_consecutive_nights": 2,
                      "resp_rate_delta_bpm": 3, "hrv_z_low": -1.5, "temp_z_high": 2.0 },
  "physio_age": { "gompertz_doubling_years": 8, "shrinkage": 0.5,
                  "cap_per_factor_years": 5, "cap_total_years": 10,
                  "window_days": 180, "min_valid_days": 21, "calibrated_days": 90, "pace_window_days": 30 },
  "fusion": { "match_overlap": 0.5, "min_leftover_min": 10, "hr_workout_priority": "apple_watch",
              "watch_min_samples": 2, "disagreement_bpm": 15, "disagreement_min": 5,
              "vo2max_watch_max_age_days": 60, "gps_distance_override": true, "agreement_window_runs": 10 },
  "day_analysis": { "min_keys": 3, "max_keys": 5, "run_pace_window_days": 60, "run_similar_distance": 0.2,
                    "bedtime_advance_min": [15, 30], "debt_threshold_min": 60 }
}
```

## 13. Proyectos de código abierto de referencia

Útiles para **contrastar resultados e ideas**. Regla (RL-63): el código con licencia GPL/LGPL **no se copia** (solo se estudia); el código MIT/Apache puede reutilizarse citando su licencia.

| Proyecto | Qué calcula | Licencia |
|---|---|---|
| [GoldenCheetah](https://github.com/GoldenCheetah/GoldenCheetah) | TRIMP (Banister, zonas), curva forma–fatiga 42/7 | GPL-2.0 |
| [Athlytics](https://github.com/ropensci/Athlytics) | ACWR (móvil y EWMA), TRIMP | MIT |
| [NeuroKit2](https://github.com/neuropsychology/NeuroKit) | Índices de HRV | MIT |
| [pyActigraphy](https://github.com/ghammad/pyActigraphy) · [GGIR](https://github.com/wadpac/GGIR) · [sleepreg](https://github.com/dpwindred/sleepreg) · [sri](https://github.com/mengelhard/sri) | Índice de regularidad del sueño | GPL-3.0 · Apache-2.0 · LGPL · MIT |
| [sleep-trackers-performance](https://github.com/SRI-human-sleep/sleep-trackers-performance) | Evaluación de *wearables* de sueño | GPL-3.0 |
| [AnomalyDetect](https://github.com/gireeshkbogu/AnomalyDetect) | Alertas por FC en reposo (laboratorio de [R22]) | MIT |
| [vitals](https://github.com/DocStream-Oficial/vitals) | Recuperación, carga, sueño, edad de forma física y ACWR sobre la Google Health API (proyecto pequeño de 2026, sin revisar) | MIT |
