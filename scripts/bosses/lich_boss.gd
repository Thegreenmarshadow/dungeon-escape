class_name LichBoss
extends BossBase
## Reina liche de escarcha (sección 9.3 de docs/assets-pack/03-jefes.md): jefa
## a distancia y de control de zona. Flota lejos del jugador, ataca en líneas y
## en la fase 2 se protege con cristales de hielo.
##
## Estados: IDLE -> REPOSITION -> SPIKES o NOVA (o SUMMON en la fase 2) ->
## RECOVER -> REPOSITION.
## - REPOSITION: se mantiene a keep_min_distance..keep_max_distance px del
##   jugador. Si él se acerca, retrocede, pero no más de max_retreat_from_home
##   px de su puesto (así no huye por un pasillo); acorralada, se planta.
## - SPIKES, línea de picos (animación attack, impacto en el frame 5 = 625 ms
##   con el báculo en alto): en el frame SPIKES_AIM_FRAME (250 ms antes del
##   impacto) fija hacia dónde va la línea. En el impacto sale el primer pico a
##   spike_spacing px de ella y cada spike_interval s otro más lejos, hasta
##   spike_count. Cada pico avisa 250 ms con una grieta (frames 0-1 de
##   fx-ice_spike) y lastima 375 ms (frames 2-4).
## - NOVA, nova de escarcha (attack2, frame 5 = 625 ms con los brazos arriba):
##   la usa cuando el jugador está a nova_trigger_range px o menos. Anillo de
##   radio 40 alrededor de ella que lastima cuando llega a su tamaño (frame 3
##   del fx, 250 ms después) y frena al jugador (frío: frost_slow_factor por
##   frost_slow_duration s). Después queda nova_recover_time en el suelo: la
##   ventana de castigo larga.
## - Fase 2 (vida <= 50 %): además del brillo y la velocidad ×1.25 de
##   BossBase, invoca crystal_count cristales (SUMMON, attack2 = 1 s, con
##   fx-frost_mark donde van a aparecer). Mientras haya alguno en pie no recibe
##   daño. Cuando se rompen todos, vuelve a invocarlos tras
##   crystal_resummon_cooldown s.
##
## Prioridad: cristales (si tocan), nova (si el jugador está cerca) y picos.
## Fuera de alcance o con todo en enfriamiento, se reacomoda.

enum State { IDLE, REPOSITION, SPIKES, NOVA, SUMMON, RECOVER }
enum Attack { SPIKES, NOVA, SUMMON }

const SPIKES_ANIMATION := &"attack"
const NOVA_ANIMATION := &"attack2"
const SUMMON_ANIMATION := &"attack2"
## Frames de impacto de la tabla de archivos de la sección 9.
const SPIKES_IMPACT_FRAME := 5
const NOVA_IMPACT_FRAME := 5
## Frame de attack en el que se fija la dirección de la línea de picos (9.3:
## "hacia donde estaba el jugador en el frame 3").
const SPIKES_AIM_FRAME := 3
## Color de las partículas del frío en el jugador (ojos de la liche, #a7d1e6).
const FROST_COLOR := Color(0.655, 0.82, 0.902)

@export_group("Distancia")
## Banda de distancia al jugador en la que se queda quieta.
@export var keep_min_distance: float = 60.0
@export var keep_max_distance: float = 110.0
## Hasta dónde retrocede desde su puesto cuando el jugador se acerca.
@export var max_retreat_from_home: float = 64.0

@export_group("Línea de picos")
## Distancia máxima al jugador para lanzar la línea.
@export var spikes_range: float = 110.0
@export var spike_count: int = 6
## Separación entre picos (el primero sale a esta distancia de ella).
@export var spike_spacing: float = 16.0
## Segundos entre un pico y el siguiente.
@export var spike_interval: float = 0.08
@export var spikes_cooldown: float = 2.5
## Recuperación después de la línea (ventana de castigo).
@export var spikes_recover_time: float = 0.5

