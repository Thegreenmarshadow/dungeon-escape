# Jefes temáticos

Este texto también sirve como **sección 9** de la biblia de personajes (`character-design.md`): se puede pegar tal cual.

## Archivos y datos técnicos

| Jefe | Carpeta | Animaciones (frames @ FPS) | Frame de impacto |
|---|---|---|---|
| Forjador de magma | `assets/bosses/forge/` | idle 6 @ 6, walk 6 @ 7, attack 10 @ 8, attack2 8 @ 8, hurt 3 @ 12, death 12 @ 12 | attack: **5** (martillazo); attack2: **4** (brasas) |
| Reina liche de escarcha | `assets/bosses/lich/` | idle 6 @ 7, walk 6 @ 7, attack 9 @ 8, attack2 8 @ 8, hurt 3 @ 12, death 12 @ 12 | attack: **5** (picos); attack2: **5** (nova) |
| Guardián musgoso | `assets/bosses/warden/` | idle 6 @ 6, walk 6 @ 6, attack 9 @ 8, attack2 8 @ 8, hurt 3 @ 12, death 12 @ 12 | attack: **5** (raíces); attack2: **4** (esporas) |

Todos usan frames de 48 × 48 con los pies en la fila 44 y el contorno en la 45. En la escena va `offset = Vector2(0, -12)`. El `<id>_frames.tres` ya trae los nombres `idle`, `walk`, `attack`, `attack2`, `hurt` y `death`.

| Efecto | Tamaño | Frames @ FPS | Notas |
|---|---|---|---|
| `forge/fx-shockwave` | 64 × 64 | 4 @ 12 | centrado en el punto de impacto |
| `forge/fx-lava_pool` | 16 × 16 | 4 @ 6, loop | charco que queda en el suelo, sin contorno |
| `forge/fx-ember_mark` | 32 × 32 | 6 @ 6 | frames 0–3 aviso, 4–5 estallido |
| `lich/fx-ice_spike` | 16 × 32 | 6 @ 8 | 0–1 grieta, 2–4 pico, 5 se rompe; la base está en la fila 30 |
| `lich/fx-frost_nova` | 64 × 64 | 4 @ 12 | se usa a escala 2 (radio 40 px) |
| `lich/fx-frost_mark` | 32 × 32 | 6 @ 6 | igual que `ember_mark` |
| `warden/fx-root_spike` | 16 × 32 | 6 @ 8 | igual que `ice_spike` |
| `warden/fx-spore_cloud` | 32 × 32 | 6 @ 4 | crece, se mantiene y se disipa |
| `warden/fx-spore_pod` | 16 × 16 | 4 @ 4, loop | vaina que hay que romper |

## Propuesta (sección 9 de la biblia)

### 9. Jefes temáticos (propuesta)

Cada tema de mazmorra cierra con un jefe hecho del mismo material que su piso:

- el **Forjador de magma** es roca y obsidiana con grietas de lava;
- la **Reina liche de escarcha** tiene escarcha en los hombros, carámbanos en el bajo de la túnica y corona de hielo;
- el **Guardián musgoso** es piedra cubierta de musgo, con raíces por piernas y setas luminosas en el hombro.

Cada jefe tiene dos habilidades y una tercera que solo usa en la fase 2 (a partir del 50 % de vida).

Los números son **propuestas** para probar en juego, igual que los de la sección 5. Los tiempos de anticipación salen de los frames y FPS que ya traen los sprites.

#### 9.1 Datos comunes

| Campo | Valor |
|---|---|
| Frame | 48 × 48 px, pies en la fila 44 (contorno en la 45), mira a la derecha |
| Escena | `offset = Vector2(0, -12)`, escala 1.0, cuerpo 20 × 10, contacto 24 × 26 |
| Animaciones | `idle`, `walk`, `attack` (habilidad 1), `attack2` (habilidad 2), `hurt` (3 frames), `death` (12 frames) |
| Archivos | `assets/bosses/<id>/boss-<id>_<anim>.png`, `<id>_frames.tres`, `fx-<efecto>.png` + `fx-<efecto>_frames.tres` |
| Corazón | `heart_drop_chance = 1.0`, más la llave si el nivel la necesita |
| Retroceso al recibir golpe | 2 px |
| Fase 2 | con vida ≤ 50 %: brillo constante, velocidad ×1.25 y se suma la habilidad 3 |
| Barra de vida | en el HUD, visible solo mientras el jefe está alerta (`is_alerted()`) |
| Peso en `DifficultyCurve` | `WEIGHT_THEME_BOSS = 10.0` |

