@tool
extends McpTestSuite
## Pruebas de la zona de pruebas: que liste todas las armas y enemigos, que
## equipar y hacer aparecer funcione, y que nada de lo que pase ahí cambie la
## partida (Game), las estadísticas (RunTracker) ni los puntajes guardados.
##
## Las pruebas de la escena necesitan los Autoload y que sandbox.gd corra (no
## es @tool): fuera del editor, con el ejecutor de pruebas sin cabeza.

const SANDBOX_SCENE := "res://scenes/Sandbox.tscn"
const WEAPONS_DIR := "res://assets/weapons"
const EXPECTED_WEAPON_COUNT := 21
## Estado de la partida que la zona de pruebas no debe tocar.
const GAME_STATE := [&"current_level", &"lives", &"enemies_killed", &"score", &"coins",
		&"damage_bonus", &"weapon_id", &"run_seed", &"test_mode"]


## Destino de estadísticas que solo cuenta lo que recibe.
class RecordingSink:
	extends StatsSink
	var calls := 0

	func start_run(_run: Dictionary) -> void:
		calls += 1

	func add_event(_run_id: String, _event: Dictionary) -> void:
		calls += 1

	func finish_run(_run_id: String, _summary: Dictionary) -> void:
		calls += 1


var _tree: SceneTree
var _saved_recorder: RefCounted
var _sink: RecordingSink


func suite_name() -> String:
	return "sandbox"


func setup() -> void:
	_tree = Engine.get_main_loop() as SceneTree
	_saved_recorder = null
	_sink = null


func teardown() -> void:
	var tracker := _tree.root.get_node_or_null("RunTracker")
	if tracker != null and _saved_recorder != null:
		tracker.recorder = _saved_recorder
	Engine.time_scale = 1.0


# ----- catálogo -----

func test_weapon_list_loads_every_weapon_folder() -> void:
	var weapons := SandboxCatalog.load_weapons()
	assert_eq(weapons.size(), EXPECTED_WEAPON_COUNT, "las 21 armas")
	assert_eq(weapons.size(), DirAccess.get_directories_at(WEAPONS_DIR).size(), "una por carpeta")
	var ids: Array[StringName] = []
	for weapon in weapons:
		assert_true(weapon != null, "cada arma carga")
		assert_true(weapon.icon != null, "%s tiene ícono" % weapon.id)
		assert_false(weapon.display_name.is_empty(), "%s tiene nombre" % weapon.id)
		ids.append(weapon.id)
	for dir_name in DirAccess.get_directories_at(WEAPONS_DIR):
		assert_contains(ids, StringName(dir_name))


func test_full_mechanics_weapons_come_first_and_are_marked() -> void:
	var ids := SandboxCatalog.weapon_ids()
	assert_eq(ids.slice(0, 3), [&"sword", &"dagger", &"spear"])
	for id in [&"sword", &"dagger", &"spear"]:
		assert_true(SandboxCatalog.has_full_mechanics(id), "%s está completa" % id)
	for id in [&"axe", &"boomerang", &"shield"]:
		assert_false(SandboxCatalog.has_full_mechanics(id), "%s solo usa los stats base" % id)


func test_enemy_scenes_exist_and_instantiate() -> void:
	var entries := SandboxCatalog.enemy_entries()
	assert_true(entries.size() >= 8, "todos los enemigos del juego")
	var ids: Array = []
	for entry in entries:
		assert_false(entry["id"] in ids, "id repetido: %s" % entry["id"])
		ids.append(entry["id"])
		assert_false(String(entry["name"]).is_empty())
		assert_true(ResourceLoader.exists(entry["scene"]), "existe %s" % entry["scene"])
		var scene: PackedScene = load(entry["scene"])
		var enemy: Node = track(scene.instantiate())
		assert_true(enemy is EnemyBase, "%s es un enemigo" % entry["id"])


func test_every_level_enemy_is_in_the_list() -> void:
	var ids: Array = SandboxCatalog.enemy_entries().map(func(entry: Dictionary) -> StringName: return entry["id"])
	for kind in LevelBuilder.ENEMY_SCENES:
		assert_contains(ids, kind, "falta %s en la zona de pruebas" % kind)


