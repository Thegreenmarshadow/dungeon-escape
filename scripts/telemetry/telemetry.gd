extends Node
## Telemetría de cada nivel: el recorrido del jugador y lo que pasa (daño,
## enemigos, corazones, llave, puerta, golpes, armas, muerte) con su posición
## y su tiempo. Se registra como Autoload ("Telemetry", después de RunTracker)
## y, como RunTracker, no cambia nada del juego: solo escucha señales.
##
## Todo queda en memoria (TelemetryRecorder) y se escribe en disco una sola
## vez, al terminar el nivel: superado, muerte o abandonado (volver al menú,
## cambiar de escena, cerrar la ventana). Ver TelemetryStore para el formato y
## la ruta de los archivos. Con la telemetría apagada en los ajustes
## (GameSettings) no se registra nada.
##
## Para las pantallas del juego (minimapa, resumen del nivel):
##   - is_recording(), current_path(), current_events(), current_map(),
##     current_data(): el nivel en curso, en vivo. Devuelven los datos sin
##     copiar: no los modifiques.
##   - level_started(data), event_recorded(event), level_finished(data, path):
##     señales. level_finished llega con el nivel ya escrito (path vacío si no
##     se pudo escribir); last_level_data y last_level_file lo conservan.
##
## Señales que observa: Game.run_started, Game.returning_to_menu,
## SceneTree.node_added (como RunTracker), y en cada nivel Player.damaged,
## lives_changed, key_collected, attacked, weapon_changed, died, knocked_out,
## revived, ExitDoor.player_escaped y locked_touched, EnemyBase.died.
##
## Sin class_name a propósito: chocaría con el nombre del Autoload.

## Empezó a registrarse un nivel. data es current_data() (vacío de eventos).
signal level_started(data: Dictionary)
## Se agregó un evento al nivel en curso.
signal event_recorded(event: Dictionary)
## Terminó el nivel y se escribió en path ("" si no se pudo).
signal level_finished(data: Dictionary, path: String)

## Carpeta de los perfiles donde se escribe (las pruebas usan una temporal).
var base_dir := ProfileStore.DEFAULT_BASE_DIR
## Ajustes de donde se lee si la telemetría está activa.
var settings_path := GameSettings.DEFAULT_PATH
var recorder := TelemetryRecorder.new()
## Último nivel terminado y su archivo.
var last_level_data: Dictionary = {}
var last_level_file := ""

## Partida en curso: run_id, mode, profile, profile_slug, seed. Vacío si no
## hay (y entonces no se registra ningún nivel).
var _run: Dictionary = {}
var _level: Node
var _player: Node2D
var _lives := 0


