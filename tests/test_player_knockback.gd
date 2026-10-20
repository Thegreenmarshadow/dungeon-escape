@tool
extends McpTestSuite
## Pruebas del retroceso del jugador al recibir un golpe: sale despedido lejos
## del origen, recorre la distancia configurada y no se mueve sin origen (picos).

const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const PLAYER_RIG := preload("res://tests/player_rig.gd")


func suite_name() -> String:
	return "player_knockback"


func test_pushes_away_from_the_hit_source() -> void:
	var player := _make_player()
	player._apply_knockback(Vector2(-10, 0))
	assert_true(player._knockback.x > 0.0, "debe ir hacia el lado contrario al golpe")
	assert_eq(player._knockback.y, 0.0)
	var expected_speed: float = 2.0 * player.knockback_distance / PLAYER_SCRIPT.KNOCKBACK_TIME
	assert_true(absf(player._knockback.length() - expected_speed) < 0.01)
	assert_eq(player._knockback_left, PLAYER_SCRIPT.KNOCKBACK_TIME)


func test_no_source_means_no_knockback() -> void:
	var player := _make_player()
	player._apply_knockback(Vector2.INF)
	assert_eq(player._knockback_left, 0.0, "los picos no empujan")
	assert_eq(player._knockback, Vector2.ZERO)


func test_source_at_the_same_position_does_not_produce_nan() -> void:
	var player := _make_player()
	player._apply_knockback(player.global_position)
	assert_eq(player._knockback, Vector2.ZERO)
	assert_false(is_nan(player._knockback_step(0.016).x))


func test_knockback_travels_the_configured_distance() -> void:
	var player := _make_player()
	player._apply_knockback(Vector2(0, -10))
	var delta := 0.001
	var traveled := 0.0
	for i in 400:
		traveled += player._knockback_step(delta).y * delta
	assert_true(absf(traveled - player.knockback_distance) < 1.0,
			"recorrió %.2f px en vez de %.2f" % [traveled, player.knockback_distance])


func test_knockback_speed_decays_to_zero() -> void:
	var player := _make_player()
	player._apply_knockback(Vector2(-10, 0))
	var first: float = player._knockback_step(0.016).length()
	var later: float = player._knockback_step(0.05).length()
	assert_true(later < first, "debe frenar con el tiempo")
	assert_eq(player._knockback_step(PLAYER_SCRIPT.KNOCKBACK_TIME), Vector2.ZERO, "al terminar queda quieto")
	assert_true(player._knockback_left <= 0.0)


func test_invincible_player_takes_no_damage_nor_knockback() -> void:
	var player := _make_player()
	player.invincible = true
	var lives: int = player.lives
	player.take_damage(1, Vector2(-10, 0))
	assert_eq(player.lives, lives, "invencible no pierde vidas")
	assert_eq(player._knockback_left, 0.0, "ni sale despedido")
	assert_eq(player._invulnerable_left, 0.0, "ni parpadea")
	player.invincible = false
	player.take_damage(1, Vector2(-10, 0))
	assert_eq(player.lives, lives - 1, "sin la marca vuelve a recibir daño")


## Jugador armado con PlayerRig (ver ahí por qué no se instancia la escena).
func _make_player() -> CharacterBody2D:
	var player: CharacterBody2D = track(PLAYER_RIG.make_player())
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player
