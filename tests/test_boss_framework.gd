@tool
extends McpTestSuite
## Pruebas de lo común a todos los jefes: en qué niveles aparecen y qué pasa si
## su escena todavía no existe (BossRegistry), cómo se genera un nivel de jefe
## (arena en la sala de salida, sin parca en la puerta), los datos comunes de
## cada escena registrada, la barra de vida del HUD, la fase 2, los efectos de
## suelo (BossHazard), la llave que lleva el jefe (BossFight) y el freno del
## jugador. Usa el Forjador como jefe de ejemplo.

const BossRig := preload("res://tests/boss_rig.gd")
const PlayerRig := preload("res://tests/player_rig.gd")
const FORGE_SCRIPT := preload("res://scripts/bosses/forge_boss.gd")
const FORGE_SCENE := "res://scenes/bosses/forge/Forge.tscn"
const BAR_SCRIPT := preload("res://scripts/bosses/boss_health_bar.gd")
const BOSS_FIGHT_SCRIPT := preload("res://scripts/bosses/boss_fight.gd")
const EMBER_MARK_SCENE := "res://scenes/bosses/forge/EmberMark.tscn"
const LAVA_POOL_SCENE := "res://scenes/bosses/forge/LavaPool.tscn"
## Niveles de jefe que se revisan (tres vueltas de la rotación de temas).
const BOSS_LEVELS := [8, 12, 16, 20, 24, 28]
const SEEDS := 15
## Animaciones que trae cada <id>_frames.tres (sección 9.1).
const BOSS_ANIMATIONS := [&"idle", &"walk", &"attack", &"attack2", &"hurt", &"death"]
const ONE_SHOT_ANIMATIONS := [&"attack", &"attack2", &"hurt", &"death"]


func suite_name() -> String:
	return "boss_framework"


# ----- registro y niveles -----

func test_boss_levels_close_each_theme_band() -> void:
	var expected := {8: &"lich", 12: &"forge", 16: &"warden", 20: &"lich", 24: &"forge",
			28: &"warden", 100: &"warden"}
	for level: int in expected:
		assert_true(BossRegistry.is_boss_level(level), "el nivel %d es de jefe" % level)
		assert_eq(BossRegistry.planned_boss_for_level(level), expected[level], "jefe del nivel %d" % level)
	for level in [1, 2, 4, 5, 7, 9, 11, 13, 15, 17, 19, 21]:
		assert_false(BossRegistry.is_boss_level(level), "el nivel %d no es de jefe" % level)
		assert_eq(BossRegistry.planned_boss_for_level(level), &"")


func test_every_theme_boss_has_its_own_registry_line() -> void:
	for theme: StringName in BossRegistry.THEME_BOSSES:
		var boss_id: StringName = BossRegistry.THEME_BOSSES[theme]
		assert_true(BossRegistry.SCENES.has(boss_id), "falta la línea de %s en SCENES" % boss_id)
	assert_true(BossRegistry.is_available(BossRegistry.FORGE), "el Forjador está hecho")
	assert_eq(BossRegistry.boss_for_level(12), BossRegistry.FORGE)
	assert_true(BossRegistry.load_scene(BossRegistry.FORGE) != null)


func test_missing_boss_scene_means_no_boss() -> void:
	var empty := {BossRegistry.FORGE: ""}
	assert_eq(BossRegistry.boss_for_level(12, empty), &"", "línea vacía")
	var broken := {BossRegistry.FORGE: "res://scenes/bosses/forge/NoExiste.tscn"}
	assert_eq(BossRegistry.boss_for_level(12, broken), &"", "escena que no existe")
	assert_eq(BossRegistry.boss_for_level(12, {}), &"", "sin línea")
	assert_false(BossRegistry.is_available(&"dragon"))
	assert_eq(BossRegistry.load_scene(&"dragon"), null)


