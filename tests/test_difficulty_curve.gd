@tool
extends McpTestSuite
## Pruebas de la curva de dificultad (DifficultyCurve).
##
## El objetivo de diseño tiene dos tramos (ver DifficultyCurve.TARGET_GROWTH y
## ESCALATION_TARGET): hasta el nivel 14, +10 % de índice por nivel; después,
## que cada nivel suba algo y que el índice del 100 sea al menos 10 veces el
## del 14. Del 15 en adelante solo la vida crece de forma continua (+8 % de
## la base por nivel, unos 0.08 / multiplicador en relativo, menos del 1 % al
## llegar al 100); la escalada la dan además la conversión de comunes en
## especiales, los escalones de daño (25, 45, 65) y los topes más altos de
## arqueros, magos y trampas.

## Pesos efectivos (peso / (1 - esquiva)) escritos a mano, para que las
## cuentas de las pruebas no dependan de las constantes que comprueban.
const SKELETON := 1.5 / 0.85
const VAMPIRE := 2.0 / 0.8
const SKULL := 2.5 / 0.9
const BOSS := 6.0 / 0.9
const ARCHER := 2.5 / 0.85
const SKULL_TURRET := 1.5 / 1.0
const MIMIC := 2.5 / 0.9
const MAGE := 3.0 / 0.85

## Escena de cada tipo y la constante de esquiva de DifficultyCurve que la copia.
const DODGE_BY_SCENE := {
	"res://scenes/Skeleton.tscn": DifficultyCurve.DODGE_SKELETON,
	"res://scenes/Vampire.tscn": DifficultyCurve.DODGE_VAMPIRE,
	"res://scenes/Skull.tscn": DifficultyCurve.DODGE_SKULL,
	"res://scenes/Reaper.tscn": DifficultyCurve.DODGE_BOSS,
	"res://scenes/Archer.tscn": DifficultyCurve.DODGE_ARCHER,
	"res://scenes/SkullTurret.tscn": DifficultyCurve.DODGE_SKULL_TURRET,
	"res://scenes/Mimic.tscn": DifficultyCurve.DODGE_MIMIC,
	"res://scenes/Mage.tscn": DifficultyCurve.DODGE_MAGE,
}

## Niveles y semillas de la prueba de capacidad. La medición completa (30
## semillas en 20, 30, 50, 75 y 100) está en docs/character-design.md, sección 8.4.
const CAPACITY_LEVELS := [2, 5, 10, 20, 30, 60, 100]
const CAPACITY_SEEDS := [1, 2, 3, 4, 5]
## Niveles hasta el 14 que ya hoy crecen menos del 10 %: 11 (+9.97 %), 12
## (+4.54 %) y 13 (+4.35 %). En el 11 se tapa la proporción de perseguidores y
## en el 12 y el 13 solo crecen la vida, la grilla y una trampa, mientras los
## especiales esperan su próximo escalón. Se decidió no retocar los niveles
## tempranos, así que la prueba del primer tramo los deja afuera a la vista.
const EARLY_LEVELS_BELOW_TARGET: Array[int] = [11, 12, 13]
## Índice planificado de los niveles que siembra el servidor de ejemplo
## (server/game_stats/seed.py, PLANNED_INDEX). Tienen que coincidir.
const SERVER_SEED_INDEX := {2: 20.629, 3: 35.76, 4: 44.685, 5: 56.756, 6: 81.035}


func suite_name() -> String:
	return "difficulty_curve"


func test_index_uses_the_documented_weights() -> void:
	# Parámetros armados a mano: 10 enemigos con la mitad de perseguidores
	# (5), de los que 2 son calaveras; 1 jefe y 4 trampas.
	var p := LevelGenerator.Params.new()
	p.enemy_count = 10
	p.chaser_share = 0.5
	p.skull_count = 2
	p.boss_count = 1
	p.hazard_count = 4
	# Multiplicador de vida 1 (el valor por defecto de Params). Pesos 1.5, 2,
	# 2.5 y 6, cada uno dividido por (1 - esquiva): 0.15, 0.2, 0.1 y 0.1.
	# 5 esqueletos + 3 vampiros + 2 calaveras + 1 jefe + 4 trampas * 0.5 = 30.5458.
	var expected := 5 * SKELETON + 3 * VAMPIRE + 2 * SKULL + BOSS + 4 * 0.5
	_assert_close(expected, 30.545752, "cuenta a mano")
	_assert_close(DifficultyCurve.index_for(p), expected, "índice de parámetros hechos a mano")


