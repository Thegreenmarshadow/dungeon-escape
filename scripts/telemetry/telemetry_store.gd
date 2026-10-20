@tool
class_name TelemetryStore
extends RefCounted
## Archivos de telemetría: dónde están, cómo se leen y cómo se exportan. Es la
## API de lectura para las pantallas de análisis (resumen de la partida,
## mapas de calor, informes). Es lógica pura y la carpeta base es inyectable,
## así las pruebas usan una temporal.
##
## Un archivo por nivel jugado:
##   <base_dir>/<slug del perfil>/runs/<run_id>/level_<n>.json
## Si el mismo nivel de la misma partida se juega otra vez (por ejemplo, al
## "Continuar" un nivel abandonado) se agrega el intento: level_<n>_2.json...
##
## Formato (schema_version 1; ver default_level para los valores por defecto):
##   schema_version  int
##   game_version    "0.9.0" (application/config/version)
##   profile         nombre del perfil;  profile_slug: su carpeta
##   run_id          id de la partida (Game.run_id)
##   mode            "normal" | "test" | "demo"
##   level           número de nivel (la demo es el nivel 1)
##   attempt         1, 2... (veces que se jugó ese nivel en la partida)
##   seed            semilla de la partida (Game.run_seed)
##   level_seed      semilla del mapa generado (Layout.seed_used) como texto
##                   (un entero de 64 bits no entra en un número de JSON);
##                   null en el nivel 1 hecho a mano y en la demo. El mapa se
##                   reproduce con LevelGenerator.generate(level, seed)
##   outcome         "completed" | "died" | "abandoned"
##   started_at      fecha UTC de inicio;  duration_s: segundos jugados
##   map             ver LevelSnapshot
##   path            [[t, x, y], ...] posiciones del jugador en píxeles
##   events          [{t, type, x, y, ...campos del tipo}, ...] (ver EVENT_*)
##   weapons_used    ids de las armas usadas, en orden
##
## Eventos (x, y: dónde pasó, en píxeles del mundo):
##   damage          {amount, source}  source: tipo de enemigo ("Skeleton"),
##                                     "spikes", id del jefe para sus efectos,
##                                     "projectile"/"boss_hazard" si no se sabe
##   enemy_killed    {enemy}           x, y: dónde murió el enemigo
##   heart           {amount}          vidas recuperadas
##   key             {}
##   door            {state}           "locked" (tocó sin llave) | "escaped"
##   attack          {hit}             un golpe; hit: si tocó algo
##   weapon_changed  {weapon}
##   death           {cause, final}    cause: source del último daño; final
##                                     false si la demo lo revive
##   revive          {lives, path_index}  la demo lo revivió en x, y; el
##                                     recorrido se corta: path_index es la
##                                     primera muestra del tramo nuevo

const SCHEMA_VERSION := 1
const RUNS_DIR := "runs"
const LEVEL_FILE_PREFIX := "level_"
const EXPORT_DIR := "user://analytics"
const EXPORT_FILE := "telemetry_export.json"

const EVENT_DAMAGE := "damage"
const EVENT_ENEMY_KILLED := "enemy_killed"
const EVENT_HEART := "heart"
const EVENT_KEY := "key"
const EVENT_DOOR := "door"
const EVENT_ATTACK := "attack"
const EVENT_WEAPON_CHANGED := "weapon_changed"
const EVENT_DEATH := "death"
const EVENT_REVIVE := "revive"

## Campos numéricos enteros de los eventos (JSON los lee como float).
const _INT_EVENT_FIELDS: Array[String] = ["amount", "lives", "path_index"]

var base_dir: String


func _init(p_base_dir: String = ProfileStore.DEFAULT_BASE_DIR) -> void:
	base_dir = p_base_dir


# ---------------------------------------------------------------------------
# Rutas y listados
# ---------------------------------------------------------------------------

func run_dir(slug: String, run_id: String) -> String:
	return base_dir.path_join(slug).path_join(RUNS_DIR).path_join(run_id)


## Perfiles (carpetas) que tienen partidas con telemetría.
func list_profiles() -> PackedStringArray:
	var slugs := PackedStringArray()
	if not DirAccess.dir_exists_absolute(base_dir):
		return slugs
	for slug in DirAccess.get_directories_at(base_dir):
		if DirAccess.dir_exists_absolute(base_dir.path_join(slug).path_join(RUNS_DIR)):
			slugs.append(slug)
	slugs.sort()
	return slugs


