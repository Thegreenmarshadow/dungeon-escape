class_name RouteMapView
extends Control
## Dibuja el mapa de un nivel con el recorrido del jugador coloreado por tiempo
## (de route_gradient: del inicio al final) y los íconos de los eventos, hasta
## replay_time. El recorrido completo se ve tenue debajo, así el deslizador del
## resumen "reproduce" la partida sobre la ruta entera.
##
## Se usa con set_data(datos de un nivel): Telemetry.last_level_data o un
## archivo de TelemetryStore.load_level_file. Todo se dibuja en _draw() y solo
## se vuelve a dibujar al cambiar los datos, el tiempo o el tamaño.
##
## Las funciones estáticas (map_image, draw_event_icon) las comparten el
## minimapa y la leyenda del resumen.

const KEY_TEXTURE := preload("res://assets/dungeon/items_and_traps/keys/keys_1_1.png")

## Eventos que se dibujan, en orden (los últimos quedan encima). Los golpes
## (attack) no se dibujan: son demasiados.
const DRAWN_EVENTS: Array[String] = [
	TelemetryStore.EVENT_WEAPON_CHANGED, TelemetryStore.EVENT_HEART,
	TelemetryStore.EVENT_ENEMY_KILLED, TelemetryStore.EVENT_KEY,
	TelemetryStore.EVENT_DAMAGE, TelemetryStore.EVENT_REVIVE, TelemetryStore.EVENT_DEATH,
]
## Tipo extra (no es un evento) para el marcador de inicio y el de la puerta
## del mapa en draw_event_icon.
const MARKER_START := "start"

const OUTLINE_COLOR := Color(0.04, 0.03, 0.05, 1)
const BONE_COLOR := Color(0.93, 0.9, 0.82)
const DAMAGE_COLOR := Color(0.95, 0.15, 0.15)
const DOOR_COLOR := Color(0.55, 0.33, 0.15)
const KILL_COLOR := Color(1.0, 0.62, 0.15)
const WEAPON_COLOR := Color(0.3, 0.85, 1.0)
const REVIVE_COLOR := Color(0.35, 0.95, 0.45)
const START_COLOR := Color(0.3, 0.9, 0.4)
const ESCAPED_COLOR := Color(0.35, 0.95, 0.45)
const LOCKED_COLOR := Color(1.0, 0.6, 0.15)

@export var background_color := Color(0.05, 0.04, 0.07, 0.95)
@export var floor_color := Color(0.32, 0.29, 0.36)
@export var wall_color := Color(0.14, 0.12, 0.17)
## Recorrido completo, debajo del que avanza con replay_time.
@export var ghost_color := Color(1, 1, 1, 0.16)
@export var route_width := 3.0
## Tamaño de los íconos de eventos en píxeles de pantalla.
@export var icon_size := 16.0
## Espacio libre alrededor del mapa, en píxeles.
@export var margin := 12.0
## Colores del recorrido según el tiempo: al principio, a la mitad y al final.
@export var route_gradient: Gradient = _default_gradient()

## Instante (s desde el inicio del nivel) hasta el que se dibuja.
var replay_time := 0.0:
	set(value):
		replay_time = value
		queue_redraw()

var replay: RouteReplay = RouteReplay.new()
var map: Dictionary = {}
var _map_texture: ImageTexture
var _map_rect := Rect2()


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	resized.connect(queue_redraw)


## Muestra los datos de un nivel (ya normalizados o los de Telemetry). Deja el
## tiempo al final: se ve el recorrido completo.
func set_data(data: Dictionary) -> void:
	map = data.get("map", {}) if data.get("map") is Dictionary else {}
	replay = RouteReplay.from_data(data)
	_map_rect = RouteReplay.map_rect(map)
	var image := map_image(map, floor_color, wall_color)
	_map_texture = ImageTexture.create_from_image(image) if image != null else null
	replay_time = replay.duration


func has_route() -> bool:
	return not replay.is_empty()


## Transformación del mundo a esta vista.
func world_transform() -> Transform2D:
	return RouteReplay.fit(replay.world_rect, size, margin)


## Imagen del mapa con un píxel por celda: suelo, pared (no suelo que toca
## suelo, como LevelGenerator.Layout.is_wall) o transparente. null si el mapa
## no tiene tamaño.
static func map_image(level_map: Dictionary, floor_tint: Color, wall_tint: Color) -> Image:
	var grid := TelemetryStore.map_size(level_map)
	if grid.x <= 0 or grid.y <= 0:
		return null
	var floor_cells := TelemetryStore.decode_floor(level_map)
	var image := Image.create_empty(grid.x, grid.y, false, Image.FORMAT_RGBA8)
	for y in grid.y:
		for x in grid.x:
			if floor_cells[y * grid.x + x] == 1:
				image.set_pixel(x, y, floor_tint)
			elif _touches_floor(floor_cells, grid, x, y):
				image.set_pixel(x, y, wall_tint)
	return image


