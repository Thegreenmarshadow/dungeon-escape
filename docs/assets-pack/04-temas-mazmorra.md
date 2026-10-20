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

```
python3 tools/retheme.py tilesets/Dungeon_Tileset.png tilesets/Dungeon_Tileset_ice.png  ice
python3 tools/retheme.py tilesets/Dungeon_Tileset.png tilesets/Dungeon_Tileset_lava.png lava
python3 tools/retheme.py tilesets/Dungeon_Tileset.png tilesets/Dungeon_Tileset_moss.png moss
```

> **Pendiente.** Los colores que se cambian (`ENV` en `retheme.py`) salen de la paleta 2.2 y de la imagen de muestra del pack. Para dejarlos exactos, sin teñir la madera de puertas y cofres, hacen falta `Dungeon_Tileset.png`, `dungeon_tileset.tres` y `level_builder.gd`. Con esos archivos genero los tres tilesets y dejo integrado el cambio de tema según el nivel.

### Cambiar el tema según el nivel (esquema)

```gdscript
# level_builder.gd: los nombres son de ejemplo; hay que ajustarlos a como el builder arma el TileMap
const THEMES := [
    {"from": 1,  "id": &"dungeon", "tiles": "res://tilesets/Dungeon_Tileset.png"},
    {"from": 5,  "id": &"ice",     "tiles": "res://tilesets/Dungeon_Tileset_ice.png"},
    {"from": 9,  "id": &"lava",    "tiles": "res://tilesets/Dungeon_Tileset_lava.png"},
    {"from": 13, "id": &"moss",    "tiles": "res://tilesets/Dungeon_Tileset_moss.png"},
]

static func theme_for_level(level: int) -> Dictionary:
    var current: Dictionary = THEMES[0]
    for t in THEMES:
        if level >= t.from:
            current = t
    return current

func _apply_theme(tile_map: TileMapLayer, level: int) -> void:
    var theme := theme_for_level(level)
    # duplicar para no modificar el recurso compartido en disco
    var ts: TileSet = tile_map.tile_set.duplicate(true)
    var src := ts.get_source(0) as TileSetAtlasSource
    src.texture = load(theme.tiles)
    tile_map.tile_set = ts
```

Las antorchas, los estandartes y las decoraciones se eligen con el mismo `theme.id`, por ejemplo `"res://assets/dungeon_themes/%s/%s_torch_frames.tres" % [theme.id, theme.id]`. El tema `dungeon` sigue usando los objetos actuales.
