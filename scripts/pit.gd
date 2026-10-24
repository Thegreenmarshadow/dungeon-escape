class_name Pit
extends Node2D
## Abismo: un hueco rectangular en el suelo. El jugador que camina encima sin
## saltar tiene coyote_time para saltar; si no, cae (ver Player). No tiene
## colisión: el jugador pregunta con contains_global() si está encima. Los
## enemigos lo ignoran.

## Grupo con todos los abismos de la escena.
const GROUP := &"pits"
const COLOR_HOLE := Color(0.02, 0.01, 0.03)
const COLOR_EDGE := Color(0.18, 0.12, 0.16)

## Tamaño del hueco en píxeles; el nodo está en su esquina superior izquierda.
@export var size := Vector2(16, 16)


func _ready() -> void:
	add_to_group(GROUP)
	# Debajo del jugador y los enemigos.
	z_index = -1


## true si global_point está sobre el hueco.
func contains_global(global_point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(to_local(global_point))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_HOLE)
	# Borde de arriba más claro: da profundidad, como una pared que baja.
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 3.0)), COLOR_EDGE)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_EDGE, false, 1.0)
