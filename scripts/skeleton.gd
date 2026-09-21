extends EnemyBase
## Esqueleto que patrulla entre dos puntos. La vida, el daño por contacto y la
## muerte vienen de EnemyBase; aquí solo se define la patrulla.

## Desplazamiento del segundo punto de patrulla respecto de la posición inicial.
@export var patrol_offset: Vector2 = Vector2(112, 0)

var _point_a: Vector2
var _point_b: Vector2
var _target: Vector2


func _ready() -> void:
	super()
	# El primer punto es donde se colocó el esqueleto en el nivel.
	_point_a = global_position
	_point_b = global_position + patrol_offset
	_target = _point_b


func _get_move_velocity(_delta: float) -> Vector2:
	# Al llegar a un extremo, cambia de destino. Se calcula la dirección en cada
	# frame, así retoma la ruta aunque un golpe lo haya desviado.
	if global_position.distance_to(_target) < 2.0:
		_target = _point_a if _target == _point_b else _point_b
	return global_position.direction_to(_target) * speed