func test_special_enemies_add_their_documented_weights() -> void:
	# Los mismos parámetros hechos a mano más 1 arquero, 2 torres, 1 mímico y
	# 1 mago: 30.5458 + 2.9412 + 2 * 1.5 + 2.7778 + 3.5294 = 42.7941.
	var p := LevelGenerator.Params.new()
	p.enemy_count = 10
	p.chaser_share = 0.5
	p.skull_count = 2
	p.boss_count = 1
	p.hazard_count = 4
	p.special_counts = {
		LevelGenerator.ARCHER: 1, LevelGenerator.SKULL_TURRET: 2,
		LevelGenerator.MIMIC: 1, LevelGenerator.MAGE: 1,
	}
	var expected := 5 * SKELETON + 3 * VAMPIRE + 2 * SKULL + BOSS + 4 * 0.5 \
			+ ARCHER + 2 * SKULL_TURRET + MIMIC + MAGE
	_assert_close(expected, 42.794118, "cuenta a mano")
	_assert_close(DifficultyCurve.index_for(p), expected, "índice con especiales")


func test_dodge_counts_as_extra_health() -> void:
	_assert_close(DifficultyCurve.effective_weight(2.0, 0.0), 2.0, "sin esquiva no cambia")
	_assert_close(DifficultyCurve.effective_weight(2.0, 0.2), 2.5, "20 % de esquiva")
	_assert_close(DifficultyCurve.effective_weight(1.0, 0.5), 2.0, "50 % de esquiva: el doble")


func test_dodge_constants_match_the_scenes() -> void:
	for path: String in DODGE_BY_SCENE:
		var scene: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var enemy: EnemyBase = track(scene.instantiate())
		_assert_close(enemy.dodge_chance, DODGE_BY_SCENE[path], "esquiva de %s" % path)


func test_health_scale_multiplies_enemies_but_not_hazards() -> void:
	var p := LevelGenerator.Params.new()
	p.enemy_count = 10
	p.chaser_share = 0.5
	p.skull_count = 2
	p.boss_count = 1
	p.hazard_count = 4
	p.enemy_health_scale = 2.0
	# (5 esqueletos + 3 vampiros + 2 calaveras + 1 jefe) * 2 + 4 trampas * 0.5 = 59.0915.
	_assert_close(DifficultyCurve.index_for(p), (5 * SKELETON + 3 * VAMPIRE + 2 * SKULL + BOSS) * 2.0 + 2.0,
			"índice con vida ×2")


func test_enemy_health_scale_grows_linearly() -> void:
	_assert_close(LevelGenerator.enemy_health_scale(1), 1.0, "nivel 1")
	_assert_close(LevelGenerator.enemy_health_scale(2), 1.08, "nivel 2")
	_assert_close(LevelGenerator.enemy_health_scale(10), 1.72, "nivel 10")
	_assert_close(LevelGenerator.enemy_health_scale(100), 8.92, "nivel 100")
	_assert_close(LevelGenerator.enemy_health_scale(0), 1.0, "nunca baja de 1")
	_assert_close(LevelGenerator.params_for_level(10).enemy_health_scale, 1.72, "Params del nivel 10")
	var rows := DifficultyCurve.report(10, 10)
	_assert_close(rows[0]["health_scale"], 1.72, "columna del informe")