func _ready() -> void:
	Game.run_started.connect(_on_run_started)
	Game.returning_to_menu.connect(abandon)
	get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	if recorder.is_active() and is_instance_valid(_player):
		recorder.advance(delta, _player.global_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		abandon()


# ---------------------------------------------------------------------------
# API para el juego
# ---------------------------------------------------------------------------

func is_recording() -> bool:
	return recorder.is_active()


## Recorrido del nivel en curso: [[t, x, y], ...].
func current_path() -> Array:
	return recorder.data.get("path", []) if recorder.is_active() else []


## Eventos del nivel en curso.
func current_events() -> Array:
	return recorder.data.get("events", []) if recorder.is_active() else []


## Mapa del nivel en curso (LevelSnapshot); {} si no se registra.
func current_map() -> Dictionary:
	return recorder.data.get("map", {}) if recorder.is_active() else {}


## Todo el archivo del nivel en curso tal como se escribiría ahora (outcome
## "in_progress"); {} si no se registra.
func current_data() -> Dictionary:
	return recorder.data if recorder.is_active() else {}


func is_enabled() -> bool:
	return GameSettings.telemetry_enabled(settings_path)


## Índice de dificultad planificado (DifficultyCurve.index_for) que se guarda
## en el archivo del nivel, redondeado a milésimas; null en los niveles hechos
## a mano y en la demo (no salen del generador).
static func planned_difficulty(level_number: int, mode: String) -> Variant:
	if mode == RunRecorder.MODE_DEMO:
		return null
	var index := LevelStats.planned_index(level_number)
	return null if is_nan(index) else roundf(index * 1000.0) / 1000.0


## Empieza una partida: los niveles que se registren desde ahora llevan estos
## datos. profile_slug es la carpeta del perfil.
func begin_run(run_id: String, mode: String, profile_name: String, profile_slug: String, run_seed: int) -> void:
	abandon()
	_run = {"run_id": run_id, "mode": mode, "profile": profile_name,
			"profile_slug": profile_slug, "seed": run_seed}


## Empieza a registrar un nivel. level es la escena (al salir del árbol el
## nivel queda abandonado), player el jugador, door la puerta de salida,
## enemies los enemigos que ya están, map el de LevelSnapshot. false si no hay
## partida o la telemetría está apagada.
func attach_level(level: Node, player: Node2D, door: Node, enemies: Array, map: Dictionary,
		level_number: int, level_seed: Variant = null) -> bool:
	if _run.is_empty() or not is_enabled():
		return false
	abandon()
	_level = level
	_player = player
	_lives = player.lives
	var meta := _run.duplicate()
	meta["level"] = level_number
	# Texto: la semilla de un mapa generado no entra en un double de JSON.
	meta["level_seed"] = str(level_seed) if level_seed != null else null
	meta["difficulty_index"] = planned_difficulty(level_number, str(_run.get("mode", "")))
	recorder.start(meta, map, player.global_position, String(player.weapon.id) if player.weapon else "")

	player.damaged.connect(_on_damaged)
	player.lives_changed.connect(_on_lives_changed)
	player.key_collected.connect(_record.bind(TelemetryStore.EVENT_KEY))
	player.attacked.connect(_on_attacked)
	player.weapon_changed.connect(_on_weapon_changed)
	player.died.connect(_on_died)
	player.knocked_out.connect(_on_knocked_out)
	player.revived.connect(_on_revived)
	if door != null:
		door.connect(&"player_escaped", _on_escaped)
		door.connect(&"locked_touched", _on_locked_touched)
	for enemy: Node in enemies:
		watch_enemy(enemy)
	level.tree_exiting.connect(_on_level_exiting.bind(level))
	level_started.emit(recorder.data)
	return true


## Registra la muerte de enemy (enemy_killed). Los enemigos que aparecen
## después (esbirros de los jefes) se agregan solos.
func watch_enemy(enemy: Node) -> void:
	if enemy.has_signal(&"died") and not enemy.is_connected(&"died", _on_enemy_died):
		enemy.connect(&"died", _on_enemy_died)


## Termina el nivel en curso con outcome, lo escribe y avisa
## (level_finished). Devuelve el archivo del nivel; {} si no había ninguno.
func finish_level(outcome: String) -> Dictionary:
	if not recorder.is_active():
		return {}
	var position := _player.global_position if is_instance_valid(_player) else Vector2.INF
	var data := recorder.finish(outcome, position)
	_disconnect_player()
	_level = null
	_player = null
	last_level_data = data
	last_level_file = TelemetryStore.new(base_dir).write_level(data)
	level_finished.emit(data, last_level_file)
	return data


## Cierra el nivel en curso (si hay) como abandonado.
func abandon() -> void:
	finish_level(TelemetryRecorder.OUTCOME_ABANDONED)


# ---------------------------------------------------------------------------
# Partida y niveles
# ---------------------------------------------------------------------------

func _on_run_started() -> void:
	var profile: Dictionary = Profiles.current_profile()
	var profile_name: String = profile.get("name", PlayerProfile.current_name())
	var slug: String = profile.get("slug", ProfileStore.slug_for(profile_name))
	begin_run(Game.run_id, RunTracker.current_mode(), profile_name, slug, Game.run_seed)


## Como RunTracker: solo las escenas principales. Otra pantalla cierra el
## nivel que estuviera abierto.
func _on_node_added(node: Node) -> void:
	if recorder.is_active() and node is EnemyBase and _level != null and _level.is_ancestor_of(node):
		watch_enemy(node)
		return
	if node.get_parent() != get_tree().root or node.scene_file_path.is_empty():
		return
	if node.scene_file_path in [Game.LEVEL_SCENE, Game.DEMO_SCENE]:
		node.ready.connect(_on_level_ready.bind(node), CONNECT_ONE_SHOT)
	else:
		abandon()


func _on_level_ready(level: Node) -> void:
	if _run.is_empty():
		return
	var enemies: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if level.is_ancestor_of(enemy):
			enemies.append(enemy)
	var layout: Variant = level.get("map_layout")
	var level_seed: Variant = layout.seed_used if layout is LevelGenerator.Layout and not Game.demo_mode else null
	# Game.current_level se cachea acá: al escapar, el nivel lo incrementa
	# antes de que llegue la señal de la puerta.
	attach_level(level, level.get_node("Player"), level.get_node_or_null("ExitDoor"), enemies,
			LevelSnapshot.from_level(level), Game.current_level, level_seed)


func _on_level_exiting(level: Node) -> void:
	if level == _level:
		abandon()


# ---------------------------------------------------------------------------
# Eventos
# ---------------------------------------------------------------------------

func _record(type: String, fields: Dictionary = {}, at: Vector2 = Vector2.INF) -> void:
	if not recorder.is_active():
		return
	if at == Vector2.INF:
		at = _player.global_position if is_instance_valid(_player) else Vector2.ZERO
	var event := recorder.record(type, at, fields)
	if not event.is_empty():
		event_recorded.emit(event)


func _on_damaged(amount: int, source: StringName) -> void:
	_record(TelemetryStore.EVENT_DAMAGE, {"amount": amount, "source": String(source)})


## Las bajas ya llegan con damaged; una suba es un corazón (lo único que cura).
func _on_lives_changed(lives: int) -> void:
	if lives > _lives:
		_record(TelemetryStore.EVENT_HEART, {"amount": lives - _lives})
	_lives = lives


func _on_attacked(hit: bool) -> void:
	_record(TelemetryStore.EVENT_ATTACK, {"hit": hit})


func _on_weapon_changed(weapon_id: StringName) -> void:
	recorder.add_weapon(String(weapon_id))
	_record(TelemetryStore.EVENT_WEAPON_CHANGED, {"weapon": String(weapon_id)})


func _on_enemy_died(enemy: Node) -> void:
	var at := (enemy as Node2D).global_position if enemy is Node2D else Vector2.INF
	_record(TelemetryStore.EVENT_ENEMY_KILLED, {"enemy": RunRecorder.enemy_kind(enemy)}, at)


func _on_locked_touched() -> void:
	_record(TelemetryStore.EVENT_DOOR, {"state": "locked"})


func _on_escaped() -> void:
	_record(TelemetryStore.EVENT_DOOR, {"state": "escaped"})
	finish_level(TelemetryRecorder.OUTCOME_COMPLETED)


func _on_died() -> void:
	_record(TelemetryStore.EVENT_DEATH, {"cause": _death_cause(), "final": true})
	finish_level(TelemetryRecorder.OUTCOME_DIED)


## La demo no termina al quedarse sin vidas: lo revive (revive) más tarde.
func _on_knocked_out() -> void:
	_record(TelemetryStore.EVENT_DEATH, {"cause": _death_cause(), "final": false})


func _on_revived(lives: int) -> void:
	if not recorder.is_active() or not is_instance_valid(_player):
		return
	_lives = lives
	var index := recorder.break_path(_player.global_position)
	_record(TelemetryStore.EVENT_REVIVE, {"lives": lives, "path_index": index})


func _death_cause() -> String:
	return String(_player.last_damage_source) if is_instance_valid(_player) else ""


func _disconnect_player() -> void:
	if not is_instance_valid(_player):
		return
	for connection: Array in [
		[&"damaged", _on_damaged], [&"lives_changed", _on_lives_changed],
		[&"attacked", _on_attacked], [&"weapon_changed", _on_weapon_changed],
		[&"died", _on_died], [&"knocked_out", _on_knocked_out], [&"revived", _on_revived],
	]:
		if _player.is_connected(connection[0], connection[1]):
			_player.disconnect(connection[0], connection[1])
	for connection: Dictionary in _player.get_signal_connection_list(&"key_collected"):
		if connection["callable"].get_object() == self:
			_player.disconnect(&"key_collected", connection["callable"])
