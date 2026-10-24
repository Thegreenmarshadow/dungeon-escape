class_name Minimap
extends Control
## Minimapa de la HUD: las zonas exploradas del nivel en curso (las celdas
## cerca de por donde pasó el jugador), el camino recorrido y la posición
## actual. Lee la telemetría en vivo (Telemetry.current_map/current_path): con
## la telemetría apagada no hay datos y el minimapa queda oculto.
##
## Barato: el mapa es una textura de un píxel por celda que solo se actualiza
## cuando llegan muestras nuevas del recorrido (cada 0,25 s o 8 px), y recién
## entonces se vuelve a dibujar. Cada frame solo compara el largo del recorrido.
##
## Se dibuja arriba a la derecha del rectángulo del control, sin deformar el
## mapa, así no tapa la barra superior ni la del jefe.

## Celdas que se descubren alrededor de cada muestra del recorrido.
@export var reveal_radius_cells := 5
@export var background_color := Color(0.03, 0.02, 0.05, 0.6)
@export var floor_color := Color(0.42, 0.39, 0.46, 0.9)
@export var wall_color := Color(0.18, 0.16, 0.21, 0.9)
@export var path_color := Color(1.0, 0.85, 0.3, 0.75)
@export var path_width := 1.5
@export var player_color := Color.WHITE
@export var door_color := Color(0.85, 0.55, 0.25)
## Píxeles de fondo alrededor del mapa.
@export var padding := 4.0

## Mapa del nivel en curso ({} sin telemetría).
var map: Dictionary = {}
## Recorrido en tramos (píxeles del mundo), cortado en cada revive.
var segments: Array[PackedVector2Array] = []

var _telemetry: Node
var _full: Image
var _explored: Image
var _texture: ImageTexture
var _grid := Vector2i.ZERO
## Muestras del recorrido ya procesadas.
var _seen := 0
var _breaks: Dictionary[int, bool] = {}
var _last_reveal := Vector2i(-9999, -9999)
var _has_key := false


func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)
	_telemetry = get_node_or_null(^"/root/Telemetry")
	if _telemetry == null:
		return
	_telemetry.level_started.connect(_on_level_started)
	_telemetry.level_finished.connect(_on_level_finished)
	_telemetry.event_recorded.connect(_on_event_recorded)
	if _telemetry.is_recording():
		setup(_telemetry.current_map())
		add_samples(_telemetry.current_path())


## Empieza con un mapa nuevo, todo sin explorar. Devuelve false (y se oculta)
## si el mapa no tiene tamaño.
func setup(level_map: Dictionary) -> bool:
	map = level_map
	segments.clear()
	_breaks.clear()
	_seen = 0
	_has_key = false
	_last_reveal = Vector2i(-9999, -9999)
	_full = RouteMapView.map_image(map, floor_color, wall_color)
	if _full == null:
		_explored = null
		_texture = null
		hide()
		return false
	_grid = Vector2i(_full.get_width(), _full.get_height())
	_explored = Image.create_empty(_grid.x, _grid.y, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_explored)
	show()
	queue_redraw()
	return true


## Procesa las muestras nuevas de path ([[t, x, y], ...], el recorrido
## completo del nivel): las agrega al camino y descubre las celdas cercanas.
func add_samples(path: Array) -> void:
	if _explored == null or path.size() <= _seen:
		return
	var changed := false
	for i in range(_seen, path.size()):
		var point := Vector2(float(path[i][1]), float(path[i][2]))
		if segments.is_empty() or _breaks.has(i):
			segments.append(PackedVector2Array())
		segments[-1].append(point)
		changed = _reveal(TelemetryStore.world_to_cell(map, point)) or changed
	_seen = path.size()
	if changed:
		_texture.update(_explored)
	queue_redraw()


## true si la celda está explorada.
func is_explored(cell: Vector2i) -> bool:
	if _explored == null or cell.x < 0 or cell.y < 0 or cell.x >= _grid.x or cell.y >= _grid.y:
		return false
	return _explored.get_pixel(cell.x, cell.y).a > 0.0


## Rectángulo (en el control) donde se dibuja el mapa: arriba a la derecha,
## con la escala más grande que entra sin deformarlo.
func map_draw_rect() -> Rect2:
	if _grid.x <= 0 or _grid.y <= 0:
		return Rect2()
	var available := (size - Vector2.ONE * padding * 2.0).max(Vector2.ONE)
	var scale := minf(available.x / _grid.x, available.y / _grid.y)
	var drawn := Vector2(_grid) * scale
	return Rect2(Vector2(size.x - padding - drawn.x, padding), drawn)


## Píxeles del mundo -> coordenadas del control.
func world_transform() -> Transform2D:
	var rect := map_draw_rect()
	var world := RouteReplay.map_rect(map)
	if not world.has_area():
		return Transform2D.IDENTITY
	var scale := rect.size.x / world.size.x
	return Transform2D(0.0, Vector2(scale, scale), 0.0, rect.position - world.position * scale)


func _process(_delta: float) -> void:
	if _explored != null and _telemetry != null and _telemetry.is_recording():
		var path: Array = _telemetry.current_path()
		if path.size() > _seen:
			add_samples(path)


func _draw() -> void:
	if _texture == null:
		return
	var rect := map_draw_rect()
	draw_rect(rect.grow(padding), background_color)
	draw_texture_rect(_texture, rect, false)
	var xf := world_transform()
	var cell_px := rect.size.x / _grid.x
	var door := TelemetryStore.map_cell(map, "door")
	if is_explored(door):
		var at := xf * TelemetryStore.cell_to_world(map, door)
		draw_rect(Rect2(at - Vector2(cell_px, cell_px * 1.5), Vector2(cell_px * 2.0, cell_px * 1.5)), door_color)
	var key := TelemetryStore.map_cell(map, "key")
	if not _has_key and is_explored(key):
		var at := xf * TelemetryStore.cell_to_world(map, key)
		draw_circle(at, maxf(cell_px * 0.8, 2.0), Color(1, 0.85, 0.2))
	for segment in segments:
		if segment.size() >= 2:
			draw_polyline(xf * segment, path_color, path_width, true)
	if not segments.is_empty() and not segments[-1].is_empty():
		var head := xf * segments[-1][-1]
		draw_circle(head, 3.5, Color(0, 0, 0, 0.8))
		draw_circle(head, 2.5, player_color)


## Descubre las celdas a reveal_radius_cells de cell. true si cambió alguna.
func _reveal(cell: Vector2i) -> bool:
	if cell == _last_reveal:
		return false
	_last_reveal = cell
	var changed := false
	var radius := reveal_radius_cells
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x := cell.x + dx
			var y := cell.y + dy
			if x < 0 or y < 0 or x >= _grid.x or y >= _grid.y:
				continue
			if _explored.get_pixel(x, y).a > 0.0:
				continue
			var color := _full.get_pixel(x, y)
			if color.a > 0.0:
				_explored.set_pixel(x, y, color)
				changed = true
	return changed


func _on_level_started(data: Dictionary) -> void:
	if setup(data.get("map", {})):
		add_samples(data.get("path", []))


func _on_event_recorded(event: Dictionary) -> void:
	match event.get("type"):
		TelemetryStore.EVENT_REVIVE:
			_breaks[int(event.get("path_index", -1))] = true
		TelemetryStore.EVENT_KEY:
			_has_key = true
			queue_redraw()


## El nivel terminó: las pantallas finales lo tapan, así que se oculta.
func _on_level_finished(_data: Dictionary, _path: String) -> void:
	hide()
