class_name MimicEnemy
extends ChaserEnemy
## Cofre mímico. Espera disfrazado de cofre (animación idle; en su frame 4 se
## asoma un ojo, la pista para el jugador atento) sin lastimar ni contar como
## alerta, así la música no lo delata. Cuando el jugador se acerca a menos de
## wake_radius, o si lo golpean, despierta (animación wake) y desde ahí se
## comporta como un perseguidor con mordisco (ChaserEnemy). Si pierde al
## jugador vuelve a su puesto y se cierra otra vez.

enum Disguise { DORMANT, WAKING, AWAKE }

## Distancia a la que el jugador lo despierta. Es corta: es una emboscada.
@export var wake_radius: float = 28.0
## Animación de despertar, configurada sin loop. Mientras dura no se mueve ni
## lastima.
@export var wake_animation: StringName = &"wake"

var _disguise: Disguise = Disguise.DORMANT


func _get_move_velocity(delta: float) -> Vector2:
	match _disguise:
		Disguise.DORMANT:
			if is_instance_valid(_player) \
					and global_position.distance_to(_player.global_position) < wake_radius:
				_wake()
			return Vector2.ZERO
		Disguise.WAKING:
			return Vector2.ZERO
	var velocity_wanted := super(delta)
	# Sin nadie a quien perseguir y ya en su puesto: vuelve a ser un cofre.
	if not _chasing and not _attacking and velocity_wanted == Vector2.ZERO:
		_disguise = Disguise.DORMANT
	return velocity_wanted


func is_alerted() -> bool:
	match _disguise:
		Disguise.DORMANT:
			return false
		Disguise.WAKING:
			return not is_dying
	return super()


func is_dormant() -> bool:
	return _disguise == Disguise.DORMANT


## Disfrazado o despertando no esquiva: el primer golpe siempre entra.
func _can_dodge() -> bool:
	return _disguise == Disguise.AWAKE and super()


## Un golpe lo despierta del todo, sin esperar la animación de despertar.
func _receive_hit(amount: int, from_position: Vector2) -> void:
	_disguise = Disguise.AWAKE
	_chasing = true
	super(amount, from_position)


## Disfrazado o despertando no lastima, aunque el jugador lo toque.
func _damage_touching_bodies() -> void:
	if _disguise != Disguise.AWAKE:
		return
	super()


func _update_animation() -> void:
	if _disguise == Disguise.WAKING:
		return
	super()


func _on_animation_finished() -> void:
	if _disguise == Disguise.WAKING and sprite.animation == wake_animation:
		_disguise = Disguise.AWAKE
		_chasing = true
		sprite.play(idle_animation)
		return
	super()


func _wake() -> void:
	_disguise = Disguise.WAKING
	if is_instance_valid(_player):
		sprite.flip_h = _player.global_position.x < global_position.x
	sprite.play(wake_animation)
	sprite.frame = 0
