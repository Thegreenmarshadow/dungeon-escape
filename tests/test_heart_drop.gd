@tool
extends McpTestSuite
## Pruebas de la curación con corazones: el tope de vidas del jugador
## (heal), la recolección del corazón (se queda si el jugador tiene todas sus
## vidas) y la decisión de soltar un corazón al morir un enemigo.

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const HEART_SCRIPT := preload("res://scripts/heart.gd")
const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")


func suite_name() -> String:
	return "heart_drop"


func test_heal_adds_one_life_and_reports_it() -> void:
	var player := _make_player(1)
	var emitted: Array[int] = []
	player.lives_changed.connect(func(lives: int) -> void: emitted.append(lives))
	assert_true(player.heal(), "con vidas faltantes debe curar")
	assert_eq(player.lives, 2)
	assert_eq(emitted, [2], "debe avisar el cambio de vidas")


func test_heal_is_capped_at_max_lives() -> void:
	var player := _make_player(2)
	assert_true(player.heal(5))
	assert_eq(player.lives, 3, "no debe superar max_lives")


func test_heal_at_full_lives_does_nothing() -> void:
	var player := _make_player(3)
	var emitted: Array[int] = []
	player.lives_changed.connect(func(lives: int) -> void: emitted.append(lives))
	assert_false(player.heal(), "con todas las vidas no debe curar")
	assert_eq(player.lives, 3)
	assert_eq(emitted, [], "sin cambio no debe emitir la señal")


func test_heal_ignores_dead_player_and_invalid_amounts() -> void:
	var dead := _make_player(0)
	assert_false(dead.heal(), "un jugador muerto no revive")
	assert_eq(dead.lives, 0)
	var hurt := _make_player(1)
	assert_false(hurt.heal(0))
	assert_false(hurt.heal(-1))
	assert_eq(hurt.lives, 1)


func test_heart_heals_and_is_removed() -> void:
	var player := _make_player(2)
	var heart: Heart = track(HEART_SCRIPT.new())
	assert_true(heart.try_collect(player))
	assert_eq(player.lives, 3)
	assert_true(heart.is_queued_for_deletion(), "el corazón recogido debe liberarse")
	assert_false(heart.try_collect(_make_player(1)), "no debe curar dos veces")


func test_heart_stays_when_player_has_full_lives() -> void:
	var player := _make_player(3)
	var heart: Heart = track(HEART_SCRIPT.new())
	assert_false(heart.try_collect(player))
	assert_false(heart.is_queued_for_deletion(), "debe quedarse en el suelo")
	player.lives = 2
	assert_true(heart.try_collect(player), "al volver herido debe poder recogerlo")
	assert_eq(player.lives, 3)


func test_heart_ignores_bodies_that_cannot_heal() -> void:
	var heart: Heart = track(HEART_SCRIPT.new())
	var other: Node2D = track(Node2D.new())
	assert_false(heart.try_collect(other))
	assert_false(heart.is_queued_for_deletion())


func test_should_drop_compares_roll_with_chance() -> void:
	assert_true(Heart.should_drop(0.18, 0.0))
	assert_true(Heart.should_drop(0.18, 0.17))
	assert_false(Heart.should_drop(0.18, 0.18))
	assert_false(Heart.should_drop(0.18, 0.99))


func test_should_drop_extremes() -> void:
	assert_true(Heart.should_drop(1.0, 1.0), "con probabilidad 1 suelta siempre")
	assert_true(Heart.should_drop(1.0, 0.0))
	assert_false(Heart.should_drop(0.0, 0.0), "con probabilidad 0 nunca suelta")
	assert_false(Heart.should_drop(0.0, 1.0))


func test_drop_rate_is_close_to_chance_with_seeded_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var drops := 0
	var rolls := 10000
	for i in rolls:
		if Heart.should_drop(0.18, rng.randf()):
			drops += 1
	var rate := float(drops) / rolls
	assert_true(absf(rate - 0.18) < 0.02, "tasa observada %.3f" % rate)


func test_drop_chance_defaults_regular_enemies_and_bosses() -> void:
	var enemy: EnemyBase = track(ENEMY_BASE_SCRIPT.new())
	assert_eq(enemy.heart_drop_chance, 0.18, "enemigo común")
	var reaper: EnemyBase = track(_load_fresh("res://scenes/Reaper.tscn").instantiate())
	assert_eq(reaper.heart_drop_chance, 1.0, "el jefe siempre suelta")
	var skeleton: EnemyBase = track(_load_fresh("res://scenes/Skeleton.tscn").instantiate())
	assert_eq(skeleton.heart_drop_chance, 0.18)


## Lee la escena desde el disco y no desde la caché del editor, que puede
## tener una versión anterior si el archivo se editó fuera de él.
func _load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Jugador fuera del árbol: heal solo usa lives y max_lives, así que no hace
## falta su escena ni que corra _ready.
func _make_player(lives: int) -> CharacterBody2D:
	var player: CharacterBody2D = track(PLAYER_SCRIPT.new())
	player.max_lives = 3
	player.lives = lives
	return player
