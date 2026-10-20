@tool
extends McpTestSuite
## Pruebas del Guardián musgoso (sección 9.4 de docs/assets-pack/03-jefes.md):
## los números de la escena y los avisos, y la máquina de estados IDLE ->
## CHASE -> ROOTS o SPORES (alterna) -> RECOVER -> CHASE, con la runa de las
## raíces, las nubes y vainas de las esporas, y la curación sobre el musgo de
## la fase 2.

const BossRig := preload("res://tests/boss_rig.gd")
const WARDEN_SCRIPT := preload("res://scripts/bosses/warden_boss.gd")
const POD_SCRIPT := preload("res://scripts/bosses/spore_pod.gd")
const WARDEN_SCENE := "res://scenes/bosses/warden/Warden.tscn"
const ROOT_SPIKE_SCENE := "res://scenes/bosses/warden/RootSpike.tscn"
const SPORE_CLOUD_SCENE := "res://scenes/bosses/warden/SporeCloud.tscn"
const SPORE_POD_SCENE := "res://scenes/bosses/warden/SporePod.tscn"
## Velocidad del jugador, para la regla de aviso de las áreas (6.1).
const PLAYER_SPEED := 80.0
const SEEDS := [1, 7, 42]


func suite_name() -> String:
	return "warden_boss"


# ----- datos -----

func test_scene_uses_the_guide_stats() -> void:
	var warden: Node = track(BossRig.load_fresh(WARDEN_SCENE).instantiate())
	assert_eq(warden.get("boss_id"), &"warden")
	assert_eq(warden.get("display_name"), "Guardián musgoso")
	assert_eq(warden.get("max_health"), 14)
	assert_eq(warden.get("speed"), 18.0)
	assert_eq(warden.get("contact_damage"), 1)
	assert_eq(warden.get("detect_radius"), 110.0)
	assert_eq(warden.get("leash_radius"), 150.0)
	assert_eq(warden.get("roots_cooldown"), 2.5)
	assert_eq(warden.get("roots_recover_time"), 0.75)
	assert_eq(warden.get("root_spread"), 20.0)
	assert_eq(warden.get("rune_bonus_damage"), 1)
	assert_eq(warden.get("spores_cooldown"), 6.0)
	assert_eq(warden.get("spores_recover_time"), 0.5)
	assert_eq(warden.get("spore_clouds"), 2)
	assert_eq(warden.get("spore_slow_factor"), 0.5)
	assert_eq(warden.get("spore_pods"), 2)
	assert_eq(warden.get("spore_pod_distance"), 20.0)
	assert_eq(warden.get("moss_heal_amount"), 1)
	assert_eq(warden.get("moss_heal_interval"), 3.0)

	var pod: Node = track(BossRig.load_fresh(SPORE_POD_SCENE).instantiate())
	assert_eq(pod.get("max_health"), 1, "se rompe con un golpe")
	assert_eq(pod.get("heal_amount"), 2)
	assert_eq(pod.get("bloom_time"), 6.0)
	assert_eq(pod.get("contact_damage"), 0)
	assert_eq(pod.get("dodge_chance"), 0.0)
	assert_eq(pod.get("heart_drop_chance"), 0.0)
	assert_eq(pod.get("coin_drop_chance"), 0.0)
	assert_eq(pod.get("collision_layer"), 4, "la espada la alcanza")