## Partidas (run_id) del perfil slug.
func list_runs(slug: String) -> PackedStringArray:
	var runs_path := base_dir.path_join(slug).path_join(RUNS_DIR)
	var runs := PackedStringArray()
	if DirAccess.dir_exists_absolute(runs_path):
		runs = DirAccess.get_directories_at(runs_path)
	runs.sort()
	return runs


## Archivos de nivel de una partida, por nivel y por intento.
func list_level_files(slug: String, run_id: String) -> PackedStringArray:
	var dir := run_dir(slug, run_id)
	var names: Array[String] = []
	if DirAccess.dir_exists_absolute(dir):
		for file_name in DirAccess.get_files_at(dir):
			if file_name.begins_with(LEVEL_FILE_PREFIX) and file_name.ends_with(".json"):
				names.append(file_name)
	names.sort_custom(func(a: String, b: String) -> bool:
		var ka := _file_order(a)
		var kb := _file_order(b)
		return ka[0] < kb[0] or (ka[0] == kb[0] and ka[1] < kb[1]))
	var paths := PackedStringArray()
	for file_name in names:
		paths.append(dir.path_join(file_name))
	return paths


## Todos los archivos de nivel de todos los perfiles y partidas.
func all_level_files() -> PackedStringArray:
	var paths := PackedStringArray()
	for slug in list_profiles():
		for run_id in list_runs(slug):
			paths.append_array(list_level_files(slug, run_id))
	return paths


# ---------------------------------------------------------------------------
# Lectura
# ---------------------------------------------------------------------------

## Archivo de nivel con todos los campos en su valor por defecto.
static func default_level() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"game_version": "",
		"profile": "",
		"profile_slug": "",
		"run_id": "",
		"mode": RunRecorder.MODE_NORMAL,
		"level": 1,
		"attempt": 1,
		"seed": 0,
		"level_seed": null,
		"outcome": TelemetryRecorder.OUTCOME_ABANDONED,
		"started_at": "",
		"duration_s": 0.0,
		"map": default_map(),
		"path": [],
		"events": [],
		"weapons_used": [],
	}


static func default_map() -> Dictionary:
	return {
		"size": [0, 0],
		"cell_px": LevelSnapshot.CELL_PX,
		"origin": [0, 0],
		"floor_encoding": LevelSnapshot.FLOOR_ENCODING,
		"floor": "",
		"door": null,
		"key": null,
		"start": null,
		"rooms": [],
	}


## Lee un archivo de nivel con valores por defecto para todo lo que falte o
## tenga otro tipo. {} si no existe o no es JSON. Agrega "_file" (la ruta).
static func load_level_file(path: String) -> Dictionary:
	var raw: Variant = JsonFile.read(path)
	if not raw is Dictionary:
		return {}
	var data := normalize_level(raw)
	data["_file"] = path
	return data


## Completa un archivo de nivel: tipos correctos (los enteros vuelven a ser
## int) y valores por defecto. Nunca falla con archivos viejos o parciales;
## lo malformado se descarta.
static func normalize_level(raw: Dictionary) -> Dictionary:
	var data := default_level()
	for key: String in ["game_version", "profile", "profile_slug", "run_id", "mode", "outcome", "started_at"]:
		if raw.get(key) is String:
			data[key] = raw[key]
	for key: String in ["schema_version", "level", "attempt", "seed"]:
		data[key] = JsonFile.to_int(raw.get(key), data[key])
	if raw.get("level_seed") is String:
		data["level_seed"] = raw["level_seed"]
	elif raw.get("level_seed") is float or raw.get("level_seed") is int:
		data["level_seed"] = str(JsonFile.to_int(raw["level_seed"]))
	data["duration_s"] = JsonFile.to_float(raw.get("duration_s"))
	data["map"] = normalize_map(raw.get("map"))
	var path: Array = []
	if raw.get("path") is Array:
		for point: Variant in raw["path"]:
			if point is Array and point.size() >= 3:
				path.append([JsonFile.to_float(point[0]), JsonFile.to_float(point[1]), JsonFile.to_float(point[2])])
	data["path"] = path
	var events: Array = []
	if raw.get("events") is Array:
		for raw_event: Variant in raw["events"]:
			if raw_event is Dictionary and raw_event.get("type") is String:
				events.append(_normalize_event(raw_event))
	data["events"] = events
	var weapons: Array = []
	if raw.get("weapons_used") is Array:
		for weapon: Variant in raw["weapons_used"]:
			weapons.append(str(weapon))
	data["weapons_used"] = weapons
	for key: String in raw:
		if not data.has(key):
			data[key] = raw[key]
	return data


