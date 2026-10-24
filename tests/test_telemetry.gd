@tool
extends McpTestSuite
## Pruebas de la telemetría: Telemetry registra lo que hace un jugador real
## (PlayerRig) con su posición y lo escribe al morir, y anota cada nivel
## terminado para subirlo a su partida del servidor (LevelUploader);
## TelemetryStore lee archivos viejos o incompletos con valores por defecto.
## Todo en una carpeta temporal de user://, que se borra al terminar. La
## instancia de Telemetry es propia de la prueba (no el Autoload) y no entra al
## árbol.

const TEMP_DIR := "user://test_telemetry"
const TELEMETRY_SCRIPT := "res://scripts/telemetry/telemetry.gd"
const PLAYER_RIG := preload("res://tests/player_rig.gd")
## Partida del servidor de estadísticas (la de RunTracker).
const STATS_RUN := "0123456789abcdef0123456789abcdef"


func suite_name() -> String:
	return "telemetry"


func setup() -> void:
	JsonFile.remove_tree(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)


func teardown() -> void:
	JsonFile.remove_tree(TEMP_DIR)


func test_records_player_events_with_position_and_writes_on_death() -> void:
	var telemetry := _make_telemetry()
	var level := _make_level()
	var player: CharacterBody2D = PLAYER_RIG.make_player()
	player.position = Vector2(40, 40)
	level.add_child(player)
	var door := Node.new()
	door.add_user_signal("player_escaped")
	door.add_user_signal("locked_touched")
	level.add_child(door)
	var enemy := Node2D.new()
	enemy.name = "Skeleton"
	enemy.add_user_signal("died", [{"name": "enemy", "type": TYPE_OBJECT}])
	enemy.position = Vector2(80, 24)
	level.add_child(enemy)

	telemetry.begin_run("run-1", "normal", "Ana", "ana", 77)
	assert_true(telemetry.attach_level(level, player, door, [enemy], _small_map(), 2, 1234))
	assert_true(telemetry.is_recording())

	# Recorrido: se muestrea al moverse más de 8 px o cada 0,25 s.
	player.position = Vector2(44, 40)
	telemetry._process(0.1)
	assert_eq(telemetry.current_path().size(), 1, "4 px en 0,1 s no muestrea")
	player.position = Vector2(60, 40)
	telemetry._process(0.1)
	telemetry._process(0.3)
	assert_eq(telemetry.current_path().size(), 3, "por distancia y por tiempo")

	# Medios corazones en el juego, corazones en el archivo: 3 medios = 1.5.
	player.take_damage(3, Vector2(30, 40), &"Skeleton")
	player.heal(2)
	player.collect_key()
	player._try_attack()
	for i in 4:
		player._update_attack(1.0)
	player.equip_weapon(WeaponData.load_by_id(&"spear"))
	enemy.emit_signal("died", enemy)
	door.emit_signal("locked_touched")
	player._invulnerable_left = 0.0
	player.take_damage(9, Vector2.INF, &"spikes")

	assert_false(telemetry.is_recording(), "morir termina el nivel")
	var data: Dictionary = telemetry.last_level_data
	var types: Array = data["events"].map(func(e: Dictionary) -> String: return e["type"])
	assert_eq(types, ["damage", "heart", "key", "attack", "weapon_changed", "enemy_killed",
			"door", "damage", "death"])
	var events: Array = data["events"]
	assert_eq(events[0]["source"], "Skeleton")
	assert_eq(events[0]["amount"], 1.5)
	assert_eq(events[1]["amount"], 1.0, "el corazón curó uno entero")
	assert_eq([events[0]["x"], events[0]["y"]], [60.0, 40.0], "donde estaba el jugador")
	assert_eq(events[3]["hit"], false)
	assert_eq(events[5]["enemy"], "Skeleton")
	assert_eq([events[5]["x"], events[5]["y"]], [80.0, 24.0], "donde murió el enemigo")
	assert_eq(events[6]["state"], "locked")
	assert_eq(events[8]["cause"], "spikes")
	assert_eq(data["outcome"], "died")
	assert_eq(data["weapons_used"], ["sword", "spear"])
	assert_eq(data["level"], 2)
	assert_eq(data["level_seed"], "1234")
	assert_true(absf(data["difficulty_index"] - DifficultyCurve.index_for_level(2)) < 0.001,
			"índice planificado del nivel generado")

	var path := TEMP_DIR.path_join("ana/runs/run-1/level_2.json")
	assert_eq(telemetry.last_level_file, path)
	var store := TelemetryStore.new(TEMP_DIR)
	var loaded := store.load_levels({"profile": "Ana", "level": 2, "mode": "normal"})
	assert_eq(loaded.size(), 1)
	assert_eq(loaded[0]["events"].size(), 9)
	assert_eq(loaded[0]["seed"], 77)
	assert_eq(typeof(loaded[0]["events"][0]["amount"]), TYPE_FLOAT, "en corazones, puede tener medio")
	assert_eq(loaded[0]["events"][0]["amount"], 1.5)
	assert_true(store.load_levels({"level": 3}).is_empty(), "el filtro de nivel descarta")
	var floor_cells := TelemetryStore.decode_floor(loaded[0]["map"])
	assert_eq(floor_cells, _small_layout().floor_cells, "el mapa vuelve igual")