func test_attacks_are_telegraphed_long_enough() -> void:
	var warden: Node = track(BossRig.load_fresh(WARDEN_SCENE).instantiate())
	var frames: SpriteFrames = warden.get_node("AnimatedSprite2D").sprite_frames
	var roots := BossBase.move_windup_seconds(frames, WardenBoss.ROOTS_ANIMATION, WardenBoss.ROOTS_IMPACT_FRAME)
	_assert_close(roots, 0.625, "brazos arriba")
	assert_true(roots >= 0.6, "aviso de un ataque dirigido (6.1)")
	var aim := BossBase.move_windup_seconds(frames, WardenBoss.ROOTS_ANIMATION, WardenBoss.ROOTS_AIM_FRAME)
	_assert_close(aim, 0.375, "la puntería se fija en el frame 3")
	var spores := BossBase.move_windup_seconds(frames, WardenBoss.SPORES_ANIMATION, WardenBoss.SPORES_IMPACT_FRAME)
	_assert_close(spores, 0.5, "setas que se inflan")

	var spike: Node = track(BossRig.load_fresh(ROOT_SPIKE_SCENE).instantiate())
	var spike_sprite: AnimatedSprite2D = spike.get_node("AnimatedSprite2D")
	var spike_active: Vector2i = spike.get("active_frames")
	var crack := BossBase.move_windup_seconds(spike_sprite.sprite_frames, &"default", spike_active.x)
	_assert_close(crack, 0.25, "tierra que se agrieta")
	var spike_radius: float = spike.get("radius")
	# Desde que fija la puntería hasta que pinchan: el resto de la anticipación
	# más la grieta.
	assert_true(roots - aim + crack >= spike_radius / PLAYER_SPEED + 0.25, "r / 80 + 0.25 (6.1)")
	assert_true(roots + crack >= 0.6, "la raíz bajo el jugador avisa más de 600 ms")
	assert_eq(spike_sprite.offset, Vector2(0, -14), "la base (fila 30) sobre el origen")

	var cloud: Node = track(BossRig.load_fresh(SPORE_CLOUD_SCENE).instantiate())
	var cloud_sprite: AnimatedSprite2D = cloud.get_node("AnimatedSprite2D")
	var cloud_active: Vector2i = cloud.get("active_frames")
	var cloud_warning := BossBase.move_windup_seconds(cloud_sprite.sprite_frames, &"default", cloud_active.x) \
			/ cloud_sprite.speed_scale
	var cloud_radius: float = cloud.get("radius")
	assert_eq(cloud_radius, 14.0, "nube de radio 14")
	assert_true(cloud_warning >= cloud_radius / PLAYER_SPEED + 0.25, "la nube crece antes de frenar")
	assert_eq(cloud.get("damage"), 0, "las esporas no lastiman")
	assert_eq(cloud.get("slow_factor"), 0.5)
	assert_true(cloud.get("continuous"))
	assert_eq(cloud.get("lifetime"), 3.0, "la nube dura 3 s")
	var cloud_frames: SpriteFrames = cloud_sprite.sprite_frames
	var cloud_length := cloud_frames.get_frame_count(&"default") / cloud_frames.get_animation_speed(&"default") \
			/ cloud_sprite.speed_scale
	_assert_close(cloud_length, 3.0, "crece, se mantiene y se disipa en sus 3 s")


# ----- persecución -----

func test_waits_in_its_post_until_the_player_comes_close() -> void:
	var warden := _make(Vector2(120, 0))
	assert_eq(warden._get_move_velocity(0.016), Vector2.ZERO)
	assert_eq(warden.get_state(), WardenBoss.State.IDLE)
	assert_false(warden.is_alerted(), "dormido no cambia la música ni muestra la barra")
	warden._player.position = Vector2(100, 0)
	warden._get_move_velocity(0.016)
	assert_eq(warden.get_state(), WardenBoss.State.CHASE)
	assert_true(warden.is_alerted())


func test_chases_slowly_and_a_bit_faster_in_phase_two() -> void:
	var warden := _make(Vector2(100, 0))
	warden._get_move_velocity(0.016)
	warden._roots_cooldown_left = 10.0
	warden._spores_cooldown_left = 10.0
	assert_eq(warden._get_move_velocity(0.016), Vector2.RIGHT * 18.0)
	warden.take_hit(7, Vector2(-10, 0))
	assert_true(warden.is_phase_two())
	warden._is_hurt = false
	assert_eq(warden._get_move_velocity(0.016), Vector2.RIGHT * 22.5, "×1.25 en la fase 2")


func test_goes_back_to_its_post_when_the_player_leaves_the_leash() -> void:
	var warden := _make(Vector2(100, 0), Vector2(50, 0))
	warden.engage()
	warden._get_move_velocity(0.016)
	warden._player.position = Vector2(50 + warden.leash_radius + 10.0, 0)
	warden.position = Vector2(80, 0)
	assert_eq(warden._get_move_velocity(0.016), Vector2.LEFT * 18.0, "vuelve a su puesto")
	assert_true(warden.is_alerted(), "sigue en combate")


