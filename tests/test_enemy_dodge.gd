@tool
extends McpTestSuite
## Pruebas de la esquiva de los enemigos (EnemyBase.try_dodge): la decisión
## pura (should_dodge), que esquivar evita el daño, el enfriamiento que impide
## dos esquivas seguidas, las ventanas en que no se puede esquivar, la señal
## dodged, los valores de cada escena y que la espada del jugador no vuelve a
## golpear en el mismo tajo al enemigo que esquivó.

const ENEMY_BASE_SCRIPT := preload("res://scripts/enemy_base.gd")
const CHASER_SCRIPT := preload("res://scripts/chaser_enemy.gd")
const SKULL_SCRIPT := preload("res://scripts/skull_enemy.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")

## Esquiva de cada escena.
const DODGE_BY_SCENE := {
	"res://scenes/Skeleton.tscn": 0.15,
	"res://scenes/Skull.tscn": 0.10,
	"res://scenes/Vampire.tscn": 0.20,
	"res://scenes/Reaper.tscn": 0.10,
	"res://scenes/Archer.tscn": 0.15,
	"res://scenes/SkullTurret.tscn": 0.0,
	"res://scenes/Mimic.tscn": 0.10,
	"res://scenes/Mage.tscn": 0.15,
}

## Tirada que siempre esquiva con chance > 0 y que nunca lo hace con chance 0.
const LOW_ROLL := 0.0


## Cuenta los take_hit que recibe, para la prueba de la hitbox del jugador.
class HitCounter:
	extends Node2D
	var hits := 0

	func take_hit(_amount: int, _from_position: Vector2) -> void:
		hits += 1


func suite_name() -> String:
	return "enemy_dodge"


func test_should_dodge_compares_roll_with_chance() -> void:
	assert_true(EnemyBase.should_dodge(0.15, 0.0))
	assert_true(EnemyBase.should_dodge(0.15, 0.149))
	assert_false(EnemyBase.should_dodge(0.15, 0.15), "el límite no esquiva")
	assert_false(EnemyBase.should_dodge(0.15, 0.99))


func test_should_dodge_extremes() -> void:
	assert_true(EnemyBase.should_dodge(1.0, 1.0), "con probabilidad 1 esquiva siempre")
	assert_true(EnemyBase.should_dodge(1.0, 0.0))
	assert_false(EnemyBase.should_dodge(0.0, 0.0), "con probabilidad 0 nunca esquiva")
	assert_false(EnemyBase.should_dodge(0.0, 1.0))


func test_dodge_rate_is_close_to_chance_with_seeded_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var dodges := 0
	var rolls := 10000
	for i in rolls:
		if EnemyBase.should_dodge(0.2, rng.randf()):
			dodges += 1
	var rate := float(dodges) / rolls
	assert_true(absf(rate - 0.2) < 0.02, "tasa observada %.3f" % rate)


func test_dodge_prevents_damage_and_pushes_away() -> void:
	var enemy := _make_enemy(ENEMY_BASE_SCRIPT)
	enemy.dodge_chance = 1.0
	var emitted: Array[EnemyBase] = []
	enemy.dodged.connect(func(e: EnemyBase) -> void: emitted.append(e))
	enemy.take_hit(1, enemy.global_position + Vector2(-10, 0))
	assert_eq(enemy.health, enemy.max_health, "esquivar no quita vida")
	assert_false(enemy._is_hurt, "esquivar no aturde")
	assert_ne(enemy.sprite.animation, enemy.hurt_animation, "no reproduce la animación de golpe")
	assert_true(enemy._knockback_left > 0.0, "da un paso atrás")
	assert_true(enemy._knockback.x > 0.0, "se aleja del golpe")
	assert_eq(emitted, [enemy], "avisa con dodged")


func test_failed_roll_takes_the_hit() -> void:
	var enemy := _make_enemy(ENEMY_BASE_SCRIPT)
	enemy.dodge_chance = 0.5
	assert_false(enemy.try_dodge(Vector2.ZERO, 0.9), "tirada alta no esquiva")
	enemy.dodge_chance = 0.0
	enemy.take_hit(1, Vector2(-10, 0))
	assert_eq(enemy.health, enemy.max_health - 1, "sin esquiva recibe el golpe")
	assert_true(enemy._is_hurt)


func test_cooldown_prevents_a_second_consecutive_dodge() -> void:
	var enemy := _make_enemy(ENEMY_BASE_SCRIPT)
	enemy.dodge_chance = 1.0
	enemy.max_health = 3
	enemy.health = 3
	enemy.take_hit(1, Vector2(-10, 0))
	assert_eq(enemy.health, 3, "el primero lo esquiva")
	enemy.take_hit(1, Vector2(-10, 0))
	assert_eq(enemy.health, 2, "el segundo seguido lo recibe aunque la probabilidad sea 1")
	# Pasado el enfriamiento (y el aturdimiento del golpe) vuelve a poder esquivar.
	enemy._is_hurt = false
	enemy._dodge_cooldown_left = 0.0
	assert_true(enemy.try_dodge(Vector2(-10, 0), LOW_ROLL))