@export_group("Nova de escarcha")
## Distancia al jugador a la que usa la nova.
@export var nova_trigger_range: float = 44.0
@export var nova_cooldown: float = 5.0
## Segundos en el suelo después de la nova (ventana de castigo).
@export var nova_recover_time: float = 1.2
## Frío: multiplica la velocidad del jugador durante frost_slow_duration s.
@export_range(0.0, 1.0, 0.05) var frost_slow_factor: float = 0.5
@export var frost_slow_duration: float = 2.0

@export_group("Fase 2: cristales escudo")
@export var crystal_count: int = 2
## Distancia de los cristales a ella.
@export var crystal_distance: float = 24.0
## Ángulo entre los cristales, centrado hacia el jugador (así quedan en el
## suelo libre entre los dos y no dentro de una pared).
@export var crystal_spread_degrees: float = 90.0
## Recuperación después de invocarlos (no es ventana de castigo: los cristales
## ya la protegen).
@export var summon_recover_time: float = 0.6
## Segundos desde que se rompe el último cristal hasta que puede invocar otros.
@export var crystal_resummon_cooldown: float = 6.0

@export_group("Efectos")
@export var ice_spike_scene: PackedScene = preload("res://scenes/bosses/lich/IceSpike.tscn")
@export var frost_nova_scene: PackedScene = preload("res://scenes/bosses/lich/FrostNova.tscn")
@export var frost_mark_scene: PackedScene = preload("res://scenes/bosses/lich/FrostMark.tscn")
@export var ice_crystal_scene: PackedScene = preload("res://scenes/bosses/lich/IceCrystal.tscn")

var _state: State = State.IDLE
var _state_left: float = 0.0
var _spikes_cooldown_left: float = 0.0
var _nova_cooldown_left: float = 0.0
var _summon_cooldown_left: float = 0.0
## Línea de picos en curso: desde dónde y hacia dónde (fijados en el frame 3).
var _spike_origin: Vector2 = Vector2.ZERO
var _spike_direction: Vector2 = Vector2.RIGHT
var _spike_aimed: bool = false
## Picos que faltan por salir y cuánto falta para el siguiente.
var _spikes_left: int = 0
var _next_spike_index: int = 0
var _spike_timer: float = 0.0
## Cristales invocados (vivos o no). Vacío si no hay ninguna invocación activa.
var _crystals: Array[Node] = []
## Dónde van los cristales de la invocación en curso (fijado al empezarla).
var _crystal_targets: Array[Vector2] = []


func get_state() -> State:
	return _state


func _physics_process(delta: float) -> void:
	# Los picos salen en su ritmo aunque ella reciba un empujón o se estremezca.
	advance_spikes(delta)
	super(delta)


func _get_move_velocity(delta: float) -> Vector2:
	_spikes_cooldown_left = maxf(_spikes_cooldown_left - delta, 0.0)
	_nova_cooldown_left = maxf(_nova_cooldown_left - delta, 0.0)
	_update_crystals(delta)
	match _state:
		State.IDLE:
			return _update_idle()
		State.REPOSITION:
			return _update_reposition(delta)
		State.RECOVER:
			_update_recover(delta)
	# SPIKES, NOVA y SUMMON: quieta mientras dura la animación.
	return Vector2.ZERO


func _update_idle() -> Vector2:
	if can_see_player():
		engage()
	if is_engaged():
		_state = State.REPOSITION
	return Vector2.ZERO


func _update_reposition(delta: float) -> Vector2:
	if not player_in_zone():
		return velocity_home()
	match _choose_attack():
		Attack.SPIKES:
			_start_spikes()
			return Vector2.ZERO
		Attack.NOVA:
			_start_nova()
			return Vector2.ZERO
		Attack.SUMMON:
			_start_summon()
			return Vector2.ZERO
	return _keep_distance_velocity(delta)


func _update_recover(delta: float) -> void:
	_state_left -= delta
	if _state_left <= 0.0:
		set_vulnerable(false)
		_state = State.REPOSITION


