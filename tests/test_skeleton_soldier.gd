@tool
extends McpTestSuite
## Pruebas del esqueleto soldado: la escena trae la estocada (9 frames, sin
## loop, impacto en los frames 6-7), patrulla sin el jugador cerca, lo enfrenta
## dentro de la zona de su ruta y vuelve a ella al perderlo, la estocada
## lastima solo en los frames de impacto, y el paso de guardia lo aleja y
## retrasa su próximo ataque.

const SKELETON_SCRIPT := preload("res://scripts/skeleton.gd")

## Propiedades de Skeleton.tscn que se copian al esqueleto armado a mano.
const SCENE_PROPERTIES := [
	"max_health", "speed", "contact_damage", "dodge_chance", "detect_radius",
	"lose_radius", "leash_radius", "attack_animation", "attack_range",
	"attack_reach", "attack_damage", "attack_hit_frames", "attack_cooldown",
	"guard_step_distance", "guard_attack_delay",
]
## Ruta de las pruebas: del origen 64 px a la derecha.
const PATROL := Vector2(64, 0)


## Jugador falso: cuenta el daño recibido.
class TargetStub:
	extends Node2D
	var damage_taken := 0

	func take_damage(amount: int, _from_position: Vector2 = Vector2.INF, _source: StringName = &"") -> void:
		damage_taken += amount


func suite_name() -> String:
	return "skeleton_soldier"


func test_scene_has_a_telegraphed_sword_attack() -> void:
	var skeleton: Node = track(_load_fresh("res://scenes/Skeleton.tscn").instantiate())
	assert_true(skeleton is ChaserEnemy, "el esqueleto reutiliza el ataque de ChaserEnemy")
	assert_eq(skeleton.attack_animation, &"attack")
	assert_eq(skeleton.contact_damage, 0, "solo lastima con la estocada")
	assert_eq(skeleton.attack_damage, 1, "el daño de los enemigos no escala")
	assert_eq(skeleton.attack_hit_frames, Vector2i(6, 7))
	var frames: SpriteFrames = skeleton.get_node("AnimatedSprite2D").sprite_frames
	assert_eq(frames.get_frame_count(&"attack"), 9)
	assert_false(frames.get_animation_loop(&"attack"), "el ataque no debe repetirse solo")
	assert_true(skeleton.attack_hit_frames.y < frames.get_frame_count(&"attack"))
	# Anticipación: los frames antes del impacto duran al menos 0.6 s.
	var windup := 0.0
	for frame in skeleton.attack_hit_frames.x:
		windup += frames.get_frame_duration(&"attack", frame)
	windup /= frames.get_animation_speed(&"attack")
	assert_true(windup >= 0.6, "anticipación de %.2f s" % windup)


func test_patrols_while_the_player_is_far() -> void:
	var skeleton := _make_skeleton(PATROL)
	var target := _make_target(Vector2(0, 300))
	skeleton._player = target
	assert_eq(skeleton._get_move_velocity(0.016), Vector2.RIGHT * skeleton.speed, "va hacia el otro extremo")
	assert_false(skeleton.is_alerted())


func test_engages_the_player_and_returns_to_its_route() -> void:
	var skeleton := _make_skeleton(PATROL)
	var target := _make_target(Vector2(0, 40))
	skeleton._player = target
	assert_eq(skeleton._get_move_velocity(0.016), Vector2.DOWN * skeleton.speed, "deja la ruta y va hacia él")
	assert_true(skeleton.is_alerted())

	# Simula que se alejó de la ruta persiguiéndolo y que el jugador se escapó.
	skeleton.global_position = Vector2(20, 30)
	target.position = Vector2(20, 30 + skeleton.lose_radius + 10.0)
	var back := skeleton._get_move_velocity(0.016)
	assert_false(skeleton.is_alerted(), "lo perdió")
	assert_true(back.is_equal_approx(skeleton.global_position.direction_to(PATROL) * skeleton.speed),
			"vuelve a la ruta")


func test_does_not_leave_its_zone() -> void:
	var skeleton := _make_skeleton(PATROL)
	# Cerca del esqueleto pero a más de leash_radius de la ruta: no lo sigue.
	var target := _make_target(Vector2(0, -(skeleton.leash_radius + 4.0)))
	skeleton._player = target
	assert_true(target.position.length() < skeleton.detect_radius, "la prueba debe estar dentro de la detección")
	skeleton._get_move_velocity(0.016)
	assert_false(skeleton.is_alerted(), "fuera de su zona no lo persigue")
	target.position = Vector2(0, -(skeleton.leash_radius - 4.0))
	skeleton._get_move_velocity(0.016)
	assert_true(skeleton.is_alerted(), "dentro de su zona sí")