func test_index_for_level_matches_hand_computed_value() -> void:
	# Nivel 7 (escalón 6): 18 enemigos, proporción 0.7 -> 13 perseguidores,
	# 5 calaveras (13 * 0.4 redondeado), 8 vampiros, 5 esqueletos, 2 jefes,
	# 1 torre, 1 mímico y 11 trampas. Vida ×1.48: (5 esqueletos + 8 vampiros
	# + 5 calaveras + 2 jefes + 1 torre + 1 mímico) * 1.48 + 5.5 = 94.7788.
	var p := LevelGenerator.params_for_level(7)
	assert_eq(p.enemy_count, 18)
	assert_eq(LevelGenerator.chaser_count(p), 13)
	assert_eq(p.skull_count, 5)
	assert_eq(p.boss_count, 2)
	assert_eq(p.hazard_count, 11)
	assert_eq(p.special_counts, {
		LevelGenerator.SKULL_TURRET: 1, LevelGenerator.MIMIC: 1,
		LevelGenerator.ARCHER: 0, LevelGenerator.MAGE: 0,
	})
	var level_7 := (5 * SKELETON + 8 * VAMPIRE + 5 * SKULL + 2 * BOSS + SKULL_TURRET + MIMIC) * 1.48 + 5.5
	_assert_close(level_7, 94.778824, "cuenta a mano del nivel 7")
	_assert_close(DifficultyCurve.index_for_level(7), level_7, "índice del nivel 7")
	# Nivel 6: 6 esqueletos, 6 vampiros, 4 calaveras, 2 jefes, 1 torre,
	# 1 mímico, 10 trampas y vida ×1.4 = 81.0346.
	var level_6 := (6 * SKELETON + 6 * VAMPIRE + 4 * SKULL + 2 * BOSS + SKULL_TURRET + MIMIC) * 1.4 + 5.0
	_assert_close(DifficultyCurve.growth(7), level_7 / level_6 - 1.0, "crecimiento del nivel 7")


func test_index_keeps_growing_after_the_caps() -> void:
	# Desde el nivel 14 el cupo de comunes está al tope (7 esqueletos, 10
	# vampiros, 7 calaveras y 2 jefes = 70.1307 de enemigos). En el 14 hay
	# además 3 torres, 2 mímicos, 3 arqueros y 2 magos y 18 trampas (9):
	# (70.1307 + 25.9379) * 2.04 + 9 = 204.98, igual que antes de los cambios
	# del 15 en adelante.
	var capped := 7 * SKELETON + 10 * VAMPIRE + 7 * SKULL + 2 * BOSS
	var level_14 := capped + 3 * SKULL_TURRET + 2 * MIMIC + 3 * ARCHER + 2 * MAGE
	_assert_close(DifficultyCurve.index_for_level(14), level_14 * 2.04 + 9.0, "índice del nivel 14")
	_assert_close(DifficultyCurve.index_for_level(14), 204.98, "índice del nivel 14 a mano")

	# Nivel 25 (escalón 24): 4 conversiones (15, 18, 21, 24), las 4 de
	# esqueletos, a arquero, mago, mímico y arquero: quedan 3 esqueletos, 10
	# vampiros y 7 calaveras. Especiales: 3 torres, 2 + 1 mímicos, 6 + 2
	# arqueros y 4 + 1 magos. Vida ×2.92, primer escalón de daño (golpe de 3
	# medios: ×1.5) y 29 trampas (14.5):
	# (3 esq + 10 vamp + 7 cal + 2 jefes + 3 torres + 3 mím + 8 arq + 5 magos)
	# = 117.0817 -> 117.0817 * 2.92 * 1.5 + 14.5 = 527.3178.
	var level_25 := 3 * SKELETON + 10 * VAMPIRE + 7 * SKULL + 2 * BOSS \
			+ 3 * SKULL_TURRET + 3 * MIMIC + 8 * ARCHER + 5 * MAGE
	_assert_close(level_25, 117.081699, "enemigos del nivel 25")
	_assert_close(DifficultyCurve.index_for_level(25), level_25 * 2.92 * 1.5 + 14.5, "índice del nivel 25")
	_assert_close(DifficultyCurve.index_for_level(25), 527.317843, "índice del nivel 25 a mano")

	# Nivel 100: las 17 conversiones (tope: todos los esqueletos y vampiros)
	# van, rotando, a 6 arqueros, 6 magos y 5 mímicos. Quedan 7 calaveras y 2
	# jefes; especiales: 3 torres, 2 + 5 = 7 mímicos, 6 + 6 = 12 arqueros y
	# 5 + 6 = 11 magos = 130.8399. Vida ×8.92, golpe de 5 medios (bonus 3,
	# el tope: ×2.5) y 30 trampas (15):
	# 130.8399 * 8.92 * 2.5 + 15 = 2932.7291 (antes 923.6498, solo con la vida).
	var all_capped := 7 * SKULL + 2 * BOSS + 3 * SKULL_TURRET + 7 * MIMIC + 12 * ARCHER + 11 * MAGE
	_assert_close(all_capped, 130.839869, "enemigos al tope")
	_assert_close(DifficultyCurve.index_for_level(100), all_capped * 8.92 * 2.5 + 15.0, "índice del nivel 100")
	_assert_close(DifficultyCurve.index_for_level(100), 2932.729085, "índice del nivel 100 a mano")


