extends Control
## Informe de patrones para el equipo (no para quien juega): lee todas las
## partidas guardadas por la telemetría y muestra dónde pasan el tiempo, dónde
## reciben daño, dónde mueren y dónde eliminan enemigos.
##
## Dos vistas, porque los niveles generados cambian con la semilla:
##   Mismo mapa  agrupa las partidas que jugaron el mismo mapa (misma semilla
##               de nivel; el nivel 1 hecho a mano siempre coincide) y dibuja
##               el mapa de calor sobre ese mapa.
##   Sin mapa    junta todas las partidas filtradas, cualquiera sea su mapa,
##               por distancia caminando a la puerta y a la llave y por tipo
##               de sala.
## Filtros: perfil, nivel, versión del juego y modo. El panel "Avisos" muestra
## lo que le pasen a set_insights.

## Se emite después de leer los archivos (reload), con todos los niveles
## leídos, sin filtrar.
signal data_loaded(levels: Array[Dictionary])

const VIEW_MAP := 0
const VIEW_ANY_MAP := 1
const VIEW_NAMES: Array[String] = ["Mismo mapa", "Sin mapa (distancias y salas)"]
const MODE_NAMES := {
	RunRecorder.MODE_NORMAL: "Normal",
	RunRecorder.MODE_TEST: "Prueba",
	RunRecorder.MODE_DEMO: "Demo",
}
const ALL_TEXT := "Todos"
const NO_VERSION_TEXT := "(sin versión)"
const INSIGHT_COLOR := Color(1.0, 0.8, 0.55)

## Carpeta base de los perfiles (la de TelemetryStore). Vacía: la de siempre,
## user://profiles. Cambiarla antes de agregar la escena al árbol, o llamar a
## load_from.
@export var base_dir: String = ""

@onready var summary_label: Label = %SummaryLabel
@onready var profile_filter: OptionButton = %ProfileFilter
@onready var level_filter: OptionButton = %LevelFilter
@onready var version_filter: OptionButton = %VersionFilter
@onready var mode_filter: OptionButton = %ModeFilter
@onready var view_select: OptionButton = %ViewSelect
@onready var layer_select: OptionButton = %LayerSelect
@onready var map_label: Label = %MapLabel
@onready var map_select: OptionButton = %MapSelect
@onready var heatmap: HeatmapView = %Heatmap
@onready var charts: Control = %Charts
@onready var door_chart: BarChartView = %DoorChart
@onready var key_chart: BarChartView = %KeyChart
@onready var room_chart: BarChartView = %RoomChart
@onready var legend_label: Label = %LegendLabel
@onready var stats_label: Label = %StatsLabel
@onready var insights_list: VBoxContainer = %InsightsList
@onready var no_insights_label: Label = %NoInsightsLabel
@onready var reload_button: Button = %ReloadButton
@onready var back_button: Button = %BackButton

var store: TelemetryStore
var _all_levels: Array[Dictionary] = []
var _filtered: Array[Dictionary] = []
var _groups: Array[Dictionary] = []


func _ready() -> void:
	for view_name in VIEW_NAMES:
		view_select.add_item(view_name)
	for layer in PatternAnalysis.LAYERS:
		layer_select.add_item(PatternAnalysis.LAYER_NAMES[layer])
	for filter in [profile_filter, level_filter, version_filter, mode_filter]:
		(filter as OptionButton).item_selected.connect(func(_index: int) -> void: _apply_filters())
	view_select.item_selected.connect(func(_index: int) -> void: _refresh_view())
	layer_select.item_selected.connect(func(_index: int) -> void: _refresh_view())
	map_select.item_selected.connect(func(_index: int) -> void: _refresh_view())
	heatmap.value_formatter = func(value: float) -> String: return PatternAnalysis.format_value(_current_layer(), value)
	reload_button.pressed.connect(reload)
	back_button.pressed.connect(Game.go_to_menu)
	set_insights(PackedStringArray())
	reload()
	view_select.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.go_to_menu()


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

## Lee las partidas de otra carpeta base.
func load_from(dir: String) -> void:
	base_dir = dir
	reload()


## Vuelve a leer todos los archivos de nivel y rehace filtros y vistas.
func reload() -> void:
	store = TelemetryStore.new(base_dir) if not base_dir.is_empty() else TelemetryStore.new()
	_all_levels = store.load_levels()
	_fill_filters()
	_apply_filters()
	data_loaded.emit(_all_levels)


## Todos los niveles leídos, sin filtrar.
func get_all_levels() -> Array[Dictionary]:
	return _all_levels


## Niveles que cumplen los filtros elegidos.
func get_filtered_levels() -> Array[Dictionary]:
	return _filtered


## Filtros elegidos, en el formato de TelemetryStore.matches.
func current_filters() -> Dictionary:
	var filters := {}
	for entry: Array in [[profile_filter, "profile"], [level_filter, "level"],
			[version_filter, "version"], [mode_filter, "mode"]]:
		var option: OptionButton = entry[0]
		if option.selected > 0:
			filters[entry[1]] = option.get_item_metadata(option.selected)
	return filters