## Velocidad para quedarse en la banda keep_min..keep_max del jugador.
func _keep_distance_velocity(delta: float) -> Vector2:
	var distance := distance_to_player()
	if distance > keep_max_distance:
		return velocity_toward(player_position())
	if distance < keep_min_distance and has_player():
		var away := player_position().direction_to(global_position)
		if away == Vector2.ZERO:
			away = Vector2.RIGHT if sprite.flip_h else Vector2.LEFT
		var velocity_away := away * current_speed()
		var next := global_position + velocity_away * delta
		var from_home := _home.distance_to(global_position)
		# Acorralada lejos de su puesto: se planta (y el jugador recibe la nova).
		if _home.distance_to(next) <= max_retreat_from_home or _home.distance_to(next) < from_home:
			return velocity_away
	face_player()
	return Vector2.ZERO


## Ataque que corresponde ahora, o -1 si ninguno.
func _choose_attack() -> int:
	if _can_summon():
		return Attack.SUMMON
	var distance := distance_to_player()
	if _nova_cooldown_left <= 0.0 and distance <= nova_trigger_range:
		return Attack.NOVA
	if _spikes_cooldown_left <= 0.0 and distance <= spikes_range:
		return Attack.SPIKES
	return -1


func _can_summon() -> bool:
	return is_phase_two() and _crystals.is_empty() and _summon_cooldown_left <= 0.0 \
			and crystal_count > 0


# ---------------------------------------------------------------------------
# Línea de picos
# ---------------------------------------------------------------------------

func _start_spikes() -> void:
	_state = State.SPIKES
	_spike_aimed = false
	start_move(SPIKES_ANIMATION, SPIKES_IMPACT_FRAME)


## Fija desde dónde y hacia dónde sale la línea: hacia el jugador ahora.
func _aim_spikes() -> void:
	_spike_aimed = true
	_spike_origin = global_position
	var direction := global_position.direction_to(player_position())
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT if sprite.flip_h else Vector2.RIGHT
	_spike_direction = direction


## Posición del pico index (0 = el más cercano) de la línea en curso.
func spike_position(index: int) -> Vector2:
	return _spike_origin + _spike_direction * spike_spacing * (index + 1)


## Dónde caen todos los picos de la línea en curso.
func spike_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in spike_count:
		out.append(spike_position(i))
	return out


## Saca los picos pendientes cuyo turno llegó. La llama _physics_process; las
## pruebas la llaman con el delta que quieren.
func advance_spikes(delta: float) -> void:
	if _spikes_left <= 0 or is_dying:
		return
	_spike_timer -= delta
	while _spikes_left > 0 and _spike_timer <= 0.0:
		_spawn_next_spike()
		_spike_timer += spike_interval


func _spawn_next_spike() -> void:
	spawn_hazard(ice_spike_scene, spike_position(_next_spike_index))
	_next_spike_index += 1
	_spikes_left -= 1


func _start_spike_line() -> void:
	if not _spike_aimed:
		_aim_spikes()
	_next_spike_index = 0
	_spikes_left = spike_count
	_spike_timer = 0.0
	# El primero sale ya, en el frame de impacto.
	advance_spikes(0.0)


# ---------------------------------------------------------------------------
# Nova de escarcha
# ---------------------------------------------------------------------------

func _start_nova() -> void:
	_state = State.NOVA
	start_move(NOVA_ANIMATION, NOVA_IMPACT_FRAME)


func _spawn_nova() -> void:
	var nova := spawn_hazard(frost_nova_scene, global_position)
	if nova != null and nova.has_signal(&"struck"):
		nova.struck.connect(_on_nova_struck)


## El anillo alcanzó al jugador: además del daño, el frío.
func _on_nova_struck(target: Node2D) -> void:
	if is_instance_valid(target) and target.has_method("apply_slow"):
		target.apply_slow(frost_slow_factor, frost_slow_duration, FROST_COLOR)


# ---------------------------------------------------------------------------
# Fase 2: cristales escudo
# ---------------------------------------------------------------------------

func _start_summon() -> void:
	_state = State.SUMMON
	_crystal_targets = crystal_positions()
	# El aviso: una marca de escarcha donde va a salir cada cristal. Dura lo
	# mismo que la invocación (6 frames a 6 FPS = 1 s) y no lastima.
	for at in _crystal_targets:
		spawn_hazard(frost_mark_scene, at)
	# Sin impacto propio: los cristales salen al terminar la animación.
	start_move(SUMMON_ANIMATION, sprite.sprite_frames.get_frame_count(SUMMON_ANIMATION))


