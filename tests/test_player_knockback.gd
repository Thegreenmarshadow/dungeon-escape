@tool
extends McpTestSuite
## Pruebas del retroceso del jugador al recibir un golpe: sale despedido lejos
## del origen, recorre la distancia configurada y no se mueve sin origen (picos).

const PLAYER_SCRIPT := preload("res://scripts/player.gd")


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


## Jugador armado con el script y los hijos que necesita su _ready, con los
## frames reales de Player.tscn. En el editor un script que no es @tool solo
## corre si se instancia con el script y no con la escena.
func _make_player() -> CharacterBody2D:
	var source: Node = track(ResourceLoader.load("res://scenes/Player.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate())
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	player.add_child(sprite)
	var pivot := Node2D.new()
	pivot.name = "AttackPivot"
	var hitbox := Area2D.new()
	hitbox.name = "Hitbox"
	pivot.add_child(hitbox)
	var slash := Line2D.new()
	slash.name = "Slash"
	pivot.add_child(slash)
	player.add_child(pivot)
	track(player)
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player
