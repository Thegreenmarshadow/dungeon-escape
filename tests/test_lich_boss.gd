@tool
extends McpTestSuite
## Pruebas de la Reina liche de escarcha (sección 9.3 de
## docs/assets-pack/03-jefes.md): los números de la escena y los avisos, y la
## máquina de estados IDLE -> REPOSITION -> SPIKES o NOVA -> RECOVER ->
## REPOSITION, con la línea de picos, la nova con frío y los cristales escudo
## de la fase 2. También que el nivel 8 (último del hielo) ya la trae.

const BossRig := preload("res://tests/boss_rig.gd")
const LICH_SCRIPT := preload("res://scripts/bosses/lich_boss.gd")
const CRYSTAL_SCRIPT := preload("res://scripts/bosses/ice_crystal.gd")
const LICH_SCENE := "res://scenes/bosses/lich/Lich.tscn"
const ICE_SPIKE_SCENE := "res://scenes/bosses/lich/IceSpike.tscn"
const FROST_NOVA_SCENE := "res://scenes/bosses/lich/FrostNova.tscn"
const FROST_MARK_SCENE := "res://scenes/bosses/lich/FrostMark.tscn"
const ICE_CRYSTAL_SCENE := "res://scenes/bosses/lich/IceCrystal.tscn"
## Velocidad del jugador, para la regla de aviso de las áreas (6.1).
const PLAYER_SPEED := 80.0


func suite_name() -> String:
	return "lich_boss"


# ----- datos -----

func test_scene_uses_the_guide_stats() -> void:
	var lich: Node = track(BossRig.load_fresh(LICH_SCENE).instantiate())
	assert_eq(lich.get("boss_id"), &"lich")
	assert_eq(lich.get("display_name"), "Reina liche de escarcha")
	assert_eq(lich.get("max_health"), 10)
	assert_eq(lich.get("speed"), 30.0)
	assert_eq(lich.get("contact_damage"), 0, "solo lastima con sus ataques")
	assert_eq(lich.get("detect_radius"), 140.0)
	assert_eq(lich.get("keep_min_distance"), 60.0)
	assert_eq(lich.get("keep_max_distance"), 110.0)
	assert_eq(lich.get("spike_count"), 6)
	assert_eq(lich.get("spike_spacing"), 16.0)
	assert_eq(lich.get("spike_interval"), 0.08)
	assert_eq(lich.get("spikes_cooldown"), 2.5)
	assert_eq(lich.get("spikes_recover_time"), 0.5)
	assert_eq(lich.get("nova_cooldown"), 5.0)
	assert_eq(lich.get("nova_recover_time"), 1.2)
	assert_eq(lich.get("frost_slow_factor"), 0.5)
	assert_eq(lich.get("frost_slow_duration"), 2.0)
	assert_eq(lich.get("crystal_count"), 2)
	assert_eq(lich.get("crystal_distance"), 24.0)
	assert_eq(lich.get("summon_recover_time"), 0.6)
	var crystal: Node = track(BossRig.load_fresh(ICE_CRYSTAL_SCENE).instantiate())
	assert_eq(crystal.get("max_health"), 2, "cada cristal aguanta 2 golpes")
	assert_eq(crystal.get("collision_layer"), 4, "la espada lo alcanza")
	assert_eq(crystal.get("contact_damage"), 0)
	assert_eq(crystal.get("heart_drop_chance"), 0.0)
	assert_eq(crystal.get("coin_drop_chance"), 0.0)


