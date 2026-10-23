@tool
class_name PatternAnalysis
extends RefCounted
## Cálculos del informe de patrones (AnalyticsReport) sobre archivos de nivel
## ya normalizados (TelemetryStore.load_levels): agrupar partidas por mapa,
## acumular mapas de calor por celda y repartir eventos por distancia a la
## puerta o a la llave y por tipo de sala. Es lógica pura: no lee disco ni
## dibuja.
##
## Capas (LAYER_*), qué suma cada una y dónde:
##   time    segundos: cada muestra del recorrido pesa el tiempo hasta la
##           siguiente (el muestreo no es uniforme en el tiempo)
##   damage  daño recibido (amount de cada evento damage), donde estaba el
##           jugador
##   deaths  muertes (eventos death, también los knock-outs de la demo)
##   kills   enemigos eliminados, donde murió el enemigo

const LAYER_TIME := "time"
const LAYER_DAMAGE := "damage"
const LAYER_DEATHS := "deaths"
const LAYER_KILLS := "kills"
const LAYERS: Array[String] = [LAYER_TIME, LAYER_DAMAGE, LAYER_DEATHS, LAYER_KILLS]
const LAYER_NAMES := {
	LAYER_TIME: "Tiempo",
	LAYER_DAMAGE: "Daño recibido",
	LAYER_DEATHS: "Muertes",
	LAYER_KILLS: "Enemigos eliminados",
}

## Ancho de cada barra de distancia, en celdas, y cantidad de barras (la
## última junta todo lo que queda más lejos).
const DISTANCE_BIN_CELLS := 10
const DISTANCE_BIN_COUNT := 8

## Tipos de sala. Si una sala cumple varios, gana el primero de ROOM_ROLES
## (la puerta antes que la llave y la llave antes que el inicio).
const ROLE_DOOR := "door"
const ROLE_KEY := "key"
const ROLE_START := "start"
const ROLE_OTHER := "other"
const ROLE_CORRIDOR := "corridor"
const ROLE_NO_ROOMS := "no_rooms"
const ROOM_ROLES: Array[String] = [ROLE_DOOR, ROLE_KEY, ROLE_START, ROLE_OTHER, ROLE_CORRIDOR, ROLE_NO_ROOMS]
const ROLE_NAMES := {
	ROLE_DOOR: "Puerta",
	ROLE_KEY: "Llave",
	ROLE_START: "Inicio",
	ROLE_OTHER: "Otra sala",
	ROLE_CORRIDOR: "Pasillo",
	ROLE_NO_ROOMS: "Sin salas",
}

const _NEIGHBOURS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


# ---------------------------------------------------------------------------
# Agrupar por mapa
# ---------------------------------------------------------------------------

## Identidad del mapa de un nivel: número de nivel más una huella del mapa
## guardado (tamaño, suelo, puerta y llave). Dos partidas con la misma semilla
## de nivel dan el mismo mapa; el nivel 1 hecho a mano siempre coincide (y si
## se rediseña entre versiones, queda en otro grupo).
static func map_key(data: Dictionary) -> String:
	var map: Dictionary = data.get("map", {})
	var fingerprint := "%s|%s|%s|%s" % [str(map.get("size")), str(map.get("floor")),
			str(map.get("door")), str(map.get("key"))]
	return "%d|%x" % [int(data.get("level", 0)), fingerprint.hash()]


## Nombre legible del mapa de un nivel.
static func map_label(data: Dictionary) -> String:
	var level := int(data.get("level", 0))
	if data.get("mode") == RunRecorder.MODE_DEMO:
		return "Demo"
	var level_seed: Variant = data.get("level_seed")
	if level_seed is String and not level_seed.is_empty():
		return "Nivel %d · semilla %s" % [level, level_seed]
	if level == 1:
		return "Nivel 1 (hecho a mano)"
	return "Nivel %d" % level


