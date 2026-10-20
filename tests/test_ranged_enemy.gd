@tool
extends McpTestSuite
## Pruebas de los enemigos a distancia (RangedEnemy): el esqueleto arquero, la
## torre de calaveras y el mago del orbe. Las escenas traen sus animaciones y un
## aviso de al menos 600 ms; la máquina de estados detecta, guarda distancia,
## dispara con el enfriamiento listo, apunta hasta aim_lock_frame y suelta un
## solo proyectil en release_frame; un golpe cancela el disparo.

const RANGED_SCRIPT := preload("res://scripts/ranged_enemy.gd")
const SCENES := ["res://scenes/Archer.tscn", "res://scenes/SkullTurret.tscn", "res://scenes/Mage.tscn"]
## Aviso mínimo de un ataque dirigido al jugador (sección 6.1 de la biblia).
const MIN_WARNING := 0.6
## Propiedades de la escena que se copian al enemigo armado a mano.
const COPIED_PROPERTIES := [
	"max_health", "speed", "contact_damage", "knockback_distance", "dodge_chance",
	"dodge_distance", "move_animation", "detect_radius", "lose_radius",
	"retreat_distance", "approach_distance", "attack_animation", "attack_range",
	"aim_lock_frame", "release_frame", "attack_cooldown", "projectile_scene",
	"projectile_offset", "show_aim_line",
]


## Jugador falso: cuenta el daño recibido.
class TargetStub:
	extends Node2D
	var damage_taken := 0

	func take_damage(amount: int, _from_position: Vector2 = Vector2.INF, _source: StringName = &"") -> void:
		damage_taken += amount


func suite_name() -> String:
	return "ranged_enemy"


func test_scenes_have_animations_and_projectile() -> void:
	for path: String in SCENES:
		var enemy: Node = track(_load_fresh(path).instantiate())
		var sprite: AnimatedSprite2D = enemy.get_node("AnimatedSprite2D")
		var frames := sprite.sprite_frames
		assert_eq(sprite.offset, Vector2(0, -5), "offset del sprite de %s" % path)
		for animation in [&"idle", &"walk", &"attack", &"hurt", &"death"]:
			assert_true(frames.has_animation(animation), "%s: falta %s" % [path, animation])
		for animation in [&"attack", &"hurt", &"death"]:
			assert_false(frames.get_animation_loop(animation), "%s: %s no debe repetirse" % [path, animation])
		var count := frames.get_frame_count(enemy.attack_animation)
		assert_true(enemy.aim_lock_frame < enemy.release_frame, "%s: apunta antes de soltar" % path)
		assert_true(enemy.release_frame < count, "%s: el frame de disparo existe" % path)
		assert_true(enemy.projectile_scene != null, "%s: sin proyectil" % path)
		var projectile: Node = track(enemy.projectile_scene.instantiate())
		assert_true(projectile is Projectile, "%s: el proyectil es un Projectile" % path)


func test_scenes_warn_at_least_600_ms_before_firing() -> void:
	for path: String in SCENES:
		var enemy: Node = track(_load_fresh(path).instantiate())
		var frames: SpriteFrames = enemy.get_node("AnimatedSprite2D").sprite_frames
		var warning := _time_until_frame(frames, enemy.attack_animation, enemy.release_frame)
		assert_true(warning >= MIN_WARNING - 0.001,
				"%s: aviso de %d ms" % [path, roundi(warning * 1000.0)])
		# Fija la dirección al menos 150 ms antes de soltar.
		var locked := warning - _time_until_frame(frames, enemy.attack_animation, enemy.aim_lock_frame)
		assert_true(locked >= 0.15 - 0.001, "%s: fija la dirección %d ms antes" % [path, roundi(locked * 1000.0)])


func test_stays_idle_when_player_is_far() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(300, 0))
	assert_eq(archer._get_move_velocity(0.016), Vector2.ZERO)
	assert_eq(archer._state, RangedEnemy.State.IDLE)
	assert_false(archer.is_alerted())


