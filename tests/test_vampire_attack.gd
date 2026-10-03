@tool
extends McpTestSuite
## Pruebas del ataque del vampiro: la escena trae la animación y desactiva el
## daño por contacto, el mordisco lastima solo en los frames de impacto y una
## vez por ataque, y un golpe del jugador lo interrumpe.

const CHASER_SCRIPT := preload("res://scripts/chaser_enemy.gd")


## Jugador falso: solo cuenta el daño recibido.
class TargetStub:
	extends Node2D
	var damage_taken := 0

	func take_damage(amount: int) -> void:
		damage_taken += amount


func suite_name() -> String:
	return "vampire_attack"


func test_vampire_scene_has_attack_and_no_contact_damage() -> void:
	var vampire: Node = track(_load_fresh("res://scenes/Vampire.tscn").instantiate())
	assert_eq(vampire.attack_animation, &"attack")
	assert_eq(vampire.contact_damage, 0, "el vampiro solo lastima con el mordisco")
	var frames: SpriteFrames = vampire.get_node("AnimatedSprite2D").sprite_frames
	assert_true(frames.has_animation(&"attack"))
	assert_eq(frames.get_frame_count(&"attack"), 16)
	assert_false(frames.get_animation_loop(&"attack"), "el ataque no debe repetirse solo")
	var last_hit: int = vampire.attack_hit_frames.y
	assert_true(last_hit < frames.get_frame_count(&"attack"), "los frames de impacto deben existir")


func test_reaper_keeps_contact_damage_and_does_not_attack() -> void:
	var reaper: Node = track(_load_fresh("res://scenes/Reaper.tscn").instantiate())
	assert_eq(reaper.attack_animation, &"")
	assert_eq(reaper.contact_damage, 1)


func test_bite_hurts_only_on_strike_frames_and_once() -> void:
	var vampire := _make_vampire()
	var target := _make_target(Vector2(10, 0))
	vampire._player = target
	vampire._start_attack(target.global_position)

	for frame in range(0, vampire.attack_hit_frames.x):
		vampire.sprite.frame = frame
	assert_eq(target.damage_taken, 0, "la anticipación no lastima")

	vampire.sprite.frame = vampire.attack_hit_frames.x
	assert_eq(target.damage_taken, vampire.attack_damage, "el primer frame de impacto lastima")
	vampire.sprite.frame = vampire.attack_hit_frames.y
	assert_eq(target.damage_taken, vampire.attack_damage, "una sola vez por ataque")


func test_bite_misses_when_player_is_out_of_reach() -> void:
	var vampire := _make_vampire()
	var target := _make_target(Vector2(vampire.attack_reach + 30.0, 0))
	vampire._player = target
	vampire._start_attack(target.global_position)
	for frame in range(vampire.attack_hit_frames.x, vampire.attack_hit_frames.y + 1):
		vampire.sprite.frame = frame
	assert_eq(target.damage_taken, 0, "esquivar alejándose evita el golpe")


func test_bite_can_land_on_second_strike_frame_if_player_steps_in() -> void:
	var vampire := _make_vampire()
	var target := _make_target(Vector2(vampire.attack_reach + 30.0, 0))
	vampire._player = target
	vampire._start_attack(target.global_position)
	vampire.sprite.frame = vampire.attack_hit_frames.x
	assert_eq(target.damage_taken, 0)
	target.position = Vector2(10, 0)
	vampire.sprite.frame = vampire.attack_hit_frames.y
	assert_eq(target.damage_taken, vampire.attack_damage)


func test_is_alerted_while_chasing_or_attacking() -> void:
	var vampire := _make_vampire()
	assert_false(vampire.is_alerted(), "quieto en su puesto no está en alerta")
	vampire._chasing = true
	assert_true(vampire.is_alerted())
	vampire._chasing = false
	vampire._start_attack(Vector2(10, 0))
	assert_true(vampire.is_alerted(), "atacando está en alerta")
	vampire.is_dying = true
	assert_false(vampire.is_alerted(), "muriendo ya no cuenta")


func test_cannot_attack_without_animation_or_during_cooldown() -> void:
	var vampire := _make_vampire()
	assert_true(vampire._can_attack())
	vampire._attack_cooldown_left = 0.5
	assert_false(vampire._can_attack(), "en enfriamiento no ataca")
	vampire._attack_cooldown_left = 0.0
	vampire.attack_animation = &""
	assert_false(vampire._can_attack(), "sin animación de ataque no ataca")


func test_attack_end_starts_cooldown_and_returns_to_idle() -> void:
	var vampire := _make_vampire()
	vampire._start_attack(Vector2(10, 0))
	assert_true(vampire._attacking)
	vampire._on_animation_finished()
	assert_false(vampire._attacking)
	assert_eq(vampire._attack_cooldown_left, vampire.attack_cooldown)
	assert_eq(vampire.sprite.animation, &"idle")


## Escena leída desde el disco y no desde la caché del editor.
func _load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Vampiro armado a mano con los frames reales de Vampire.tscn. Se crea con
## el script (no con la escena) porque en el editor un script que no es @tool
## solo corre si se instancia así.
func _make_vampire() -> ChaserEnemy:
	var source: Node = track(_load_fresh("res://scenes/Vampire.tscn").instantiate())
	var vampire: ChaserEnemy = CHASER_SCRIPT.new()
	vampire.attack_animation = &"attack"
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	vampire.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	vampire.add_child(shape)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	vampire.add_child(contact)
	_add_to_tree(vampire)
	return vampire


func _make_target(at: Vector2) -> TargetStub:
	var target := TargetStub.new()
	target.position = at
	_add_to_tree(target)
	return target


func _add_to_tree(node: Node) -> void:
	track(node)
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
