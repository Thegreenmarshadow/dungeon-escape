@tool
class_name LevelStats
extends RefCounted
## Estadísticas por nivel a partir de los archivos de telemetría ya
## normalizados (TelemetryStore.load_levels): intentos, muertes, % que
## completa, tiempo medio, daño por minuto y por fuente, armas usadas, muertes
## por causa y la dificultad medida.
##
## Es lógica pura y sin estado (solo funciones estáticas): la usan la
## exportación a CSV, los avisos automáticos, la gráfica de DifficultyReport y
## las pruebas.
##
## Dificultad medida (0–1) de un nivel L, entre los niveles analizados juntos:
##   muertes_por_intento(L) = eventos "death" de L / intentos de L
##   daño_por_minuto(L)     = suma de "amount" (corazones) de los eventos "damage" de L
##                            / (suma de duration_s de L / 60)
##   muertes_norm(L) = muertes_por_intento(L) / máximo de muertes_por_intento
##   daño_norm(L)    = daño_por_minuto(L) / máximo de daño_por_minuto
##   medida(L) = WEIGHT_DEATHS * muertes_norm(L) + WEIGHT_DAMAGE * daño_norm(L)
## Cada término se normaliza dividiendo por el máximo entre los niveles (si el
## máximo es 0, el término vale 0), así el nivel más letal vale 1 en ese
## término. Con pesos que suman 1, la medida queda entre 0 y 1. Es relativa:
## compara niveles del mismo conjunto de datos, no entre conjuntos distintos.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

## Modos que no entran en las estadísticas por nivel: la demo es un mapa hecho
## a mano distinto del nivel 1 normal y además revive al jugador.
const EXCLUDED_MODES: Array[String] = ["demo"]
## Peso de las muertes por intento en la dificultad medida.
const WEIGHT_DEATHS := 0.5
## Peso del daño por minuto en la dificultad medida.
const WEIGHT_DAMAGE := 0.5
## Nombre de la fuente de daño o causa de muerte vacía.
const UNKNOWN_SOURCE := "unknown"
## La gráfica muestra al menos hasta este nivel aunque no haya datos.
const CHART_MIN_LAST_LEVEL := 10

const _OUTCOME_COMPLETED := "completed"
const _OUTCOME_DIED := "died"
const _OUTCOME_ABANDONED := "abandoned"
const _EVENT_DAMAGE := "damage"
const _EVENT_DEATH := "death"


## Una fila por nivel (ordenadas por nivel) con estas claves:
##   level, attempts (archivos terminados: completado, muerte o abandono),
##   completed, died, abandoned (intentos por resultado),
##   completion_rate, death_rate, abandon_rate (0–1, sobre los intentos),
##   deaths (eventos "death", incluye los knock-out que no terminan el nivel),
##   deaths_by_cause {causa: n}, total_time_s, mean_time_s,
##   damage_total, damage_per_min, damage_by_source {fuente: daño} (el daño
##   en corazones, como en la telemetría: puede tener medios),
##   weapons_used (Array[String], en orden de primera aparición),
##   deaths_per_attempt, deaths_norm, damage_norm, measured_difficulty.
## Ignora los archivos "in_progress" y los modos de excluded_modes.
static func aggregate(levels: Array, excluded_modes: Array[String] = EXCLUDED_MODES) -> Array[Dictionary]:
	var by_level := {}
	for data: Variant in levels:
		if not data is Dictionary:
			continue
		var outcome := str(data.get("outcome", ""))
		if outcome not in [_OUTCOME_COMPLETED, _OUTCOME_DIED, _OUTCOME_ABANDONED]:
			continue
		if str(data.get("mode", "")) in excluded_modes:
			continue
		var level := int(data.get("level", 0))
		if not by_level.has(level):
			by_level[level] = _empty_row(level)
		_add_level_file(by_level[level], data)

	var rows: Array[Dictionary] = []
	var keys := by_level.keys()
	keys.sort()
	for level: int in keys:
		rows.append(_finish_row(by_level[level]))
	apply_measured_difficulty(rows)
	return rows


## Calcula deaths_norm, damage_norm y measured_difficulty de cada fila según
## la fórmula del encabezado. Modifica las filas.
static func apply_measured_difficulty(rows: Array[Dictionary]) -> void:
	var max_deaths := 0.0
	var max_damage := 0.0
	for row in rows:
		max_deaths = maxf(max_deaths, row["deaths_per_attempt"])
		max_damage = maxf(max_damage, row["damage_per_min"])
	for row in rows:
		row["deaths_norm"] = _ratio(row["deaths_per_attempt"], max_deaths)
		row["damage_norm"] = _ratio(row["damage_per_min"], max_damage)
		row["measured_difficulty"] = measured_difficulty(
				row["deaths_per_attempt"], row["damage_per_min"], max_deaths, max_damage)


## Dificultad medida de un nivel dados sus valores y los máximos del conjunto.
static func measured_difficulty(deaths_per_attempt: float, damage_per_min: float,
		max_deaths_per_attempt: float, max_damage_per_min: float) -> float:
	return WEIGHT_DEATHS * _ratio(deaths_per_attempt, max_deaths_per_attempt) \
			+ WEIGHT_DAMAGE * _ratio(damage_per_min, max_damage_per_min)


