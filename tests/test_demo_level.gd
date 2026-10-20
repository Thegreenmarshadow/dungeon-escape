@tool
extends McpTestSuite
## Pruebas de la demo: el mapa hecho a mano (salas, enemigos, armas, jefe), el
## orden obligatorio de las salas, el punto de control en lugar de Game Over,
## el cambio de arma, que no guarde puntajes y se registre con modo "demo", que
## salir de la demo deje Game como en una partida nueva y el botón del menú.
##
## Las pruebas de la escena necesitan los Autoload y que los scripts del nivel
## corran (no son @tool): fuera del editor, con el ejecutor sin cabeza.

const DEMO_SCENE := "res://scenes/DemoLevel.tscn"
const GAME_SCRIPT := "res://scripts/game.gd"
## Estado de Game que las pruebas tocan y dejan como estaba.
const GAME_STATE := [&"current_level", &"lives", &"enemies_killed", &"score", &"coins",
		&"damage_bonus", &"weapon_id", &"run_seed", &"test_mode", &"test_start_level", &"demo_mode"]
## Salas en el orden en que se recorren.
const ROOM_ORDER: Array[StringName] = [&"entrance", &"archers", &"mage", &"mimic", &"armory",
		&"antechamber", &"arena"]
## Escena de los enemigos de cada sala (sin el jefe).
const ROOM_ENEMIES := {
	&"entrance": ["Skeleton", "Skeleton"],
	&"archers": ["Archer"],
	&"mage": ["Mage"],
	&"mimic": ["Mimic"],
	&"antechamber": ["SkullTurret", "Vampire"],
}


## Destino de estadísticas que guarda lo que recibe.
class RecordingSink:
	extends StatsSink
	var runs: Array[Dictionary] = []
	var events: Array[Dictionary] = []

	func start_run(run: Dictionary) -> void:
		runs.append(run)

	func add_event(_run_id: String, event: Dictionary) -> void:
		events.append(event)


var _tree: SceneTree
var _saved_recorder: RefCounted
var _saved_game := {}
var _sink: RecordingSink


func suite_name() -> String:
	return "demo_level"


func setup() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_saved_recorder = null
	_sink = null
	var game := _tree.root.get_node_or_null("Game")
	_saved_game = {}
	if game != null:
		for property in GAME_STATE:
			_saved_game[property] = game.get(property)


func teardown() -> void:
	var tracker := _tree.root.get_node_or_null("RunTracker")
	if tracker != null and _saved_recorder != null:
		tracker.recorder = _saved_recorder
	var game := _tree.root.get_node_or_null("Game")
	for property in _saved_game:
		game.set(property, _saved_game[property])
	_tree.paused = false


# ----- mapa -----

func test_map_has_every_room_in_order() -> void:
	var map := DemoMap.create()
	var ids: Array[StringName] = []
	for room in map.rooms:
		ids.append(room.id)
		assert_false(room.hint.is_empty(), "%s tiene ayuda" % room.id)
		assert_true(room.hint.split(" ").size() <= 6, "ayuda corta: %s" % room.hint)
		assert_true(map.layout.is_floor(room.respawn_cell), "%s reaparece en el suelo" % room.id)
	assert_eq(ids, ROOM_ORDER)
	assert_eq(map.gates.size(), map.rooms.size() - 1, "una reja entre cada par de salas")
	# Las salas van de izquierda a derecha y el tema cambia a lava antes del jefe.
	for i in range(1, map.rooms.size()):
		assert_gt(map.rooms[i].rect.position.x, map.rooms[i - 1].rect.end.x)
	assert_eq(map.rooms[0].theme, DungeonTheme.DUNGEON)
	assert_eq(map.rooms[map.room_index(&"arena")].theme, DungeonTheme.LAVA)
	assert_eq(map.layout.boss.kind, BossRegistry.FORGE)
	assert_eq(map.room_at(map.layout.boss.cell), map.room_index(&"arena"))
	assert_eq(map.room_at(map.layout.player_cell), 0)


func test_room_order_is_enforced_by_the_gates() -> void:
	var map := DemoMap.create()
	for open_gates in map.gates.size() + 1:
		var expected: Array[int] = []
		for i in open_gates + 1:
			expected.append(i)
		assert_eq(map.reachable_rooms(open_gates), expected,
				"con %d rejas abiertas solo se llega hasta la sala %d" % [open_gates, open_gates])
	assert_false(map.room_index(&"arena") in map.reachable_rooms(map.gates.size() - 1),
			"al jefe solo se llega con todas las rejas abiertas")


