# Biblia de personajes: estilo, fichas y ataques

Referencia para crear personajes nuevos (arte y código) que encajen con los que ya tiene *Dungeon Escape*, y para sumar variedad de enemigos, ataques y trampas sin romper la curva de dificultad.

## 1. Propósito y cómo usar este documento

- **Para hacer arte** (a mano o con un generador de imágenes): leer la sección 2 y copiar el prompt base. Cada ficha de la sección 5 trae su prompt propio.
- **Para programar un enemigo**: copiar la plantilla de la sección 4, completarla y seguir la lista de la sección 7.
- **Para balancear**: los tiempos de ataque de la sección 6 y la curva de la sección 8.

Convenciones:

- Los números de las secciones 2 y 3 salen del código, de las escenas `.tscn` y de los PNG del proyecto. Lo que no se pudo comprobar se marca **(por verificar)**.
- Los números de las secciones 5 y 8 son **propuestas**: valores de partida para probar en juego, no mediciones.
- Unidades: píxeles del mundo (px), segundos (s) o milisegundos (ms), celdas de 16 px. La cámara del jugador usa `zoom = 3`, así que 1 px del mundo se ve como 3 px en pantalla.

## 2. Guía de estilo visual

### 2.1 Datos técnicos comprobados

| Aspecto | Valor | Fuente |
|---|---|---|
| Tamaño de celda | 16 × 16 px | `tilesets/dungeon_tileset.tres` (polígonos de -8 a 8) |
| Frame de los enemigos animados | 32 × 32 px, tiras horizontales de 1 fila | `assets/enemies/*.png` (alto 32, ancho = 32 × frames) |
| Frame del pack de calabozo | 16 × 16 px, un PNG por frame | `assets/dungeon/character_animation/**`, `items_and_traps/**` |
| Tamaño real del personaje | 12–16 px de ancho, 15–17 px de alto | caja de píxeles opacos de los frames de reposo |
| Apoyo de los pies (frames de 32) | fila 29 (quedan 2 px libres debajo) | ídem |
| Posición horizontal (frames de 32) | columnas 7–24, casi centrado | ídem |
| Transparencia | binaria: alfa 0 o 255, sin semitransparencias | todos los PNG analizados |
| Contorno | 1 px, color `#25131a` (marrón vino casi negro) | es el color más usado en ambos packs |
| Colores por personaje | 6–8 (16 × 16) y 8–15 (32 × 32) | conteo de colores por hoja |
| Orientación | mira a la **derecha**; el código voltea con `flip_h` | `EnemyBase._update_animation` |
| Filtro de textura | Nearest para todo el proyecto | `project.godot`: `textures/canvas_textures/default_texture_filter=0` |
| Importación | sin compresión con pérdida (`compress/mode=0`), sin mipmaps | archivos `.import` |
| Escala en escena | 1.0; solo la parca usa `scale = Vector2(1.4, 1.4)` | `scenes/Reaper.tscn` |
| Desfase del sprite (frames de 32) | `offset = Vector2(0, -5)` | `Skeleton.tscn`, `Vampire.tscn`, `Reaper.tscn` |
| Vista | cenital con personajes de frente/perfil (estilo RPG 3/4) | inspección visual |
| Área visible | unos 384 × 216 px de mundo (ventana base por defecto 1152 × 648 con zoom 3) | `project.godot` no fija tamaño de ventana; el valor es el de Godot **(por verificar en juego con `aspect = expand`)** |

Los dos packs conviven porque el personaje mide unos 16 px de alto en ambos: los sprites de 32 × 32 dejan margen para armas y efectos (los arcos de la guadaña llegan a 30 px de ancho).

### 2.2 Paleta

Colores reales de los sprites existentes (de mayor a menor uso). Un personaje nuevo debería tomar la mayoría de sus colores de aquí y agregar uno o dos acentos propios.

| Rol | Colores |
|---|---|
| Contorno (siempre) | `#25131a` |
| Hueso / tela clara | `#b3b2a1`, `#dae0ea`, `#e6e6e6` |
| Metal frío / piel gris | `#6d758d`, `#989eb3`, `#b3b9d1`, `#3e4652` |
| Tela y cuero marrón | `#5e4e3a`, `#676057`, `#827860`, `#79593f`, `#4b3726`, `#b19d83` |
| Rojo (ojos, sangre, detalles) | `#be2b25`, `#79191d`, `#9b534a`, `#bc4c51` |
| Oro / fuego | `#d9701a`, `#ffed56`, `#d1851e`, `#ffd569` |
| Azul espectral (calavera) | `#62abd4`, `#a7d1e6`, `#577ea1`, `#56587b` |
| Caballero (jugador) | `#adc1cf`, `#90919e`, `#373737`, `#895a45`, `#bf704d` |
| Suelo y paredes | `#3d253b`, `#4c2f49`, `#362030`, `#6e4a48`, `#895a45`, `#78514f` |
| Estela de ataque | `#dae0ea` (arcos de la guadaña y la espada en las hojas de ataque) |

Sensación general: grises fríos y marrones apagados sobre un suelo violeta oscuro, con acentos pequeños y saturados (ojos rojos, amuleto dorado, fuego naranja, azul espectral). El enemigo debe contrastar con el suelo `#3d253b`: evitar cuerpos enteros en violetas oscuros.

### 2.3 Sombreado y colores reservados

- Sombreado plano de 2–3 tonos por material, sin degradados ni anti-aliasing. La dirección de la luz parece venir de arriba **(por verificar)**.
- Los ojos brillantes (rojo o azul) son el rasgo que identifica a un enemigo en 16 px: conviene que cada enemigo nuevo los tenga.
- El código usa tintes sobre el sprite con un significado concreto. Un enemigo nuevo no debe usarlos para otra cosa:

| Tinte | Significado | Dónde |
|---|---|---|
| Destello rojo `Color(1, 0.3, 0.3)` durante 0.25 s | recibió un golpe | `EnemyBase._flash_red` |
| Parpadeo rojo `Color(1, 0.4, 0.4)` a 6 Hz | está cargando un ataque | `SkullEnemy.WINDUP_TINT` |
| Azulado `Color(0.7, 0.7, 1)` | aturdido y vulnerable | `SkullEnemy.RECOVER_TINT` |
| Parpadeo de transparencia | jugador invulnerable | `player.gd` |

### 2.4 Animaciones y frames

Nombres de archivo del pack de enemigos: `enemies-<nombre>_<animación>.png`. Nombres de animación en Godot: los que espera `EnemyBase` (`idle`, `walk`, `hurt`, `death`) más `attack` en `ChaserEnemy`.

| Hoja (archivo) | Animación en Godot | Esqueleto | Parca (skeleton2) | Vampiro | FPS en escena | Loop |
|---|---|---|---|---|---|---|
| `_idle` | `idle` | 6 | 6 | 6 | 8 | sí |
| `_movement` | `walk` | 10 | 10 | 8 | 10 (parca 7) | sí |
| `_take_damage` | `hurt` | 5 | 5 | 5 | 15 | no |
| `_death` | `death` | 17 | 15 | 14 | 14 (parca 12) | no |
| `_attack` | `attack` | 9 (a 10 FPS) | 15 **(sin usar)** | 16 | 14 | no |
| `_death2` | — | — | 15 **(sin usar)** | — | — | — |

