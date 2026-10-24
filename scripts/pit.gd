class_name Pit
extends Node2D
## Abismo: un hueco rectangular en el suelo. El jugador que camina encima sin
## saltar tiene coyote_time para saltar; si no, cae (ver Player). No tiene
## colisión para el jugador: él pregunta con contains_global() si está encima.
## Para los enemigos que caminan es una pared: un cuerpo en la capa "pits"
## (PIT_COLLISION_LAYER) que solo ellos detectan, así se frenan en el borde.
## Los proyectiles y los enemigos que vuelan (EnemyBase.can_fly) lo cruzan.

## Grupo con todos los abismos de la escena.
const GROUP := &"pits"
## Capa de física de los abismos ("pits", capa 4).
const PIT_COLLISION_LAYER := 8
const COLOR_HOLE := Color(0.02, 0.01, 0.03)
const COLOR_EDGE := Color(0.18, 0.12, 0.16)
const COLOR_LAVA := Color(0.75, 0.2, 0.05)
const COLOR_LAVA_GLOW := Color(1.0, 0.6, 0.15)

## Tamaño del hueco en píxeles; el nodo está en su esquina superior izquierda.
@export var size := Vector2(16, 16)
## true lo dibuja como lava (la parte de lava de la demo). Se juega igual.
@export var lava := false


func _ready() -> void:
	add_to_group(GROUP)
	# z_index 0 a propósito: con uno negativo quedaría debajo del suelo
	# (TileMapLayer) y no se vería. Queda sobre el suelo y debajo del jugador
	# porque la escena lo agrega después del mapa y antes de los personajes.
	_add_enemy_blocker()


## Cuerpo del tamaño del hueco en la capa "pits": frena a los enemigos.
func _add_enemy_blocker() -> void:
	var body := StaticBody2D.new()
	body.name = "EnemyBlocker"
	body.collision_layer = PIT_COLLISION_LAYER
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size / 2.0
	body.add_child(shape)
	add_child(body)


## true si global_point está sobre el hueco.
func contains_global(global_point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(to_local(global_point))


func _draw() -> void:
	if lava:
		draw_rect(Rect2(Vector2.ZERO, size), COLOR_LAVA)
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), COLOR_LAVA_GLOW.darkened(0.2))
		draw_rect(Rect2(Vector2.ZERO, size), COLOR_EDGE, false, 1.0)
		return
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_HOLE)
	# Borde de arriba más claro: da profundidad, como una pared que baja.
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, 3.0)), COLOR_EDGE)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_EDGE, false, 1.0)