func test_every_enemy_and_item_is_inside_a_room() -> void:
	var map := DemoMap.create()
	for spawn in map.layout.enemies:
		assert_true(map.room_at(spawn.cell) >= 0, "%s en %s está en una sala" % [spawn.kind, spawn.cell])
	var cells: Array[Vector2i] = []
	cells.append_array(map.heart_cells)
	cells.append_array(map.coin_cells)
	cells.append_array(map.weapon_cells.values())
	cells.append(map.checkpoint_cell)
	for cell in cells:
		assert_true(map.layout.is_floor(cell), "%s es suelo" % cell)
	assert_eq(map.room_at(map.checkpoint_cell), map.room_index(&"antechamber"),
			"el punto de control está justo antes del jefe")
	for cell in map.heart_cells:
		assert_true(map.room_at(cell) < map.room_index(&"arena"), "corazones antes del jefe")


# ----- escena -----

func test_scene_builds_rooms_enemies_pickups_and_boss() -> void:
	var demo := _make_demo()
	if demo == null:
		return
	var counts := {}
	for enemy in _tree.get_nodes_in_group("enemies"):
		if not demo.is_ancestor_of(enemy) or enemy is BossBase:
			continue
		var room: StringName = demo.demo_map.rooms[demo.demo_map.room_at(demo._cell_of(enemy.position))].id
		var kinds: Array = counts.get_or_add(room, [])
		kinds.append(RunRecorder.enemy_kind(enemy))
	for room in ROOM_ENEMIES:
		var kinds: Array = counts.get(room, [])
		kinds.sort()
		assert_eq(kinds, ROOM_ENEMIES[room], "enemigos de %s" % room)

	var boss := _tree.get_first_node_in_group(BossBase.GROUP) as BossBase
	assert_true(boss != null and demo.is_ancestor_of(boss), "está el jefe")
	assert_eq(boss.boss_id, BossRegistry.FORGE)
	assert_eq(boss.max_health, 12, "el Forjador con su vida base")
	assert_eq(demo.hud.boss_bar.boss, boss, "la barra del HUD sigue al jefe")

	var ids: Array = demo.weapon_pickups.map(func(p: WeaponPickup) -> StringName: return p.weapon_id)
	assert_eq(ids, [&"spear", &"dagger"])
	assert_eq(demo.gates.size(), 6)
	for gate in demo.gates:
		assert_false(gate.is_open(), "las rejas empiezan cerradas")
	assert_true(demo.checkpoint != null and not demo.checkpoint.is_active())
	var hearts := demo.get_node("DemoItems").get_children().filter(func(n: Node) -> bool: return n is Heart)
	assert_eq(hearts.size(), demo.demo_map.heart_cells.size())

	var lava_atlas := demo.lava_layer.tile_set.get_source(0) as TileSetAtlasSource
	assert_eq(lava_atlas.texture.resource_path, DungeonTheme.tileset_texture_path(DungeonTheme.LAVA))
	assert_gt(demo.lava_layer.get_used_cells().size(), 0)
	assert_eq(demo.player.lives, _game().DEMO_LIVES)
	assert_eq(demo.player.max_lives, _game().DEMO_LIVES)
	assert_eq(demo.hud.message_label.text, demo.demo_map.rooms[0].hint, "la primera ayuda")


func test_gate_opens_only_when_its_room_is_cleared() -> void:
	var demo := _make_demo()
	if demo == null:
		return
	var entrance: Array = demo._room_enemies[0].duplicate()
	entrance[0]._die()
	assert_false(demo.gates[0].is_open(), "queda un esqueleto")
	entrance[1]._die()
	assert_true(demo.gates[0].is_open(), "sala despejada")
	for i in range(1, demo.gates.size()):
		assert_false(demo.gates[i].is_open(), "la reja %d sigue cerrada" % i)
	# La armería no tiene enemigos: se abre al elegir un arma.
	var armory: int = demo.demo_map.room_index(&"armory")
	for room in range(1, armory):
		for enemy in demo._room_enemies[room].duplicate():
			enemy._die()
	assert_true(demo.gates[armory - 1].is_open())
	assert_false(demo.gates[armory].is_open(), "la armería espera un arma")
	demo.weapon_pickups[0].try_swap(demo.player)
	assert_true(demo.gates[armory].is_open())


