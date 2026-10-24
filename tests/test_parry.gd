@tool
extends McpTestSuite
## Pruebas del parry: devuelve proyectiles (también los que la espada solo
## rompe), castiga golpes cuerpo a cuerpo sin recibir daño, cura, reinicia la
## espera, y no sirve contra trampas ni fuera de la ventana.

const PLAYER_RIG := preload("res://tests/player_rig.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy_base.gd")
const DT := 0.016


func suite_name() -> String:
	return "parry"


func test_parry_reflects_a_projectile_faster_and_heals() -> void:
	var player := _make_player()
	player.health = 3
	var projectile := _make_projectile(player.global_position + Vector2(15, 0))
	var speed: float = projectile.speed
	var parried: Array = []
	player.parried.connect(func(target): parried.append(target))
	player._update_parry(DT, true)
	assert_true(projectile.is_reflected, "el proyectil cercano se devuelve")
	assert_true(projectile.direction.x > 0.0, "sale alejándose del jugador")
	assert_eq(projectile.speed, speed * player.parry_projectile_speed)
	assert_eq(projectile.reflected_damage, 1 + player.parry_projectile_bonus)
	assert_eq(player.health, 3 + player.parry_heal, "un parry logrado cura")
	assert_eq(parried.size(), 1)
	assert_eq(player.parry_cooldown_left(), 0.0, "un parry logrado reinicia la espera")


func test_parry_reflects_even_non_reflectable_projectiles() -> void:
	var player := _make_player()
	var projectile := _make_projectile(player.global_position + Vector2(0, 10))
	projectile.reflectable = false
	player._update_parry(DT, true)
	assert_true(projectile.is_reflected, "la flecha, que la espada solo rompe, el parry la devuelve")


func test_far_projectile_is_not_parried() -> void:
	var player := _make_player()
	var projectile := _make_projectile(player.global_position + Vector2(80, 0))
	player._update_parry(DT, true)
	assert_false(projectile.is_reflected)
	assert_true(player.is_parrying(), "la ventana sigue abierta")


func test_parry_punishes_a_melee_hit_without_damage() -> void:
	var player := _make_player()
	var enemy := _make_enemy(player.global_position + Vector2(12, 0))
	var health: int = player.health
	var enemy_health: int = enemy.health
	player._update_parry(DT, true)
	player.take_damage(2, enemy.global_position, &"Skeleton")
	assert_eq(player.health, health, "el golpe devuelto no hace daño")
	assert_eq(enemy.health, enemy_health - player.get_hit_damage() * player.parry_damage_multiplier,
			"el enemigo recibe el contragolpe")


func test_traps_cannot_be_parried() -> void:
	var player := _make_player()
	var health: int = player.health
	player._update_parry(DT, true)
	player.take_damage(2, Vector2.INF, &"spikes")
	assert_eq(player.health, health - 2, "los picos lastiman igual")


func test_hit_after_the_window_hurts() -> void:
	var player := _make_player()
	var enemy := _make_enemy(player.global_position + Vector2(12, 0))
	var health: int = player.health
	player._update_parry(DT, true)
	for i in int(ceil(player.parry_window / DT)) + 1:
		player._update_parry(DT, false)
	assert_false(player.is_parrying())
	player.take_damage(2, enemy.global_position, &"Skeleton")
	assert_eq(player.health, health - 2, "fuera de la ventana el golpe entra")


func test_missed_parry_has_a_cooldown() -> void:
	var player := _make_player()
	player._update_parry(DT, true)
	for i in int(ceil(player.parry_window / DT)) + 1:
		player._update_parry(DT, false)
	assert_false(player.can_parry(), "un parry fallido obliga a esperar")
	player._update_parry(DT, true)
	assert_false(player.is_parrying(), "durante la espera no abre otra ventana")


func test_parry_flash_returns_to_normal_color() -> void:
	var player := _make_player()
	player.sprite.modulate.a = 0.3
	player._update_parry(DT, true)
	assert_true(player.sprite.modulate.r > 1.0, "al pulsar destella")
	# Avanza la animación del destello hasta el final.
	player._parry_flash_tween.custom_step(player.parry_window + 0.1)
	assert_eq(player.sprite.modulate, Color(1, 1, 1, 0.3), "vuelve a su color y respeta el alfa")


func _make_player() -> CharacterBody2D:
	var player: CharacterBody2D = track(PLAYER_RIG.make_player())
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	player.global_position = Vector2(200, 200)
	return player


func _make_projectile(at: Vector2) -> Projectile:
	var projectile: Projectile = track(PROJECTILE_SCRIPT.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(projectile)
	projectile.launch(at, Vector2.LEFT)
	return projectile


## Enemigo base mínimo, como en test_projectile.gd.
func _make_enemy(at: Vector2) -> EnemyBase:
	var enemy: EnemyBase = ENEMY_SCRIPT.new()
	enemy.max_health = 20
	enemy.dodge_chance = 0.0
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	var frames := SpriteFrames.new()
	for animation in [&"idle", &"hurt", &"death"]:
		if not frames.has_animation(animation):
			frames.add_animation(animation)
	sprite.sprite_frames = frames
	enemy.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	enemy.add_child(shape)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	enemy.add_child(contact)
	track(enemy)
	(Engine.get_main_loop() as SceneTree).root.add_child(enemy)
	enemy.global_position = at
	return enemy