# ----- raíces -----

func test_roots_aim_at_frame_three_and_strike_at_the_impact() -> void:
	var warden := _start_roots(Vector2(60, 0))
	assert_eq(warden.sprite.animation, &"attack")
	BossRig.play_until(warden, WardenBoss.ROOTS_AIM_FRAME - 1)
	assert_true(warden.root_targets().is_empty(), "todavía no apuntó")
	BossRig.play_until(warden, WardenBoss.ROOTS_AIM_FRAME)
	var targets := warden.root_targets()
	assert_eq(targets.size(), 3, "debajo del jugador y a los costados")
	for expected: Vector2 in [Vector2(60, 0), Vector2(60, 20), Vector2(60, -20)]:
		assert_true(targets.has(expected), "raíz en %s; hay %s" % [expected, targets])
	# El jugador se mueve después de la puntería: las raíces salen donde apuntó.
	warden._player.position = Vector2(60, 40)
	BossRig.play_until(warden, WardenBoss.ROOTS_IMPACT_FRAME - 1)
	assert_true(warden.spawned_alive().is_empty(), "la anticipación no ataca")
	BossRig.play_until(warden, WardenBoss.ROOTS_IMPACT_FRAME)
	var spikes := BossRig.spawned_from(warden, warden.root_spike_scene)
	assert_eq(spikes.size(), 3, "tres raíces")
	for spike in spikes:
		assert_true(targets.has(spike.global_position), "raíz en %s" % spike.global_position)
	for spike in spikes:
		spike.sprite.frame = 2
	assert_eq(warden._player.damage_taken, 0, "salió de las raíces a tiempo")


func test_root_spike_hits_a_player_who_stays_after_the_crack() -> void:
	var warden := _start_roots(Vector2(60, 0))
	BossRig.play_until(warden, WardenBoss.ROOTS_IMPACT_FRAME)
	assert_eq(warden._player.damage_taken, 0, "la grieta avisa")
	for spike in BossRig.spawned_from(warden, warden.root_spike_scene):
		spike.sprite.frame = 1
	assert_eq(warden._player.damage_taken, 0, "todavía es grieta")
	for spike in BossRig.spawned_from(warden, warden.root_spike_scene):
		spike.sprite.frame = 2
	assert_eq(warden._player.damage_taken, 1, "la raíz de abajo lo pincha una vez")


func test_rune_window_makes_hits_stronger() -> void:
	var warden := _start_roots(Vector2(60, 0))
	BossRig.finish_animation(warden)
	assert_eq(warden.get_state(), WardenBoss.State.RECOVER)
	assert_true(warden.is_vulnerable(), "ventana de castigo")
	assert_true(warden.is_rune_lit(), "la runa brilla")
	assert_eq(warden.modulate, BossBase.VULNERABLE_TINT, "tinte azulado")
	assert_eq(warden._get_move_velocity(0.1), Vector2.ZERO, "no se mueve")
	var before := warden.health
	warden.take_hit(1, Vector2(-10, 0))
	assert_eq(warden.health, before - 2, "golpe de 1 con la runa encendida hace 2")
	assert_false(warden._is_hurt, "en la ventana de castigo no se estremece")
	warden._get_move_velocity(warden.roots_recover_time)
	assert_eq(warden.get_state(), WardenBoss.State.CHASE)
	assert_false(warden.is_rune_lit())
	assert_false(warden.is_vulnerable())
	assert_gt(warden._roots_cooldown_left, 0.0, "las raíces quedan en enfriamiento")
	before = warden.health
	warden.take_hit(1, Vector2(-10, 0))
	assert_eq(warden.health, before - 1, "sin runa, daño normal")


func test_player_hit_does_not_cancel_the_roots() -> void:
	var warden := _start_roots(Vector2(60, 0))
	warden.take_hit(1, Vector2(-10, 0))
	assert_eq(warden.get_state(), WardenBoss.State.ROOTS)
	BossRig.play_until(warden, WardenBoss.ROOTS_IMPACT_FRAME)
	assert_eq(BossRig.spawned_from(warden, warden.root_spike_scene).size(), 3, "las raíces salen igual")