func test_keeps_its_distance_while_reloading() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(30, 0))
	archer._cooldown_left = 10.0
	var away := archer._get_move_velocity(0.016)
	assert_eq(archer._state, RangedEnemy.State.ALERT)
	assert_eq(away, Vector2.LEFT * archer.speed, "demasiado cerca: se aleja")
	archer._player.position = Vector2(archer.approach_distance + 10.0, 0)
	assert_eq(archer._get_move_velocity(0.016), Vector2.RIGHT * archer.speed, "lejos: se acerca")
	archer._player.position = Vector2(90, 0)
	assert_eq(archer._get_move_velocity(0.016), Vector2.ZERO, "a buena distancia: se queda")


func test_loses_the_player_past_lose_radius() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(90, 0))
	archer._cooldown_left = 10.0
	archer._get_move_velocity(0.016)
	assert_true(archer.is_alerted())
	archer._player.position = Vector2(archer.lose_radius + 10.0, 0)
	archer._get_move_velocity(0.016)
	assert_eq(archer._state, RangedEnemy.State.IDLE)
	assert_false(archer.is_alerted())


func test_attacks_when_ready_and_in_range() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(90, 0))
	assert_eq(archer._get_move_velocity(0.016), Vector2.ZERO)
	assert_eq(archer._state, RangedEnemy.State.ATTACK)
	assert_eq(archer.sprite.animation, archer.attack_animation)
	assert_true(archer.is_alerted())
	assert_eq(archer._get_move_velocity(0.016), Vector2.ZERO, "disparando no se mueve")


func test_aims_until_lock_frame_then_fires_once_in_locked_direction() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(90, 0))
	archer._get_move_velocity(0.016)
	# Antes de fijar la dirección sigue al jugador.
	archer._player.position = Vector2(0, 90)
	archer._get_move_velocity(0.016)
	archer.sprite.frame = archer.aim_lock_frame
	var locked: Vector2 = (archer._player.global_position - archer.projectile_spawn_position()).normalized()
	_assert_vec_close(archer._aim_direction, locked, "apunta a donde estaba el jugador al fijar")
	# Después ya no: el jugador puede salirse de la línea.
	archer._player.position = Vector2(-90, 0)
	archer._get_move_velocity(0.016)
	_assert_vec_close(archer._aim_direction, locked, "la dirección ya no cambia")
	assert_eq(_projectiles(archer).size(), 0, "todavía no disparó")

	archer.sprite.frame = archer.release_frame
	var shots := _projectiles(archer)
	assert_eq(shots.size(), 1, "un proyectil en el frame de disparo")
	_assert_vec_close(shots[0].direction, locked, "vuela en la dirección fijada")
	archer.sprite.frame = archer.release_frame + 1
	assert_eq(_projectiles(archer).size(), 1, "un solo proyectil por disparo")


func test_projectile_leaves_from_the_flipped_offset() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(-90, 0))
	archer._get_move_velocity(0.016)
	assert_true(archer.sprite.flip_h, "mira hacia el jugador, a la izquierda")
	archer.sprite.frame = archer.release_frame
	var shot: Projectile = _projectiles(archer)[0]
	var expected := archer.global_position + Vector2(-archer.projectile_offset.x, archer.projectile_offset.y)
	_assert_vec_close(shot.global_position, expected, "sale del lado del arco")


func test_end_of_attack_starts_cooldown() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(90, 0))
	archer._get_move_velocity(0.016)
	archer.sprite.frame = archer.release_frame
	archer._on_animation_finished()
	assert_eq(archer._state, RangedEnemy.State.ALERT)
	_assert_close(archer._cooldown_left, archer.attack_cooldown, "enfriamiento")
	archer._get_move_velocity(0.016)
	assert_eq(archer._state, RangedEnemy.State.ALERT, "en enfriamiento no vuelve a disparar")


func test_hit_cancels_the_shot() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(90, 0))
	archer._get_move_velocity(0.016)
	archer._receive_hit(1, archer._player.global_position)
	assert_false(archer.is_dying)
	assert_eq(archer._state, RangedEnemy.State.ALERT)
	_assert_close(archer._cooldown_left, archer.attack_cooldown, "enfriamiento tras el golpe")
	assert_false(archer._aim_line.visible, "la línea de apuntado se oculta")
	archer.sprite.frame = mini(archer.release_frame, archer.sprite.sprite_frames.get_frame_count(&"hurt") - 1)
	assert_eq(_projectiles(archer).size(), 0, "un disparo cancelado no suelta el proyectil")