func test_damage_factor_multiplies_enemies_but_not_hazards() -> void:
	var p := LevelGenerator.Params.new()
	p.enemy_count = 10
	p.chaser_share = 0.5
	p.skull_count = 2
	p.boss_count = 1
	p.hazard_count = 4
	var enemies := 5 * SKELETON + 3 * VAMPIRE + 2 * SKULL + BOSS
	# Golpe base de 2 medios corazones: (2 + bonus) / 2.
	for case: Array in [[0, 1.0], [1, 1.5], [2, 2.0], [3, 2.5], [7, 2.5]]:
		p.enemy_damage_bonus = case[0]
		_assert_close(DifficultyCurve.damage_factor(p), case[1], "factor con bonus %d" % case[0])
		_assert_close(DifficultyCurve.index_for(p), enemies * case[1] + 4 * 0.5,
				"índice con bonus %d: las trampas no se multiplican" % case[0])
	# Vida ×2 y bonus 1: (5 esq + 3 vamp + 2 cal + 1 jefe = 28.5458) * 2 * 1.5
	# + 4 trampas * 0.5 = 87.6373.
	p.enemy_health_scale = 2.0
	p.enemy_damage_bonus = 1
	_assert_close(DifficultyCurve.index_for(p), 87.637255, "vida ×2 y golpe ×1.5")


func test_boss_index_uses_the_same_health_and_damage_factor() -> void:
	# Nivel 28 (Guardián): vida ×3.16 y golpe ×1.5. El jefe temático (10)
	# reemplaza a la parca de la puerta (6 / 0.9): (10 - 6.6667) * 3.16 * 1.5 = 15.8.
	var p := LevelGenerator.params_for_level(28)
	assert_eq(p.theme_boss, BossRegistry.WARDEN)
	_assert_close(DifficultyCurve.boss_index_for(p) - DifficultyCurve.index_for(p), 15.8, "jefe del nivel 28")
	var plain := LevelGenerator.params_for_level(27)
	_assert_close(DifficultyCurve.boss_index_for(plain), DifficultyCurve.index_for(plain), "sin jefe es igual")


func test_damage_bonus_steps_and_cap() -> void:
	assert_true(LevelGenerator.DAMAGE_FIRST_LEVEL >= 20, "el primer escalón no llega antes del nivel 20")
	var expected := {1: 0, 14: 0, 24: 0, 25: 1, 44: 1, 45: 2, 64: 2, 65: 3, 100: 3, 1000: 3}
	for level: int in expected:
		assert_eq(LevelGenerator.enemy_damage_bonus(level), expected[level], "bonus del nivel %d" % level)
		assert_eq(LevelGenerator.params_for_level(level).enemy_damage_bonus, expected[level],
				"Params del nivel %d" % level)
	# Golpe base de 2 medios: 2, 3, 4, 5 y después se queda en 5.
	var hits: Array[int] = []
	for bonus in 6:
		hits.append(LevelGenerator.scaled_hit(LevelGenerator.BASE_ENEMY_HIT, bonus))
	assert_eq(hits, [2, 3, 4, 5, 5, 5] as Array[int])
	assert_eq(LevelGenerator.scaled_hit(0, 3), 0, "lo que no lastima sigue sin lastimar")
	assert_eq(LevelGenerator.scaled_hit(1, 9), LevelGenerator.MAX_SCALED_HIT)
	assert_eq(LevelGenerator.scaled_hit(6, 3), 6, "un golpe diseñado más fuerte que el tope no baja")
	assert_eq(LevelGenerator.scaled_hit(2, -1), 2, "un bonus negativo no resta")
	# Nunca un golpe de enemigo escalado mata de una vez con la vida llena.
	var player: Node = track(ResourceLoader.load("res://scenes/Player.tscn", "",
			ResourceLoader.CACHE_MODE_IGNORE).instantiate())
	var full_health: int = player.max_health
	assert_eq(full_health, 6, "3 corazones = 6 medios")
	for level in range(1, DifficultyCurve.LAST_LEVEL + 1):
		var hit := LevelGenerator.scaled_hit(LevelGenerator.BASE_ENEMY_HIT, LevelGenerator.enemy_damage_bonus(level))
		assert_true(hit < full_health, "golpe de %d medios en el nivel %d" % [hit, level])


