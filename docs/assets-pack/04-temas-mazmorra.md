# Temas de mazmorra

Hay tres temas nuevos, cada uno con sus colores y sus símbolos. Sirven para que el jugador note que avanzó a otra zona.

| Tema | Carpeta | Colores | Símbolo | Niveles propuestos | Jefe |
|---|---|---|---|---|---|
| Calabozo actual | — | violeta y marrón | — | 1–4 | parca |
| Cripta helada | `assets/dungeon_themes/ice/` | azul gris, escarcha `#d8f0f8` | copo de nieve, triángulo invertido | 5–8 | Reina liche (nivel 8) |
| Fragua de lava | `assets/dungeon_themes/lava/` | obsidiana y rojo, lava `#ff8a2a` | llama, triángulo de fuego | 9–12 | Forjador de magma (nivel 12) |
| Ruinas con musgo | `assets/dungeon_themes/moss/` | piedra verde, musgo `#6b8f3a` | hoja, espiral | 13–16 | Guardián musgoso (nivel 16) |

## Objetos por tema (16 × 16)

Cada carpeta trae los mismos 7 tipos de objeto, con el prefijo del tema (`ice_`, `lava_`, `moss_`):

| Archivo | Frames | Dónde va | Colisión |
|---|---|---|---|
| `<tema>_torch.png` | 4, a 8 FPS, en loop | pared frontal, igual que las antorchas actuales (`_is_torch_wall`) | no |
| `<tema>_banner.png` | 1 | pared frontal; estandarte con el símbolo del tema | no |
| `<tema>_emblem.png` | 4, a 4 FPS, en loop | pared frontal; emblema de piedra con una runa que brilla | no |
| `<tema>_floor_rune.png` | 4, a 4 FPS, en loop | suelo; sirve para marcar la sala del jefe o la de la llave | no |
| `<tema>_floor_patch.png` | lava y hielo: 4 frames; musgo: 1 | suelo; grieta con lava, escarcha o musgo. En el tema musgo el Guardián se cura parado encima | no |
| `<tema>_prop.png` | 4, a 6 FPS, en loop | suelo: brasero, cristal de hielo o seta luminosa | **sí**, ocupa 1 celda |
| `<tema>_scatter.png` | 3 variantes en una tira | suelo, decoración al azar | no |

Los que están animados traen su `<tema>_<objeto>_frames.tres` (animación `default`).

Las manchas y las runas de suelo no tienen contorno, para que se lean como parte del piso. El resto lleva el contorno `#25131a` del estilo del juego.

## Piso y paredes: el tileset recoloreado

`tools/retheme.py` cambia los tonos de suelo y paredes del tileset actual por la rampa de colores de cada tema. Respeta el contorno y el acomodo de la imagen. Las coordenadas del atlas no cambian, así que `dungeon_tileset.tres` y sus colisiones sirven tal cual: solo hay que cambiar la textura.

Solo recolorea los tiles de suelo y pared (`ENV_TILES`): la madera de puertas y cofres comparte tonos con las paredes, así que filtrar por color no alcanza. Al terminar comprueba que ningún píxel fuera de esos tiles cambió (puertas, cofres, llaves, monedas, pociones y antorchas quedan idénticos).

```
D=assets/dungeon/character_and_tileset
python3 tools/retheme.py $D/Dungeon_Tileset.png $D/Dungeon_Tileset_ice.png  ice
python3 tools/retheme.py $D/Dungeon_Tileset.png $D/Dungeon_Tileset_lava.png lava
python3 tools/retheme.py $D/Dungeon_Tileset.png $D/Dungeon_Tileset_moss.png moss
```

Los tilesets generados quedan junto al original porque son derivados de Pixel_Poem y siguen su licencia.

## Integración en el juego

- `scripts/dungeon_theme.gd` (`DungeonTheme`): tema de cada nivel en tramos de 4. Niveles 1–4 calabozo, 5–8 hielo, 9–12 lava, 13–16 musgo; el último nivel de cada tramo es el del jefe del tema. Desde el 17 los tramos siguen rotando (17–20 hielo, 21–24 lava...). `themed_tile_set()` duplica el `TileSet` del nivel y cambia la textura del atlas, sin tocar el recurso compartido ni copiar la definición de los tiles.
- `scripts/theme_decor.gd` (`ThemeDecor`): cambia el tileset del mapa y del fondo y coloca la decoración, determinista con `hash([run_seed, nivel, "decoracion"])`. Las antorchas del tema van en las mismas celdas que las actuales (`LevelBuilder.torch_frames`). Nada se coloca sobre el inicio, la llave, la puerta, enemigos (con su patrulla), trampas ni monedas sueltas. El objeto grande (`prop`) tiene colisión y solo va en celdas rodeadas de suelo, separado de todo, así nunca corta un camino.
- Las manchas y las runas de suelo quedan en los grupos `theme_floor_patches` y `theme_floor_runes`, para los jefes.