## Partidas agrupadas por mapa (map_key), de la que más tiene a la que menos
## (a igual cantidad, por nivel). Cada grupo: {key, label, level, map,
## levels: Array[Dictionary]}. Si dos grupos tienen el mismo nombre (el mismo
## nivel cambió entre versiones) se numeran.
static func group_by_map(levels: Array[Dictionary]) -> Array[Dictionary]:
	var by_key := {}
	var groups: Array[Dictionary] = []
	for data in levels:
		var key := map_key(data)
		if not by_key.has(key):
			var group_levels: Array[Dictionary] = []
			var group := {"key": key, "label": map_label(data), "level": int(data.get("level", 0)),
					"map": data.get("map", {}), "levels": group_levels}
			by_key[key] = group
			groups.append(group)
		(by_key[key]["levels"] as Array[Dictionary]).append(data)
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var count_a: int = a["levels"].size()
		var count_b: int = b["levels"].size()
		if count_a != count_b:
			return count_a > count_b
		if a["level"] != b["level"]:
			return a["level"] < b["level"]
		return a["label"] < b["label"])
	var seen := {}
	for group in groups:
		var label: String = group["label"]
		seen[label] = int(seen.get(label, 0)) + 1
		if seen[label] > 1:
			group["label"] = "%s (mapa %d)" % [label, seen[label]]
	return groups


# ---------------------------------------------------------------------------
# Puntos con peso
# ---------------------------------------------------------------------------

## Puntos de una capa en un nivel: [[Vector2 en píxeles del mundo, peso], ...].
static func weighted_points(data: Dictionary, layer: String) -> Array:
	var points: Array = []
	match layer:
		LAYER_TIME:
			var path: Array = data.get("path", [])
			var duration := float(data.get("duration_s", 0.0))
			for i in path.size():
				var t := float(path[i][0])
				var next_t := float(path[i + 1][0]) if i + 1 < path.size() else maxf(duration, t)
				var weight := maxf(next_t - t, 0.0)
				if weight > 0.0:
					points.append([Vector2(path[i][1], path[i][2]), weight])
		LAYER_DAMAGE:
			for event: Dictionary in TelemetryStore.events_of_type(data, TelemetryStore.EVENT_DAMAGE):
				# Corazones perdidos; al menos medio corazón por golpe.
				points.append([_event_position(event), maxf(JsonFile.to_float(event.get("amount", 1.0)), 0.5)])
		LAYER_DEATHS:
			for event: Dictionary in TelemetryStore.events_of_type(data, TelemetryStore.EVENT_DEATH):
				points.append([_event_position(event), 1.0])
		LAYER_KILLS:
			for event: Dictionary in TelemetryStore.events_of_type(data, TelemetryStore.EVENT_ENEMY_KILLED):
				points.append([_event_position(event), 1.0])
	return points


## Suma de la capa en los niveles dados (segundos o cantidad de eventos).
static func layer_total(levels: Array[Dictionary], layer: String) -> float:
	var total := 0.0
	for data in levels:
		for point: Array in weighted_points(data, layer):
			total += point[1]
	return total


# ---------------------------------------------------------------------------
# Mapa de calor
# ---------------------------------------------------------------------------

## Mapa de calor de una capa sobre map: un valor por celda (índice
## y * ancho + x). Lo que cae fuera de la grilla se descarta.
static func heat_grid(map: Dictionary, levels: Array[Dictionary], layer: String) -> PackedFloat32Array:
	var size := TelemetryStore.map_size(map)
	var grid := PackedFloat32Array()
	grid.resize(maxi(size.x * size.y, 0))
	for data in levels:
		for point: Array in weighted_points(data, layer):
			var cell := TelemetryStore.world_to_cell(map, point[0])
			if cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y:
				grid[cell.y * size.x + cell.x] += point[1]
	return grid


# ---------------------------------------------------------------------------
# Vistas que no dependen del mapa
# ---------------------------------------------------------------------------

## Distancia caminando (celdas, 4 vecinos, solo por suelo) de cada celda a
## target. -1 en las celdas a las que no se llega o si target no es suelo.
static func distance_field(map: Dictionary, target: Vector2i,
		floor_cells: PackedByteArray = PackedByteArray()) -> PackedInt32Array:
	var size := TelemetryStore.map_size(map)
	var field := PackedInt32Array()
	field.resize(maxi(size.x * size.y, 0))
	field.fill(-1)
	if floor_cells.is_empty():
		floor_cells = TelemetryStore.decode_floor(map)
	if not TelemetryStore.is_floor(map, target, floor_cells):
		return field
	field[target.y * size.x + target.x] = 0
	var queue: Array[Vector2i] = [target]
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var next_distance := field[cell.y * size.x + cell.x] + 1
		for offset in _NEIGHBOURS:
			var next := cell + offset
			if not TelemetryStore.is_floor(map, next, floor_cells):
				continue
			var index := next.y * size.x + next.x
			if field[index] == -1:
				field[index] = next_distance
				queue.append(next)
	return field


