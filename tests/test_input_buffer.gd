@tool
extends McpTestSuite
## Pruebas del input buffering del ataque: un ataque pulsado durante el
## enfriamiento sale solo al terminar, si no pasó attack_buffer_time.

const PLAYER_RIG := preload("res://tests/player_rig.gd")


func suite_name() -> String:
	return "input_buffer"


func test_attack_ready_fires_on_the_same_frame() -> void:
	var player := _make_player()
	var used: Array = []
	player.buffered_action_used.connect(func(action, waited): used.append([action, waited]))
	player._update_attack_buffer(0.016, true)
	assert_true(player._cooldown_left > 0.0, "debe atacar en el mismo frame")
	assert_eq(player.attack_buffer_left(), 0.0)
	assert_eq(used.size(), 0, "sin espera no cuenta como buffer")


func test_attack_during_cooldown_fires_when_ready() -> void:
	var player := _make_player()
	player._cooldown_left = 0.1
	var used: Array = []
	player.buffered_action_used.connect(func(action, waited): used.append([action, waited]))
	player._update_attack_buffer(0.05, true)
	assert_true(player.attack_buffer_left() > 0.0, "queda guardado")
	player._cooldown_left = 0.0
	player._update_attack_buffer(0.05, false)
	assert_true(player._cooldown_left > 0.0, "el golpe guardado sale solo")
	assert_eq(player.attack_buffer_left(), 0.0)
	assert_eq(used.size(), 1)
	assert_eq(used[0][0], &"attack")


func test_buffered_attack_expires() -> void:
	var player := _make_player()
	player._cooldown_left = 1.0
	player._update_attack_buffer(0.016, true)
	for i in 20:
		player._update_attack_buffer(0.016, false)
	assert_eq(player.attack_buffer_left(), 0.0, "pasado attack_buffer_time se olvida")
	player._cooldown_left = 0.0
	player._update_attack_buffer(0.016, false)
	assert_eq(player._cooldown_left, 0.0, "no debe atacar con un pedido vencido")


func test_zero_buffer_time_disables_buffering() -> void:
	var player := _make_player()
	player.attack_buffer_time = 0.0
	player._cooldown_left = 0.05
	player._update_attack_buffer(0.016, true)
	player._cooldown_left = 0.0
	player._update_attack_buffer(0.016, false)
	assert_eq(player._cooldown_left, 0.0, "sin buffer no debe atacar después")


## Jugador armado con PlayerRig, como en test_player_knockback.gd.
func _make_player() -> CharacterBody2D:
	var player: CharacterBody2D = track(PLAYER_RIG.make_player())
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player
