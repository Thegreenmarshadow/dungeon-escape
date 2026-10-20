@tool
extends McpTestSuite
## Pruebas del Forjador de magma (sección 9.2 de docs/assets-pack/03-jefes.md):
## los números de la escena y los avisos, y la máquina de estados IDLE ->
## CHASE -> SLAM o ROAR (alterna) -> RECOVER -> CHASE, con la lava del
## martillazo, las brasas del rugido y el surco de la fase 2.

const BossRig := preload("res://tests/boss_rig.gd")
const FORGE_SCRIPT := preload("res://scripts/bosses/forge_boss.gd")
const FORGE_SCENE := "res://scenes/bosses/forge/Forge.tscn"
const SHOCKWAVE_SCENE := "res://scenes/bosses/forge/Shockwave.tscn"
const EMBER_MARK_SCENE := "res://scenes/bosses/forge/EmberMark.tscn"
const LAVA_POOL_SCENE := "res://scenes/bosses/forge/LavaPool.tscn"
## Velocidad del jugador, para la regla de aviso de las áreas (6.1).
const PLAYER_SPEED := 80.0


func suite_name() -> String:
	return "forge_boss"


# ----- datos -----

func test_scene_uses_the_guide_stats() -> void:
	var forge: Node = track(BossRig.load_fresh(FORGE_SCENE).instantiate())
	assert_eq(forge.get("boss_id"), &"forge")
	assert_eq(forge.get("max_health"), 12)
	assert_eq(forge.get("speed"), 20.0)
	assert_eq(forge.get("contact_damage"), 1)
	assert_eq(forge.get("detect_radius"), 120.0)
	assert_eq(forge.get("leash_radius"), 160.0)
	assert_eq(forge.get("slam_reach"), 28.0)
	assert_eq(forge.get("slam_cooldown"), 2.0)
	assert_eq(forge.get("slam_recover_time"), 1.0)
	assert_eq(forge.get("roar_cooldown"), 4.0)
	assert_eq(forge.get("roar_recover_time"), 0.6)
	assert_eq(forge.get("ember_marks"), 4)
	assert_eq(forge.get("lava_pools"), 3)
	assert_eq(forge.get("furrow_pools"), 5)


func test_attacks_are_telegraphed_long_enough() -> void:
	var forge: Node = track(BossRig.load_fresh(FORGE_SCENE).instantiate())
	var frames: SpriteFrames = forge.get_node("AnimatedSprite2D").sprite_frames
	var slam := BossBase.move_windup_seconds(frames, ForgeBoss.SLAM_ANIMATION, ForgeBoss.SLAM_IMPACT_FRAME)
	_assert_close(slam, 0.625, "martillo en alto")
	assert_true(slam >= 0.6, "aviso de un ataque dirigido (6.1)")
	var roar := BossBase.move_windup_seconds(frames, ForgeBoss.ROAR_ANIMATION, ForgeBoss.ROAR_IMPACT_FRAME)
	_assert_close(roar, 0.5, "rugido")

	var mark: Node = track(BossRig.load_fresh(EMBER_MARK_SCENE).instantiate())
	var mark_frames: SpriteFrames = mark.get_node("AnimatedSprite2D").sprite_frames
	var active: Vector2i = mark.get("active_frames")
	var mark_warning := BossBase.move_windup_seconds(mark_frames, &"default", active.x)
	_assert_close(mark_warning, 0.6667, "aviso de cada marca")
	var radius: float = mark.get("radius")
	assert_eq(radius, 12.0)
	assert_true(mark_warning >= radius / PLAYER_SPEED + 0.25, "r / 80 + 0.25 (6.1)")
	assert_true(roar + mark_warning >= 0.6, "la marca sobre el jugador avisa más de 600 ms")

	var wave: Node = track(BossRig.load_fresh(SHOCKWAVE_SCENE).instantiate())
	assert_eq(wave.get("radius"), 20.0, "onda de radio 20")
	var pool: Node = track(BossRig.load_fresh(LAVA_POOL_SCENE).instantiate())
	assert_eq(pool.get("lifetime"), 4.0, "el charco dura 4 s")
	assert_true(pool.get("continuous"))


# ----- persecución -----

func test_waits_in_its_post_until_the_player_comes_close() -> void:
	var forge := _make(Vector2(130, 0))
	assert_eq(forge._get_move_velocity(0.016), Vector2.ZERO)
	assert_eq(forge.get_state(), ForgeBoss.State.IDLE)
	assert_false(forge.is_alerted(), "dormido no cambia la música ni muestra la barra")
	var engaged: Array = []
	forge.engaged.connect(func(boss: BossBase) -> void: engaged.append(boss))
	forge._player.position = Vector2(100, 0)
	forge._get_move_velocity(0.016)
	assert_eq(forge.get_state(), ForgeBoss.State.CHASE)
	assert_true(forge.is_alerted())
	assert_eq(engaged.size(), 1)