func test_boss_levels_without_their_boss_play_as_normal_levels() -> void:
	# Vale antes y después de que existan la liche y el Guardián: cada nivel de
	# jefe tiene jefe si y solo si su escena existe; si no, la parca guarda la
	# puerta y la llave está en su sala como en cualquier otro nivel.
	for level: int in BOSS_LEVELS:
		var planned := BossRegistry.planned_boss_for_level(level)
		var available := BossRegistry.is_available(planned)
		var params := LevelGenerator.params_for_level(level)
		assert_eq(params.theme_boss, planned if available else &"", "jefe en Params del nivel %d" % level)
		for run_seed in SEEDS:
			var layout := LevelGenerator.generate(level, run_seed)
			var where := "nivel %d semilla %d" % [level, run_seed]
			assert_eq(layout.has_boss(), available, "jefe, " + where)
			if not available:
				assert_gt(_kinds_in_room(layout, layout.exit_room).count(LevelGenerator.REAPER), 0,
						"parca en la puerta, " + where)


func test_boss_level_has_an_arena_in_front_of_the_door() -> void:
	for level: int in _available_boss_levels():
		for run_seed in SEEDS:
			var layout := LevelGenerator.generate(level, run_seed)
			var where := "nivel %d semilla %d" % [level, run_seed]
			assert_eq(LevelGenerator.validate(layout), "", where)
			assert_eq(layout.boss.kind, BossRegistry.boss_for_level(level), "jefe, " + where)
			var arena := layout.rooms[layout.exit_room]
			assert_true(arena.size.x >= LevelGenerator.BOSS_ROOM_MIN.x and arena.size.y >= LevelGenerator.BOSS_ROOM_MIN.y,
					"arena de %s, %s" % [str(arena.size), where])
			assert_true(arena.has_point(layout.boss.cell), "jefe en la arena, " + where)
			assert_true(_kinds_in_room(layout, layout.exit_room).is_empty(),
					"sin otros enemigos en la arena, " + where)
			for trap in layout.hazards:
				assert_false(arena.has_point(trap.cell), "trampa en la arena, " + where)
			for enemy in layout.enemies:
				assert_ne(enemy.cell, layout.boss.cell, where)
			# La parca de la llave sigue: el jefe solo reemplaza a la de la puerta.
			var params := LevelGenerator.params_for_level(level)
			assert_eq(_count_kind(layout, LevelGenerator.REAPER), params.boss_count - 1, "parcas, " + where)


func test_boss_level_fallback_layout_has_an_arena() -> void:
	for level: int in _available_boss_levels():
		for run_seed in 5:
			var layout := LevelGenerator.build_fallback(level, run_seed)
			assert_eq(LevelGenerator.validate(layout), "", "emergencia nivel %d semilla %d" % [level, run_seed])
			assert_true(layout.has_boss(), "emergencia con jefe, nivel %d" % level)


func test_boss_levels_place_what_they_request() -> void:
	# El jefe cuenta en el lugar de la parca de la puerta.
	for level: int in _available_boss_levels():
		for run_seed in 5:
			var report := DifficultyCurve.capacity_report(level, run_seed)
			assert_eq(report["placed_enemies"], report["requested_enemies"],
					"enemigos colocados, nivel %d semilla %d" % [level, run_seed])


func test_difficulty_curve_reports_the_theme_boss_apart() -> void:
	var p := LevelGenerator.params_for_level(12)
	assert_eq(p.theme_boss, BossRegistry.FORGE)
	# 10 (sin esquiva) en lugar de una parca (6 / 0.9), con la vida ×1.88.
	var swap := (10.0 - 6.0 / 0.9) * 1.88
	_assert_close(DifficultyCurve.boss_index_for(p), DifficultyCurve.index_for(p) + swap, "índice con jefe")
	var normal := LevelGenerator.params_for_level(13)
	_assert_close(DifficultyCurve.boss_index_for(normal), DifficultyCurve.index_for(normal), "sin jefe")
	var row: Dictionary = DifficultyCurve.report(12, 12)[0]
	assert_eq(row["theme_boss"], BossRegistry.FORGE)


