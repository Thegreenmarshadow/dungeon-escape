class_name BossBase
extends EnemyBase
## Base de los jefes temáticos (docs/assets-pack/03-jefes.md, sección 9).
##
## Hereda de EnemyBase en lugar de componerse con él: así un jefe sigue siendo
## un enemigo para todo lo que ya existe (grupo "enemies", música de peligro,
## contador de muertes, escala de vida por nivel, corazón y monedas al morir,
## golpes de la espada) sin tocar Level ni el jugador. Lo propio de los jefes
## se agrega acá:
##
## - Vida visible: health_changed y display_name para la barra del HUD
##   (BossHealthBar), que se ve mientras el jefe está en alerta.
## - Combate comprometido: una vez que ve al jugador (engage) queda en alerta
##   hasta morir, aunque se aleje.
## - Fase 2 con vida <= PHASE_TWO_RATIO: brillo constante, velocidad
##   ×phase_two_speed_multiplier, phase_changed y el gancho _on_phase_two.
## - Golpes con frame de impacto: start_move(animación, frame) llama a
##   _on_move_impact en ese frame y a _on_move_finished al terminar.
## - Ventana de castigo: set_vulnerable(true) tiñe de azulado (2.3 de la biblia).
## - Efectos en el suelo y criaturas: spawn_hazard / spawn_minion, que se
##   borran solos cuando el jefe muere.
## - Ganchos de daño: _modify_incoming_damage (inmune, +1...) y _can_flinch.
##
## Un golpe del jugador no cancela el ataque de un jefe (sí el de un enemigo
## común): el jefe solo se estremece si no está atacando ni en su ventana de
## castigo. Los jefes no esquivan (dodge_chance 0 en sus escenas).
##
## Estructura de la escena: la de EnemyBase (AnimatedSprite2D,
## CollisionShape2D y ContactArea). Cada jefe hereda de esta clase y arma su
## máquina de estados en _get_move_velocity.

## Cambió la vida (golpe, curación o escala del nivel).
signal health_changed(health: int, max_health: int)
## Entró en otra fase. Hoy solo existe la 2.
signal phase_changed(phase: int)
## Vio al jugador o recibió un golpe por primera vez: empieza el combate.
signal engaged(boss: BossBase)

## Grupo de todos los jefes; Level busca acá al jefe del nivel.
const GROUP := &"bosses"
## Fracción de la vida máxima desde la que empieza la fase 2 (incluida).
const PHASE_TWO_RATIO := 0.5
## Tinte de la ventana de castigo: el mismo azulado que "aturdido y vulnerable"
## de SkullEnemy, reservado para eso en la sección 2.3 de la biblia.
const VULNERABLE_TINT := Color(0.7, 0.7, 1.0)

## Id del jefe en BossRegistry (forge, lich, warden).
@export var boss_id: StringName = &""
## Nombre que muestra la barra de vida del HUD.
@export var display_name: String = "Jefe"

@export_group("Persecución")
## Distancia a la que ve al jugador y empieza el combate.
@export var detect_radius: float = 120.0
## Distancia máxima entre el jugador y el puesto del jefe para perseguirlo.
## Fuera de ella el jefe vuelve a su puesto (sigue en alerta).
@export var leash_radius: float = 160.0

@export_group("Fase 2")
## Multiplicador de speed en la fase 2.
@export var phase_two_speed_multiplier: float = 1.25
## Brillo constante de la fase 2, en el modulate del nodo raíz (así el destello
## rojo de un golpe, que va en el sprite, se sigue viendo).
@export var phase_two_tint: Color = Color(1.3, 1.15, 1.0)

## Fase actual: 1 o 2.
var phase: int = 1
## Nodo donde spawn_hazard agrega los efectos del suelo. LevelBuilder pone el
## nodo Traps del nivel, que se dibuja debajo del jugador; si es null se usa el
## padre del jefe.
var hazard_parent: Node2D

var _engaged: bool = false
var _vulnerable: bool = false
var _home: Vector2
var _player: Node2D
## Generador propio para los sorteos de los ataques; las pruebas lo siembran.
var _rng := RandomNumberGenerator.new()
var _spawned: Array[Node] = []
# Golpe con frame de impacto en curso (start_move). &"" si no hay ninguno.
var _move_animation: StringName = &""
var _move_impact_frame: int = -1
var _move_impact_done: bool = false


func _ready() -> void:
	super()
	add_to_group(GROUP)
	# El puesto es donde LevelBuilder lo colocó (delante de la puerta).
	_home = global_position
	_player = get_tree().get_first_node_in_group("player")
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	_rng.randomize()


# ---------------------------------------------------------------------------
# Estado público
# ---------------------------------------------------------------------------

## En alerta desde que empieza el combate hasta que muere: la música de peligro
## y la barra de vida dependen de esto.
func is_alerted() -> bool:
	return _engaged and not is_dying


func is_engaged() -> bool:
	return _engaged


