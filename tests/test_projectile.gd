@tool
extends McpTestSuite
## Pruebas de los proyectiles (Projectile): vuelan en línea recta, lastiman al
## jugador una sola vez, desaparecen al chocar o al agotar su alcance, la
## espada los rompe y el orbe del mago se puede devolver contra los enemigos.

const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")
const ENEMY_SCRIPT := preload("res://scripts/enemy_base.gd")
const SCENES := [
	"res://scenes/projectiles/Arrow.tscn",
	"res://scenes/projectiles/OrbBlue.tscn",
	"res://scenes/projectiles/OrbGold.tscn",
]
## Velocidad máxima de un proyectil (sección 6.1 de la biblia).
const MAX_SPEED := 140.0


## Jugador falso: cuenta el daño recibido y desde dónde llegó.
class TargetStub:
	extends Node2D
	var damage_taken := 0
	var last_source := Vector2.INF

	func take_damage(amount: int, from_position: Vector2 = Vector2.INF) -> void:
		damage_taken += amount
		last_source = from_position


func suite_name() -> String:
	return "projectile"


func test_scenes_use_the_expected_layers() -> void:
	for path: String in SCENES:
		var projectile: Projectile = track(_load_fresh(path).instantiate())
		assert_eq(projectile.collision_layer, 4, "%s: capa 3, la espada lo detecta" % path)
		assert_eq(projectile.collision_mask, 3, "%s: choca con paredes y jugador" % path)
		assert_true(projectile.speed <= MAX_SPEED, "%s: demasiado rápido" % path)
		assert_true(projectile.max_range > 0.0, path)
		assert_true(projectile.has_node("AnimatedSprite2D"), path)
	var arrow: Projectile = track(_load_fresh(SCENES[0]).instantiate())
	assert_true(arrow.rotate_to_direction, "la flecha gira hacia donde vuela")
	assert_false(arrow.reflectable, "la flecha se rompe")
	var gold: Projectile = track(_load_fresh(SCENES[2]).instantiate())
	assert_true(gold.reflectable, "el orbe del mago se devuelve")


func test_flies_straight_and_expires_at_max_range() -> void:
	var projectile := _make()
	projectile.launch(Vector2(10, 10), Vector2(0, 5))
	projectile.advance(0.5)
	assert_true(projectile.global_position.distance_to(Vector2(10, 10 + projectile.speed * 0.5)) < 0.001)
	assert_false(projectile.is_queued_for_deletion())
	projectile.advance(projectile.max_range / projectile.speed)
	assert_true(projectile.is_queued_for_deletion(), "desaparece al agotar el alcance")


func test_rotates_toward_its_direction() -> void:
	var projectile := _make()
	projectile.rotate_to_direction = true
	projectile.launch(Vector2.ZERO, Vector2.DOWN)
	assert_true(absf(projectile.rotation - PI / 2.0) < 0.001)


func test_hurts_the_player_once_and_disappears() -> void:
	var projectile := _make()
	projectile.launch(Vector2(5, 0), Vector2.RIGHT)
	var target := _make_target()
	projectile._on_body_entered(target)
	assert_eq(target.damage_taken, projectile.damage)
	assert_eq(target.last_source, Vector2(5, 0), "empuja desde donde estaba el proyectil")
	assert_true(projectile.is_queued_for_deletion())
	projectile._on_body_entered(target)
	assert_eq(target.damage_taken, projectile.damage, "una sola vez")


func test_wall_stops_it_without_damage() -> void:
	var projectile := _make()
	var wall: StaticBody2D = track(StaticBody2D.new())
	projectile._on_body_entered(wall)
	assert_true(projectile.is_queued_for_deletion())


func test_sword_breaks_a_non_reflectable_projectile() -> void:
	var projectile := _make()
	projectile.take_hit(1, Vector2(-10, 0))
	assert_true(projectile.is_queued_for_deletion())


func test_sword_reflects_the_mage_orb_against_enemies() -> void:
	var projectile := _make()
	projectile.reflectable = true
	projectile.launch(Vector2(20, 0), Vector2.LEFT)
	projectile.take_hit(1, Vector2(10, 0))
	assert_false(projectile.is_queued_for_deletion())
	assert_true(projectile.is_reflected)
	assert_eq(projectile.direction, Vector2.RIGHT, "vuelve alejándose del jugador")
	assert_eq(projectile.collision_mask, Projectile.WORLD_MASK | Projectile.ENEMY_MASK)

	var target := _make_target()
	projectile._on_body_entered(target)
	assert_eq(target.damage_taken, 0, "devuelto ya no lastima al jugador")

	var reflected := _make()
	reflected.reflectable = true
	reflected.take_hit(1, Vector2(-10, 0))
	var enemy := _make_enemy()
	var health_before := enemy.health
	reflected._on_body_entered(enemy)
	assert_eq(enemy.health, health_before - reflected.damage, "lastima al enemigo que toca")
	assert_true(reflected.is_queued_for_deletion())


func test_reflected_orb_flies_back_at_the_body_of_its_shooter() -> void:
	# El orbe sale más arriba que el cuerpo del mago: devuelto por el mismo
	# camino le pasaría por encima, así que apunta al centro de su cuerpo.
	var mage := _make_enemy()
	mage.global_position = Vector2(0, 0)
	mage.body_shape.position = Vector2(0, 4)
	var orb := _make()
	orb.reflectable = true
	orb.shooter = mage
	orb.launch(Vector2(60, -15), Vector2.RIGHT)
	orb.take_hit(1, Vector2(70, -15))
	assert_true(orb.direction.is_equal_approx(Vector2(-60, 19).normalized()),
			"vuelve al cuerpo del tirador, no por donde vino")

	var orphan := _make()
	orphan.reflectable = true
	orphan.shooter = mage
	mage._die()
	orphan.launch(Vector2(60, -15), Vector2.RIGHT)
	orphan.take_hit(1, Vector2(70, -15))
	assert_eq(orphan.direction, Vector2.LEFT, "con el tirador muerto sale alejándose del jugador")


# ----- ayudas -----

func _load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _make() -> Projectile:
	var projectile: Projectile = PROJECTILE_SCRIPT.new()
	_add_to_tree(projectile)
	return projectile


func _make_target() -> TargetStub:
	var target := TargetStub.new()
	_add_to_tree(target)
	return target


## Enemigo base mínimo, sin esquiva, para recibir el orbe devuelto.
func _make_enemy() -> EnemyBase:
	var enemy: EnemyBase = ENEMY_SCRIPT.new()
	enemy.max_health = 3
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
	_add_to_tree(enemy)
	return enemy


func _add_to_tree(node: Node) -> void:
	track(node)
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
