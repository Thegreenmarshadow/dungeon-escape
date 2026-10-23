@tool
extends McpTestSuite
## Pruebas de la curación con corazones: el tope de vida del jugador (heal,
## en medios corazones), la recolección del corazón (se queda si el jugador
## tiene la vida llena), la decisión de soltar un corazón al morir un enemigo
## y la unidad de medio corazón (Heart.HALF_HEARTS_PER_HEART).

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const HEART_SCRIPT := preload("res://scripts/heart.gd")
const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")
## Vida máxima del jugador: 3 corazones = 6 medios.
const FULL := 6


func suite_name() -> String:
	return "heart_drop"


func test_player_and_heart_use_half_hearts() -> void:
	assert_eq(Heart.HALF_HEARTS_PER_HEART, 2)
	var player := _load_fresh("res://scenes/Player.tscn").instantiate()
	track(player)
	assert_eq(player.max_health, FULL, "3 corazones de vida")
	var heart: Heart = track(_load_fresh("res://scenes/Heart.tscn").instantiate())
	assert_eq(heart.heal_amount, Heart.HALF_HEARTS_PER_HEART, "un corazón del suelo cura uno entero")
	assert_eq(Heart.to_hearts(5), 2.5)
	assert_eq(Heart.format_hearts(5), "2.5")
	assert_eq(Heart.format_hearts(4), "2", "sin decimales si es entero")
	assert_eq(Heart.format_heart_amount(3.0), "3")
	assert_eq(Heart.format_heart_amount(0.5), "0.5")
	assert_eq(CsvExport.hearts(1.5), "1.5", "el daño de los CSV de análisis")


func test_half_heart_texture_is_the_left_half_of_the_heart() -> void:
	var full := Heart.get_texture().get_image()
	var half := Heart.get_half_texture().get_image()
	assert_eq(half.get_size(), full.get_size(), "mismo tamaño: se dibuja encima sin moverse")
	for y in full.get_height():
		for x in full.get_width():
			var expected := full.get_pixel(x, y) if x < Heart.HALF_COLUMNS else Color(0, 0, 0, 0)
			assert_eq(half.get_pixel(x, y), expected, "píxel %d, %d" % [x, y])


func test_hud_shows_full_half_and_empty_hearts() -> void:
	var hud_script: GDScript = load("res://scripts/hud.gd")
	assert_eq(hud_script.heart_fills(6, 6), [2, 2, 2] as Array[int], "vida llena")
	assert_eq(hud_script.heart_fills(5, 6), [2, 2, 1] as Array[int], "medio corazón menos")
	assert_eq(hud_script.heart_fills(1, 6), [1, 0, 0] as Array[int])
	assert_eq(hud_script.heart_fills(0, 6), [0, 0, 0] as Array[int], "sin vida, tres vacíos")
	assert_eq(hud_script.heart_fills(9, 10), [2, 2, 2, 2, 1] as Array[int], "la demo tiene 5 corazones")
	assert_eq(hud_script.heart_fills(8, 6), [2, 2, 2, 2] as Array[int], "más vida que el tope: se ve toda")

	var hud: CanvasLayer = load("res://scenes/HUD.tscn").instantiate()
	if not hud.has_method("set_health"):
		hud.free()
		skip("los scripts de la HUD no corren en el editor")
		return
	track(hud)
	(Engine.get_main_loop() as SceneTree).root.add_child(hud)
	hud.set_health(5, 6)
	var hearts: Array[Node] = hud.lives_hearts.get_children()
	assert_eq(hearts.size(), 3, "3 corazones de vida máxima")
	var fills: Array = hearts.map(func(icon: Node) -> TextureRect: return icon.get_child(0))
	assert_true(fills[0].visible and fills[0].texture == Heart.get_texture(), "primero lleno")
	assert_true(fills[2].visible and fills[2].texture == Heart.get_half_texture(), "el último a medias")
	hud.set_health(2, 6)
	assert_false(fills[1].visible or fills[2].visible, "los perdidos quedan vacíos")
	assert_true(hearts[2].self_modulate.a < 1.0, "la parte vacía se ve apagada")


func test_heal_adds_one_heart_and_reports_it() -> void:
	var player := _make_player(1)
	var emitted: Array[int] = []
	player.health_changed.connect(func(health: int) -> void: emitted.append(health))
	assert_true(player.heal(), "con vida faltante debe curar")
	assert_eq(player.health, 1 + Heart.HALF_HEARTS_PER_HEART, "por defecto cura un corazón (2 medios)")
	assert_eq(emitted, [3], "debe avisar el cambio de vida")


func test_heal_is_capped_at_max_health() -> void:
	var player := _make_player(2)
	assert_true(player.heal(10))
	assert_eq(player.health, FULL, "no debe superar max_health")
	var almost := _make_player(FULL - 1)
	assert_true(almost.heal(), "con medio corazón menos también cura")
	assert_eq(almost.health, FULL, "y se queda en el tope")


func test_heal_at_full_health_does_nothing() -> void:
	var player := _make_player(FULL)
	var emitted: Array[int] = []
	player.health_changed.connect(func(health: int) -> void: emitted.append(health))
	assert_false(player.heal(), "con la vida llena no debe curar")
	assert_eq(player.health, FULL)
	assert_eq(emitted, [], "sin cambio no debe emitir la señal")


func test_heal_ignores_dead_player_and_invalid_amounts() -> void:
	var dead := _make_player(0)
	assert_false(dead.heal(), "un jugador muerto no revive")
	assert_eq(dead.health, 0)
	var hurt := _make_player(1)
	assert_false(hurt.heal(0))
	assert_false(hurt.heal(-1))
	assert_eq(hurt.health, 1)


func test_heart_heals_and_is_removed() -> void:
	var player := _make_player(3)
	var heart: Heart = track(HEART_SCRIPT.new())
	assert_true(heart.try_collect(player))
	assert_eq(player.health, 5)
	assert_true(heart.is_queued_for_deletion(), "el corazón recogido debe liberarse")
	assert_false(heart.try_collect(_make_player(1)), "no debe curar dos veces")


func test_heart_stays_when_player_has_full_health() -> void:
	var player := _make_player(FULL)
	var heart: Heart = track(HEART_SCRIPT.new())
	assert_false(heart.try_collect(player))
	assert_false(heart.is_queued_for_deletion(), "debe quedarse en el suelo")
	player.health = FULL - 2
	assert_true(heart.try_collect(player), "al volver herido debe poder recogerlo")
	assert_eq(player.health, FULL)


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


## Jugador fuera del árbol con health medios corazones de FULL: heal solo usa
## health y max_health, así que no hace falta su escena ni que corra _ready.
func _make_player(health: int) -> CharacterBody2D:
	var player: CharacterBody2D = track(PLAYER_SCRIPT.new())
	player.max_health = FULL
	player.health = health
	return player