func test_registered_boss_scenes_follow_the_common_data() -> void:
	# Sección 9.1: lo que comparten los tres jefes. Revisa cada escena
	# registrada, así un jefe nuevo se comprueba solo.
	for boss_id: StringName in BossRegistry.SCENES:
		if not BossRegistry.is_available(boss_id):
			continue
		var boss: Node = track(BossRig.load_fresh(BossRegistry.scene_path(boss_id)).instantiate())
		var where := String(boss_id)
		assert_eq(boss.get("boss_id"), boss_id, "boss_id de " + where)
		assert_false(String(boss.get("display_name")).is_empty(), "nombre de " + where)
		assert_eq(boss.get("heart_drop_chance"), 1.0, "corazón seguro, " + where)
		assert_eq(boss.get("dodge_chance"), DifficultyCurve.DODGE_THEME_BOSS, "esquiva de " + where)
		assert_eq(boss.get("knockback_distance"), 2.0, "retroceso de " + where)
		assert_eq(boss.get("collision_layer"), 4, "capa de enemigos, " + where)
		var sprite: AnimatedSprite2D = boss.get_node("AnimatedSprite2D")
		assert_eq(sprite.offset, Vector2(0, -12), "offset de " + where)
		for animation in BOSS_ANIMATIONS:
			assert_true(sprite.sprite_frames.has_animation(animation), "%s sin %s" % [where, animation])
		for animation in ONE_SHOT_ANIMATIONS:
			assert_false(sprite.sprite_frames.get_animation_loop(animation), "%s: %s sin loop" % [where, animation])
		var body: RectangleShape2D = boss.get_node("CollisionShape2D").shape
		assert_eq(body.size, Vector2(20, 10), "cuerpo de " + where)
		var contact: RectangleShape2D = boss.get_node("ContactArea/CollisionShape2D").shape
		assert_eq(contact.size, Vector2(24, 26), "contacto de " + where)


# ----- barra de vida -----

func test_health_bar_shows_only_while_the_boss_is_alerted_and_alive() -> void:
	var bar := _make_bar()
	assert_false(bar.visible, "sin jefe no se ve")
	var boss := _make_forge(Vector2(500, 0))
	bar.track(boss)
	assert_false(bar.visible, "jefe dormido: no se ve")
	boss.engage()
	bar.refresh()
	assert_true(bar.visible, "en combate se ve")
	assert_eq(bar.name_label.text, "Forjador de magma")
	assert_eq(bar.bar.max_value, float(boss.max_health))
	assert_eq(bar.bar.value, float(boss.max_health))
	boss.take_hit(3, Vector2(-10, 0))
	bar.refresh()
	assert_eq(bar.bar.value, float(boss.max_health - 3), "baja con los golpes")
	boss.take_hit(boss.health, Vector2(-10, 0))
	bar.refresh()
	assert_false(bar.visible, "muerto no se ve")
	bar.track(null)
	assert_false(bar.visible)


func test_health_bar_lets_go_of_a_freed_boss() -> void:
	var bar := _make_bar()
	var boss := _make_forge(Vector2(500, 0))
	bar.track(boss)
	boss.engage()
	bar.refresh()
	assert_true(bar.visible)
	boss.free()
	bar.refresh()
	assert_false(bar.visible, "el jefe liberado no se muestra")
	assert_true(bar.boss == null, "suelta la referencia")
	assert_false(BossHealthBar.should_show(null))


func test_boss_reports_health_changes() -> void:
	var boss := _make_forge(Vector2(500, 0))
	var seen: Array = []
	boss.health_changed.connect(func(health: int, max_health: int) -> void: seen.append([health, max_health]))
	boss.apply_health_scale(LevelGenerator.enemy_health_scale(24))
	boss.take_hit(1, Vector2(-10, 0))
	assert_eq(seen, [[18, 18], [17, 18]], "escala del nivel y golpe")
	assert_true(boss.is_alerted(), "un golpe empieza el combate")


