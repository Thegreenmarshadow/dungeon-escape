@tool
extends McpTestSuite
## Pruebas de la curva de dificultad (DifficultyCurve).
##
## test_every_level_meets_the_target_growth expresa el objetivo de diseño
## (+10 % de índice por nivel, del 2 al 100). Con los números actuales de
## LevelGenerator falla a propósito: la curva baja del 10 % en el nivel 8 y
## queda en meseta desde el nivel 11, cuando se alcanzan los topes. No se
## ajustan las constantes para que pase; el mensaje de fallo indica los
## niveles que no cumplen.

## Niveles y semillas de la prueba de capacidad.
const CAPACITY_LEVELS := [2, 5, 10, 20]
const CAPACITY_SEEDS := [1, 2, 3, 4, 5]


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
	# 5 esqueletos * 1 + 3 vampiros * 2 + 2 calaveras * 2.5 + 1 jefe * 6 + 4 trampas * 0.5
	_assert_close(DifficultyCurve.index_for(p), 24.0, "índice de parámetros hechos a mano")


func test_index_for_level_matches_hand_computed_value() -> void:
	# Nivel 7 (escalón 6): 18 enemigos, proporción 0.7 -> 13 perseguidores,
	# 5 calaveras (13 * 0.4 redondeado), 8 vampiros, 5 esqueletos, 2 jefes y
	# 11 trampas: 5 + 16 + 12.5 + 12 + 5.5 = 51.
	var p := LevelGenerator.params_for_level(7)
	assert_eq(p.enemy_count, 18)
	assert_eq(LevelGenerator.chaser_count(p), 13)
	assert_eq(p.skull_count, 5)
	assert_eq(p.boss_count, 2)
	assert_eq(p.hazard_count, 11)
	_assert_close(DifficultyCurve.index_for_level(7), 51.0, "índice del nivel 7")
	# Crecimiento del nivel 7 respecto del 6 (índice 45): 51 / 45 - 1.
	_assert_close(DifficultyCurve.growth(7), 51.0 / 45.0 - 1.0, "crecimiento del nivel 7")


func test_first_generated_level_has_no_growth() -> void:
	assert_true(is_nan(DifficultyCurve.growth(LevelGenerator.FIRST_GENERATED_LEVEL)))
	var rows := DifficultyCurve.report(2, 3)
	assert_true(rows[0]["meets_target"], "sin nivel anterior no hay objetivo que incumplir")


func test_index_never_decreases() -> void:
	var previous := DifficultyCurve.index_for_level(LevelGenerator.FIRST_GENERATED_LEVEL)
	for level in range(LevelGenerator.FIRST_GENERATED_LEVEL + 1, DifficultyCurve.LAST_LEVEL + 1):
		var current := DifficultyCurve.index_for_level(level)
		assert_true(current >= previous, "el índice baja en el nivel %d (%.2f -> %.2f)" % [level, previous, current])
		previous = current


func test_report_covers_every_level_with_consistent_counts() -> void:
	var rows := DifficultyCurve.report()
	assert_eq(rows.size(), DifficultyCurve.LAST_LEVEL - LevelGenerator.FIRST_GENERATED_LEVEL + 1)
	assert_eq(rows[0]["level"], LevelGenerator.FIRST_GENERATED_LEVEL)
	assert_eq(rows[-1]["level"], DifficultyCurve.LAST_LEVEL)
	for row in rows:
		assert_eq(row["skeletons"] + row["vampires"] + row["skulls"], row["enemies"],
				"reparto de enemigos del nivel %d" % row["level"])
	# Desde el nivel 14 se alcanzaron todos los topes de cantidad.
	var caps: Array = rows[14 - LevelGenerator.FIRST_GENERATED_LEVEL]["capped_params"]
	for cap in [DifficultyCurve.CAP_ENEMIES, DifficultyCurve.CAP_CHASER_SHARE, DifficultyCurve.CAP_HAZARDS]:
		assert_true(cap in caps, "el nivel 14 debería tener el tope %s" % cap)


func test_format_levels_compacts_ranges() -> void:
	var levels: Array[int] = [3, 8, 9, 10, 12, 20, 21]
	assert_eq(DifficultyCurve.format_levels(levels), "3, 8-10, 12, 20-21")
	assert_eq(DifficultyCurve.format_levels([] as Array[int]), "")


func test_every_level_meets_the_target_growth() -> void:
	# Objetivo de diseño: cada nivel del 2 al 100 sube el índice al menos
	# TARGET_GROWTH. Se espera que falle con los números actuales.
	var rows := DifficultyCurve.report()
	var failing := DifficultyCurve.failing_levels(rows)
	assert_true(failing.is_empty(),
			"%d de %d niveles crecen menos del %d %%: %s (meseta desde el nivel %d)" % [
				failing.size(), rows.size() - 1, roundi(DifficultyCurve.TARGET_GROWTH * 100.0),
				DifficultyCurve.format_levels(failing), DifficultyCurve.plateau_start(rows)])


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
