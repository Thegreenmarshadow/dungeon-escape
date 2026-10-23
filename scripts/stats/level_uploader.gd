class_name LevelUploader
extends Node
## Sube al servidor de estadísticas cada archivo de nivel que escribe
## Telemetry (POST /api/runs/<partida>/levels, el JSON tal cual), para ver el
## recorrido y los mapas de calor en la página web. Lo crea Telemetry.
##
## Va aparte de la cola de eventos de RunTracker (StatsQueue, con tope de 1000
## pedidos): los pendientes se anotan en una LevelUploadQueue guardada en disco
## (pending_path), así un servidor apagado o cerrar el juego no los pierde y se
## reintentan más tarde, también en la próxima sesión.
##
## Orden: un nivel se sube recién cuando su partida ya existe en el servidor,
## es decir, cuando StatsQueue ya no tiene pendiente su inicio. Un 404 con el
## inicio todavía en la cola espera; sin él, la partida no va a llegar nunca y
## el archivo se descarta.
##
## Nunca bloquea el juego: un pedido a la vez, asíncrono y en otro hilo; el
## archivo se lee recién al subirlo. Reintentos como HttpStatsSink
## (next_retry_delay): 2 s y el doble en cada fallo seguido, hasta 60 s. El
## servidor ignora un archivo repetido (misma partida, nivel e intento: 200),
## así reenviarlo no lo duplica.
##
## Con la telemetría apagada en Ajustes (GameSettings) no sube nada: lo que
## quedó pendiente espera y se sube solo cuando se vuelve a activar.

## Espera antes de volver a mirar los niveles que todavía no se pueden subir:
## su partida no llegó al servidor o la telemetría está apagada.
const WAIT_DELAY := 5.0
## Tamaño máximo de un archivo de nivel (el mismo límite que el servidor).
const MAX_FILE_BYTES := 2_000_000

var base_url := StatsServer.BASE_URL
var pending_path := LevelUploadQueue.DEFAULT_PATH
var settings_path := GameSettings.DEFAULT_PATH
## Cola de eventos de RunTracker: mientras tenga el inicio de una partida, sus
## niveles esperan. null = no esperar.
var stats_queue: StatsQueue
var pending: LevelUploadQueue

var _http: HTTPRequest
var _retry_timer: Timer
var _in_flight: Dictionary = {}
var _retry_delay := 0.0


func _ready() -> void:
	# Sigue subiendo con el juego en pausa (pantallas de fin de nivel).
	process_mode = Node.PROCESS_MODE_ALWAYS
	pending = LevelUploadQueue.load_from(pending_path)
	_http = HTTPRequest.new()
	_http.timeout = StatsServer.REQUEST_TIMEOUT
	_http.use_threads = true
	_http.request_completed.connect(_on_request_completed)
	add_child(_http)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.timeout.connect(flush)
	add_child(_retry_timer)
	if not pending.is_empty():
		print("LevelUploader: %d niveles pendientes de la sesión anterior" % pending.size())
	flush()


## Anota el archivo de nivel file (de la partida del servidor run_id) para
## subirlo y prueba enseguida.
func enqueue(file: String, run_id: String, level: int, attempt: int) -> void:
	if pending == null or file.is_empty() or run_id.is_empty():
		return
	var dropped := pending.push(file, run_id, level, attempt)
	if dropped > 0:
		push_warning("LevelUploader: lista llena (%d); se descartaron %d niveles viejos" % [pending.max_items, dropped])
	pending.save(pending_path)
	flush()


## true mientras hay un archivo en camino al servidor.
func is_uploading() -> bool:
	return not _in_flight.is_empty()


## Sube el próximo nivel listo si no hay otro en camino ni una espera.
func flush() -> void:
	if _http == null or is_uploading() or not _retry_timer.is_stopped() or pending.is_empty():
		return
	if not GameSettings.telemetry_enabled(settings_path):
		_retry_timer.start(WAIT_DELAY)
		return
	var item := pending.next_ready(_run_start_pending)
	if item.is_empty():
		_retry_timer.start(WAIT_DELAY)
		return
	var body := _read_file(item)
	if body.is_empty():
		pending.remove(item["id"])
		pending.save(pending_path)
		flush.call_deferred()
		return
	_in_flight = item
	var url := "%s/api/runs/%s/levels" % [base_url, String(item["run_id"]).uri_encode()]
	var error := _http.request(url, StatsServer.JSON_HEADERS, HTTPClient.METHOD_POST, body)
	if error != OK:
		_in_flight = {}
		_schedule_retry()


func _run_start_pending(run_id: String) -> bool:
	return stats_queue != null and stats_queue.has_run_start(run_id)


## Texto del archivo, o "" (con un aviso) si ya no está o es demasiado grande.
func _read_file(item: Dictionary) -> String:
	var path: String = item["file"]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("LevelUploader: no se pudo leer %s; no se sube" % path)
		return ""
	if file.get_length() == 0 or file.get_length() > MAX_FILE_BYTES:
		push_warning("LevelUploader: %s está vacío o es demasiado grande; no se sube" % path)
		return ""
	return file.get_as_text()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var item := _in_flight
	_in_flight = {}
	if item.is_empty():
		return
	match LevelUploadQueue.decide(result, response_code, _run_start_pending(item["run_id"])):
		LevelUploadQueue.Action.DONE:
			_retry_delay = 0.0
			pending.remove(item["id"])
			pending.save(pending_path)
			flush()
		LevelUploadQueue.Action.DROP:
			push_warning("LevelUploader: el servidor rechazó el nivel %d (intento %d) de %s (HTTP %d): %s" % [
				item["level"], item["attempt"], item["run_id"], response_code,
				body.get_string_from_utf8().left(200)])
			pending.remove(item["id"])
			pending.save(pending_path)
			flush()
		LevelUploadQueue.Action.WAIT:
			_retry_timer.start(WAIT_DELAY)
		LevelUploadQueue.Action.RETRY:
			_schedule_retry()


func _schedule_retry() -> void:
	_retry_delay = HttpStatsSink.next_retry_delay(_retry_delay)
	_retry_timer.start(_retry_delay)