# ----- esporas -----

func test_spores_cloud_the_player_and_drop_pods_beside_the_warden() -> void:
	var warden := _start_spores(Vector2(60, 0))
	BossRig.play_until(warden, WardenBoss.SPORES_IMPACT_FRAME - 1)
	assert_true(warden.spawned_alive().is_empty(), "las setas avisan")
	_spore_impact(warden)
	var clouds := BossRig.spawned_from(warden, warden.spore_cloud_scene)
	assert_eq(clouds.size(), 2, "dos nubes")
	var middle := Vector2.ZERO
	for cloud in clouds:
		_assert_close(cloud.global_position.distance_to(Vector2(60, 0)), warden.spore_cloud_offset, "nube junto al jugador")
		middle += cloud.global_position / clouds.size()
	assert_true(middle.distance_to(Vector2(60, 0)) < 0.01, "repartidas alrededor del jugador")
	var pods := BossRig.spawned_from(warden, warden.spore_pod_scene)
	assert_eq(pods.size(), 2, "dos vainas")
	for pod in pods:
		_assert_close(pod.global_position.distance_to(Vector2.ZERO), 20.0, "vaina a 20 px del jefe")
	assert_true(pods[0].global_position.distance_to(pods[1].global_position) > 30.0, "una a cada lado")
	BossRig.finish_animation(warden)
	assert_eq(warden.get_state(), WardenBoss.State.RECOVER)
	assert_false(warden.is_rune_lit(), "la runa solo brilla después de las raíces")
	warden._get_move_velocity(warden.spores_recover_time)
	assert_eq(warden.get_state(), WardenBoss.State.CHASE)
	assert_gt(warden._spores_cooldown_left, 0.0)


func test_spore_cloud_slows_after_growing_and_never_hurts() -> void:
	var warden := _start_spores(Vector2(60, 0))
	_spore_impact(warden)
	var cloud: BossHazard = BossRig.spawned_from(warden, warden.spore_cloud_scene)[0]
	var player: BossRig.TargetStub = warden._player
	assert_false(cloud.try_strike(), "mientras crece no frena")
	assert_eq(player.slow_calls, 0)
	cloud.sprite.frame = 1
	assert_true(cloud.try_strike())
	assert_gt(player.slow_calls, 0, "frena al jugador")
	_assert_close(player.last_slow_factor, 0.5, "al 50 %")
	assert_eq(player.damage_taken, 0, "las esporas no lastiman")
	player.position = Vector2(200, 0)
	var calls := player.slow_calls
	cloud.try_strike()
	assert_eq(player.slow_calls, calls, "fuera de la nube no frena")


func test_pod_heals_the_warden_if_nobody_breaks_it() -> void:
	var warden := _make(Vector2(300, 0))
	warden.take_hit(4, Vector2(-10, 0))
	assert_eq(warden.health, 10)
	var pod := _make_pod(warden)
	pod._get_move_velocity(5.9)
	assert_eq(warden.health, 10, "todavía no florece")
	var bloomed: Array = []
	pod.bloomed.connect(func(p: SporePod) -> void: bloomed.append(p))
	pod._get_move_velocity(0.2)
	assert_eq(warden.health, 12, "a los 6 s le cura 2")
	assert_eq(bloomed.size(), 1)
	assert_true(pod.is_queued_for_deletion(), "desaparece al florecer")
	pod._get_move_velocity(6.0)
	assert_eq(warden.health, 12, "florece una sola vez")


func test_broken_pod_does_not_heal() -> void:
	var warden := _make(Vector2(300, 0))
	warden.take_hit(4, Vector2(-10, 0))
	var pod := _make_pod(warden)
	pod.take_hit(1, Vector2(-10, 0))
	assert_true(pod.is_dying, "se rompe con un golpe")
	pod._get_move_velocity(7.0)
	assert_eq(warden.health, 10, "rota no cura")
	assert_false(pod.has_bloomed())