func test_attacks_are_telegraphed_long_enough() -> void:
	var lich: Node = track(BossRig.load_fresh(LICH_SCENE).instantiate())
	var frames: SpriteFrames = lich.get_node("AnimatedSprite2D").sprite_frames
	var spikes := BossBase.move_windup_seconds(frames, LichBoss.SPIKES_ANIMATION, LichBoss.SPIKES_IMPACT_FRAME)
	_assert_close(spikes, 0.625, "báculo en alto")
	var nova := BossBase.move_windup_seconds(frames, LichBoss.NOVA_ANIMATION, LichBoss.NOVA_IMPACT_FRAME)
	_assert_close(nova, 0.625, "brazos arriba")
	var aim := BossBase.move_windup_seconds(frames, LichBoss.SPIKES_ANIMATION, LichBoss.SPIKES_AIM_FRAME)
	assert_true(spikes - aim >= 0.15, "la línea se fija 150 ms antes del impacto (6.1)")

	# Cada pico: 250 ms de grieta (frames 0-1) y 375 ms de pico (frames 2-4).
	var spike: Node = track(BossRig.load_fresh(ICE_SPIKE_SCENE).instantiate())
	var spike_frames: SpriteFrames = spike.get_node("AnimatedSprite2D").sprite_frames
	var spike_active: Vector2i = spike.get("active_frames")
	var crack := BossBase.move_windup_seconds(spike_frames, &"default", spike_active.x)
	_assert_close(crack, 0.25, "grieta de cada pico")
	_assert_close(BossBase.move_windup_seconds(spike_frames, &"default", spike_active.y + 1) - crack, 0.375,
			"pico activo")
	var spike_radius: float = spike.get("radius")
	assert_true((spikes - aim) + crack >= spike_radius / PLAYER_SPEED + 0.25,
			"desde que fija la línea, cada pico avisa r / 80 + 0.25 (6.1)")
	assert_true(spikes + crack >= 0.6, "el primer pico avisa más de 600 ms")

	# Nova: el anillo lastima al llegar a su radio (frame 3 del fx).
	var ring: Node = track(BossRig.load_fresh(FROST_NOVA_SCENE).instantiate())
	assert_eq(ring.get("radius"), 40.0, "anillo de radio 40")
	assert_eq(ring.get_node("AnimatedSprite2D").scale, Vector2(2, 2), "fx a escala 2")
	var ring_frames: SpriteFrames = ring.get_node("AnimatedSprite2D").sprite_frames
	var ring_active: Vector2i = ring.get("active_frames")
	var ring_warning := BossBase.move_windup_seconds(ring_frames, &"default", ring_active.x)
	assert_true(nova + ring_warning >= 40.0 / PLAYER_SPEED + 0.25, "la nova cumple r / 80 + 0.25 (6.1)")

	# Cristales: 1 s de invocación, marcada en el suelo por fx-frost_mark.
	var summon := BossBase.move_windup_seconds(frames, LichBoss.SUMMON_ANIMATION,
			frames.get_frame_count(LichBoss.SUMMON_ANIMATION))
	_assert_close(summon, 1.0, "invocación")
	var mark: Node = track(BossRig.load_fresh(FROST_MARK_SCENE).instantiate())
	var mark_frames: SpriteFrames = mark.get_node("AnimatedSprite2D").sprite_frames
	_assert_close(BossBase.move_windup_seconds(mark_frames, &"default", mark_frames.get_frame_count(&"default")),
			1.0, "la marca dura lo que la invocación")
	assert_eq(mark.get("damage"), 0, "la marca solo avisa")


# ----- distancia -----

func test_waits_in_her_post_until_the_player_comes_close() -> void:
	var lich := _make(Vector2(150, 0))
	assert_eq(lich._get_move_velocity(0.016), Vector2.ZERO)
	assert_eq(lich.get_state(), LichBoss.State.IDLE)
	assert_false(lich.is_alerted(), "dormida no cambia la música ni muestra la barra")
	lich._player.position = Vector2(130, 0)
	lich._get_move_velocity(0.016)
	assert_eq(lich.get_state(), LichBoss.State.REPOSITION)
	assert_true(lich.is_alerted())