Colocación: un jefe en el **último nivel de cada rango de tema**. Siguiendo los rangos propuestos para los tilesets:

| Tema | Niveles | Jefe | Nivel del jefe |
|---|---|---|---|
| Cripta helada | 5–8 | Reina liche de escarcha | 8 |
| Fragua de lava | 9–12 | Forjador de magma | 12 |
| Ruinas con musgo | 13–16 | Guardián musgoso | 16 |

La sala del jefe necesita al menos 9 × 9 celdas libres y va delante de la puerta, en lugar de la parca.

#### 9.2 Forjador de magma (`FORGE_BOSS` = &"forge")

**Concepto:** un gólem de roca y obsidiana con grietas de lava que late. Arrastra un martillo de fragua.
**Rol:** jefe de zona y de golpe pesado.
**Aporta:** el suelo se vuelve peligroso; el jugador tiene que leer dónde queda la lava.

| Visual | |
|---|---|
| Silueta y colores | cuerpo encorvado y ancho; roca `#2b1b1e`, `#45282a`, `#6b3a30`, `#8e4a3a`; grietas `#d9701a`, `#ff8a2a`, `#ffed56`; púas de obsidiana en los hombros; ojos y boca encendidos |
| Detalle del material | las grietas cambian de color en cada frame; suben brasas sobre los hombros |
| Animaciones | idle 6 (6 FPS), walk 6 (7), attack 10 (8), attack2 8 (8), hurt 3, death 12 |

| Stats | vida 12 · velocidad 20 px/s · contacto 1 · detecta a 120 px, correa 160 px |
|---|---|

**Estados:** `IDLE` → `CHASE` → `SLAM` o `ROAR` (alterna) → `RECOVER` → `CHASE`.

| Habilidad | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| 1. Martillazo | onda de radio 20 px en el punto de impacto (28 px adelante) | 625 ms (frames 0–4: levanta el martillo y las grietas se encienden) | frame **5** | 1000 ms (el martillo queda clavado) | 2.0 s | 1 | martillo en alto + brasas; `fx-shockwave` |
| — deja lava | 3 `fx-lava_pool` alrededor del impacto, 4 s | — | contacto | — | — | 1 | charco que burbujea |
| 2. Lluvia de brasas | 4 marcas: una sobre el jugador y 3 al azar a 24–48 px | 500 ms de rugido (frame **4**) + 667 ms por marca | 333 ms | 600 ms | 4.0 s | 1 | `fx-ember_mark`: anillo que se cierra (cumple `r / 80 + 0.25` para r = 12) |
| 3. Fase 2: surco de lava | el martillazo deja 5 charcos en línea hacia el jugador | igual que el 1 | — | 1000 ms | — | 1 | charcos en línea |

**Cómo vencerlo:** salir de la onda hacia atrás y golpearlo mientras tiene el martillo clavado. Que el jugador no termine encerrado entre charcos.

**Reutiliza:**

- los frames de impacto de `ChaserEnemy` (`attack_hit_frames = [5]`);
- `FireMark.tscn` (5.4) para las brasas;
- `spike_trap.gd` (revisión de cuerpos superpuestos) para los charcos.

**Código nuevo:** `LavaPool.tscn` (`Area2D`, máscara 2, se borra a los 4 s) y una segunda animación de ataque. `ChaserEnemy` hoy solo tiene `attack_animation`, así que hace falta un `attack2_animation` o una máquina de estados como la de `SkullEnemy`.

**Prompt (EN):** `hulking magma golem made of black obsidian and dark red rock, glowing orange lava cracks across the chest, small glowing yellow eyes, dragging a heavy iron forge hammer`.

