@tool
extends McpTestSuite
## Dificultad medida (LevelStats): muertes por intento y daño por minuto,
## normalizados por su máximo entre niveles y combinados con pesos 0,5 / 0,5.
## Datos de ejemplo armados a mano (sin archivos).


func suite_name() -> String:
	return "level_stats"


func test_measured_difficulty_matches_expected_value_with_sample_data() -> void:
	var levels: Array[Dictionary] = [
		# Nivel 2: dos intentos de 60 s, una muerte, 4 de daño -> 0,5 muertes
		# por intento y 2 de daño por minuto.
		_level(2, "died", 60.0, [1, 2], "spikes"),
		_level(2, "completed", 60.0, [1], ""),
		# Nivel 3: un intento de 30 s, una muerte, 3 de daño -> 1 muerte por
		# intento y 6 de daño por minuto (los máximos).
		_level(3, "died", 30.0, [3], "Vampire"),
		# La demo no cuenta: si contara, el nivel 1 tendría muertes.
		_level(1, "abandoned", 10.0, [5], "spikes", "demo"),
	]
	var rows := LevelStats.aggregate(levels)
	assert_eq(rows.size(), 2, "la demo queda afuera")

	var level_2 := rows[0]
	assert_eq(level_2["level"], 2)
	assert_eq(level_2["attempts"], 2)
	assert_true(is_equal_approx(level_2["deaths_per_attempt"], 0.5), "muertes por intento")
	assert_true(is_equal_approx(level_2["damage_per_min"], 2.0), "daño por minuto")
	# 0,5 * (0,5 / 1) + 0,5 * (2 / 6) = 0,41667
	assert_true(is_equal_approx(level_2["measured_difficulty"], 0.25 + 1.0 / 6.0),
			"medida del nivel 2: %f" % level_2["measured_difficulty"])
	assert_true(is_equal_approx(rows[1]["measured_difficulty"], 1.0), "el nivel más difícil vale 1")
	assert_eq(LevelStats.measured_difficulty(0.0, 0.0, 0.0, 0.0), 0.0, "sin muertes ni daño vale 0")


func _level(level: int, outcome: String, duration: float, damage: Array, cause: String,
		mode: String = "normal") -> Dictionary:
	var events: Array = []
	for amount: int in damage:
		events.append({"t": 1.0, "type": "damage", "x": 0.0, "y": 0.0, "amount": amount, "source": cause})
	if outcome == "died" or mode == "demo":
		events.append({"t": duration, "type": "death", "x": 0.0, "y": 0.0, "cause": cause, "final": mode != "demo"})
	return TelemetryStore.normalize_level({
		"level": level, "mode": mode, "outcome": outcome, "duration_s": duration, "events": events,
	})