Pack de calabozo (16 × 16): solo reposo de 4 frames (`<nombre>_v1_1.png` … `_4.png`). La carpeta `v2` es la misma animación con marcas de color en las esquinas (marcador de selección): para el juego conviene `v1`.

Recomendación para un enemigo nuevo de 32 × 32: idle 4–6 frames, walk 6–10, hurt 3–5, death 8–17, attack 9–16. `hurt` y `death` sin loop (lo exige `EnemyBase`). Con `hurt` de 5 frames a 15 FPS el enemigo queda aturdido 0.33 s.

### 2.5 Licencia y créditos

Según `assets/CREDITS.md`, los sprites son de **Pixel_Poem** (*2D Pixel Dungeon Asset Pack* y su set gratuito de animaciones de enemigos): se pueden usar y modificar en proyectos gratuitos y comerciales, pero **no redistribuir ni revender por separado**. Para un personaje nuevo:

- Un recoloreo o edición de un sprite de Pixel_Poem sigue sujeto a esa licencia: va en `assets/` como parte del juego y no se publica suelto.
- Subir los sprites del pack a un servicio externo como imagen de referencia podría contar como redistribución **(por verificar con la licencia del autor)**. Lo seguro es describir el estilo con texto, como en el prompt de abajo.
- Arte generado por IA: revisar los términos del generador y anotar herramienta, fecha y autor en `assets/CREDITS.md`, con el mismo formato que las demás entradas.

### 2.6 Prompt base para generadores de imágenes

Prompt en inglés (los generadores responden mejor en inglés). Reemplazar lo que va entre `<>`.

```text
Pixel art sprite sheet of <CHARACTER DESCRIPTION>, dark fantasy dungeon enemy,
top-down RPG style with the character seen from the front-side, facing right,
single horizontal strip of <N> frames, each frame exactly 32x32 pixels,
character about 16 pixels tall standing near the bottom of the frame,
crisp 1-pixel dark outline in #25131a, limited palette of 10 to 14 colors,
flat shading with 2-3 tones per material, no anti-aliasing,
muted cold greys and desaturated browns with small saturated accents
(glowing red eyes, orange-gold metal), transparent background,
animation: <ANIMATION NAME AND SHORT DESCRIPTION>
```

Prompt negativo (en inglés):

```text
blurry, anti-aliasing, smooth gradients, soft shading, painterly, 3D render,
photorealistic, high detail, isometric, large character filling the frame,
semi-transparent pixels, glow halo, drop shadow, background, floor tiles,
text, watermark, frame borders, multiple characters, inconsistent frame size
```

Ningún generador entrega una grilla de píxeles exacta. Después de generar:

1. Reducir a la escala real con vecino más cercano (nearest) hasta que cada frame mida 32 × 32.
2. Cuantizar a la paleta de 2.2 y limpiar a mano en Aseprite o LibreSprite (el contorno de 1 px se pierde casi siempre).
3. Forzar alfa binario (0 o 255) y alinear los pies en la fila 29 en todos los frames.
4. Comprobar con este script (el Python del sistema tiene Pillow 11.3):

```python
# python3 -I check_sheet.py assets/enemies/enemies-<nombre>_<anim>.png
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGBA")
assert im.height == 32 and im.width % 32 == 0, "la tira debe ser de frames de 32x32"
alphas = {p[3] for p in im.getdata()}
assert alphas <= {0, 255}, f"hay semitransparencias: {sorted(alphas)}"
colors = {p[:3] for p in im.getdata() if p[3]}
print(f"{im.width // 32} frames, {len(colors)} colores, contorno #25131a: {(0x25, 0x13, 0x1a) in colors}")
```

## 3. Fichas de los personajes existentes

Valores comunes de `EnemyBase` salvo que la escena los cambie: `knockback_distance = 10` px aplicados en `KNOCKBACK_TIME = 0.15` s, `heart_drop_chance = 0.18`, `contact_damage = 1`. Capas de física: 1 `world`, 2 `player`, 3 `enemies` (valor 4).

### 3.1 Jugador (caballero)

| Campo | Valor |
|---|---|
| Archivos | `scripts/player.gd`, `scenes/Player.tscn`, sprite `priest3/v1/priest3_v1_1..4.png` (16 × 16) |
| Visual | caballero con yelmo gris con visera, armadura gris y espada; 6 colores |
| Animaciones | solo `idle` (4 frames, 6 FPS). La caminata se simula inclinando el sprite ±8° y con un rebote de 1.5 px a 8 pasos/s; el ataque es un arco blanco (`Line2D`) y un avance de 3 px |
| Movimiento | 80 px/s en 8 direcciones; es más rápido que todos los enemigos |
| Vidas | 3, invulnerable 1.5 s tras recibir daño |
| Retroceso al recibir daño | 14 px en 0.15 s (no lo aplican los picos) |
| Espada | daño 1, hitbox de 12 × 18 px centrada a 10 px del jugador (alcance de unos 16 px), activa 0.2 s, enfriamiento 0.4 s, apunta a la última dirección de movimiento |
| Colisión | pies 10 × 6 px; la hitbox detecta capa 3 (cuerpos y también áreas con `take_hit`) |

Consecuencias de diseño: con 3 vidas, cada punto de daño es un tercio de la partida; la invulnerabilidad de 1.5 s hace que varios golpes seguidos cuenten como uno. Un enemigo más rápido que 80 px/s no se puede esquivar corriendo.

### 3.2 Esqueleto (soldado)

| Campo | Valor |
|---|---|
| Archivos | `scripts/skeleton.gd` (hereda de `ChaserEnemy`), `scenes/Skeleton.tscn`, `enemies-skeleton1_*.png` |
| Rol | soldado cuerpo a cuerpo que guarda su ruta |
| Visual | esqueleto pequeño con espada corta y tela roja en el pecho; 8 colores |
| Stats | vida 2, velocidad 35 px/s, `contact_damage = 0` (solo lastima con la estocada), esquiva 15 %, cuerpo 10 × 8, contacto 12 × 14 |
| Comportamiento | va y viene entre su punto inicial y `patrol_offset` (tramo recto de 3–7 celdas, 48–112 px); sin tramo espera en su puesto |
| Detección | detecta a 64 px, pierde a 96 px, no persigue si el jugador está a más de 56 px de su ruta (`leash_radius`, medido al punto más cercano del tramo) |
| Estados | patrulla → va hacia el jugador → ataca → enfriamiento → vuelve a la ruta si lo pierde |
| Estocada | empieza a 20 px (`attack_range`), alcance 24 px (`attack_reach`), daño 1, frames de impacto 6–7 (el arco del tajo, verificado en la hoja) |
| Tiempos de la estocada (9 frames a 10 FPS, el 5 dura 1.5) | anticipación 650 ms (frames 0–5), activo 200 ms (6–7), recuperación 100 ms (8), enfriamiento 1.4 s |
| Paso de guardia | cada golpe que aguanta lo hace retroceder 22 px (10 + `guard_step_distance` 12) y no ataca durante 1.8 s (`guard_attack_delay`) |
| Interrupción | un golpe del jugador cancela la estocada; atacando no esquiva |
| Cómo vencerlo | esperar la estocada fuera de su alcance y contraatacar en la recuperación; dos golpes |
| Aparece | nivel 1 (3 en el mapa hecho a mano); generado desde el 2 (5 en el nivel 2) |
| Peso | `WEIGHT_SKELETON = 1.5` (efectivo 1.5 / 0.85 con la esquiva) |

