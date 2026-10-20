class_name ForgeBoss
extends BossBase
## Forjador de magma (sección 9.2 de docs/assets-pack/03-jefes.md): gólem de
## roca y obsidiana, lento y de golpe pesado, que deja lava en el suelo.
##
## Estados: IDLE -> CHASE -> SLAM o ROAR (alterna) -> RECOVER -> CHASE.
## - SLAM, martillazo (animación attack, impacto en el frame 5 = 625 ms de
##   aviso): al empezar fija el punto de impacto slam_reach px hacia el
##   jugador. En el impacto crea la onda (fx-shockwave, radio 20) y lava_pools
##   charcos alrededor. Después el martillo queda clavado slam_recover_time:
##   la ventana de castigo (tinte azulado).
## - ROAR, lluvia de brasas (attack2, frame 4 = 500 ms de rugido): ember_marks
##   marcas (fx-ember_mark), una sobre el jugador y el resto a 24-48 px de él.
##   Cada una avisa 667 ms (frames 0-3) y estalla 333 ms (frames 4-5).
## - Fase 2 (vida <= 50 %): además del brillo y la velocidad ×1.25 de
##   BossBase, el martillazo deja un surco de furrow_pools charcos en línea
##   hacia el jugador en lugar del anillo.
##
## Alterna: después de un martillazo prefiere la lluvia y al revés. Si el
## ataque preferido no se puede usar (enfriamiento o distancia) y el otro sí,
## usa el otro, así alejarse no lo deja sin atacar.

enum State { IDLE, CHASE, SLAM, ROAR, RECOVER }
enum Attack { SLAM, ROAR }

const SLAM_ANIMATION := &"attack"
const ROAR_ANIMATION := &"attack2"
## Frames de impacto de la tabla de archivos de la sección 9.
const SLAM_IMPACT_FRAME := 5
const ROAR_IMPACT_FRAME := 4

@export_group("Martillazo")
## Distancia al jugador a la que empieza el martillazo.
@export var slam_range: float = 36.0
## Distancia del punto de impacto, hacia el jugador.
@export var slam_reach: float = 28.0
## Segundos entre el fin de un martillazo y el siguiente.
@export var slam_cooldown: float = 2.0
## Segundos con el martillo clavado después del golpe (ventana de castigo).
@export var slam_recover_time: float = 1.0
## Charcos de lava alrededor del impacto (fase 1) y a qué distancia de él.
@export var lava_pools: int = 3
@export var lava_pool_ring_radius: float = 14.0

@export_group("Lluvia de brasas")
## Distancia máxima al jugador para rugir.
@export var roar_range: float = 120.0
## Segundos entre el fin de una lluvia y la siguiente.
@export var roar_cooldown: float = 4.0
## Segundos de recuperación después de rugir (ventana de castigo).
@export var roar_recover_time: float = 0.6
## Marcas por lluvia: la primera sobre el jugador, el resto alrededor.
@export var ember_marks: int = 4
@export var ember_min_distance: float = 24.0
@export var ember_max_distance: float = 48.0

@export_group("Fase 2: surco de lava")
## Charcos del surco y separación entre ellos, desde el impacto hacia el jugador.
@export var furrow_pools: int = 5
@export var furrow_spacing: float = 14.0

@export_group("Efectos")
@export var shockwave_scene: PackedScene = preload("res://scenes/bosses/forge/Shockwave.tscn")
@export var ember_mark_scene: PackedScene = preload("res://scenes/bosses/forge/EmberMark.tscn")
@export var lava_pool_scene: PackedScene = preload("res://scenes/bosses/forge/LavaPool.tscn")

var _state: State = State.IDLE
var _state_left: float = 0.0
var _next_attack: Attack = Attack.SLAM
var _slam_cooldown_left: float = 0.0
var _roar_cooldown_left: float = 0.0
## Punto de impacto del martillazo en curso (global), fijado al empezarlo.
var _slam_target: Vector2 = Vector2.ZERO


func get_state() -> State:
	return _state


func _get_move_velocity(delta: float) -> Vector2:
	_slam_cooldown_left = maxf(_slam_cooldown_left - delta, 0.0)
	_roar_cooldown_left = maxf(_roar_cooldown_left - delta, 0.0)
	match _state:
		State.IDLE:
			return _update_idle()
		State.CHASE:
			return _update_chase()
		State.RECOVER:
			_update_recover(delta)
	# SLAM y ROAR: quieto mientras dura la animación (ver _on_move_finished).
	return Vector2.ZERO


