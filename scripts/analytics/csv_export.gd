@tool
class_name CsvExport
extends RefCounted
## Exporta la telemetría a CSV para abrirla en una hoja de cálculo:
##   levels.csv  una fila por nivel (LevelStats): intentos, muertes, % que
##               completa, tiempo medio, daño por minuto, daño por fuente
##               (una columna damage_<fuente> por cada fuente de todos los
##               niveles, 0 donde no aparece), armas usadas y dificultad.
##   deaths.csv  una fila por evento "death": causa y posición (px y celda).
##   runs.csv    una fila por partida (perfil + run_id).
##
## Formato: UTF-8 con BOM (para que Excel lea bien los acentos), separador
## coma, decimales con punto, una fila de encabezado y siempre la misma
## cantidad de columnas. Los campos con coma, comillas o saltos de línea van
## entre comillas dobles (las comillas internas se duplican). El texto que
## empieza con = + - @ y no es un número lleva un apóstrofo delante para que la
## hoja de cálculo no lo tome como fórmula.
##
## La carpeta de destino se recibe por parámetro (por defecto DEFAULT_DIR).
##
## @tool: así las pruebas del editor pueden ejecutarlo.

const DEFAULT_DIR := "user://analytics"
const LEVELS_FILE := "levels.csv"
const DEATHS_FILE := "deaths.csv"
const RUNS_FILE := "runs.csv"
const SEPARATOR := ","
## Separador de las listas dentro de un campo (armas usadas).
const LIST_SEPARATOR := ";"
const BOM := "﻿"
## Prefijo de las columnas de daño por fuente en levels.csv.
const DAMAGE_COLUMN_PREFIX := "damage_"

const LEVELS_HEADER: Array[String] = [
	"level", "attempts", "completed", "died", "abandoned", "completion_pct",
	"deaths", "deaths_per_attempt", "mean_time_s", "total_time_s",
	"damage_total", "damage_per_min", "measured_difficulty", "planned_index",
	"weapons_used",
]
const DEATHS_HEADER: Array[String] = [
	"profile", "run_id", "mode", "game_version", "level", "attempt",
	"t_s", "x", "y", "cell_x", "cell_y", "cause", "final",
]
const RUNS_HEADER: Array[String] = [
	"profile", "run_id", "mode", "game_version", "seed", "started_at",
	"levels_played", "first_level", "last_level", "levels_completed", "deaths",
	"total_time_s", "damage_total", "last_outcome", "weapons_used",
]


## Escribe los tres CSV en dir (lo crea si hace falta). Devuelve
## {"error": Error, "files": PackedStringArray con las rutas escritas}.
static func export_all(levels: Array, dir: String = DEFAULT_DIR) -> Dictionary:
	var files := PackedStringArray()
	var error := DirAccess.make_dir_recursive_absolute(dir)
	if error != OK:
		return {"error": error, "files": files}
	var tables := {
		LEVELS_FILE: levels_table(LevelStats.aggregate(levels)),
		DEATHS_FILE: deaths_table(levels),
		RUNS_FILE: runs_table(levels),
	}
	for file_name: String in tables:
		var path := dir.path_join(file_name)
		error = write_csv(path, tables[file_name])
		if error != OK:
			return {"error": error, "files": files}
		files.append(path)
	return {"error": OK, "files": files}


## Encabezado + una fila por nivel de LevelStats.aggregate.
static func levels_table(rows: Array[Dictionary]) -> Array[PackedStringArray]:
	var sources := LevelStats.all_sources(rows)
	var header := PackedStringArray(LEVELS_HEADER)
	for source in sources:
		header.append(DAMAGE_COLUMN_PREFIX + source)
	var table: Array[PackedStringArray] = [header]
	for row in rows:
		var line := PackedStringArray([
			str(row["level"]), str(row["attempts"]), str(row["completed"]),
			str(row["died"]), str(row["abandoned"]),
			number(row["completion_rate"] * 100.0, 1),
			str(row["deaths"]), number(row["deaths_per_attempt"], 3),
			number(row["mean_time_s"], 2), number(row["total_time_s"], 2),
			str(row["damage_total"]), number(row["damage_per_min"], 3),
			number(row["measured_difficulty"], 3),
			number(LevelStats.planned_index(row["level"]), 3),
			LIST_SEPARATOR.join(PackedStringArray(row["weapons_used"])),
		])
		var by_source: Dictionary = row["damage_by_source"]
		for source in sources:
			line.append(str(by_source.get(source, 0)))
		table.append(line)
	return table


## Encabezado + una fila por evento "death" de todos los archivos (todos los
## modos; la columna mode los distingue y final = false marca los knock-out
## de la demo).
static func deaths_table(levels: Array) -> Array[PackedStringArray]:
	var table: Array[PackedStringArray] = [PackedStringArray(DEATHS_HEADER)]
	for data: Variant in levels:
		if not data is Dictionary:
			continue
		var map: Dictionary = data.get("map", {})
		for event: Variant in data.get("events", []):
			if not event is Dictionary or event.get("type") != TelemetryStore.EVENT_DEATH:
				continue
			var pos := Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
			var cell := TelemetryStore.world_to_cell(map, pos)
			table.append(PackedStringArray([
				str(data.get("profile", "")), str(data.get("run_id", "")),
				str(data.get("mode", "")), str(data.get("game_version", "")),
				str(data.get("level", 0)), str(data.get("attempt", 1)),
				number(float(event.get("t", 0.0)), 2), number(pos.x, 1), number(pos.y, 1),
				str(cell.x), str(cell.y),
				LevelStats.source_name(event.get("cause", "")),
				"true" if bool(event.get("final", true)) else "false",
			]))
	return table