static func normalize_map(raw: Variant) -> Dictionary:
	var map := default_map()
	if not raw is Dictionary:
		return map
	map["size"] = _int_pair(raw.get("size"), [0, 0])
	map["cell_px"] = maxi(JsonFile.to_int(raw.get("cell_px"), LevelSnapshot.CELL_PX), 1)
	if raw.get("origin") is Array and raw["origin"].size() >= 2:
		map["origin"] = [JsonFile.to_float(raw["origin"][0]), JsonFile.to_float(raw["origin"][1])]
	if raw.get("floor_encoding") is String:
		map["floor_encoding"] = raw["floor_encoding"]
	if raw.get("floor") is String:
		map["floor"] = raw["floor"]
	for key: String in ["door", "key", "start"]:
		map[key] = _int_pair(raw.get(key), null)
	var rooms: Array = []
	if raw.get("rooms") is Array:
		for room: Variant in raw["rooms"]:
			if room is Array and room.size() >= 4:
				rooms.append([JsonFile.to_int(room[0]), JsonFile.to_int(room[1]),
						JsonFile.to_int(room[2]), JsonFile.to_int(room[3])])
	map["rooms"] = rooms
	return map


## Archivos de nivel que cumplen filters (ver matches), ya normalizados.
func load_levels(filters: Dictionary = {}) -> Array[Dictionary]:
	var levels: Array[Dictionary] = []
	for path in all_level_files():
		var data := load_level_file(path)
		if not data.is_empty() and matches(data, filters):
			levels.append(data)
	return levels


## true si data cumple todos los filtros dados. Claves (todas opcionales):
##   profile  nombre o carpeta del perfil
##   level    número o lista de números
##   version  game_version exacta
##   mode     "normal" | "test" | "demo" (o una lista)
##   outcome  "completed" | "died" | "abandoned" (o una lista)
##   run_id
static func matches(data: Dictionary, filters: Dictionary) -> bool:
	if filters.has("profile"):
		var wanted := str(filters["profile"])
		if wanted != data.get("profile") and wanted != data.get("profile_slug"):
			return false
	if filters.has("level") and not _matches_value(data.get("level"), filters["level"]):
		return false
	if filters.has("version") and str(filters["version"]) != data.get("game_version"):
		return false
	if filters.has("mode") and not _matches_value(data.get("mode"), filters["mode"]):
		return false
	if filters.has("outcome") and not _matches_value(data.get("outcome"), filters["outcome"]):
		return false
	if filters.has("run_id") and str(filters["run_id"]) != data.get("run_id"):
		return false
	return true


# ---------------------------------------------------------------------------
# Mapa y coordenadas
# ---------------------------------------------------------------------------

## Suelo del mapa: un byte por celda (índice y * ancho + x), 1 = suelo.
static func decode_floor(map: Dictionary) -> PackedByteArray:
	var size := map_size(map)
	return LevelSnapshot.decode_floor(str(map.get("floor", "")), size.x * size.y)


static func map_size(map: Dictionary) -> Vector2i:
	var size: Variant = map.get("size")
	if size is Array and size.size() >= 2:
		return Vector2i(JsonFile.to_int(size[0]), JsonFile.to_int(size[1]))
	return Vector2i.ZERO


## true si cell (de la grilla del mapa) es suelo. floor_cells es el resultado
## de decode_floor (pasarlo evita decodificar cada vez).
static func is_floor(map: Dictionary, cell: Vector2i, floor_cells: PackedByteArray = PackedByteArray()) -> bool:
	var size := map_size(map)
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return false
	if floor_cells.is_empty():
		floor_cells = decode_floor(map)
	return floor_cells[cell.y * size.x + cell.x] == 1


## Píxel del mundo -> celda de la grilla del mapa.
static func world_to_cell(map: Dictionary, px: Vector2) -> Vector2i:
	return LevelSnapshot.world_to_cell(map, px)


## Celda de la grilla del mapa -> píxel del mundo de su centro.
static func cell_to_world(map: Dictionary, cell: Vector2i) -> Vector2:
	return LevelSnapshot.cell_to_world(map, cell)


## Celda guardada en el mapa ("door", "key" o "start"); Vector2i(-1, -1) si
## no hay.
static func map_cell(map: Dictionary, key: String) -> Vector2i:
	var value: Variant = map.get(key)
	if value is Array and value.size() >= 2:
		return Vector2i(JsonFile.to_int(value[0]), JsonFile.to_int(value[1]))
	return Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# Recorrido y eventos
