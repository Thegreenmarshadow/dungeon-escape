@tool
extends McpTestSuite
## Pruebas de la calavera embestidora: la escena trae sus animaciones, y la
## máquina de estados avanza detectar -> cargar -> embestir -> aturdirse, cancela
## al recibir un golpe y apunta al jugador solo al terminar la carga.

const SKULL_SCRIPT := preload("res://scripts/skull_enemy.gd")


## Jugador falso: solo tiene posición.
class TargetStub:
	extends Node2D


func suite_name() -> String:
	return "skull_enemy"


func test_skull_scene_has_non_looping_hurt_and_death() -> void:
	var skull: Node = track(_load_fresh("res://scenes/Skull.tscn").instantiate())
	var frames: SpriteFrames = skull.get_node("AnimatedSprite2D").sprite_frames
	assert_true(frames.get_animation_loop(&"idle"))
	for animation in [&"hurt", &"death"]:
		assert_true(frames.has_animation(animation), "falta %s" % animation)
		assert_false(frames.get_animation_loop(animation), "%s no debe repetirse" % animation)
	assert_eq(skull.move_animation, &"idle", "no tiene animación de caminar")
	assert_eq(skull.contact_damage, 1)


func test_stays_idle_when_player_is_far() -> void:
	var skull := _make_skull(Vector2(200, 0))
	skull._get_move_velocity(0.016)
	assert_eq(skull._state, SkullEnemy.State.IDLE)


func test_starts_windup_when_player_is_close_and_stands_still() -> void:
	var skull := _make_skull(Vector2(40, 0))
	var velocity := skull._get_move_velocity(0.016)
	assert_eq(skull._state, SkullEnemy.State.WINDUP)
	assert_eq(velocity, Vector2.ZERO)
	assert_eq(skull._get_move_velocity(0.016), Vector2.ZERO, "durante la carga no se mueve")


func test_charges_toward_player_after_windup() -> void:
	var skull := _make_skull(Vector2(40, 0))
	skull._get_move_velocity(0.016)
	skull._get_move_velocity(skull.windup_time + 0.1)
	assert_eq(skull._state, SkullEnemy.State.CHARGE)
	var velocity := skull._get_move_velocity(0.016)
	assert_eq(velocity, Vector2.RIGHT * skull.charge_speed)


func test_aim_locks_at_end_of_windup_not_before() -> void:
	var skull := _make_skull(Vector2(40, 0))
	skull._get_move_velocity(0.016)
	# El jugador se mueve durante la carga: la embestida va a donde está al final.
	skull._player.position = Vector2(0, 40)
	skull._get_move_velocity(skull.windup_time + 0.1)
	assert_eq(skull._charge_direction, Vector2.DOWN)
	skull._player.position = Vector2(-40, 0)
	assert_eq(skull._get_move_velocity(0.016), Vector2.DOWN * skull.charge_speed,
			"una vez lanzada no cambia de dirección")


func test_charge_ends_after_max_time_and_recovers() -> void:
	var skull := _make_skull(Vector2(40, 0))
	skull._get_move_velocity(0.016)
	skull._get_move_velocity(skull.windup_time + 0.1)
	skull._get_move_velocity(skull.charge_max_time + 0.1)
	assert_eq(skull._state, SkullEnemy.State.RECOVER)
	assert_eq(skull._get_move_velocity(0.016), Vector2.ZERO, "aturdida no se mueve")
	skull._get_move_velocity(skull.recover_time + 0.1)
	assert_eq(skull._state, SkullEnemy.State.IDLE)
	assert_true(skull._cooldown_left > 0.0, "tras recuperarse espera antes de cargar otra vez")
	skull._get_move_velocity(0.016)
	assert_eq(skull._state, SkullEnemy.State.IDLE, "en enfriamiento no vuelve a cargar")


func test_is_alerted_from_windup_until_recovery_ends() -> void:
	var skull := _make_skull(Vector2(40, 0))
	assert_false(skull.is_alerted(), "en reposo no está en alerta")
	skull._enter(SkullEnemy.State.WINDUP, 1.0)
	assert_true(skull.is_alerted())
	skull._enter(SkullEnemy.State.CHARGE, 1.0)
	assert_true(skull.is_alerted())
	skull._enter(SkullEnemy.State.IDLE, 0.0)
	assert_false(skull.is_alerted())
	skull._enter(SkullEnemy.State.WINDUP, 1.0)
	skull.is_dying = true
	assert_false(skull.is_alerted(), "muriendo ya no cuenta")


func test_only_hurts_while_charging() -> void:
	var skull := _make_skull(Vector2(40, 0))
	# Sin el área de contacto, el daño por contacto de la base fallaría: que
	# no falle prueba que fuera de la embestida ni siquiera llega a consultarla.
	skull.contact_area = null
	skull._damage_touching_bodies()
	assert_eq(skull._state, SkullEnemy.State.IDLE, "fuera de la embestida no hace daño")


func test_speed_scale_rises_only_while_charging() -> void:
	var skull := _make_skull(Vector2(40, 0))
	assert_eq(skull.sprite.speed_scale, 1.0)
	skull._enter(SkullEnemy.State.CHARGE, 1.0)
	assert_eq(skull.sprite.speed_scale, SkullEnemy.CHARGE_ANIMATION_SCALE)
	skull._enter(SkullEnemy.State.RECOVER, 1.0)
	assert_eq(skull.sprite.speed_scale, 1.0)


## Escena leída desde el disco y no desde la caché del editor.
func _load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Calavera armada a mano con los frames reales de Skull.tscn. Se crea con el
## script (no con la escena) porque en el editor un script que no es @tool solo
## corre si se instancia así.
func _make_skull(player_at: Vector2) -> SkullEnemy:
	var source: Node = track(_load_fresh("res://scenes/Skull.tscn").instantiate())
	var skull: SkullEnemy = SKULL_SCRIPT.new()
	skull.move_animation = &"idle"
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	skull.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	skull.add_child(shape)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	skull.add_child(contact)
	_add_to_tree(skull)
	var target := TargetStub.new()
	target.position = player_at
	_add_to_tree(target)
	skull._player = target
	return skull


func _add_to_tree(node: Node) -> void:
	track(node)
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