func test_boss_has_base_health_on_its_first_level() -> void:
	for boss_id in [&"lich", &"forge", &"warden"]:
		var boss: BossBase = track(load(BossRegistry.scene_path(boss_id)).instantiate())
		var base: int = boss.max_health
		var first := BossRegistry.first_level(boss_id)
		boss.apply_health_scale(LevelGenerator.enemy_health_scale(first))
		assert_eq(boss.max_health, base, "%s en el nivel %d" % [boss_id, first])
		boss.apply_health_scale(LevelGenerator.enemy_health_scale(first + 12))
		assert_true(boss.max_health > base, "%s crece en la vuelta siguiente" % boss_id)
	assert_eq(BossRegistry.first_level(&"lich"), 8)
	assert_eq(BossRegistry.first_level(&"forge"), 12)
	assert_eq(BossRegistry.first_level(&"warden"), 16)


# ----- fase 2 -----

func test_phase_two_starts_at_half_health_once() -> void:
	var boss := _make_forge(Vector2(500, 0))
	var phases: Array[int] = []
	boss.phase_changed.connect(func(phase: int) -> void: phases.append(phase))
	assert_eq(boss.max_health, 12)
	for i in 5:
		boss.take_hit(1, Vector2(-10, 0))
	assert_eq(boss.health, 7)
	assert_eq(boss.phase, 1, "con 7 de 12 sigue en la fase 1")
	assert_eq(boss.current_speed(), boss.speed)
	boss.take_hit(1, Vector2(-10, 0))
	assert_eq(boss.phase, 2, "con 6 de 12 (50 %) pasa a la fase 2")
	assert_eq(phases, [2] as Array[int])
	assert_eq(boss.modulate, boss.phase_two_tint, "brillo constante")
	_assert_close(boss.current_speed(), boss.speed * 1.25, "velocidad de la fase 2")
	boss.take_hit(1, Vector2(-10, 0))
	assert_eq(phases.size(), 1, "la fase 2 empieza una sola vez")


func test_phase_two_threshold_with_scaled_health() -> void:
	var boss := _make_forge(Vector2(500, 0))
	boss.apply_health_scale(LevelGenerator.enemy_health_scale(24))
	assert_eq(boss.max_health, 18)
	boss.take_hit(8, Vector2(-10, 0))
	assert_eq(boss.phase, 1, "10 de 18 es más de la mitad")
	boss.take_hit(1, Vector2(-10, 0))
	assert_eq(boss.phase, 2, "9 de 18")


func test_heal_is_capped_and_keeps_phase_two() -> void:
	var boss := _make_forge(Vector2(500, 0))
	boss.take_hit(8, Vector2(-10, 0))
	assert_eq(boss.phase, 2)
	assert_eq(boss.heal(2), 2)
	assert_eq(boss.health, 6)
	assert_eq(boss.heal(100), 6, "no pasa de la vida máxima")
	assert_eq(boss.health, boss.max_health)
	assert_eq(boss.phase, 2, "curarse no vuelve a la fase 1")
	assert_eq(boss.heal(0), 0)


# ----- golpes -----

func test_bosses_never_dodge_and_hits_do_not_cancel_attacks() -> void:
	var boss := _make_forge(Vector2(500, 0))
	boss.dodge_chance = 1.0
	boss.take_hit(1, Vector2(-10, 0))
	assert_eq(boss.health, boss.max_health - 1, "no esquiva")
	assert_true(boss._is_hurt, "fuera de un ataque se estremece")
	boss._is_hurt = false
	boss.start_move(&"attack", 5)
	boss.take_hit(1, Vector2(-10, 0))
	assert_true(boss.is_performing_move(), "el golpe no corta el ataque")
	assert_false(boss._is_hurt, "atacando no se estremece")
	assert_eq(boss.sprite.animation, &"attack")


