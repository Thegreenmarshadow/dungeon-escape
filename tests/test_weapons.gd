@tool
extends McpTestSuite
## Pruebas de las armas del caballero: que la espada (sword.tres) juegue igual
## que el ataque que estaba fijo en player.gd, que el golpe lea sus valores del
## WeaponData equipado y que el arma de la partida se conserve entre niveles y
## se reinicie con cada partida. La compra de armas se prueba en test_shop.

const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")
const PLAYER_RIG := preload("res://tests/player_rig.gd")
const GAME_SCRIPT := "res://scripts/game.gd"
const WEAPONS_DIR := "res://assets/weapons"

## Valores del ataque que player.gd y Player.tscn tenían fijos antes de las
## armas: la espada debe dar exactamente lo mismo.
const OLD_DAMAGE := 1
const OLD_ACTIVE_TIME := 0.2
const OLD_COOLDOWN := 0.4
const OLD_HITBOX_SIZE := Vector2(12, 18)
const OLD_HITBOX_POSITION := Vector2(10, 0)
const OLD_PIVOT_POSITION := Vector2(0, 1)


## Cuenta los golpes que recibe; no es un enemigo, así que recibe el golpe sin
## retroceso del arma.
class HitCounter:
	extends Node2D
	var hits := 0

	func take_hit(_amount: int, _from_position: Vector2) -> void:
		hits += 1


var _game: Node


func suite_name() -> String:
	return "weapons"


func setup() -> void:
	var stub := GDScript.new()
	stub.source_code = "extends \"%s\"\n\n\nfunc start_level() -> void:\n\tpass\n" % GAME_SCRIPT
	stub.reload()
	_game = stub.new()
	_game.new_game()


func teardown() -> void:
	_game.free()


# ----- la espada juega igual que antes -----

func test_sword_has_the_old_hardcoded_values() -> void:
	var sword := WeaponData.load_by_id(&"sword")
	assert_eq(sword.id, &"sword")
	assert_eq(sword.damage, OLD_DAMAGE)
	assert_eq(sword.hitbox_size, OLD_HITBOX_SIZE)
	assert_eq(sword.hitbox_distance, OLD_HITBOX_POSITION.x)
	assert_eq(sword.hitbox_radius, 0.0)
	assert_eq(sword.windup, 0.0)
	assert_eq(sword.active_time, OLD_ACTIVE_TIME)
	assert_eq(sword.cooldown, OLD_COOLDOWN)
	assert_eq(sword.knockback_scale(), 1.0, "cada enemigo retrocede su knockback_distance, como antes")
	assert_eq(sword.move_speed_while_attacking, 1.0)
	assert_true(sword.pierce, "golpea a todos los que toca, como antes")
	assert_eq([sword.combo_hits, sword.crit_chance, sword.stun_time, sword.sweep_degrees], [1, 0.0, 0.0, 0.0])
	assert_false(sword.is_thrust(), "la espada corta en arco")


