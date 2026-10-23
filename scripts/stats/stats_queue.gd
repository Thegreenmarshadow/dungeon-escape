@tool
class_name StatsQueue
extends RefCounted
## Cola de pedidos de estadísticas pendientes de enviar al servidor. Es lógica
## pura (no crea nodos) y recibe la ruta del archivo, así las pruebas usan una
## ruta temporal.
##
## Cada elemento es un Dictionary con:
##   id:     número único y creciente dentro de la cola.
##   kind:   KIND_RUN_STARTED, KIND_EVENT o KIND_RUN_FINISHED.
##   run_id: partida a la que pertenece.
##   data:   cuerpo del pedido (la partida, el evento o el resumen final).
##
## Los elementos se envían en el orden en que llegaron: una partida se crea
## antes de recibir sus eventos y se cierra después de ellos. Los eventos
## seguidos de una misma partida se agrupan en lotes.
##
## Tope: guarda como máximo max_items elementos (MAX_ITEMS por defecto). Si se
## pasa, descarta los más viejos. Con el servidor apagado durante mucho tiempo
## se pierden las partidas más antiguas; si se descarta el inicio de una
## partida, el servidor rechaza sus eventos (404) y la cola también los
## descarta, así nunca queda trabada.
##
## Formato del archivo (versión 1):
##   {"version": 1, "next_id": 8, "items": [{"id": 7, "kind": "event",
##    "run_id": "…", "data": {…}}, ...]}

const DEFAULT_PATH := "user://stats_queue.json"
const VERSION := 1
const MAX_ITEMS := 1000
const KIND_RUN_STARTED := "run_started"
const KIND_EVENT := "event"
const KIND_RUN_FINISHED := "run_finished"
const KINDS := [KIND_RUN_STARTED, KIND_EVENT, KIND_RUN_FINISHED]

var items: Array[Dictionary] = []
var max_items: int
var _next_id := 1


func _init(p_max_items: int = MAX_ITEMS) -> void:
	max_items = maxi(p_max_items, 1)


func size() -> int:
	return items.size()


func is_empty() -> bool:
	return items.is_empty()


## Agrega un pedido al final. Devuelve cuántos de los más viejos se
## descartaron por superar el tope (normalmente 0).
func push(kind: String, run_id: String, data: Dictionary) -> int:
	items.append({"id": _next_id, "kind": kind, "run_id": run_id, "data": data})
	_next_id += 1
	return _trim()


## Próximo lote a enviar, sin quitarlo de la cola: el primer elemento y, si es
## un evento, los eventos que le siguen de la misma partida (hasta max_events).
func next_batch(max_events: int) -> Array[Dictionary]:
	var batch: Array[Dictionary] = []
	if items.is_empty():
		return batch
	var head: Dictionary = items[0]
	if head["kind"] != KIND_EVENT:
		batch.append(head)
		return batch
	for item in items:
		if batch.size() >= max_events or item["kind"] != KIND_EVENT or item["run_id"] != head["run_id"]:
			break
		batch.append(item)
	return batch


## true si el inicio de la partida run_id todavía no llegó al servidor (sigue
## en la cola, también mientras se está enviando). LevelUploader espera a que
## no esté para subir los niveles de esa partida.
func has_run_start(run_id: String) -> bool:
	return items.any(func(item: Dictionary) -> bool:
		return item["kind"] == KIND_RUN_STARTED and item["run_id"] == run_id)


## Quita de la cola los elementos del lote (por id). Los que ya no estén, por
## ejemplo descartados por el tope mientras se enviaban, se ignoran.
func remove(batch: Array[Dictionary]) -> void:
	var ids := {}
	for item in batch:
		ids[item["id"]] = true
	var kept: Array[Dictionary] = []
	for item in items:
		if not ids.has(item["id"]):
			kept.append(item)
	items = kept


## Guarda la cola en path (archivo temporal y luego renombrado). Devuelve false
## con un aviso si algo falla; la cola en memoria sigue intacta.
func save(path: String = DEFAULT_PATH) -> bool:
	var data := {"version": VERSION, "next_id": _next_id, "items": items}
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("StatsQueue: no se pudo escribir %s (%s)" % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_warning("StatsQueue: falló la escritura de %s (%s)" % [temp_path, error_string(write_error)])
		DirAccess.remove_absolute(temp_path)
		return false
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		push_warning("StatsQueue: no se pudo reemplazar %s (%s)" % [path, error_string(rename_error)])
		DirAccess.remove_absolute(temp_path)
		return false
	return true


## Carga la cola guardada en path. Nunca falla: un archivo ausente o dañado da
## una cola vacía (con un aviso) y los elementos inválidos se descartan.
static func load_from(path: String = DEFAULT_PATH, p_max_items: int = MAX_ITEMS) -> StatsQueue:
	var queue := StatsQueue.new(p_max_items)
	if not FileAccess.file_exists(path):
		return queue
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary or not json.data.get("items") is Array:
		push_warning("StatsQueue: %s está dañado; se empieza con una cola vacía" % path)
		return queue
	var max_id := 0
	for raw: Variant in json.data["items"]:
		var item: Variant = _item_from_data(raw)
		if item == null:
			continue
		queue.items.append(item)
		max_id = maxi(max_id, item["id"])
	var saved_next: Variant = json.data.get("next_id", 0)
	queue._next_id = maxi(max_id + 1, int(saved_next) if saved_next is float else 0)
	queue._trim()
	return queue


func _trim() -> int:
	var overflow := items.size() - max_items
	if overflow <= 0:
		return 0
	for i in overflow:
		items.pop_front()
	return overflow


static func _item_from_data(raw: Variant) -> Variant:
	if not raw is Dictionary:
		return null
	var id: Variant = raw.get("id")
	var kind: Variant = raw.get("kind")
	var run_id: Variant = raw.get("run_id")
	var data: Variant = raw.get("data")
	if not id is float or not kind in KINDS or not run_id is String or run_id.is_empty() or not data is Dictionary:
		return null
	return {"id": int(id), "kind": kind, "run_id": run_id, "data": _restore_ints(data)}


## JSON guarda todos los números como float: los enteros vuelven a ser int
## para que el servidor reciba 3 y no 3.0.
static func _restore_ints(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9.0e15:
		return int(value)
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			out[key] = _restore_ints(value[key])
		return out
	if value is Array:
		var list := []
		for element: Variant in value:
			list.append(_restore_ints(element))
		return list
	return value
