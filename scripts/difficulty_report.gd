extends Control
## Pantalla del modo prueba: tabla de la curva de dificultad de los niveles
## generados, gráfica de dificultad planificada contra medida (con las
## partidas guardadas por la telemetría), análisis de capacidad del mapa,
## exportación a CSV y acceso directo a una partida de prueba en cualquier
## nivel.

## Carpeta de perfiles de donde se leen las partidas (TelemetryStore).
@export var telemetry_dir := ProfileStore.DEFAULT_BASE_DIR
## Carpeta donde "Exportar análisis" escribe los CSV e insights.md.
@export var analytics_dir := CsvExport.DEFAULT_DIR

## Niveles y semillas de muestra para el análisis de capacidad.
const CAPACITY_LEVELS: Array[int] = [2, 5, 10, 20, 30, 50, 100]
const CAPACITY_SEEDS: Array[int] = [1, 2, 3]
## Niveles cuyo índice se resume en la parte superior.
const SUMMARY_LEVELS: Array[int] = [10, 25, 50, 100]
## Color de las filas que no alcanzan el crecimiento objetivo.
const BELOW_TARGET_COLOR := Color(1.0, 0.45, 0.45)
const HEADER_COLOR := Color(1.0, 0.86, 0.5)

## Columnas de la tabla: título y ancho mínimo. La última se estira.
const COLUMNS := [
	["Nivel", 44], ["Comunes", 64], ["Esq/Vamp/Cal", 100], ["Especiales", 84], ["Jefes", 44],
	["Trampas", 64], ["Vida", 52], ["Golpe", 52], ["Índice", 56], ["Δ%", 64], ["Topes", 0],
]
## Nombre abreviado de cada tope de LevelGenerator (la leyenda está en la
## línea de estado).
const CAP_LABELS := {
	DifficultyCurve.CAP_ENEMIES: "E",
	DifficultyCurve.CAP_CHASER_SHARE: "P",
	DifficultyCurve.CAP_HAZARDS: "T",
	DifficultyCurve.CAP_GRID: "G",
	DifficultyCurve.CAP_ROOMS: "S",
	DifficultyCurve.CAP_DAMAGE: "D",
}
const CAPACITY_HEADERS := ["Nivel", "Sem.", "Enem.", "Tramp.", "Libres", "+Enem.", "+Tramp."]
const CAPACITY_FONT_SIZE := 12

@onready var summary_label: Label = %SummaryLabel
@onready var table_header: HBoxContainer = %TableHeader
@onready var rows_box: VBoxContainer = %Rows
@onready var capacity_button: Button = %CapacityButton
@onready var capacity_status: Label = %CapacityStatus
@onready var capacity_grid: GridContainer = %CapacityGrid
@onready var level_spin: SpinBox = %LevelSpin
@onready var play_level_button: Button = %PlayLevelButton
@onready var export_button: Button = %ExportButton
@onready var analytics_export_button: Button = %AnalyticsExportButton
@onready var chart: DifficultyChart = %DifficultyChart
@onready var chart_hint: Label = %ChartHint
@onready var back_button: Button = %BackButton
@onready var status_label: Label = %StatusLabel

var _rows: Array[Dictionary] = []
## Archivos de nivel de la telemetría y sus estadísticas por nivel.
var _levels: Array[Dictionary] = []
var _level_stats: Array[Dictionary] = []


func _ready() -> void:
	_rows = DifficultyCurve.report()
	_show_summary()
	_fill_table()
	load_measured()

	level_spin.min_value = 1
	level_spin.max_value = DifficultyCurve.LAST_LEVEL
	level_spin.value = LevelGenerator.FIRST_GENERATED_LEVEL
	capacity_grid.columns = CAPACITY_HEADERS.size()
	for header: String in CAPACITY_HEADERS:
		var label := _make_label(header, 0, HEADER_COLOR)
		label.add_theme_font_size_override("font_size", CAPACITY_FONT_SIZE)
		capacity_grid.add_child(label)

	capacity_button.pressed.connect(_run_capacity_check)
	play_level_button.pressed.connect(func() -> void: Game.start_test_run(int(level_spin.value)))
	export_button.pressed.connect(_export_csv)
	analytics_export_button.pressed.connect(export_analytics)
	back_button.pressed.connect(Game.go_to_menu)
	status_label.text = ("Las filas en rojo no cumplen el objetivo de su tramo: +%d %% respecto del nivel anterior hasta el nivel %d, crecer algo después. "
			+ "Especiales: total (comunes convertidos). Vida: multiplicador de la vida de los enemigos. "
			+ "Golpe: corazones que quita un golpe común. "
			+ "Topes: E enemigos, P proporción de perseguidores, T trampas, G grilla, S salas, D daño.") % [
			roundi(DifficultyCurve.TARGET_GROWTH * 100.0), DifficultyCurve.TARGET_GROWTH_LAST_LEVEL]
	play_level_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not back_button.disabled:
		get_viewport().set_input_as_handled()
		Game.go_to_menu()