Esquiva (todos los enemigos, `EnemyBase.dodge_chance`): esqueleto 15 %, calavera 10 %, vampiro 20 %, parca 10 %. Al esquivar no recibe daño, da un paso atrás de 8 px, parpadea en blanco translúcido y muestra «¡Esquiva!»; después no puede volver a esquivar durante 1 s. No esquiva aturdido, mientras ataca (vampiro, esqueleto) ni mientras embiste o se recupera (calavera).

### 3.3 Vampiro (perseguidor con mordisco)

| Campo | Valor |
|---|---|
| Archivos | `scripts/chaser_enemy.gd` (`ChaserEnemy`), `scenes/Vampire.tscn`, `enemies-vampire_*.png` |
| Rol | perseguidor cuerpo a cuerpo con ataque anunciado |
| Visual | piel gris azulada, ojos rojos, capa marrón, amuleto dorado; 14 colores |
| Stats | vida 3, velocidad 50 px/s, `contact_damage = 0` (solo lastima al morder) |
| Detección | detecta a 80 px, pierde a 120 px, no persigue si el jugador está a más de 140 px de su puesto (`leash_radius`) |
| Estados | en el puesto → persigue → ataca → enfriamiento → vuelve al puesto si lo pierde |
| Mordisco | empieza a 20 px (`attack_range`), alcance 26 px (`attack_reach`), daño 1, frames de impacto 9–10 |
| Tiempos del mordisco (16 frames a 14 FPS) | anticipación 643 ms (frames 0–8), activo 143 ms (9–10), recuperación 357 ms (11–15), enfriamiento 1.2 s |
| Interrupción | un golpe del jugador cancela el mordisco y empieza el enfriamiento |
| Cómo vencerlo | retroceder un paso durante la anticipación y contraatacar; es más lento que el jugador |
| Aparece | nivel 1 (6 en el mapa hecho a mano); generado desde el 2 |
| Peso | `WEIGHT_VAMPIRE = 2.0` |

### 3.4 Calavera embestidora

| Campo | Valor |
|---|---|
| Archivos | `scripts/skull_enemy.gd` (`SkullEnemy`), `scenes/Skull.tscn`, `monsters_idle/skull/v1/skull_v1_1..4.png` (16 × 16) |
| Rol | embestida en línea recta |
| Visual | calavera azul envuelta en llama espectral, ojos rojos; 6 colores |
| Stats | vida 2, cuerpo 8 × 8, contacto 12 × 12; daño 1 **solo mientras embiste** |
| Estados | `IDLE` → `WINDUP` (0.7 s, parpadeo rojo a 6 Hz) → `CHARGE` (150 px/s, hasta 0.6 s ≈ 90 px o hasta chocar con una pared) → `RECOVER` (1.0 s, tinte azulado, quieta) → enfriamiento 0.8 s |
| Detección | 90 px |
| Apuntado | fija la dirección **al final** de la carga: el jugador tiene los 0.7 s para salirse de la línea |
| Interrupción | un golpe cancela la carga o la embestida |
| Animaciones | `idle` 4 frames a 8 FPS (también se usa al moverse, `move_animation = &"idle"`), `hurt` 2 frames a 12 FPS, `death` 4 frames a 10 FPS más un inflado a 1.6× en 0.4 s; durante la embestida la animación va 2.5× más rápida |
| Cómo vencerla | moverse de costado durante la carga y golpearla mientras se recupera |
| Aparece | nivel 3 (40 % de los perseguidores, `SKULL_CHASER_SHARE = 0.4`) |
| Peso | `WEIGHT_SKULL = 2.5` |

### 3.5 Parca (jefe guardián)

| Campo | Valor |
|---|---|
| Archivos | `scripts/chaser_enemy.gd`, `scenes/Reaper.tscn`, `enemies-skeleton2_*.png` |
| Rol | jefe lento que custodia la puerta o la llave |
| Visual | esqueleto con capucha marrón y guadaña, a escala 1.4 (unos 22 px de alto); 11 colores |
| Stats | vida 5, velocidad 22 px/s, retroceso 4 px, corazón garantizado (`heart_drop_chance = 1.0`), contacto 1, cuerpo 14 × 10, contacto 18 × 20 |
| Detección | detecta a 90 px, pierde a 130 px, no se aleja más de 100 px de su puesto |
| Ataque | solo contacto (`attack_animation` vacío) |
| Colocación | a 3–8 celdas de la puerta (desde el nivel 3) y otra de la llave (desde el nivel 6) |
| Cómo vencerla | es la más lenta: golpear y alejarse; la correa de 100 px permite sacarla de la puerta |
| Aparece | nivel 1 (1 en el mapa hecho a mano); generada desde el 3 |
| Peso | `WEIGHT_BOSS = 6.0` |

Las hojas `enemies-skeleton2_attack.png` (15 frames, dos giros completos de guadaña) y `enemies-skeleton2_death2.png` (15 frames, la calavera sale volando) no se usan (ver 5.9).

### 3.6 Trampa de picos

| Campo | Valor |
|---|---|
| Archivos | `scripts/spike_trap.gd`, `scenes/SpikeTrap.tscn`, `items_and_traps/peaks/peaks_1..4.png` (16 × 16) |
| Ciclo `cycle` (6 FPS, 2.0 s en total) | abajo 667 ms (`peaks_3`) → aviso 333 ms (`peaks_4`, `peaks_2`) → **arriba 667 ms** (`peaks_1`, frame 3, `SPIKES_UP_FRAME`) → bajada 333 ms |
| Daño | 1, sin retroceso, área 12 × 12 |
| Desfase | `start_frame` 0 o 3 al azar en mapas generados |
| Aparece | nivel 1 (10); generadas desde el 2 (`HAZARDS_BASE = 5` + 1 por nivel, tope 18) |
| Peso | `WEIGHT_HAZARD = 0.5` |

### 3.7 Objetos

| Objeto | Archivos | Datos |
|---|---|---|
| Corazón | `scripts/heart.gd`, `scenes/Heart.tscn` | dibujo de 9 × 8 px generado en código (contorno `#3d0a12`, relleno `#d92633`, brillo `#ff9e9e`), flota 1.5 px, cura 1; si el jugador tiene todas las vidas se queda en el suelo |
| Llave | `scripts/key.gd`, `scenes/Key.tscn`, `keys/keys_1_1..4.png` | 4 frames a 6 FPS, área 10 × 10 |
| Puerta | `scripts/door.gd`, `scenes/Door.tscn` | región `Rect2(96, 96, 32, 16)` de `Dungeon_Tileset.png`, área 24 × 8; sin llave muestra "Necesitas la llave" |

### 3.8 Arte del proyecto que todavía no se usa

