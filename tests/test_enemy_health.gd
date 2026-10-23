@tool
extends McpTestSuite
## Pruebas de la vida escalada por nivel (EnemyBase.apply_health_scale):
## redondeo, mínimo en la vida base, que no se acumula y que no cambia el daño
## de los enemigos; y del daño escalado por nivel (apply_damage_bonus, en
## medios corazones): parte del daño de la escena, no se acumula, respeta el
## tope y lo que no lastima sigue sin lastimar.

## Escena de cada enemigo y su vida base.
const ENEMY_SCENES := {
	"res://scenes/Skeleton.tscn": 2,
	"res://scenes/Vampire.tscn": 3,
	"res://scenes/Skull.tscn": 2,
	"res://scenes/Reaper.tscn": 5,
	"res://scenes/Archer.tscn": 2,
	"res://scenes/SkullTurret.tscn": 3,
	"res://scenes/Mimic.tscn": 3,
	"res://scenes/Mage.tscn": 3,
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


func test_every_hit_is_one_heart_at_base() -> void:
	# Con los medios corazones el daño base se duplicó: cada golpe sigue
	# quitando un corazón entero, como antes. 0 = no lastima de esa forma.
	for path: String in ENEMY_SCENES:
		var enemy := _make_enemy(path)
		for damage: int in _damage_values(enemy):
			assert_true(damage == 0 or damage == Heart.HALF_HEARTS_PER_HEART,
					"%s: golpe base de %d medios corazones" % [path, damage])


func test_damage_bonus_scales_every_hit_from_its_base() -> void:
	for level in [1, 24, 25, 45, 65, 100]:
		var bonus := LevelGenerator.enemy_damage_bonus(level)
		for path: String in ENEMY_SCENES:
			var enemy := _make_enemy(path)
			var base := _damage_values(enemy)
			enemy.apply_damage_bonus(bonus)
			var expected: Array = base.map(func(d: int) -> int: return LevelGenerator.scaled_hit(d, bonus))
			assert_eq(_damage_values(enemy), expected, "%s en el nivel %d" % [path, level])
			for damage: int in _damage_values(enemy):
				assert_true(damage <= LevelGenerator.MAX_SCALED_HIT, "%s: nunca más de 5 medios" % path)


func test_damage_bonus_does_not_compound_nor_touch_health() -> void:
	var vampire := _make_enemy("res://scenes/Vampire.tscn")
	vampire.apply_damage_bonus(2)
	vampire.apply_damage_bonus(2)
	assert_eq(vampire.attack_damage, 4, "parte de la base 2, no de 4")
	assert_eq(vampire.contact_damage, 0, "sin daño por contacto en la escena, sigue sin él")
	assert_eq(vampire.max_health, 3, "el daño no cambia la vida")
	vampire.apply_damage_bonus(0)
	assert_eq(vampire.attack_damage, 2)
	var reaper := _make_enemy("res://scenes/Reaper.tscn")
	reaper.apply_damage_bonus(1)
	assert_eq(reaper.contact_damage, 3, "la parca también recibe el bonus")


func test_spike_traps_keep_their_base_damage() -> void:
	# Las trampas no son enemigos: el nivel no les suma el bonus de daño.
	var trap: Node = track(ResourceLoader.load("res://scenes/SpikeTrap.tscn", "",
			ResourceLoader.CACHE_MODE_IGNORE).instantiate())
	assert_eq(trap.get("damage"), Heart.HALF_HEARTS_PER_HEART, "un corazón")
	assert_false(trap.has_method("apply_damage_bonus"))


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