func test_weapon_pickup_swaps_the_equipped_weapon() -> void:
	var demo := _make_demo()
	if demo == null:
		return
	var spear: WeaponPickup = demo.weapon_pickups[0]
	var dagger: WeaponPickup = demo.weapon_pickups[1]
	assert_eq(demo.player.weapon.id, WeaponData.STARTING_ID)
	assert_true(spear.try_swap(demo.player))
	assert_eq(demo.player.weapon.id, &"spear")
	assert_eq(_game().weapon_id, &"spear", "el arma de la demo")
	assert_eq(spear.weapon_id, WeaponData.STARTING_ID, "la espada queda en el suelo")
	assert_true(dagger.try_swap(demo.player))
	assert_eq(demo.player.weapon.id, &"dagger")
	assert_eq(dagger.weapon_id, &"spear")
	assert_eq(demo.hud.message_label.text, "¡Daga equipada!")
	assert_false(spear.try_swap(track(Node.new())), "solo el jugador")


func test_knock_out_respawns_at_the_checkpoint_instead_of_game_over() -> void:
	var demo := _make_demo()
	if demo == null:
		return
	var scores_before := _scores_file()
	var player: CharacterBody2D = demo.player
	var deaths := [0]
	player.died.connect(func() -> void: deaths[0] += 1)

	# Antes de la vela: vuelve a la entrada de la sala a la que llegó.
	demo.enter_room(2)
	var room_respawn: Vector2 = demo._cell_center(demo.demo_map.rooms[2].respawn_cell)
	assert_eq(demo.respawn_position, room_respawn)
	player.position = Vector2(700, 150)
	player.take_damage(player.lives)
	assert_eq(deaths[0], 0, "no muere: no hay Game Over")
	assert_false(demo.hud.game_over_screen.visible)
	demo.respawn_player()
	assert_eq(player.lives, _game().DEMO_LIVES, "vuelve con todas las vidas")
	assert_eq(_game().lives, _game().DEMO_LIVES)
	assert_eq(player.global_position, demo.to_global(room_respawn))
	assert_true(player.is_physics_processing(), "se puede mover")

	# Con la vela encendida, también desde la arena vuelve a la vela.
	demo.checkpoint.activate()
	demo.enter_room(demo.demo_map.room_index(&"arena"))
	var flag_respawn: Vector2 = demo._cell_center(demo.demo_map.checkpoint_cell + Vector2i(0, 1))
	assert_eq(demo.respawn_position, flag_respawn)
	player._invulnerable_left = 0.0
	player.take_damage(player.lives)
	demo.respawn_player()
	assert_eq(player.global_position, demo.to_global(flag_respawn))
	assert_eq(deaths[0], 0)
	assert_eq(demo.respawns, 2)
	assert_eq(_scores_file(), scores_before, "no se guarda ningún puntaje")


func test_escaping_shows_the_thank_you_screen() -> void:
	var demo := _make_demo()
	if demo == null:
		return
	var scores_before := _scores_file()
	demo.run_time = 332.0
	demo._on_player_escaped()
	var screen: DemoEndScreen = demo.end_screen()
	assert_true(screen != null and screen.is_inside_tree(), "pantalla final")
	assert_eq(screen.title_label.text, "¡Gracias por jugar!")
	assert_true(screen.stats_label.text.contains("5:32"), "muestra el tiempo")
	assert_true(_tree.paused, "el juego queda en pausa")
	assert_eq(screen.download_button.text, "Descargar el juego completo")
	assert_eq(_scores_file(), scores_before, "no se guarda ningún puntaje")


func test_demo_runs_are_recorded_with_mode_demo() -> void:
	var demo := _make_demo()
	if demo == null:
		return
	var tracker := _tree.root.get_node("RunTracker")
	assert_eq(tracker.current_mode(), RunRecorder.MODE_DEMO)
	tracker._on_run_started()
	assert_eq(_sink.runs.size(), 1)
	assert_eq(_sink.runs[0]["mode"], "demo")
	_game().demo_mode = false
	assert_eq(tracker.current_mode(), RunRecorder.MODE_NORMAL, "una partida normal sigue siendo normal")