func test_chases_at_its_speed_and_faster_in_phase_two() -> void:
	var forge := _make(Vector2(100, 0))
	forge._get_move_velocity(0.016)
	# Fuera del alcance del martillazo y con la lluvia en enfriamiento: camina.
	forge._roar_cooldown_left = 10.0
	assert_eq(forge._get_move_velocity(0.016), Vector2.RIGHT * 20.0)
	forge.take_hit(6, Vector2(-10, 0))
	assert_true(forge.is_phase_two())
	forge._is_hurt = false
	assert_eq(forge._get_move_velocity(0.016), Vector2.RIGHT * 25.0, "×1.25 en la fase 2")


func test_goes_back_to_its_post_when_the_player_leaves_the_leash() -> void:
	var forge := _make(Vector2(100, 0), Vector2(50, 0))
	forge.engage()
	forge._get_move_velocity(0.016)
	forge._player.position = Vector2(50 + forge.leash_radius + 10.0, 0)
	forge.position = Vector2(80, 0)
	assert_eq(forge._get_move_velocity(0.016), Vector2.LEFT * 20.0, "vuelve a su puesto")
	assert_true(forge.is_alerted(), "sigue en combate")


# ----- martillazo -----

func test_slam_lands_where_it_aimed_after_the_windup() -> void:
	var forge := _make(Vector2(30, 0))
	forge.engage()
	forge._get_move_velocity(0.016)
	forge._get_move_velocity(0.016)
	assert_eq(forge.get_state(), ForgeBoss.State.SLAM)
	assert_eq(forge.sprite.animation, &"attack")
	assert_eq(forge._slam_target, Vector2(28, 0), "28 px hacia el jugador")
	# El jugador se mueve durante la anticipación: el golpe va adonde apuntó.
	forge._player.position = Vector2(30, 40)
	BossRig.play_until(forge, ForgeBoss.SLAM_IMPACT_FRAME - 1)
	assert_true(forge.spawned_alive().is_empty(), "la anticipación no ataca")
	BossRig.play_until(forge, ForgeBoss.SLAM_IMPACT_FRAME)
	var waves := BossRig.spawned_from(forge, forge.shockwave_scene)
	assert_eq(waves.size(), 1, "una onda")
	assert_eq(waves[0].global_position, Vector2(28, 0))
	var pools := BossRig.spawned_from(forge, forge.lava_pool_scene)
	assert_eq(pools.size(), 3, "tres charcos alrededor")
	for pool in pools:
		_assert_close(pool.global_position.distance_to(Vector2(28, 0)), forge.lava_pool_ring_radius, "charco alrededor")
	assert_eq(forge._player.damage_taken, 0, "salió de la onda a tiempo")


func test_slam_hits_a_player_who_stays_in_the_wave() -> void:
	var forge := _make(Vector2(30, 0))
	forge.engage()
	forge._get_move_velocity(0.016)
	forge._get_move_velocity(0.016)
	BossRig.play_until(forge, ForgeBoss.SLAM_IMPACT_FRAME)
	assert_eq(forge._player.damage_taken, 1, "la onda lo alcanza (los charcos lastiman en su paso de física)")


func test_hammer_stays_down_during_the_punish_window() -> void:
	var forge := _start_slam()
	BossRig.finish_animation(forge)
	assert_eq(forge.get_state(), ForgeBoss.State.RECOVER)
	assert_true(forge.is_vulnerable(), "ventana de castigo")
	assert_eq(forge.modulate, BossBase.VULNERABLE_TINT, "tinte azulado")
	forge._update_animation()
	assert_eq(forge.sprite.animation, &"attack", "el martillo queda clavado")
	assert_eq(forge._get_move_velocity(0.5), Vector2.ZERO, "no se mueve")
	forge.take_hit(1, Vector2(-10, 0))
	assert_false(forge._is_hurt, "en la ventana de castigo no se estremece")
	forge._get_move_velocity(forge.slam_recover_time)
	assert_eq(forge.get_state(), ForgeBoss.State.CHASE)
	assert_false(forge.is_vulnerable())
	assert_eq(forge.modulate, Color.WHITE)
	assert_gt(forge._slam_cooldown_left, 0.0, "el martillazo queda en enfriamiento")


func test_player_hit_does_not_cancel_the_slam() -> void:
	var forge := _start_slam()
	forge.take_hit(1, Vector2(-10, 0))
	assert_eq(forge.get_state(), ForgeBoss.State.SLAM)
	BossRig.play_until(forge, ForgeBoss.SLAM_IMPACT_FRAME)
	assert_eq(BossRig.spawned_from(forge, forge.shockwave_scene).size(), 1, "el golpe sigue")


# ----- lluvia de brasas -----