## Índice planificado (DifficultyCurve.index_for) del nivel; NAN para los
## niveles hechos a mano (antes de LevelGenerator.FIRST_GENERATED_LEVEL).
static func planned_index(level: int) -> float:
	if level < LevelGenerator.FIRST_GENERATED_LEVEL or level > DifficultyCurve.LAST_LEVEL:
		return NAN
	return DifficultyCurve.index_for(LevelGenerator.params_for_level(level))


## Todas las fuentes de daño de las filas, ordenadas (columnas del CSV).
static func all_sources(rows: Array[Dictionary]) -> PackedStringArray:
	var seen := {}
	for row in rows:
		for source: String in row["damage_by_source"]:
			seen[source] = true
	var sources := PackedStringArray(seen.keys())
	sources.sort()
	return sources


## Fuente con más muertes de la fila: {cause, count, share (0–1 sobre deaths)}.
## cause es "" si no hubo muertes.
static func top_death_cause(row: Dictionary) -> Dictionary:
	var best := ""
	var best_count := 0
	var causes: Dictionary = row["deaths_by_cause"]
	var keys := causes.keys()
	keys.sort()
	for cause: String in keys:
		if causes[cause] > best_count:
			best = cause
			best_count = causes[cause]
	return {"cause": best, "count": best_count, "share": _ratio(best_count, row["deaths"])}


## Puntos de la gráfica de DifficultyReport, un punto por nivel desde 1 hasta
## last_level (por defecto el último con datos, al menos CHART_MIN_LAST_LEVEL):
##   level, planned_raw (índice o NAN), planned (índice / máximo índice del
##   rango, 0–1, o NAN), measured (dificultad medida o NAN si no hay
##   intentos) y attempts.
static func chart_rows(rows: Array[Dictionary], last_level: int = -1) -> Array[Dictionary]:
	var by_level := {}
	var last := CHART_MIN_LAST_LEVEL
	for row in rows:
		by_level[row["level"]] = row
		last = maxi(last, row["level"])
	if last_level > 0:
		last = last_level
	last = clampi(last, 1, DifficultyCurve.LAST_LEVEL)

	var points: Array[Dictionary] = []
	var max_planned := 0.0
	for level in range(1, last + 1):
		var planned := planned_index(level)
		if not is_nan(planned):
			max_planned = maxf(max_planned, planned)
		var row: Dictionary = by_level.get(level, {})
		points.append({
			"level": level,
			"planned_raw": planned,
			"measured": row.get("measured_difficulty", NAN),
			"attempts": row.get("attempts", 0),
		})
	for point in points:
		var raw: float = point["planned_raw"]
		point["planned"] = NAN if is_nan(raw) else _ratio(raw, max_planned)
	return points


# ---------------------------------------------------------------------------
# Ayudas
# ---------------------------------------------------------------------------

static func _empty_row(level: int) -> Dictionary:
	return {
		"level": level,
		"attempts": 0,
		"completed": 0,
		"died": 0,
		"abandoned": 0,
		"deaths": 0,
		"deaths_by_cause": {},
		"total_time_s": 0.0,
		"damage_total": 0.0,
		"damage_by_source": {},
		"weapons_used": [] as Array[String],
	}


static func _add_level_file(row: Dictionary, data: Dictionary) -> void:
	row["attempts"] += 1
	match str(data.get("outcome", "")):
		_OUTCOME_COMPLETED:
			row["completed"] += 1
		_OUTCOME_DIED:
			row["died"] += 1
		_OUTCOME_ABANDONED:
			row["abandoned"] += 1
	row["total_time_s"] += maxf(float(data.get("duration_s", 0.0)), 0.0)
	var events: Variant = data.get("events", [])
	if events is Array:
		for event: Variant in events:
			if not event is Dictionary:
				continue
			match str(event.get("type", "")):
				_EVENT_DAMAGE:
					var amount := JsonFile.to_float(event.get("amount", 0.0))
					var source := source_name(event.get("source", ""))
					row["damage_total"] += amount
					row["damage_by_source"][source] = row["damage_by_source"].get(source, 0.0) + amount
				_EVENT_DEATH:
					var cause := source_name(event.get("cause", ""))
					row["deaths"] += 1
					row["deaths_by_cause"][cause] = row["deaths_by_cause"].get(cause, 0) + 1
	var weapons: Variant = data.get("weapons_used", [])
	if weapons is Array:
		var used: Array[String] = row["weapons_used"]
		for weapon: Variant in weapons:
			var id := str(weapon)
			if not id.is_empty() and id not in used:
				used.append(id)


static func _finish_row(row: Dictionary) -> Dictionary:
	var attempts: int = row["attempts"]
	row["completion_rate"] = _ratio(row["completed"], attempts)
	row["death_rate"] = _ratio(row["died"], attempts)
	row["abandon_rate"] = _ratio(row["abandoned"], attempts)
	row["mean_time_s"] = _ratio(row["total_time_s"], attempts)
	row["damage_per_min"] = _ratio(row["damage_total"], row["total_time_s"] / 60.0)
	row["deaths_per_attempt"] = _ratio(row["deaths"], attempts)
	return row


## Nombre de una fuente de daño o causa de muerte; vacía = UNKNOWN_SOURCE.
static func source_name(value: Variant) -> String:
	var text := str(value).strip_edges()
	return UNKNOWN_SOURCE if text.is_empty() else text


## a / b, o 0 si b no es positivo.
static func _ratio(a: float, b: float) -> float:
	return a / b if b > 0.0 else 0.0