func _show_summary() -> void:
	var failing := DifficultyCurve.failing_levels(_rows)
	var first_below := DifficultyCurve.first_below_target(_rows)
	var plateau := DifficultyCurve.plateau_start(_rows)
	var escalation := DifficultyCurve.escalation()
	var lines := PackedStringArray()
	lines.append("Objetivo: +%d %% por nivel hasta el %d; después crecer en cada nivel y llegar a ×%d del %d al %d (hoy ×%.1f, %s)" % [
		roundi(DifficultyCurve.TARGET_GROWTH * 100.0), DifficultyCurve.TARGET_GROWTH_LAST_LEVEL,
		roundi(DifficultyCurve.ESCALATION_TARGET), DifficultyCurve.TARGET_GROWTH_LAST_LEVEL,
		DifficultyCurve.LAST_LEVEL, escalation,
		"cumple" if escalation >= DifficultyCurve.ESCALATION_TARGET else "no cumple"])
	lines.append("Primer nivel bajo el objetivo: %s · Meseta (crecimiento < %d %%) desde el nivel %s" % [
		str(first_below) if first_below > 0 else "ninguno",
		roundi(DifficultyCurve.PLATEAU_GROWTH * 100.0),
		str(plateau) if plateau > 0 else "ninguno"])
	lines.append("Niveles bajo el objetivo: %d de %d (%s)" % [
		failing.size(), _rows.size() - 1, DifficultyCurve.format_levels(failing) if not failing.is_empty() else "ninguno"])
	var indexes := PackedStringArray()
	for level in SUMMARY_LEVELS:
		indexes.append("nivel %d = %.1f" % [level, DifficultyCurve.index_for_level(level)])
	lines.append("Índice: " + " · ".join(indexes))
	summary_label.text = "\n".join(lines)


func _fill_table() -> void:
	var titles := PackedStringArray()
	for column: Array in COLUMNS:
		titles.append(column[0])
	_add_table_row(table_header, titles, HEADER_COLOR)
	for row in _rows:
		var level_growth: float = row["growth"]
		var caps := PackedStringArray()
		for cap: StringName in row["capped_params"]:
			caps.append(CAP_LABELS.get(cap, String(cap)))
		var line := _add_table_row(rows_box, PackedStringArray([
			str(row["level"]),
			str(row["enemies"]),
			"%d/%d/%d" % [row["skeletons"], row["vampires"], row["skulls"]],
			"%d (%d)" % [row["archers"] + row["skull_turrets"] + row["mimics"] + row["mages"], row["converted"]],
			str(row["bosses"]),
			str(row["hazards"]),
			"×%.1f" % row["health_scale"],
			Heart.format_hearts(row["hit"]),
			"%.1f" % row["index"],
			"—" if is_nan(level_growth) else "%+.1f%%" % (level_growth * 100.0),
			" ".join(caps),
		]))
		if not row["meets_target"]:
			line.modulate = BELOW_TARGET_COLOR


func _add_table_row(parent: Container, cells: PackedStringArray, color: Color = Color.WHITE) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 6)
	for i in cells.size():
		var width: int = COLUMNS[i][1]
		var cell := _make_label(cells[i], width, color)
		if width == 0:
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.clip_text = true
		else:
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(cell)
	parent.add_child(line)
	return line