| Archivo | Contenido | Uso propuesto |
|---|---|---|
| `enemies-skeleton1_attack.png` | 9 frames, estocada con arco | en uso: estocada del esqueleto (3.2) |
| `enemies-skeleton2_attack.png` | 15 frames, dos giros de guadaña | ataque de la parca (5.9) |
| `enemies-skeleton2_death2.png` | 15 frames, muerte alternativa | variedad de muerte |
| `items_and_traps/flamethrower/flamethrower_1_*.png` (16 × 32) y `flamethrower_2_*.png` (32 × 16) | 4 frames: llama pequeña, llama grande, brasas, apagado | lanzallamas (5.11) |
| `items_and_traps/arrow/arrow_1..4.png` (16 × 32) y `Just_arrow.png` (16 × 16) | agujero en la pared y flecha | ballesta de pared (5.12) y flecha del arquero (5.1) |
| `items_and_traps/flasks/` | frascos rojos y azules, 4 frames | botín o mejoras |
| `priests_idle/priest1`, `priest2` | caballeros como el jugador | evitar como enemigos: se confunden con el jugador |
| `character_and_tileset/Dungeon_Character.png` (7 × 4 celdas de 16 px) | además de los anteriores: hombre calvo, personaje con sombrero de ala ancha, llama azul, esqueleto con daga | bases para el piromante, el nigromante o un fuego fatuo; solo 1 frame cada uno **(por verificar si hay más frames en otro archivo)** |
| `enemies/enemies.aseprite` | archivo fuente del pack de enemigos | etiquetas y capas **(por verificar)** |

## 4. Plantilla de ficha

Copiar y completar. Los campos de tiempo van en ms para comparar con la tabla de la sección 6.

```markdown
### <Nombre> (`<KIND>` = &"<kind>")

**Concepto:** una frase.
**Rol:** cuerpo a cuerpo | distancia | control de zona | apoyo/invocador | élite | enjambre
**Qué aporta que hoy no existe:** ...

| Visual | |
|---|---|
| Silueta y colores | ... (colores de la paleta 2.2 + acento) |
| Tamaño | frame 32 × 32 (o 16 × 16), personaje ~16 px de alto, escala en escena |
| Animaciones | idle (n, loop), walk (n, loop), attack (n), hurt (n), death (n) |

| Stats | |
|---|---|
| Vida / velocidad | ... / ... px/s |
| Daño por contacto | ... |
| Detección / pérdida / correa | ... / ... / ... px |
| Retroceso al recibir golpe | ... px |
| Probabilidad de corazón | ... |

**Estados:** `IDLE` → ... (condición de cada cambio)

| Ataque | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| ... | ... px | ... ms | ... ms | ... ms | ... ms | 1 | ... |

**Cómo vencerlo:** ...
**Reutiliza:** EnemyBase / ChaserEnemy / patrón de SkullEnemy / ...
**Código nuevo:** ...
**Generación:** primer nivel ..., máximo por mapa ..., separación ... celdas, reglas de colocación ...
**Peso en DifficultyCurve:** ...
**Prompt (EN):** prompt base de 2.6 con: ...
```

## 5. Propuestas nuevas

Cubren lo que hoy falta: ataques a distancia, control de zona, apoyo, enemigos acorazados, emboscadas, enjambres y enemigos que se dividen. Todas usan la estructura de `EnemyBase` y sus tres patrones de ataque: frames de impacto (`ChaserEnemy`), máquina de estados con tiempos (`SkullEnemy`) y contacto con invulnerabilidad del jugador.

### 5.1 Esqueleto arquero (`ARCHER` = &"archer")

**Concepto:** se mantiene a distancia y dispara flechas en línea recta. **Rol:** distancia. **Aporta:** el primer peligro que no hay que tocar para recibirlo.

| Visual | |
|---|---|
| Silueta y colores | esqueleto de `skeleton1` con arco corto y aljaba marrón; ojos rojos `#be2b25` |
| Animaciones | idle 6, walk 8–10, attack 8 (tensa, suelta, baja el arco), hurt 5, death 10–17 (se puede reutilizar la muerte de `skeleton1`) |
| Proyectil | `Just_arrow.png` rotado; según la vista previa apunta hacia abajo **(por verificar en el editor)** |

| Stats | vida 2 · velocidad 30 px/s · contacto 1 · detecta a 140 px, pierde a 180 px · retroceso 10 px · corazón 0.18 |
|---|---|

**Estados:** `IDLE` → `REPOSITION` (se aleja si el jugador está a menos de 56 px, se acerca si está a más de 120 px) → `AIM` (quieto) → `SHOOT` → `COOLDOWN`.

| Ataque | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| Flecha | 160 px | 600 ms (fija la dirección a los 450 ms) | vuelo a 120 px/s | 300 ms | 1600 ms | 1 | arco tensado + línea roja tenue hacia el jugador |

**Cómo vencerlo:** acercarse en diagonal; la flecha se rompe contra paredes y con la espada.
**Reutiliza:** frames de impacto de `ChaserEnemy` para soltar la flecha; el apuntado tardío de `SkullEnemy`.
**Código nuevo:** escena `scenes/Arrow.tscn` (`Area2D` con capa 3 para que la espada la detecte y máscara 1 + 2 para chocar con paredes y jugador; llama a `take_damage(1, global_position)` y tiene `take_hit()` para romperse). Un rayo (`PhysicsRayQueryParameters2D` contra la capa 1) para no disparar a través de paredes.
**Generación:** desde el nivel 8, máximo 4, separación `ENEMY_SPACING`.
**Peso:** 2.5.
**Prompt (EN):** `skeleton archer holding a short wooden bow, brown leather quiver, glowing red eyes`; animación `drawing the bow, releasing an arrow, lowering the bow`.

### 5.2 Guardián acorazado (`SHIELD_GUARD` = &"shield_guard")

**Concepto:** armadura negra con escudo de torre; bloquea los golpes de frente. **Rol:** cuerpo a cuerpo acorazado. **Aporta:** obliga a rodear o a esperar la apertura.

| Visual | |
|---|---|
| Silueta y colores | ancho y bajo, armadura `#3e4652`/`#6d758d`, escudo con borde dorado `#d9701a`, ojos rojos tras la visera. **No** reutilizar `priest1`/`priest2`: se confunden con el jugador |
| Animaciones | idle 4–6, walk 8, attack 10 (levanta el arma, golpe al suelo), block 3 (sin loop), hurt 5, death 12 |

| Stats | vida 4 · velocidad 28 px/s · contacto 1 · detecta a 90 px, pierde a 130 px, correa 140 px · retroceso 4 px · corazón 0.3 |
|---|---|

**Estados:** igual que el vampiro, más `BLOCK` al recibir un golpe de frente.

| Ataque | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| Golpe de maza | inicia a 22 px, alcanza 30 px | 800 ms | 150 ms | 700 ms (escudo bajo, vulnerable de frente) | 1500 ms | 1 | arma en alto + parpadeo rojo los últimos 300 ms |

