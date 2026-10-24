class_name BarChartView
extends Control
## Gráfica de barras simple dibujada con _draw(): un título, una barra por
## categoría, su nombre abajo y arriba el valor con el porcentaje del total.

const BACKGROUND_COLOR := Color(0.04, 0.03, 0.06, 1.0)
const AXIS_COLOR := Color(0.5, 0.36, 0.18, 1.0)
const TITLE_COLOR := Color(1.0, 0.86, 0.5, 1.0)
const TEXT_COLOR := Color(0.95, 0.88, 0.7, 1.0)
const MUTED_COLOR := Color(0.8, 0.72, 0.85, 0.85)
const FONT_SIZE := 11
const TITLE_FONT_SIZE := 13
const PADDING := 6.0
## Separación entre barras, como fracción del ancho de cada categoría.
const BAR_GAP := 0.25

@export var bar_color := Color(1.0, 0.55, 0.2, 0.9)

var _title := ""
var _labels := PackedStringArray()
var _values := PackedFloat32Array()
var _value_texts := PackedStringArray()
var _note := ""


## Muestra una gráfica. value_texts: el texto de cada valor (si falta, el
## número redondeado). note: texto chico debajo del título (por ejemplo,
## cuántas partidas no entraron).
func set_data(title: String, labels: PackedStringArray, values: PackedFloat32Array,
		value_texts: PackedStringArray = PackedStringArray(), note: String = "") -> void:
	_title = title
	_labels = labels
	_values = values
	_value_texts = value_texts
	_note = note
	queue_redraw()


func total() -> float:
	var sum := 0.0
	for value in _values:
		sum += value
	return sum


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	var font := get_theme_default_font()
	var line := font.get_height(FONT_SIZE)
	var title_line := font.get_height(TITLE_FONT_SIZE)
	draw_string(font, Vector2(PADDING, PADDING + title_line * 0.8), _title, HORIZONTAL_ALIGNMENT_LEFT,
			size.x - PADDING * 2.0, TITLE_FONT_SIZE, TITLE_COLOR)
	var top := PADDING + title_line + 2.0
	if not _note.is_empty():
		draw_string(font, Vector2(PADDING, top + line * 0.8), _note, HORIZONTAL_ALIGNMENT_LEFT,
				size.x - PADDING * 2.0, FONT_SIZE, MUTED_COLOR)
		top += line
	var sum := total()
	if _values.is_empty() or sum <= 0.0:
		draw_string(font, Vector2(PADDING, top + line * 1.5), "Sin datos", HORIZONTAL_ALIGNMENT_LEFT,
				-1, FONT_SIZE, MUTED_COLOR)
		return
	var max_value := 0.0
	for value in _values:
		max_value = maxf(max_value, value)
	# Arriba de cada barra va su valor; abajo, su nombre.
	var plot := Rect2(PADDING, top + line * 2.0 + 2.0, size.x - PADDING * 2.0,
			size.y - top - line * 3.0 - PADDING - 4.0)
	if plot.size.y <= 4.0 or plot.size.x <= 4.0:
		return
	var slot := plot.size.x / _values.size()
	var bar_width := maxf(slot * (1.0 - BAR_GAP), 1.0)
	for i in _values.size():
		var height := plot.size.y * _values[i] / max_value
		var x := plot.position.x + slot * i + (slot - bar_width) / 2.0
		var bar := Rect2(x, plot.end.y - height, bar_width, height)
		draw_rect(bar, bar_color)
		var value_text := _value_texts[i] if i < _value_texts.size() else str(roundi(_values[i]))
		if _values[i] > 0.0:
			_draw_centered(font, value_text, x + bar_width / 2.0, bar.position.y - line * 0.95, TEXT_COLOR, slot)
			_draw_centered(font, "%d %%" % roundi(_values[i] / sum * 100.0), x + bar_width / 2.0,
					bar.position.y - 2.0 - line * 0.05, MUTED_COLOR, slot)
		if i < _labels.size():
			_draw_centered(font, _labels[i], x + bar_width / 2.0, plot.end.y + line * 0.85, TEXT_COLOR, slot)
	draw_line(Vector2(plot.position.x, plot.end.y), Vector2(plot.end.x, plot.end.y), AXIS_COLOR, 1.0)


func _draw_centered(font: Font, text: String, center_x: float, baseline: float, color: Color, width: float) -> void:
	var text_width := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x, width)
	draw_string(font, Vector2(center_x - text_width / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT,
			width, FONT_SIZE, color)
