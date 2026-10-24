@tool
class_name RouteReplay
extends RefCounted
## Recorrido de un nivel (un archivo de TelemetryStore o Telemetry.last_level_data)
## listo para dibujar y reproducir: tramos continuos con su tiempo, la posición
## del jugador en cualquier instante y el área del mundo que hay que mostrar.
##
## Los tramos se cortan en cada evento revive (la demo teletransporta al
## jugador al revivir), igual que TelemetryStore.path_segments, así la línea no
## cruza el mapa. Las muestras no son uniformes en el tiempo (0,25 s quieto,
## más seguido al moverse): todo se interpola por t, nunca por índice.
##
## Lógica pura, sin nodos: la usan RouteMapView, el resumen del nivel y las
## pruebas.

## Margen en píxeles del mundo alrededor del recorrido cuando el archivo no
## tiene mapa (archivos viejos o parciales).
const PATH_ONLY_MARGIN := 32.0

## Puntos de cada tramo, en píxeles del mundo.
var segments: Array[PackedVector2Array] = []
## Tiempo (s desde el inicio del nivel) de cada punto de segments.
var segment_times: Array[PackedFloat64Array] = []
## Segundos del nivel: duration_s, o el último t si falta.
var duration := 0.0
## Eventos del nivel ordenados por t (los de TelemetryStore).
var events: Array = []
## Área del mundo a mostrar: el mapa y todo el recorrido.
var world_rect := Rect2()


## Arma el recorrido desde un archivo de nivel ya normalizado (o el de
## Telemetry, que tiene el mismo formato). Nunca falla: sin datos queda vacío.
static func from_data(data: Dictionary) -> RouteReplay:
	var replay := RouteReplay.new()
	var breaks: Array[int] = []
	for event: Variant in data.get("events", []):
		if event is Dictionary:
			replay.events.append(event)
			if event.get("type") == TelemetryStore.EVENT_REVIVE and event.has("path_index"):
				breaks.append(int(event["path_index"]))
	replay.events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))

	var points := PackedVector2Array()
	var times := PackedFloat64Array()
	var path: Variant = data.get("path", [])
	if path is Array:
		for i in path.size():
			var sample: Variant = path[i]
			if not sample is Array or sample.size() < 3:
				continue
			if i in breaks and not points.is_empty():
				replay.segments.append(points)
				replay.segment_times.append(times)
				points = PackedVector2Array()
				times = PackedFloat64Array()
			points.append(Vector2(float(sample[1]), float(sample[2])))
			times.append(float(sample[0]))
	if not points.is_empty():
		replay.segments.append(points)
		replay.segment_times.append(times)

	var last_t := 0.0
	if not replay.segment_times.is_empty():
		last_t = replay.segment_times[-1][-1]
	if not replay.events.is_empty():
		last_t = maxf(last_t, float(replay.events[-1].get("t", 0.0)))
	replay.duration = maxf(float(data.get("duration_s", 0.0)), last_t)
	replay.world_rect = world_rect_for(data.get("map", {}) if data.get("map") is Dictionary else {},
			replay.segments)
	return replay


## Área del mundo del mapa (origin + size * cell_px) unida a la del recorrido.
## Sin mapa, el recorrido con un margen; sin nada, un cuadrado de 1 px.
static func world_rect_for(map: Dictionary, path_segments: Array[PackedVector2Array]) -> Rect2:
	var rect := map_rect(map)
	var has_rect := rect.has_area()
	var path_rect := Rect2()
	var has_path := false
	for segment in path_segments:
		for point in segment:
			if has_path:
				path_rect = path_rect.expand(point)
			else:
				path_rect = Rect2(point, Vector2.ZERO)
				has_path = true
	if has_path and not has_rect:
		return path_rect.grow(PATH_ONLY_MARGIN)
	if has_path:
		return rect.merge(path_rect)
	return rect if has_rect else Rect2(0, 0, 1, 1)


## Área del mundo que cubre la grilla del mapa; vacía si no tiene tamaño.
static func map_rect(map: Dictionary) -> Rect2:
	var size := TelemetryStore.map_size(map)
	if size.x <= 0 or size.y <= 0:
		return Rect2()
	var cell_px := float(maxi(JsonFile.to_int(map.get("cell_px"), LevelSnapshot.CELL_PX), 1))
	var origin := Vector2.ZERO
	var raw_origin: Variant = map.get("origin")
	if raw_origin is Array and raw_origin.size() >= 2:
		origin = Vector2(JsonFile.to_float(raw_origin[0]), JsonFile.to_float(raw_origin[1]))
	return Rect2(origin, Vector2(size) * cell_px)


## Transformación del mundo a una vista de view_size: escala uniforme (el mapa
## no se deforma), centrado y con margin píxeles libres en cada borde.
static func fit(world: Rect2, view_size: Vector2, margin: float = 0.0) -> Transform2D:
	var available := (view_size - Vector2.ONE * margin * 2.0).max(Vector2.ONE)
	var world_size := world.size.max(Vector2.ONE)
	var scale := minf(available.x / world_size.x, available.y / world_size.y)
	var offset := (view_size - world_size * scale) / 2.0 - world.position * scale
	return Transform2D(0.0, Vector2(scale, scale), 0.0, offset)


func is_empty() -> bool:
	return segments.is_empty()


## Tramo en el que está el jugador en el instante t: el último que empezó
## antes o en t (0 si t es anterior a todo). -1 si no hay recorrido.
func segment_at(t: float) -> int:
	if segments.is_empty():
		return -1
	var index := 0
	for i in segment_times.size():
		if segment_times[i][0] <= t:
			index = i
	return index


## Cuántos puntos del tramo segment tienen tiempo <= t.
func points_until(segment: int, t: float) -> int:
	if segment < 0 or segment >= segment_times.size():
		return 0
	return segment_times[segment].bsearch(t, false)


## Posición del jugador en el instante t, interpolada entre las dos muestras
## que lo rodean. Antes del inicio, el primer punto; después del final (o
## entre un tramo y el siguiente, mientras está caído), el último del tramo.
func position_at(t: float) -> Vector2:
	var segment := segment_at(t)
	if segment < 0:
		return Vector2.ZERO
	var points := segments[segment]
	var times := segment_times[segment]
	var count := points_until(segment, t)
	if count <= 0:
		return points[0]
	if count >= points.size():
		return points[-1]
	var t0 := times[count - 1]
	var t1 := times[count]
	var weight := 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
	return points[count - 1].lerp(points[count], weight)


## Eventos con t <= time.
func events_until(time: float) -> Array:
	return events.filter(func(event: Dictionary) -> bool:
		return float(event.get("t", 0.0)) <= time)
