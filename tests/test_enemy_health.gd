@tool
extends McpTestSuite
## Pruebas de la vida escalada por nivel (EnemyBase.apply_health_scale):
## redondeo, mínimo en la vida base, que no se acumula y que el daño de los
## enemigos no cambia.

## Escena de cada enemigo y su vida base.
const ENEMY_SCENES := {
	"res://scenes/Skeleton.tscn": 2,
	"res://scenes/Vampire.tscn": 3,
	"res://scenes/Skull.tscn": 2,
	"res://scenes/Reaper.tscn": 5,
}


func suite_name() -> String:
	return "enemy_health"


func test_skeleton_health_at_level_10() -> void:
	var skeleton := _make_enemy("res://scenes/Skeleton.tscn")
	skeleton.apply_health_scale(LevelGenerator.enemy_health_scale(10))
	# roundi(2 * 1.72) = 3.
	assert_eq(skeleton.max_health, 3)
	assert_eq(skeleton.health, 3, "la vida actual también se ajusta")


func test_every_enemy_scales_from_its_base() -> void:
	for level in [1, 2, 10, 100]:
		var scale := LevelGenerator.enemy_health_scale(level)
		for path: String in ENEMY_SCENES:
			var base: int = ENEMY_SCENES[path]
			var enemy := _make_enemy(path)
			assert_eq(enemy.max_health, base, "vida base de %s" % path)
			enemy.apply_health_scale(scale)
			assert_eq(enemy.max_health, roundi(base * scale), "%s en el nivel %d" % [path, level])
			assert_eq(enemy.health, enemy.max_health, "%s empieza con la vida llena" % path)


func test_health_never_drops_below_base() -> void:
	for path: String in ENEMY_SCENES:
		var enemy := _make_enemy(path)
		enemy.apply_health_scale(0.4)
		assert_eq(enemy.max_health, ENEMY_SCENES[path], "%s con multiplicador menor a 1" % path)
		enemy.apply_health_scale(0.0)
		assert_eq(enemy.max_health, ENEMY_SCENES[path], "%s con multiplicador 0" % path)


func test_scaling_twice_does_not_compound() -> void:
	var vampire := _make_enemy("res://scenes/Vampire.tscn")
	vampire.apply_health_scale(2.0)
	vampire.apply_health_scale(2.0)
	assert_eq(vampire.max_health, 6, "parte de la base 3, no de 6")
	vampire.apply_health_scale(1.0)
	assert_eq(vampire.max_health, 3)


func test_damage_does_not_change_with_the_scale() -> void:
	for path: String in ENEMY_SCENES:
		var enemy := _make_enemy(path)
		var before := _damage_values(enemy)
		var speed := enemy.speed
		enemy.apply_health_scale(LevelGenerator.enemy_health_scale(100))
		assert_eq(_damage_values(enemy), before, "daño de %s" % path)
		assert_eq(enemy.speed, speed, "velocidad de %s" % path)


# ----- ayudas -----

## Enemigo fuera del árbol: apply_health_scale no usa los nodos de la escena.
func _make_enemy(path: String) -> EnemyBase:
	var scene: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return track(scene.instantiate())


## Daño por contacto y, en los perseguidores, daño del ataque.
func _damage_values(enemy: EnemyBase) -> Array:
	var values: Array = [enemy.contact_damage]
	if enemy is ChaserEnemy:
		values.append(enemy.attack_damage)
	return values
