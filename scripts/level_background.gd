extends Parallax2D
## Fondo del nivel: piedra oscura que se repite sin costuras detrás de todo y
## se desplaza más lento que la cámara para dar sensación de profundidad.
## Es reutilizable: la generación procedural puede instanciarlo tal cual.

## Tiles del atlas usados como piedra de fondo (interior liso del suelo, sin
## colisión). Se eligen al azar con semilla fija para romper la repetición.
const STONE_TILES: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
	Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
	Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
]

## Tamaño en tiles del bloque que se repite.
@export var block_size := Vector2i(48, 32)
## Semilla para que el patrón sea siempre el mismo.
@export var pattern_seed := 7

@onready var floor_layer: TileMapLayer = $Floor


func _ready() -> void:
	var tile_size := floor_layer.tile_set.tile_size
	repeat_size = Vector2(block_size * tile_size)
	_fill_block()


## Rellena el bloque una sola vez; no hay trabajo por frame.
func _fill_block() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = pattern_seed
	for y in block_size.y:
		for x in block_size.x:
			var atlas_coords := STONE_TILES[rng.randi() % STONE_TILES.size()]
			floor_layer.set_cell(Vector2i(x, y), 0, atlas_coords)
