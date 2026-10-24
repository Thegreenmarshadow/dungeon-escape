@tool
extends McpTestSuite
## Pruebas de los perfiles (ProfileStore): tiempo jugado acumulado entre
## sesiones, partida guardada (con la migración de las vidas enteras a medios
## corazones), carga tolerante y migración de player.cfg. Todo en una carpeta
## temporal de user://, que se borra al terminar.

const TEMP_DIR := "user://test_profiles"
const GAME_SCRIPT := "res://scripts/game.gd"


func suite_name() -> String:
	return "profiles"


func setup() -> void:
	JsonFile.remove_tree(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)


func teardown() -> void:
	JsonFile.remove_tree(TEMP_DIR)


func test_play_time_sums_across_sessions() -> void:
	var first_session := ProfileStore.new(TEMP_DIR)
	var profile := first_session.create_profile("Iñaki Núñez")
	assert_eq(profile["slug"], "inaki-nunez")
	assert_true(first_session.select_profile(profile["slug"]))
	first_session.add_play_time(profile["slug"], 12.5, "run-a", "normal")
	first_session.add_play_time(profile["slug"], 7.5, "run-a", "normal")

	# Otra sesión: un ProfileStore nuevo lee lo que quedó en disco.
	var second_session := ProfileStore.new(TEMP_DIR)
	assert_eq(second_session.selected_slug(), "inaki-nunez", "el perfil elegido se recuerda")
	var loaded := second_session.selected_profile()
	assert_eq(loaded["name"], "Iñaki Núñez")
	assert_true(is_equal_approx(loaded["total_time_s"], 20.0))
	assert_true(is_equal_approx(loaded["runs"]["run-a"]["time_s"], 20.0))
	second_session.add_play_time(profile["slug"], 5.0, "run-b", "demo")

	var third_session := ProfileStore.new(TEMP_DIR)
	var profiles := third_session.list_profiles()
	assert_eq(profiles.size(), 1)
	assert_true(is_equal_approx(profiles[0]["total_time_s"], 25.0))
	assert_eq(profiles[0]["runs"]["run-b"]["mode"], "demo")
	assert_true(is_equal_approx(profiles[0]["runs"]["run-a"]["time_s"], 20.0), "cada partida suma lo suyo")


func test_save_slot_round_trip_and_clear() -> void:
	var store := ProfileStore.new(TEMP_DIR)
	var slug: String = store.create_profile("Ana")["slug"]
	assert_true(store.get_save(slug).is_empty())
	store.set_save(slug, {"level": 4, "health": 5, "weapon_id": "spear", "run_seed": 4294967295,
			"coins": 31, "damage_bonus": 1, "mode": "normal", "score": 470, "enemies_killed": 17,
			"run_id": "abc"})
	var save := ProfileStore.new(TEMP_DIR).get_save(slug)
	assert_eq(save["level"], 4)
	assert_eq(typeof(save["level"]), TYPE_INT)
	assert_eq(save["health"], 5, "medios corazones: vuelve igual, sin convertir")
	assert_false(save.has(ProfileStore.LEGACY_LIVES_KEY))
	assert_eq(save["run_seed"], 4294967295)
	assert_eq(save["weapon_id"], "spear")
	assert_eq(save["coins"], 31)
	assert_eq(save["damage_bonus"], 1)
	assert_eq(save["run_id"], "abc")
	store.clear_save(slug)
	assert_true(store.get_save(slug).is_empty())


func test_saves_from_before_half_hearts_load_their_lives_as_halves() -> void:
	# Un profile.json escrito antes de los medios corazones: la partida guarda
	# "lives" en vidas enteras.
	var store := ProfileStore.new(TEMP_DIR)
	var slug: String = store.create_profile("Ana")["slug"]
	var raw: Variant = JsonFile.read(store.profile_path(slug))
	raw["save"] = {"level": 7, "lives": 2, "weapon_id": "sword", "run_seed": 9, "coins": 3,
			"damage_bonus": 0, "mode": "normal", "score": 50, "enemies_killed": 4, "run_id": "old"}
	JsonFile.write(store.profile_path(slug), raw, "\t")

	var save := ProfileStore.new(TEMP_DIR).get_save(slug)
	assert_eq(save["health"], 2 * Heart.HALF_HEARTS_PER_HEART, "2 vidas = 4 medios corazones")
	assert_false(save.has(ProfileStore.LEGACY_LIVES_KEY), "la clave vieja no se arrastra")
	assert_eq(save["level"], 7)
	# Guardarla otra vez no la convierte de nuevo: la clave marca la unidad.
	store.set_save(slug, save)
	assert_eq(ProfileStore.new(TEMP_DIR).get_save(slug)["health"], 4)

	assert_eq(ProfileStore.saved_health({"lives": 3}), 6)
	assert_eq(ProfileStore.saved_health({"health": 3}), 3, "medio corazón impar: ya está en medios")
	assert_eq(ProfileStore.saved_health({"health": 5, "lives": 1}), 5, "si están las dos, manda la nueva")
	assert_eq(ProfileStore.saved_health({"lives": 0}), 2, "nunca menos de una vida: 2 medios")
	assert_eq(ProfileStore.saved_health({}, 6), 6, "sin ninguna, el valor por defecto")


func test_continue_restores_old_and_new_saves_in_half_hearts() -> void:
	var stub := GDScript.new()
	stub.source_code = "extends \"%s\"\n\n\nfunc start_level() -> void:\n\tpass\n" % GAME_SCRIPT
	stub.reload()
	var game: Node = stub.new()
	game.continue_run({"level": 6, "lives": 1, "run_seed": 5})
	assert_eq(game.health, 2, "partida vieja: 1 vida = 2 medios")
	assert_eq(game.current_level, 6)
	game.continue_run({"level": 6, "health": 3, "run_seed": 5})
	assert_eq(game.health, 3, "partida nueva: medio corazón incluido")
	game.continue_run({"level": 6, "run_seed": 5})
	assert_eq(game.health, game.STARTING_HEALTH, "sin vida guardada empieza con la de siempre")
	game.free()


func test_partial_profile_and_duplicates_load_safely() -> void:
	var store := ProfileStore.new(TEMP_DIR)
	JsonFile.write(store.profile_path("viejo"), {"name": "Viejo"})
	var profile := store.load_profile("viejo")
	assert_eq(profile["name"], "Viejo")
	assert_eq(profile["total_time_s"], 0.0)
	assert_true(profile["runs"].is_empty())
	assert_true(profile["save"].is_empty())
	assert_eq(profile["schema_version"], ProfileStore.SCHEMA_VERSION)
	# El mismo nombre devuelve el mismo perfil; otra carpeta igual se numera.
	assert_eq(store.create_profile("viejo")["slug"], "viejo")
	assert_eq(store.create_profile("Viejo!!")["slug"], "viejo-2")
	assert_true(store.delete_profile("viejo-2"))
	assert_false(store.has_profile("viejo-2"))


func test_legacy_name_is_migrated_once() -> void:
	var legacy_path := TEMP_DIR.path_join("player.cfg")
	PlayerProfile.save_name("Lucía", legacy_path)
	var store := ProfileStore.new(TEMP_DIR.path_join("profiles"))
	var migrated := store.migrate_legacy(legacy_path)
	assert_eq(migrated["name"], "Lucía")
	assert_eq(store.selected_slug(), "lucia")
	store.delete_profile("lucia")
	assert_true(store.migrate_legacy(legacy_path).is_empty(), "solo se migra una vez")
	assert_true(store.list_profiles().is_empty())