func test_pods_avoid_walls() -> void:
	var warden := _make(Vector2(60, 0))
	# Una pared justo donde iría la primera vaina (perpendicular al jugador).
	var wall := StaticBody2D.new()
	wall.collision_layer = WardenBoss.WALL_MASK
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	wall.add_child(shape)
	wall.position = Vector2(0, -20)
	warden.get_parent().add_child(wall)
	assert_false(warden._is_open_floor(Vector2(0, -20)), "la pared ocupa el lugar")
	for at in warden.spore_pod_positions():
		assert_true(warden._is_open_floor(at), "vaina en %s, fuera de la pared" % at)
		_assert_close(at.length(), 20.0, "sigue a 20 px")


func test_alternates_between_roots_and_spores() -> void:
	var warden := _start_roots(Vector2(60, 0))
	assert_eq(warden._next_attack, WardenBoss.Attack.SPORES, "después de las raíces tocan las esporas")
	BossRig.finish_animation(warden)
	warden._get_move_velocity(warden.roots_recover_time)
	warden._get_move_velocity(0.016)
	assert_eq(warden.get_state(), WardenBoss.State.SPORES)
	assert_eq(warden._next_attack, WardenBoss.Attack.ROOTS)
	_spore_impact(warden)
	BossRig.finish_animation(warden)
	warden._get_move_velocity(warden.spores_recover_time)
	warden._roots_cooldown_left = 0.0
	warden._get_move_velocity(0.016)
	assert_eq(warden.get_state(), WardenBoss.State.ROOTS, "y vuelve a las raíces")


func test_uses_spores_when_the_player_is_beyond_root_range() -> void:
	var warden := _make(Vector2(105, 0))
	warden.engage()
	warden._get_move_velocity(0.016)
	assert_true(warden.distance_to_player() > warden.roots_range)
	warden._get_move_velocity(0.016)
	assert_eq(warden.get_state(), WardenBoss.State.SPORES, "aunque tocaban las raíces, suelta esporas")


# ----- fase 2: tierra fértil -----

func test_phase_two_heals_on_a_moss_patch() -> void:
	var warden := _make(Vector2(300, 0))
	assert_true(_patch_nodes().is_empty(), "sin manchas de otras pruebas")
	_add_patch(warden, Vector2(4, 3))
	assert_true(warden.is_on_moss_patch())
	# En la fase 1 el musgo no lo cura.
	warden.take_hit(2, Vector2(-10, 0))
	warden._get_move_velocity(3.1)
	assert_eq(warden.health, 12, "fase 1: sin curación")
	warden.take_hit(5, Vector2(-10, 0))
	assert_true(warden.is_phase_two())
	assert_eq(warden.health, 7)
	warden._get_move_velocity(2.9)
	assert_eq(warden.health, 7, "todavía no pasaron 3 s")
	warden._get_move_velocity(0.2)
	assert_eq(warden.health, 8, "1 cada 3 s")
	assert_true(warden.is_phase_two(), "curarse no lo saca de la fase 2")
	warden._get_move_velocity(3.0)
	assert_eq(warden.health, 9)


func test_no_healing_off_the_patch_or_without_patches() -> void:
	var warden := _make(Vector2(300, 0))
	warden.take_hit(7, Vector2(-10, 0))
	assert_true(warden.is_phase_two())
	assert_false(warden.is_on_moss_patch(), "sin manchas en el mapa")
	for i in 4:
		warden._get_move_velocity(3.0)
	assert_eq(warden.health, 7, "sin manchas no se cura")
	_add_patch(warden, Vector2(30, 0))
	assert_false(warden.is_on_moss_patch(), "la mancha está lejos")
	warden._get_move_velocity(3.5)
	assert_eq(warden.health, 7)
	# Salir de la mancha reinicia el conteo.
	warden.position = Vector2(30, 0)
	warden._get_move_velocity(2.0)
	warden.position = Vector2.ZERO
	warden._get_move_velocity(0.1)
	warden.position = Vector2(30, 0)
	warden._get_move_velocity(2.0)
	assert_eq(warden.health, 7, "tiene que quedarse 3 s seguidos")


# ----- muerte y nivel -----