func test_commons_convert_into_specials_from_level_15() -> void:
	# Una conversión en el 15 y otra cada 3 niveles; primero esqueletos (7),
	# después vampiros (10), nunca calaveras; destino arquero, mago, mímico...
	var expected := {
		14: [0, 0], 15: [1, 0], 17: [1, 0], 18: [2, 0], 33: [7, 0], 36: [7, 1], 63: [7, 10], 100: [7, 10],
	}
	for level: int in expected:
		var p := LevelGenerator.params_for_level(level)
		assert_eq([p.converted_skeletons, p.converted_vampires], expected[level], "conversiones del nivel %d" % level)
	var p15 := LevelGenerator.params_for_level(15)
	assert_eq(p15.special_counts[LevelGenerator.ARCHER], LevelGenerator.special_count(LevelGenerator.ARCHER, 15) + 1,
			"la primera conversión es un arquero")
	var p18 := LevelGenerator.params_for_level(18)
	assert_eq(p18.special_counts[LevelGenerator.MAGE], LevelGenerator.special_count(LevelGenerator.MAGE, 18) + 1,
			"la segunda, un mago")
	assert_eq(LevelGenerator.conversion_count(14), 0)
	assert_eq(LevelGenerator.conversion_count(15), 1)
	assert_eq(LevelGenerator.conversion_count(63), 17)

	for level in range(LevelGenerator.FIRST_GENERATED_LEVEL, DifficultyCurve.LAST_LEVEL + 1):
		var p := LevelGenerator.params_for_level(level)
		var rule_specials := 0
		for kind: StringName in LevelGenerator.SPECIAL_ENEMIES:
			rule_specials += LevelGenerator.special_count(kind, level)
		var converted := p.converted_skeletons + p.converted_vampires
		assert_eq(LevelGenerator.common_count(p) + LevelGenerator.special_total(p), p.enemy_count + rule_specials,
				"nivel %d: convertir no cambia el total de enemigos" % level)
		assert_eq(LevelGenerator.special_total(p), rule_specials + converted, "nivel %d" % level)
		assert_eq(p.skull_count, roundi(LevelGenerator.chaser_count(p) * LevelGenerator.SKULL_CHASER_SHARE) \
				if level >= LevelGenerator.SKULL_FIRST_LEVEL else 0, "nivel %d: las calaveras se quedan" % level)
		assert_eq(p.special_counts[LevelGenerator.SKULL_TURRET],
				LevelGenerator.special_count(LevelGenerator.SKULL_TURRET, level), "nivel %d: no se convierte en torre" % level)
		assert_true(LevelGenerator.skeleton_count(p) >= 0 and LevelGenerator.vampire_count(p) >= 0, "nivel %d" % level)


