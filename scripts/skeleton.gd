extends Area2D
## Esqueleto que patrulla entre dos puntos y lastima al jugador al tocarlo.

## Daño que hace al tocar al jugador.
@export var damage: int = 1
## Velocidad de patrulla en píxeles por segundo.
@export var speed: float = 30.0
## Desplazamiento del segundo punto de patrulla respecto de la posición inicial.
@export var patrol_offset: Vector2 = Vector2(112, 0)

var _point_a: Vector2
var _point_b: Vector2
var _target: Vector2

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	# El primer punto es donde se colocó el esqueleto en el nivel.
	_point_a = position
	_point_b = position + patrol_offset
	_target = _point_b
	sprite.play("walk")


func _physics_process(delta: float) -> void:
	_patrol(delta)
	# Lastima a cualquier cuerpo que pueda recibir daño mientras lo esté tocando.
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage)


func _patrol(delta: float) -> void:
	position = position.move_toward(_target, speed * delta)
	# Al llegar a un extremo, cambia de destino.
	if position.is_equal_approx(_target):
		_target = _point_a if _target == _point_b else _point_b
	# El sprite mira a la derecha por defecto; se voltea al ir a la izquierda.
	sprite.flip_h = _target.x < position.x
