extends Node
## Game feel ("juice"): vibración de cámara (screenshake), congelado breve al
## golpear (hit-stop), textos flotantes y chispas. Se registra como Autoload
## ("GameFeel") y, como Sfx o RunTracker, solo escucha señales: el jugador y los
## enemigos no dependen de él.
##
## Screenshake por trauma: cada momento clave suma trauma (0 a 1), la cámara se
## desplaza MAX_SHAKE_OFFSET * trauma² con ruido suave, y el trauma baja solo
## (TRAUMA_DECAY por segundo). Elevarlo al cuadrado hace que los golpes chicos
## apenas se noten y los grandes sí.
##
## F3 muestra un panel con los tiempos en vivo (buffer, coyote, trauma) para
## demostrar los efectos.

## Desplazamiento máximo de la cámara, en píxeles del mundo (la cámara tiene
## zoom 3: 5 px son 15 px en pantalla).
const MAX_SHAKE_OFFSET := Vector2(5.0, 4.0)
## Trauma que se pierde por segundo.
const TRAUMA_DECAY := 1.6
## Velocidad del ruido de la vibración (más alto = más nervioso).
const SHAKE_NOISE_SPEED := 60.0

## Trauma de cada momento clave.
const TRAUMA_PLAYER_HURT := 0.45
const TRAUMA_ENEMY_HIT := 0.15
const TRAUMA_ENEMY_KILLED := 0.25
const TRAUMA_BOSS_HIT := 0.3
const TRAUMA_BOSS_KILLED := 0.8
const TRAUMA_LANDING := 0.15
const TRAUMA_FALL := 0.5

## Hit-stop: segundos de juego casi congelado y a qué velocidad corre.
const HITSTOP_ENEMY_HIT := 0.05
const HITSTOP_PLAYER_HURT := 0.08
const HITSTOP_BOSS_KILLED := 0.15
const HITSTOP_TIME_SCALE := 0.05

## Textos flotantes: cuánto suben y cuánto duran.
const POPUP_RISE := 12.0
const POPUP_TIME := 0.7
const COLOR_DAMAGE_DEALT := Color(1.0, 0.95, 0.6)
const COLOR_DAMAGE_TAKEN := Color(1.0, 0.35, 0.3)
const COLOR_COIN := Color(1.0, 0.82, 0.2)
const COLOR_HEAL := Color(0.5, 1.0, 0.5)
const COLOR_KEY := Color(1.0, 0.9, 0.4)
const COLOR_BUFFER := Color(0.6, 0.85, 1.0)

## Apaga la vibración (accesibilidad). El hit-stop y los textos siguen.
var shake_enabled := true
## Trauma actual, de 0 a 1.
var trauma := 0.0

var _noise := FastNoiseLite.new()
var _noise_t := 0.0
var _last_ticks := 0
var _shaken_camera: Camera2D
var _camera_base_offset := Vector2.ZERO
var _hitstop_until_ms := 0
var _time_scale_before := 1.0
var _player: Node2D
var _player_health := -1
var _debug_layer: CanvasLayer
var _debug_label: Label
var _last_buffered := ""


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	# Sigue con el juego en pausa o en hit-stop (corre con el tiempo real).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise.seed = randi()
	_noise.frequency = 0.5
	_last_ticks = Time.get_ticks_usec()


## Suma trauma (se recorta a 1). Lo usan los momentos clave.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Congela casi por completo el juego seconds segundos (tiempo real).
func hitstop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if _hitstop_until_ms == 0:
		_time_scale_before = Engine.time_scale
	Engine.time_scale = HITSTOP_TIME_SCALE
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))


## Texto que sube y se desvanece en world_position (coordenadas del mundo).
func popup(world_position: Vector2, text: String, color: Color, size := 7) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene is Node2D:
		return
	var holder := Node2D.new()
	holder.z_index = 20
	holder.global_position = world_position
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06))
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(40.0, 10.0)
	label.position = Vector2(-20.0, -24.0)
	label.pivot_offset = label.size / 2.0
	holder.add_child(label)
	scene.add_child(holder)
	var tween := holder.create_tween().set_parallel()
	label.scale = Vector2(1.4, 1.4)
	tween.tween_property(label, "scale", Vector2.ONE, 0.12)
	tween.tween_property(label, "position:y", label.position.y - POPUP_RISE, POPUP_TIME) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_TIME * 0.5).set_delay(POPUP_TIME * 0.5)
	tween.chain().tween_callback(holder.queue_free)


## Chispas de un golpe en world_position.
func sparks(world_position: Vector2, color := Color(1.0, 0.9, 0.5)) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene is Node2D:
		return
	var particles := CPUParticles2D.new()
	particles.z_index = 15
	particles.global_position = world_position + Vector2(0, -6)
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 8
	particles.lifetime = 0.25
	particles.spread = 180.0
	particles.initial_velocity_min = 40.0
	particles.initial_velocity_max = 80.0
	particles.gravity = Vector2.ZERO
	particles.damping_min = 120.0
	particles.damping_max = 160.0
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 2.0
	particles.color = color
	scene.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := minf((now - _last_ticks) / 1_000_000.0, 0.1)
	_last_ticks = now
	if _hitstop_until_ms != 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = _time_scale_before
	_update_shake(real_delta)
	_update_debug()


