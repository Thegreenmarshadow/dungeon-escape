class_name HttpStatsSink
extends StatsSink
## Envía las estadísticas al servidor local (StatsServer.BASE_URL) por HTTP.
##
## Todo pasa primero por una StatsQueue guardada en disco (queue_path), así un
## servidor apagado, un corte o cerrar el juego no pierden datos: lo pendiente
## se reenvía al volver a abrirlo. Los pedidos son asíncronos (un HTTPRequest a
## la vez) y nunca bloquean ni detienen el juego.
##
## Reintentos: si el servidor no responde o responde 408, 429 o 5xx, espera
## MIN_RETRY_DELAY segundos y duplica la espera en cada fallo seguido, hasta
## MAX_RETRY_DELAY. Un 4xx distinto significa que el servidor no acepta ese
## pedido (por ejemplo, eventos de una partida que no conoce): se descarta con
## un aviso en lugar de reintentarlo para siempre. El servidor ignora los
## pedidos repetidos, así reenviar algo que ya había llegado no lo duplica.

## Eventos por pedido como máximo.
const BATCH_SIZE := 50
const MIN_RETRY_DELAY := 2.0
const MAX_RETRY_DELAY := 60.0

## Qué hacer con un lote según la respuesta del servidor.
enum Outcome { SENT, REJECTED, RETRY }

var base_url := StatsServer.BASE_URL
var queue_path := StatsQueue.DEFAULT_PATH
var queue: StatsQueue

var _http: HTTPRequest
var _retry_timer: Timer
var _in_flight: Array[Dictionary] = []
var _retry_delay := 0.0


func _ready() -> void:
	# Sigue enviando con el juego en pausa (pantallas de fin de nivel).
	process_mode = Node.PROCESS_MODE_ALWAYS
	queue = StatsQueue.load_from(queue_path)
	_http = HTTPRequest.new()
	_http.timeout = StatsServer.REQUEST_TIMEOUT
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(flush)
	add_child(_retry_timer)
	if not queue.is_empty():
		print("HttpStatsSink: %d pedidos pendientes de la sesión anterior" % queue.size())
	flush()


func start_run(run: Dictionary) -> void:
	_enqueue(StatsQueue.KIND_RUN_STARTED, run["id"], run)


func add_event(run_id: String, event: Dictionary) -> void:
	_enqueue(StatsQueue.KIND_EVENT, run_id, event)


func finish_run(run_id: String, summary: Dictionary) -> void:
	_enqueue(StatsQueue.KIND_RUN_FINISHED, run_id, summary)


## Envía el próximo lote si no hay otro en camino ni una espera de reintento.
func flush() -> void:
	if _http == null or not _in_flight.is_empty() or not _retry_timer.is_stopped() or queue.is_empty():
		return
	_in_flight = queue.next_batch(BATCH_SIZE)
	var request := request_for(_in_flight, base_url)
	var error := _http.request(request["url"], StatsServer.JSON_HEADERS, request["method"],
			JSON.stringify(request["body"]))
	if error != OK:
		_in_flight.clear()
		_schedule_retry()


## Pedido HTTP de un lote de StatsQueue.next_batch: Dictionary con method
## (HTTPClient.Method), url y body.
static func request_for(batch: Array[Dictionary], url: String) -> Dictionary:
	var head: Dictionary = batch[0]
	var run_path := "%s/api/runs/%s" % [url, String(head["run_id"]).uri_encode()]
	if head["kind"] == StatsQueue.KIND_RUN_STARTED:
		return {"method": HTTPClient.METHOD_POST, "url": url + "/api/runs", "body": head["data"]}
	if head["kind"] == StatsQueue.KIND_RUN_FINISHED:
		return {"method": HTTPClient.METHOD_PATCH, "url": run_path, "body": head["data"]}
	var events := []
	for item in batch:
		events.append(item["data"])
	return {"method": HTTPClient.METHOD_POST, "url": run_path + "/events", "body": {"events": events}}


static func classify(result: int, response_code: int) -> Outcome:
	if result != HTTPRequest.RESULT_SUCCESS:
		return Outcome.RETRY
	if response_code >= 200 and response_code < 300:
		return Outcome.SENT
	if response_code == 408 or response_code == 429 or response_code >= 500:
		return Outcome.RETRY
	return Outcome.REJECTED


## Espera antes del próximo intento: MIN_RETRY_DELAY y luego el doble cada vez.
static func next_retry_delay(previous: float) -> float:
	if previous <= 0.0:
		return MIN_RETRY_DELAY
	return minf(previous * 2.0, MAX_RETRY_DELAY)


func _enqueue(kind: String, run_id: String, data: Dictionary) -> void:
	var dropped := queue.push(kind, run_id, data)
	if dropped > 0:
		push_warning("HttpStatsSink: cola llena (%d); se descartaron %d pedidos viejos" % [queue.max_items, dropped])
	queue.save(queue_path)
	flush()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var sent := _in_flight
	_in_flight = []
	match classify(result, response_code):
		Outcome.SENT:
			_retry_delay = 0.0
			queue.remove(sent)
			queue.save(queue_path)
			flush()
		Outcome.REJECTED:
			push_warning("HttpStatsSink: el servidor rechazó %d pedidos (%s, HTTP %d): %s" % [
				sent.size(), sent[0]["kind"], response_code, body.get_string_from_utf8().left(200)])
			queue.remove(sent)
			queue.save(queue_path)
			flush()
		Outcome.RETRY:
			_schedule_retry()


func _schedule_retry() -> void:
	_retry_delay = next_retry_delay(_retry_delay)
	_retry_timer.start(_retry_delay)
