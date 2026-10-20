class_name WardenBoss
extends BossBase
## Guardián musgoso (sección 9.4 de docs/assets-pack/03-jefes.md): estatua de
## piedra cubierta de musgo, lenta, que invoca vainas y se cura.
##
## Estados: IDLE -> CHASE -> ROOTS o SPORES (alterna) -> RECOVER -> CHASE.
## - ROOTS, raíces (animación attack, impacto en el frame 5 = 625 ms de
##   aviso): en el frame ROOTS_AIM_FRAME (375 ms) fija dónde salen: debajo del
##   jugador y a ±root_spread px a sus costados. En el impacto salen los
##   fx-root_spike, que se agrietan 250 ms (frames 0-1) y pinchan 375 ms
##   (frames 2-4). Después la runa brilla roots_recover_time: la ventana de
##   castigo, en la que cada golpe hace rune_bonus_damage más.
## - SPORES, esporas (attack2, frame 4 = 500 ms de setas que se inflan):
##   spore_clouds nubes (fx-spore_cloud, radio 14) alrededor del jugador que lo
##   frenan al 50 % sin lastimar, y spore_pods vainas a spore_pod_distance px a
##   los costados del jefe. Una vaina que nadie rompe en 6 s le cura 2.
## - Fase 2, tierra fértil (vida <= 50 %): además del brillo y la velocidad
##   ×1.25 de BossBase, parado sobre una mancha del suelo
##   (ThemeDecor.FLOOR_PATCH_GROUP) se cura moss_heal_amount cada
##   moss_heal_interval segundos. Sin manchas en el mapa no se cura.
##
## Alterna como el Forjador: después de las raíces prefiere las esporas y al
## revés; si el preferido no se puede usar (enfriamiento o distancia) y el
## otro sí, usa el otro.
##
## Cada curación suelta un puñado de partículas verdes (los tintes están
## reservados, sección 2.3 de la biblia).

enum State { IDLE, CHASE, ROOTS, SPORES, RECOVER }
enum Attack { ROOTS, SPORES }

const ROOTS_ANIMATION := &"attack"
const SPORES_ANIMATION := &"attack2"
## Frames de impacto de la tabla de archivos de la sección 9.
const ROOTS_IMPACT_FRAME := 5
const SPORES_IMPACT_FRAME := 4
## Frame de las raíces en el que se fija dónde van a salir (sección 9.4).
const ROOTS_AIM_FRAME := 3
## Color de las partículas del freno de las esporas y de la curación: el verde
## de las setas del hombro (#9ff0c0), en lugar del celeste del frío.
const SPORE_COLOR := Color(0.62, 0.94, 0.75)
## Segundos de freno que renueva cada paso de física dentro de una nube (los
## mismos que usa BossHazard).
const SPORE_SLOW_REFRESH := 0.2
## Capa de las paredes y los objetos grandes (ThemeDecor.WALL_COLLISION_LAYER):
## las vainas y las raíces de los costados no aparecen dentro de una pared.
const WALL_MASK := 1
## Direcciones que prueba para cada vaina si la preferida cae en una pared.
const POD_DIRECTION_TRIES := 8

@export_group("Raíces")
## Distancia máxima al jugador para lanzar las raíces.
@export var roots_range: float = 96.0
## Segundos entre el fin de unas raíces y las siguientes.
@export var roots_cooldown: float = 2.5
## Segundos de runa encendida después de las raíces (ventana de castigo).
@export var roots_recover_time: float = 0.75
## Distancia de las raíces de los costados a la del centro.
@export var root_spread: float = 20.0
## Daño extra de cada golpe mientras la runa brilla.
@export var rune_bonus_damage: int = 1

@export_group("Esporas")
## Distancia máxima al jugador para soltar las esporas.
@export var spores_range: float = 110.0
## Segundos entre el fin de unas esporas y las siguientes.
@export var spores_cooldown: float = 6.0
## Segundos de recuperación después de las esporas (ventana de castigo).
@export var spores_recover_time: float = 0.5
## Nubes por ataque, repartidas alrededor del jugador, y a qué distancia de él.
@export var spore_clouds: int = 2
@export var spore_cloud_offset: float = 10.0
## Velocidad del jugador dentro de una nube (multiplica).
@export_range(0.0, 1.0, 0.05) var spore_slow_factor: float = 0.5
## Vainas por ataque y a qué distancia del jefe aparecen.
@export var spore_pods: int = 2
@export var spore_pod_distance: float = 20.0

@export_group("Fase 2: tierra fértil")
## Vida que recupera sobre una mancha de musgo cada moss_heal_interval segundos.
@export var moss_heal_amount: int = 1
@export var moss_heal_interval: float = 3.0
## Distancia máxima (en x y en y) al centro de una mancha para estar encima.
## Las manchas miden 16 px.
@export var moss_patch_reach: float = 10.0

@export_group("Efectos")
@export var root_spike_scene: PackedScene = preload("res://scenes/bosses/warden/RootSpike.tscn")
@export var spore_cloud_scene: PackedScene = preload("res://scenes/bosses/warden/SporeCloud.tscn")
@export var spore_pod_scene: PackedScene = preload("res://scenes/bosses/warden/SporePod.tscn")

