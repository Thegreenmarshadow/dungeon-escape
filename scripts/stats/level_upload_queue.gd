@tool
class_name LevelUploadQueue
extends RefCounted
## Lista de archivos de nivel (los de Telemetry) pendientes de subir al
## servidor de estadísticas. Va aparte de StatsQueue: un archivo de nivel pesa
## varios KB y no debe ocupar el lugar de los eventos. Es lógica pura (no crea
## nodos ni hace pedidos) y recibe la ruta del archivo, así las pruebas usan
## una temporal. La usa LevelUploader.
##
## Cada elemento es un Dictionary con:
##   id:      número único y creciente dentro de la lista.
##   file:    ruta del archivo de nivel (se lee recién al subirlo).
##   run_id:  partida del servidor (la de RunTracker, no Game.run_id).
##   level, attempt: para los avisos.
##
## Orden: un nivel solo se sube cuando su partida ya existe en el servidor, es
## decir, cuando StatsQueue ya no tiene pendiente su inicio (next_ready). Los
## niveles de una misma partida salen en el orden en que llegaron.
##
## Tope: max_items elementos (MAX_ITEMS por defecto); si se pasa, descarta los
## más viejos. Así nunca crece sin límite con el servidor apagado.
##
## Formato del archivo (versión 1):
##   {"version": 1, "next_id": 4, "items": [{"id": 3, "file": "user://…",
##    "run_id": "…", "level": 2, "attempt": 1}, ...]}

const DEFAULT_PATH := "user://level_uploads.json"
const VERSION := 1
const MAX_ITEMS := 300

## Qué hacer con un archivo según la respuesta del servidor (decide).
enum Action {
	DONE, ## Lo guardó (o ya lo tenía): sale de la lista.
	DROP, ## No lo acepta y no lo va a aceptar: sale de la lista con un aviso.
	WAIT, ## Su partida todavía no llegó al servidor: queda y se reintenta.
	RETRY, ## Servidor apagado o con problemas: queda y se reintenta más tarde.
}

var items: Array[Dictionary] = []
var max_items: int
var _next_id := 1


func _init(p_max_items: int = MAX_ITEMS) -> void:
	max_items = maxi(p_max_items, 1)


func size() -> int:
	return items.size()


func is_empty() -> bool:
	return items.is_empty()


## Agrega un archivo al final. Un archivo que ya está no se repite. Devuelve
## cuántos de los más viejos se descartaron por superar el tope.
func push(file: String, run_id: String, level: int, attempt: int) -> int:
	if file.is_empty() or run_id.is_empty() or has_file(file):
		return 0
	items.append({"id": _next_id, "file": file, "run_id": run_id, "level": level, "attempt": attempt})
	_next_id += 1
	return _trim()


func has_file(file: String) -> bool:
	return items.any(func(item: Dictionary) -> bool: return item["file"] == file)


## El primer elemento que se puede subir ya: el más viejo cuya partida no está
## bloqueada. is_blocked(run_id) -> bool dice si el inicio de esa partida
## todavía no llegó al servidor. {} si no hay ninguno.
func next_ready(is_blocked: Callable) -> Dictionary:
	var blocked := {}
	for item in items:
		var run_id: String = item["run_id"]
		if not blocked.has(run_id):
			blocked[run_id] = bool(is_blocked.call(run_id))
		if not blocked[run_id]:
			return item
	return {}


## Quita el elemento con ese id (si ya no está, no hace nada).
func remove(id: int) -> void:
	for i in items.size():
		if items[i]["id"] == id:
			items.remove_at(i)
			return


## Qué hacer después de un pedido. result es el de HTTPRequest y
## run_start_pending dice si StatsQueue todavía tiene que crear la partida.
## Un 404 es una partida que el servidor no conoce: si su inicio sigue en la
## cola, espera; si no, ya no va a llegar nunca y el archivo se descarta.
static func decide(result: int, response_code: int, run_start_pending: bool) -> Action:
	if result != HTTPRequest.RESULT_SUCCESS:
		return Action.RETRY
	if response_code >= 200 and response_code < 300:
		return Action.DONE
	if response_code == 404:
		return Action.WAIT if run_start_pending else Action.DROP
	if response_code == 408 or response_code == 429 or response_code >= 500:
		return Action.RETRY
	return Action.DROP


## Guarda la lista en path (de forma atómica, ver JsonFile.write).
func save(path: String = DEFAULT_PATH) -> bool:
	return JsonFile.write(path, {"version": VERSION, "next_id": _next_id, "items": items})


## Carga la lista guardada en path. Nunca falla: un archivo ausente o dañado
## da una lista vacía y los elementos inválidos se descartan.
static func load_from(path: String = DEFAULT_PATH, p_max_items: int = MAX_ITEMS) -> LevelUploadQueue:
	var queue := LevelUploadQueue.new(p_max_items)
	var raw: Variant = JsonFile.read(path)
	if not raw is Dictionary or not raw.get("items") is Array:
		return queue
	var max_id := 0
	for value: Variant in raw["items"]:
		if not value is Dictionary:
			continue
		var id := JsonFile.to_int(value.get("id"), -1)
		var file: Variant = value.get("file")
		var run_id: Variant = value.get("run_id")
		if id < 0 or not file is String or file.is_empty() or not run_id is String or run_id.is_empty():
			continue
		queue.items.append({"id": id, "file": file, "run_id": run_id,
				"level": JsonFile.to_int(value.get("level"), 0),
				"attempt": JsonFile.to_int(value.get("attempt"), 1)})
		max_id = maxi(max_id, id)
	queue._next_id = maxi(max_id + 1, JsonFile.to_int(raw.get("next_id"), 0))
	queue._trim()
	return queue


func _trim() -> int:
	var overflow := items.size() - max_items
	if overflow <= 0:
		return 0
	for i in overflow:
		items.pop_front()
	return overflow
