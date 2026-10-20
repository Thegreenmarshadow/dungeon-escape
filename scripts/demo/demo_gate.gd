class_name DemoGate
extends StaticBody2D
## Reja de madera que cierra el corredor entre dos salas de la demo. Mientras
## está cerrada choca como una pared (capa del mundo): frena al jugador, a los
## enemigos y a los proyectiles, y corta la línea de visión de los arqueros.
## open() la abre una sola vez. Si el jugador la toca cerrada avisa con
## locked_touched, así el nivel puede explicar cómo abrirla.
##
## Se arma en código (setup) porque su tamaño sale del corredor: una columna de
## dos celdas de alto. El dibujo es la puerta doble del tileset, girada.

signal opened(gate: DemoGate)
signal locked_touched(gate: DemoGate)

## Puerta doble cerrada del atlas del tileset (dos celdas de ancho).
const DOOR_REGION := Rect2(96, 48, 32, 16)
## Capa de colisión de las paredes (la misma que la del tileset).
const WALL_LAYER := 1
const PLAYER_MASK := 2
## Segundos que tarda en desaparecer al abrirse.
const OPEN_TIME := 0.35

## Índice de la reja en DemoMap.gates.
var index := 0

var _open := false
var _shape: CollisionShape2D
var _touch: Area2D
var _sprite: Sprite2D


## Arma la reja centrada en las dos celdas desde top_cell hacia abajo, con el
## atlas texture (el del tema de esa parte del mapa).
func setup(gate_index: int, top_cell: Vector2i, tile_size: Vector2, texture: Texture2D) -> void:
	index = gate_index
	name = "Gate%d" % gate_index
	position = (Vector2(top_cell) + Vector2(0.5, 1.0)) * tile_size
	collision_layer = WALL_LAYER
	collision_mask = 0
	var size := Vector2(tile_size.x, tile_size.y * 2.0)

	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	add_child(_shape)

	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.region_enabled = true
	_sprite.region_rect = DOOR_REGION
	# La puerta del atlas es horizontal; girada cierra el corredor de arriba abajo.
	_sprite.rotation = PI / 2.0
	add_child(_sprite)

	# Un poco más ancha que la reja: el jugador la "toca" aunque choque antes.
	_touch = Area2D.new()
	_touch.collision_layer = 0
	_touch.collision_mask = PLAYER_MASK
	var touch_shape := CollisionShape2D.new()
	var touch_rect := RectangleShape2D.new()
	touch_rect.size = size + Vector2(8, 0)
	touch_shape.shape = touch_rect
	_touch.add_child(touch_shape)
	_touch.body_entered.connect(_on_touch_body_entered)
	add_child(_touch)


func is_open() -> bool:
	return _open


## Abre la reja: deja de chocar, suena la puerta y se desvanece. Una sola vez.
func open() -> void:
	if _open:
		return
	_open = true
	# Diferido: puede abrirse por una muerte, durante un callback de física.
	_shape.set_deferred("disabled", true)
	_touch.set_deferred("monitoring", false)
	Sfx.play(&"door_open")
	var tween := create_tween().set_parallel()
	tween.tween_property(_sprite, "modulate:a", 0.0, OPEN_TIME)
	# El largo de la puerta (su eje x, girado) se encoge hacia el centro.
	tween.tween_property(_sprite, "scale", Vector2(0.1, 1.0), OPEN_TIME)
	opened.emit(self)


func _on_touch_body_entered(body: Node2D) -> void:
	if not _open and body.is_in_group("player"):
		locked_touched.emit(self)
