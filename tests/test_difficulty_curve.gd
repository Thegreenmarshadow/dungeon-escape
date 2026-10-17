@tool
extends McpTestSuite
## Pruebas de la curva de dificultad (DifficultyCurve).
##
## test_every_level_meets_the_target_growth expresa el objetivo de diseño
## (+10 % de índice por nivel, del 2 al 100). Con los números actuales de
## LevelGenerator falla a propósito: la vida de los enemigos crece de forma
## lineal (+8 % de la base por nivel), así que una vez alcanzados los topes de
## cantidad el crecimiento relativo es de aproximadamente 0.08 / multiplicador,
## que ya es menor al 10 % desde que se alcanzan los topes. El índice sigue subiendo en cada nivel,
## sin quedar plano. No se ajustan las constantes para que pase; el mensaje de
## fallo indica los niveles que no cumplen.

## Pesos efectivos (peso / (1 - esquiva)) escritos a mano, para que las
## cuentas de las pruebas no dependan de las constantes que comprueban.
const SKELETON := 1.5 / 0.85
const VAMPIRE := 2.0 / 0.8
const SKULL := 2.5 / 0.9
const BOSS := 6.0 / 0.9

## Escena de cada tipo y la constante de esquiva de DifficultyCurve que la copia.
const DODGE_BY_SCENE := {
	"res://scenes/Skeleton.tscn": DifficultyCurve.DODGE_SKELETON,
	"res://scenes/Vampire.tscn": DifficultyCurve.DODGE_VAMPIRE,
	"res://scenes/Skull.tscn": DifficultyCurve.DODGE_SKULL,
	"res://scenes/Reaper.tscn": DifficultyCurve.DODGE_BOSS,
}

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
	# Multiplicador de vida 1 (el valor por defecto de Params). Pesos 1.5, 2,
	# 2.5 y 6, cada uno dividido por (1 - esquiva): 0.15, 0.2, 0.1 y 0.1.
	# 5 esqueletos + 3 vampiros + 2 calaveras + 1 jefe + 4 trampas * 0.5 = 30.5458.
	var expected := 5 * SKELETON + 3 * VAMPIRE + 2 * SKULL + BOSS + 4 * 0.5
	_assert_close(expected, 30.545752, "cuenta a mano")
	_assert_close(DifficultyCurve.index_for(p), expected, "índice de parámetros hechos a mano")


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
	# 5 calaveras (13 * 0.4 redondeado), 8 vampiros, 5 esqueletos, 2 jefes y
	# 11 trampas. Vida ×1.48: (5 esqueletos + 8 vampiros + 5 calaveras + 2 jefes)
	# * 1.48 + 5.5 = 88.4477.
	var p := LevelGenerator.params_for_level(7)
	assert_eq(p.enemy_count, 18)
	assert_eq(LevelGenerator.chaser_count(p), 13)
	assert_eq(p.skull_count, 5)
	assert_eq(p.boss_count, 2)
	assert_eq(p.hazard_count, 11)
	var level_7 := (5 * SKELETON + 8 * VAMPIRE + 5 * SKULL + 2 * BOSS) * 1.48 + 5.5
	_assert_close(DifficultyCurve.index_for_level(7), level_7, "índice del nivel 7")
	# Nivel 6: 6 esqueletos, 6 vampiros, 4 calaveras, 2 jefes, 10 trampas y
	# vida ×1.4 = 75.0458.
	var level_6 := (6 * SKELETON + 6 * VAMPIRE + 4 * SKULL + 2 * BOSS) * 1.4 + 5.0
	_assert_close(DifficultyCurve.growth(7), level_7 / level_6 - 1.0, "crecimiento del nivel 7")


func test_index_keeps_growing_after_the_caps() -> void:
	# Desde el nivel 14 las cantidades están al tope (7 esqueletos, 10 vampiros,
	# 7 calaveras y 2 jefes = 70.1307 de enemigos, y 9 de trampas); solo crece
	# la vida: 70.1307 * 2.04 + 9 y 70.1307 * 8.92 + 9.
	var capped := 7 * SKELETON + 10 * VAMPIRE + 7 * SKULL + 2 * BOSS
	_assert_close(DifficultyCurve.index_for_level(14), capped * 2.04 + 9.0, "índice del nivel 14")
	_assert_close(DifficultyCurve.index_for_level(14), 152.066667, "índice del nivel 14 a mano")
	_assert_close(DifficultyCurve.index_for_level(100), 634.566013, "índice del nivel 100")


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