func test_keeps_her_distance_from_the_player() -> void:
	var lich := _make(Vector2(130, 0))
	lich._get_move_velocity(0.016)
	_cool_down_all(lich)
	assert_eq(lich._get_move_velocity(0.016), Vector2.RIGHT * 30.0, "lejos: se acerca")
	lich._player.position = Vector2(80, 0)
	_cool_down_all(lich)
	assert_eq(lich._get_move_velocity(0.016), Vector2.ZERO, "en la banda: se queda")
	lich._player.position = Vector2(40, 0)
	_cool_down_all(lich)
	assert_eq(lich._get_move_velocity(0.016), Vector2.LEFT * 30.0, "cerca: retrocede")
	# Lejos de su puesto, acorralada, se planta.
	lich.position = Vector2(-lich.max_retreat_from_home, 0)
	lich._player.position = lich.position + Vector2(40, 0)
	_cool_down_all(lich)
	assert_eq(lich._get_move_velocity(0.016), Vector2.ZERO, "no huye por un pasillo")
	assert_true(lich.is_alerted())


func test_goes_back_to_her_post_when_the_player_leaves_the_leash() -> void:
	var lich := _make(Vector2(100, 0), Vector2(50, 0))
	lich.engage()
	lich._get_move_velocity(0.016)
	lich._player.position = Vector2(50 + lich.leash_radius + 10.0, 0)
	lich.position = Vector2(80, 0)
	assert_eq(lich._get_move_velocity(0.016), Vector2.LEFT * 30.0, "vuelve a su puesto")


# ----- línea de picos -----

func test_spike_line_aims_on_frame_three_and_rises_in_sequence() -> void:
	var lich := _make(Vector2(80, 0))
	lich.engage()
	lich._get_move_velocity(0.016)
	lich._get_move_velocity(0.016)
	assert_eq(lich.get_state(), LichBoss.State.SPIKES)
	assert_eq(lich.sprite.animation, &"attack")
	# Se mueve antes del frame 3: la línea lo sigue hasta ahí.
	lich._player.position = Vector2(0, 80)
	BossRig.play_until(lich, LichBoss.SPIKES_AIM_FRAME)
	# Después del frame 3 ya no: la línea va adonde estaba.
	lich._player.position = Vector2(80, 0)
	BossRig.play_until(lich, LichBoss.SPIKES_IMPACT_FRAME - 1)
	assert_true(lich.spawned_alive().is_empty(), "el báculo en alto avisa")
	BossRig.play_until(lich, LichBoss.SPIKES_IMPACT_FRAME)
	var spikes := BossRig.spawned_from(lich, lich.ice_spike_scene)
	assert_eq(spikes.size(), 1, "el primer pico sale en el impacto")
	assert_eq(spikes[0].global_position, Vector2(0, 16))
	lich.advance_spikes(0.07)
	assert_eq(BossRig.spawned_from(lich, lich.ice_spike_scene).size(), 1, "80 ms entre picos")
	lich.advance_spikes(0.011)
	assert_eq(BossRig.spawned_from(lich, lich.ice_spike_scene).size(), 2)
	lich.advance_spikes(1.0)
	spikes = BossRig.spawned_from(lich, lich.ice_spike_scene)
	assert_eq(spikes.size(), 6, "seis picos")
	for i in spikes.size():
		assert_true(spikes[i].global_position.distance_to(Vector2(0, 16 * (i + 1))) < 0.01,
				"pico %d en %s" % [i, spikes[i].global_position])
	assert_eq(lich._player.damage_taken, 0, "cada pico avisa con su grieta")


func test_spike_hurts_after_its_crack() -> void:
	var player := BossRig.TargetStub.new()
	var hazard := BossRig.make_hazard(self, ICE_SPIKE_SCENE, player)
	hazard.get_parent().add_child(player)
	hazard.sprite.frame = 1
	assert_eq(player.damage_taken, 0, "grieta")
	hazard.sprite.frame = 2
	assert_eq(player.damage_taken, 1, "pico")
	hazard.sprite.frame = 3
	assert_eq(player.damage_taken, 1, "una sola vez")
	player.position = Vector2(10, 0)
	var other := BossRig.make_hazard(self, ICE_SPIKE_SCENE, player)
	other.sprite.frame = 2
	assert_eq(player.damage_taken, 1, "a 10 px de costado no lo alcanza")


