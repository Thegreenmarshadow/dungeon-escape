class_name ChaserEnemy
extends EnemyBase
## Enemigo que persigue al jugador cuando se acerca y vuelve a su puesto si lo
## pierde. Lo usan el vampiro y la parca con distintos parámetros.

## Distancia a la que detecta al jugador y empieza a perseguirlo.
@export var detect_radius: float = 80.0
## Distancia a la que lo pierde. Es mayor que detect_radius para que no
## alterne entre perseguir y volver cuando el jugador está justo en el borde.
@export var lose_radius: float = 120.0
## Distancia máxima entre el jugador y el puesto del enemigo para perseguirlo.
## Sirve para que un guardián no abandone la zona que protege.
@export var leash_radius: float = 160.0

var _home: Vector2
var _chasing: bool = false
var _player: Node2D


func _ready() -> void:
	super()
	# El puesto es donde se colocó al enemigo en el nivel.
	_home = global_position
	_player = get_tree().get_first_node_in_group("player")


func _get_move_velocity(_delta: float) -> Vector2:
	if is_instance_valid(_player):
		var player_pos := _player.global_position
		var distance := global_position.distance_to(player_pos)
		var player_in_zone := _home.distance_to(player_pos) <= leash_radius
		if _chasing:
			_chasing = player_in_zone and distance <= lose_radius
		else:
			_chasing = player_in_zone and distance < detect_radius
		if _chasing:
			return global_position.direction_to(player_pos) * speed

	# Sin jugador a la vista, vuelve a su puesto y espera ahí.
	if global_position.distance_to(_home) > 2.0:
		return global_position.direction_to(_home) * speed
	return Vector2.ZERO