func _update_idle() -> Vector2:
	if can_see_player():
		engage()
	if is_engaged():
		_state = State.CHASE
	return Vector2.ZERO


func _update_chase() -> Vector2:
	# Sin jugador en su zona vuelve a su puesto delante de la puerta.
	if not player_in_zone():
		return velocity_home()
	match _choose_attack():
		Attack.SLAM:
			_start_slam()
			return Vector2.ZERO
		Attack.ROAR:
			_start_roar()
			return Vector2.ZERO
	return velocity_toward(player_position())


func _update_recover(delta: float) -> void:
	_state_left -= delta
	if _state_left <= 0.0:
		set_vulnerable(false)
		_state = State.CHASE


## Ataque que corresponde ahora, o -1 si ninguno: primero el preferido
## (alterna) y, si no se puede, el otro.
func _choose_attack() -> int:
	var other: Attack = Attack.ROAR if _next_attack == Attack.SLAM else Attack.SLAM
	for attack: Attack in [_next_attack, other]:
		if _can_use(attack):
			return attack
	return -1


func _can_use(attack: Attack) -> bool:
	var distance := distance_to_player()
	if attack == Attack.SLAM:
		return _slam_cooldown_left <= 0.0 and distance <= slam_range
	return _roar_cooldown_left <= 0.0 and distance <= roar_range


func _start_slam() -> void:
	_state = State.SLAM
	_next_attack = Attack.ROAR
	# El punto de impacto se fija ahora, 625 ms antes del golpe (6.1 pide al
	# menos 150 ms): el jugador ve dónde va a caer y puede salir hacia atrás.
	var direction := global_position.direction_to(player_position())
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT if sprite.flip_h else Vector2.RIGHT
	_slam_target = global_position + direction * slam_reach
	start_move(SLAM_ANIMATION, SLAM_IMPACT_FRAME)


func _start_roar() -> void:
	_state = State.ROAR
	_next_attack = Attack.SLAM
	start_move(ROAR_ANIMATION, ROAR_IMPACT_FRAME)


func _on_move_impact(animation: StringName) -> void:
	if animation == SLAM_ANIMATION:
		spawn_hazard(shockwave_scene, _slam_target)
		for at in lava_pool_positions():
			spawn_hazard(lava_pool_scene, at)
	elif animation == ROAR_ANIMATION:
		for at in ember_positions():
			spawn_hazard(ember_mark_scene, at)


func _on_move_finished(animation: StringName) -> void:
	if animation == SLAM_ANIMATION:
		_slam_cooldown_left = slam_cooldown
		_enter_recover(slam_recover_time)
	elif animation == ROAR_ANIMATION:
		_roar_cooldown_left = roar_cooldown
		_enter_recover(roar_recover_time)


func _enter_recover(duration: float) -> void:
	_state = State.RECOVER
	_state_left = duration
	set_vulnerable(true)


## Dónde quedan los charcos del martillazo en curso: un anillo alrededor del
## impacto en la fase 1 y un surco hacia el jugador en la fase 2.
func lava_pool_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if is_phase_two():
		var direction := _slam_target.direction_to(player_position())
		if direction == Vector2.ZERO:
			direction = global_position.direction_to(_slam_target)
		for i in furrow_pools:
			out.append(_slam_target + direction * furrow_spacing * i)
		return out
	var start_angle := _rng.randf() * TAU
	for i in lava_pools:
		var angle := start_angle + TAU * i / float(maxi(lava_pools, 1))
		out.append(_slam_target + Vector2.from_angle(angle) * lava_pool_ring_radius)
	return out


## Dónde caen las brasas: la primera donde está el jugador al rugir y el resto
## a ember_min_distance..ember_max_distance de él.
func ember_positions() -> Array[Vector2]:
	var center := player_position()
	var out: Array[Vector2] = [center]
	for i in ember_marks - 1:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(ember_min_distance, ember_max_distance)
		out.append(center + Vector2.from_angle(angle) * distance)
	return out


## Además del golpe en curso, el martillo clavado (y el final del rugido) se
## mantienen durante la recuperación.
func _is_animation_locked() -> bool:
	return super() or _state == State.RECOVER