static func _touches_floor(floor_cells: PackedByteArray, grid: Vector2i, x: int, y: int) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and ny >= 0 and nx < grid.x and ny < grid.y and floor_cells[ny * grid.x + nx] == 1:
				return true
	return false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), background_color)
	if replay.is_empty() and _map_texture == null:
		_draw_centered_text("Sin recorrido registrado")
		return
	var xf := world_transform()
	if _map_texture != null:
		draw_texture_rect(_map_texture, Rect2(xf * _map_rect.position, _map_rect.size * xf.get_scale()), false)
	_draw_map_markers(xf)
	_draw_route(xf)
	for type in DRAWN_EVENTS:
		for event: Dictionary in replay.events:
			if event.get("type") == type and float(event.get("t", 0.0)) <= replay_time:
				var at := xf * Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
				draw_event_icon(self, type, at, icon_size, event)
	if not replay.is_empty():
		var head := xf * replay.position_at(replay_time)
		draw_circle(head, 6.0, OUTLINE_COLOR)
		draw_circle(head, 4.0, Color.WHITE)
	if replay.is_empty():
		_draw_centered_text("Sin recorrido registrado")


## Inicio, puerta (con borde verde si escapó y naranja si la tocó sin llave)
## y la llave del mapa, tenue mientras no la haya tomado.
func _draw_map_markers(xf: Transform2D) -> void:
	var cell_px := float(maxi(JsonFile.to_int(map.get("cell_px"), LevelSnapshot.CELL_PX), 1))
	var start := TelemetryStore.map_cell(map, "start")
	if start.x >= 0:
		draw_event_icon(self, MARKER_START, xf * TelemetryStore.cell_to_world(map, start), icon_size * 0.8)
	var door := TelemetryStore.map_cell(map, "door")
	if door.x >= 0:
		var state := ""
		for event: Dictionary in replay.events_until(replay_time):
			if event.get("type") == TelemetryStore.EVENT_DOOR:
				state = str(event.get("state", ""))
		# La celda es la de abajo de la puerta: el ícono va media celda arriba.
		var at := xf * (TelemetryStore.cell_to_world(map, door) - Vector2(0, cell_px * 0.5))
		draw_event_icon(self, TelemetryStore.EVENT_DOOR, at, icon_size * 1.2, {"state": state})
	var key := TelemetryStore.map_cell(map, "key")
	var has_key := replay.events_until(replay_time).any(func(event: Dictionary) -> bool:
		return event.get("type") == TelemetryStore.EVENT_KEY)
	if key.x >= 0 and not has_key:
		var at := xf * TelemetryStore.cell_to_world(map, key)
		var rect := Rect2(at - Vector2.ONE * icon_size / 2.0, Vector2.ONE * icon_size)
		draw_texture_rect(KEY_TEXTURE, rect, false, Color(1, 1, 1, 0.45))


## Cada tramo: completo y tenue, y encima con colores por tiempo hasta
## replay_time (con la cabeza interpolada entre dos muestras).
func _draw_route(xf: Transform2D) -> void:
	var duration := maxf(replay.duration, 0.001)
	var current := replay.segment_at(replay_time)
	for i in replay.segments.size():
		var points: PackedVector2Array = xf * replay.segments[i]
		if points.size() >= 2:
			draw_polyline(points, ghost_color, route_width, true)
		if i > current:
			continue
		var times := replay.segment_times[i]
		var count := replay.points_until(i, replay_time)
		var shown := points.slice(0, count)
		var colors := PackedColorArray()
		for k in count:
			colors.append(route_gradient.sample(times[k] / duration))
		if i == current and count > 0 and count < points.size():
			shown.append(xf * replay.position_at(replay_time))
			colors.append(route_gradient.sample(replay_time / duration))
		if shown.size() >= 2:
			draw_polyline_colors(shown, colors, route_width, true)


func _draw_centered_text(text: String) -> void:
	var font := get_theme_default_font()
	var font_size := 22
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var at := (size - text_size) / 2.0 + Vector2(0, font.get_ascent(font_size))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.85, 0.85, 0.85))


