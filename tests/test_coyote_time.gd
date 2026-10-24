@tool
extends McpTestSuite
## Pruebas del salto: coyote time sobre un abismo, caída al acabarse, salto
## por encima del abismo y buffer del salto pulsado en el aire.

const PLAYER_RIG := preload("res://tests/player_rig.gd")
const PIT_SCRIPT := preload("res://scripts/pit.gd")
const DT := 0.016


func suite_name() -> String:
	return "coyote_time"


func test_can_jump_during_coyote_time() -> void:
	var player := _make_player_next_to_pit()
	player.global_position = Vector2(108, 8)
	player._update_jump(DT, false)
	assert_true(player.coyote_left() > 0.0, "al pisar el abismo empieza el coyote time")
	assert_true(player.can_jump(), "todavía puede saltar")
	player._update_jump(DT, true)
	assert_true(player.is_jumping(), "salta aunque ya esté sobre el abismo")
	assert_false(player._falling)


func test_falls_when_coyote_time_runs_out() -> void:
	var player := _make_player_next_to_pit()
	var fell := [false]
	player.fell.connect(func(): fell[0] = true)
	player.global_position = Vector2(108, 8)
	var steps := int(ceil(player.coyote_time / DT)) + 1
	for i in steps:
		player._update_jump(DT, false)
	assert_true(player._falling, "sin saltar, cae")
	assert_true(fell[0])
	assert_false(player.can_jump(), "cayendo no puede saltar")


func test_safe_ground_is_remembered() -> void:
	var player := _make_player_next_to_pit()
	player.global_position = Vector2(90, 8)
	player._update_jump(DT, false)
	assert_eq(player._last_safe_position, Vector2(90, 8))
	player.global_position = Vector2(108, 8)
	player._update_jump(DT, false)
	assert_eq(player._last_safe_position, Vector2(90, 8), "sobre el abismo no se actualiza")


func test_no_fall_while_in_the_air() -> void:
	var player := _make_player_next_to_pit()
	player._update_jump(DT, true)
	assert_true(player.is_jumping())
	player.global_position = Vector2(108, 8)
	for i in 10:
		player._update_jump(DT, false)
	assert_false(player._falling, "en el aire no cae")


func test_landing_on_the_pit_falls() -> void:
	var player := _make_player_next_to_pit()
	player._update_jump(DT, true)
	player.global_position = Vector2(108, 8)
	for i in int(ceil(player.jump_duration / DT)) + 1:
		player._update_jump(DT, false)
	assert_true(player._falling, "aterrizar en el abismo hace caer sin coyote time")


func test_jump_pressed_in_the_air_is_buffered() -> void:
	var player := _make_player_next_to_pit()
	var used: Array = []
	player.buffered_action_used.connect(func(action, waited): used.append(action))
	player._update_jump(DT, true)
	# Pulsa de nuevo poco antes de aterrizar.
	player._jump_left = 0.05
	player._update_jump(DT, true)
	for i in 4:
		player._update_jump(DT, false)
	assert_true(player.is_jumping(), "el salto guardado sale al aterrizar")
	assert_true(used.has(&"jump"))


func test_jump_buffer_expires() -> void:
	var player := _make_player_next_to_pit()
	player._update_jump(DT, true)
	player._jump_left = 0.5
	player._update_jump(DT, true)
	for i in 40:
		player._update_jump(DT, false)
	assert_false(player.is_jumping(), "un salto pulsado mucho antes de aterrizar se olvida")


## Jugador en (40, 8) y un abismo de 16 px de ancho en x = 100..116.
func _make_player_next_to_pit() -> CharacterBody2D:
	var root := (Engine.get_main_loop() as SceneTree).root
	var pit: Node2D = track(PIT_SCRIPT.new())
	pit.position = Vector2(100, 0)
	pit.size = Vector2(16, 16)
	root.add_child(pit)
	var player: CharacterBody2D = track(PLAYER_RIG.make_player())
	root.add_child(player)
	player.global_position = Vector2(40, 8)
	player._last_safe_position = player.global_position
	return player