func test_special_and_hazard_caps_keep_growing_after_18() -> void:
	# Arqueros hasta 6 (nivel 23), magos hasta 5 (26) y trampas hasta 30
	# (26); antes paraban en 4 (17), 3 (18) y 18 (14).
	assert_eq(LevelGenerator.special_count(LevelGenerator.ARCHER, 17), 4)
	assert_eq(LevelGenerator.special_count(LevelGenerator.ARCHER, 23), 6)
	assert_eq(LevelGenerator.special_count(LevelGenerator.ARCHER, 100), 6)
	assert_eq(LevelGenerator.special_count(LevelGenerator.MAGE, 18), 3)
	assert_eq(LevelGenerator.special_count(LevelGenerator.MAGE, 26), 5)
	assert_eq(LevelGenerator.special_count(LevelGenerator.MAGE, 100), 5)
	assert_eq(LevelGenerator.params_for_level(14).hazard_count, 18)
	assert_eq(LevelGenerator.params_for_level(25).hazard_count, 29)
	assert_eq(LevelGenerator.params_for_level(26).hazard_count, LevelGenerator.HAZARDS_MAX)
	assert_eq(LevelGenerator.HAZARDS_MAX, 30)
	var previous := LevelGenerator.params_for_level(18)
	for level in range(19, 27):
		var p := LevelGenerator.params_for_level(level)
		var grew := LevelGenerator.special_total(p) > LevelGenerator.special_total(previous) \
				or p.hazard_count > previous.hazard_count
		assert_true(grew, "el nivel %d suma especiales o trampas" % level)
		previous = p


func test_levels_up_to_14_are_unchanged() -> void:
	# Los cambios del 15 en adelante no tocan los niveles tempranos: sin
	# conversiones ni bonus de daño, y los topes nuevos todavía no se alcanzan.
	for level in range(LevelGenerator.FIRST_GENERATED_LEVEL, DifficultyCurve.TARGET_GROWTH_LAST_LEVEL + 1):
		var p := LevelGenerator.params_for_level(level)
		assert_eq(p.converted_skeletons + p.converted_vampires, 0, "nivel %d" % level)
		assert_eq(p.enemy_damage_bonus, 0, "nivel %d" % level)
		_assert_close(DifficultyCurve.damage_factor(p), 1.0, "nivel %d" % level)


func test_planned_index_matches_the_server_seed() -> void:
	for level: int in SERVER_SEED_INDEX:
		assert_true(absf(DifficultyCurve.index_for_level(level) - SERVER_SEED_INDEX[level]) < 0.0005,
				"nivel %d: %.4f en el juego, %.3f en seed.py" % [level, DifficultyCurve.index_for_level(level),
				SERVER_SEED_INDEX[level]])


func test_first_generated_level_has_no_growth() -> void:
	assert_true(is_nan(DifficultyCurve.growth(LevelGenerator.FIRST_GENERATED_LEVEL)))
	var rows := DifficultyCurve.report(2, 3)
	assert_true(rows[0]["meets_target"], "sin nivel anterior no hay objetivo que incumplir")


func test_index_grows_every_level() -> void:
	# Con la vida escalada no hay mesetas planas: cada nivel supera al anterior.
	var previous := DifficultyCurve.index_for_level(LevelGenerator.FIRST_GENERATED_LEVEL)
	for level in range(LevelGenerator.FIRST_GENERATED_LEVEL + 1, DifficultyCurve.LAST_LEVEL + 1):
		var current := DifficultyCurve.index_for_level(level)
		assert_true(current > previous, "el índice no crece en el nivel %d (%.2f -> %.2f)" % [level, previous, current])
		previous = current


func test_report_covers_every_level_with_consistent_counts() -> void:
	var rows := DifficultyCurve.report()
	assert_eq(rows.size(), DifficultyCurve.LAST_LEVEL - LevelGenerator.FIRST_GENERATED_LEVEL + 1)
	assert_eq(rows[0]["level"], LevelGenerator.FIRST_GENERATED_LEVEL)
	assert_eq(rows[-1]["level"], DifficultyCurve.LAST_LEVEL)
	for row in rows:
		assert_eq(row["skeletons"] + row["vampires"] + row["skulls"], row["enemies"],
				"reparto de enemigos del nivel %d" % row["level"])
	for row in rows:
		var converted := row["converted"] as int
		assert_eq(row["archers"] + row["skull_turrets"] + row["mimics"] + row["mages"],
				LevelGenerator.special_total(LevelGenerator.params_for_level(row["level"])),
				"especiales del nivel %d" % row["level"])
		assert_true(converted >= 0, "conversiones del nivel %d" % row["level"])
		assert_eq(row["hit"], LevelGenerator.scaled_hit(LevelGenerator.BASE_ENEMY_HIT, row["damage_bonus"]),
				"golpe del nivel %d" % row["level"])
	# Desde el nivel 14 el cupo de comunes está al tope; las trampas, desde el
	# 26, y el daño, desde el 65.
	var caps: Array = rows[14 - LevelGenerator.FIRST_GENERATED_LEVEL]["capped_params"]
	for cap in [DifficultyCurve.CAP_ENEMIES, DifficultyCurve.CAP_CHASER_SHARE]:
		assert_true(cap in caps, "el nivel 14 debería tener el tope %s" % cap)
	assert_false(DifficultyCurve.CAP_HAZARDS in caps, "las trampas siguen creciendo después del 14")
	assert_true(DifficultyCurve.CAP_HAZARDS in rows[26 - LevelGenerator.FIRST_GENERATED_LEVEL]["capped_params"])
	assert_false(DifficultyCurve.CAP_DAMAGE in rows[64 - LevelGenerator.FIRST_GENERATED_LEVEL]["capped_params"])
	assert_true(DifficultyCurve.CAP_DAMAGE in rows[65 - LevelGenerator.FIRST_GENERATED_LEVEL]["capped_params"])


