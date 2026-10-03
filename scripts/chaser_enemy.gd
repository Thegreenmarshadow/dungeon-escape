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

@export_group("Ataque")
## Animación del ataque, configurada sin loop. Si está vacía el enemigo no
## ataca y solo lastima por contacto (contact_damage).
@export var attack_animation: StringName = &""
## Distancia al jugador a la que se detiene y empieza el ataque.
@export var attack_range: float = 20.0
## Distancia máxima al jugador a la que el golpe lo alcanza. Es mayor que
## attack_range para que un paso atrás corto no lo salve si ya está a mitad.
@export var attack_reach: float = 26.0
## Daño que hace el golpe.
@export var attack_damage: int = 1
## Primer y último frame de la animación en los que el golpe puede lastimar.
## Los anteriores son la anticipación (el jugador tiene tiempo de esquivar) y
## los posteriores la recuperación.
@export var attack_hit_frames: Vector2i = Vector2i(9, 10)
## Segundos de espera entre el fin de un ataque y el inicio del siguiente.
@export var attack_cooldown: float = 1.2

var _home: Vector2
var _chasing: bool = false
var _player: Node2D
var _attacking: bool = false
var _attack_hit_done: bool = false
var _attack_cooldown_left: float = 0.0


func _ready() -> void:
	super()
	# El puesto es donde se colocó al enemigo en el nivel.
	_home = global_position
	_player = get_tree().get_first_node_in_group("player")
	sprite.frame_changed.connect(_on_sprite_frame_changed)


func _get_move_velocity(delta: float) -> Vector2:
	# Durante el ataque se queda quieto: el jugador puede ver venir el golpe.
	if _attacking:
		return Vector2.ZERO
	_attack_cooldown_left = maxf(_attack_cooldown_left - delta, 0.0)

	if is_instance_valid(_player):
		var player_pos := _player.global_position
		var distance := global_position.distance_to(player_pos)
		var player_in_zone := _home.distance_to(player_pos) <= leash_radius
		if _chasing:
			_chasing = player_in_zone and distance <= lose_radius
		else:
			_chasing = player_in_zone and distance < detect_radius
		if _chasing:
			if _can_attack() and distance <= attack_range:
				_start_attack(player_pos)
				return Vector2.ZERO
			return global_position.direction_to(player_pos) * speed

	# Sin jugador a la vista, vuelve a su puesto y espera ahí.
	if global_position.distance_to(_home) > 2.0:
		return global_position.direction_to(_home) * speed
	return Vector2.ZERO


func is_alerted() -> bool:
	return not is_dying and (_chasing or _attacking)


## Un ataque interrumpido por un golpe del jugador se cancela y empieza el
## enfriamiento; si no, _attacking quedaría activo sin animación que lo termine.
func take_hit(amount: int, from_position: Vector2) -> void:
	_attacking = false
	_attack_cooldown_left = attack_cooldown
	super(amount, from_position)


# Mientras ataca, la animación de ataque no se pisa con idle/walk.
func _update_animation() -> void:
	if _attacking:
		return
	super()


func _on_animation_finished() -> void:
	if _attacking and sprite.animation == attack_animation:
		_attacking = false
		_attack_cooldown_left = attack_cooldown
		sprite.play(idle_animation)
		return
	super()


func _can_attack() -> bool:
	return attack_animation != &"" and _attack_cooldown_left <= 0.0


func _start_attack(target_position: Vector2) -> void:
	_attacking = true
	_attack_hit_done = false
	# Mira hacia el jugador; durante el ataque no se mueve, así no se re-orienta.
	sprite.flip_h = target_position.x < global_position.x
	sprite.play(attack_animation)
	sprite.frame = 0


## El golpe lastima solo en los frames de impacto y una vez por ataque.
func _on_sprite_frame_changed() -> void:
	if not _attacking or _attack_hit_done or sprite.animation != attack_animation:
		return
	if sprite.frame < attack_hit_frames.x or sprite.frame > attack_hit_frames.y:
		return
	if not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > attack_reach:
		return
	if _player.has_method("take_damage"):
		_player.take_damage(attack_damage)
		_attack_hit_done = true