func _update_shake(real_delta: float) -> void:
	trauma = maxf(trauma - TRAUMA_DECAY * real_delta, 0.0)
	var camera := get_viewport().get_camera_2d()
	if camera != _shaken_camera:
		if is_instance_valid(_shaken_camera):
			_shaken_camera.offset = _camera_base_offset
		_shaken_camera = camera
		if camera != null:
			_camera_base_offset = camera.offset
	if camera == null:
		return
	if not shake_enabled or trauma <= 0.0 or get_tree().paused:
		camera.offset = _camera_base_offset
		return
	_noise_t += real_delta * SHAKE_NOISE_SPEED
	var shake := trauma * trauma
	camera.offset = _camera_base_offset + Vector2(
			MAX_SHAKE_OFFSET.x * shake * _noise.get_noise_2d(_noise_t, 0.0),
			MAX_SHAKE_OFFSET.y * shake * _noise.get_noise_2d(0.0, _noise_t))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle_debug()


# --- Conexiones -----------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is EnemyBase:
		node.hit_received.connect(_on_enemy_hit)
		node.died.connect(_on_enemy_died)
	elif node is CharacterBody2D and node.has_signal(&"buffered_action_used"):
		_player = node
		_player_health = -1
		node.damaged.connect(_on_player_damaged)
		node.health_changed.connect(_on_player_health_changed)
		node.coins_collected.connect(_on_player_coins)
		node.key_collected.connect(_on_player_key)
		node.buffered_action_used.connect(_on_buffered_action)
		node.landed.connect(_on_player_landed)
		node.fell.connect(_on_player_fell)


func _on_enemy_hit(enemy: EnemyBase, amount: int) -> void:
	var is_boss := enemy is BossBase
	add_trauma(TRAUMA_BOSS_HIT if is_boss else TRAUMA_ENEMY_HIT)
	hitstop(HITSTOP_ENEMY_HIT)
	sparks(enemy.global_position)
	popup(enemy.global_position, "-%d" % amount, COLOR_DAMAGE_DEALT)


func _on_enemy_died(enemy: EnemyBase) -> void:
	if enemy is BossBase:
		add_trauma(TRAUMA_BOSS_KILLED)
		hitstop(HITSTOP_BOSS_KILLED)
	else:
		add_trauma(TRAUMA_ENEMY_KILLED)
	sparks(enemy.global_position, Color(1.0, 0.6, 0.3))


func _on_player_damaged(amount: int, _source: StringName) -> void:
	add_trauma(TRAUMA_PLAYER_HURT)
	hitstop(HITSTOP_PLAYER_HURT)
	if is_instance_valid(_player):
		popup(_player.global_position, "-%s♥" % _hearts_text(amount), COLOR_DAMAGE_TAKEN)


func _on_player_health_changed(health: int) -> void:
	if _player_health >= 0 and health > _player_health and is_instance_valid(_player):
		popup(_player.global_position, "+%s♥" % _hearts_text(health - _player_health), COLOR_HEAL)
	_player_health = health


func _on_player_coins(amount: int) -> void:
	if is_instance_valid(_player):
		popup(_player.global_position, "+%d" % amount, COLOR_COIN, 8)


func _on_player_key() -> void:
	if is_instance_valid(_player):
		popup(_player.global_position, "¡Llave!", COLOR_KEY, 8)
	add_trauma(0.2)


func _on_buffered_action(action: StringName, waited: float) -> void:
	_last_buffered = "%s guardado %.0f ms" % [action, waited * 1000.0]
	if is_instance_valid(_player):
		popup(_player.global_position + Vector2(0, -8), "buffer", COLOR_BUFFER, 6)


func _on_player_landed() -> void:
	add_trauma(TRAUMA_LANDING)
	if is_instance_valid(_player):
		sparks(_player.global_position + Vector2(0, 12), Color(0.75, 0.7, 0.65))


func _on_player_fell() -> void:
	add_trauma(TRAUMA_FALL)
	if is_instance_valid(_player):
		popup(_player.global_position, "¡Abismo!", COLOR_DAMAGE_TAKEN, 8)


## Medios corazones como texto en corazones: 1 -> "½", 2 -> "1", 3 -> "1½".
static func _hearts_text(half_hearts: int) -> String:
	var whole := half_hearts / 2
	var half := half_hearts % 2 == 1
	if whole == 0:
		return "½"
	return str(whole) + ("½" if half else "")


# --- Panel F3 -------------------------------------------------------------------

func _toggle_debug() -> void:
	if _debug_layer == null:
		_debug_layer = CanvasLayer.new()
		_debug_layer.layer = 100
		_debug_label = Label.new()
		_debug_label.position = Vector2(8, 60)
		_debug_label.add_theme_font_size_override("font_size", 14)
		_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_debug_label.add_theme_constant_override("outline_size", 4)
		_debug_layer.add_child(_debug_label)
		add_child(_debug_layer)
	else:
		_debug_layer.visible = not _debug_layer.visible


func _update_debug() -> void:
	if _debug_layer == null or not _debug_layer.visible:
		return
	var lines := PackedStringArray(["GAME FEEL (F3)"])
	if is_instance_valid(_player):
		lines.append("Buffer ataque: %.0f / %.0f ms" % [
				_player.attack_buffer_left() * 1000.0, _player.attack_buffer_time * 1000.0])
		if _player.has_method("coyote_left"):
			lines.append("Buffer salto: %.0f / %.0f ms" % [
					_player.jump_buffer_left() * 1000.0, _player.jump_buffer_time * 1000.0])
			lines.append("Coyote: %.0f / %.0f ms" % [
					_player.coyote_left() * 1000.0, _player.coyote_time * 1000.0])
			lines.append("Saltando: %s" % ("sí" if _player.is_jumping() else "no"))
	lines.append("Trauma: %.2f  %s" % [trauma, "▮".repeat(int(trauma * 20.0))])
	lines.append("Hit-stop: %s" % ("SÍ" if _hitstop_until_ms != 0 else "no"))
	if _last_buffered != "":
		lines.append("Último buffer: " + _last_buffered)
	_debug_label.text = "\n".join(lines)