func is_phase_two() -> bool:
	return phase >= 2


## Empieza el combate (una sola vez).
func engage() -> void:
	if _engaged or is_dying:
		return
	_engaged = true
	engaged.emit(self)


## Velocidad actual: speed, más rápida en la fase 2.
func current_speed() -> float:
	return speed * (phase_two_speed_multiplier if is_phase_two() else 1.0)


## Vida actual sobre la máxima (0 a 1).
func health_ratio() -> float:
	return clampf(float(health) / float(maxi(max_health, 1)), 0.0, 1.0)


## La vida de la escena ya es la pensada para el primer nivel del jefe, así que
## solo crece lo que crecieron los enemigos desde ese nivel: en su primera
## aparición tiene la vida base y en las vueltas siguientes (20, 24, 28...) sube.
func apply_health_scale(multiplier: float) -> void:
	var first_level := BossRegistry.first_level(boss_id)
	if first_level > 0:
		multiplier /= LevelGenerator.enemy_health_scale(first_level)
	super(multiplier)
	health_changed.emit(health, max_health)


func heal(amount: int) -> int:
	var healed := super(amount)
	if healed > 0:
		health_changed.emit(health, max_health)
	return healed


## true si la ventana de castigo está activa (tinte azulado).
func is_vulnerable() -> bool:
	return _vulnerable


## Activa o apaga el tinte de la ventana de castigo.
func set_vulnerable(on: bool) -> void:
	_vulnerable = on
	_refresh_tint()


# ---------------------------------------------------------------------------
# Jugador y movimiento
# ---------------------------------------------------------------------------

func has_player() -> bool:
	return is_instance_valid(_player)


func player_position() -> Vector2:
	return _player.global_position if has_player() else global_position


func distance_to_player() -> float:
	return global_position.distance_to(player_position()) if has_player() else INF


## true si el jugador está dentro de la correa del puesto del jefe.
func player_in_zone() -> bool:
	return has_player() and _home.distance_to(_player.global_position) <= leash_radius


## true si el jugador está a la vista (detect_radius) y dentro de la correa.
func can_see_player() -> bool:
	return player_in_zone() and distance_to_player() <= detect_radius


## Velocidad para ir hacia point a la velocidad actual.
func velocity_toward(point: Vector2) -> Vector2:
	if global_position.distance_to(point) <= 1.0:
		return Vector2.ZERO
	return global_position.direction_to(point) * current_speed()


## Velocidad para volver al puesto; cero si ya está.
func velocity_home() -> Vector2:
	if global_position.distance_to(_home) <= 2.0:
		return Vector2.ZERO
	return velocity_toward(_home)


## Gira el sprite hacia el jugador (mira a la derecha por defecto).
func face_player() -> void:
	if has_player():
		sprite.flip_h = _player.global_position.x < global_position.x


# ---------------------------------------------------------------------------
# Golpes con frame de impacto
# ---------------------------------------------------------------------------

## Empieza un golpe: mira al jugador y reproduce animation (sin loop) desde el
## frame 0. Al llegar a impact_frame llama a _on_move_impact(animation) una
## vez, y al terminar la animación a _on_move_finished(animation). Mientras
## dura, idle/walk no pisan la animación.
func start_move(animation: StringName, impact_frame: int) -> void:
	face_player()
	_move_animation = animation
	_move_impact_frame = impact_frame
	_move_impact_done = false
	sprite.play(animation)
	sprite.frame = 0
	# Asignar el frame 0 no siempre emite frame_changed: un impacto en el
	# frame 0 se resuelve acá.
	_on_sprite_frame_changed()


func is_performing_move() -> bool:
	return _move_animation != &""


## Corta el golpe en curso sin llamar a sus ganchos.
func cancel_move() -> void:
	_move_animation = &""
	_move_impact_done = false


## Segundos de anticipación de un golpe: lo que tarda animation en llegar a
## impact_frame con sus duraciones y FPS. Sirve para comprobar la regla de
## 600 ms de la sección 6.1 de la biblia.
static func move_windup_seconds(frames: SpriteFrames, animation: StringName, impact_frame: int) -> float:
	var total := 0.0
	for i in mini(impact_frame, frames.get_frame_count(animation)):
		total += frames.get_frame_duration(animation, i)
	return total / frames.get_animation_speed(animation)


# ---------------------------------------------------------------------------
# Efectos y criaturas
# ---------------------------------------------------------------------------

## Crea un efecto de suelo (normalmente un BossHazard) en la posición global
## at. Se agrega al momento: un Node2D sin física se puede agregar incluso
## durante un callback de física. Si tiene la propiedad target se le pasa el
## jugador. Se borra solo cuando el jefe muere.
func spawn_hazard(scene: PackedScene, at: Vector2) -> Node2D:
	var hazard: Node2D = scene.instantiate()
	if "target" in hazard:
		hazard.target = _player
	var parent := hazard_parent if is_instance_valid(hazard_parent) else get_parent() as Node2D
	if parent == null:
		hazard.free()
		return null
	hazard.position = parent.to_local(at)
	parent.add_child(hazard)
	_spawned.append(hazard)
	return hazard


