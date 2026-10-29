# Dungeon Escape

Juego de acción 2D con vista cenital, hecho en **Godot 4.7.2**. El jugador controla a un caballero que debe recorrer un calabozo de 7 salas, conseguir la llave que custodia una parca y llegar a la puerta de salida.

![Captura del juego](docs/capturas/01-juego.png)

Las capturas de la página web están en [Página web](#página-web) y el resumen de la entrega en [docs/entrega.md](docs/entrega.md).

**Descarga:** los ejecutables para Windows y Linux están en [Releases](https://github.com/Thegreenmarshadow/dungeon-escape/releases/latest).

## Cómo jugar

| Acción | Teclas | Mando | Pantalla táctil |
|---|---|---|---|
| Moverse (8 direcciones) | Flechas o W A S D | Stick izquierdo o cruceta | Joystick (mitad izquierda) |
| Atacar con la espada | Espacio o J | X | ATAQUE |
| Saltar (abismos y picos) | K o Shift | A | SALTO |
| Parry | L | B o RB | PARRY |
| Pausa | Escape | Start | Botón de pausa |
| Panel de game feel | F3 | — | — |
| Reiniciar (en las pantallas finales) | R | Back | Botones de la pantalla |

Los controles táctiles se explican en [Controles móviles](#controles-móviles).

**Objetivo:** encontrar la llave y llegar a la puerta de salida, en el extremo opuesto del mapa.

- El jugador tiene **3 corazones** de vida y 1.5 s de invulnerabilidad después de recibir daño. La vida se cuenta en **medios corazones**: un golpe de enemigo o de los picos quita un corazón entero, pero en niveles altos los enemigos pegan más fuerte (ver abajo) y pueden quitar uno y medio, dos o dos y medio. La interfaz muestra cada corazón lleno, a medias o vacío.
- Las **trampas de picos** hacen daño solo cuando los picos están levantados.
- Enemigos:

| Enemigo | Vida | Comportamiento |
|---|---|---|
| Esqueleto | 2 golpes | Patrulla entre dos puntos; si el jugador se acerca a su ruta, va hacia él y ataca con una estocada anunciada. Al recibir un golpe retrocede y tarda en volver a atacar |
| Vampiro | 3 golpes | Persigue al jugador a menos de 80 px y vuelve a su puesto si lo pierde |
| Parca (jefe) | 5 golpes | Lenta; protege la sala de la llave |

- **Esquiva:** cada enemigo puede esquivar un golpe (esqueleto 15 %, calavera 10 %, vampiro 20 %, parca 10 %): no recibe daño, da un paso atrás y aparece «¡Esquiva!». Nunca esquiva dos golpes seguidos (1 s de espera), ni mientras ataca o embiste.
- La vida de la tabla es la del nivel 1. Cada nivel suma un **8 % de la vida base** (×1.08 en el nivel 2, ×1.72 en el 10, ×8.92 en el 100; se redondea): un esqueleto aguanta 3 golpes en el nivel 10 y 18 en el 100.
- **Daño por escalones:** desde el nivel 25 cada golpe de un enemigo (comunes, especiales, la parca, los jefes y sus proyectiles o efectos) quita medio corazón más, y otro medio en el 45 y en el 65: 1.5, 2 y 2.5 corazones. Nunca más de 2.5, así ningún golpe mata con la vida llena. Los picos siempre quitan un corazón.
- **Composición:** desde el nivel 15, cada 3 niveles un enemigo común pasa a ser un especial (arquero, mago o mímico, rotando): primero los esqueletos y después los vampiros; las calaveras se quedan. El total de enemigos no cambia. Los arqueros llegan a 6, los magos a 5 y las trampas a 30 (antes 4, 3 y 18).

- **Monedas:** los enemigos pueden soltar monedas al morir (los más duros, más seguido y de más valor; la parca, casi siempre) y en cada mapa generado hay una suelta. Valen más cuanto más alto el nivel: se multiplican por la misma escala que la vida de los enemigos. Se conservan entre niveles y se reinician en cada partida.
- **Tienda:** en la pantalla de nivel superado se pueden gastar las monedas en **+1 daño** (10, 20, 30... hasta 100 monedas; hasta 10 veces por partida) o **+1 corazón** (6 monedas en el nivel 1, multiplicadas por la escala del nivel; solo si falta vida, y nunca pasa de los 3 corazones). Así las mejoras de daño siguen el ritmo de la vida de los enemigos.
- **Armas:** el caballero empieza cada partida con la espada. En la tienda se puede cambiar por la **lanza** (15 monedas: estocada larga y angosta, el doble de alcance, pero más lenta y frena al jugador al golpear) o la **daga** (25 monedas: golpea el doble de seguido, de muy cerca). El arma comprada reemplaza a la actual, se conserva entre niveles y el +1 daño se le suma igual. Los valores de cada arma están en `assets/weapons/<id>/<id>.tres` (`WeaponData`).
- La interfaz muestra los corazones (llenos, a medias o vacíos), si se tiene la llave, cuántos enemigos se eliminaron y las monedas. La pantalla de victoria incluye ese contador.

## Cómo ejecutarlo

### Opción 1: ejecutable (sin instalar Godot)

Descargar el archivo de la plataforma desde [Releases](https://github.com/Thegreenmarshadow/dungeon-escape/releases/latest) y ejecutarlo:

- **Windows:** descomprimir `dungeon-escape-windows.zip` y abrir `dungeon-escape.exe`. Si Windows SmartScreen muestra un aviso (el ejecutable no está firmado), elegir **Más información → Ejecutar de todas formas**.
- **Linux:** descomprimir `dungeon-escape-linux.tar.gz` y ejecutar `./dungeon-escape.x86_64` (si no arranca, darle permiso con `chmod +x dungeon-escape.x86_64`).

### Opción 2: abrir el proyecto en Godot

1. Instalar **Godot 4.7.2** (versión estándar, no .NET).
2. En el gestor de proyectos: **Importar** → seleccionar el archivo `project.godot`.
3. Presionar **F5** (o el botón ▶) para jugar. La escena principal es el menú, `scenes/MainMenu.tscn`; los niveles son `scenes/Level.tscn`.

## Game feel

Mejoras para que las acciones se sientan más responsivas y claras. Los parámetros del jugador son `@export` de `scripts/player.gd` (se cambian en el Inspector de `Player.tscn`); los de la cámara y el feedback son constantes al inicio de `scripts/game_feel.gd` (Autoload `GameFeel`). Pulsa **F3** durante el juego para ver un panel con los tiempos en vivo (buffer, coyote time, trauma, hit-stop).

### Capturas

| Input buffering, screenshake y feedback | Coyote time |
|---|---|
| ![Ataque guardado en el buffer mientras la espada se enfría, con hit-stop, chispas y número de daño](docs/capturas/buffer-y-feedback.png) | ![El jugador ya está sobre el abismo y todavía puede saltar](docs/capturas/coyote-time.png) |
| El panel F3 muestra un ataque guardado (`Buffer ataque: 131 / 150 ms`) mientras la espada se enfría, y «buffer» sobre el jugador cuando sale uno. El golpe anterior dejó trauma en la cámara (barra de screenshake), chispas, el enemigo en rojo y el número de daño. | El jugador ya pisa el abismo, pero le quedan 53 de los 120 ms de coyote time: si salta ahora, llega al otro lado. |

![Parry: destello, congelado y el golpe devuelto al enemigo](docs/capturas/parry.png)

Parry logrado: el texto «¡PARRY!», el juego congelado (`Hit-stop: SÍ`), la cámara con trauma 0.68 y el golpe devuelto al esqueleto.

### Input buffering

Si se pulsa una acción cuando todavía no se puede hacer, el juego la recuerda un momento y la ejecuta en cuanto se puede, en lugar de ignorarla.

| Parámetro | Valor | Qué hace |
|---|---|---|
| `attack_buffer_time` | 0.15 s | Un ataque pulsado durante el enfriamiento del arma sale solo al terminar el enfriamiento |
| `jump_buffer_time` | 0.15 s | Un salto pulsado en el aire (o mientras el jugador sale despedido) sale al aterrizar |

Con el panel F3 se ve el buffer bajando y, cuando sale una acción guardada, aparece «buffer» sobre el jugador.

### Salto, abismos y coyote time

El juego es de vista cenital, así que el coyote time se aplica a los **abismos**: el jugador salta con **K** o **Shift**. En el aire no le hacen daño las trampas de picos y no cae en los abismos. Al pisar un abismo sin saltar tiene un margen para saltar todavía; si no lo hace, cae, pierde medio corazón (fuente `pit`, queda registrado en la base de datos) y vuelve al último suelo firme. Aterrizar sobre un abismo hace caer en el acto. Los enemigos que caminan no pueden cruzarlos (se frenan en el borde, como en una pared: saltar un abismo sirve para escapar); los que vuelan, como la calavera, y los proyectiles pasan por encima. La demo usa cada mecánica en su recorrido, con un cartel en la pared que la explica:

| Dónde | Qué se usa |
|---|---|
| Entrada | Primer abismo (se salta o se rodea) y dos esqueletos para el buffer de ataque y el parry cuerpo a cuerpo |
| Pasillo entrada → arqueros | Un abismo de 1 celda que corta el paso: hay que saltar |
| Sala de arqueros | Parry de flechas |
| Pasillo arqueros → mago | Salto largo de 2 celdas (32 px, justo lo que cubre un salto): saltando antes del borde no se llega, el coyote time deja saltar un poco después de pisar el hueco |
| Sala del mago | Fila de picos de pared a pared: se salta (en el aire no lastiman) y se devuelve el orbe |
| Antesala de lava | Zanja de lava de lado a lado |

| Parámetro | Valor | Qué hace |
|---|---|---|
| `coyote_time` | 0.12 s | Tiempo para saltar después de pisar el borde de un abismo |
| `jump_duration` | 0.4 s | Tiempo en el aire (a 80 px/s alcanza para cruzar 32 px) |
| `jump_height` | 8 px | Altura visual del salto |
| `fall_damage` | 1 (½ corazón) | Daño al caer en un abismo |

### Golpes más ágiles y enemigos sólidos

| Parámetro | Valor | Qué hace |
|---|---|---|
| `attack_speed` (`player.gd`) | 1.4 | Divide la anticipación, la ventana activa y el enfriamiento de todas las armas: la espada pasa de 0.4 s a 0.29 s entre golpes. La estela también se reproduce 1.4 veces más rápido |
| Colisión jugador–enemigo | capas 2 y 3 | El jugador y los enemigos ya no se atraviesan: se frenan al chocar |
| `CONTACT_MARGIN` (`enemy_base.gd`) | 3 px | Lo que crece la zona de daño por contacto de cada enemigo, para que siga tocando al jugador aunque los cuerpos ya no se superpongan |

### Parry

Inspirado en ULTRAKILL: pulsar **L** abre una ventana corta. Lo que llegue en esa ventana se devuelve en lugar de hacer daño:

- **Proyectiles** (flechas, orbes): vuelven hacia quien los disparó, más rápido y con más daño. El parry devuelve incluso las flechas, que la espada solo puede romper.
- **Golpes cuerpo a cuerpo** (estocada del esqueleto, mordida del vampiro, contacto): no hacen daño y el enemigo recibe un contragolpe fuerte que no puede esquivar.
- **Recompensa:** cura medio corazón y reinicia la espera, así se pueden encadenar parrys. Un parry fallido obliga a esperar.
- Las trampas y los efectos de suelo de los jefes no se pueden devolver.

| Parámetro | Valor | Qué hace |
|---|---|---|
| `parry_window` | 0.18 s | Duración de la ventana de parry |
| `parry_cooldown` | 0.5 s | Espera después de un parry fallido (uno logrado la reinicia) |
| `parry_radius` | 22 px | Distancia a la que atrapa proyectiles |
| `parry_projectile_speed` | ×2 | Velocidad del proyectil devuelto |
| `parry_projectile_bonus` | +2 | Daño extra del proyectil devuelto |
| `parry_damage_multiplier` | ×3 | Daño del contragolpe cuerpo a cuerpo (daño del arma × 3) |
| `parry_heal` | 1 (½ corazón) | Curación por parry logrado |

Feedback del parry (`game_feel.gd`): congelado total de 0.22 s (`HITSTOP_PARRY`), destello blanco de toda la pantalla (`PARRY_FLASH_ALPHA` 0.65, se desvanece en 0.25 s), golpe de zoom de la cámara (×1.12, vuelve en 0.3 s), trauma 0.6, chispas doradas, «¡PARRY!» sobre el jugador y doble sonido. Al pulsar L el caballero destella en blanco para que se vea el intento.

### Screenshake

Vibración de cámara por **trauma**: cada momento clave suma trauma (de 0 a 1), la cámara se desplaza `MAX_SHAKE_OFFSET × trauma²` con ruido suave y el trauma baja solo. Al elevarlo al cuadrado, los golpes pequeños apenas se notan y los grandes sí.

| Parámetro | Valor |
|---|---|
| `MAX_SHAKE_OFFSET` | (5, 4) px del mundo (×3 de zoom en pantalla) |
| `TRAUMA_DECAY` | 1.6 por segundo |
| Jugador recibe daño | 0.45 |
| Caída a un abismo | 0.5 |
| Golpe a un enemigo / a un jefe | 0.15 / 0.3 |
| Enemigo eliminado / jefe eliminado | 0.25 / 0.8 |
| Aterrizaje del salto | 0.15 |
| Recoger la llave | 0.2 |

### Feedback

| Acción | Visual | Sonido / interfaz |
|---|---|---|
| Golpe acertado | Hit-stop de 0.05 s (el juego corre al 5 %), chispas y número de daño flotante | Sonido de golpe (ya existía) |
| Recibir daño | Hit-stop de 0.08 s, «-1♥» flotante en rojo, parpadeo y retroceso | Sonido de daño |
| Jefe eliminado | Hit-stop de 0.15 s y vibración fuerte | — |
| Recoger monedas | «+N» dorado sobre el jugador | El contador de monedas del HUD rebota y se pone dorado |
| Curarse / llave | «+1♥» verde / «¡Llave!» | Sonidos de recogida |
| Saltar / aterrizar | Se estira al despegar y se aplasta al aterrizar, con polvo | — |
| Caer a un abismo | Se achica, «¡Abismo!» | Sonido de daño |

Ninguna de estas mejoras cambia las estadísticas: `GameFeel` solo escucha señales, y el registro de partidas, el leaderboard y la web siguen igual. La única novedad en la base es la fuente de daño `pit`.

## Controles móviles

El juego se puede jugar entero con la pantalla táctil sin perder el teclado ni el mando: un joystick flotante a la izquierda, los botones **ATAQUE**, **SALTO** y **PARRY** abajo a la derecha y la pausa arriba. Los menús, la tienda y las pantallas finales ya eran botones, y se tocan directamente.

| Controles en juego | Menú de ajustes |
|---|---|
| ![Joystick inclinado hacia arriba a la derecha y ATAQUE apretado, con el golpe en curso](docs/capturas/05-controles-tactiles.png) | ![Ajustes con opacidad, tamaño, zona muerta y vibración, y la vista previa de los controles](docs/capturas/06-ajustes-controles.png) |
| Un dedo en el joystick y otro en ATAQUE a la vez (multitouch): el caballero camina y golpea. | Los cambios se guardan en el acto y la vista previa los muestra. |

![HUD y controles en una pantalla de celular 20:9](docs/capturas/07-hud-movil.png)

HUD y controles con la proporción de un celular (20:9, la vista queda en 1440 × 648): los anclajes mantienen los corazones arriba a la izquierda, el minimapa arriba a la derecha y los botones en las esquinas de abajo.

### Una sola capa de entrada

El jugador (`scripts/player.gd`) solo lee **acciones del Input Map** (`move_left`, `move_right`, `move_up`, `move_down`, `attack`, `jump`, `parry`, `pause`) con `Input.get_vector` e `Input.is_action_just_pressed`, sin saber qué dispositivo las aprieta. Cada acción tiene su tecla, su botón del mando y su control táctil:

- **Botones** (`scripts/input/touch_action_button.gd`): son `TouchScreenButton` con su propiedad `action`, así que tocarlos aprieta la acción como la tecla. Se dibujan solos (círculo, ícono del juego y rótulo) y su área de toque es un círculo del mismo diámetro.
- **Joystick** (`scripts/input/touch_joystick.gd`): convierte el desplazamiento de la perilla en `Input.action_press("move_right", fuerza)` y `Input.action_release(...)`. Solo suelta las acciones que apretó él, así no corta una tecla que se mantiene a la vez. Es **flotante**: el centro queda donde apoya el pulgar; sin dedo se ve tenue abajo a la izquierda. Fuera de la zona muerta la dirección sale con fuerza completa, porque el caballero camina a una sola velocidad, igual que con el teclado.
- **Multitouch:** el joystick sigue a un solo dedo por su índice de toque y cada `TouchScreenButton` sigue al suyo, así que se puede caminar y saltar o atacar al mismo tiempo.

Godot 4.7 trae un `VirtualJoystick` nativo (por eso el del juego se llama `TouchJoystick`). Se prefirió uno propio para controlar qué acciones suelta, que se suelte solo al pausar u ocultarse y poder probarlo sin pantalla.

Como todo pasa por las mismas acciones, el **input buffering** y el **coyote time** funcionan igual con los botones táctiles. `tests/test_touch_controls.gd` lo comprueba tocando SALTO en el aire (el salto sale al aterrizar) y sobre el borde de un abismo (salta dentro del coyote time).

### Cuándo se ven

`scripts/input/touch_controls.gd` (Autoload `TouchControls`, escena `scenes/TouchControls.tscn`) los muestra solo en partida: con un jugador vivo, sin pausa y fuera de las pantallas finales. Al ocultarse suelta todo lo que estaba apretado. En **Ajustes → Mostrar** se elige el modo:

| Modo | Cuándo se ven |
|---|---|
| **Auto** (por defecto) | En el celular, siempre (`DisplayServer.is_touchscreen_available()`). En una PC con pantalla táctil, desde el primer toque real hasta que se usa el teclado o el mando: en Windows Godot no informa la pantalla táctil, así que se detecta con el toque |
| **Siempre** | Modo de depuración para probar en PC. Sin pantalla táctil enciende `Input.emulate_touch_from_mouse`, así el mouse maneja el joystick y los botones |
| **Nunca** | Solo teclado y mando |

La emulación de toques se enciende desde el código y no en Project Settings: con *Emulate Touch From Mouse* activado en el proyecto, `is_touchscreen_available()` daría `true` en cualquier PC y el modo Auto los mostraría siempre.

### Diseño y pantalla

- **Ergonomía:** el joystick ocupa la parte izquierda de la pantalla (45 % del ancho, sin el 30 % de arriba) y aparece donde se apoye el pulgar. ATAQUE, la acción más usada, es el botón más grande y queda en la esquina, donde descansa el pulgar derecho; SALTO a su izquierda y PARRY encima, en arco. La pausa va arriba, a la izquierda del minimapa, lejos de los pulgares para no tocarla sin querer. El centro de la pantalla, donde está el caballero, queda libre.
- **Orientación y escalado:** horizontal (`display/window/handheld/orientation` = sensor landscape, gira con el celular) y stretch `canvas_items` + `expand`. La vista mide 648 px de alto y se ensancha según la pantalla (1440 px en un 20:9).
- **Anclajes:** joystick y botones cuelgan de nodos anclados a cada esquina (`Safe/BottomRight`, `Safe/TopRight`).
- **Zona segura:** `scripts/input/safe_area.gd` convierte `DisplayServer.get_display_safe_area()` a píxeles de la vista. Los controles, la barra superior del HUD, el minimapa y la barra del jefe se corren para no quedar debajo del notch ni de los bordes redondeados. En PC los márgenes valen cero.
- **Menú de ajustes:** con la vista previa visible, el contenido se corre al espacio libre entre el joystick y los botones.

### Parámetros

| Parámetro | Valor usado | Dónde |
|---|---|---|
| Radio del joystick | 100 px (75–150 px con el tamaño de Ajustes) | `JOYSTICK_RADIUS` en `touch_controls.gd` |
| Zona muerta | 0.20 del radio (ajustable de 0.05 a 0.50) | Ajustes; `ControlSettings.DEFAULT_DEADZONE` |
| Tamaño de los botones | ATAQUE 132 px, SALTO 112 px, PARRY 100 px, pausa 96 px (× 0.75–1.5) | `*_DIAMETER` en `touch_controls.gd` |
| Tamaño físico aproximado | 96 px de la vista ≈ 160 px en una pantalla de 1080 px de alto ≈ 10 mm a 400 ppp | — |
| Opacidad de los controles | 0.55 (ajustable de 0.2 a 1.0); en reposo el joystick se ve al 60 % de eso | Ajustes; `ControlSettings.DEFAULT_OPACITY` |
| Zona muerta del stick del mando | 0.2 en las acciones de movimiento (antes 0.5) | Input Map |
| Duración de vibración | 30–80 ms (ver abajo) | `scripts/input/haptics.gd` |
| Orientación y stretch | Landscape (sensor), `canvas_items` + `expand` | Project Settings |

### Vibración

`Haptics` llama a `Input.vibrate_handheld(ms)` solo en Android e iOS y si la vibración está encendida en Ajustes. La dispara `GameFeel`, que ya escuchaba esos momentos:

| Momento | Duración |
|---|---|
| Recibir daño (también al caer a un abismo) | 70 ms |
| Parry logrado | 50 ms |
| Matar un enemigo / un jefe | 35 / 80 ms |
| Recoger la llave o un corazón | 30 ms |

Las monedas no vibran, para no saturar.

### Ajustes guardados

Se guardan en la sección `[controls]` de `user://settings.cfg`, el mismo archivo de la telemetría (`scripts/settings/control_settings.gd`). Un valor fuera de rango se recorta al límite y un archivo dañado vuelve a los valores por defecto.

```ini
[controls]
touch_mode="auto"   ; auto, always o never
opacity=0.55
scale=1.0
deadzone=0.2
vibration=true
```

### Cómo probarlo

- **PC con pantalla táctil** (por ejemplo, una Latitude 5320): correr el juego con F5 y tocar la pantalla; con Auto los controles aparecen al primer toque y se ocultan al usar el teclado.
- **PC sin pantalla táctil:** Ajustes → Mostrar → **Siempre (depuración)** y usar el mouse (un solo "dedo": sirve para el joystick o un botón, no para los dos a la vez).
- **Pruebas automáticas:** `tests/test_touch_joystick.gd` (zona muerta, acciones, un dedo por joystick) y `tests/test_touch_controls.gd` (ajustes, modos, multitouch, buffer y coyote con el botón táctil, vibración, zona segura). Las suites anteriores siguen pasando, y también las del servidor (`uv run pytest`).

### Limitaciones en el celular

- **Servidor y web local:** el servidor escucha en `127.0.0.1`, la propia PC. En el celular esa dirección es el celular, así que el juego no llega al servidor: guarda las partidas en su cola local (`user://stats_queue.json`, hasta 1000 pedidos) y el menú muestra el ranking local ("Fuente: local"). La base de datos, el leaderboard y la web se consultan desde la PC como siempre; las partidas del celular no aparecen ahí. La web tampoco se puede abrir desde el celular.
- **Panel F3** de game feel: solo con teclado.
- **Zona de pruebas** (sandbox): sus atajos para hacer aparecer enemigos son de teclado; el jugador sí se maneja con los controles táctiles.

## Estadísticas, ranking y servidor local

El juego registra cada partida (tiempo, niveles, enemigos eliminados, daño recibido, monedas, llaves y corazones recogidos, compras, muerte o abandono) y la envía a un servidor local que la guarda en SQLite. El mismo servidor tiene una interfaz web para consultar los datos.

```text
Godot --HTTP/JSON--> FastAPI (127.0.0.1:8765) --> SQLite (server/data/game.db)
                      └── interfaz web en http://127.0.0.1:8765/
```

**El servidor es opcional.** Si no está encendido el juego funciona igual: guarda lo pendiente en `user://stats_queue.json` (hasta 1000 pedidos; pasado ese tope descarta los más viejos) y lo envía cuando el servidor vuelve a responder, con reintentos cada 2 s que se duplican hasta 60 s. El menú muestra el ranking del servidor ("Fuente: en línea") o, si no responde, la tabla local de siempre ("Fuente: local").

### Encender el servidor

Requiere [uv](https://docs.astral.sh/uv/) (instala Python 3.13 y las dependencias la primera vez):

```bash
cd server
uv run game-stats            # http://127.0.0.1:8765  (--port, --db, --reload)
```

Luego abrir <http://127.0.0.1:8765/>. La base se crea sola al arrancar con `server/schema.sql`.

Otros comandos (desde `server/`):

| Comando | Qué hace |
|---|---|
| `uv run pytest` | Pruebas del servidor (usan una base temporal) |
| `uv run game-stats-seed` | Agrega partidas de ejemplo (ids `seed-…`) |
| `uv run game-stats-seed --remove` | Quita las partidas de ejemplo |

Para empezar de cero basta con borrar `server/data/`.

### Base de datos

SQLite en `server/data/game.db`, con cuatro tablas (`server/schema.sql`):

```text
players 1 ──< runs 1 ──< events
                   1 ──< level_tracks
```

| Tabla | Una fila por | Columnas principales |
|---|---|---|
| `players` | jugador | `name` (único, sin distinguir mayúsculas; se escribe en el menú, por defecto "Jugador"), `created_at` |
| `runs` | partida | `id` (lo genera el juego, así puede reenviar sin duplicar), `player_id`, `mode` (`normal`, `test` o `demo`), `run_seed`, `start_level`, `level_reached`, `score`, `enemies_killed`, `duration_s`, `outcome` (`died`, `quit` o `in_progress`), `started_at`, `ended_at` |
| `events` | cosa que hizo el jugador | `run_id`, `seq` (orden dentro de la partida; `run_id + seq` es único), `type`, `level`, `t_run_s` (segundos jugados), `payload` (JSON), `created_at` |
| `level_tracks` | nivel jugado | `run_id`, `level`, `attempt` (`run_id + level + attempt` es único), `outcome`, `duration_s`, `map_key`, `difficulty_index`, `data` (el archivo de telemetría completo: recorrido, eventos y mapa; ver `docs/analitica.md`) |

`events` acepta cualquier tipo de evento y los datos propios de cada uno van en `payload`, así se pueden sumar tipos nuevos sin migrar la base. `lives` (la vida que queda) y el `amount` del daño y de los corazones están en **corazones** y pueden tener medio (`0.5`, `2.5`): el juego cuenta la vida en medios corazones y los informa divididos por 2, así las partidas anteriores (vidas enteras) siguen siendo comparables. Eventos actuales:

| Tipo | `payload` |
|---|---|
| `level_started` | `lives`, `enemies_total` |
| `enemy_killed` | `enemy` (Skeleton, Vampire…) |
| `enemy_dodged` | `enemy` |
| `damage_taken` | `amount`, `lives` |
| `heart_picked` | `amount`, `lives` |
| `key_picked` | vacío |
| `coin_picked` | `amount` |
| `item_bought` | `item` (`damage`, `life` = un corazón, o el id de un arma), `price` |
| `level_completed` | `duration_s`, `kills`, `enemies_total`, `score` |
| `player_died` | `score` |
| `run_quit` | vacío |

Las monedas y los tiempos salen de estos eventos: el servidor suma `coin_picked` (recogidas) e `item_bought` (gastadas y artículos comprados) al calcular las estadísticas.

### Página web

Es una página estática (`server/web/`: HTML, CSS y JS sin dependencias) que el mismo servidor sirve en <http://127.0.0.1:8765/> y que consulta la API. Arriba a la derecha se puede filtrar todo por jugador. Tiene cinco secciones:

| Sección | Qué muestra |
|---|---|
| **Ranking** | Mejores puntajes: puesto, jugador, puntos, nivel, enemigos, monedas recogidas, duración y fecha. Solo cuentan las partidas terminadas en modo normal. |
| **Jugadores** | Puntos, tiempo y partidas sumados por jugador, para ver quién jugó más. Cada jugador tiene su perfil. |
| **Partidas** | Historial de partidas, filtrable por jugador y modo, con monedas recogidas y gastadas. Al abrir una se ve su detalle con la línea de tiempo de eventos y, si subió su telemetría, el recorrido sobre el mapa. |
| **Analítica** | La telemetría de los niveles: avisos de dificultad, mapas de calor (tiempo, daño, muertes) y dificultad por nivel. |
| **Estadísticas** | Totales globales (jugadores, partidas, enemigos eliminados, llaves, corazones, daño recibido, mejor nivel y puntaje, duración media), monedas recogidas y gastadas, artículos comprados por tipo y cantidad de eventos de cada tipo. Se puede filtrar por modo. |

**Ranking** (mejores puntajes):

![Ranking en la página web](docs/capturas/02-ranking-web.png)

**Estadísticas** (totales de todo lo que hicieron los jugadores):

![Estadísticas en la página web](docs/capturas/03-estadisticas-web.png)

**Recorrido de una partida** (detalle en Partidas): el mapa del nivel con el camino del jugador, del inicio al final, y dónde recibió daño, eliminó enemigos, recogió corazones y la llave. Al costado, el tiempo, el daño por fuente, el combate y el arma:

![Recorrido de un nivel en la página web](docs/capturas/04-recorrido-web.png)

### API

`POST /api/players`, `POST /api/runs`, `POST /api/runs/{id}/events`, `POST /api/runs/{id}/levels`, `PATCH /api/runs/{id}`, `GET /api/leaderboard?limit=10`, `GET /api/players`, `GET /api/players/totals`, `GET /api/players/{id}`, `GET /api/runs?player=&mode=&limit=`, `GET /api/runs/{id}`, `GET /api/runs/{id}/levels`, `GET /api/stats`, `GET /api/analytics` y `GET /api/health`. La documentación interactiva está en <http://127.0.0.1:8765/docs>.

## Estructura del proyecto

```text
scenes/          Escenas: nivel, jugador, enemigos, trampas, llave, puerta, HUD
  props/         Decoración animada (antorchas, estandartes, candelabros)
scripts/         Lógica en GDScript, comentada en español
  enemy_base.gd  Clase base de enemigos (vida, daño, golpe recibido, muerte)
  chaser_enemy.gd  Persecución con regreso a su puesto (vampiro y parca)
  level.gd       Conecta jugador, puerta, enemigos e interfaz
  stats/         Registro de partidas: RunTracker (Autoload), cola en disco y envío HTTP
  input/         Controles táctiles (TouchControls), joystick, botones, vibración y zona segura
  settings/      Ajustes guardados (telemetría y controles) y su menú
server/          Servidor local de estadísticas (FastAPI + SQLite) e interfaz web
tilesets/        TileSet del calabozo con colisión en las paredes
assets/          Sprites del calabozo y de los enemigos
addons/godot_ai/ Plugin usado durante el desarrollo (ver nota)
```

Decisiones de diseño principales:

- **Enemigos reutilizables:** `EnemyBase` concentra vida, daño por contacto, reacción al golpe (animación, parpadeo rojo y retroceso) y muerte. Cada enemigo solo define cómo se mueve.
- **Colisiones por capas:** `world`, `player` y `enemies`. Los enemigos chocan con las paredes pero no bloquean al jugador.
- **Interfaz desacoplada:** el HUD solo muestra datos; `level.gd` decide cuándo actualizarlo.
- **Entrada por acciones:** el jugador solo lee acciones del Input Map; teclado, mando y controles táctiles aprietan las mismas.

## Nota sobre el plugin godot-ai

El proyecto se desarrolló con asistencia de IA mediante el plugin [godot-ai](https://github.com/hi-godot/godot-ai) (v4.1.0), que conecta el editor de Godot con un asistente por MCP. **No hace falta para jugar.** Si al abrir el proyecto el editor muestra avisos del plugin, se puede desactivar en **Proyecto → Configuración del proyecto → Plugins**.

## Créditos

- **Sprites:** [2D Pixel Dungeon Asset Pack](https://pixel-poem.itch.io/dungeon-assetpuck) y su [set gratuito de animaciones de enemigos](https://pixel-poem.itch.io/dungeon-assetpuck/devlog/902754/new-animations-set-for-free) (vampiro, esqueleto espadachín y parca), de **Pixel_Poem**.
- **Licencia de los sprites:** según el autor, se pueden usar en proyectos gratuitos y comerciales y modificarse, pero **no se pueden redistribuir ni revender por separado**. Se incluyen en este repositorio únicamente como parte del juego. Para usarlos en otro proyecto, deben descargarse desde la página del autor.
- **Plugin de desarrollo:** [godot-ai](https://github.com/hi-godot/godot-ai), licencia MIT (ver `addons/godot_ai/LICENSE`).