## Muestra los avisos automáticos en el panel "Avisos" (uno por línea). Sin
## avisos muestra "Sin avisos".
func set_insights(lines: PackedStringArray) -> void:
	for child in insights_list.get_children():
		insights_list.remove_child(child)
		child.queue_free()
	for line in lines:
		var label := Label.new()
		label.text = "• " + line
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", INSIGHT_COLOR)
		label.add_theme_font_size_override("font_size", 13)
		insights_list.add_child(label)
	no_insights_label.visible = lines.is_empty()


## Elige la vista (VIEW_MAP o VIEW_ANY_MAP) y la capa (una de
## PatternAnalysis.LAYERS). Sirve para revisar el informe sin mouse.
func show_view(view: int, layer: String) -> void:
	view_select.select(clampi(view, 0, VIEW_NAMES.size() - 1))
	layer_select.select(maxi(PatternAnalysis.LAYERS.find(layer), 0))
	_refresh_view()


## Grupos de partidas por mapa con los filtros actuales
## (PatternAnalysis.group_by_map).
func get_map_groups() -> Array[Dictionary]:
	return _groups


# ---------------------------------------------------------------------------
# Filtros
# ---------------------------------------------------------------------------

func _fill_filters() -> void:
	var profiles := {}
	var levels := {}
	var versions := {}
	var modes := {}
	for data in _all_levels:
		var slug: String = data["profile_slug"] if not str(data["profile_slug"]).is_empty() else str(data["profile"])
		profiles[slug] = str(data["profile"]) if not str(data["profile"]).is_empty() else slug
		levels[int(data["level"])] = true
		versions[str(data["game_version"])] = true
		modes[str(data["mode"])] = true

	var profile_items: Array = []
	for slug: String in profiles:
		profile_items.append([profiles[slug], slug])
	profile_items.sort_custom(func(a: Array, b: Array) -> bool: return a[0].naturalnocasecmp_to(b[0]) < 0)
	_fill_option(profile_filter, profile_items)

	var level_numbers := levels.keys()
	level_numbers.sort()
	_fill_option(level_filter, level_numbers.map(func(level: int) -> Array: return ["Nivel %d" % level, level]))

	var version_names := versions.keys()
	version_names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	_fill_option(version_filter, version_names.map(func(version: String) -> Array:
		return [version if not version.is_empty() else NO_VERSION_TEXT, version]))

	var mode_names := modes.keys()
	mode_names.sort()
	_fill_option(mode_filter, mode_names.map(func(mode: String) -> Array:
		return [MODE_NAMES.get(mode, mode), mode]))


## Llena un filtro con "Todos" más items ([texto, valor]) y conserva el valor
## elegido si sigue estando.
func _fill_option(option: OptionButton, items: Array) -> void:
	var previous: Variant = option.get_item_metadata(option.selected) if option.selected > 0 else null
	option.clear()
	option.add_item(ALL_TEXT)
	option.set_item_metadata(0, null)
	var selected := 0
	for item: Array in items:
		option.add_item(str(item[0]))
		var index := option.item_count - 1
		option.set_item_metadata(index, item[1])
		if previous != null and typeof(previous) == typeof(item[1]) and previous == item[1]:
			selected = index
	option.select(selected)


func _apply_filters() -> void:
	var filters := current_filters()
	_filtered.assign(_all_levels.filter(func(data: Dictionary) -> bool:
		return TelemetryStore.matches(data, filters)))
	_groups = PatternAnalysis.group_by_map(_filtered)
	_fill_map_select()
	_show_summary()
	_refresh_view()


func _fill_map_select() -> void:
	var previous: Variant = map_select.get_item_metadata(map_select.selected) if map_select.selected >= 0 else null
	map_select.clear()
	var selected := 0
	for group in _groups:
		var count: int = group["levels"].size()
		map_select.add_item("%s · %d %s" % [group["label"], count, "partida" if count == 1 else "partidas"])
		map_select.set_item_metadata(map_select.item_count - 1, group["key"])
		if previous != null and previous == group["key"]:
			selected = map_select.item_count - 1
	if map_select.item_count > 0:
		map_select.select(selected)
	map_select.disabled = _groups.is_empty()


func _show_summary() -> void:
	var runs := {}
	var profiles := {}
	for data in _all_levels:
		runs[data["run_id"]] = true
		profiles[data["profile_slug"]] = true
	var folder := store.base_dir if store != null else base_dir
	summary_label.text = "%d niveles jugados en %d partidas de %d perfiles (carpeta %s). Con los filtros: %d niveles, %d mapas distintos." % [
		_all_levels.size(), runs.size(), profiles.size(), folder, _filtered.size(), _groups.size()]


# ---------------------------------------------------------------------------
# Vistas
# ---------------------------------------------------------------------------

func _current_layer() -> String:
	return PatternAnalysis.LAYERS[clampi(layer_select.selected, 0, PatternAnalysis.LAYERS.size() - 1)]