func test_only_available_bosses_are_listed() -> void:
	var ids: Array = SandboxCatalog.enemy_entries().map(func(entry: Dictionary) -> StringName: return entry["id"])
	for boss_id in BossRegistry.SCENES:
		if BossRegistry.is_available(boss_id):
			assert_contains(ids, boss_id, "falta el jefe %s" % boss_id)
		else:
			assert_false(boss_id in ids, "%s todavía no tiene escena" % boss_id)


# ----- escena -----

func test_equipping_does_not_change_the_run_weapon() -> void:
	var sandbox := _make_sandbox()
	if sandbox == null:
		return
	var before := _game_state()
	for id in [&"axe", &"dagger", &"crossbow"]:
		assert_true(sandbox.equip_weapon_id(id))
		assert_eq(sandbox.player.weapon.id, id, "el jugador de la zona de pruebas la tiene")
	assert_false(sandbox.equip_weapon_id(&"no_existe"))
	assert_eq(_game_state(), before, "Game.weapon_id y el resto de la partida no cambian")


func test_spawning_and_killing_records_nothing() -> void:
	var sandbox := _make_sandbox()
	if sandbox == null:
		return
	var scores_before := _scores_file()
	var before := _game_state()
	for i in sandbox.enemies.size():
		var enemy: Node2D = sandbox.spawn_enemy(i)
		assert_true(enemy != null and enemy.is_inside_tree(), "aparece %s" % sandbox.enemies[i]["id"])
	assert_eq(sandbox.alive_enemy_count(), sandbox.enemies.size())
	assert_true(sandbox.spawn_enemy(sandbox.enemies.size()) == null, "un índice inválido no hace nada")
	sandbox.kill_all_enemies()
	assert_eq(sandbox.alive_enemy_count(), 0, "matar todos")
	sandbox.player.take_damage(1, Vector2.ZERO)
	assert_eq(_game_state(), before, "ni puntos, ni muertes, ni monedas, ni vidas")
	assert_eq(_sink.calls, 0, "no se envía nada a las estadísticas")
	assert_false(_tree.root.get_node("RunTracker").recorder.is_running(), "no empieza ninguna partida")
	assert_eq(_scores_file(), scores_before, "no se guarda ningún puntaje")


func test_clear_removes_everything_spawned() -> void:
	var sandbox := _make_sandbox()
	if sandbox == null:
		return
	sandbox.spawn_enemy(0)
	sandbox.spawn_enemy(0)
	sandbox.clear_spawned()
	assert_eq(sandbox.spawned.get_child_count(), 0)
	assert_eq(sandbox.alive_enemy_count(), 0)


func test_frozen_enemies_stop_moving() -> void:
	var sandbox := _make_sandbox()
	if sandbox == null:
		return
	var before: Node2D = sandbox.spawn_enemy(1)
	sandbox.set_enemies_frozen(true)
	var after: Node2D = sandbox.spawn_enemy(1)
	assert_false(before.is_physics_processing(), "los que ya estaban se quedan quietos")
	assert_false(after.is_physics_processing(), "y los nuevos aparecen quietos")
	sandbox.set_enemies_frozen(false)
	assert_true(before.is_physics_processing())


func test_player_is_invincible_and_never_dies() -> void:
	var sandbox := _make_sandbox()
	if sandbox == null:
		return
	var player: CharacterBody2D = sandbox.player
	sandbox.invincible_check.button_pressed = true
	player.take_damage(1, Vector2.ZERO)
	assert_eq(player.lives, player.max_lives, "invencible no pierde vidas")
	sandbox.invincible_check.button_pressed = false
	player._invulnerable_left = 0.0
	player.take_damage(player.lives, Vector2.ZERO)
	assert_eq(player.lives, player.max_lives, "al quedarse sin vidas las recupera")
	assert_true(player.is_physics_processing(), "y se puede seguir moviendo")