func test_spikes_recover_and_cool_down() -> void:
	var lich := _start_spikes()
	BossRig.finish_animation(lich)
	assert_eq(lich.get_state(), LichBoss.State.RECOVER)
	assert_true(lich.is_vulnerable(), "ventana de castigo")
	assert_eq(lich._get_move_velocity(0.4), Vector2.ZERO)
	assert_eq(lich.get_state(), LichBoss.State.RECOVER)
	lich._get_move_velocity(0.11)
	assert_eq(lich.get_state(), LichBoss.State.REPOSITION)
	assert_false(lich.is_vulnerable())
	assert_gt(lich._spikes_cooldown_left, 0.0, "la línea queda en enfriamiento")
	lich._get_move_velocity(0.016)
	assert_eq(lich.get_state(), LichBoss.State.REPOSITION, "sin ataque listo se reacomoda")


func test_player_hit_does_not_cancel_the_spikes() -> void:
	var lich := _start_spikes()
	lich.take_hit(1, Vector2(70, 0))
	assert_eq(lich.get_state(), LichBoss.State.SPIKES)
	assert_false(lich._is_hurt, "atacando no se estremece")
	BossRig.play_until(lich, LichBoss.SPIKES_IMPACT_FRAME)
	assert_eq(BossRig.spawned_from(lich, lich.ice_spike_scene).size(), 1, "la línea sigue")


# ----- nova de escarcha -----

func test_nova_freezes_a_player_who_stays_close() -> void:
	var lich := _start_nova()
	BossRig.play_until(lich, LichBoss.NOVA_IMPACT_FRAME - 1)
	assert_true(lich.spawned_alive().is_empty(), "los brazos arriba avisan")
	BossRig.play_until(lich, LichBoss.NOVA_IMPACT_FRAME)
	var novas := BossRig.spawned_from(lich, lich.frost_nova_scene)
	assert_eq(novas.size(), 1)
	assert_eq(novas[0].global_position, Vector2.ZERO, "alrededor de ella")
	var nova: BossHazard = novas[0]
	nova.sprite.frame = 2
	assert_eq(lich._player.damage_taken, 0, "el anillo todavía crece")
	nova.sprite.frame = 3
	assert_eq(lich._player.damage_taken, 1)
	assert_eq(lich._player.slow_calls, 1, "frío")
	assert_eq(lich._player.last_slow_factor, 0.5, "al 50 % de velocidad")


func test_nova_spares_a_player_who_backs_away() -> void:
	var lich := _start_nova()
	BossRig.play_until(lich, LichBoss.NOVA_IMPACT_FRAME)
	lich._player.position = Vector2(-45, 0)
	var nova: BossHazard = BossRig.spawned_from(lich, lich.frost_nova_scene)[0]
	nova.sprite.frame = 3
	assert_eq(lich._player.damage_taken, 0)
	assert_eq(lich._player.slow_calls, 0)


func test_nova_leaves_her_grounded_and_vulnerable() -> void:
	var lich := _start_nova()
	BossRig.finish_animation(lich)
	assert_eq(lich.get_state(), LichBoss.State.RECOVER)
	assert_true(lich.is_vulnerable())
	assert_eq(lich.modulate, BossBase.VULNERABLE_TINT, "tinte azulado")
	lich._update_animation()
	assert_eq(lich.sprite.animation, &"attack2", "queda en su pose")
	lich._get_move_velocity(1.1)
	assert_eq(lich.get_state(), LichBoss.State.RECOVER, "1.2 s en el suelo")
	lich._get_move_velocity(0.11)
	assert_eq(lich.get_state(), LichBoss.State.REPOSITION)
	assert_gt(lich._nova_cooldown_left, 0.0)


