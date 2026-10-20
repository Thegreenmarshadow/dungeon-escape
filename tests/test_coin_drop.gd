@tool
extends McpTestSuite
## Pruebas de las monedas: la decisión de soltar una y su valor, la
## recolección, las monedas sueltas de los mapas generados, los datos que
## exponen los enemigos y el daño extra del jugador.

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const COIN_SCRIPT := preload("res://scripts/coin.gd")
const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")


func suite_name() -> String:
	return "coin_drop"


func test_should_drop_compares_roll_with_chance() -> void:
	assert_true(Coin.should_drop(0.45, 0.0))
	assert_true(Coin.should_drop(0.45, 0.44))
	assert_false(Coin.should_drop(0.45, 0.45))
	assert_true(Coin.should_drop(1.0, 1.0), "con probabilidad 1 suelta siempre")
	assert_false(Coin.should_drop(0.0, 0.0), "con probabilidad 0 nunca suelta")


func test_value_covers_the_whole_range() -> void:
	assert_eq(Coin.value_for(1, 3, 0.0), 1)
	assert_eq(Coin.value_for(1, 3, 0.34), 2)
	assert_eq(Coin.value_for(1, 3, 0.99), 3)
	assert_eq(Coin.value_for(1, 3, 1.0), 3, "roll 1 no se sale del rango")
	assert_eq(Coin.value_for(2, 2, 0.7), 2)
	assert_eq(Coin.value_for(5, 3, 0.0), 3, "acepta el rango invertido")


func test_value_distribution_is_roughly_uniform() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var counts := {1: 0, 2: 0, 3: 0}
	for i in 9000:
		counts[Coin.value_for(1, 3, rng.randf())] += 1
	for value in counts:
		assert_true(absi(counts[value] - 3000) < 300, "valor %d salió %d veces" % [value, counts[value]])


func test_coin_gives_its_value_once_and_is_removed() -> void:
	var player := _make_player()
	var collected: Array[int] = []
	player.coins_collected.connect(func(amount: int) -> void: collected.append(amount))
	var coin: Coin = track(COIN_SCRIPT.new())
	coin.value = 3
	assert_true(coin.try_collect(player))
	assert_true(coin.is_queued_for_deletion())
	assert_false(coin.try_collect(player), "no debe sumar dos veces")
	assert_eq(collected, [3])


func test_coin_ignores_bodies_that_cannot_collect() -> void:
	var coin: Coin = track(COIN_SCRIPT.new())
	assert_false(coin.try_collect(track(Node2D.new())))
	assert_false(coin.is_queued_for_deletion())


func test_player_damage_includes_the_bought_bonus() -> void:
	var player := _make_player()
	assert_eq(player.get_hit_damage(), player.weapon.damage)
	player.damage_bonus = 2
	assert_eq(player.get_hit_damage(), player.weapon.damage + 2)
	player.damage_bonus = -1
	assert_eq(player.get_hit_damage(), player.weapon.damage, "un bono negativo no resta")


func test_enemies_expose_their_coin_data() -> void:
	var enemy: EnemyBase = track(ENEMY_BASE_SCRIPT.new())
	assert_eq(enemy.coin_drop_chance, 0.25)
	assert_eq([enemy.coin_min_value, enemy.coin_max_value], [1, 2])
	var vampire: EnemyBase = track(_load_fresh("res://scenes/Vampire.tscn").instantiate())
	assert_eq(vampire.coin_drop_chance, 0.35, "el vampiro es más duro y suelta más")
	assert_eq(vampire.coin_max_value, 3)
	var reaper: EnemyBase = track(_load_fresh("res://scenes/Reaper.tscn").instantiate())
	assert_eq(reaper.coin_drop_chance, 0.75, "el jefe es el que más suelta")
	assert_eq([reaper.coin_min_value, reaper.coin_max_value], [3, 5])


func test_loose_coins_are_deterministic_and_on_free_floor() -> void:
	var layout := LevelGenerator.generate(4, 777)
	var cells := Coin.scatter_cells(layout, 99, 3)
	assert_eq(cells.size(), 3)
	assert_eq(Coin.scatter_cells(layout, 99, 3), cells, "misma semilla, mismas celdas")
	var occupied: Array[Vector2i] = [layout.player_cell, layout.key_cell, layout.door_cell]
	for spawn in layout.enemies + layout.hazards:
		occupied.append(spawn.cell)
	var seen := {}
	for cell in cells:
		assert_true(layout.is_interior(cell), "%s debe ser suelo interior" % cell)
		assert_false(cell in occupied, "%s está ocupada" % cell)
		assert_false(seen.has(cell), "%s repetida" % cell)
		seen[cell] = true


func test_loose_coins_do_not_change_the_generated_map() -> void:
	var before := LevelGenerator.generate(5, 31337).summary()
	Coin.scatter_cells(LevelGenerator.generate(5, 31337), 1, 3)
	assert_eq(LevelGenerator.generate(5, 31337).summary(), before)
	assert_eq(Coin.scatter_cells(LevelGenerator.Layout.new(Vector2i(4, 4)), 1, 3), [] as Array[Vector2i],
			"sin salas no hay monedas")


func test_coin_value_follows_the_enemy_scale() -> void:
	assert_eq(Coin.scaled_value(1, 1.0), 1)
	assert_eq(Coin.scaled_value(1, 1.08), 1, "se redondea")
	assert_eq(Coin.scaled_value(3, 1.72), 5)
	assert_eq(Coin.scaled_value(5, 8.92), 45)
	assert_eq(Coin.scaled_value(2, 0.5), 2, "nunca baja del valor base")


func _load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Jugador fuera del árbol: collect_coins y get_hit_damage no usan su escena.
func _make_player() -> CharacterBody2D:
	return track(PLAYER_SCRIPT.new())