func test_slow_motion_and_hitboxes_are_restored_on_exit() -> void:
	var sandbox := _make_sandbox()
	if sandbox == null:
		return
	var hint_before := _tree.debug_collisions_hint
	sandbox.set_slow_motion(true)
	sandbox.set_hitboxes_visible(true)
	assert_eq(Engine.time_scale, 0.25)
	assert_true(_tree.debug_collisions_hint)
	_tree.root.remove_child(sandbox)
	assert_eq(Engine.time_scale, 1.0, "al salir el juego vuelve a velocidad normal")
	assert_eq(_tree.debug_collisions_hint, hint_before, "y la vista de colisiones como estaba")


func test_theme_changes_the_arena_tileset() -> void:
	var sandbox := _make_sandbox()
	if sandbox == null:
		return
	var original: TileSet = sandbox.dungeon.tile_set
	sandbox.set_theme(DungeonTheme.LAVA)
	assert_ne(sandbox.dungeon.tile_set, original)
	var atlas := sandbox.dungeon.tile_set.get_source(0) as TileSetAtlasSource
	assert_eq(atlas.texture.resource_path, DungeonTheme.tileset_texture_path(DungeonTheme.LAVA))
	sandbox.set_theme(DungeonTheme.DUNGEON)
	assert_eq(sandbox.dungeon.tile_set, original, "el original es el tileset de siempre")


func test_arena_is_closed_by_walls() -> void:
	var sandbox := _make_sandbox()
	if sandbox == null:
		return
	var dungeon: TileMapLayer = sandbox.dungeon
	var size: Vector2i = sandbox.ARENA_SIZE
	for x in size.x:
		for y in [0, size.y - 1]:
			assert_ne(dungeon.get_cell_atlas_coords(Vector2i(x, y)), LevelBuilder.FLOOR_TILE)
			assert_ne(dungeon.get_cell_source_id(Vector2i(x, y)), -1, "borde con pared")
	for y in size.y:
		for x in [0, size.x - 1]:
			assert_ne(dungeon.get_cell_atlas_coords(Vector2i(x, y)), LevelBuilder.FLOOR_TILE)
			assert_ne(dungeon.get_cell_source_id(Vector2i(x, y)), -1, "borde con pared")


# ----- ayudas -----

## Zona de pruebas en el árbol, con las estadísticas desviadas a un destino que
## solo cuenta. null (y la prueba queda omitida) si no hay Autoload o si el
## script de la escena no corre (en el editor).
func _make_sandbox() -> Node2D:
	var tracker := _tree.root.get_node_or_null("RunTracker")
	if tracker == null or _tree.root.get_node_or_null("Game") == null:
		skip("necesita los Autoload Game y RunTracker")
		return null
	_sink = track(RecordingSink.new())
	_saved_recorder = tracker.recorder
	tracker.recorder = RunRecorder.new(_sink)
	var sandbox: Node2D = track(load(SANDBOX_SCENE).instantiate())
	if not sandbox.has_method("spawn_enemy"):
		skip("el script de la zona de pruebas no corre en el editor")
		return null
	_tree.root.add_child(sandbox)
	return sandbox


func _game_state() -> Dictionary:
	var game := _tree.root.get_node("Game")
	var state := {}
	for property in GAME_STATE:
		state[property] = game.get(property)
	return state


func _scores_file() -> String:
	if not FileAccess.file_exists(ScoreBoard.DEFAULT_PATH):
		return ""
	return FileAccess.get_file_as_string(ScoreBoard.DEFAULT_PATH)


func test_main_menu_button_starts_hidden() -> void:
	# main_menu.gd lo muestra solo si OS.is_debug_build(); en la escena empieza
	# oculto, así una build publicada nunca lo muestra.
	var menu: Node = track(load("res://scenes/MainMenu.tscn").instantiate())
	var button := menu.get_node_or_null("SandboxButton") as Button
	assert_true(button != null, "el menú tiene el botón")
	assert_false(button.visible)
	assert_eq(button.text, "Zona de pruebas")