func test_player_scene_keeps_the_old_hitbox_layout() -> void:
	var scene: Node = track(ResourceLoader.load("res://scenes/Player.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate())
	var pivot: Node2D = scene.get_node("WeaponPivot")
	assert_eq(pivot.position, OLD_PIVOT_POSITION)
	var area: Area2D = scene.get_node("WeaponPivot/Hitbox")
	assert_eq([area.collision_layer, area.collision_mask, area.monitoring], [0, 4, false])
	assert_eq(scene.get_node("WeaponPivot/Hitbox/CollisionShape2D").position, OLD_HITBOX_POSITION)
	assert_eq(scene.weapon.id, &"sword", "empieza con la espada")


func test_player_starts_with_the_sword_hitbox() -> void:
	var player := _make_player()
	assert_eq(player.weapon.id, &"sword")
	var shape: RectangleShape2D = player.hitbox_shape.shape
	assert_eq(shape.size, OLD_HITBOX_SIZE)
	assert_eq(player.hitbox_shape.position, OLD_HITBOX_POSITION)


func test_sword_attack_timing_matches_the_old_one() -> void:
	var player := _make_player()
	# Con attack_speed 1 los tiempos son los de la espada original.
	player.attack_speed = 1.0
	player._try_attack()
	assert_eq(player._cooldown_left, OLD_COOLDOWN)
	assert_eq(player._attack_left, OLD_ACTIVE_TIME, "sin anticipación: la hitbox se activa enseguida")
	assert_true(player.is_attacking())
	player._update_attack(OLD_ACTIVE_TIME + 0.01)
	assert_false(player.is_attacking(), "la hitbox dura active_time")
	player._try_attack()
	assert_false(player.is_attacking(), "en enfriamiento no vuelve a atacar")
	player._update_attack(OLD_COOLDOWN)
	player._try_attack()
	assert_true(player.is_attacking(), "pasado el enfriamiento ataca otra vez")


func test_sword_damage_keeps_the_shop_bonus() -> void:
	var player := _make_player()
	assert_eq(player.get_hit_damage(), OLD_DAMAGE)
	player.damage_bonus = 3
	assert_eq(player.get_hit_damage(), OLD_DAMAGE + 3)


# ----- el golpe sale del WeaponData -----

func test_attack_stats_come_from_the_equipped_weapon() -> void:
	var player := _make_player()
	var axe := WeaponData.load_by_id(&"axe")
	player.equip_weapon(axe)
	player.damage_bonus = 1
	assert_eq(player.get_hit_damage(), axe.damage + 1, "daño del arma más el bono")
	player._try_attack()
	var speed: float = player.attack_speed
	assert_eq(player._cooldown_left, axe.cooldown / speed, "attack_speed acelera el enfriamiento")
	assert_eq(player._windup_left, axe.windup / speed)
	assert_eq(player._attack_left, 0.0, "durante la anticipación la hitbox no está activa")
	assert_true(player.is_attacking())
	player._update_attack(axe.windup / speed + 0.001)
	assert_eq(player._attack_left, axe.active_time / speed, "terminada la anticipación empieza el golpe")
	assert_true(player.effect.visible, "y se ve la estela")


func test_equip_builds_the_hitbox_and_the_held_sprite() -> void:
	var player := _make_player()
	var spear := WeaponData.load_by_id(&"spear")
	player.equip_weapon(spear)
	var shape: RectangleShape2D = player.hitbox_shape.shape
	assert_eq(shape.size, spear.hitbox_size)
	assert_eq(player.hitbox_shape.position, Vector2(spear.hitbox_distance, 0))
	assert_eq(player.held.texture, spear.held_texture)
	assert_eq(player.held.offset, spear.held_texture.get_size() / 2.0 - spear.held_grip,
			"la empuñadura queda en el origen del sprite")
	assert_eq(player.effect.sprite_frames, spear.effect_frames)
	assert_true(spear.is_thrust(), "la lanza es una estocada")


func test_round_weapons_get_a_circle_hitbox() -> void:
	var mace := WeaponData.load_by_id(&"mace")
	var shape := mace.make_hitbox_shape()
	assert_true(shape is CircleShape2D)
	assert_eq((shape as CircleShape2D).radius, mace.hitbox_radius)


func test_equip_null_keeps_the_current_weapon() -> void:
	var player := _make_player()
	player.equip_weapon(null)
	assert_eq(player.weapon.id, &"sword")


func test_weapon_slows_the_player_while_attacking() -> void:
	var player := _make_player()
	var spear := WeaponData.load_by_id(&"spear")
	player.equip_weapon(spear)
	assert_eq(player._move_speed_factor(), 1.0)
	player._try_attack()
	assert_eq(player._move_speed_factor(), spear.move_speed_while_attacking)
	player._update_attack(spear.windup + 0.001)
	assert_eq(player._move_speed_factor(), spear.move_speed_while_attacking, "también durante el golpe")
	player._update_attack(spear.active_time + 0.001)
	assert_eq(player._move_speed_factor(), 1.0)


func test_weapon_knockback_scales_the_enemy_knockback() -> void:
	var player := _make_player()
	var spear := WeaponData.load_by_id(&"spear")
	player.equip_weapon(spear)
	var enemy := _make_enemy()
	enemy.global_position = Vector2(20, 0)
	player._on_hitbox_touched(enemy)
	var expected: float = 2.0 * enemy.knockback_distance * spear.knockback / WeaponData.BASE_KNOCKBACK \
			/ EnemyBase.KNOCKBACK_TIME
	assert_true(absf(enemy._knockback.length() - expected) < 0.01,
			"retroceso %.2f en vez de %.2f" % [enemy._knockback.length(), expected])
	assert_true(enemy._knockback.x > 0.0, "lejos del jugador")
	assert_eq(enemy.hit_knockback_distance(), enemy.knockback_distance, "fuera del golpe vuelve a 1")


func test_sword_knockback_is_the_enemy_own_distance() -> void:
	var player := _make_player()
	var enemy := _make_enemy()
	enemy.global_position = Vector2(20, 0)
	player._on_hitbox_touched(enemy)
	var expected: float = 2.0 * enemy.knockback_distance / EnemyBase.KNOCKBACK_TIME
	assert_true(absf(enemy._knockback.length() - expected) < 0.01)


func test_non_piercing_weapon_hits_only_the_first_target() -> void:
	var player := _make_player()
	var narrow: WeaponData = WeaponData.load_by_id(&"sword").duplicate()
	narrow.pierce = false
	player.equip_weapon(narrow)
	var first := HitCounter.new()
	var second := HitCounter.new()
	_add_to_tree(first)
	_add_to_tree(second)
	player._on_hitbox_touched(first)
	player._on_hitbox_touched(second)
	assert_eq([first.hits, second.hits], [1, 0])


func test_weapon_points_where_the_player_faces() -> void:
	var player := _make_player()
	player.facing = Vector2.LEFT
	player.sprite.flip_h = true
	player._aim_weapon()
	assert_true(absf(absf(player.weapon_pivot.rotation) - PI) < 0.001)
	assert_eq(player.weapon_pivot.scale.y, -1.0, "reflejado: el arma no queda boca abajo")
	player.facing = Vector2.UP
	player._aim_weapon()
	assert_eq(player.held.z_index, -1, "mirando hacia arriba el arma va detrás")


func test_every_weapon_resource_loads() -> void:
	for weapon_id in DirAccess.get_directories_at(WEAPONS_DIR):
		var weapon := WeaponData.load_by_id(StringName(weapon_id))
		assert_true(weapon != null, "%s.tres carga" % weapon_id)
		if weapon == null:
			continue
		assert_eq(weapon.id, StringName(weapon_id))
		assert_true(weapon.held_texture != null, "%s tiene sprite en la mano" % weapon_id)
		assert_true(weapon.effect_frames != null and weapon.effect_frames.has_animation(&"default"),
				"%s tiene estela" % weapon_id)
	assert_eq(WeaponData.load_by_id(&"no_existe"), null)


# ----- estado de la partida -----

func test_new_run_starts_with_the_sword() -> void:
	assert_eq(_game.weapon_id, WeaponData.STARTING_ID)
	assert_eq(WeaponData.STARTING_ID, &"sword")


func test_weapon_survives_levels_and_resets_with_a_new_run() -> void:
	_game.weapon_id = &"dagger"
	_game.complete_level()
	_game.start_level()
	assert_eq(_game.weapon_id, &"dagger", "se conserva entre niveles")
	_game.retry()
	assert_eq(_game.weapon_id, &"sword", "Reintentar empieza con la espada")
	_game.weapon_id = &"spear"
	_game.start_test_run(10)
	assert_eq(_game.weapon_id, &"sword", "la partida de prueba también")


func test_level_gives_the_run_weapon_to_the_player() -> void:
	# Lo que hace Level._ready con Game.weapon_id.
	var player := _make_player()
	player.equip_weapon(WeaponData.load_by_id(&"dagger"))
	assert_eq(player.weapon.id, &"dagger")
	player._try_attack()
	assert_eq(player._cooldown_left, WeaponData.load_by_id(&"dagger").cooldown / player.attack_speed)


# ----- ayudas -----

func _make_player() -> CharacterBody2D:
	var player: CharacterBody2D = PLAYER_RIG.make_player()
	_add_to_tree(player)
	return player


## Enemigo base sin esquiva, armado con el script como en test_enemy_dodge.
func _make_enemy() -> EnemyBase:
	var source: Node = track(ResourceLoader.load("res://scenes/Vampire.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate())
	var enemy: EnemyBase = ENEMY_BASE_SCRIPT.new()
	enemy.dodge_chance = 0.0
	enemy.max_health = 5
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
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
