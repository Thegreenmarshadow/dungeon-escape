class_name DifficultyChart
extends Control
## Gráfica de dificultad por nivel: índice planificado (DifficultyCurve) contra
## dificultad medida (LevelStats), dibujada con _draw() sobre un solo eje 0–1.
## El índice planificado se divide por su máximo en el rango mostrado, así las
## dos líneas comparan forma: dónde sube o baja cada una. La medida es
## relativa entre los niveles jugados (ver LevelStats).
##
## Planificada: línea discontinua. Medida: línea continua con un punto por
## nivel jugado; el punto queda hueco si el nivel tiene menos de
## LOW_SAMPLE_ATTEMPTS intentos. Los niveles sin partidas no tienen punto y
## cortan la línea medida.

## Intentos por debajo de los cuales el punto medido se dibuja hueco.
@export var low_sample_attempts := 5
@export var planned_color := Color("#3987e5")
@export var measured_color := Color("#d95926")
@export var axis_color := Color(0.95, 0.88, 0.7, 0.85)
@export var grid_color := Color(0.95, 0.88, 0.7, 0.12)
@export var text_color := Color(0.95, 0.88, 0.7, 1.0)
@export var muted_text_color := Color(0.8, 0.72, 0.85, 0.85)
@export var font_size := 11
@export var line_width := 2.0
@export var point_radius := 4.0

## Margen interno: izquierda (etiquetas del eje Y), arriba (leyenda), derecha y
## abajo (etiquetas del eje X y su título).
const PAD_LEFT := 40.0
const PAD_TOP := 26.0
const PAD_RIGHT := 12.0
const PAD_BOTTOM := 34.0
const Y_TICKS: Array[float] = [0.0, 0.25, 0.5, 0.75, 1.0]
## Separación mínima en px entre etiquetas del eje X.
const MIN_X_LABEL_GAP := 28.0
const DASH := 6.0

var _points: Array[Dictionary] = []


## Puntos de LevelStats.chart_rows. Redibuja.
func set_points(points: Array[Dictionary]) -> void:
	_points = points
	queue_redraw()


func get_points() -> Array[Dictionary]:
	return _points


## true si algún nivel tiene dificultad medida.
func has_measured() -> bool:
	for point in _points:
		if not is_nan(point["measured"]):
			return true
	return false


func _draw() -> void:
	var font := get_theme_default_font()
	var plot := _plot_rect()
	if plot.size.x <= 10.0 or plot.size.y <= 10.0:
		return

	# Grilla y eje Y.
	for tick in Y_TICKS:
		var y := _y_at(plot, tick)
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid_color, 1.0)
		draw_string(font, Vector2(0.0, y + font_size * 0.35), "%.2f" % tick,
				HORIZONTAL_ALIGNMENT_RIGHT, PAD_LEFT - 6.0, font_size, muted_text_color)
	draw_line(plot.position, Vector2(plot.position.x, plot.end.y), axis_color, 1.0)
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, axis_color, 1.0)

	_draw_legend(font, plot)
	draw_string(font, Vector2(plot.position.x, size.y - 2.0), "Nivel",
			HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, font_size, muted_text_color)

	if _points.is_empty():
		return
	_draw_x_labels(font, plot)
	_draw_series(plot, "planned", planned_color, true)
	_draw_series(plot, "measured", measured_color, false)
	if not has_measured():
		draw_string(font, plot.position + Vector2(0.0, plot.size.y * 0.5),
				"Sin partidas registradas: solo se ve la curva planificada.",
				HORIZONTAL_ALIGNMENT_CENTER, plot.size.x, font_size + 1, muted_text_color)


func _draw_legend(font: Font, plot: Rect2) -> void:
	var y := 10.0
	var x := plot.position.x
	x = _legend_item(font, Vector2(x, y), planned_color, true, "Planificada")
	x = _legend_item(font, Vector2(x + 16.0, y), measured_color, false, "Medida")
	draw_string(font, Vector2(x + 16.0, y + font_size * 0.35), "○ menos de %d intentos" % low_sample_attempts,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, muted_text_color)