## Encabezado + una fila por partida (perfil + run_id), ordenadas por fecha de
## inicio. last_outcome es el resultado del último nivel jugado.
static func runs_table(levels: Array) -> Array[PackedStringArray]:
	var runs := {}
	var order: Array[String] = []
	for data: Variant in levels:
		if not data is Dictionary:
			continue
		var key := "%s/%s" % [data.get("profile_slug", ""), data.get("run_id", "")]
		if not runs.has(key):
			runs[key] = []
			order.append(key)
		runs[key].append(data)

	var summaries: Array[Dictionary] = []
	for key in order:
		summaries.append(_run_summary(runs[key]))
	summaries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["started_at"] != b["started_at"]:
			return a["started_at"] < b["started_at"]
		return a["run_id"] < b["run_id"])

	var table: Array[PackedStringArray] = [PackedStringArray(RUNS_HEADER)]
	for run in summaries:
		table.append(PackedStringArray([
			run["profile"], run["run_id"], run["mode"], run["game_version"], str(run["seed"]),
			run["started_at"], str(run["levels_played"]), str(run["first_level"]),
			str(run["last_level"]), str(run["levels_completed"]), str(run["deaths"]),
			number(run["total_time_s"], 2), str(run["damage_total"]), run["last_outcome"],
			LIST_SEPARATOR.join(PackedStringArray(run["weapons_used"])),
		]))
	return table


## Texto CSV de una tabla (sin BOM), con "\n" al final de cada fila.
static func to_csv(table: Array[PackedStringArray]) -> String:
	var lines := PackedStringArray()
	for row in table:
		var fields := PackedStringArray()
		for value in row:
			fields.append(escape_field(value))
		lines.append(SEPARATOR.join(fields))
	return "\n".join(lines) + "\n"


## Un campo CSV: entre comillas si tiene separador, comillas, saltos de línea
## o espacios en los bordes; apóstrofo delante si parece una fórmula.
static func escape_field(value: String) -> String:
	var text := value
	if not text.is_empty() and text[0] in ["=", "+", "-", "@", "\t", "\r"] and not text.is_valid_float():
		text = "'" + text
	var needs_quotes := text.contains(SEPARATOR) or text.contains("\"") \
			or text.contains("\n") or text.contains("\r") or text != text.strip_edges()
	if needs_quotes:
		text = "\"" + text.replace("\"", "\"\"") + "\""
	return text


## Escribe la tabla en path como UTF-8 con BOM.
static func write_csv(path: String, table: Array[PackedStringArray]) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(BOM + to_csv(table))
	file.close()
	return OK


## Número con decimals decimales y punto decimal; "" si es NAN o infinito.
static func number(value: float, decimals: int) -> String:
	if is_nan(value) or is_inf(value):
		return ""
	return String.num(value, decimals) if decimals > 0 else str(roundi(value))


static func _run_summary(files: Array) -> Dictionary:
	var first: Dictionary = files[0]
	var summary := {
		"profile": str(first.get("profile", "")),
		"run_id": str(first.get("run_id", "")),
		"mode": str(first.get("mode", "")),
		"game_version": str(first.get("game_version", "")),
		"seed": int(first.get("seed", 0)),
		"started_at": "",
		"levels_played": files.size(),
		"first_level": 0,
		"last_level": 0,
		"levels_completed": 0,
		"deaths": 0,
		"total_time_s": 0.0,
		"damage_total": 0,
		"last_outcome": "",
		"weapons_used": [] as Array[String],
	}
	var last_order := [-1, -1]
	for data: Dictionary in files:
		var level := int(data.get("level", 0))
		var started := str(data.get("started_at", ""))
		if not started.is_empty() and (summary["started_at"] == "" or started < summary["started_at"]):
			summary["started_at"] = started
		summary["first_level"] = level if summary["first_level"] == 0 else mini(summary["first_level"], level)
		summary["last_level"] = maxi(summary["last_level"], level)
		if data.get("outcome") == "completed":
			summary["levels_completed"] += 1
		summary["total_time_s"] += float(data.get("duration_s", 0.0))
		for event: Variant in data.get("events", []):
			if not event is Dictionary:
				continue
			if event.get("type") == TelemetryStore.EVENT_DEATH:
				summary["deaths"] += 1
			elif event.get("type") == TelemetryStore.EVENT_DAMAGE:
				summary["damage_total"] += int(event.get("amount", 0))
		for weapon: Variant in data.get("weapons_used", []):
			var id := str(weapon)
			if not id.is_empty() and id not in summary["weapons_used"]:
				summary["weapons_used"].append(id)
		var order := [level, int(data.get("attempt", 1))]
		if order[0] > last_order[0] or (order[0] == last_order[0] and order[1] > last_order[1]):
			last_order = order
			summary["last_outcome"] = str(data.get("outcome", ""))
	return summary
