@tool
class_name LevelSnapshot
extends RefCounted
## Foto del mapa de un nivel para la telemetría (el campo "map" de cada
## archivo de nivel). Sale de un LevelGenerator.Layout (niveles generados y la
## demo) o, en el nivel 1 hecho a mano, de la capa Dungeon de Level.tscn.
##
## Formato (todo en celdas salvo origin y cell_px):
##   size            [ancho, alto] de la grilla
##   cell_px         píxeles por celda (16)
##   origin          [x, y] en píxeles del mundo de la esquina superior
##                   izquierda de la celda [0, 0] de la grilla
##   floor_encoding  "rle" (único formato por ahora)
##   floor           suelo de la grilla, fila por fila (índice y * ancho + x),
##                   como largos de tramos separados por comas que alternan
##                   sin suelo / suelo, empezando por sin suelo (el primero
##                   puede ser 0). "3,2,1" = 0 0 0 1 1 0. Ver decode_floor.
##   door            celda de suelo justo debajo de la mitad izquierda de la
##                   puerta de salida (como LevelGenerator.Layout.door_cell)
##   key             celda de la llave (en los niveles de jefe, donde la
##                   suelta el jefe: la del Layout); null si no se sabe
##   start           celda donde empieza el jugador
##   rooms           [[x, y, ancho, alto], ...] salas del Layout; [] en el
##                   nivel 1 hecho a mano
##
## Píxel del mundo -> celda: floor((p - origin) / cell_px). Celda -> centro en
## píxeles: origin + (celda + 0.5) * cell_px. Ver world_to_cell y
## cell_to_world.
##
## @tool: es lógica pura, así las pruebas del editor pueden ejecutarlo.

const CELL_PX := 16
const FLOOR_ENCODING := "rle"
## Tile de suelo del atlas (el mismo que pinta LevelBuilder).
const FLOOR_ATLAS := Vector2i(1, 1)


## Mapa desde un Layout. origin es la posición global de la capa Dungeon.
static func from_layout(layout: LevelGenerator.Layout, cell_px: int = CELL_PX,
		origin: Vector2 = Vector2.ZERO) -> Dictionary:
	var rooms: Array = []
	for room in layout.rooms:
		rooms.append([room.position.x, room.position.y, room.size.x, room.size.y])
	return {
		"size": [layout.size.x, layout.size.y],
		"cell_px": cell_px,
		"origin": _vec_to_array(origin),
		"floor_encoding": FLOOR_ENCODING,
		"floor": encode_floor(layout.floor_cells),
		"door": _cell_to_array(layout.door_cell),
		"key": _cell_to_array(layout.key_cell),
		"start": _cell_to_array(layout.player_cell),
		"rooms": rooms,
	}


## Mapa desde una capa de tiles pintada a mano (nivel 1). La grilla es el
## rectángulo de las celdas de suelo (FLOOR_ATLAS) más una celda de pared
## alrededor, no get_used_rect(): el nivel 1 tiene tiles sueltos lejos del
## mapa. start_px, key_px y door_px son posiciones globales del jugador, la
## llave y la puerta (Vector2.INF si no hay). layer_origin es la posición
## global de la capa.
static func from_tile_layer(layer: TileMapLayer, start_px: Vector2, key_px: Vector2,
		door_px: Vector2, layer_origin: Vector2 = Vector2.ZERO) -> Dictionary:
	var cell_px := layer.tile_set.tile_size.x if layer.tile_set != null else CELL_PX
	var floor_list: Array[Vector2i] = []
	for cell in layer.get_used_cells():
		if layer.get_cell_atlas_coords(cell) == FLOOR_ATLAS:
			floor_list.append(cell)
	var bounds := Rect2i()
	if not floor_list.is_empty():
		var low := floor_list[0]
		var high := floor_list[0]
		for cell in floor_list:
			low = low.min(cell)
			high = high.max(cell)
		# Una celda de pared alrededor del suelo.
		bounds = Rect2i(low, high - low + Vector2i.ONE).grow(1)
	var floor_bytes := PackedByteArray()
	floor_bytes.resize(bounds.size.x * bounds.size.y)
	for cell in floor_list:
		var local := cell - bounds.position
		floor_bytes[local.y * bounds.size.x + local.x] = 1
	var origin := layer_origin + Vector2(bounds.position * cell_px)
	var map := {
		"size": [bounds.size.x, bounds.size.y],
		"cell_px": cell_px,
		"origin": _vec_to_array(origin),
		"floor_encoding": FLOOR_ENCODING,
		"floor": encode_floor(floor_bytes),
		"door": null,
		"key": null,
		"start": null,
		"rooms": [],
	}
	if start_px != Vector2.INF:
		map["start"] = _cell_to_array(world_to_cell(map, start_px))
	if key_px != Vector2.INF:
		map["key"] = _cell_to_array(world_to_cell(map, key_px))
	if door_px != Vector2.INF:
		# Inversa de LevelBuilder.door_position: la puerta queda centrada
		# entre sus dos celdas, media celda por encima del suelo.
		var half := cell_px / 2.0
		map["door"] = _cell_to_array(world_to_cell(map, door_px + Vector2(-half, cell_px)))
	return map


