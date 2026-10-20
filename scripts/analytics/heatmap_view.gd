class_name HeatmapView
extends Control
## Dibuja el mapa de un nivel (suelo y paredes, como en el juego) con un mapa
## de calor encima: un valor por celda (PatternAnalysis.heat_grid). El color
## sigue la raíz cuadrada del valor sobre el máximo, así las celdas con poco
## valor no desaparecen al lado de una muy alta. Marca inicio (I), llave (L) y
## puerta (P) y muestra el valor de la celda bajo el mouse.

## Se emite al pasar el mouse por una celda de la grilla (valor de esa celda),
## o con (-1, -1) y 0 al salir del mapa.
signal cell_hovered(cell: Vector2i, value: float)

const BACKGROUND_COLOR := Color(0.04, 0.03, 0.06, 1.0)
const FLOOR_COLOR := Color(0.2, 0.18, 0.24, 1.0)
const WALL_COLOR := Color(0.42, 0.34, 0.26, 1.0)
const START_COLOR := Color(0.35, 0.9, 0.45, 1.0)
const KEY_COLOR := Color(1.0, 0.85, 0.2, 1.0)
const DOOR_COLOR := Color(0.55, 0.75, 1.0, 1.0)
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const TEXT_COLOR := Color(0.95, 0.88, 0.7, 1.0)
## Alto y ancho de la escala de colores dibujada abajo a la izquierda.
const LEGEND_SIZE := Vector2(120.0, 8.0)
const FONT_SIZE := 12

## Colores del calor, de poco a mucho (con transparencia sobre el suelo).
@export var heat_gradient: Gradient = _default_gradient()
## Texto del valor de una celda para el cartel bajo el mouse (recibe el
## valor, devuelve el texto). Sin asignar: el número con un decimal.
var value_formatter: Callable

var _map: Dictionary = {}
var _grid_size := Vector2i.ZERO
var _floor := PackedByteArray()
var _walls := PackedByteArray()
var _values := PackedFloat32Array()
var _max_value := 0.0
var _max_text := ""
var _empty_text := "Sin datos"
var _hovered := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void: _set_hovered(Vector2i(-1, -1)))


## Muestra map con values (uno por celda). max_text es el texto del máximo en
## la escala (por ejemplo "12.5 s").
func show_heat(map: Dictionary, values: PackedFloat32Array, max_text: String = "") -> void:
	_map = map
	_grid_size = TelemetryStore.map_size(map)
	_floor = TelemetryStore.decode_floor(map)
	_walls = _wall_cells(_floor, _grid_size)
	_values = values
	_max_value = 0.0
	for value in values:
		_max_value = maxf(_max_value, value)
	_max_text = max_text
	_hovered = Vector2i(-1, -1)
	queue_redraw()


## Deja la vista vacía con un mensaje.
func clear(text: String = "Sin datos") -> void:
	_map = {}
	_grid_size = Vector2i.ZERO
	_values = PackedFloat32Array()
	_max_value = 0.0
	_empty_text = text
	_hovered = Vector2i(-1, -1)
	queue_redraw()


func has_map() -> bool:
	return _grid_size.x > 0 and _grid_size.y > 0


