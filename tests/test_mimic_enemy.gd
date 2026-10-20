@tool
extends McpTestSuite
## Pruebas del cofre mímico: la escena trae sus animaciones (con wake) y un
## mordisco con aviso de al menos 600 ms; disfrazado no se mueve, no lastima ni
## cuenta como alerta; despierta al acercarse el jugador o al recibir un golpe,
## persigue y muerde como un ChaserEnemy, y al perder al jugador se cierra otra
## vez en su puesto.

const MIMIC_SCRIPT := preload("res://scripts/mimic_enemy.gd")
const MIMIC_SCENE := "res://scenes/Mimic.tscn"
const COPIED_PROPERTIES := [
	"max_health", "speed", "contact_damage", "dodge_chance", "detect_radius",
	"lose_radius", "leash_radius", "attack_animation", "attack_range", "attack_reach",
	"attack_hit_frames", "attack_cooldown", "wake_radius", "wake_animation",
]


## Jugador falso: cuenta el daño recibido.
class TargetStub:
	extends Node2D
	var damage_taken := 0

	func take_damage(amount: int, _from_position: Vector2 = Vector2.INF) -> void:
		damage_taken += amount


func suite_name() -> String:
	return "mimic_enemy"


func test_scene_has_wake_and_bite() -> void:
	var mimic: Node = track(_load_fresh(MIMIC_SCENE).instantiate())
	var sprite: AnimatedSprite2D = mimic.get_node("AnimatedSprite2D")
	var frames := sprite.sprite_frames
	assert_eq(sprite.offset, Vector2(0, -5))
	for animation in [&"idle", &"wake", &"walk", &"attack", &"hurt", &"death"]:
		assert_true(frames.has_animation(animation), "falta %s" % animation)
	for animation in [&"wake", &"attack", &"hurt", &"death"]:
		assert_false(frames.get_animation_loop(animation), "%s no debe repetirse" % animation)
	assert_eq(mimic.contact_damage, 0, "solo lastima con el mordisco")
	assert_eq(mimic.attack_hit_frames, Vector2i(4, 5))
	assert_true(mimic.attack_hit_frames.y < frames.get_frame_count(&"attack"), "los frames de impacto existen")
	var warning := 0.0
	for i in mimic.attack_hit_frames.x:
		warning += frames.get_frame_duration(&"attack", i)
	warning /= frames.get_animation_speed(&"attack")
	assert_true(warning >= 0.599, "aviso del mordisco de %d ms" % roundi(warning * 1000.0))


func test_stays_disguised_when_player_is_far() -> void:
	var mimic := _make(Vector2(60, 0))
	assert_eq(mimic._get_move_velocity(0.016), Vector2.ZERO)
	assert_true(mimic.is_dormant())
	assert_false(mimic.is_alerted(), "disfrazado no cambia la música")
	assert_eq(mimic.sprite.animation, &"idle")


func test_does_not_hurt_while_disguised() -> void:
	var mimic := _make(Vector2(60, 0))
	mimic.contact_damage = 1
	# Sin el área de contacto el daño de la base fallaría: que no falle prueba
	# que disfrazado ni siquiera la consulta.
	mimic.contact_area = null
	mimic._damage_touching_bodies()
	assert_true(mimic.is_dormant())


func test_wakes_when_player_comes_close() -> void:
	var mimic := _make(Vector2(mimic_wake_distance() - 4.0, 0))
	assert_eq(mimic._get_move_velocity(0.016), Vector2.ZERO)
	assert_eq(mimic._disguise, MimicEnemy.Disguise.WAKING)
	assert_eq(mimic.sprite.animation, &"wake")
	assert_true(mimic.is_alerted(), "despertando ya está en alerta")
	assert_eq(mimic._get_move_velocity(0.016), Vector2.ZERO, "mientras despierta no se mueve")
	mimic._update_animation()
	assert_eq(mimic.sprite.animation, &"wake", "no se pisa la animación de despertar")


func test_chases_after_waking() -> void:
	var mimic := _make(Vector2(20, 0))
	mimic._get_move_velocity(0.016)
	mimic.sprite.play(&"wake")
	mimic._on_animation_finished()
	assert_eq(mimic._disguise, MimicEnemy.Disguise.AWAKE)
	mimic._player.position = Vector2(60, 0)
	assert_eq(mimic._get_move_velocity(0.016), Vector2.RIGHT * mimic.speed, "persigue al jugador")
	assert_true(mimic.is_alerted())


func test_bites_only_on_strike_frames() -> void:
	var mimic := _make(Vector2(12, 0))
	mimic._disguise = MimicEnemy.Disguise.AWAKE
	mimic._chasing = true
	mimic._get_move_velocity(0.016)
	assert_true(mimic._attacking, "a menos de attack_range muerde")
	for frame in mimic.attack_hit_frames.x:
		mimic.sprite.frame = frame
	assert_eq(mimic._player.damage_taken, 0, "la anticipación no lastima")
	mimic.sprite.frame = mimic.attack_hit_frames.x
	assert_eq(mimic._player.damage_taken, 1)
	mimic.sprite.frame = mimic.attack_hit_frames.y
	assert_eq(mimic._player.damage_taken, 1, "una vez por mordisco")


func test_hit_while_disguised_wakes_it_and_cannot_be_dodged() -> void:
	var mimic := _make(Vector2(60, 0))
	mimic.dodge_chance = 1.0
	var health_before := mimic.health
	mimic.take_hit(1, mimic._player.global_position)
	assert_eq(mimic.health, health_before - 1, "disfrazado no esquiva")
	assert_eq(mimic._disguise, MimicEnemy.Disguise.AWAKE)
	assert_true(mimic.is_alerted())


func test_closes_again_when_back_home_without_player() -> void:
	var mimic := _make(Vector2(20, 0))
	mimic._disguise = MimicEnemy.Disguise.AWAKE
	mimic._player.position = Vector2(mimic.lose_radius + 50.0, 0)
	assert_eq(mimic._get_move_velocity(0.016), Vector2.ZERO, "ya está en su puesto")
	assert_true(mimic.is_dormant(), "vuelve a ser un cofre")
	assert_false(mimic.is_alerted())


# ----- ayudas -----

func mimic_wake_distance() -> float:
	var mimic: Node = track(_load_fresh(MIMIC_SCENE).instantiate())
	return mimic.wake_radius


func _load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Mímico armado a mano con el script y los datos de la escena (ver
## test_skull_enemy.gd: en el editor un script que no es @tool solo corre así).
func _make(player_at: Vector2) -> MimicEnemy:
	var source: Node = track(_load_fresh(MIMIC_SCENE).instantiate())
	var mimic: MimicEnemy = MIMIC_SCRIPT.new()
	for property: String in COPIED_PROPERTIES:
		mimic.set(property, source.get(property))
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	mimic.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	mimic.add_child(shape)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	mimic.add_child(contact)
	_add_to_tree(mimic)
	var target := TargetStub.new()
	target.position = player_at
	_add_to_tree(target)
	mimic._player = target
	return mimic


func _add_to_tree(node: Node) -> void:
	track(node)
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