func test_zone_is_the_whole_route() -> void:
	var skeleton := _make_skeleton(PATROL)
	assert_true(is_equal_approx(skeleton._distance_to_zone(Vector2(32, -20)), 20.0), "al costado del tramo")
	assert_true(is_equal_approx(skeleton._distance_to_zone(Vector2(100, 0)), 36.0), "pasado el extremo")
	assert_true(is_equal_approx(skeleton._distance_to_zone(Vector2(-10, 0)), 10.0), "antes del puesto")


func test_stationary_skeleton_guards_its_post() -> void:
	var skeleton := _make_skeleton(Vector2.ZERO)
	skeleton._player = _make_target(Vector2(0, 300))
	assert_eq(skeleton._get_move_velocity(0.016), Vector2.ZERO, "sin ruta espera en su puesto")


func test_attacks_when_in_range() -> void:
	var skeleton := _make_skeleton(PATROL)
	var target := _make_target(Vector2(skeleton.attack_range - 4.0, 0))
	skeleton._player = target
	assert_eq(skeleton._get_move_velocity(0.016), Vector2.ZERO, "se detiene para atacar")
	assert_true(skeleton._attacking)
	assert_eq(skeleton.sprite.animation, &"attack")


func test_thrust_hurts_only_on_impact_frames_and_once() -> void:
	var skeleton := _make_skeleton(PATROL)
	var target := _make_target(Vector2(12, 0))
	skeleton._player = target
	skeleton._start_attack(target.global_position)
	for frame in range(0, skeleton.attack_hit_frames.x):
		skeleton.sprite.frame = frame
	assert_eq(target.damage_taken, 0, "la anticipación no lastima")
	skeleton.sprite.frame = skeleton.attack_hit_frames.x
	assert_eq(target.damage_taken, 1, "el primer frame de impacto lastima")
	skeleton.sprite.frame = skeleton.attack_hit_frames.y
	skeleton.sprite.frame = 8
	assert_eq(target.damage_taken, 1, "una sola vez por ataque, y la recuperación no lastima")


func test_thrust_misses_out_of_reach() -> void:
	var skeleton := _make_skeleton(PATROL)
	var target := _make_target(Vector2(skeleton.attack_reach + 10.0, 0))
	skeleton._player = target
	skeleton._start_attack(target.global_position)
	for frame in range(skeleton.attack_hit_frames.x, skeleton.attack_hit_frames.y + 1):
		skeleton.sprite.frame = frame
	assert_eq(target.damage_taken, 0, "alejarse a tiempo evita la estocada")


func test_guard_step_opens_distance_and_delays_the_next_attack() -> void:
	var skeleton := _make_skeleton(PATROL)
	skeleton.dodge_chance = 0.0
	skeleton.max_health = 3
	skeleton.health = 3
	skeleton.take_hit(1, Vector2(-10, 0))
	assert_eq(skeleton.health, 2)
	var expected_speed: float = 2.0 * (skeleton.knockback_distance + skeleton.guard_step_distance) / EnemyBase.KNOCKBACK_TIME
	assert_true(is_equal_approx(skeleton._knockback.length(), expected_speed), "retrocede más que el empuje normal")
	assert_true(skeleton._knockback.x > 0.0, "se aleja del golpe")
	assert_eq(skeleton._attack_cooldown_left, skeleton.guard_attack_delay, "retrasa su próximo ataque")
	assert_false(skeleton._can_attack())


func test_lethal_hit_has_no_guard_step() -> void:
	var skeleton := _make_skeleton(PATROL)
	skeleton.dodge_chance = 0.0
	skeleton.health = 1
	skeleton.take_hit(1, Vector2(-10, 0))
	assert_true(skeleton.is_dying)
	assert_eq(skeleton._knockback_left, 0.0, "muerto no retrocede")


# ----- ayudas -----

func _load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Esqueleto armado con el script y los valores y frames reales de
## Skeleton.tscn, en el origen y con la ruta patrol. Se crea con el script (no
## con la escena) porque en el editor un script que no es @tool solo corre si
## se instancia así.
func _make_skeleton(patrol: Vector2) -> ChaserEnemy:
	var source: Node = track(_load_fresh("res://scenes/Skeleton.tscn").instantiate())
	var skeleton: ChaserEnemy = SKELETON_SCRIPT.new()
	for property: String in SCENE_PROPERTIES:
		skeleton.set(property, source.get(property))
	skeleton.set("patrol_offset", patrol)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	skeleton.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	skeleton.add_child(shape)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	skeleton.add_child(contact)
	_add_to_tree(skeleton)
	return skeleton


func _make_target(at: Vector2) -> TargetStub:
	var target := TargetStub.new()
	target.position = at
	_add_to_tree(target)
	return target


func _add_to_tree(node: Node) -> void:
	track(node)
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
