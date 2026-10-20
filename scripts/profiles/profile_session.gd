extends Node
## Perfil del jugador durante el juego. Se registra como Autoload ("Profiles",
## antes de RunTracker) y guarda todo con un ProfileStore:
##
## - Perfil elegido: ensure_profile() lo asegura (migra el nombre del menú
##   anterior la primera vez o crea uno). Lo usan el menú principal y la
##   pantalla de perfiles (ProfileSelect).
## - Tiempo jugado: suma el tiempo sin pausa de cada nivel (los Autoload se
##   pausan con el árbol) y lo guarda en el perfil y en la partida al terminar
##   el nivel, al morir, al volver al menú y al cerrar la ventana.
## - Partida guardada: al empezar cada nivel de una partida normal (no de
##   prueba ni la demo) guarda nivel, vidas, arma, semilla, monedas y mejoras;
##   morir la borra. continue_saved_game() la retoma ("Continuar").
##
## Solo observa señales que ya existen (Game.run_started,
## Game.returning_to_menu, SceneTree.node_added, Player.died,
## Door.player_escaped): no cambia nada del juego. Nada se escribe si no hay
## una partida empezada con Game.run_started, así las pruebas que cargan un
## nivel suelto no tocan los perfiles.
##
## Sin class_name a propósito: chocaría con el nombre del Autoload.

var store := ProfileStore.new()

# Partida en curso: perfil y modo con los que empezó (vacío si no hay).
var _run_slug := ""
var _run_id := ""
var _mode := ""
var _level_active := false
# Segundos jugados que todavía no se guardaron en el perfil.
var _pending_time := 0.0


func _ready() -> void:
	Game.run_started.connect(_on_run_started)
	Game.returning_to_menu.connect(_end_run)
	get_tree().node_added.connect(_on_node_added)


## Usa otra carpeta de perfiles (las pruebas y las corridas de prueba).
func use_base_dir(base_dir: String) -> void:
	store = ProfileStore.new(base_dir)


## Perfil elegido, creándolo si hace falta: la primera vez pasa el nombre de
## player.cfg a un perfil; si no hay ninguno elegido, elige el primero o crea
## uno con el nombre por defecto.
func ensure_profile() -> Dictionary:
	store.migrate_legacy()
	var profile := store.selected_profile()
	if not profile.is_empty():
		return profile
	var profiles := store.list_profiles()
	profile = profiles[0] if not profiles.is_empty() else store.create_profile(PlayerProfile.load_name())
	select_profile(profile["slug"])
	return profile


## Perfil elegido, o {} si no hay.
func current_profile() -> Dictionary:
	return store.selected_profile()


## Elige el perfil y deja su nombre también en player.cfg, el que usan las
## estadísticas (PlayerProfile).
func select_profile(slug: String) -> bool:
	if not store.select_profile(slug):
		return false
	PlayerProfile.save_name(store.load_profile(slug)["name"])
	return true


## Crea un perfil (o devuelve el que ya tiene ese nombre) y lo elige.
func create_profile(player_name: String) -> Dictionary:
	var profile := store.create_profile(player_name)
	select_profile(profile["slug"])
	return profile


func delete_profile(slug: String) -> bool:
	return store.delete_profile(slug)


## Partida guardada del perfil elegido, o {} si no tiene.
func saved_game() -> Dictionary:
	var profile := current_profile()
	return profile.get("save", {}) if not profile.is_empty() else {}


## Retoma la partida guardada del perfil elegido. false si no hay.
func continue_saved_game() -> bool:
	var save := saved_game()
	if save.is_empty():
		return false
	Game.continue_run(save)
	return true


func _process(delta: float) -> void:
	if _level_active:
		_pending_time += delta


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_end_run()


## Guarda en el perfil el tiempo jugado que falta.
func flush_time() -> void:
	if _pending_time > 0.0 and not _run_slug.is_empty():
		store.add_play_time(_run_slug, _pending_time, _run_id, _mode)
	_pending_time = 0.0


func _on_run_started() -> void:
	flush_time()
	var profile := ensure_profile()
	_run_slug = profile["slug"]
	_run_id = Game.run_id
	_mode = _current_mode()
	_level_active = false


func _current_mode() -> String:
	if Game.demo_mode:
		return RunRecorder.MODE_DEMO
	return RunRecorder.MODE_TEST if Game.test_mode else RunRecorder.MODE_NORMAL


## Como RunTracker: solo las escenas principales. Otra pantalla (el menú, los
## perfiles) cierra el nivel que estuviera abierto.
func _on_node_added(node: Node) -> void:
	if node.get_parent() != get_tree().root or node.scene_file_path.is_empty():
		return
	if node.scene_file_path in [Game.LEVEL_SCENE, Game.DEMO_SCENE]:
		node.ready.connect(_on_level_ready.bind(node), CONNECT_ONE_SHOT)
	else:
		_end_level()


func _on_level_ready(level: Node) -> void:
	if _run_slug.is_empty():
		return
	_level_active = true
	_pending_time = 0.0
	if _mode == RunRecorder.MODE_NORMAL:
		store.set_save(_run_slug, {
			"level": Game.current_level,
			"lives": Game.lives,
			"weapon_id": String(Game.weapon_id),
			"run_seed": Game.run_seed,
			"coins": Game.coins,
			"damage_bonus": Game.damage_bonus,
			"mode": _mode,
			"score": Game.score,
			"enemies_killed": Game.enemies_killed,
			"run_id": _run_id,
		})
	var player: Node = level.get_node("Player")
	player.died.connect(_on_player_died)
	level.get_node("ExitDoor").player_escaped.connect(_end_level)
	level.tree_exiting.connect(_end_level)


## Fin de un nivel (superado, cambio de escena): guarda el tiempo.
func _end_level() -> void:
	flush_time()
	_level_active = false


## Morir termina la partida y borra la partida guardada.
func _on_player_died() -> void:
	_end_level()
	if _mode == RunRecorder.MODE_NORMAL and not _run_slug.is_empty():
		store.clear_save(_run_slug)
	_run_slug = ""


## Volver al menú o cerrar la ventana: guarda el tiempo y cierra la partida.
## La partida guardada queda para "Continuar".
func _end_run() -> void:
	_end_level()
	_run_slug = ""