## Crea una criatura (cristal, vaina...) junto al jefe, en la posición global
## at. Se agrega diferido porque puede tener física y el pedido puede llegar
## durante un callback de física (por ejemplo, al pasar a la fase 2 por un
## golpe). No entra en el contador del nivel: Level solo cuenta a los enemigos
## que existen al empezar. Se borra cuando el jefe muere.
func spawn_minion(scene: PackedScene, at: Vector2) -> Node2D:
	var minion: Node2D = scene.instantiate()
	var parent := get_parent() as Node2D
	if parent == null:
		minion.free()
		return null
	minion.position = parent.to_local(at)
	parent.add_child.call_deferred(minion)
	_spawned.append(minion)
	return minion


## Borra los efectos y criaturas que siguen vivos.
func clear_spawned() -> void:
	for node in _spawned:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			node.queue_free()
	_spawned.clear()


## Efectos y criaturas creados que siguen vivos.
func spawned_alive() -> Array[Node]:
	var alive: Array[Node] = []
	for node in _spawned:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			alive.append(node)
	return alive


# ---------------------------------------------------------------------------
# Ganchos para cada jefe
# ---------------------------------------------------------------------------

## Llega el frame de impacto del golpe empezado con start_move.
func _on_move_impact(_animation: StringName) -> void:
	pass


## Terminó la animación del golpe empezado con start_move.
func _on_move_finished(_animation: StringName) -> void:
	pass


## Empieza la fase 2 (una sola vez). La base ya aplicó el brillo y la velocidad.
func _on_phase_two() -> void:
	pass


## Daño que de verdad recibe de un golpe de amount. 0 o menos = inmune (por
## ejemplo, la liche con sus cristales en pie); amount + 1 = golpe reforzado
## (el Guardián con la runa encendida).
func _modify_incoming_damage(amount: int) -> int:
	return amount


## Un golpe que _modify_incoming_damage dejó en cero.
func _on_hit_blocked(_from_position: Vector2) -> void:
	pass


## true si un golpe lo hace estremecerse (animación hurt, quieto un momento).
## Por defecto, solo cuando no está atacando ni en su ventana de castigo.
func _can_flinch() -> bool:
	return not is_performing_move() and not _vulnerable


## true mientras idle/walk no deben pisar la animación actual. Por defecto,
## durante un golpe; un jefe lo amplía (p. ej. el martillo clavado).
func _is_animation_locked() -> bool:
	return is_performing_move()


# ---------------------------------------------------------------------------
# EnemyBase
# ---------------------------------------------------------------------------

## Los jefes no esquivan: su ritmo lo marcan los avisos y las ventanas de castigo.
func _can_dodge() -> bool:
	return false


## Resta vida sin cancelar el ataque en curso; empieza el combate, revisa la
## fase 2 y avisa a la barra de vida.
func _receive_hit(amount: int, from_position: Vector2) -> void:
	var dealt := _modify_incoming_damage(amount)
	if dealt <= 0:
		_on_hit_blocked(from_position)
		return
	health -= dealt
	_flash_red()
	Sfx.play(&"enemy_hit")
	engage()
	health_changed.emit(maxi(health, 0), max_health)
	if health <= 0:
		_die()
		return
	_push_away(from_position, hit_knockback_distance())
	_update_phase()
	if _can_flinch():
		_is_hurt = true
		sprite.play(hurt_animation)
		sprite.frame = 0


func _update_animation() -> void:
	if _is_animation_locked():
		return
	super()


func _die() -> void:
	cancel_move()
	set_vulnerable(false)
	super()
	clear_spawned()


func _on_animation_finished() -> void:
	if is_performing_move() and sprite.animation == _move_animation:
		var finished := _move_animation
		if not _move_impact_done:
			_move_impact_done = true
			_on_move_impact(finished)
		_move_animation = &""
		_on_move_finished(finished)
		return
	super()


func _on_sprite_frame_changed() -> void:
	if not is_performing_move() or _move_impact_done or sprite.animation != _move_animation:
		return
	if sprite.frame >= _move_impact_frame:
		_move_impact_done = true
		_on_move_impact(_move_animation)


func _update_phase() -> void:
	if phase != 1 or health <= 0 or health > max_health * PHASE_TWO_RATIO:
		return
	phase = 2
	_refresh_tint()
	phase_changed.emit(phase)
	_on_phase_two()


## modulate del nodo raíz: brillo de la fase 2 por el azulado de la ventana de
## castigo. El sprite queda libre para el destello rojo de los golpes.
func _refresh_tint() -> void:
	var tint := phase_two_tint if is_phase_two() else Color.WHITE
	if _vulnerable:
		tint *= VULNERABLE_TINT
	modulate = tint