func test_does_not_dodge_while_attacking() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(90, 0))
	archer.dodge_chance = 1.0
	archer._get_move_velocity(0.016)
	assert_false(archer.try_dodge(Vector2.ZERO, 0.0), "disparando no esquiva")
	archer._end_attack()
	assert_true(archer.try_dodge(Vector2.ZERO, 0.0), "fuera del disparo sí")


func test_aim_line_shows_only_while_aiming() -> void:
	var archer := _make("res://scenes/Archer.tscn", Vector2(90, 0))
	assert_false(archer._aim_line.visible)
	archer._get_move_velocity(0.016)
	assert_true(archer._aim_line.visible, "aviso: línea hacia el jugador")
	archer.sprite.frame = archer.release_frame
	assert_false(archer._aim_line.visible, "desaparece al soltar la flecha")


func test_turret_never_moves() -> void:
	var turret := _make("res://scenes/SkullTurret.tscn", Vector2(20, 0))
	assert_eq(turret.speed, 0.0)
	assert_eq(turret.knockback_distance, 0.0, "los golpes no la empujan")
	assert_eq(turret.contact_damage, 0, "solo lastima con sus orbes")
	turret._cooldown_left = 10.0
	assert_eq(turret._get_move_velocity(0.016), Vector2.ZERO, "aunque el jugador esté encima")
	turret._player.position = Vector2(-60, 0)
	assert_eq(turret._get_move_velocity(0.016), Vector2.ZERO)
	assert_true(turret.sprite.flip_h, "gira hacia el jugador")


func test_turret_and_mage_fire_their_orbs() -> void:
	for path: String in ["res://scenes/SkullTurret.tscn", "res://scenes/Mage.tscn"]:
		var enemy := _make(path, Vector2(80, 0))
		enemy._get_move_velocity(0.016)
		assert_eq(enemy._state, RangedEnemy.State.ATTACK, path)
		enemy.sprite.frame = enemy.release_frame
		var shots := _projectiles(enemy)
		assert_eq(shots.size(), 1, "%s dispara un orbe" % path)
	var mage := _make("res://scenes/Mage.tscn", Vector2(80, 0))
	mage._get_move_velocity(0.016)
	mage.sprite.frame = mage.release_frame
	assert_true(_projectiles(mage)[0].reflectable, "el orbe del mago se puede devolver")


# ----- ayudas -----

## Escena leída desde el disco y no desde la caché del editor.
func _load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Segundos desde el inicio de la animación hasta que empieza frame.
func _time_until_frame(frames: SpriteFrames, animation: StringName, frame: int) -> float:
	var total := 0.0
	for i in frame:
		total += frames.get_frame_duration(animation, i)
	return total / frames.get_animation_speed(animation)


## Enemigo armado a mano con el script y los datos de la escena. Se crea con
## el script (no con la escena) porque en el editor un script que no es @tool
## solo corre si se instancia así. Va dentro de un contenedor, donde también
## aparecen sus proyectiles.
func _make(scene_path: String, player_at: Vector2) -> RangedEnemy:
	var source: Node = track(_load_fresh(scene_path).instantiate())
	var enemy: RangedEnemy = RANGED_SCRIPT.new()
	for property: String in COPIED_PROPERTIES:
		enemy.set(property, source.get(property))
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
	var container := Node2D.new()
	_add_to_tree(container)
	container.add_child(enemy)
	var target := TargetStub.new()
	target.position = player_at
	_add_to_tree(target)
	enemy._player = target
	return enemy


func _projectiles(enemy: Node) -> Array[Projectile]:
	var out: Array[Projectile] = []
	for child in enemy.get_parent().get_children():
		if child is Projectile and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _add_to_tree(node: Node) -> void:
	track(node)
	(Engine.get_main_loop() as SceneTree).root.add_child(node)


func _assert_close(actual: float, expected: float, msg: String = "") -> void:
	assert_true(absf(actual - expected) < 0.0001, "%s: %.4f, se esperaba %.4f" % [msg, actual, expected])


func _assert_vec_close(actual: Vector2, expected: Vector2, msg: String = "") -> void:
	assert_true(actual.distance_to(expected) < 0.001, "%s: %s, se esperaba %s" % [msg, actual, expected])