## Distancia en celdas de la celda cell a target usando field (de
## distance_field). Si no se llega caminando (por ejemplo, un punto pegado a
## la pared), usa la distancia en línea recta, redondeada.
static func cell_distance(map: Dictionary, field: PackedInt32Array, cell: Vector2i, target: Vector2i) -> int:
	var size := TelemetryStore.map_size(map)
	if cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y:
		var walked := field[cell.y * size.x + cell.x]
		if walked >= 0:
			return walked
	return roundi(Vector2(cell).distance_to(Vector2(target)))


## Barra en la que cae una distancia (la última junta todo lo más lejano).
static func distance_bin(distance: int, bin_cells: int = DISTANCE_BIN_CELLS,
		bin_count: int = DISTANCE_BIN_COUNT) -> int:
	return clampi(distance / maxi(bin_cells, 1), 0, maxi(bin_count, 1) - 1)


## Nombres de las barras de distancia: "0-9", "10-19"... y "70+".
static func distance_bin_labels(bin_cells: int = DISTANCE_BIN_CELLS,
		bin_count: int = DISTANCE_BIN_COUNT) -> PackedStringArray:
	var labels := PackedStringArray()
	for i in bin_count:
		if i == bin_count - 1:
			labels.append("%d+" % (i * bin_cells))
		else:
			labels.append("%d-%d" % [i * bin_cells, (i + 1) * bin_cells - 1])
	return labels


## Reparto de una capa por distancia caminando a la celda target_key ("door"
## o "key") de cada mapa. Devuelve {values: PackedFloat32Array (una por barra),
## skipped: niveles sin esa celda en el mapa}.
static func distance_histogram(levels: Array[Dictionary], layer: String, target_key: String,
		bin_cells: int = DISTANCE_BIN_CELLS, bin_count: int = DISTANCE_BIN_COUNT) -> Dictionary:
	var values := PackedFloat32Array()
	values.resize(bin_count)
	var skipped := 0
	var fields := {}
	for data in levels:
		var map: Dictionary = data.get("map", {})
		var target := TelemetryStore.map_cell(map, target_key)
		if target.x < 0:
			skipped += 1
			continue
		var cache_key := "%s|%s" % [map_key(data), target_key]
		if not fields.has(cache_key):
			fields[cache_key] = distance_field(map, target)
		var field: PackedInt32Array = fields[cache_key]
		for point: Array in weighted_points(data, layer):
			var cell := TelemetryStore.world_to_cell(map, point[0])
			values[distance_bin(cell_distance(map, field, cell, target), bin_cells, bin_count)] += point[1]
	return {"values": values, "skipped": skipped}


## Tipo de sala de una celda (ROLE_*). Sin salas en el mapa (nivel 1 hecho a
## mano): ROLE_NO_ROOMS. Suelo fuera de toda sala: ROLE_CORRIDOR.
static func room_role(map: Dictionary, cell: Vector2i) -> String:
	var rooms: Array = map.get("rooms", [])
	if rooms.is_empty():
		return ROLE_NO_ROOMS
	var special := {
		ROLE_DOOR: TelemetryStore.map_cell(map, "door"),
		ROLE_KEY: TelemetryStore.map_cell(map, "key"),
		ROLE_START: TelemetryStore.map_cell(map, "start"),
	}
	for room: Array in rooms:
		var rect := Rect2i(int(room[0]), int(room[1]), int(room[2]), int(room[3]))
		if not rect.has_point(cell):
			continue
		for role: String in [ROLE_DOOR, ROLE_KEY, ROLE_START]:
			if rect.has_point(special[role]):
				return role
		return ROLE_OTHER
	return ROLE_CORRIDOR


## Reparto de una capa por tipo de sala: un valor por ROOM_ROLES, en ese orden.
static func room_histogram(levels: Array[Dictionary], layer: String) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(ROOM_ROLES.size())
	for data in levels:
		var map: Dictionary = data.get("map", {})
		for point: Array in weighted_points(data, layer):
			var role := room_role(map, TelemetryStore.world_to_cell(map, point[0]))
			values[ROOM_ROLES.find(role)] += point[1]
	return values


## Nombres de ROOM_ROLES, en orden.
static func room_role_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for role in ROOM_ROLES:
		labels.append(ROLE_NAMES[role])
	return labels


## Valor de una capa como texto ("12.5 s" para el tiempo, "3" para eventos).
static func format_value(layer: String, value: float) -> String:
	if layer == LAYER_TIME:
		return "%.1f s" % value
	return str(roundi(value))


static func _event_position(event: Dictionary) -> Vector2:
	return Vector2(float(event.get("x", 0.0)), float(event.get("y", 0.0)))