func test_move_impact_fires_once_on_its_frame() -> void:
	# El rugido del Forjador: su impacto crea las marcas de brasas.
	var boss := _make_forge(Vector2(500, 0))
	boss.start_move(&"attack2", 4)
	var windup := BossBase.move_windup_seconds(boss.sprite.sprite_frames, &"attack2", 4)
	_assert_close(windup, 0.5, "4 frames a 8 FPS")
	BossRig.play_until(boss, 3)
	assert_eq(boss.spawned_alive().size(), 0, "la anticipación no ataca")
	BossRig.play_until(boss, 4)
	var after_impact := boss.spawned_alive().size()
	assert_gt(after_impact, 0, "el frame de impacto ataca")
	BossRig.play_until(boss, 7)
	assert_eq(boss.spawned_alive().size(), after_impact, "una sola vez")
	boss._on_animation_finished()
	assert_false(boss.is_performing_move(), "termina con la animación")


func test_spawned_effects_are_cleared_when_the_boss_dies() -> void:
	var boss := _make_forge(Vector2(20, 0))
	boss.spawn_hazard(boss.lava_pool_scene, Vector2(10, 10))
	boss.spawn_hazard(boss.lava_pool_scene, Vector2(-10, 10))
	assert_eq(boss.spawned_alive().size(), 2)
	assert_eq(boss.spawned_alive()[0].get_parent(), boss.get_parent(), "sin hazard_parent van al padre")
	boss.take_hit(boss.health, Vector2(-10, 0))
	assert_true(boss.is_dying)
	assert_eq(boss.spawned_alive().size(), 0, "la lava se enfría con el jefe")


func test_hazards_go_to_the_hazard_parent() -> void:
	var boss := _make_forge(Vector2(20, 0))
	var traps := Node2D.new()
	traps.position = Vector2(100, 50)
	boss.get_parent().add_child(traps)
	boss.hazard_parent = traps
	var pool := boss.spawn_hazard(boss.lava_pool_scene, Vector2(10, 10))
	assert_eq(pool.get_parent(), traps)
	assert_eq(pool.global_position, Vector2(10, 10), "en la posición global pedida")


# ----- efectos de suelo -----

func test_one_shot_hazard_hurts_only_in_its_active_frames() -> void:
	var target := _make_target(Vector2(5, 0))
	var mark := BossRig.make_hazard(self, EMBER_MARK_SCENE, target)
	assert_eq(mark.active_frames, Vector2i(4, 5), "frames 0-3 aviso, 4-5 estallido")
	for frame in 4:
		mark.sprite.frame = frame
	assert_eq(target.damage_taken, 0, "el aviso no lastima")
	mark.sprite.frame = 4
	assert_eq(target.damage_taken, 1, "estalla")
	mark.sprite.frame = 5
	assert_false(mark.try_strike(), "una sola vez")
	assert_eq(target.damage_taken, 1)


func test_hazard_misses_outside_its_radius() -> void:
	var target := _make_target(Vector2(13, 0))
	var mark := BossRig.make_hazard(self, EMBER_MARK_SCENE, target)
	mark.sprite.frame = 4
	assert_eq(target.damage_taken, 0, "a 13 px del centro de una marca de radio 12")


func test_continuous_hazard_hurts_while_active() -> void:
	var target := _make_target(Vector2(3, 0))
	var pool := BossRig.make_hazard(self, LAVA_POOL_SCENE, target)
	assert_true(pool.continuous)
	assert_eq(pool.lifetime, 4.0, "dura 4 s")
	assert_true(pool.try_strike())
	assert_true(pool.try_strike(), "lastima cada vez (la invulnerabilidad del jugador lo frena)")
	assert_eq(target.damage_taken, 2)
	pool.slow_factor = 0.5
	pool.damage = 0
	pool.try_strike()
	assert_eq(target.slow_calls, 1, "con slow_factor frena al jugador")
	assert_eq(target.last_slow_factor, 0.5)
	assert_eq(target.damage_taken, 2, "con damage 0 no lastima")


# ----- la llave -----