func test_chooses_nova_up_close_and_spikes_otherwise() -> void:
	var lich := _start_nova()
	assert_eq(lich.get_state(), LichBoss.State.NOVA, "cerca y con la nova lista")
	BossRig.finish_animation(lich)
	lich._get_move_velocity(lich.nova_recover_time)
	# La nova en enfriamiento: aunque esté cerca, la línea.
	lich._get_move_velocity(0.016)
	assert_eq(lich.get_state(), LichBoss.State.SPIKES)
	BossRig.finish_animation(lich)
	lich._get_move_velocity(lich.spikes_recover_time)
	# Todo en enfriamiento y demasiado cerca: retrocede, sin atacar.
	assert_eq(lich._get_move_velocity(0.016), Vector2.RIGHT * 30.0)
	assert_eq(lich.get_state(), LichBoss.State.REPOSITION)
	lich._spikes_cooldown_left = 0.0
	lich._player.position = Vector2(lich.spikes_range + 5.0, 0)
	lich._get_move_velocity(0.016)
	assert_eq(lich.get_state(), LichBoss.State.REPOSITION, "fuera del alcance de la línea")


# ----- fase 2: cristales -----

func test_phase_two_summons_crystals_marked_on_the_floor() -> void:
	var lich := _make(Vector2(80, 0))
	lich.take_hit(ceili(lich.max_health / 2.0), Vector2(70, 0))
	assert_true(lich.is_phase_two())
	lich._is_hurt = false
	lich._get_move_velocity(0.016)
	lich._get_move_velocity(0.016)
	assert_eq(lich.get_state(), LichBoss.State.SUMMON, "lo primero de la fase 2")
	var marks := BossRig.spawned_from(lich, lich.frost_mark_scene)
	assert_eq(marks.size(), 2, "una marca por cristal")
	var expected := [Vector2(24, 0).rotated(-PI / 4.0), Vector2(24, 0).rotated(PI / 4.0)]
	for i in marks.size():
		assert_true(marks[i].global_position.distance_to(expected[i]) < 0.01,
				"marca %d en %s" % [i, marks[i].global_position])
	assert_true(BossRig.spawned_from(lich, lich.ice_crystal_scene).is_empty(), "salen al terminar")
	BossRig.finish_animation(lich)
	var crystals := BossRig.spawned_from(lich, lich.ice_crystal_scene)
	for crystal in crystals:
		track(crystal)
	assert_eq(crystals.size(), 2, "dos cristales")
	for i in crystals.size():
		assert_true(crystals[i].position.distance_to(expected[i]) < 0.01, "a 24 px, hacia el jugador")
	assert_eq(lich.get_state(), LichBoss.State.RECOVER)
	assert_false(lich.is_vulnerable(), "los cristales ya la protegen")
	var health := lich.health
	lich.take_hit(1, Vector2(70, 0))
	assert_eq(lich.health, health, "con cristales en pie no recibe daño")
	lich._get_move_velocity(lich.summon_recover_time)
	assert_eq(lich.get_state(), LichBoss.State.REPOSITION)


func test_crystals_break_in_two_hits_and_lift_the_shield() -> void:
	var lich := _make(Vector2(80, 0))
	lich.take_hit(ceili(lich.max_health / 2.0), Vector2(70, 0))
	var first := _make_crystal(lich, Vector2(17, -17))
	var second := _make_crystal(lich, Vector2(17, 17))
	lich._crystals.assign([first, second])
	var health := lich.health
	lich.take_hit(1, Vector2(70, 0))
	assert_eq(lich.health, health, "inmune")
	first.take_hit(1, Vector2(70, 0))
	assert_false(first.is_dying, "aguanta el primer golpe")
	first.take_hit(1, Vector2(70, 0))
	assert_true(first.is_dying, "se rompe con el segundo")
	lich.take_hit(1, Vector2(70, 0))
	assert_eq(lich.health, health, "con un cristal en pie sigue inmune")
	second.take_hit(2, Vector2(70, 0))
	assert_false(lich.is_shielded())
	lich.take_hit(1, Vector2(70, 0))
	assert_eq(lich.health, health - 1, "sin cristales recibe daño")
	lich._is_hurt = false
	lich._get_move_velocity(0.016)
	assert_true(lich._crystals.is_empty())
	assert_eq(lich._summon_cooldown_left, lich.crystal_resummon_cooldown, "espera para volver a invocar")
	_cool_down_all(lich)
	lich._summon_cooldown_left = 0.1
	lich._get_move_velocity(0.2)
	assert_eq(lich.get_state(), LichBoss.State.SUMMON, "y los invoca otra vez")
	for crystal in BossRig.spawned_from(lich, lich.ice_crystal_scene):
		track(crystal)