var _state: State = State.IDLE
var _state_left: float = 0.0
var _next_attack: Attack = Attack.ROOTS
var _roots_cooldown_left: float = 0.0
var _spores_cooldown_left: float = 0.0
## Dónde salen las raíces en curso (globales). Vacío hasta ROOTS_AIM_FRAME.
var _root_targets: Array[Vector2] = []
## true mientras la runa brilla (recuperación de las raíces): golpes +1.
var _rune_lit: bool = false
var _moss_heal_left: float = 0.0
var _heal_particles: CPUParticles2D


func _ready() -> void:
	super()
	_moss_heal_left = moss_heal_interval
	# Después del de BossBase: si un salto de frames llega directo al impacto,
	# _on_move_impact fija la puntería él mismo.
	sprite.frame_changed.connect(_on_roots_frame_changed)


func get_state() -> State:
	return _state


## true mientras la runa brilla y los golpes hacen más daño.
func is_rune_lit() -> bool:
	return _rune_lit


## Dónde van a salir las raíces en curso (vacío antes de fijarlas).
func root_targets() -> Array[Vector2]:
	return _root_targets.duplicate()


func _get_move_velocity(delta: float) -> Vector2:
	_roots_cooldown_left = maxf(_roots_cooldown_left - delta, 0.0)
	_spores_cooldown_left = maxf(_spores_cooldown_left - delta, 0.0)
	_update_moss_heal(delta)
	match _state:
		State.IDLE:
			return _update_idle()
		State.CHASE:
			return _update_chase()
		State.RECOVER:
			_update_recover(delta)
	# ROOTS y SPORES: quieto mientras dura la animación (ver _on_move_finished).
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
		Attack.ROOTS:
			_start_roots()
			return Vector2.ZERO
		Attack.SPORES:
			_start_spores()
			return Vector2.ZERO
	return velocity_toward(player_position())


func _update_recover(delta: float) -> void:
	_state_left -= delta
	if _state_left <= 0.0:
		_rune_lit = false
		set_vulnerable(false)
		_state = State.CHASE


## Ataque que corresponde ahora, o -1 si ninguno: primero el preferido
## (alterna) y, si no se puede, el otro.
func _choose_attack() -> int:
	var other: Attack = Attack.SPORES if _next_attack == Attack.ROOTS else Attack.ROOTS
	for attack: Attack in [_next_attack, other]:
		if _can_use(attack):
			return attack
	return -1


func _can_use(attack: Attack) -> bool:
	var distance := distance_to_player()
	if attack == Attack.ROOTS:
		return _roots_cooldown_left <= 0.0 and distance <= roots_range
	return _spores_cooldown_left <= 0.0 and distance <= spores_range


func _start_roots() -> void:
	_state = State.ROOTS
	_next_attack = Attack.SPORES
	_root_targets.clear()
	start_move(ROOTS_ANIMATION, ROOTS_IMPACT_FRAME)


func _start_spores() -> void:
	_state = State.SPORES
	_next_attack = Attack.ROOTS
	start_move(SPORES_ANIMATION, SPORES_IMPACT_FRAME)


func _on_roots_frame_changed() -> void:
	if _state == State.ROOTS and _root_targets.is_empty() \
			and sprite.animation == ROOTS_ANIMATION and sprite.frame >= ROOTS_AIM_FRAME:
		_aim_roots()


## Fija dónde salen las raíces: debajo del jugador y a sus costados, en la
## perpendicular a la línea jefe-jugador. Las de los costados que caerían en
## una pared no salen.
func _aim_roots() -> void:
	var center := player_position()
	var across := global_position.direction_to(center).orthogonal()
	if across == Vector2.ZERO:
		across = Vector2.DOWN
	_root_targets.clear()
	_root_targets.append(center)
	for side: float in [-1.0, 1.0]:
		var at: Vector2 = center + across * root_spread * side
		if _is_open_floor(at):
			_root_targets.append(at)


func _on_move_impact(animation: StringName) -> void:
	if animation == ROOTS_ANIMATION:
		if _root_targets.is_empty():
			_aim_roots()
		for at in _root_targets:
			spawn_hazard(root_spike_scene, at)
	elif animation == SPORES_ANIMATION:
		for at in spore_cloud_positions():
			var cloud := spawn_hazard(spore_cloud_scene, at)
			if cloud != null and cloud.has_signal("struck"):
				cloud.connect("struck", _on_spore_cloud_struck)
		for at in spore_pod_positions():
			var pod := spawn_minion(spore_pod_scene, at)
			if pod != null and "heal_target" in pod:
				pod.heal_target = self


func _on_move_finished(animation: StringName) -> void:
	if animation == ROOTS_ANIMATION:
		_roots_cooldown_left = roots_cooldown
		_rune_lit = true
		_enter_recover(roots_recover_time)
	elif animation == SPORES_ANIMATION:
		_spores_cooldown_left = spores_cooldown
		_enter_recover(spores_recover_time)