## Dibuja el ícono de un evento (un TelemetryStore.EVENT_*, o MARKER_START)
## centrado en at, de unos size píxeles, sobre canvas (llamar desde su _draw).
## event da detalles: el estado de la puerta ("escaped", "locked").
static func draw_event_icon(canvas: CanvasItem, type: String, at: Vector2, icon: float, event: Dictionary = {}) -> void:
	var r := icon / 2.0
	match type:
		TelemetryStore.EVENT_DEATH:
			# Calavera: cráneo, mandíbula y ojos.
			var skull := at - Vector2(0, r * 0.15)
			var jaw := Rect2(at.x - r * 0.45, at.y + r * 0.25, r * 0.9, r * 0.55)
			canvas.draw_circle(skull, r * 0.8 + 1.5, OUTLINE_COLOR)
			canvas.draw_rect(jaw.grow(1.5), OUTLINE_COLOR)
			canvas.draw_circle(skull, r * 0.8, BONE_COLOR)
			canvas.draw_rect(jaw, BONE_COLOR)
			canvas.draw_circle(skull + Vector2(-r * 0.32, r * 0.05), r * 0.22, OUTLINE_COLOR)
			canvas.draw_circle(skull + Vector2(r * 0.32, r * 0.05), r * 0.22, OUTLINE_COLOR)
			canvas.draw_line(Vector2(at.x, jaw.position.y), Vector2(at.x, jaw.end.y), OUTLINE_COLOR, 1.0)
		TelemetryStore.EVENT_DAMAGE:
			# X roja con borde oscuro.
			var h := r * 0.7
			for pass_width: float in [4.5, 2.5]:
				var color := OUTLINE_COLOR if pass_width > 3.0 else DAMAGE_COLOR
				canvas.draw_line(at + Vector2(-h, -h), at + Vector2(h, h), color, pass_width, true)
				canvas.draw_line(at + Vector2(-h, h), at + Vector2(h, -h), color, pass_width, true)
		TelemetryStore.EVENT_KEY:
			canvas.draw_texture_rect(KEY_TEXTURE, Rect2(at - Vector2.ONE * r, Vector2.ONE * icon), false)
		TelemetryStore.EVENT_HEART:
			var heart := Heart.get_texture()
			canvas.draw_texture_rect(heart, Rect2(at - Vector2(r, r * 0.9), Vector2(icon, icon * 0.9)), false)
		TelemetryStore.EVENT_DOOR:
			# Puerta: madera con borde según el estado y un picaporte.
			var rect := Rect2(at.x - r * 0.7, at.y - r, r * 1.4, icon)
			var state := str(event.get("state", ""))
			var border := ESCAPED_COLOR if state == "escaped" else LOCKED_COLOR if state == "locked" else OUTLINE_COLOR
			canvas.draw_rect(rect.grow(1.5), border)
			canvas.draw_rect(rect, DOOR_COLOR)
			canvas.draw_rect(rect.grow(-r * 0.25), DOOR_COLOR.darkened(0.3), false, 1.0)
			canvas.draw_circle(Vector2(rect.end.x - r * 0.35, at.y + r * 0.1), maxf(r * 0.12, 1.0), Color(1, 0.85, 0.3))
		TelemetryStore.EVENT_ENEMY_KILLED:
			var d := r * 0.6
			var diamond := PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)])
			canvas.draw_colored_polygon(diamond, KILL_COLOR)
			diamond.append(diamond[0])
			canvas.draw_polyline(diamond, OUTLINE_COLOR, 1.0)
		TelemetryStore.EVENT_WEAPON_CHANGED:
			canvas.draw_circle(at, r * 0.55 + 1.0, OUTLINE_COLOR)
			canvas.draw_circle(at, r * 0.55, WEAPON_COLOR)
			canvas.draw_line(at + Vector2(-r * 0.3, r * 0.3), at + Vector2(r * 0.3, -r * 0.3), OUTLINE_COLOR, 1.5)
		TelemetryStore.EVENT_REVIVE:
			canvas.draw_arc(at, r * 0.7, 0.0, TAU, 20, OUTLINE_COLOR, 4.0)
			canvas.draw_arc(at, r * 0.7, 0.0, TAU, 20, REVIVE_COLOR, 2.0)
			canvas.draw_line(at + Vector2(0, -r * 0.35), at + Vector2(0, r * 0.35), REVIVE_COLOR, 2.0)
			canvas.draw_line(at + Vector2(-r * 0.35, 0), at + Vector2(r * 0.35, 0), REVIVE_COLOR, 2.0)
		MARKER_START:
			canvas.draw_circle(at, r * 0.6 + 1.5, OUTLINE_COLOR)
			canvas.draw_circle(at, r * 0.6, START_COLOR)


static func _default_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(0.25, 0.75, 1.0), Color(1.0, 0.9, 0.3), Color(1.0, 0.3, 0.25)])
	return gradient
