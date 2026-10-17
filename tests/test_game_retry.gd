@tool
extends McpTestSuite
## Pruebas de "Reintentar" (Game.retry) y de qué estado de la partida se
## conserva o se reinicia (monedas y mejoras). Usan una copia de Game cuya
## start_level solo cuenta las llamadas, así nunca se cambia de escena.

const GAME_SCRIPT := "res://scripts/game.gd"


var _game: Node


func suite_name() -> String:
	return "game_retry"


func setup() -> void:
	var stub := GDScript.new()
	stub.source_code = "extends \"%s\"\n\nvar levels_started: int = 0\n\n\nfunc start_level() -> void:\n\tlevels_started += 1\n" % GAME_SCRIPT
	stub.reload()
	_game = stub.new()


func teardown() -> void:
	_game.free()


func test_retry_after_a_normal_run_starts_from_level_one() -> void:
	_game.start_new_game()
	_game.current_level = 4
	_game.retry()
	assert_false(_game.test_mode)
	assert_eq(_game.current_level, 1)
	assert_eq(_game.levels_started, 2)


func test_retry_after_a_test_run_restarts_at_its_first_level() -> void:
	_game.start_test_run(50)
	_game.complete_level()
	_game.complete_level()
	_game.lives = 0
	_game.retry()
	assert_true(_game.test_mode, "debe seguir en modo prueba")
	assert_eq(_game.current_level, 50)
	assert_eq(_game.test_start_level, 50)
	assert_eq(_game.lives, _game.STARTING_LIVES)
	assert_eq(_game.levels_started, 2)


func test_retry_emits_run_started() -> void:
	_game.start_test_run(7)
	var started := [0]
	_game.run_started.connect(func() -> void: started[0] += 1)
	_game.retry()
	assert_eq(started[0], 1)


func test_playing_normally_after_a_test_run_leaves_test_mode() -> void:
	_game.start_test_run(30)
	_game.start_new_game()
	_game.retry()
	assert_false(_game.test_mode)
	assert_eq(_game.current_level, 1)


func test_retry_resets_coins_and_upgrades() -> void:
	_game.start_new_game()
	_game.add_coins(40)
	assert_true(_game.buy(Shop.ITEM_DAMAGE, 3))
	assert_eq(_game.damage_bonus, 1)
	_game.retry()
	assert_eq(_game.coins, 0)
	assert_eq(_game.damage_bonus, 0)


func test_retry_of_a_test_run_also_resets_the_wallet() -> void:
	_game.start_test_run(12)
	_game.add_coins(25)
	assert_true(_game.buy(Shop.ITEM_DAMAGE, 3))
	_game.retry()
	assert_true(_game.test_mode)
	assert_eq(_game.coins, 0)
	assert_eq(_game.damage_bonus, 0)


func test_coins_and_upgrades_survive_between_levels() -> void:
	_game.start_new_game()
	_game.add_coins(15)
	assert_true(_game.buy(Shop.ITEM_DAMAGE, 3))
	_game.complete_level()
	_game.start_level()
	assert_eq(_game.coins, 5)
	assert_eq(_game.damage_bonus, 1)