**Cómo vencerlo:** golpearlo de costado o por detrás, o de frente durante la recuperación.
**Reutiliza:** `ChaserEnemy` completo (persecución, ataque por frames, cancelación).
**Código nuevo:** sobrescribir `take_hit(amount, from_position)`: si `(from_position - global_position)` apunta hacia donde mira (`flip_h`) y no está en recuperación, reproducir `block`, `Sfx` propio y no restar vida. Para empujar al jugador al bloquear hace falta un método público en `player.gd` (hoy `_apply_knockback` es privado y `take_damage` siempre quita vida).
**Generación:** desde el nivel 10, máximo 3.
**Peso:** 3.0.
**Prompt (EN):** `undead knight in black plate armor with a tall tower shield and a mace, red eyes glowing behind the visor`.

### 5.3 Enjambre de murciélagos (`BAT_SWARM` = &"bat_swarm")

**Concepto:** tres murciélagos que entran, muerden y se alejan. **Rol:** enjambre. **Aporta:** varios objetivos pequeños a la vez.

| Visual | |
|---|---|
| Silueta y colores | murciélago de 10–12 px en frame de 16 × 16 o 32 × 32, alas `#5e4e3a`, cuerpo `#4b3726`, ojos rojos |
| Animaciones | fly 4 (loop, también como idle y walk), hurt 2, death 4 |

| Stats (por murciélago) | vida 1 · velocidad 70 px/s · contacto 1 · detecta a 100 px · retroceso 14 px · corazón 0.05 |
|---|---|

**Estados:** `IDLE` (revolotea en su lugar) → `SWOOP` (persigue con una ondulación lateral de ±6 px) → al tocar al jugador `RETREAT` 800 ms en dirección opuesta → `SWOOP`.

| Ataque | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| Picotazo por contacto | cuerpo | 0 (se ve venir: 70 px/s) | contacto | 800 ms de huida | — | 1 | chillido (`Sfx`) al detectar |

**Cómo vencerlo:** un golpe mata a cada uno; la invulnerabilidad de 1.5 s evita que los tres hagan daño seguido.
**Reutiliza:** daño por contacto de `EnemyBase`; persecución como `ChaserEnemy` con `attack_animation` vacío.
**Código nuevo:** un `Spawn` del generador crea 3 murciélagos alrededor de la celda (`LevelBuilder._make_enemy` instancia 3). Cada uno es un enemigo para el contador de muertes.
**Generación:** desde el nivel 11, máximo 3 grupos, 1 celda por grupo.
**Peso:** 2.4 por grupo (0.8 por murciélago).
**Prompt (EN):** `small cave bat with brown leathery wings and red eyes, flying loop`.

### 5.4 Piromante (`PYROMANCER` = &"pyromancer")

**Concepto:** hechicero que marca el suelo bajo el jugador y lo hace estallar. **Rol:** control de zona. **Aporta:** obliga a moverse, castiga quedarse quieto.

| Visual | |
|---|---|
| Silueta y colores | túnica `#79191d`, sombrero de ala ancha (puede partir del personaje con sombrero de `Dungeon_Character.png`), manos con fuego `#ffd569` |
| Animaciones | idle 6, walk 8, cast 8–10 (levanta las manos), hurt 5, death 10 |
| Efecto | marca circular en el suelo de 32 px (2 frames de pulso) y explosión de 3–4 frames; puede reutilizar los colores de `flamethrower` |

| Stats | vida 2 · velocidad 25 px/s · contacto 0 · detecta a 150 px · mantiene 70–130 px · corazón 0.25 |
|---|---|

**Estados:** `IDLE` → `REPOSITION` → `CAST` (fija la marca donde está el jugador **al empezar**) → `COOLDOWN`.

| Ataque | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| Estallido | marca a hasta 150 px, radio 20 px | 900 ms (marca visible todo ese tiempo) | 150 ms | 500 ms | 2500 ms | 1 | círculo que se cierra + manos encendidas |

**Cómo vencerlo:** seguir moviéndose; tiene poca vida y no lastima por contacto.
**Reutiliza:** máquina de estados de `SkullEnemy` (`_enter(state, duration)`); `take_damage(1, centro)` para que el jugador salga empujado desde el centro.
**Código nuevo:** escena `scenes/FireMark.tscn` (`Area2D` máscara 2, temporizador propio). Se agrega con `call_deferred` al nodo del nivel.
**Generación:** desde el nivel 12, máximo 3.
**Peso:** 3.0.
**Prompt (EN):** `pyromancer in a dark red robe and wide-brimmed hat, small flames in both hands`; animación `raising both hands to cast a fire spell`.

### 5.5 Espectro (`WRAITH` = &"wraith")

**Concepto:** casi invisible; aparece al lado del jugador y araña. **Rol:** emboscada. **Aporta:** ataques desde ángulos inesperados, pero siempre anunciados.

| Visual | |
|---|---|
| Silueta y colores | figura encapuchada sin piernas, azul espectral `#577ea1`/`#a7d1e6`, ojos `#62abd4` |
| Animaciones | idle 4–6, fade_out 4, fade_in 4, attack 8 (zarpazo), hurt 3, death 8 |

| Stats | vida 3 · velocidad 40 px/s · contacto 0 · detecta a 110 px · corazón 0.25 |
|---|---|

**Estados:** `HIDDEN` (deriva hacia el jugador con `modulate.a = 0.25`, se le puede pegar) → `FADE_OUT` 300 ms → `MARKED` (marca de humo en el destino, a 32 px a un costado del jugador) → `FADE_IN` → `ATTACK` → `RECOVER` 1000 ms (visible del todo) → `HIDDEN`.

| Ataque | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| Aparición + zarpazo | aparece a 32 px, alcanza 26 px | 600 ms de marca + 400 ms de zarpazo | 143 ms | 1000 ms | 3000 ms | 1 | humo en el suelo en el destino |

**Cómo vencerlo:** al ver el humo, alejarse y golpearlo durante la recuperación.
**Reutiliza:** frames de impacto de `ChaserEnemy`; estados con tiempo de `SkullEnemy`.
**Código nuevo:** validar el destino con una consulta de punto contra la capa 1 (`PhysicsPointQueryParameters2D`) para no aparecer dentro de una pared; si falla, probar el otro costado. Un tinte de transparencia propio: la transparencia con parpadeo ya significa "jugador invulnerable", así que el espectro debe usar transparencia **fija**.
**Generación:** desde el nivel 13, máximo 3.
**Peso:** 3.0.
**Prompt (EN):** `hooded wraith with no legs, translucent pale blue cloak, glowing cyan eyes, clawed hands`.

### 5.6 Nigromante (`NECROMANCER` = &"necromancer")

**Concepto:** levanta esqueletos y huye. **Rol:** apoyo / invocador. **Aporta:** una prioridad de objetivo.

| Visual | |
|---|---|
| Silueta y colores | túnica negra `#25131a`/`#3e4652` con capucha, báculo con calavera, luz verde o violeta claro como acento propio |
| Animaciones | idle 6, walk 8, summon 10, hurt 5, death 12 |

| Stats | vida 3 · velocidad 30 px/s · contacto 0 · detecta a 140 px · mantiene 80–140 px · corazón 0.5 |
|---|---|

**Estados:** `IDLE` → `FLEE`/`REPOSITION` → `SUMMON` (si tiene menos de 2 esbirros vivos) → `COOLDOWN`.

| Ataque | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| Invocar esqueleto | círculo a 24–40 px de sí mismo | 1000 ms (círculo en el suelo donde sale) | — | 600 ms | 6000 ms | — | círculo + báculo brillante |

