@tool
extends RefCounted
## Ayudas para las pruebas de los jefes (como player_rig.gd). Arma un jefe con
## su script y los datos de su escena, dentro de un nivel falso (Node2D) donde
## caen sus efectos, con un jugador falso que cuenta el daño. En el editor un
## script que no es @tool solo corre si se instancia con el script y no con la
## escena (ver test_skull_enemy.gd).
##
## Uso:
##   const BossRig := preload("res://tests/boss_rig.gd")
##   var boss: ForgeBoss = BossRig.make_boss(self, FORGE_SCRIPT, FORGE_SCENE, Vector2(30, 0))
##   var player: BossRig.TargetStub = boss._player


## Jugador falso: posición, daño recibido y frenos (apply_slow).
class TargetStub:
	extends Node2D
	var damage_taken := 0
	var slow_calls := 0
	var last_slow_factor := 1.0

	func take_damage(amount: int, _from_position: Vector2 = Vector2.INF, _source: StringName = &"") -> void:
		damage_taken += amount

	func apply_slow(factor: float, _duration: float, _color: Color = Color.WHITE) -> void:
		slow_calls += 1
		last_slow_factor = factor


## Escena leída desde el disco y no desde la caché del editor.
static func load_fresh(path: String) -> PackedScene:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


## Jefe armado con script y los valores exportados de la escena en scene_path
## (vida, velocidad, radios, escenas de efectos...), con el sprite de la escena,
## un cuerpo y un ContactArea vacíos. Queda en un nivel falso (el padre, un
## Node2D en la raíz) en boss_at, con un TargetStub en player_at como jugador.
## Todo queda rastreado por suite y se libera al terminar la prueba.
static func make_boss(suite: McpTestSuite, script: Script, scene_path: String,
		player_at: Vector2, boss_at: Vector2 = Vector2.ZERO) -> BossBase:
	var source: Node = suite.track(load_fresh(scene_path).instantiate())
	var boss: BossBase = script.new()
	copy_exported(source, boss)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	boss.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	boss.add_child(shape)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	boss.add_child(contact)
	boss.position = boss_at

	var level := make_level(suite)
	level.add_child(boss)
	var target := TargetStub.new()
	target.position = player_at
	level.add_child(target)
	boss._player = target
	# Sorteos repetibles (posición de las brasas, ángulo de los charcos).
	boss._rng.seed = 1234
	return boss


## Nivel falso: un Node2D en la raíz del árbol, rastreado por suite.
static func make_level(suite: McpTestSuite) -> Node2D:
	var level := Node2D.new()
	level.name = "FakeLevel"
	suite.track(level)
	(Engine.get_main_loop() as SceneTree).root.add_child(level)
	return level


## Efecto armado con el script de BossHazard y los datos de la escena en
## scene_path, en at dentro de un nivel falso, apuntando a target.
static func make_hazard(suite: McpTestSuite, scene_path: String, target: Node2D,
		at: Vector2 = Vector2.ZERO) -> BossHazard:
	var source: Node = suite.track(load_fresh(scene_path).instantiate())
	var hazard: BossHazard = load("res://scripts/bosses/boss_hazard.gd").new()
	copy_exported(source, hazard)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	hazard.add_child(sprite)
	hazard.position = at
	hazard.target = target
	make_level(suite).add_child(hazard)
	return hazard


## Copia las variables exportadas (las que guarda la escena) de from a to.
static func copy_exported(from: Object, to: Object) -> void:
	for property in from.get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			to.set(property["name"], from.get(property["name"]))


## Lleva el sprite del jefe hasta frame (emite frame_changed en cada uno).
static func play_until(boss: BossBase, frame: int) -> void:
	for i in range(boss.sprite.frame + 1, frame + 1):
		boss.sprite.frame = i


## Termina la animación actual como si hubiera llegado al final.
static func finish_animation(boss: BossBase) -> void:
	play_until(boss, boss.sprite.sprite_frames.get_frame_count(boss.sprite.animation) - 1)
	boss._on_animation_finished()


## Efectos vivos del jefe creados desde scene (por su ruta).
static func spawned_from(boss: BossBase, scene: PackedScene) -> Array[Node]:
	var out: Array[Node] = []
	for node in boss.spawned_alive():
		if node.scene_file_path == scene.resource_path:
			out.append(node)
	return out