func _make_label(text: String, min_width: int = 0, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = min_width
	if color != Color.WHITE:
		label.add_theme_color_override("font_color", color)
	return label


## Genera los mapas de muestra y muestra lo pedido frente a lo colocado. Espera
## un cuadro entre mapa y mapa para que la interfaz no se congele. Mientras
## corre se desactivan los botones que cambian de escena.
func _run_capacity_check() -> void:
	_set_buttons_disabled(true)
	while capacity_grid.get_child_count() > CAPACITY_HEADERS.size():
		var old := capacity_grid.get_child(capacity_grid.get_child_count() - 1)
		capacity_grid.remove_child(old)
		old.queue_free()

	var total := CAPACITY_LEVELS.size() * CAPACITY_SEEDS.size()
	var done := 0
	var short_maps := 0
	var min_enemy_slots := -1
	var min_hazard_slots := -1
	for level in CAPACITY_LEVELS:
		for run_seed in CAPACITY_SEEDS:
			capacity_status.text = "Generando nivel %d, semilla %d (%d/%d)…" % [level, run_seed, done + 1, total]
			await get_tree().process_frame
			var report := DifficultyCurve.capacity_report(level, run_seed)
			_add_capacity_row(report)
			done += 1
			if report["placed_enemies"] < report["requested_enemies"] \
					or report["placed_hazards"] < report["requested_hazards"]:
				short_maps += 1
			min_enemy_slots = _min_or_first(min_enemy_slots, report["extra_enemy_slots"])
			min_hazard_slots = _min_or_first(min_hazard_slots, report["extra_hazard_slots"])

	capacity_status.text = "%d mapas: %d con menos entidades de las pedidas. Margen mínimo: +%d enemigos, +%d trampas." % [
		total, short_maps, min_enemy_slots, min_hazard_slots]
	_set_buttons_disabled(false)


func _add_capacity_row(report: Dictionary) -> void:
	var short_enemies: bool = report["placed_enemies"] < report["requested_enemies"]
	var short_hazards: bool = report["placed_hazards"] < report["requested_hazards"]
	var level_text := str(report["level"]) + (" (E)" if report["used_fallback"] else "")
	var cells := [
		[level_text, false],
		[str(report["seed"]), false],
		["%d/%d" % [report["placed_enemies"], report["requested_enemies"]], short_enemies],
		["%d/%d" % [report["placed_hazards"], report["requested_hazards"]], short_hazards],
		[str(report["free_cells"]), false],
		[str(report["extra_enemy_slots"]), false],
		[str(report["extra_hazard_slots"]), false],
	]
	for cell: Array in cells:
		var label := _make_label(cell[0], 0, BELOW_TARGET_COLOR if cell[1] else Color.WHITE)
		label.add_theme_font_size_override("font_size", CAPACITY_FONT_SIZE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		capacity_grid.add_child(label)


func _min_or_first(current: int, value: int) -> int:
	return value if current < 0 else mini(current, value)


func _set_buttons_disabled(disabled: bool) -> void:
	for button: Button in [capacity_button, play_level_button, back_button]:
		button.disabled = disabled


func _export_csv() -> void:
	var error := DifficultyCurve.save_csv(_rows)
	if error == OK:
		status_label.text = "CSV exportado en: " + ProjectSettings.globalize_path(DifficultyCurve.CSV_PATH)
	else:
		status_label.text = "No se pudo exportar el CSV (error %d)." % error


## Lee las partidas guardadas en telemetry_dir y actualiza la gráfica.
func load_measured() -> void:
	_levels = TelemetryStore.new(telemetry_dir).load_levels()
	_level_stats = LevelStats.aggregate(_levels)
	chart.set_points(LevelStats.chart_rows(_level_stats))
	var files := 0
	for row in _level_stats:
		files += row["attempts"]
	chart_hint.text = ("Las dos líneas van de 0 a 1. Planificada: índice de dificultad ÷ su máximo en el rango. "
			+ "Medida: %d %% muertes por intento + %d %% daño por minuto, cada uno ÷ su máximo entre los niveles jugados. "
			+ "Datos: %d intentos en %d niveles (sin la demo). Pasa el puntero sobre la gráfica para ver los valores.") % [
			roundi(LevelStats.WEIGHT_DEATHS * 100.0), roundi(LevelStats.WEIGHT_DAMAGE * 100.0),
			files, _level_stats.size()]


## Escribe levels.csv, deaths.csv, runs.csv e insights.md en analytics_dir.
## Devuelve OK o el primer error.
func export_analytics() -> Error:
	var result := CsvExport.export_all(_levels, analytics_dir)
	var error: Error = result["error"]
	var lines := AnalyticsInsights.generate_from_stats(_level_stats)
	if error == OK:
		var files := 0
		for row in _level_stats:
			files += row["attempts"]
		error = AnalyticsInsights.save_markdown(lines, analytics_dir, files)
	if error == OK:
		status_label.text = "Análisis exportado en %s (levels.csv, deaths.csv, runs.csv, insights.md). Avisos: %d." % [
			ProjectSettings.globalize_path(analytics_dir), lines.size()]
	else:
		status_label.text = "No se pudo exportar el análisis (error %d)." % error
	return error
