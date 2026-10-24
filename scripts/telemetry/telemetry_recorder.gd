@tool
class_name TelemetryRecorder
extends RefCounted
## Arma en memoria el archivo de telemetría de un nivel (ver TelemetryStore):
## el recorrido del jugador y los eventos con su posición y su tiempo. Es
## lógica pura: no conoce nodos ni señales (Telemetry se las pasa) y no usa el
## generador de números aleatorios global, así no cambia ningún sorteo del
## juego.
##
## Ciclo: start -> (advance | record | add_weapon | break_path)* -> finish.
## Los tiempos (t) son segundos de juego desde que empezó el nivel, sin contar
## las pausas (Telemetry solo llama a advance mientras el árbol no está en
## pausa).

## Muestra la posición del jugador como mínimo cada SAMPLE_INTERVAL segundos...
const SAMPLE_INTERVAL := 0.25
## ...o en cuanto se movió más de SAMPLE_DISTANCE píxeles desde la última.
const SAMPLE_DISTANCE := 8.0

const OUTCOME_IN_PROGRESS := "in_progress"
const OUTCOME_COMPLETED := "completed"
const OUTCOME_DIED := "died"
const OUTCOME_ABANDONED := "abandoned"

var sample_interval: float = SAMPLE_INTERVAL
var sample_distance: float = SAMPLE_DISTANCE
## Archivo del nivel en curso (o del último terminado). Ver TelemetryStore
## para el formato.
var data: Dictionary = {}

var _active := false
var _time := 0.0
var _last_sample_time := 0.0
var _last_sample_position := Vector2.INF


func is_active() -> bool:
	return _active


## Segundos de juego del nivel en curso.
func elapsed() -> float:
	return _time


## Empieza un nivel. meta trae profile, profile_slug, run_id, mode, level,
## seed y level_seed (ver TelemetryStore.default_level); map sale de
## LevelSnapshot. Toma la primera muestra en start_position.
func start(meta: Dictionary, map: Dictionary, start_position: Vector2, weapon_id: String) -> void:
	data = TelemetryStore.default_level()
	for key: String in meta:
		data[key] = meta[key]
	data["game_version"] = str(ProjectSettings.get_setting("application/config/version", ""))
	data["outcome"] = OUTCOME_IN_PROGRESS
	data["started_at"] = Time.get_datetime_string_from_system(true) + "Z"
	data["map"] = map
	data["path"] = []
	data["events"] = []
	data["weapons_used"] = []
	_active = true
	_time = 0.0
	_last_sample_position = Vector2.INF
	add_weapon(weapon_id)
	_sample(start_position)


## Suma delta segundos y muestrea la posición si toca (ver SAMPLE_INTERVAL y
## SAMPLE_DISTANCE).
func advance(delta: float, position: Vector2) -> void:
	if not _active:
		return
	_time += maxf(delta, 0.0)
	if _time - _last_sample_time >= sample_interval \
			or position.distance_to(_last_sample_position) > sample_distance:
		_sample(position)


## Agrega un evento de tipo type en position con los campos extra fields.
## Devuelve el evento ({} si no hay nivel en curso).
func record(type: String, position: Vector2, fields: Dictionary = {}) -> Dictionary:
	if not _active:
		return {}
	var event := {"t": _round(_time, 100.0), "type": type,
			"x": _round(position.x, 10.0), "y": _round(position.y, 10.0)}
	for key: String in fields:
		event[key] = fields[key]
	(data["events"] as Array).append(event)
	return event


## Suma un arma a weapons_used (sin repetir, en el orden en que se usaron).
func add_weapon(weapon_id: String) -> void:
	if weapon_id.is_empty():
		return
	var weapons: Array = data.get("weapons_used", [])
	if not weapon_id in weapons:
		weapons.append(weapon_id)


## El jugador apareció en otro lado (revivir en la demo): muestrea ya la
## posición nueva y devuelve el índice de esa muestra en path, donde empieza
## el tramo nuevo del recorrido.
func break_path(position: Vector2) -> int:
	if not _active:
		return -1
	_sample(position)
	return (data["path"] as Array).size() - 1


## Termina el nivel con outcome (OUTCOME_*), con una última muestra en
## position si se da. Devuelve data; {} si no había nivel en curso.
func finish(outcome: String, position: Vector2 = Vector2.INF) -> Dictionary:
	if not _active:
		return {}
	if position != Vector2.INF:
		_sample(position)
	data["outcome"] = outcome
	data["duration_s"] = _round(_time, 100.0)
	_active = false
	return data


func _sample(position: Vector2) -> void:
	_last_sample_time = _time
	_last_sample_position = position
	var path: Array = data["path"]
	var point := [_round(_time, 100.0), _round(position.x, 10.0), _round(position.y, 10.0)]
	# Sin duplicados exactos (por ejemplo, la muestra final quieta).
	if not path.is_empty() and path[-1] == point:
		return
	path.append(point)


## Redondea a 1/scale sin el error de snappedf.
static func _round(value: float, scale: float) -> float:
	return roundf(value * scale) / scale