#### 9.3 Reina liche de escarcha (`LICH_BOSS` = &"lich")

**Concepto:** una liche que flota, con túnica escarchada, corona de carámbanos y báculo de cristal.
**Rol:** jefa a distancia y de control de zona.
**Aporta:** se aleja del jugador, ataca en líneas y obliga a romper sus escudos.

| Visual | |
|---|---|
| Silueta y colores | túnica en trapecio `#2c3a52`, `#4a6a8a`, `#8fb8d0`, con pliegues; escarcha `#d8f0f8` en los hombros y carámbanos en el bajo; cráneo `#dae0ea` con ojos `#a7d1e6`; sombra en el suelo porque flota |
| Detalle del material | tres copos orbitan a su alrededor; el cristal del báculo destella al cargar |
| Animaciones | idle 6 (7 FPS, flota ±2 px), walk 6 (7), attack 9 (8), attack2 8 (8), hurt 3, death 12 |

| Stats | vida 10 · velocidad 30 px/s · contacto 0 · detecta a 140 px · se mantiene a 60–110 px del jugador |
|---|---|

**Estados:** `IDLE` → `REPOSITION` → `SPIKES` o `NOVA` → `RECOVER` → `REPOSITION`.

| Habilidad | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| 1. Línea de picos | 6 `fx-ice_spike` cada 16 px hacia donde estaba el jugador en el frame 3 | 625 ms (sube el báculo) + 250 ms de grieta por pico, 80 ms entre picos | 375 ms por pico | 500 ms | 2.5 s | 1 | báculo en alto con destellos y grieta en el suelo antes de cada pico |
| 2. Nova de escarcha | anillo de radio 40 px alrededor de ella (`fx-frost_nova` a escala 2) | 625 ms (brazos arriba, se eleva 3 px) | frame **5** | **1200 ms en el suelo, vulnerable** | 5.0 s | 1 + **frío** (jugador al 50 % de velocidad por 2 s) | brazos arriba, copos girando rápido |
| 3. Fase 2: cristales escudo | invoca 2 cristales de hielo a 24 px | 1000 ms | — | 600 ms | al romperse los dos | — | mientras haya cristales de pie, **no recibe daño**; cada cristal aguanta 2 golpes |

**Cómo vencerla:**

- cruzar la línea de picos de costado, no de frente;
- alejarse más de 40 px cuando levanta los brazos y castigarla durante los 1.2 s que queda en el suelo;
- en la fase 2, romper primero los cristales.

**Reutiliza:**

- la máquina de estados de `SkullEnemy`;
- el movimiento a distancia del arquero (5.1);
- `ice_prop.png` de los tilesets nuevos para los cristales.

**Código nuevo:**

- `IceSpike.tscn`, que se instancia en secuencia con `call_deferred`;
- el estado "frío" en `player.gd`: sin tinte, porque el azulado ya significa "aturdido". Se marca con copos alrededor del jugador;
- los cristales necesitan el mismo arreglo de contador que el nigromante (5.6).

**Prompt (EN):** `floating lich queen in a frosted navy blue robe with icicles hanging from the hem, crown of ice crystals, skull face with glowing pale blue eyes, holding a staff topped with an ice crystal`.

#### 9.4 Guardián musgoso (`WARDEN_BOSS` = &"warden")

**Concepto:** una estatua de piedra de las ruinas que despertó, con un solo ojo, cubierta de musgo y con raíces por piernas.
**Rol:** jefe lento con invocaciones y curación.
**Aporta:** hay que darle prioridad a objetivos que no son el jefe y alejarlo de su terreno.

| Visual | |
|---|---|
| Silueta y colores | bloques de piedra `#3e4652`, `#6d758d`, `#989eb3` con grietas; musgo `#3d5a2c`, `#6b8f3a`, `#a8c84a` encima y chorreando; lianas; raíces `#79593f`; setas `#3fa88a` / `#9ff0c0` en el hombro; ojo y runa espiral que laten |
| Detalle del material | el musgo es distinto en cada bloque (se genera con una semilla) y las setas sueltan esporas |
| Animaciones | idle 6 (6 FPS), walk 6 (6), attack 9 (8), attack2 8 (8), hurt 3, death 12 |