## Mapa del nivel en escena (Level o DemoLevel ya listos). Usa el Layout del
## nivel (map_layout) si lo tiene; si no, la capa Dungeon hecha a mano.
static func from_level(level: Node) -> Dictionary:
	var dungeon := level.get_node_or_null("Dungeon") as TileMapLayer
	var cell_px := CELL_PX
	var origin := Vector2.ZERO
	if dungeon != null:
		origin = dungeon.global_position if dungeon.is_inside_tree() else dungeon.position
		if dungeon.tile_set != null:
			cell_px = dungeon.tile_set.tile_size.x
	var layout: Variant = level.get("map_layout")
	if layout is LevelGenerator.Layout:
		return from_layout(layout, cell_px, origin)
	if dungeon == null:
		return {}
	return from_tile_layer(dungeon, _node_position(level, "Player"), _node_position(level, "Key"),
			_node_position(level, "ExitDoor"), origin)


## Suelo de la grilla (un byte por celda, 1 = suelo) como texto RLE.
static func encode_floor(cells: PackedByteArray) -> String:
	var runs := PackedStringArray()
	var current := 0
	var length := 0
	for value in cells:
		var bit := 1 if value != 0 else 0
		if bit == current:
			length += 1
		else:
			runs.append(str(length))
			current = bit
			length = 1
	runs.append(str(length))
	return ",".join(runs)


## Inversa de encode_floor: cell_count bytes (1 = suelo). Un texto dañado o
## corto rellena con 0 en lugar de fallar.
static func decode_floor(text: String, cell_count: int) -> PackedByteArray:
	var cells := PackedByteArray()
	cells.resize(maxi(cell_count, 0))
	var index := 0
	var bit := 0
	for part in text.split(",", false):
		var length := maxi(part.to_int(), 0)
		if bit == 1:
			for i in range(index, mini(index + length, cell_count)):
				cells[i] = 1
		index += length
		bit = 1 - bit
		if index >= cell_count:
			break
	return cells


## Celda de la grilla del mapa que contiene el píxel global px.
static func world_to_cell(map: Dictionary, px: Vector2) -> Vector2i:
	var cell_px := float(map.get("cell_px", CELL_PX))
	var origin := _array_to_vec(map.get("origin"))
	return Vector2i(((px - origin) / cell_px).floor())


## Centro en píxeles globales de la celda cell de la grilla del mapa.
static func cell_to_world(map: Dictionary, cell: Vector2i) -> Vector2:
	var cell_px := float(map.get("cell_px", CELL_PX))
	return _array_to_vec(map.get("origin")) + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_px


static func _node_position(level: Node, path: String) -> Vector2:
	var node := level.get_node_or_null(path) as Node2D
	if node == null:
		return Vector2.INF
	return node.global_position if node.is_inside_tree() else node.position


static func _cell_to_array(cell: Vector2i) -> Array:
	return [cell.x, cell.y]


## Vector como [x, y], con enteros cuando no tiene decimales.
static func _vec_to_array(v: Vector2) -> Array:
	return [_number(v.x), _number(v.y)]


static func _number(value: float) -> Variant:
	return int(value) if value == floorf(value) else value


static func _array_to_vec(value: Variant) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(JsonFile.to_float(value[0]), JsonFile.to_float(value[1]))
	return Vector2.ZERO