func test_death_clears_roots_clouds_and_pods() -> void:
	var warden := _start_spores(Vector2(60, 0))
	BossRig.play_until(warden, WardenBoss.SPORES_IMPACT_FRAME)
	assert_eq(warden.spawned_alive().size(), 4, "dos nubes y dos vainas")
	var pods := BossRig.spawned_from(warden, warden.spore_pod_scene)
	warden.take_hit(warden.health, Vector2(-10, 0))
	assert_true(warden.is_dying)
	assert_true(warden.spawned_alive().is_empty())
	assert_false(warden.is_alerted())
	assert_eq(warden.sprite.animation, &"death")
	# Quedaron en la cola de borrado fuera del árbol y las pruebas no avanzan
	# frames: se liberan a mano.
	for pod in pods:
		pod.free()


func test_level_sixteen_spawns_the_warden() -> void:
	assert_eq(BossRegistry.boss_for_level(16), BossRegistry.WARDEN)
	assert_eq(BossRegistry.boss_for_level(28), BossRegistry.WARDEN)
	var scene := BossRegistry.load_scene(BossRegistry.WARDEN)
	assert_true(scene != null, "escena registrada")
	assert_eq(track(scene.instantiate()).get("boss_id"), &"warden")
	for run_seed: int in SEEDS:
		var layout := LevelGenerator.generate(16, run_seed)
		assert_true(layout.has_boss(), "jefe en el nivel 16, semilla %d" % run_seed)
		assert_eq(layout.boss.kind, BossRegistry.WARDEN)


# ----- ayudas -----

func _make(player_at: Vector2, boss_at: Vector2 = Vector2.ZERO) -> WardenBoss:
	return BossRig.make_boss(self, WARDEN_SCRIPT, WARDEN_SCENE, player_at, boss_at)


func _start_roots(player_at: Vector2) -> WardenBoss:
	var warden := _make(player_at)
	warden.engage()
	warden._get_move_velocity(0.016)
	warden._get_move_velocity(0.016)
	assert_eq(warden.get_state(), WardenBoss.State.ROOTS)
	return warden


func _start_spores(player_at: Vector2) -> WardenBoss:
	var warden := _make(player_at)
	warden.engage()
	warden._get_move_velocity(0.016)
	warden._next_attack = WardenBoss.Attack.SPORES
	warden._get_move_velocity(0.016)
	assert_eq(warden.get_state(), WardenBoss.State.SPORES)
	assert_eq(warden.sprite.animation, &"attack2")
	return warden


## Lleva las esporas hasta el impacto. Las vainas se agregan diferidas y las
## pruebas no avanzan frames, así que nunca entran al nivel falso: se rastrean
## para liberarlas al terminar.
func _spore_impact(warden: WardenBoss) -> void:
	BossRig.play_until(warden, WardenBoss.SPORES_IMPACT_FRAME)
	for pod in BossRig.spawned_from(warden, warden.spore_pod_scene):
		track(pod)


## Vaina armada con su script y los datos de la escena, junto al jefe.
func _make_pod(warden: WardenBoss) -> SporePod:
	var source: Node = track(BossRig.load_fresh(SPORE_POD_SCENE).instantiate())
	var pod: SporePod = POD_SCRIPT.new()
	BossRig.copy_exported(source, pod)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	pod.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	pod.add_child(shape)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	pod.add_child(contact)
	pod.position = Vector2(0, 20)
	pod.heal_target = warden
	warden.get_parent().add_child(pod)
	return pod


## Mancha del suelo como las de ThemeDecor, en el nivel falso del jefe.
func _add_patch(warden: WardenBoss, at: Vector2) -> Node2D:
	var patch := Node2D.new()
	patch.position = at
	patch.add_to_group(ThemeDecor.FLOOR_PATCH_GROUP)
	warden.get_parent().add_child(patch)
	return patch


func _patch_nodes() -> Array[Node]:
	return (Engine.get_main_loop() as SceneTree).get_nodes_in_group(ThemeDecor.FLOOR_PATCH_GROUP)


func _assert_close(actual: float, expected: float, msg: String = "") -> void:
	assert_true(absf(actual - expected) < 0.001, "%s: %.4f, se esperaba %.4f" % [msg, actual, expected])