**Cómo vencerlo:** ir por él primero; al morir, sus esbirros se desmoronan.
**Reutiliza:** el esqueleto existente (`scenes/Skeleton.tscn`) con `patrol_offset = Vector2.ZERO` y `heart_drop_chance = 0`.
**Código nuevo:** el nivel cuenta y conecta a los enemigos una sola vez en `level.gd` `_ready`; un esbirro creado después no suma al contador del HUD ni conecta `died`. Opciones: una señal `minion_spawned(enemy)` que el nivel conecte igual que los demás, o marcar a los esbirros para que no cuenten. Crear el esbirro con `call_deferred`.
**Generación:** desde el nivel 15, máximo 2.
**Peso:** 4.0 (incluye a sus esbirros).
**Prompt (EN):** `necromancer in a tattered black hooded robe holding a staff topped with a skull, faint green magic glow`.

### 5.7 Limo divisor (`SLIME` = &"slime")

**Concepto:** al morir se parte en dos limos pequeños. **Rol:** divisor. **Aporta:** la pelea sigue después del golpe final.

| Visual | |
|---|---|
| Silueta y colores | gota de 14 px de ancho; verde apagado o el rojo `#9b534a` para que contraste con el suelo violeta; ojos y brillo en `#e6e6e6` |
| Animaciones | idle 4, hop 6 (aplasta, salta, cae), hurt 3, death 6 |

| Stats | grande: vida 3, 45 px/s durante el salto · pequeño (escala 0.6): vida 1, 55 px/s · contacto 1 · detecta a 90 px · corazón 0.1 (grande) / 0 (pequeños) |
|---|---|

**Estados:** `IDLE` → `HOP` (400 ms en movimiento) → `PAUSE` (600 ms quieto) → `HOP` …

| Ataque | Alcance | Anticipación | Activo | Recuperación | Enfriamiento | Daño | Aviso visual |
|---|---|---|---|---|---|---|---|
| Salto por contacto | cuerpo | 150 ms de aplastarse antes de saltar | 400 ms | 600 ms | — | 1 | se aplasta |

**Cómo vencerlo:** golpear durante la pausa; dejar espacio para los dos pequeños.
**Reutiliza:** daño por contacto de `EnemyBase`; el patrón de corazón diferido (`_try_drop_heart` + `call_deferred`) para crear a los hijos.
**Código nuevo:** sobrescribir `_die()` para pedir los hijos al nivel (mismo problema de contador que el nigromante).
**Generación:** desde el nivel 16, máximo 3.
**Peso:** 3.0 (2.0 + 0.5 por hijo).
**Prompt (EN):** `small blob slime with two white eyes, glossy highlight`; animación `squash, jump and land`.

### 5.8 Modificadores de élite

Variedad sin arte nuevo: el generador marca a algunos enemigos comunes como élite.

| Modificador | Efecto | Identificación visual | Multiplicador de peso |
|---|---|---|---|
| Veloz | velocidad ×1.3, enfriamientos ×0.8 | tinte amarillo pálido | ×1.3 |
| Acorazado | vida +2, retroceso ×0.4 | escala 1.15 | ×1.4 |
| Enfurecido | con vida ≤ 50 %: velocidad ×1.4 y enfriamientos ×0.6 | tinte naranja al activarse | ×1.25 |
| Explosivo | al morir deja una marca de 600 ms y estalla con radio 20 px | parpadeo naranja lento | ×1.3 |
| Regenerador | recupera 1 de vida cada 4 s sin recibir golpes | partículas verdes | ×1.2 |

Reglas:

- El tinte va en el `modulate` del **nodo raíz** del enemigo, no en el del sprite: `_flash_red` devuelve el sprite a `Color.WHITE` y `SkullEnemy._enter` también lo pisa. El `modulate` del padre se multiplica con el del hijo, así el destello rojo se sigue viendo.
- Los cambios se aplican antes de `add_child` (como `patrol_offset` en `LevelBuilder._make_enemy`): `EnemyBase._ready` copia `max_health` a `health`.
- Un enemigo tiene como máximo un modificador. Los jefes no los reciben.

### 5.9 Ataques nuevos con el arte que ya existe

| Enemigo | Cambio | Datos |
|---|---|---|
| Esqueleto espadachín (`SKELETON_GUARD`) | `skeleton1` con la hoja de ataque de 9 frames: patrulla y, si el jugador entra a 20 px, ataca | **hecho** (ver 3.2): impacto en los frames 6–7, 10 FPS con el frame 5 a 1.5 (anticipación 650 ms). Peso 1.5 |
| Parca con guadaña | `Reaper.tscn` con `attack_animation = &"attack"` y la hoja de 15 frames | dos giros completos, con impacto estimado en los frames 5–6 y 10–11 **(por verificar)**. `ChaserEnemy` admite una sola ventana (`attack_hit_frames`) y un golpe por ataque: hay que pasarla a varias ventanas y reiniciar `_attack_hit_done` en cada una. Anticipación ≥ 650 ms ajustando `duration`. Alcance unos 28 px (el arco mide 30 px × 1.4 de escala). Peso de jefe propuesto 7.5 |

### 5.10 Runa ígnea (trampa, `RUNE` = &"rune")

| Campo | Valor |
|---|---|
| Concepto | losa con una runa que estalla un momento después de pisarla |
| Visual | baldosa de 16 × 16 con runa grabada `#4c2f49` que brilla `#d9701a` → `#ffd569`; arte nuevo |
| Ciclo | pisada → brillo 600 ms → estallido 150 ms, radio 20 px → recarga 3000 ms (apagada) |
| Daño | 1, con retroceso desde el centro (`take_damage(1, global_position)`) |
| Cómo evitarla | seguir caminando: a 80 px/s se recorren 48 px en 600 ms |
| Reutiliza | `spike_trap.gd` (revisión por frame de `get_overlapping_bodies`) |
| Generación | desde el nivel 16, máximo 6, en el suelo, separación `HAZARD_SPACING` |
| Peso | 0.8 |
| Prompt (EN) | `16x16 pixel art dungeon floor tile with an engraved rune, dark purple stone, the rune glowing orange, 4 frames from dark to bright` |

### 5.11 Lanzallamas de pared (trampa, `FLAMETHROWER` = &"flamethrower")

| Campo | Valor |
|---|---|
| Concepto | boquilla en la pared que lanza un chorro de 2 celdas |
| Visual | arte existente: `flamethrower_1_*.png` (vertical, 16 × 32) y `flamethrower_2_*.png` (horizontal, 32 × 16); hacia dónde apunta la horizontal **(por verificar)** |
| Ciclo | apagado 1500 ms (frame 4) → aviso 500 ms (frame 1, llama pequeña) → activo 700 ms (frame 2) → brasas 300 ms (frame 3) |
| Daño | 1, área de 12 × 28 px, retroceso desde la boquilla |
| Cómo evitarlo | cruzar durante el apagado; el aviso de 500 ms basta para frenar |
| Reutiliza | `spike_trap.gd`: frame activo + `duration` por frame en `SpriteFrames` |
| Generación | desde el nivel 9, máximo 6; va en una pared frontal con suelo debajo, como las antorchas (`_is_torch_wall`). No ocupa celdas de suelo pero sí reserva las 2 del chorro |
| Peso | 1.0 |

