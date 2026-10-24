@tool
extends McpTestSuite
## Pruebas del abismo: frena a los enemigos que caminan (cuerpo en la capa
## "pits"), no al jugador ni a los proyectiles, y deja pasar a los que vuelan.

const PIT_SCRIPT := preload("res://scripts/pit.gd")
const PLAYER_RIG := preload("res://tests/player_rig.gd")
const PROJECTILE_SCRIPT := preload("res://scripts/projectile.gd")


func suite_name() -> String:
	return "pit"


func test_pit_has_a_blocker_the_size_of_the_hole() -> void:
	var pit := _make_pit(Vector2(32, 16))
	var body := pit.get_node("EnemyBlocker") as StaticBody2D
	assert_true(body != null, "tiene el cuerpo que frena a los enemigos")
	assert_eq(body.collision_layer, PIT_SCRIPT.PIT_COLLISION_LAYER)
	assert_eq(body.collision_mask, 0)
	var shape := body.get_child(0) as CollisionShape2D
	assert_eq((shape.shape as RectangleShape2D).size, Vector2(32, 16))
	assert_eq(shape.position, Vector2(16, 8), "centrado en el hueco")


func test_walking_enemies_collide_with_pits_and_flying_ones_do_not() -> void:
	for path in ["res://scenes/Skeleton.tscn", "res://scenes/Vampire.tscn", "res://scenes/Skull.tscn"]:
		var enemy: Node = track(load(path).instantiate())
		var can_fly: bool = enemy.can_fly
		# La máscara se arma en _ready: se replica sin instanciar el script en el editor.
		var mask: int = enemy.collision_mask | EnemyBase.PLAYER_COLLISION_LAYER
		if not can_fly:
			mask |= EnemyBase.PIT_COLLISION_LAYER
		assert_eq(mask & PIT_SCRIPT.PIT_COLLISION_LAYER != 0, not can_fly, path)
	assert_true(load("res://scenes/Skull.tscn").instantiate().can_fly, "la calavera vuela")
	assert_false(load("res://scenes/Skeleton.tscn").instantiate().can_fly, "el esqueleto camina")


func test_player_and_projectiles_ignore_the_pit_layer() -> void:
	var player: CharacterBody2D = track(PLAYER_RIG.make_player())
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	assert_eq(player.collision_mask & PIT_SCRIPT.PIT_COLLISION_LAYER, 0,
			"el jugador pisa el abismo (y cae) en vez de chocar")
	var projectile: Projectile = track(PROJECTILE_SCRIPT.new())
	assert_eq(projectile.collision_mask & PIT_SCRIPT.PIT_COLLISION_LAYER, 0, "los proyectiles vuelan por encima")


func _make_pit(size: Vector2) -> Node2D:
	var pit: Node2D = track(PIT_SCRIPT.new())
	pit.size = size
	(Engine.get_main_loop() as SceneTree).root.add_child(pit)
	return pit
