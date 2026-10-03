class_name SkullEnemy
extends EnemyBase
## Calavera embestidora. Flota quieta hasta que el jugador se acerca; entonces
## se carga (parpadea en rojo), apunta y embiste en línea recta hasta chocar
## con una pared o agotar el tiempo, y queda aturdida un rato. Solo lastima
## mientras embiste, así que se puede esquivar yéndose de costado.

enum State { IDLE, WINDUP, CHARGE, RECOVER }

## Distancia al jugador a la que empieza a cargar la embestida.
@export var detect_radius: float = 90.0
## Segundos de carga antes de embestir. Al final apunta al jugador y ya no
## cambia de dirección.
@export var windup_time: float = 0.7
## Velocidad de la embestida en píxeles por segundo.
@export var charge_speed: float = 150.0
## Duración máxima de la embestida si no choca antes con una pared.
@export var charge_max_time: float = 0.6
## Segundos aturdida (vulnerable y quieta) después de embestir.
@export var recover_time: float = 1.0
## Segundos de espera tras recuperarse antes de poder cargar otra vez.
@export var cooldown_time: float = 0.8

## Multiplicador de la velocidad de la animación mientras embiste.
const CHARGE_ANIMATION_SCALE := 2.5
## Parpadeos por segundo durante la carga.
const WINDUP_BLINK_RATE := 6.0
const WINDUP_TINT := Color(1.0, 0.4, 0.4)
const RECOVER_TINT := Color(0.7, 0.7, 1.0)

var _state: State = State.IDLE
var _state_left: float = 0.0
var _cooldown_left: float = 0.0
var _charge_direction: Vector2 = Vector2.ZERO
var _player: Node2D


func _ready() -> void:
	super()
	_player = get_tree().get_first_node_in_group("player")


func _get_move_velocity(delta: float) -> Vector2:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	match _state:
		State.IDLE:
			_update_idle()
		State.WINDUP:
			_update_windup(delta)
		State.CHARGE:
			return _update_charge(delta)
		State.RECOVER:
			_update_recover(delta)
	return Vector2.ZERO


func is_alerted() -> bool:
	return not is_dying and _state != State.IDLE


## Un golpe del jugador cancela la carga o la embestida y empieza el
## enfriamiento. Se resetea antes de super() para que el destello rojo del
## golpe no se pise con el color de la carga.
func take_hit(amount: int, from_position: Vector2) -> void:
	_enter(State.IDLE, 0.0)
	_cooldown_left = cooldown_time
	super(amount, from_position)


## Solo lastima mientras embiste, no por rozarla.
func _damage_touching_bodies() -> void:
	if _state != State.CHARGE:
		return
	super()


func _die() -> void:
	super()
	# No tiene animación de muerte propia: infla el sprite mientras dura la
	# animación de muerte armada con sus frames de reposo.
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.6, 1.6), 0.4)


func _update_idle() -> void:
	if _cooldown_left > 0.0 or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) < detect_radius:
		_enter(State.WINDUP, windup_time)


func _update_windup(delta: float) -> void:
	_state_left -= delta
	if is_instance_valid(_player):
		sprite.flip_h = _player.global_position.x < global_position.x
	var blink_on := int(_state_left * WINDUP_BLINK_RATE * 2.0) % 2 == 0
	sprite.modulate = WINDUP_TINT if blink_on else Color.WHITE
	if _state_left > 0.0:
		return
	# Apunta recién ahora: el jugador tuvo toda la carga para moverse.
	if is_instance_valid(_player):
		_charge_direction = global_position.direction_to(_player.global_position)
	else:
		_charge_direction = Vector2.RIGHT if not sprite.flip_h else Vector2.LEFT
	sprite.flip_h = _charge_direction.x < 0.0
	_enter(State.CHARGE, charge_max_time)


func _update_charge(delta: float) -> Vector2:
	_state_left -= delta
	# Colisiona solo con paredes (capa 1), así que cualquier choque es una pared.
	if _state_left <= 0.0 or get_slide_collision_count() > 0:
		_enter(State.RECOVER, recover_time)
		return Vector2.ZERO
	return _charge_direction * charge_speed


func _update_recover(delta: float) -> void:
	_state_left -= delta
	if _state_left <= 0.0:
		_enter(State.IDLE, 0.0)
		_cooldown_left = cooldown_time


func _enter(state: State, duration: float) -> void:
	_state = state
	_state_left = duration
	sprite.modulate = RECOVER_TINT if state == State.RECOVER else Color.WHITE
	sprite.speed_scale = CHARGE_ANIMATION_SCALE if state == State.CHARGE else 1.0