func test_cooldown_wears_off_with_physics_time() -> void:
	var enemy := _make_enemy(ENEMY_BASE_SCRIPT)
	enemy.dodge_chance = 1.0
	assert_true(enemy.try_dodge(Vector2(-10, 0), LOW_ROLL))
	enemy._physics_process(EnemyBase.DODGE_COOLDOWN * 0.5)
	assert_false(enemy.try_dodge(Vector2(-10, 0), LOW_ROLL), "a mitad del enfriamiento no esquiva")
	enemy._physics_process(EnemyBase.DODGE_COOLDOWN * 0.5 + 0.01)
	assert_true(enemy.try_dodge(Vector2(-10, 0), LOW_ROLL), "terminado el enfriamiento vuelve a esquivar")


func test_cannot_dodge_while_dying_or_stunned() -> void:
	var enemy := _make_enemy(ENEMY_BASE_SCRIPT)
	enemy.dodge_chance = 1.0
	enemy._is_hurt = true
	assert_false(enemy.try_dodge(Vector2.ZERO, LOW_ROLL), "aturdido no esquiva")
	enemy._is_hurt = false
	enemy.is_dying = true
	assert_false(enemy.try_dodge(Vector2.ZERO, LOW_ROLL), "muriendo no esquiva")


func test_chaser_does_not_dodge_while_attacking() -> void:
	var vampire: ChaserEnemy = _make_enemy(CHASER_SCRIPT)
	vampire.attack_animation = &"attack"
	vampire.dodge_chance = 1.0
	vampire.max_health = 3
	vampire.health = 3
	vampire._start_attack(Vector2(10, 0))
	vampire.take_hit(1, Vector2(10, 0))
	assert_eq(vampire.health, 2, "comprometido con el ataque recibe el golpe")
	assert_false(vampire._attacking, "el golpe cancela el ataque")


func test_skull_does_not_dodge_while_charging_or_recovering() -> void:
	var skull: SkullEnemy = _make_enemy(SKULL_SCRIPT)
	skull.dodge_chance = 1.0
	skull._enter(SkullEnemy.State.CHARGE, 1.0)
	assert_false(skull.try_dodge(Vector2.ZERO, LOW_ROLL), "embistiendo no esquiva")
	skull._enter(SkullEnemy.State.RECOVER, 1.0)
	assert_false(skull.try_dodge(Vector2.ZERO, LOW_ROLL), "aturdida tras embestir no esquiva")
	skull._enter(SkullEnemy.State.IDLE, 0.0)
	assert_true(skull.try_dodge(Vector2.ZERO, LOW_ROLL), "en reposo sí")


func test_scenes_have_their_dodge_chance() -> void:
	for path: String in DODGE_BY_SCENE:
		var scene: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var enemy: EnemyBase = track(scene.instantiate())
		assert_true(absf(enemy.dodge_chance - DODGE_BY_SCENE[path]) < 0.0001,
				"esquiva de %s: %.2f" % [path, enemy.dodge_chance])
	var plain: EnemyBase = track(ENEMY_BASE_SCRIPT.new())
	assert_true(absf(plain.dodge_chance - 0.15) < 0.0001, "valor por defecto")


func test_player_swing_hits_each_enemy_once() -> void:
	# La espada anota al enemigo antes de golpearlo: si esquiva y sigue dentro
	# de la hitbox durante el tajo, no se vuelve a tirar la esquiva.
	var player := _make_player()
	var target := HitCounter.new()
	_add_to_tree(target)
	player._hit_this_swing.clear()
	player._on_hitbox_touched(target)
	player._on_hitbox_touched(target)
	assert_eq(target.hits, 1, "un solo golpe por tajo")


# ----- ayudas -----

## Enemigo armado con el script y los hijos que espera EnemyBase. Se crea con
## el script (no con la escena) porque en el editor un script que no es @tool
## solo corre si se instancia así.
func _make_enemy(script: GDScript) -> EnemyBase:
	var source: Node = track(ResourceLoader.load("res://scenes/Vampire.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate())
	var enemy: EnemyBase = script.new()
	if enemy is SkullEnemy:
		enemy.move_animation = &"idle"
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


## Jugador armado como en test_player_knockback.
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
	_add_to_tree(player)
	return player


func _add_to_tree(node: Node) -> void:
	track(node)
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