## Dónde salen los cristales: a crystal_distance px de ella, repartidos en
## crystal_spread_degrees y centrados hacia el jugador.
func crystal_positions() -> Array[Vector2]:
	var toward := global_position.direction_to(player_position())
	if toward == Vector2.ZERO:
		toward = Vector2.LEFT if sprite.flip_h else Vector2.RIGHT
	var out: Array[Vector2] = []
	var spread := deg_to_rad(crystal_spread_degrees)
	for i in crystal_count:
		var t := 0.5 if crystal_count == 1 else float(i) / float(crystal_count - 1)
		out.append(global_position + toward.rotated(lerpf(-spread / 2.0, spread / 2.0, t)) * crystal_distance)
	return out


func _spawn_crystals() -> void:
	_crystals.clear()
	for at in _crystal_targets:
		var crystal := spawn_minion(ice_crystal_scene, at)
		if crystal != null:
			_crystals.append(crystal)


## Cristales que siguen en pie (los que todavía no aparecieron también
## cuentan: ya fueron invocados).
func standing_crystals() -> Array[Node]:
	var out: Array[Node] = []
	for crystal in _crystals:
		if is_instance_valid(crystal) and not crystal.is_queued_for_deletion() \
				and not (crystal as EnemyBase).is_dying:
			out.append(crystal)
	return out


func is_shielded() -> bool:
	return not standing_crystals().is_empty()


## Cuando cae el último cristal empieza la espera para volver a invocarlos.
func _update_crystals(delta: float) -> void:
	_summon_cooldown_left = maxf(_summon_cooldown_left - delta, 0.0)
	if not _crystals.is_empty() and not is_shielded():
		_crystals.clear()
		_summon_cooldown_left = crystal_resummon_cooldown


# ---------------------------------------------------------------------------
# Ganchos de BossBase
# ---------------------------------------------------------------------------

func _on_sprite_frame_changed() -> void:
	# Fija la línea de picos en su frame, antes del impacto.
	if _state == State.SPIKES and not _spike_aimed and is_performing_move() \
			and sprite.animation == SPIKES_ANIMATION and sprite.frame >= SPIKES_AIM_FRAME:
		_aim_spikes()
	super()


func _on_move_impact(animation: StringName) -> void:
	match _state:
		State.SPIKES:
			if animation == SPIKES_ANIMATION:
				_start_spike_line()
		State.NOVA:
			if animation == NOVA_ANIMATION:
				_spawn_nova()


func _on_move_finished(animation: StringName) -> void:
	match _state:
		State.SPIKES:
			if animation == SPIKES_ANIMATION:
				_spikes_cooldown_left = spikes_cooldown
				_enter_recover(spikes_recover_time, true)
		State.NOVA:
			if animation == NOVA_ANIMATION:
				_nova_cooldown_left = nova_cooldown
				_enter_recover(nova_recover_time, true)
		State.SUMMON:
			if animation == SUMMON_ANIMATION:
				_spawn_crystals()
				_enter_recover(summon_recover_time, false)


func _enter_recover(duration: float, vulnerable: bool) -> void:
	_state = State.RECOVER
	_state_left = duration
	set_vulnerable(vulnerable)


## Con cristales en pie no recibe daño.
func _modify_incoming_damage(amount: int) -> int:
	return 0 if is_shielded() else amount


## El golpe rebota: los cristales laten para mostrar quién la protege.
func _on_hit_blocked(_from_position: Vector2) -> void:
	engage()
	for crystal in standing_crystals():
		if crystal.is_inside_tree():
			var pulse := crystal.create_tween()
			crystal.scale = Vector2(1.3, 1.3)
			pulse.tween_property(crystal, "scale", Vector2.ONE, 0.2)


## Además del ataque en curso, la pose final se mantiene en la recuperación.
func _is_animation_locked() -> bool:
	return super() or _state == State.RECOVER


func _die() -> void:
	_spikes_left = 0
	_crystals.clear()
	super()
