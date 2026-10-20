@tool
class_name AnalyticsInsights
extends RefCounted
## Avisos automáticos para el equipo, con reglas simples sobre las
## estadísticas por nivel (LevelStats). Ejemplos:
##   "Nivel 7: 45 % muere, el 60 % por picos"
##   "Nivel 3: tiempo medio 3× el del nivel 2"
## Un nivel solo genera avisos cuando tiene al menos MIN_ATTEMPTS intentos; las
## comparaciones con el nivel anterior exigen ese mínimo en los dos.
##
## generate() es pura (no escribe nada); save_markdown() guarda los avisos en
## insights.md dentro de la carpeta que se le pase (por defecto
## user://analytics).
##
## @tool: así las pruebas del editor pueden ejecutarlo.

# ---------------------------------------------------------------------------
# Umbrales. Ajustables: son criterios de alerta, no mediciones.
# ---------------------------------------------------------------------------

## Intentos mínimos de un nivel para avisar sobre él.
const MIN_ATTEMPTS := 5
## Muertes mínimas para nombrar la causa principal.
const MIN_DEATHS_FOR_CAUSE := 3
## Avisa si muere al menos esta proporción de los intentos.
const DEATH_RATE_WARN := 0.40
## Nombra la causa principal si explica al menos esta proporción de las muertes.
const CAUSE_SHARE_WARN := 0.50
## Avisa si se abandona al menos esta proporción de los intentos.
const ABANDON_RATE_WARN := 0.40
## Avisa si el tiempo medio es al menos esta cantidad de veces el del nivel anterior.
const TIME_RATIO_WARN := 2.5
## Avisa si el daño por minuto es al menos esta cantidad de veces el del nivel anterior.
const DAMAGE_RATIO_WARN := 2.0

const DEFAULT_DIR := "user://analytics"
const MARKDOWN_FILE := "insights.md"

## Nombre en español de cada fuente de daño o causa de muerte (ver
## TelemetryStore: escenas de enemigos, "spikes", peligros de jefe en
## minúsculas, "projectile" y "boss_hazard"). Las demás se muestran tal cual.
const SOURCE_NAMES := {
	"spikes": "picos",
	"Skeleton": "esqueletos",
	"Vampire": "vampiros",
	"Skull": "calaveras",
	"Archer": "arqueros",
	"SkullTurret": "torres de calaveras",
	"Mimic": "mímicos",
	"Mage": "magos",
	"Reaper": "la parca",
	"Forge": "el Forjador",
	"forge": "peligros del Forjador",
	"Lich": "el liche",
	"lich": "peligros del liche",
	"Warden": "el Guardián",
	"warden": "peligros del Guardián",
	"projectile": "proyectiles",
	"boss_hazard": "peligros de jefe",
	"unknown": "causa desconocida",
}


## Avisos en español, ordenados por nivel. levels es lo que devuelve
## TelemetryStore.load_levels() (la demo no entra, ver LevelStats). Si ningún
## nivel llega al mínimo de intentos devuelve una sola línea que lo explica;
## si no hay datos, un arreglo vacío.
static func generate(levels: Array) -> PackedStringArray:
	return generate_from_stats(LevelStats.aggregate(levels))


## Igual que generate, pero con las filas de LevelStats.aggregate ya calculadas.
static func generate_from_stats(rows: Array[Dictionary]) -> PackedStringArray:
	var lines := PackedStringArray()
	if rows.is_empty():
		return lines
	var by_level := {}
	for row in rows:
		by_level[row["level"]] = row

	var enough := 0
	for row in rows:
		if row["attempts"] < MIN_ATTEMPTS:
			continue
		enough += 1
		var level: int = row["level"]
		var death_line := _death_warning(row)
		if not death_line.is_empty():
			lines.append(death_line)
		if row["abandon_rate"] >= ABANDON_RATE_WARN:
			lines.append("Nivel %d: %d %% abandona sin terminar" % [level, _pct(row["abandon_rate"])])
		var previous: Dictionary = by_level.get(level - 1, {})
		if previous.is_empty() or previous["attempts"] < MIN_ATTEMPTS:
			continue
		if previous["mean_time_s"] > 0.0:
			var time_ratio: float = row["mean_time_s"] / previous["mean_time_s"]
			if time_ratio >= TIME_RATIO_WARN:
				lines.append("Nivel %d: tiempo medio %s el del nivel %d" % [level, _times(time_ratio), level - 1])
		if previous["damage_per_min"] > 0.0:
			var damage_ratio: float = row["damage_per_min"] / previous["damage_per_min"]
			if damage_ratio >= DAMAGE_RATIO_WARN:
				lines.append("Nivel %d: daño por minuto %s el del nivel %d" % [level, _times(damage_ratio), level - 1])

	if enough == 0:
		lines.append("Sin avisos todavía: ningún nivel llega a %d intentos (hay %d niveles con menos)." % [
			MIN_ATTEMPTS, rows.size()])
	return lines


## Guarda los avisos en dir/insights.md (crea la carpeta si hace falta).
## Devuelve OK o el error de escritura.
static func save_markdown(lines: PackedStringArray, dir: String = DEFAULT_DIR, analyzed_files: int = -1) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(dir)
	if error != OK:
		return error
	var file := FileAccess.open(dir.path_join(MARKDOWN_FILE), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(to_markdown(lines, analyzed_files))
	file.close()
	return OK


## Texto de insights.md.
static func to_markdown(lines: PackedStringArray, analyzed_files: int = -1) -> String:
	var out := PackedStringArray([
		"# Avisos automáticos",
		"",
		"Generado: %s UTC" % Time.get_datetime_string_from_system(true, true),
	])
	if analyzed_files >= 0:
		out.append("Intentos analizados: %d." % analyzed_files)
	out.append("Mínimo de intentos por nivel para avisar: %d." % MIN_ATTEMPTS)
	out.append("")
	if lines.is_empty():
		out.append("No hay avisos.")
	for line in lines:
		out.append("- " + line)
	return "\n".join(out) + "\n"


## Nombre en español de una fuente de daño o causa de muerte.
static func source_label(source: String) -> String:
	return SOURCE_NAMES.get(source, source)


static func _death_warning(row: Dictionary) -> String:
	if row["death_rate"] < DEATH_RATE_WARN:
		return ""
	var text := "Nivel %d: %d %% muere" % [row["level"], _pct(row["death_rate"])]
	var top := LevelStats.top_death_cause(row)
	if row["deaths"] >= MIN_DEATHS_FOR_CAUSE and top["share"] >= CAUSE_SHARE_WARN:
		text += ", el %d %% por %s" % [_pct(top["share"]), source_label(top["cause"])]
	return text


static func _pct(rate: float) -> int:
	return roundi(rate * 100.0)


## "3×" para valores casi enteros, "2.5×" para el resto.
static func _times(ratio: float) -> String:
	var rounded := snappedf(ratio, 0.1)
	if is_equal_approx(rounded, roundf(rounded)):
		return "%d×" % roundi(rounded)
	return "%.1f×" % rounded