func _refresh_view() -> void:
	var layer := _current_layer()
	var map_view := view_select.selected != VIEW_ANY_MAP
	heatmap.visible = map_view
	map_select.visible = map_view
	map_label.visible = map_view
	charts.visible = not map_view
	var scope: Array[Dictionary] = _filtered
	if map_view:
		scope = _show_heatmap(layer)
	else:
		_show_charts(layer)
	_show_stats(scope)


## Dibuja el mapa de calor del grupo elegido. Devuelve sus niveles.
func _show_heatmap(layer: String) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	if _groups.is_empty():
		heatmap.clear(_empty_text())
		_set_legend("")
		return none
	var group: Dictionary = _groups[clampi(map_select.selected, 0, _groups.size() - 1)]
	var group_levels: Array[Dictionary] = group["levels"]
	var values := PatternAnalysis.heat_grid(group["map"], group_levels, layer)
	var max_value := 0.0
	for value in values:
		max_value = maxf(max_value, value)
	heatmap.show_heat(group["map"], values, PatternAnalysis.format_value(layer, max_value))
	_set_legend("%s, suma de %d %s en este mapa. Color: raíz del valor de la celda sobre el máximo. I = inicio, L = llave, P = puerta. Pasa el mouse por una celda para ver su valor." % [
		PatternAnalysis.LAYER_NAMES[layer], group_levels.size(),
		"nivel jugado" if group_levels.size() == 1 else "niveles jugados"])
	return group_levels


func _show_charts(layer: String) -> void:
	var layer_name: String = PatternAnalysis.LAYER_NAMES[layer]
	var bins := PatternAnalysis.distance_bin_labels()
	var door := PatternAnalysis.distance_histogram(_filtered, layer, "door")
	var key := PatternAnalysis.distance_histogram(_filtered, layer, "key")
	var rooms := PatternAnalysis.room_histogram(_filtered, layer)
	door_chart.set_data("%s por distancia a la puerta (celdas)" % layer_name, bins, door["values"],
			_value_texts(layer, door["values"]), _skipped_note(door["skipped"], "puerta"))
	key_chart.set_data("%s por distancia a la llave (celdas)" % layer_name, bins, key["values"],
			_value_texts(layer, key["values"]), _skipped_note(key["skipped"], "llave"))
	room_chart.set_data("%s por tipo de sala" % layer_name, PatternAnalysis.room_role_labels(), rooms,
			_value_texts(layer, rooms))
	_set_legend("%d niveles jugados, de cualquier mapa. Distancia: celdas caminando hasta la puerta o la llave de cada mapa. Salas: la que tiene la puerta, la llave o el inicio (en ese orden), otra sala, pasillo, o \"Sin salas\" en el nivel 1 hecho a mano." % _filtered.size()
			if not _filtered.is_empty() else _empty_text())


func _show_stats(scope: Array[Dictionary]) -> void:
	if scope.is_empty():
		stats_label.text = "Sin partidas."
		return
	var outcomes := {}
	var duration := 0.0
	var runs := {}
	for data in scope:
		outcomes[data["outcome"]] = int(outcomes.get(data["outcome"], 0)) + 1
		duration += float(data["duration_s"])
		runs[data["run_id"]] = true
	var lines := PackedStringArray()
	lines.append("Niveles jugados: %d (%d partidas)" % [scope.size(), runs.size()])
	lines.append("Completados: %d · Muertes: %d · Abandonados: %d" % [
		outcomes.get(TelemetryRecorder.OUTCOME_COMPLETED, 0), outcomes.get(TelemetryRecorder.OUTCOME_DIED, 0),
		outcomes.get(TelemetryRecorder.OUTCOME_ABANDONED, 0)])
	lines.append("Tiempo: %s en total, %s de media" % [ProfileStore.format_duration(duration),
		ProfileStore.format_duration(duration / scope.size())])
	lines.append("Daño recibido: %d · Muertes (eventos): %d · Enemigos eliminados: %d" % [
		roundi(PatternAnalysis.layer_total(scope, PatternAnalysis.LAYER_DAMAGE)),
		roundi(PatternAnalysis.layer_total(scope, PatternAnalysis.LAYER_DEATHS)),
		roundi(PatternAnalysis.layer_total(scope, PatternAnalysis.LAYER_KILLS))])
	stats_label.text = "\n".join(lines)


func _set_legend(text: String) -> void:
	legend_label.text = text


func _empty_text() -> String:
	if _all_levels.is_empty():
		return "No hay partidas guardadas en %s" % (store.base_dir if store != null else base_dir)
	return "Ninguna partida cumple los filtros"


func _value_texts(layer: String, values: PackedFloat32Array) -> PackedStringArray:
	var texts := PackedStringArray()
	for value in values:
		texts.append(PatternAnalysis.format_value(layer, value))
	return texts


func _skipped_note(skipped: int, what: String) -> String:
	if skipped == 0:
		return ""
	return "%d %s sin %s en el mapa" % [skipped, "nivel" if skipped == 1 else "niveles", what]
