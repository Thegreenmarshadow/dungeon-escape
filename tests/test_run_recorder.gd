@tool
extends McpTestSuite
## Pruebas de RunRecorder: qué eventos y qué resumen produce cada momento de
## una partida. Usa un destino que solo anota (RecordingSink), sin red. También
## cubre el nombre del jugador (PlayerProfile y el perfil elegido con el que
## RunTracker empieza la partida) y la lectura de la tabla en línea
## (OnlineLeaderboard.parse_response).

const RUN_ID := "0123456789abcdef0123456789abcdef"
const TEMP_DIR := "user://test_run_recorder"
const RUN_TRACKER_SCRIPT := "res://scripts/stats/run_tracker.gd"


## Destino falso: guarda todo lo que recibe.
class RecordingSink:
	extends StatsSink
	var runs: Array[Dictionary] = []
	var events: Array[Dictionary] = []
	var summaries: Array[Dictionary] = []

	func start_run(run: Dictionary) -> void:
		runs.append(run)

	func add_event(run_id: String, event: Dictionary) -> void:
		event["run_id"] = run_id
		events.append(event)

	func finish_run(run_id: String, summary: Dictionary) -> void:
		summary["run_id"] = run_id
		summaries.append(summary)

	func types() -> Array:
		var out := []
		for event in events:
			out.append(event["type"])
		return out


var _sink: RecordingSink
var _recorder: RunRecorder
# Autoload Profiles y su ProfileStore real, para devolverlo en teardown.
var _profiles: Node
var _previous_store: ProfileStore


func suite_name() -> String:
	return "run_recorder"


func setup() -> void:
	_sink = track(RecordingSink.new())
	_recorder = RunRecorder.new(_sink)


func teardown() -> void:
	if _profiles != null:
		_profiles.store = _previous_store
		_profiles = null
		_previous_store = null
	JsonFile.remove_tree(TEMP_DIR)


func test_start_run_sends_the_run_data() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_TEST, 77, 5)
	assert_true(_recorder.is_running())
	assert_eq(_sink.runs.size(), 1)
	var run := _sink.runs[0]
	assert_eq(run["id"], RUN_ID)
	assert_eq(run["player_name"], "Ana")
	assert_eq(run["mode"], "test")
	assert_eq(run["run_seed"], 77)
	assert_eq(run["start_level"], 5)
	assert_true(String(run["started_at"]).ends_with("Z"), "la fecha debe ser UTC")


func test_a_full_level_produces_events_in_order() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 1)
	_recorder.start_level(1, 3, 4)
	_recorder.advance(2.0)
	_recorder.record_kill("Skeleton", 1, 10)
	_recorder.record_lives(2, "Skeleton")
	_recorder.advance(1.0)
	_recorder.record_lives(3)
	_recorder.record_key()
	_recorder.record_weapon("spear")
	_recorder.advance(0.5)
	_recorder.complete_level(110)

	assert_eq(_sink.types(), [
		"level_started", "enemy_killed", "damage_taken", "heart_picked", "key_picked",
		"weapon_changed", "level_completed"])
	var seqs := []
	for event in _sink.events:
		seqs.append(event["seq"])
		assert_eq(event["run_id"], RUN_ID)
		assert_eq(event["level"], 1)
	assert_eq(seqs, [0, 1, 2, 3, 4, 5, 6])
	assert_eq(_sink.events[0]["payload"], {"lives": 3, "enemies_total": 4})
	assert_eq(_sink.events[1]["payload"], {"enemy": "Skeleton"})
	assert_eq(_sink.events[1]["t_run_s"], 2.0)
	assert_eq(_sink.events[2]["payload"], {"amount": 1, "lives": 2, "source": "Skeleton"})
	assert_eq(_sink.events[3]["payload"], {"amount": 1, "lives": 3})
	assert_eq(_sink.events[5]["payload"], {"weapon": "spear"})
	var completed: Dictionary = _sink.events[6]["payload"]
	assert_eq(completed["duration_s"], 3.5)
	assert_eq(completed["kills"], 1)
	assert_eq(completed["enemies_total"], 4)
	assert_eq(completed["score"], 110)
	assert_false(_recorder.is_level_active())
	assert_true(_recorder.is_running(), "superar un nivel no termina la partida")