func test_level_file_missing_fields_loads_with_defaults() -> void:
	var path := TEMP_DIR.path_join("viejo.json")
	JsonFile.write(path, {
		"level": 3,
		"path": [[1.5, 20, 30], "roto", [2]],
		"events": [{"type": "damage", "amount": 2.0}, {"sin": "tipo"}],
		"map": {"size": [2, 2], "floor": "1,2,1"},
		"extra": "se conserva",
	})
	var data := TelemetryStore.load_level_file(path)
	assert_eq(data["level"], 3)
	assert_eq(data["schema_version"], TelemetryStore.SCHEMA_VERSION)
	assert_eq(data["mode"], "normal")
	assert_eq(data["outcome"], "abandoned")
	assert_eq(data["weapons_used"], [])
	assert_eq(data["level_seed"], null)
	assert_eq(data["difficulty_index"], null, "los archivos viejos no lo tienen")
	assert_eq(data["path"], [[1.5, 20.0, 30.0]], "descarta los puntos malformados")
	assert_eq(data["events"].size(), 1)
	assert_eq(data["events"][0]["amount"], 2.0, "un archivo viejo en corazones enteros se lee igual")
	assert_eq(typeof(data["events"][0]["amount"]), TYPE_FLOAT)
	assert_eq(data["events"][0]["t"], 0.0)
	assert_eq(data["map"]["cell_px"], 16)
	assert_eq(data["map"]["door"], null)
	assert_eq(data["extra"], "se conserva")
	assert_eq(TelemetryStore.decode_floor(data["map"]), PackedByteArray([0, 1, 1, 0]))
	assert_eq(TelemetryStore.world_to_cell(data["map"], Vector2(20, 30)), Vector2i(1, 1))
	assert_eq(TelemetryStore.cell_to_world(data["map"], Vector2i(1, 1)), Vector2(24, 24))

	var broken := TEMP_DIR.path_join("roto.json")
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string("{no es json")
	file.close()
	assert_true(TelemetryStore.load_level_file(broken).is_empty(), "un archivo dañado no rompe nada")


func test_turned_off_records_nothing() -> void:
	var telemetry := _make_telemetry()
	GameSettings.set_telemetry_enabled(false, telemetry.settings_path)
	var level := _make_level()
	var player: CharacterBody2D = PLAYER_RIG.make_player()
	level.add_child(player)
	telemetry.begin_run("run-2", "normal", "Ana", "ana", 1)
	assert_false(telemetry.attach_level(level, player, null, [], _small_map(), 1))
	assert_false(telemetry.is_recording())
	assert_true(telemetry.current_path().is_empty())
	assert_true(TelemetryStore.new(TEMP_DIR).all_level_files().is_empty())


func test_finished_level_is_queued_for_upload_to_its_stats_run() -> void:
	var telemetry := _make_telemetry()
	var stats := StatsQueue.new()
	stats.push(StatsQueue.KIND_RUN_STARTED, STATS_RUN, {"id": STATS_RUN})
	var uploader := _make_uploader(telemetry, stats)
	var level := _make_level()
	var player: CharacterBody2D = PLAYER_RIG.make_player()
	level.add_child(player)
	telemetry.begin_run("run-3", "normal", "Ana", "ana", 5)
	telemetry.stats_run_id = STATS_RUN
	assert_true(telemetry.attach_level(level, player, null, [], _small_map(), 1))
	telemetry.finish_level(TelemetryRecorder.OUTCOME_COMPLETED)

	assert_eq(uploader.pending.size(), 1)
	var item: Dictionary = uploader.pending.items[0]
	assert_eq(item["file"], telemetry.last_level_file)
	assert_eq(item["run_id"], STATS_RUN, "la partida del servidor, no Game.run_id")
	assert_eq([item["level"], item["attempt"]], [1, 1])
	assert_false(uploader.is_uploading(), "espera a que el servidor tenga la partida")
	assert_eq(telemetry.stats_run_id, "", "cada nivel toma su propia partida")

	var next_level := _make_level()
	var next_player: CharacterBody2D = PLAYER_RIG.make_player()
	next_level.add_child(next_player)
	assert_true(telemetry.attach_level(next_level, next_player, null, [], _small_map(), 2))
	telemetry.finish_level(TelemetryRecorder.OUTCOME_ABANDONED)
	assert_eq(uploader.pending.size(), 1, "sin partida del servidor no se anota")


# ----- ayudas -----

func _make_telemetry() -> Node:
	var telemetry: Node = track(load(TELEMETRY_SCRIPT).new())
	telemetry.base_dir = TEMP_DIR
	telemetry.settings_path = TEMP_DIR.path_join("settings.cfg")
	return telemetry


## LevelUploader de telemetry en el árbol, con su lista en TEMP_DIR y un
## servidor que no existe. stats es la cola de eventos de RunTracker.
func _make_uploader(telemetry: Node, stats: StatsQueue) -> LevelUploader:
	var uploader := LevelUploader.new()
	uploader.base_url = "http://127.0.0.1:1"
	uploader.pending_path = TEMP_DIR.path_join("level_uploads.json")
	uploader.settings_path = telemetry.settings_path
	uploader.stats_queue = stats
	track(uploader)
	(Engine.get_main_loop() as SceneTree).root.add_child(uploader)
	telemetry.uploader = uploader
	return uploader


## Nivel falso en la raíz del árbol, rastreado (se libera con todo adentro).
func _make_level() -> Node2D:
	var level := Node2D.new()
	level.name = "FakeLevel"
	track(level)
	(Engine.get_main_loop() as SceneTree).root.add_child(level)
	return level


func _small_layout() -> LevelGenerator.Layout:
	var layout := LevelGenerator.Layout.new(Vector2i(6, 4))
	layout.carve_rect(Rect2i(1, 1, 4, 2))
	layout.player_cell = Vector2i(2, 2)
	layout.key_cell = Vector2i(4, 1)
	layout.door_cell = Vector2i(1, 1)
	return layout


func _small_map() -> Dictionary:
	return LevelSnapshot.from_layout(_small_layout())
