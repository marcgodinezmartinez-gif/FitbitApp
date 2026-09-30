# 19 · Esferas del Apple Watch

> Estado: implementado en la v0.1 (app del reloj, complicaciones y editor en el iPhone). Código: `FaceKit` (modelo, textos y geometría, probado en Linux), `FaceUI` (dibujo compartido), `Watch/`, `WatchWidgets/` y `App/Features/Faces/`.

## 1. Qué es y qué no puede ser

Apple no deja que ninguna app instale esferas propias en el Apple Watch: solo existen las suyas, y watchOS 27 (septiembre de 2026) tampoco lo ha abierto. Las esferas del Ultra (Modular Ultra y Wayfinder) además están reservadas al Ultra y no se pueden poner en otro modelo, ni compartiéndolas.

Por eso Recupera hace dos cosas:

1. **Tus esferas dentro de la app del reloj.** Las diseñas en el iPhone y se ven a pantalla completa en la app de Recupera del Watch, con datos en vivo y la pantalla siempre activa.
2. **Complicaciones para las esferas de Apple.** Recuperación, tu día y un acceso directo a tus esferas.

La pega de la primera es que es una app, no una esfera del sistema:

- Se queda puesta hasta una hora con la muñeca bajada si en el reloj eliges *Ajustes › General › Volver al reloj › Recupera › Después de 1 hora*.
- Pasado ese rato, o al pulsar la corona, vuelve tu esfera de Apple. Con la complicación «Mis esferas» se vuelve a la tuya con un toque.

## 2. Plantillas

| Plantilla | Qué es | Huecos | Bisel |
|---|---|---|---|
| **Ultra modular** | Hora grande arriba a la izquierda y los segundos corriendo por el borde de la pantalla (al estilo del Modular Ultra) | 1 redondo arriba, 1 grande en el centro, 3 redondos abajo | Segundos, recuperación, carga, pasos o ninguno |
| **Explorador** | Agujas con bisel de brújula o de minutos (al estilo del Wayfinder) | 4 esquinas y 3 subesferas | Brújula (gira con el rumbo), minutos, recuperación o ninguno |
| **Recuperación** | La hora y tu recuperación en un anillo grande, con la carga y el sueño por dentro | 1 línea arriba y 2 esquinas abajo | — |
| **Clásica** | Agujas con bastones, números, romanos o solo las cuatro principales | 1 redondo arriba y 1 abajo | Minutos o ninguno |
| **Digital XL** | Horas y minutos enormes, uno encima del otro | 1 línea arriba y 1 abajo | — |

## 3. Qué se puede cambiar

- **Color** (diez de muestra o cualquiera) y **fondo**: negro, color liso oscurecido o un halo del color que se funde con el negro.
- **Letra de la hora**: ancha (como la del Ultra), redondeada, estrecha, monoespaciada, con remates o fina.
- **24 horas** y **segundos** o segundero.
- **Marcas** de las esferas de agujas.
- **Bisel** (los que admita la plantilla).
- **Qué dato va en cada hueco**. Cada dato solo se ofrece en los huecos donde cabe.
- **Empezar en modo noche.** En el reloj, girar la corona hacia arriba lo pone (todo en rojo, como en el Ultra) y hacia abajo lo quita, para cada esfera.

Las esferas se guardan en el iPhone. Desde la galería se duplican, se ordenan (el orden en que se pasan en el reloj) y se borran.

### Datos disponibles

| Dato | De dónde sale | Huecos |
|---|---|---|
| Recuperación, carga del día, sueño, resumen (las tres) | iPhone (doc. 05) | Todos (el resumen, solo grande o línea) |
| Variabilidad (VFC), FC en reposo, hora de acostarte | iPhone | Redondo, esquina, línea |
| Entreno de hoy (del plan, doc. 18 §8) y cuenta atrás a tu carrera | iPhone | Entreno: grande o línea; carrera: todos |
| Pulso (y su línea de la última hora en el hueco grande), pasos, anillos de actividad | Salud en el reloj | Pulso y pasos: todos; anillos: redondo o grande |
| Batería, fecha | Reloj | Redondo, esquina, línea |
| Brújula | Brújula del reloj | Redondo o esquina (y el bisel del Explorador) |
| El tiempo | Open-Meteo con la ubicación del reloj, cada 30 min | Todos |

Lo que falte sale como «–».

## 4. Complicaciones

Para las esferas de Apple y la Smart Stack (WidgetKit):

- **Recuperación**: aro con la cifra, esquina curvada, línea o rectangular.
- **Tu día**: rectangular con recuperación, carga y sueño en barras y el entreno de hoy; o una línea.
- **Mis esferas**: abre la app de Recupera con un toque.

Leen lo último que mandó el iPhone (App Group del reloj).

## 5. Cómo llegan al reloj

1. El iPhone manda un JSON (`WatchPayload`, con versión) con tus esferas y los datos del día en el **contexto de la app** de WatchConnectivity, que solo guarda lo último y llega en cuanto puede.
2. Se manda al abrir la app y cada vez que cambian los datos o una esfera.
3. Si hay una complicación de Recupera en la esfera y han cambiado los datos (no solo la hora de envío), además se despierta al reloj para actualizarla, dentro del cupo diario de watchOS.
4. El reloj lo guarda en su App Group (lo leen la app y las complicaciones) y pone encima lo que mide él: pulso, pasos, anillos, batería, rumbo y el tiempo.
5. Si llega un diseño que esta versión no entiende (una plantilla o un dato más nuevos), se salta o vuelve a lo de fábrica sin perder los demás.

## 6. En el reloj

- Deslizando se pasa de una esfera a otra; girando la corona, el modo noche.
- Con la muñeca bajada, la esfera se ve atenuada, sin segundero y redibujada una vez por minuto.
- Los sensores se leen una vez por minuto mientras la app está delante; la brújula, solo si alguna esfera la usa y la pantalla está activa.
- La hora del sistema, que watchOS pinta en las apps arriba a la derecha, se oculta con un modificador de SwiftUI sin documentar. Si una versión de watchOS no lo respeta, se verá encima de la esfera.

## 7. Privacidad

- **Salud (en el reloj):** solo lectura, y solo si alguna esfera enseña el pulso, los pasos o los anillos. Nada sale del reloj.
- **Ubicación (en el reloj):** solo si alguna esfera enseña el tiempo o la brújula. Se pide en el momento y no se guarda. A Open-Meteo solo van la latitud y la longitud redondeadas a tres decimales (unos 100 m), sin clave ni identificador.
- **El iPhone:** manda al reloj las cifras del día (recuperación, carga, sueño, variabilidad, reposo, hora de acostarte, entreno de hoy y carrera), nada más.

## 8. Pruebas

`FaceKitTests` (16 pruebas):

- plantillas válidas de fábrica;
- normalización de lo que no cabe;
- lectura tolerante de diseños más nuevos;
- ida y vuelta del JSON (sin los datos del reloj);
- textos en español;
- hora de 12 y 24 horas y agujas;
- geometría del bisel en el borde de una pantalla de 45 mm;
- rumbos y el tiempo de Open-Meteo.

Las capturas de CI incluyen cada plantilla en el simulador del reloj, dos en modo noche, la galería y el editor del iPhone.