### 5.12 Ballesta de pared (trampa, `CROSSBOW` = &"crossbow")

| Campo | Valor |
|---|---|
| Concepto | agujero en la pared que dispara flechas por el pasillo |
| Visual | arte existente: `arrow_1..4.png` (16 × 32) y `Just_arrow.png`; orden exacto de los frames **(por verificar)** |
| Ciclo | cada 2500 ms: chasquido y frame de aviso 400 ms → flecha a 140 px/s hasta chocar con una pared |
| Daño | 1, con retroceso |
| Cómo evitarla | cruzar la línea justo después de un disparo; la espada rompe la flecha |
| Reutiliza | `scenes/Arrow.tscn` del arquero (5.1) |
| Generación | desde el nivel 12, máximo 6, en una pared frontal que mire a un tramo de suelo de al menos 4 celdas |
| Peso | 1.0 |

## 6. Catálogo de ataques

### 6.1 Reglas de tiempo

Valores de referencia del juego actual: aviso de los picos 333 ms (ciclo fijo y visible), mordisco del vampiro 643 ms, carga de la calavera 700 ms.

| Regla | Valor |
|---|---|
| Aviso mínimo de una trampa con ciclo fijo | 333 ms (como los picos) |
| Aviso mínimo de un ataque dirigido al jugador | 600 ms |
| Aviso de un área de radio `r` | ≥ `r / 80 + 0.25` s (80 px/s es la velocidad del jugador); radio 20 px → ≥ 500 ms, se proponen 600–900 ms |
| Proyectiles | ≤ 140 px/s (el jugador esquiva 10 px de costado en 125 ms) |
| Apuntado | fijarlo antes de soltar el ataque: como mínimo 150 ms antes del impacto |
| Daño | 1. Daño 2 solo en élites o jefes, con aviso ≥ 900 ms |
| Ventana de castigo | recuperación ≥ 300 ms después de cada ataque (vampiro 357 ms, calavera 1000 ms) |
| Interrupción | un golpe del jugador cancela el ataque en curso (como `ChaserEnemy.take_hit` y `SkullEnemy.take_hit`) |
| Velocidad de persecución | < 80 px/s; el más rápido propuesto es el murciélago, con 70 px/s |
| Alcance a distancia | ≤ 160 px horizontal y ≤ 100 px vertical, para que el atacante esté en pantalla (unos 384 × 216 px visibles) |

### 6.2 Patrones

| Patrón | Descripción | Aviso / activo / recuperación | Implementación base | Lo usan |
|---|---|---|---|---|
| Contacto | daña al tocar, cada frame | 0 / continuo / — | `EnemyBase._damage_touching_bodies` | esqueleto, parca, murciélagos, limo |
| Golpe por frames | animación con frames de impacto y alcance | 600–800 / 140–150 / 350–700 ms | `ChaserEnemy` (`attack_hit_frames`, `attack_reach`) | vampiro, guardián, espadachín, espectro |
| Barrido circular | como el anterior, sin importar el ángulo, con varias ventanas | ≥ 650 / 2 ventanas / 500 ms | `ChaserEnemy` con varias ventanas | parca con guadaña |
| Embestida | carga, línea recta, aturdimiento | 700 / hasta 600 / 1000 ms | `SkullEnemy` | calavera |
| Proyectil | objeto que viaja y choca con paredes | 400–600 / vuelo / 300 ms | `Arrow.tscn` nuevo | arquero, ballesta |
| Marca en el suelo | área que estalla después de un aviso | 600–900 / 150 / — | `FireMark.tscn` nuevo + patrón de `spike_trap.gd` | piromante, runa, élite explosivo |
| Chorro | área alargada fija en ciclo | 500 / 700 / 300 ms | `spike_trap.gd` con otra forma | lanzallamas |
| Aparición | desaparece y aparece junto al jugador | 600 + 400 / 143 / 1000 ms | estados de `SkullEnemy` + golpe por frames | espectro |
| Invocación | crea enemigos | 1000 / — / 600 ms | `Skeleton.tscn` + `call_deferred` | nigromante |
| División | crea enemigos al morir | — | `_die()` + `call_deferred` | limo |
| Golpe y huida | toca y se aleja | 0 / contacto / 800 ms | contacto + estado de huida | murciélagos |
| Ciclo de trampa | daña en ciertos frames del ciclo | 333 / 667 / 333 ms | `spike_trap.gd` | picos |

## 7. Cómo integrar un enemigo nuevo

Ejemplo con el arquero (`ARCHER`). Para trampas, ver el paso 9.

1. **Arte.** Guardar las tiras como `assets/enemies/enemies-archer_<idle|movement|attack|take_damage|death>.png` (frames de 32 × 32). Correr el script de 2.6. Anotar el origen en `assets/CREDITS.md`.
2. **Escena `scenes/Archer.tscn`.** Copiar la estructura de `scenes/Vampire.tscn`:
   - raíz `CharacterBody2D`: `collision_layer = 4`, `motion_mode = 1`, script del enemigo;
   - `AnimatedSprite2D` con `offset = Vector2(0, -5)` y un `SpriteFrames` con `idle`/`walk` en loop y `hurt`/`death`/`attack` sin loop (una `AtlasTexture` de 32 × 32 por frame);
   - `CollisionShape2D` 10 × 8 en `(0, 4)`;
   - `ContactArea` (`Area2D`: `collision_layer = 0`, `collision_mask = 2`, `monitorable = false`) con un rectángulo de 12 × 14 en `(0, 1)`.
   - Si la animación tiene otro nombre, cambiar las propiedades `idle_animation`, `move_animation`, `hurt_animation`, `death_animation`.
3. **Script `scripts/archer_enemy.gd`** con `class_name ArcherEnemy` que extienda `EnemyBase` (o `ChaserEnemy` si persigue y ataca por frames):
   - `_get_move_velocity(delta)`: decide el movimiento y avanza la máquina de estados;
   - `is_alerted()`: `true` mientras persigue o ataca (cambia la música en `level.gd`);
   - `take_hit(amount, from_position)`: cancela el ataque y empieza el enfriamiento antes de `super()`;
   - `_damage_touching_bodies()`: sobrescribir si solo lastima en ciertos estados (como la calavera);
   - parámetros con `@export` y comentarios `##` en español, como los scripts actuales.
4. **`scripts/level_generator.gd`:**
   - constante `const ARCHER := &"archer"` junto a `SKELETON`, `VAMPIRE`, etc.;
   - constantes de balance arriba del archivo: `ARCHER_FIRST_LEVEL`, `ARCHERS_PER_LEVEL`, `ARCHERS_MAX`;
   - campo `var archer_count := 0` en `Params` y su cálculo en `params_for_level`;
   - colocarlos en `_place_enemies` después de los perseguidores, con `_is_spaced(cell, taken, ENEMY_SPACING)` y `taken.append(cell)`;
   - `validate` ya rechaza patrullas de todo lo que no sea `SKELETON`.
   - Decidir si el tipo nuevo **se suma** a `ENEMIES_MAX` (más entidades) o **reemplaza** parte de los comunes (más peso sin ocupar más celdas). La sección 8 asume que se suma.