| Stats | vida 14 · velocidad 18 px/s · contacto 1 · detecta a 110 px, correa 150 px |
|---|---|

**Estados:** `IDLE` → `CHASE` → `ROOTS` o `SPORES` → `RECOVER` → `CHASE`.

| Habilidad | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| 1. Raíces | 3 `fx-root_spike`: debajo del jugador y a ±20 px (posición fijada en el frame 3) | 625 ms (brazos arriba) + 250 ms de tierra que se agrieta | frame **5** + 375 ms | 750 ms (**la runa brilla: los golpes hacen +1**) | 2.5 s | 1 | brazos en alto + grieta con hojitas |
| 2. Esporas | 2 `fx-spore_cloud` de radio 14 px cerca del jugador, por 3 s | 500 ms (las setas se inflan, frame **4**) | nube | 500 ms | 6.0 s | 0; el jugador va al 50 % de velocidad dentro de la nube | nube verde que crece |
| — vainas | 2 `fx-spore_pod` a 20 px del jefe | con las esporas | — | — | — | — | si no se rompen en 6 s, cada una le cura 2 de vida; se rompen con 1 golpe |
| 3. Fase 2: tierra fértil | parado sobre una mancha de musgo (`moss_floor_patch`) se cura 1 cada 3 s | — | — | — | — | — | su ojo late más rápido |

**Cómo vencerlo:**

- moverse cuando levanta los brazos y castigarlo en la recuperación, cuando la runa brilla;
- romper las vainas antes que nada;
- en la fase 2, sacarlo de las manchas de musgo: es el más lento de los tres.

**Reutiliza:**

- `ChaserEnemy` para la persecución;
- el patrón de `IceSpike.tscn` con otra textura para las raíces;
- `moss_floor_patch` de los tilesets.

**Código nuevo:**

- `SporeCloud.tscn` (`Area2D` que baja la velocidad del jugador);
- `SporePod.tscn` (enemigo de 1 de vida que no cuenta para el contador de muertes y que, si el tiempo se acaba, llama a `heal(2)` del jefe);
- `heal()` en `EnemyBase`.

**Prompt (EN):** `ancient one-eyed stone golem covered in thick green moss and hanging vines, root legs, glowing teal mushrooms growing on its shoulder, glowing spiral rune carved on its chest`.

#### 9.5 Mecánicas nuevas que suman los jefes

| Mecánica | Dónde | Implementación mínima |
|---|---|---|
| Segunda habilidad | los tres | `attack2_animation` y su propia tabla de frames de impacto, o un estado aparte como en `SkullEnemy` |
| Fase 2 al 50 % | los tres | señal `phase_changed` en `EnemyBase.take_hit` cuando `health <= max_health / 2` |
| Peligros que quedan en el suelo | lava, picos, raíces, nubes | escenas `Area2D` que se crean con `call_deferred` y se borran con un `Timer` |
| Ralentizar al jugador | frío, esporas | `player.gd`: `speed_multiplier` con temporizador; se ve con partículas, no con tinte (los tintes están reservados, 2.3) |
| Objetivos prioritarios | cristales, vainas | enemigos que no cuentan para el HUD (mismo problema que 5.6) |
| Curación del jefe | vainas, musgo | `EnemyBase.heal(amount)` con tope en `max_health` |

Las tres cumplen las reglas de la sección 6.1: todo lo que apunta al jugador avisa al menos 600 ms y las áreas cumplen `r / 80 + 0.25`. El daño es siempre 1 corazón (2 medios corazones en el código, donde se cuenta la vida del jugador) en el primer nivel de cada jefe; en sus vueltas desde el nivel 25 suma el mismo bonus de daño que el resto de los enemigos, con un tope de 2.5 corazones por golpe (`BossBase.apply_damage_bonus`). Cada jefe tiene una ventana de castigo de 750 a 1200 ms.