func test_respawn_is_recorded_without_counting_a_heart() -> void:
	var sink := RecordingSink.new()
	var recorder := RunRecorder.new(sink)
	recorder.start_run("demo-run", "Ana", RunRecorder.MODE_DEMO, 1, 1)
	recorder.start_level(1, 5, 8)
	recorder.record_lives(0)
	recorder.record_respawn(5)
	recorder.record_lives(4)
	var types: Array = sink.events.map(func(e: Dictionary) -> String: return e["type"])
	assert_eq(types, ["level_started", "damage_taken", "player_respawned", "damage_taken"])
	assert_true(recorder.is_running(), "reaparecer no termina la partida")


# ----- Game -----

func test_leaving_the_demo_resets_the_game_state() -> void:
	var game := _make_game_stub()
	game.start_demo()
	assert_true(game.demo_mode)
	assert_eq(game.lives, game.DEMO_LIVES)
	assert_eq(game.current_level, 1)
	assert_eq(game.scenes, [game.DEMO_SCENE])
	game.weapon_id = &"spear"
	game.add_coins(12)
	game.lives = 2
	game.register_kill()
	game.go_to_menu()
	assert_false(game.demo_mode)
	assert_false(game.test_mode)
	assert_eq(game.lives, game.STARTING_LIVES)
	assert_eq(game.weapon_id, WeaponData.STARTING_ID)
	assert_eq(game.coins, 0)
	assert_eq(game.score, 0)
	assert_eq(game.enemies_killed, 0)


func test_retry_in_the_demo_restarts_the_demo() -> void:
	var game := _make_game_stub()
	game.start_demo()
	game.lives = 0
	game.retry()
	assert_true(game.demo_mode)
	assert_eq(game.lives, game.DEMO_LIVES)
	assert_eq(game.scenes, [game.DEMO_SCENE, game.DEMO_SCENE])


func test_a_normal_game_after_the_demo_is_not_a_demo() -> void:
	var game := _make_game_stub()
	game.start_demo()
	game.start_new_game()
	assert_false(game.demo_mode)
	assert_eq(game.lives, game.STARTING_LIVES)
	game.retry()
	assert_false(game.demo_mode, "reintentar una partida normal no vuelve a la demo")


# ----- menú y pantalla final -----



func test_end_screen_formats_minutes_and_seconds() -> void:
	assert_eq(DemoEndScreen.format_time(0.0), "0:00")
	assert_eq(DemoEndScreen.format_time(65.9), "1:05")
	assert_eq(DemoEndScreen.format_time(332.0), "5:32")


# ----- ayudas -----

## Demo en el árbol con las estadísticas desviadas a un destino que guarda lo
## que recibe y Game como al empezar la demo. null (y la prueba queda omitida)
## si no hay Autoload o si los scripts del nivel no corren (en el editor).
func _make_demo() -> Node2D:
	var tracker := _tree.root.get_node_or_null("RunTracker")
	var game := _tree.root.get_node_or_null("Game")
	if tracker == null or game == null:
		skip("necesita los Autoload Game y RunTracker")
		return null
	_sink = RecordingSink.new()
	_saved_recorder = tracker.recorder
	tracker.recorder = RunRecorder.new(_sink)
	game.new_game()
	game.demo_mode = true
	game.lives = game.DEMO_LIVES
	var demo: Node2D = track(load(DEMO_SCENE).instantiate())
	if not demo.has_method("enter_room"):
		skip("los scripts del nivel no corren en el editor")
		return null
	_tree.root.add_child(demo)
	return demo


## Copia de Game que anota las escenas en lugar de cambiar de escena.
func _make_game_stub() -> Node:
	var stub := GDScript.new()
	stub.source_code = "extends \"%s\"\n\nvar scenes: Array = []\n\n\nfunc _change_scene(path: String) -> void:\n\tscenes.append(path)\n" % GAME_SCRIPT
	stub.reload()
	return track(stub.new())


func _game() -> Node:
	return _tree.root.get_node("Game")


func _scores_file() -> String:
	if not FileAccess.file_exists(ScoreBoard.DEFAULT_PATH):
		return ""
	return FileAccess.get_file_as_string(ScoreBoard.DEFAULT_PATH)