## Valor de una celda (0 fuera de la grilla).
func value_at(cell: Vector2i) -> float:
	if not _in_grid(cell) or _values.size() != _grid_size.x * _grid_size.y:
		return 0.0
	return _values[cell.y * _grid_size.x + cell.x]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
	var font := get_theme_default_font()
	if not has_map():
		var text_size := font.get_string_size(_empty_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		draw_string(font, (size - text_size) / 2.0 + Vector2(0, text_size.y * 0.75), _empty_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		return
	var cell_size := _cell_size()
	var offset := _grid_offset(cell_size)
	var has_values := _values.size() == _grid_size.x * _grid_size.y and _max_value > 0.0
	for y in _grid_size.y:
		for x in _grid_size.x:
			var index := y * _grid_size.x + x
			var rect := Rect2(offset + Vector2(x, y) * cell_size, Vector2(cell_size, cell_size))
			if _floor.size() > index and _floor[index] == 1:
				draw_rect(rect, FLOOR_COLOR)
			elif _walls[index] == 1:
				draw_rect(rect, WALL_COLOR)
			if has_values and _values[index] > 0.0:
				draw_rect(rect, heat_gradient.sample(sqrt(_values[index] / _max_value)))
	_draw_marker(TelemetryStore.map_cell(_map, "start"), START_COLOR, cell_size, offset, "I")
	_draw_marker(TelemetryStore.map_cell(_map, "key"), KEY_COLOR, cell_size, offset, "L")
	_draw_marker(TelemetryStore.map_cell(_map, "door"), DOOR_COLOR, cell_size, offset, "P")
	if _in_grid(_hovered):
		draw_rect(Rect2(offset + Vector2(_hovered) * cell_size, Vector2(cell_size, cell_size)),
				HOVER_COLOR, false, 1.0)
		_draw_hover_text(font)
	_draw_legend(font)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and has_map():
		var cell_size := _cell_size()
		var local: Vector2 = (event.position - _grid_offset(cell_size)) / cell_size
		var cell := Vector2i(floori(local.x), floori(local.y))
		_set_hovered(cell if _in_grid(cell) else Vector2i(-1, -1))


func _set_hovered(cell: Vector2i) -> void:
	if cell == _hovered:
		return
	_hovered = cell
	cell_hovered.emit(cell, value_at(cell))
	queue_redraw()


## Lado de una celda en pantalla: el mapa entero entra conservando la forma.
func _cell_size() -> float:
	if not has_map():
		return 1.0
	return maxf(minf(size.x / _grid_size.x, size.y / _grid_size.y), 0.5)


func _grid_offset(cell_size: float) -> Vector2:
	return ((size - Vector2(_grid_size) * cell_size) / 2.0).floor()


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _grid_size.x and cell.y < _grid_size.y


func _draw_marker(cell: Vector2i, color: Color, cell_size: float, offset: Vector2, letter: String) -> void:
	if not _in_grid(cell):
		return
	var center := offset + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size
	var radius := maxf(cell_size * 0.9, 4.0)
	draw_circle(center, radius, Color(0, 0, 0, 0.6))
	draw_arc(center, radius, 0.0, TAU, 24, color, 2.0)
	var font := get_theme_default_font()
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	draw_string(font, center + Vector2(-text_size.x / 2.0, text_size.y * 0.3), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


func _draw_hover_text(font: Font) -> void:
	var value := value_at(_hovered)
	var value_text: String = value_formatter.call(value) if value_formatter.is_valid() else "%.1f" % value
	var text := "Celda (%d, %d): %s" % [_hovered.x, _hovered.y, value_text]
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	draw_rect(Rect2(Vector2(4.0, 4.0), text_size + Vector2(8.0, 4.0)), Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(8.0, 6.0 + text_size.y * 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			FONT_SIZE, TEXT_COLOR)


func _draw_legend(font: Font) -> void:
	var origin := Vector2(8.0, size.y - LEGEND_SIZE.y - 8.0)
	var steps := 24
	for i in steps:
		var rect := Rect2(origin + Vector2(LEGEND_SIZE.x * i / steps, 0.0),
				Vector2(LEGEND_SIZE.x / steps + 0.5, LEGEND_SIZE.y))
		draw_rect(rect, FLOOR_COLOR)
		draw_rect(rect, heat_gradient.sample(float(i) / (steps - 1)))
	draw_string(font, origin + Vector2(0.0, -4.0), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	var top := _max_text if not _max_text.is_empty() else "máx."
	if _max_value <= 0.0:
		top = "sin valores"
	var text_width := font.get_string_size(top, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, origin + Vector2(LEGEND_SIZE.x - text_width, -4.0), top,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)


## Pared = celda sin suelo que toca suelo (8 vecinos), como
## LevelGenerator.Layout.is_wall.
static func _wall_cells(floor_cells: PackedByteArray, grid_size: Vector2i) -> PackedByteArray:
	var walls := PackedByteArray()
	walls.resize(maxi(grid_size.x * grid_size.y, 0))
	if floor_cells.size() != walls.size():
		return walls
	for y in grid_size.y:
		for x in grid_size.x:
			if floor_cells[y * grid_size.x + x] == 1:
				continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < grid_size.x and ny < grid_size.y \
							and floor_cells[ny * grid_size.x + nx] == 1:
						walls[y * grid_size.x + x] = 1
	return walls


static func _default_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.25, 0.45, 1.0, 0.55),
		Color(1.0, 0.85, 0.2, 0.8),
		Color(1.0, 0.15, 0.1, 0.95),
	])
	return gradient