func test_death_clears_spikes_and_crystals() -> void:
	var lich := _start_spikes()
	BossRig.play_until(lich, LichBoss.SPIKES_IMPACT_FRAME)
	var crystal := _make_crystal(lich, Vector2(17, 17))
	lich._crystals.assign([crystal])
	lich._spawned.append(crystal)
	assert_eq(lich.spawned_alive().size(), 2)
	crystal.take_hit(2, Vector2(70, 0))
	lich._get_move_velocity(0.016)
	lich.take_hit(lich.health, Vector2(-10, 0))
	assert_true(lich.is_dying)
	assert_true(lich.spawned_alive().is_empty())
	lich.advance_spikes(1.0)
	assert_true(lich.spawned_alive().is_empty(), "no salen más picos")
	assert_false(lich.is_alerted())
	assert_eq(lich.sprite.animation, &"death")


# ----- nivel 8 -----

func test_last_ice_level_brings_the_lich() -> void:
	assert_true(BossRegistry.is_available(BossRegistry.LICH))
	for level in [8, 20]:
		assert_eq(BossRegistry.boss_for_level(level), BossRegistry.LICH, "nivel %d" % level)
		assert_eq(LevelGenerator.params_for_level(level).theme_boss, BossRegistry.LICH)
		for run_seed in 5:
			var layout := LevelGenerator.generate(level, run_seed)
			assert_true(layout.has_boss(), "nivel %d semilla %d" % [level, run_seed])
			assert_eq(layout.boss.kind, BossRegistry.LICH)
	var ids: Array = SandboxCatalog.boss_entries().map(func(entry: Dictionary) -> StringName: return entry["id"])
	assert_contains(ids, BossRegistry.LICH, "la zona de pruebas la lista")


# ----- ayudas -----

func _make(player_at: Vector2, boss_at: Vector2 = Vector2.ZERO) -> LichBoss:
	return BossRig.make_boss(self, LICH_SCRIPT, LICH_SCENE, player_at, boss_at)


## Liche en plena línea de picos, con el jugador a 70 px a la derecha.
func _start_spikes() -> LichBoss:
	var lich := _make(Vector2(70, 0))
	lich.engage()
	lich._get_move_velocity(0.016)
	lich._get_move_velocity(0.016)
	assert_eq(lich.get_state(), LichBoss.State.SPIKES)
	return lich


## Liche en plena nova, con el jugador a 30 px a la izquierda.
func _start_nova() -> LichBoss:
	var lich := _make(Vector2(-30, 0))
	lich.engage()
	lich._get_move_velocity(0.016)
	lich._get_move_velocity(0.016)
	assert_eq(lich.get_state(), LichBoss.State.NOVA)
	assert_eq(lich.sprite.animation, &"attack2")
	return lich


func _cool_down_all(lich: LichBoss) -> void:
	lich._spikes_cooldown_left = 10.0
	lich._nova_cooldown_left = 10.0


## Cristal armado con su script y los datos de su escena, ya en el nivel falso
## de la liche (spawn_minion lo agrega diferido y las pruebas no esperan frames).
func _make_crystal(lich: LichBoss, at: Vector2) -> IceCrystal:
	var source: Node = track(BossRig.load_fresh(ICE_CRYSTAL_SCENE).instantiate())
	var crystal: IceCrystal = CRYSTAL_SCRIPT.new()
	BossRig.copy_exported(source, crystal)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	crystal.add_child(sprite)
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	crystal.add_child(shape)
	var contact := Area2D.new()
	contact.name = "ContactArea"
	crystal.add_child(contact)
	crystal.position = at
	lich.get_parent().add_child(crystal)
	return crystal


func _assert_close(actual: float, expected: float, msg: String = "") -> void:
	assert_true(absf(actual - expected) < 0.001, "%s: %.4f, se esperaba %.4f" % [msg, actual, expected])