func test_roar_rains_marks_on_and_around_the_player() -> void:
	var forge := _make(Vector2(80, 0))
	forge.engage()
	forge._get_move_velocity(0.016)
	# Lejos para el martillazo: aunque le toca, ruge.
	forge._get_move_velocity(0.016)
	assert_eq(forge.get_state(), ForgeBoss.State.ROAR)
	assert_eq(forge.sprite.animation, &"attack2")
	BossRig.play_until(forge, ForgeBoss.ROAR_IMPACT_FRAME - 1)
	assert_true(forge.spawned_alive().is_empty(), "el rugido avisa")
	BossRig.play_until(forge, ForgeBoss.ROAR_IMPACT_FRAME)
	var marks := BossRig.spawned_from(forge, forge.ember_mark_scene)
	assert_eq(marks.size(), 4)
	assert_eq(marks[0].global_position, Vector2(80, 0), "la primera sobre el jugador")
	for i in range(1, marks.size()):
		var distance: float = marks[i].global_position.distance_to(Vector2(80, 0))
		assert_true(distance >= 24.0 - 0.001 and distance <= 48.0 + 0.001, "marca a %.1f px" % distance)
	assert_eq(forge._player.damage_taken, 0, "las marcas avisan antes de estallar")
	BossRig.finish_animation(forge)
	assert_eq(forge.get_state(), ForgeBoss.State.RECOVER)
	forge._get_move_velocity(forge.roar_recover_time)
	assert_eq(forge.get_state(), ForgeBoss.State.CHASE)
	assert_gt(forge._roar_cooldown_left, 0.0)


func test_alternates_between_slam_and_roar() -> void:
	var forge := _start_slam()
	assert_eq(forge._next_attack, ForgeBoss.Attack.ROAR, "después del martillazo toca la lluvia")
	BossRig.finish_animation(forge)
	forge._get_move_velocity(forge.slam_recover_time)
	# Con el martillazo en enfriamiento, ruge.
	forge._get_move_velocity(0.016)
	assert_eq(forge.get_state(), ForgeBoss.State.ROAR)
	assert_eq(forge._next_attack, ForgeBoss.Attack.SLAM)
	BossRig.finish_animation(forge)
	forge._get_move_velocity(forge.roar_recover_time)
	forge._slam_cooldown_left = 0.0
	forge._player.position = Vector2(-30, 0)
	forge._get_move_velocity(0.016)
	assert_eq(forge.get_state(), ForgeBoss.State.SLAM, "y vuelve al martillazo")


# ----- fase 2 -----

func test_phase_two_slam_leaves_a_lava_furrow_toward_the_player() -> void:
	var forge := _make(Vector2(30, 0))
	forge.take_hit(6, Vector2(-10, 0))
	assert_true(forge.is_phase_two())
	forge._is_hurt = false
	forge._get_move_velocity(0.016)
	forge._get_move_velocity(0.016)
	assert_eq(forge.get_state(), ForgeBoss.State.SLAM)
	forge._player.position = Vector2(28, 60)
	BossRig.play_until(forge, ForgeBoss.SLAM_IMPACT_FRAME)
	var pools := BossRig.spawned_from(forge, forge.lava_pool_scene)
	assert_eq(pools.size(), 5, "surco de 5 charcos")
	for i in pools.size():
		var expected := Vector2(28, 0) + Vector2.DOWN * forge.furrow_spacing * i
		assert_true(pools[i].global_position.distance_to(expected) < 0.01,
				"charco %d en %s, se esperaba %s" % [i, pools[i].global_position, expected])


func test_death_cools_the_lava() -> void:
	var forge := _start_slam()
	BossRig.play_until(forge, ForgeBoss.SLAM_IMPACT_FRAME)
	assert_eq(forge.spawned_alive().size(), 4)
	forge.take_hit(forge.health, Vector2(-10, 0))
	assert_true(forge.is_dying)
	assert_true(forge.spawned_alive().is_empty())
	assert_false(forge.is_alerted())
	assert_eq(forge.sprite.animation, &"death")


# ----- ayudas -----

func _make(player_at: Vector2, boss_at: Vector2 = Vector2.ZERO) -> ForgeBoss:
	return BossRig.make_boss(self, FORGE_SCRIPT, FORGE_SCENE, player_at, boss_at)


## Forjador en pleno martillazo, con el jugador fuera de la onda.
func _start_slam() -> ForgeBoss:
	var forge := _make(Vector2(-30, 0))
	forge.engage()
	forge._get_move_velocity(0.016)
	forge._get_move_velocity(0.016)
	assert_eq(forge.get_state(), ForgeBoss.State.SLAM)
	forge._player.position = Vector2(-30, 30)
	return forge


func _assert_close(actual: float, expected: float, msg: String = "") -> void:
	assert_true(absf(actual - expected) < 0.001, "%s: %.4f, se esperaba %.4f" % [msg, actual, expected])