5. **`scripts/level_builder.gd`:** agregar `LevelGenerator.ARCHER: preload("res://scenes/Archer.tscn")` a `ENEMY_SCENES`. Las propiedades por instancia (élites, grupos) se asignan en `_make_enemy` antes de devolver el nodo.
6. **`scripts/difficulty_curve.gd`:**
   - `const WEIGHT_ARCHER := 2.5` con su comentario;
   - sumarlo en `index_for` y agregar la clave en `_enemy_counts`, `report` y las columnas de `save_csv`;
   - si tiene tope propio, agregarlo a `capped_params`;
   - en `capacity_report`, `requested_enemies` hoy es `params.enemy_count + params.boss_count`: sumar el tipo nuevo o `test_generated_levels_place_what_they_request` va a fallar.
7. **Pruebas** (`McpTestSuite`, se corren con el plugin godot-ai):
   - `tests/test_archer_enemy.gd`, siguiendo `tests/test_skull_enemy.gd`: la escena tiene `hurt`/`death` sin loop y `attack` con los frames de impacto dentro del rango; los estados avanzan llamando a `_get_move_velocity(delta)` con un `TargetStub` (`Node2D` que cuenta `take_damage`); un golpe cancela el ataque; `is_alerted()` en cada estado; no daña fuera de los frames o estados de impacto;
   - armar el enemigo con el script y nodos hijos como `_make_skull`, porque en el editor un script que no es `@tool` solo corre así;
   - `tests/test_level_generator.gd`: agregar el tipo a `test_builder_has_a_scene_for_every_generated_enemy_kind` y una prueba como `test_skulls_appear_from_the_configured_level`;
   - `tests/test_difficulty_curve.gd`: actualizar `test_index_uses_the_documented_weights` y `test_index_for_level_matches_hand_computed_value` si cambian los números de esos niveles.
8. **Nivel (`scripts/level.gd`).** No requiere cambios si el enemigo existe desde la generación: entra al grupo `"enemies"` en `EnemyBase._ready` y el nivel conecta `died` (contador, puntaje y corazón). Los enemigos creados después (invocación, división) necesitan el arreglo de 5.6.
9. **Trampas nuevas.** Hoy todas las trampas son picos: `LevelBuilder._make_trap` siempre instancia `SPIKE_TRAP_SCENE` y `LevelGenerator.validate` exige `hazard.frame` entre 0 y 3. Hay que pasar a un diccionario `TRAP_SCENES` por `kind`, limitar la regla del frame a `SPIKES`, sumar `WEIGHT_*` en `DifficultyCurve` y, para trampas de pared, una función de colocación como `_place_torches` / `_is_torch_wall`.
10. **Probar en juego** con el modo prueba de dificultad (`DifficultyReport.tscn`), que muestra el índice por nivel y los topes alcanzados.

## 8. Propuesta de curva

> **Nota:** desde que se escribió esta sección la vida de los enemigos crece un 8 % de la base por nivel y `index_for` multiplica la parte de enemigos por ese factor, así que la columna «Índice actual» ya no refleja el código (por ejemplo, el nivel 14 pasó de 65.5 a 212.4).

**Esto es una estimación.** Usa la fórmula de `DifficultyCurve.index_for` con los pesos actuales (1.0 / 2.0 / 2.5 / 6.0 / 0.5) y los propuestos en la sección 5. Supuestos:

- los tipos nuevos se suman a los comunes, no los reemplazan;
- un grupo de murciélagos ocupa 1 celda de aparición;
- élite: multiplicador medio de 1.29 (la media de la tabla de 5.8) sobre el peso de todos los enemigos, jefes incluidos; las trampas no cuentan;
- desde el nivel 9 la parca pesa 7.5 (ataque de guadaña);
- en cada nivel se agrega lo mínimo para llegar a +10 %, repartiendo entre los tipos ya disponibles.

| Nivel | Índice actual | Se agrega respecto del nivel anterior | Índice estimado | Crecimiento |
|---|---|---|---|---|
| 7 | 51.0 | — | 51.0 | +13.3 % |
| 8 | 55.0 | **arquero** ×1 | 57.5 | +12.7 % |
| 9 | 58.5 | **lanzallamas** ×1, **parca con guadaña** | 65.0 | +13.0 % |
| 10 | 63.5 | **guardián acorazado** ×1 | 73.0 | +12.3 % |
| 11 | 64.0 | **murciélagos** ×2 grupos, arquero +1, lanzallamas +1 | 81.8 | +12.1 % |
| 12 | 64.5 | **piromante** ×1, **ballesta** ×2, guardián +1, lanzallamas +1 | 91.3 | +11.6 % |
| 13 | 65.0 | **espectro** ×2, piromante +1 | 100.8 | +10.4 % |
| 14 | 65.5 | **élites** 30 %, arquero +1, ballesta +1 | 112.6 | +11.7 % |
| 15 | 65.5 | **nigromante** ×2, élites 40 %, lanzallamas +1, ballesta +1 | 126.1 | +12.0 % |
| 16 | 65.5 | **limo** ×2, **runa ígnea** ×4, murciélagos +1 grupo, lanzallamas +1 | 139.7 | +10.8 % |
| 17 | 65.5 | guardián +1, piromante +1, espectro +1, limo +1, runa +1 | 153.9 | +10.2 % |
| 18 | 65.5 | élites 50 %, arquero +1, lanzallamas +1, ballesta +2, runa +1 (todo al tope) | 164.0 | +6.6 % |
| 19+ | 65.5 | — | 164.0 | 0 % |

Topes por mapa en el nivel 18: 4 arqueros, 3 guardianes, 3 grupos de murciélagos, 3 piromantes, 3 espectros, 2 nigromantes, 3 limos y 6 trampas de cada tipo nuevo.

Lectura:

- Con este contenido, la curva cumple +10 % hasta el nivel 17 (hoy deja de cumplir en el 8) y llega al tope en el 18.
- En el nivel 17 hay 20 celdas extra de enemigos. Los mapas al tope tienen sitio para 15–38 enemigos más según la semilla: en las semillas más justas no entraría todo. El generador coloca lo que cabe, así que el índice real puede quedar por debajo de la estimación. Hay que medirlo con `DifficultyCurve.capacity_report`.
- Las trampas de pared no ocupan celdas de suelo para enemigos. Las runas sí, pero hay sitio para 66–144 trampas más.
- Un crecimiento compuesto de +10 % no se sostiene indefinidamente con un mapa que deja de crecer en el nivel 13: el nivel 30 pediría un índice de unos 457. Pasado el nivel 17 hay que elegir entre mantener el índice y rotar la composición para que cada nivel sea distinto, bajar el objetivo de crecimiento a partir de cierto nivel, o agregar otra fuente de dificultad (un tercer jefe o subir `GRID_MAX`). `test_every_level_meets_the_target_growth` va a seguir fallando desde el 18 con cualquiera de las tres.
- Los pesos nuevos son supuestos, igual que los actuales (ver el comentario de `difficulty_curve.gd`): conviene ajustarlos con los datos de `difficulty_playtest.csv` después de probarlos.
