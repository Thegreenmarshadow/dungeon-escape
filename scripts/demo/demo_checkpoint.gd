class_name DemoCheckpoint
extends Area2D
## Vela del punto de control de la demo, antes del jefe. Apagada (oscura y
## quieta) hasta que el jugador pasa cerca; entonces se enciende (la llama se
## mueve) y avisa con activated una sola vez. Dónde reaparece el jugador lo
## decide DemoLevel.

signal activated(checkpoint: DemoCheckpoint)

const FRAME_PATH := "res://assets/dungeon/items_and_traps/torch/candlestick_2_%d.png"
const FRAME_COUNT := 4
const FPS := 6.0
## Radio en píxeles en el que el jugador la activa: alcanza el camino hacia la
## reja del jefe, así no hace falta tocar la vela.
const ACTIVATION_RADIUS := 26.0
const PLAYER_MASK := 2
const INACTIVE_TINT := Color(0.35, 0.35, 0.42)

var _active := false
var _sprite: AnimatedSprite2D


func _init() -> void:
	name = "Checkpoint"
	collision_layer = 0
	collision_mask = PLAYER_MASK
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = ACTIVATION_RADIUS
	shape.shape = circle
	add_child(shape)

	var frames := SpriteFrames.new()
	frames.set_animation_speed(&"default", FPS)
	for i in FRAME_COUNT:
		frames.add_frame(&"default", load(FRAME_PATH % (i + 1)))
	_sprite = AnimatedSprite2D.new()
	_sprite.sprite_frames = frames
	_sprite.modulate = INACTIVE_TINT
	add_child(_sprite)


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func is_active() -> bool:
	return _active


## Enciende la vela (una sola vez). Pública para las pruebas; en el juego la
## llama el paso del jugador.
func activate() -> void:
	if _active:
		return
	_active = true
	_sprite.modulate = Color.WHITE
	_sprite.play(&"default")
	Sfx.play(&"key_pickup")
	activated.emit(self)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		activate()
