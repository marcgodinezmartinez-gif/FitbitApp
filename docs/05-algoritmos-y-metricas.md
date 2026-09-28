# 05 · Algoritmos y métricas

Especificación de **cómo se calcula cada puntuación**. Los algoritmos de WHOOP son propietarios y no se copian (RL-62): aquí se definen equivalentes funcionales **abiertos**, construidos con métodos publicados (referencias en [referencias.md](referencias.md), citadas como [R#]).

Principios:

1. **Personalización**: casi todo se compara con la **línea base del propio usuario**, no con medias poblacionales.
2. **Transparencia**: cada puntuación guarda sus componentes y se explica en la app (RF-REC-04, RF-PER-04).
3. **Parámetros calibrables y versionados**: todos los valores numéricos marcados como *parámetro* viven en `algorithm_params` (doc. 09) y se ajustan con la validación del doc. 13 §6; la versión inicial es `0.x` (calibración) y se congela como `1.0.0` al cumplir H2.
4. **Sin cifras inventadas**: si faltan datos, estado «Calibrando» o «Datos insuficientes» (RNF-CAL-02).
5. **Determinismo**: mismas entradas + misma versión ⇒ mismo resultado (RNF-DIS-07).

Notación: `clip(x, a, b)` limita x al intervalo [a, b]; `Φ` es la función de distribución normal estándar; `ln` logaritmo natural.

---

## 0. Validez de datos (ALG-VAL)

| Regla | Valor inicial (*parámetro*) |
|---|---|
| Muestra de FC válida | 25 ≤ lpm ≤ 230; se descartan saltos > 40 lpm en ≤ 2 s sin continuidad (artefactos) |
| Minuto con FC válida | ≥ 50 % de las muestras esperadas del minuto (si la fuente da FC por minuto, el propio valor) |
| Noche válida para líneas base | Sueño principal con ≥ 180 min dormidos y HRV presente |
| Cobertura de FC nocturna | Minutos con FC válida / minutos dormidos |
| Día válido para carga | ≥ 10 h de FC válida en el ciclo (si no, confianza baja) |

## 1. Ciclo fisiológico (ALG-CIC-01)

Un ciclo va del **fin del sueño principal** de una noche al fin del sueño principal de la siguiente (doc. 08 §4.3). El ciclo «abierto» es el actual. Si no se detecta sueño principal en 30 h, se crea un ciclo de reserva 04:00–04:00 hora local (`is_fallback = true`). Siestas y actividades pertenecen al ciclo en el que empiezan.

## 2. Líneas base (ALG-BAS-01)

**Entradas nocturnas** (tipos de la Google Health API, doc. 03 §4):

| Métrica | Origen | Nota |
|---|---|---|
| RMSSD | `daily-heart-rate-variability`: RMSSD en **sueño profundo** si hay ≥ 20 min de sueño profundo; si no, RMSSD medio de la noche (*parámetro* `hrv_source`) | El sueño profundo es la condición más estable (WHOOP también pondera el sueño de ondas lentas); se valida en la calibración cuál de los dos es más estable para el usuario (menor CV) |
| FCR | `daily-resting-heart-rate` | Diaria |
| FR | `daily-respiratory-rate` | Nocturna |
| Temp | `daily-sleep-temperature-derivations` (temperatura nocturna absoluta) | Nuestra propia línea base; la base de 30 días de Google se guarda solo como referencia |
| SpO₂ | `daily-oxygen-saturation` (media nocturna) | |

Para cada métrica nocturna `m ∈ {lnRMSSD, FCR, FR, Temp, SpO₂}` y cada noche `t`:

- Ventana **corta**: las 30 noches válidas anteriores a `t` (sin incluir `t`). Ventana **larga**: 60 noches (rangos del monitor de salud).
- Estadísticos **robustos**: `μ = mediana`, `σ = 1,4826 · MAD`, con un **suelo** para evitar divisiones por valores minúsculos (*parámetros*): lnRMSSD 0,05; FCR 1 lpm; FR 0,3 rpm; Temp 0,1 °C; SpO₂ 0,5 %.
- Calibración: con **n < 4** noches no hay línea base (no hay recuperación); **4 ≤ n < 14** ⇒ confianza como máximo «media»; **n ≥ 14** ⇒ confianza plena.
- Además: media móvil de 7 días de lnRMSSD y su coeficiente de variación (CV = DE₇ / media₇), útiles para tendencias y el Coach [R1][R2].

Se usa **ln(RMSSD)** porque el RMSSD tiene distribución asimétrica y el logaritmo estabiliza la varianza; es la práctica habitual en monitorización con HRV [R1][R2][R3].

## 3. Recuperación (ALG-REC-01)

Entradas de la noche `t`: RMSSD nocturno (ms), FC en reposo (lpm), **suficiencia** de sueño SP (%, ALG-SUE-02), FR (rpm), temperatura cutánea nocturna (°C), SpO₂ media (%).

**Paso 1 — puntuaciones z frente a la línea base corta** (cada una recortada a [−3, 3]):

| Componente | Fórmula | Sentido |
|---|---|---|
| HRV | `z_hrv = (ln RMSSD_t − μ) / σ` | Más alto = mejor |
| FC en reposo | `z_fcr = −(FCR_t − μ) / σ` | Más baja = mejor |
| Sueño | `z_sue = clip((SP_t − 85) / 10, −3, 1,5)` | Anclado a una suficiencia absoluta (la necesidad ya es personal): 85 % neutro |
| FR | `z_fr = −max(0, (FR_t − μ) / σ)` | Solo penaliza subidas |
| Temperatura | `z_tmp = −max(0, (Temp_t − μ) / σ)` | Solo penaliza subidas |
| SpO₂ | `z_spo2 = min(0, (SpO₂_t − μ) / σ)` | Solo penaliza bajadas |

**Paso 2 — compuesto**:

```
C = 0,55·z_hrv + 0,25·z_fcr + 0,20·z_sue  +  0,10·(z_fr + z_tmp + z_spo2)
```

Pesos iniciales (*parámetros*). Los tres primeros suman 1 y reflejan que HRV y FC en reposo son los marcadores con más respaldo para la preparación diaria [R1][R3][R4][R5]; los tres últimos solo restan (señales de posible sobrecarga o malestar [R21][R22][R23]). Si falta un componente secundario (FR, Temp, SpO₂) su término vale 0 y la confianza baja un nivel; si falta el sueño se reparte su peso entre HRV y FCR; **sin HRV no hay recuperación** (RF-REC-05).

**Paso 3 — escala 0–100**:

```
Recuperación = round( 100 · Φ( (C − c₀) / s ) )
```

con `c₀ = −0,15` y `s = 0,8` (*parámetros*): un día «normal» (C ≈ 0) da ≈ 57 % (la media publicada de los miembros de WHOOP es ≈ 58 %, lo que da una referencia de calibración); C ≈ +0,20 marca el paso a zona alta (67 %) y C ≈ −0,50 a zona baja (33 %). `s` se re-estima en la calibración como la desviación típica de `C` en el histórico del propietario.

**Zonas**: alta 67–100 · media 34–66 · baja 0–33.

**Confianza**: alta si n ≥ 14, cobertura de FC nocturna ≥ 70 % y los 3 componentes principales presentes; media si 4 ≤ n < 14 o falta un secundario; baja si cobertura < 50 % o menos de 4 h dormidas.

**Explicación en la app** (RF-REC-04): se muestra cada `z` convertido a lenguaje natural («Tu VFC está un 12 % por encima de tu media», usando `exp(ln RMSSD_t − μ) − 1`).

**Extensión v1.1** (opcional): término de tendencia `z_tend = (media₇ lnRMSSD − μ₆₀) / σ₆₀` para detectar fatiga acumulada que un solo día no refleja [R1][R4].

## 4. Carga — «Strain» (ALG-CAR)

### ALG-CAR-06 · FC máxima, FC de reserva y zonas

- `FCmáx_est = 208 − 0,7 · edad` [R10] (la fórmula de Gellish, `207 − 0,7 · edad`, que usa WHOOP, es prácticamente equivalente [R42]). Se sustituye por la **máxima observada** si en ≥ 2 entrenamientos distintos de los últimos 180 días la mediana móvil de 30 s (FC de 1 s del entrenamiento) supera la estimada en ≥ 3 lpm (el usuario confirma), o por un valor manual.
- `FCR_ref` = media de 7 días de la FC en reposo.
- Fracción de FC de reserva de cada minuto: `x = clip((FC − FCR_ref) / (FCmáx − FCR_ref), 0, 1)` [R11].
- Zonas por defecto (% de FC de reserva): Z1 50–60 · Z2 60–70 · Z3 70–80 · Z4 80–90 · Z5 90–100; alternativa por % de FC máx. o personalizada (RF-CAR-03).

### ALG-CAR-01 · Carga del ciclo (0–21)

1. **Impulso de entrenamiento por minuto** (TRIMP de Banister [R6][R7]):

   ```
   y = x · a · e^(b·x)     si x ≥ x_min,   si no 0
   ```

   con `(a, b) = (0,64; 1,92)` en hombres y `(0,86; 1,67)` en mujeres; sexo no indicado: `(0,75; 1,795)`. `x_min = 0,25` (*parámetro*) evita que la simple vigilia sedentaria acumule carga.

2. **Carga bruta** `L = Σ y` sobre los minutos del ciclo (unidades TRIMP), usando la FC media de cada minuto (`hr_minute`, obtenida con `rollUp` de 60 s).

3. **Escala 0–21** (saturante, más difícil de subir cuanto más alta, como la escala de WHOOP inspirada en Borg):

   ```
   Carga = 21 · (1 − e^(−L / τ)),   τ = 100 (parámetro)
   ```

   Comprobación con τ = 100 (FCR 55, FCmáx 185, hombre): día sedentario con 60 min de paseo (L ≈ 25–35) ⇒ 5–6; carrera de 45 min a 150 lpm (L ≈ 85) ⇒ ≈ 12; carrera dura de 60 min a 165 lpm (L ≈ 165) ⇒ ≈ 17; maratón de 3 h 30 a 160 lpm (L ≈ 510) ⇒ ≈ 20,9. Coincide con los objetivos de calibración del doc. 13 §6.

4. Se muestra con 1 decimal. Rangos de lectura: 0–9 ligera · 10–13 moderada · 14–17 alta · 18–21 máxima.

### ALG-CAR-02 · Carga de actividad

Mismo cálculo limitado a los minutos de la actividad. Por la escala saturante, las cargas de actividad **no se suman** para dar la del ciclo (se suma `L`, no la puntuación).

### ALG-CAR-05 · Carga muscular (fuerza) con sRPE

Para actividades de fuerza con RPE: `sRPE = RPE (0–10) × minutos` [R12]. Carga bruta de la actividad `L_act = max(L_cardio_act, κ · sRPE)` con `κ = 0,2` (*parámetro*); al ciclo se añade `max(0, κ · sRPE − L_cardio_act)`. Así, una sesión de fuerza de 60 min con RPE 7 suma ≈ 84 TRIMP (≈ 12 de carga) aunque la FC haya sido moderada.

### ALG-CAR-03 · Carga objetivo

```
centro = S̄₂₈ + k · (Recuperación − 50) / 50        k = 3 (parámetro)
banda  = [centro − 1,5 ; centro + 1,5] ∩ [4 ; 19]
```

`S̄₂₈` = media de la carga diaria de los últimos 28 ciclos. Modos opcionales del usuario: «Mantener» (0), «Progresar» (+1), «Descargar» (−2). Ejemplo: media 11, recuperación 90 % ⇒ 11,9–14,9; recuperación 20 % ⇒ 7,7–10,7.

### ALG-CAR-04 · Carga aguda, crónica y relación entre ambas

Medias móviles exponenciales de la carga bruta diaria [R13]: `λ_a = 2/(7+1)`, `λ_c = 2/(28+1)`; `EWMA_t = λ·L_t + (1−λ)·EWMA_{t−1}`; `ACWR = EWMA_a / EWMA_c`. Lectura: < 0,8 «descarga», 0,8–1,3 «estable», > 1,5 «aumento brusco». Se presenta **solo como indicador de cambios de carga**, no como predictor de lesiones, por las limitaciones metodológicas conocidas [R14][R15].

## 5. Sueño (ALG-SUE)

### ALG-SUE-00 · Sueño principal y siestas

Si la API marca el sueño principal, se usa. Si no: sueño principal = la sesión más larga con ≥ 180 min dormidos que termina entre las 03:00 y las 15:00 locales; el resto de sesiones ≥ 15 min son siestas.

### ALG-SUE-01 · Necesidad de sueño

```
necesidad = base + ajuste_carga + ajuste_deuda − crédito_siestas
```

| Término | Definición (valores iniciales = *parámetros*) |
|---|---|
| `base` | Por edad según recomendaciones de consenso [R16][R17]: 18–25 años 8 h; 26–64 8 h; ≥ 65 7 h 30. Editable por el usuario. Personalización (F3): tras ≥ 8 noches «libres» (anteriores a días sin hora de despertar fijada), `base = 0,5·base₀ + 0,5·mediana(sueño en noches libres)`, recortada a [6 h 30, 9 h 30] |
| `ajuste_carga` | `5 min × max(0, Carga_ciclo_anterior − S̄₂₈)`, máx. 45 min |
| `ajuste_deuda` | `0,25 × deuda_actual`, máx. 60 min |
| `crédito_siestas` | Minutos dormidos en siestas del ciclo, máx. 60 min |

### ALG-SUE-02 · Suficiencia de sueño

`SP = min(100, 100 · minutos_dormidos / necesidad)`, donde minutos dormidos = ligero + profundo + REM (o «dormido» si no hay fases). Es la entrada de sueño de la recuperación (ALG-REC-01).

### ALG-SUE-03 · Deuda de sueño

```
deuda_t = clip( ρ · deuda_{t−1} + (necesidad_sin_deuda_t − dormido_t), 0, 600 min )
```

con `ρ = 0,85` (la deuda antigua pierde peso; semivida ≈ 4,3 noches) y `necesidad_sin_deuda = base + ajuste_carga − crédito_siestas` (evita contar la deuda dos veces). Dormir más de lo necesario reduce la deuda.

### ALG-SUE-04 · Constancia (índice de regularidad del sueño, SRI)

Índice de regularidad de Phillips et al. [R18] sobre los últimos 7 días, con estado dormido/despierto por minuto (incluye siestas):

```
SRI = −100 + (200 / (M · (N − 1))) · Σ_{i=1}^{N−1} Σ_{j=1}^{M} δ(s_{i,j}, s_{i+1,j})
```

`M` = 1 440 minutos/día, `N` = días con datos válidos, `δ = 1` si el estado coincide 24 h después. Se muestra 0–100 (valores negativos ⇒ 0). Requiere ≥ 5 pares de días válidos. La regularidad se asocia a mejores resultados de salud incluso más que la duración [R19].

### ALG-SUE-05 · Planificador y alarma por necesidad

```
hora_acostarse = hora_despertar − (necesidad · f) / eficiencia_habitual − latencia_habitual
```

`f ∈ {1,00 «Máximo»; 0,85 «Rendir»; 0,70 «Mínimo»}`; eficiencia y latencia habituales = medianas de 30 noches (latencia por defecto 15 min). Redondeo a 5 min.
Modo «Mejorar mi constancia»: `hora_acostarse_t = hora_habitual + clip(objetivo − hora_habitual, −15 min, +15 min)`, donde `hora_habitual` es la mediana de las horas de acostarse de 14 noches; converge de forma gradual hacia la hora objetivo.
Alarma del móvil (RF-SUE-12): `hora = clip(hora_declarada_de_dormir + latencia + necesidad / eficiencia, inicio_ventana, fin_ventana)`.

### ALG-SUE-06 · Otras métricas

Eficiencia = dormido / tiempo en cama × 100; sueño reparador = profundo + REM (min y %); latencia = desde el inicio de la sesión hasta la primera fase no «despierto»; despertares = segmentos «despierto» ≥ 5 min. Referencias normativas de proporciones por edad en [R20]; solo como contexto, sin «notas» a las fases porque la estadificación por pulsera tiene una exactitud limitada frente a la polisomnografía [R36][R37].

### ALG-SUE-07 · Rendimiento de sueño (dial)

Como el rediseño de WHOOP de 2025, el dial combina varias dimensiones (pesos = *parámetros*):

```
Rendimiento = 0,70 · Suficiencia + 0,15 · Eficiencia_esc + 0,15 · Constancia
Eficiencia_esc = clip( (Eficiencia − 70) / (95 − 70) · 100, 0, 100 )
Constancia = SRI de 7 días (ALG-SUE-04), 0–100
```

Sin constancia disponible (F1 o < 5 pares de días), se renormaliza: `0,82 · Suficiencia + 0,18 · Eficiencia_esc`. Bandas para el total y cada submétrica: **óptimo ≥ 85**, **suficiente 70–84**, **bajo < 70** (eficiencia: ≥ 90 / 80–89 / < 80 %; constancia: ≥ 80 / 70–79 / < 70).

## 6. Estrés (ALG-EST-01)

La Fitbit Air calcula la HRV **durante el sueño**; durante el día solo se dispone de la FC y del movimiento, así que el estrés diurno se estima a partir de la FC (versión «beta»). Si en el futuro la API ofrece HRV diurna, se sustituirá por un índice basado en HRV (p. ej. el índice de estrés de Baevsky o el enfoque de Firstbeat [R34][R35]).

Por cada ventana de 5 min en vigilia:

1. **Exclusiones**: sueño; entrenamientos y los 10 min posteriores; ventanas con > 100 pasos (≈ caminar) si hay pasos por minuto.
2. `FC_calma` = percentil 10 de la FC de ventanas válidas (sin exclusiones) de los últimos 14 días en vigilia.
3. `Δ_ref = max(15 lpm, 0,2 · (FCmáx − FCR_ref))`.
4. `estrés = clip(3 · (mediana_FC_ventana − FC_calma) / Δ_ref, 0, 3)`.

Niveles: 0–1 bajo · 1–2 medio · 2–3 alto. Resumen diario: media ponderada por tiempo y minutos por nivel. Aviso de estrés alto sostenido: ≥ 30 min seguidos ≥ 2,5 (*parámetros*).

## 7. Monitor de salud (ALG-SAL-01)

- Rango habitual de cada vital = `μ₆₀ ± 2·σ₆₀` (robustos, ventana larga).
- **Fuera de rango** si `|z| > 2` en la dirección desfavorable (HRV baja, FCR alta, FR alta, temperatura alta, SpO₂ baja).
- **Aviso combinado** si ≥ 2 vitales fuera de rango la misma noche. Las desviaciones conjuntas de FC en reposo, FR y temperatura son señales documentadas de alteración fisiológica [R21][R22][R23][R24][R25], pero la app **no** interpreta su causa (RL-01/02): mensaje de bienestar y sugerencia de descanso.

## 8. Impacto de hábitos (ALG-DIA-01)

Para cada hábito `h` con respuestas en los últimos 180 días:

```
Recuperación_{t+1} = β₀ + β_h · h_t + β_c · Carga_t + β_f · FinDeSemana_t + ε
```

Mínimos cuadrados; `β_h` = efecto en puntos de recuperación; IC 95 % por *bootstrap* por bloques de 7 días (1 000 remuestreos). Solo se muestra con ≥ 5 días «sí» y ≥ 5 «no». Si el IC incluye 0: «Sin efecto claro todavía». No se ajusta por el sueño de esa noche porque es parte del mecanismo (p. ej. el alcohol empeora el sueño). Se advierte que es una asociación personal, no causalidad demostrada.

## 9. Edad fisiológica y ritmo de envejecimiento (ALG-EDA)

### ALG-EDA-01 · Edad fisiológica

Estimación orientativa (F3, «beta») de cuántos años «suma o resta» cada factor, convirtiendo razones de riesgo (*hazard ratios*, HR) de mortalidad por cualquier causa publicadas en años mediante la ley de Gompertz (el riesgo de mortalidad adulta se duplica aproximadamente cada 8 años [R33]). Es el mismo enfoque general que describe WHOOP para *WHOOP Age* (razones de riesgo publicadas + corrección de solapamiento), implementado aquí con fuentes abiertas:

```
Δaños_i = ln(HR_i) / β,     β = ln 2 / 8 ≈ 0,087 por año
Edad fisiológica = edad cronológica + η · Σ Δaños_i,   η = 0,5 (solapamiento entre factores), recortado a ±15 años
```

Medias de **180 días**, recalculada **cada semana**; disponible con ≥ 21 días válidos en los últimos 31 y «calibrada» a los 90 días (RF-EDA-02). La HRV no se usa (depende mucho del dispositivo y la edad, y no hay razones de riesgo comparables para RMSSD nocturno de muñeca).

| Factor | Dato de la app | Relación dosis-respuesta de referencia |
|---|---|---|
| Forma cardiorrespiratoria | VO₂ máx. (Google o ALG-EDA-02) frente a la media de su edad y sexo | Cada MET (3,5 ml/kg/min) adicional ⇒ ≈ 13 % menos mortalidad [R28]; relación sin techo en [R27] |
| Pasos diarios | Media de pasos/día | Riesgo decreciente hasta 6 000–8 000 (≥ 60 años) u 8 000–10 000 (< 60) pasos/día [R29] |
| FC en reposo | Media de FCR | ≈ +9 % de mortalidad por cada 10 lpm [R30] |
| Actividad moderada y vigorosa | Minutos/semana en zonas 1–3 y en zonas 4–5 | Mayor beneficio al cumplir 150–300 min/semana moderados o 75–150 vigorosos, y más [R32] |
| Fuerza | Minutos/semana de fuerza registrados | Beneficio con 30–60 min/semana [R43] |
| Duración del sueño | Media de horas dormidas | Curva en U: riesgo mayor por debajo de 7 h y por encima de 9 h [R31] |
| Regularidad del sueño | SRI medio | Mayor regularidad ⇒ menor mortalidad, independientemente de la duración [R19] |

Los valores `HR_i` de cada tramo se fijan en `algorithm_params` a partir de las tablas de cada estudio, citando tabla y población. En la app se muestran el intervalo y el impacto de cada factor (verde/gris/ámbar).

### ALG-EDA-03 · Ritmo de envejecimiento

```
Ritmo = (EdadF(t) − EdadF(t − 30 días)) / (30 / 365)
```

1,0 = la edad fisiológica avanza al mismo ritmo que el calendario; 0 = se mantiene; negativo = disminuye. Se muestra recortado a [−3, 3] y suavizado (media de las últimas 4 semanas).

### ALG-EDA-02 · VO₂ máx. estimado sin ejercicio

Google solo actualiza el VO₂ máx. con carreras al aire libre con GPS. Si no hay valor de Google en los últimos 180 días, se estima con un **modelo de predicción sin ejercicio** publicado (p. ej. el del estudio HUNT [R44]: edad, sexo, perímetro de cintura o IMC, FC en reposo y nivel de actividad), usando los coeficientes del artículo y marcando el valor como «estimado».

## 10. Exactitud esperable de las entradas

Las pulseras de muñeca son razonablemente fiables para distinguir sueño/vigilia y para la FC en reposo, pero menos para las fases del sueño y la vigilia intra-sueño, y la HRV de muñeca por PPG difiere de la del ECG [R36][R37][R38]. Consecuencias de diseño:

- Todas las métricas son **relativas a la línea base personal** (los sesgos constantes del sensor se cancelan en gran medida).
- No se dan umbrales absolutos de fases del sueño ni diagnósticos.
- Se muestra la **confianza** de cada puntuación (RNF-CAL-01).

## 11. Calendario de calibración

| Función | Disponible con | Confianza plena con |
|---|---|---|
| Vitales de la noche (valores) | 1 noche | — |
| Suficiencia, eficiencia, fases | 1 noche | — |
| **Recuperación** (número y zona) | 4 noches válidas | 14 noches |
| Constancia (SRI) y rendimiento de sueño completo | 5 pares de días (≈ 6 días) | 7 días |
| Carga del ciclo | 1 ciclo (con FC en reposo de Google) | 7 ciclos (FCR de referencia) |
| Carga objetivo | 7 ciclos | 28 ciclos |
| Estrés | 3 días de vigilia con FC | 14 días |
| Rangos del monitor de salud | 14 noches | 60 noches |
| Necesidad de sueño personalizada | 8 noches «libres» | 30 noches |
| Relación carga aguda/crónica | 28 días | — |
| Impacto de hábitos | ≥ 5 días «sí» y ≥ 5 «no» | ≥ 20 y ≥ 20 |
| Edad fisiológica | 21 días válidos en 31 | 90 días |

Con el *backfill* de 90 días (RF-SYN-01), un usuario que ya llevaba la pulsera tiene casi todo calibrado desde el primer día.

## 12. Parámetros iniciales (`algorithm_version = 0.1.0`)

```json
{
  "baseline": { "short_window": 30, "long_window": 60, "min_nights": 4, "full_nights": 14,
                "hrv_source": "deep_if_min_20_else_avg",
                "sd_floor": { "ln_rmssd": 0.05, "rhr": 1.0, "resp_rate": 0.3, "skin_temp": 0.1, "spo2": 0.5 } },
  "recovery": { "w_hrv": 0.55, "w_rhr": 0.25, "w_sleep": 0.20, "w_penalties": 0.10,
                "sleep_anchor": 85, "sleep_scale": 10, "c0": -0.15, "s": 0.8,
                "zones": { "high": 67, "low": 33 } },
  "strain": { "x_min": 0.25, "tau": 100,
              "banister": { "male": [0.64, 1.92], "female": [0.86, 1.67], "unspecified": [0.75, 1.795] },
              "kappa_srpe": 0.2, "target_k": 3, "target_half_width": 1.5, "target_bounds": [4, 19] },
  "sleep": { "base_by_age": { "18-25": 480, "26-64": 480, "65+": 450 },
             "strain_adj_per_point": 5, "strain_adj_max": 45,
             "debt_repay_fraction": 0.25, "debt_repay_max": 60, "nap_credit_max": 60,
             "debt_decay": 0.85, "debt_cap": 600, "planner_factors": [1.0, 0.85, 0.70],
             "consistency_step_max_min": 15,
             "performance_weights": { "sufficiency": 0.70, "efficiency": 0.15, "consistency": 0.15 },
             "efficiency_scale": [70, 95], "bands": { "optimal": 85, "sufficient": 70 } },
  "stress": { "window_min": 5, "steps_exclusion": 100, "post_exercise_exclusion_min": 10,
              "calm_percentile": 10, "delta_ref_min_bpm": 15, "delta_ref_hrr_fraction": 0.2,
              "sustained_high": { "level": 2.5, "minutes": 30 } },
  "health_monitor": { "z_threshold": 2.0, "min_flags_for_alert": 2 },
  "physio_age": { "gompertz_doubling_years": 8, "overlap_shrinkage": 0.5, "cap_years": 15,
                  "window_days": 180, "min_valid_days": 21, "calibrated_days": 90, "pace_window_days": 30 }
}
```