# ---------------------------------------------------------------------------

## Posiciones del recorrido en píxeles del mundo (sin el tiempo).
static func path_points(data: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Array in data.get("path", []):
		points.append(Vector2(point[1], point[2]))
	return points


## Recorrido en tramos continuos: se corta en cada evento revive (el jugador
## aparece en otro lado), así una línea no cruza el mapa.
static func path_segments(data: Dictionary) -> Array[PackedVector2Array]:
	var breaks: Array[int] = []
	for event: Dictionary in events_of_type(data, EVENT_REVIVE):
		if event.has("path_index"):
			breaks.append(int(event["path_index"]))
	breaks.sort()
	var segments: Array[PackedVector2Array] = []
	var current := PackedVector2Array()
	var path: Array = data.get("path", [])
	for i in path.size():
		if i in breaks and not current.is_empty():
			segments.append(current)
			current = PackedVector2Array()
		current.append(Vector2(path[i][1], path[i][2]))
	if not current.is_empty():
		segments.append(current)
	return segments


## Eventos de un tipo (EVENT_*), en orden.
static func events_of_type(data: Dictionary, type: String) -> Array:
	return (data.get("events", []) as Array).filter(func(event: Dictionary) -> bool:
		return event.get("type") == type)


# ---------------------------------------------------------------------------
# Escritura y exportación
# ---------------------------------------------------------------------------

## Guarda el archivo de un nivel terminado en su carpeta (perfil y partida de
## data). Si ya hay uno de ese nivel, usa el intento siguiente y lo anota en
## data["attempt"]. Devuelve la ruta, o "" si no pudo.
func write_level(data: Dictionary) -> String:
	var slug := str(data.get("profile_slug", ""))
	var run_id := str(data.get("run_id", ""))
	if slug.is_empty() or run_id.is_empty():
		push_warning("TelemetryStore: falta el perfil o la partida; no se guarda el nivel")
		return ""
	var dir := run_dir(slug, run_id)
	var level := int(data.get("level", 1))
	var attempt := 1
	var path := dir.path_join("%s%d.json" % [LEVEL_FILE_PREFIX, level])
	while FileAccess.file_exists(path):
		attempt += 1
		path = dir.path_join("%s%d_%d.json" % [LEVEL_FILE_PREFIX, level, attempt])
	data["attempt"] = attempt
	return path if JsonFile.write(path, data) else ""


## Junta todos los niveles que cumplen filters en un solo JSON:
## {schema_version, exported_at, count, levels: [...]}. file_path vacío usa
## EXPORT_DIR/EXPORT_FILE. Devuelve la ruta escrita, o "" si no pudo.
func export_all(file_path: String = "", filters: Dictionary = {}) -> String:
	if file_path.is_empty():
		file_path = EXPORT_DIR.path_join(EXPORT_FILE)
	var levels: Array = []
	for data in load_levels(filters):
		data.erase("_file")
		levels.append(data)
	var bundle := {
		"schema_version": SCHEMA_VERSION,
		"exported_at": Time.get_datetime_string_from_system(true) + "Z",
		"count": levels.size(),
		"levels": levels,
	}
	return file_path if JsonFile.write(file_path, bundle) else ""


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

static func _normalize_event(raw: Dictionary) -> Dictionary:
	var event := {}
	for key: Variant in raw:
		event[str(key)] = raw[key]
	event["t"] = JsonFile.to_float(raw.get("t"))
	event["x"] = JsonFile.to_float(raw.get("x"))
	event["y"] = JsonFile.to_float(raw.get("y"))
	for key in _INT_EVENT_FIELDS:
		if event.has(key):
			event[key] = JsonFile.to_int(event[key])
	return event


static func _int_pair(value: Variant, default: Variant) -> Variant:
	if value is Array and value.size() >= 2:
		return [JsonFile.to_int(value[0]), JsonFile.to_int(value[1])]
	return default


static func _matches_value(value: Variant, wanted: Variant) -> bool:
	if wanted is Array:
		return value in wanted
	return value == wanted


## Nivel e intento de "level_3.json" ([3, 1]) o "level_3_2.json" ([3, 2]).
static func _file_order(file_name: String) -> Array[int]:
	var parts := file_name.trim_prefix(LEVEL_FILE_PREFIX).trim_suffix(".json").split("_")
	var level := parts[0].to_int()
	var attempt := parts[1].to_int() if parts.size() > 1 else 1
	return [level, attempt]