func _enter_recover(duration: float) -> void:
	_state = State.RECOVER
	_state_left = duration
	set_vulnerable(true)


## La nube ya frena con su slow_factor; se vuelve a aplicar con el color de
## las esporas para que las partículas del jugador sean verdes y no celestes.
func _on_spore_cloud_struck(target: Node2D) -> void:
	if is_instance_valid(target) and target.has_method("apply_slow"):
		target.apply_slow(spore_slow_factor, SPORE_SLOW_REFRESH, SPORE_COLOR)


## Dónde aparecen las nubes: repartidas alrededor del jugador, a
## spore_cloud_offset px, con un ángulo al azar.
func spore_cloud_positions() -> Array[Vector2]:
	var center := player_position()
	var start_angle := _rng.randf() * TAU
	var out: Array[Vector2] = []
	for i in spore_clouds:
		var angle := start_angle + TAU * i / float(maxi(spore_clouds, 1))
		out.append(center + Vector2.from_angle(angle) * spore_cloud_offset)
	return out


## Dónde aparecen las vainas: a spore_pod_distance px del jefe, repartidas a
## partir de sus costados (perpendicular al jugador). Si una cae en una pared
## prueba girando; si no encuentra lugar la deja a sus pies.
func spore_pod_positions() -> Array[Vector2]:
	var facing := global_position.direction_to(player_position())
	if facing == Vector2.ZERO:
		facing = Vector2.LEFT if sprite.flip_h else Vector2.RIGHT
	var out: Array[Vector2] = []
	for i in spore_pods:
		var base_angle := facing.orthogonal().angle() + TAU * i / float(maxi(spore_pods, 1))
		var spot := global_position
		for t in POD_DIRECTION_TRIES:
			var angle := base_angle + TAU * t / float(POD_DIRECTION_TRIES)
			var at := global_position + Vector2.from_angle(angle) * spore_pod_distance
			if _is_open_floor(at) and not out.has(at):
				spot = at
				break
		out.append(spot)
	return out


## true si en point no hay pared ni objeto grande. Sin mundo físico (pruebas)
## todo es suelo.
func _is_open_floor(point: Vector2) -> bool:
	if not is_inside_tree():
		return true
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = WALL_MASK
	query.collide_with_areas = false
	return get_world_2d().direct_space_state.intersect_point(query, 1).is_empty()


# ---------------------------------------------------------------------------
# Tierra fértil y curación
# ---------------------------------------------------------------------------

## true si está parado sobre una mancha del suelo (musgo en su tema).
func is_on_moss_patch() -> bool:
	if not is_inside_tree():
		return false
	for patch in get_tree().get_nodes_in_group(ThemeDecor.FLOOR_PATCH_GROUP):
		var node := patch as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var offset := node.global_position - global_position
		if absf(offset.x) <= moss_patch_reach and absf(offset.y) <= moss_patch_reach:
			return true
	return false


## En la fase 2 cuenta el tiempo que lleva sobre una mancha y se cura cada
## moss_heal_interval. Al salir de la mancha el conteo vuelve a empezar.
func _update_moss_heal(delta: float) -> void:
	if not is_phase_two() or is_dying or not is_on_moss_patch():
		_moss_heal_left = moss_heal_interval
		return
	_moss_heal_left -= delta
	if _moss_heal_left <= 0.0:
		_moss_heal_left += moss_heal_interval
		heal(moss_heal_amount)


## Además de curar (BossBase), suelta las partículas verdes de la curación.
func heal(amount: int) -> int:
	var healed := super(amount)
	if healed > 0:
		_show_heal_particles()
	return healed


func _show_heal_particles() -> void:
	if _heal_particles == null:
		_heal_particles = CPUParticles2D.new()
		_heal_particles.one_shot = true
		_heal_particles.emitting = false
		_heal_particles.amount = 10
		_heal_particles.lifetime = 0.7
		_heal_particles.explosiveness = 0.6
		_heal_particles.position = Vector2(0, -10)
		_heal_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_heal_particles.emission_sphere_radius = 10.0
		_heal_particles.direction = Vector2.UP
		_heal_particles.spread = 25.0
		_heal_particles.gravity = Vector2.ZERO
		_heal_particles.initial_velocity_min = 8.0
		_heal_particles.initial_velocity_max = 16.0
		_heal_particles.scale_amount_min = 1.0
		_heal_particles.scale_amount_max = 2.0
		_heal_particles.color = SPORE_COLOR
		add_child(_heal_particles)
	_heal_particles.restart()


# ---------------------------------------------------------------------------
# BossBase
# ---------------------------------------------------------------------------

## Con la runa encendida cada golpe hace rune_bonus_damage más.
func _modify_incoming_damage(amount: int) -> int:
	return amount + rune_bonus_damage if _rune_lit else amount


## Además del golpe en curso, el final de la animación se mantiene durante la
## recuperación (brazos abajo con la runa encendida).
func _is_animation_locked() -> bool:
	return super() or _state == State.RECOVER


func _die() -> void:
	_rune_lit = false
	super()