func test_death_ends_the_run_with_its_totals() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 1)
	_recorder.start_level(1, 3, 2)
	_recorder.advance(4.0)
	_recorder.complete_level(100)
	_recorder.advance(9.0)  # Entre niveles (pantalla de nivel superado) no cuenta.
	_recorder.start_level(2, 3, 5)
	_recorder.advance(6.0)
	_recorder.record_kill("Vampire", 1, 110)
	_recorder.record_lives(0, "spikes")
	_recorder.record_death(110, 1, "spikes")

	assert_eq(_sink.types().slice(-2), ["damage_taken", "player_died"])
	assert_eq(_sink.events[-1]["payload"], {"score": 110, "cause": "spikes"})
	assert_eq(_sink.events[-1]["level"], 2)
	assert_eq(_sink.summaries.size(), 1)
	var summary := _sink.summaries[0]
	assert_eq(summary["run_id"], RUN_ID)
	assert_eq(summary["outcome"], "died")
	assert_eq(summary["score"], 110)
	assert_eq(summary["enemies_killed"], 1)
	assert_eq(summary["level_reached"], 2)
	assert_eq(summary["duration_s"], 10.0)
	assert_false(_recorder.is_running())


func test_quit_uses_the_given_totals_and_adds_a_quit_event() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 3)
	_recorder.start_level(3, 2, 6)
	_recorder.finish_run(RunRecorder.OUTCOME_QUIT, 40, 4)

	assert_eq(_sink.types()[-1], "run_quit")
	assert_eq(_sink.events[-1]["payload"], {"score": 40})
	var summary := _sink.summaries[0]
	assert_eq(summary["outcome"], "quit")
	assert_eq(summary["score"], 40)
	assert_eq(summary["enemies_killed"], 4)
	assert_eq(summary["level_reached"], 3)


func test_starting_a_run_while_another_is_running_closes_the_old_one() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 1)
	_recorder.start_level(1, 3, 2)
	_recorder.record_kill("Skeleton", 1, 10)
	_recorder.start_run("ffffffffffffffff", "Ana", RunRecorder.MODE_NORMAL, 2, 1)

	assert_eq(_sink.summaries.size(), 1)
	assert_eq(_sink.summaries[0]["run_id"], RUN_ID)
	assert_eq(_sink.summaries[0]["outcome"], "quit")
	assert_eq(_sink.summaries[0]["score"], 10, "usa los últimos totales conocidos")
	assert_eq(_recorder.run_id, "ffffffffffffffff")


func test_nothing_is_sent_without_a_run_or_outside_a_level() -> void:
	_recorder.start_level(1, 3, 2)
	_recorder.record_kill("Skeleton", 1, 10)
	_recorder.finish_run(RunRecorder.OUTCOME_QUIT)
	assert_true(_sink.events.is_empty())
	assert_true(_sink.summaries.is_empty())

	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 1)
	_recorder.record_key()
	_recorder.record_lives(1)
	_recorder.record_death(0, 0)
	assert_true(_sink.events.is_empty(), "sin nivel activo no hay eventos")
	assert_true(_recorder.is_running())


func test_unchanged_lives_produce_no_event() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 1)
	_recorder.start_level(1, 3, 0)
	_recorder.record_lives(3)
	assert_eq(_sink.types(), ["level_started"])


func test_coins_picked_in_a_level_are_recorded() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 1)
	_recorder.start_level(1, 3, 2)
	_recorder.record_coins(2)
	_recorder.record_coins(0)
	assert_eq(_sink.types(), ["level_started", "coin_picked"], "cero monedas no es un evento")
	assert_eq(_sink.events[1]["payload"], {"amount": 2})
	_recorder.complete_level(100)
	_recorder.record_coins(1)
	assert_eq(_sink.types()[-1], "level_completed", "fuera de un nivel no se registran monedas")


func test_enemy_dodges_in_a_level_are_recorded() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 1)
	_recorder.record_dodge("Skeleton")
	assert_true(_sink.events.is_empty(), "antes del nivel no se registran esquivas")
	_recorder.start_level(1, 3, 2)
	_recorder.record_dodge("Skeleton")
	assert_eq(_sink.types(), ["level_started", "enemy_dodged"])
	assert_eq(_sink.events[1]["type"], RunRecorder.EVENT_ENEMY_DODGED)
	assert_eq(_sink.events[1]["payload"], {"enemy": "Skeleton"})
	assert_eq(_sink.events[1]["level"], 1)
	_recorder.complete_level(100)
	_recorder.record_dodge("Vampire")
	assert_eq(_sink.types()[-1], "level_completed", "fuera de un nivel no se registran esquivas")


func test_purchases_between_levels_are_recorded_with_the_completed_level() -> void:
	_recorder.start_run(RUN_ID, "Ana", RunRecorder.MODE_NORMAL, 1, 2)
	_recorder.start_level(2, 3, 4)
	_recorder.complete_level(100)
	_recorder.record_purchase("damage", 10)
	_recorder.record_purchase("life", 6)
	assert_eq(_sink.types().slice(-2), ["item_bought", "item_bought"])
	assert_eq(_sink.events[-2]["payload"], {"item": "damage", "price": 10})
	assert_eq(_sink.events[-1]["payload"], {"item": "life", "price": 6})
	assert_eq(_sink.events[-1]["level"], 2)