func test_format_levels_compacts_ranges() -> void:
	var levels: Array[int] = [3, 8, 9, 10, 12, 20, 21]
	assert_eq(DifficultyCurve.format_levels(levels), "3, 8-10, 12, 20-21")
	assert_eq(DifficultyCurve.format_levels([] as Array[int]), "")


func test_levels_up_to_14_meet_the_target_growth() -> void:
	# Primer tramo: +10 % por nivel hasta el 14, salvo los niveles que ya hoy
	# no lo cumplen y se dejaron como están (EARLY_LEVELS_BELOW_TARGET).
	var rows := DifficultyCurve.report(LevelGenerator.FIRST_GENERATED_LEVEL, DifficultyCurve.TARGET_GROWTH_LAST_LEVEL)
	var failing := DifficultyCurve.failing_levels(rows)
	var unexpected: Array[int] = []
	for level in failing:
		if not level in EARLY_LEVELS_BELOW_TARGET:
			unexpected.append(level)
	assert_true(unexpected.is_empty(), "niveles hasta el 14 que crecen menos del %d %%: %s" % [
			roundi(DifficultyCurve.TARGET_GROWTH * 100.0), DifficultyCurve.format_levels(unexpected)])
	for level in EARLY_LEVELS_BELOW_TARGET:
		assert_true(DifficultyCurve.growth(level) > 0.0, "el nivel %d crece aunque no llegue al 10 %%" % level)


func test_index_escalates_tenfold_from_14_to_100() -> void:
	# Segundo tramo: la curva sigue escalando después del 14. Antes de estos
	# cambios el 100 era ×4.5 del 14 (923.65 / 204.98); el objetivo es ×10.
	var escalation := DifficultyCurve.escalation()
	assert_true(escalation >= DifficultyCurve.ESCALATION_TARGET,
			"el nivel 100 es ×%.2f del 14, se pide ×%.0f" % [escalation, DifficultyCurve.ESCALATION_TARGET])
	_assert_close(escalation, DifficultyCurve.index_for_level(100) / DifficultyCurve.index_for_level(14), "escalada")
	var rows := DifficultyCurve.report(DifficultyCurve.TARGET_GROWTH_LAST_LEVEL + 1)
	assert_true(DifficultyCurve.failing_levels(rows).is_empty(), "del 15 al 100 cada nivel sube algo")


func test_generated_levels_place_what_they_request() -> void:
	for level in CAPACITY_LEVELS:
		for run_seed in CAPACITY_SEEDS:
			var report := DifficultyCurve.capacity_report(level, run_seed)
			var where := "nivel %d semilla %d" % [level, run_seed]
			assert_false(report["used_fallback"], "diseño de emergencia, " + where)
			assert_eq(report["placed_enemies"], report["requested_enemies"], "enemigos colocados, " + where)
			assert_eq(report["placed_hazards"], report["requested_hazards"], "trampas colocadas, " + where)
			assert_true(report["free_cells"] <= report["spawnable_cells"], "celdas libres, " + where)


# ----- ayudas -----

func _assert_close(actual: float, expected: float, msg: String = "") -> void:
	assert_true(absf(actual - expected) < 0.0001, "%s: %.4f, se esperaba %.4f" % [msg, actual, expected])