func test_boss_keeps_the_key_until_it_dies() -> void:
	var boss := _make_forge(Vector2(500, 0), Vector2(40, 30))
	var level := boss.get_parent()
	var key := Node2D.new()
	key.name = "Key"
	level.add_child(key)
	var fight: BossFight = BOSS_FIGHT_SCRIPT.new(boss, key, level)
	assert_true(fight.is_key_held())
	assert_false(key.is_inside_tree(), "la llave sale del mapa")
	boss.take_hit(boss.health, Vector2(0, 30))
	# En el juego la llave vuelve diferida (la muerte llega en un callback de
	# física); acá se llama directo.
	fight.release_key()
	assert_false(fight.is_key_held())
	assert_true(key.is_inside_tree(), "la llave vuelve al morir el jefe")
	assert_eq(key.get_parent(), level)
	assert_eq(key.global_position, boss.global_position, "donde cayó el jefe")
	fight.release_key()
	assert_eq(level.get_children().count(key), 1, "una sola vez")


func test_boss_fight_frees_a_key_never_released() -> void:
	var boss := _make_forge(Vector2(500, 0))
	var level := boss.get_parent()
	var key := Node2D.new()
	level.add_child(key)
	var fight: BossFight = BOSS_FIGHT_SCRIPT.new(boss, key, level)
	fight.dispose()
	assert_false(is_instance_valid(key), "sin jefe derrotado la llave se libera al salir")


# ----- freno del jugador -----

func test_player_slow_takes_the_strongest_and_expires() -> void:
	var player: CharacterBody2D = track(PlayerRig.make_player())
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	assert_eq(player.slow_multiplier(), 1.0)
	player.apply_slow(0.5, 2.0)
	assert_eq(player.slow_multiplier(), 0.5)
	assert_eq(player._move_speed_factor(), 0.5, "la velocidad usa el freno")
	player.apply_slow(0.8, 3.0)
	assert_eq(player.slow_multiplier(), 0.5, "se queda con el freno más fuerte")
	player._update_slow(2.5)
	assert_eq(player.slow_multiplier(), 0.5, "y con el tiempo más largo")
	player._update_slow(0.6)
	assert_eq(player.slow_multiplier(), 1.0, "se termina")
	assert_false(player._slow_particles.emitting, "y se apagan las partículas")


# ----- ayudas -----

func _make_forge(player_at: Vector2, boss_at: Vector2 = Vector2.ZERO) -> ForgeBoss:
	return BossRig.make_boss(self, FORGE_SCRIPT, FORGE_SCENE, player_at, boss_at)


func _make_target(at: Vector2) -> Node2D:
	var target := BossRig.TargetStub.new()
	target.position = at
	BossRig.make_level(self).add_child(target)
	return target


func _make_bar() -> BossHealthBar:
	var bar: BossHealthBar = BAR_SCRIPT.new()
	var label := Label.new()
	label.name = "NameLabel"
	bar.add_child(label)
	var progress := ProgressBar.new()
	progress.name = "Bar"
	bar.add_child(progress)
	track(bar)
	(Engine.get_main_loop() as SceneTree).root.add_child(bar)
	return bar


## Niveles de BOSS_LEVELS cuyo jefe ya existe.
func _available_boss_levels() -> Array[int]:
	var out: Array[int] = []
	for level: int in BOSS_LEVELS:
		if BossRegistry.boss_for_level(level) != &"":
			out.append(level)
	return out


func _kinds_in_room(layout: LevelGenerator.Layout, room_index: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for enemy in layout.enemies:
		if layout.rooms[room_index].has_point(enemy.cell):
			out.append(enemy.kind)
	return out


func _count_kind(layout: LevelGenerator.Layout, kind: StringName) -> int:
	var count := 0
	for enemy in layout.enemies:
		if enemy.kind == kind:
			count += 1
	return count


func _assert_close(actual: float, expected: float, msg: String = "") -> void:
	assert_true(absf(actual - expected) < 0.0001, "%s: %.4f, se esperaba %.4f" % [msg, actual, expected])