func test_purchases_without_a_run_are_ignored() -> void:
	_recorder.record_purchase("damage", 10)
	assert_true(_sink.events.is_empty())


func test_enemy_kind_comes_from_the_scene_file() -> void:
	var from_scene: Node = track(load("res://scenes/Skeleton.tscn").instantiate())
	assert_eq(RunRecorder.enemy_kind(from_scene), "Skeleton")
	var plain: Node = track(Node.new())
	plain.name = "Boss"
	assert_eq(RunRecorder.enemy_kind(plain), "Boss")


func test_new_run_ids_are_unique_hex() -> void:
	var a := RunRecorder.new_run_id()
	var b := RunRecorder.new_run_id()
	assert_eq(a.length(), 32)
	assert_true(a.is_valid_hex_number(), "debe ser hexadecimal")
	assert_ne(a, b)


func test_player_name_is_sanitized_and_persisted() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var path := TEMP_DIR.path_join("player.cfg")
	assert_eq(PlayerProfile.load_name(path), PlayerProfile.DEFAULT_NAME, "sin archivo da el nombre por defecto")
	assert_eq(PlayerProfile.save_name("  Ana\t ", path), "Ana")
	assert_eq(PlayerProfile.load_name(path), "Ana")
	assert_eq(PlayerProfile.sanitize("   "), PlayerProfile.DEFAULT_NAME)
	assert_eq(PlayerProfile.sanitize("x".repeat(40)).length(), PlayerProfile.MAX_NAME_LENGTH)
	assert_eq(PlayerProfile.sanitize("Iñaki Núñez"), "Iñaki Núñez")


func test_current_name_is_the_selected_profile() -> void:
	var store := ProfileStore.new(TEMP_DIR.path_join("profiles"))
	var ana := store.create_profile("  Ana  ")
	var long_name := store.create_profile("x".repeat(40))
	store.select_profile(ana["slug"])
	assert_eq(PlayerProfile.current_name(store.base_dir), "Ana")
	store.select_profile(long_name["slug"])
	assert_eq(PlayerProfile.current_name(store.base_dir).length(), PlayerProfile.MAX_NAME_LENGTH,
			"entra en el player_name del servidor (32 como máximo)")


func test_run_tracker_starts_the_run_with_the_selected_profile_name() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var profiles := root.get_node_or_null("Profiles")
	if profiles == null or root.get_node_or_null("Game") == null:
		skip("necesita los Autoload Profiles y Game")
		return
	_profiles = profiles
	_previous_store = profiles.store
	_profiles.store = ProfileStore.new(TEMP_DIR.path_join("profiles"))
	_profiles.store.create_profile("Ana")
	var beto: Dictionary = _profiles.store.create_profile("Beto")
	_profiles.store.select_profile(beto["slug"])

	var tracker: Node = track(load(RUN_TRACKER_SCRIPT).new())
	tracker.recorder = _recorder
	tracker._on_run_started()
	assert_eq(_sink.runs.size(), 1)
	assert_eq(_sink.runs[0]["player_name"], "Beto", "el perfil elegido, no el primero ni player.cfg")


func test_online_leaderboard_parses_valid_responses_only() -> void:
	var body := JSON.stringify({"best_level": 4, "entries": [
		{"rank": 1, "player_name": "Ana", "score": 300, "level_reached": 4, "ended_at": "2026-10-16T12:00:00Z"},
	]}).to_utf8_buffer()
	var board: Variant = OnlineLeaderboard.parse_response(HTTPRequest.RESULT_SUCCESS, 200, body)
	assert_eq(board["best_level"], 4)
	assert_eq(board["entries"], [{"name": "Ana", "score": 300, "level": 4, "date": "2026-10-16T12:00:00Z"}])

	var ok := HTTPRequest.RESULT_SUCCESS
	assert_eq(OnlineLeaderboard.parse_response(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedByteArray()), null)
	assert_eq(OnlineLeaderboard.parse_response(ok, 500, body), null)
	assert_eq(OnlineLeaderboard.parse_response(ok, 200, "no es json".to_utf8_buffer()), null)
	var bad_entry := JSON.stringify({"entries": [{"player_name": 3}]}).to_utf8_buffer()
	assert_eq(OnlineLeaderboard.parse_response(ok, 200, bad_entry), null)