## Dibuja un elemento de la leyenda y devuelve la x donde termina.
func _legend_item(font: Font, at: Vector2, color: Color, dashed: bool, text: String) -> float:
	var end := at + Vector2(22.0, 0.0)
	if dashed:
		draw_dashed_line(at, end, color, line_width, DASH)
	else:
		draw_line(at, end, color, line_width)
		draw_circle(at.lerp(end, 0.5), point_radius, color)
	var text_x := end.x + 6.0
	draw_string(font, Vector2(text_x, at.y + font_size * 0.35), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	return text_x + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _draw_x_labels(font: Font, plot: Rect2) -> void:
	var step := 1
	var spacing := plot.size.x / maxf(_points.size() - 1, 1)
	while spacing * step < MIN_X_LABEL_GAP:
		step = 5 if step == 1 else step * 2
	for i in _points.size():
		var level: int = _points[i]["level"]
		if level != 1 and level % step != 0 and i != _points.size() - 1:
			continue
		var x := _x_at(plot, i)
		draw_line(Vector2(x, plot.end.y), Vector2(x, plot.end.y + 4.0), axis_color, 1.0)
		draw_string(font, Vector2(x - 20.0, plot.end.y + 6.0 + font_size), str(level),
				HORIZONTAL_ALIGNMENT_CENTER, 40.0, font_size, muted_text_color)


## Una serie: segmentos entre niveles consecutivos con valor (NAN corta la
## línea) y, en la medida, un punto por nivel con su etiqueta en el último.
func _draw_series(plot: Rect2, key: String, color: Color, dashed: bool) -> void:
	var previous := Vector2.INF
	for i in _points.size():
		var value: float = _points[i][key]
		if is_nan(value):
			previous = Vector2.INF
			continue
		var point := Vector2(_x_at(plot, i), _y_at(plot, value))
		if previous != Vector2.INF:
			if dashed:
				draw_dashed_line(previous, point, color, line_width, DASH)
			else:
				draw_line(previous, point, color, line_width, true)
		previous = point
	if dashed:
		return
	for i in _points.size():
		var value: float = _points[i][key]
		if is_nan(value):
			continue
		var point := Vector2(_x_at(plot, i), _y_at(plot, value))
		if int(_points[i]["attempts"]) < low_sample_attempts:
			draw_circle(point, point_radius, Color(0.06, 0.04, 0.09, 1.0))
			draw_arc(point, point_radius, 0.0, TAU, 16, color, 1.5, true)
		else:
			draw_circle(point, point_radius, color)


## Tooltip con los valores del nivel más cercano al puntero.
func _get_tooltip(at_position: Vector2) -> String:
	var plot := _plot_rect()
	if _points.is_empty() or not plot.grow(8.0).has_point(at_position):
		return ""
	var index := 0
	if _points.size() > 1:
		index = clampi(roundi((at_position.x - plot.position.x) / plot.size.x * (_points.size() - 1)),
				0, _points.size() - 1)
	var point := _points[index]
	var lines := PackedStringArray(["Nivel %d" % point["level"]])
	var planned_raw: float = point["planned_raw"]
	lines.append("Planificada: —" if is_nan(planned_raw) else "Planificada: %.2f (índice %.1f)" % [
			point["planned"], planned_raw])
	var measured: float = point["measured"]
	lines.append("Medida: sin partidas" if is_nan(measured) else "Medida: %.2f (%d intentos)" % [
			measured, point["attempts"]])
	return "\n".join(lines)


func _plot_rect() -> Rect2:
	return Rect2(PAD_LEFT, PAD_TOP, size.x - PAD_LEFT - PAD_RIGHT, size.y - PAD_TOP - PAD_BOTTOM)


func _x_at(plot: Rect2, index: int) -> float:
	if _points.size() <= 1:
		return plot.position.x + plot.size.x * 0.5
	return plot.position.x + plot.size.x * index / float(_points.size() - 1)


func _y_at(plot: Rect2, value: float) -> float:
	return plot.end.y - plot.size.y * clampf(value, 0.0, 1.0)
