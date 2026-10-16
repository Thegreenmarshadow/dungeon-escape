@tool
extends McpTestSuite
## Pruebas de la cola de estadísticas pendientes (StatsQueue) y de cómo
## HttpStatsSink arma los pedidos y decide reintentar. Sin red: solo lógica y
## archivos en una carpeta temporal de user://, que se borra al terminar.

const TEMP_DIR := "user://test_stats_queue"
const RUN_A := "aaaaaaaaaaaaaaaa"
const RUN_B := "bbbbbbbbbbbbbbbb"
const URL := "http://127.0.0.1:8765"

var _path := ""


func suite_name() -> String:
	return "stats_queue"


func setup() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	_path = TEMP_DIR.path_join("stats_queue.json")
	_clean_temp_dir()


func teardown() -> void:
	_clean_temp_dir()
	DirAccess.remove_absolute(TEMP_DIR)


func test_missing_file_gives_empty_queue() -> void:
	var queue := StatsQueue.load_from(_path)
	assert_true(queue.is_empty())
	assert_true(queue.next_batch(10).is_empty())
	assert_false(FileAccess.file_exists(_path), "cargar no debe crear el archivo")


func test_save_and_load_round_trip_keeps_order_and_integers() -> void:
	var queue := StatsQueue.new()
	queue.push(StatsQueue.KIND_RUN_STARTED, RUN_A, {"id": RUN_A, "run_seed": 4294967295, "start_level": 1})
	queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": 0, "type": "key_picked", "level": 2, "t_run_s": 1.5})
	assert_true(queue.save(_path))
	assert_false(FileAccess.file_exists(_path + ".tmp"), "quedó el archivo temporal")

	var loaded := StatsQueue.load_from(_path)
	assert_eq(loaded.size(), 2)
	assert_eq(loaded.items[0]["kind"], StatsQueue.KIND_RUN_STARTED)
	assert_eq(loaded.items[1]["data"]["type"], "key_picked")
	# JSON devuelve float; los enteros deben volver a ser int.
	assert_eq(typeof(loaded.items[0]["data"]["run_seed"]), TYPE_INT)
	assert_eq(loaded.items[0]["data"]["run_seed"], 4294967295)
	assert_eq(typeof(loaded.items[1]["data"]["seq"]), TYPE_INT)
	assert_eq(loaded.items[1]["data"]["t_run_s"], 1.5)
	# Los ids siguen creciendo después de cargar.
	loaded.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": 1})
	assert_gt(loaded.items[2]["id"], loaded.items[1]["id"])


func test_cap_drops_the_oldest_items() -> void:
	var queue := StatsQueue.new(3)
	for seq in 3:
		assert_eq(queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": seq}), 0)
	assert_eq(queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": 3}), 1, "debe avisar que descartó uno")
	assert_eq(queue.size(), 3)
	assert_eq(queue.items[0]["data"]["seq"], 1, "el más viejo (seq 0) debe salir")
	assert_eq(queue.items[-1]["data"]["seq"], 3)


func test_loading_more_items_than_the_cap_keeps_the_newest() -> void:
	var queue := StatsQueue.new()
	for seq in 5:
		queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": seq})
	queue.save(_path)
	var loaded := StatsQueue.load_from(_path, 2)
	assert_eq(loaded.size(), 2)
	assert_eq(loaded.items[0]["data"]["seq"], 3)


func test_batches_group_consecutive_events_of_the_same_run() -> void:
	var queue := StatsQueue.new()
	queue.push(StatsQueue.KIND_RUN_STARTED, RUN_A, {"id": RUN_A})
	for seq in 4:
		queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": seq})
	queue.push(StatsQueue.KIND_RUN_FINISHED, RUN_A, {"outcome": "died"})
	queue.push(StatsQueue.KIND_EVENT, RUN_B, {"seq": 0})

	# El inicio de la partida va solo.
	var first := queue.next_batch(3)
	assert_eq(first.size(), 1)
	assert_eq(first[0]["kind"], StatsQueue.KIND_RUN_STARTED)
	queue.remove(first)

	# Los eventos se agrupan hasta el máximo del lote.
	var events := queue.next_batch(3)
	assert_eq(events.size(), 3)
	queue.remove(events)
	var rest := queue.next_batch(3)
	assert_eq(rest.size(), 1, "el lote no cruza el cierre de la partida")
	assert_eq(rest[0]["data"]["seq"], 3)
	queue.remove(rest)

	assert_eq(queue.next_batch(3)[0]["kind"], StatsQueue.KIND_RUN_FINISHED)
	queue.remove(queue.next_batch(3))
	var other := queue.next_batch(3)
	assert_eq(other.size(), 1)
	assert_eq(other[0]["run_id"], RUN_B)


func test_remove_ignores_items_already_dropped_by_the_cap() -> void:
	var queue := StatsQueue.new(2)
	queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": 0})
	queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": 1})
	var in_flight := queue.next_batch(10)
	# Mientras el lote viaja llega otro evento y el tope descarta el seq 0.
	queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": 2})
	queue.remove(in_flight)
	assert_eq(queue.size(), 1)
	assert_eq(queue.items[0]["data"]["seq"], 2, "el evento nuevo no debe perderse")


func test_corrupt_file_gives_empty_queue_and_skips_invalid_items() -> void:
	_write(_path, "{no es json")
	assert_true(StatsQueue.load_from(_path).is_empty())

	_write(_path, JSON.stringify({"version": 1, "items": [
		{"id": 1, "kind": "event", "run_id": RUN_A, "data": {"seq": 0}},
		{"id": 2, "kind": "otra_cosa", "run_id": RUN_A, "data": {}},
		{"id": 3, "kind": "event", "run_id": "", "data": {}},
		"basura",
	]}))
	var queue := StatsQueue.load_from(_path)
	assert_eq(queue.size(), 1)
	assert_eq(queue.items[0]["id"], 1)


func test_requests_for_each_kind_of_batch() -> void:
	var queue := StatsQueue.new()
	queue.push(StatsQueue.KIND_RUN_STARTED, RUN_A, {"id": RUN_A, "player_name": "Ana"})
	queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": 0})
	queue.push(StatsQueue.KIND_EVENT, RUN_A, {"seq": 1})
	queue.push(StatsQueue.KIND_RUN_FINISHED, RUN_A, {"outcome": "quit"})

	var start := HttpStatsSink.request_for(queue.next_batch(10), URL)
	assert_eq(start["method"], HTTPClient.METHOD_POST)
	assert_eq(start["url"], URL + "/api/runs")
	assert_eq(start["body"]["player_name"], "Ana")
	queue.remove(queue.next_batch(10))

	var events := HttpStatsSink.request_for(queue.next_batch(10), URL)
	assert_eq(events["method"], HTTPClient.METHOD_POST)
	assert_eq(events["url"], "%s/api/runs/%s/events" % [URL, RUN_A])
	assert_eq(events["body"], {"events": [{"seq": 0}, {"seq": 1}]})
	queue.remove(queue.next_batch(10))

	var finish := HttpStatsSink.request_for(queue.next_batch(10), URL)
	assert_eq(finish["method"], HTTPClient.METHOD_PATCH)
	assert_eq(finish["url"], "%s/api/runs/%s" % [URL, RUN_A])


func test_responses_decide_between_sent_rejected_and_retry() -> void:
	var ok := HTTPRequest.RESULT_SUCCESS
	assert_eq(HttpStatsSink.classify(ok, 200), HttpStatsSink.Outcome.SENT)
	assert_eq(HttpStatsSink.classify(ok, 201), HttpStatsSink.Outcome.SENT)
	assert_eq(HttpStatsSink.classify(ok, 404), HttpStatsSink.Outcome.REJECTED)
	assert_eq(HttpStatsSink.classify(ok, 422), HttpStatsSink.Outcome.REJECTED)
	assert_eq(HttpStatsSink.classify(ok, 429), HttpStatsSink.Outcome.RETRY)
	assert_eq(HttpStatsSink.classify(ok, 503), HttpStatsSink.Outcome.RETRY)
	assert_eq(HttpStatsSink.classify(HTTPRequest.RESULT_CANT_CONNECT, 0), HttpStatsSink.Outcome.RETRY)
	assert_eq(HttpStatsSink.classify(HTTPRequest.RESULT_TIMEOUT, 0), HttpStatsSink.Outcome.RETRY)


func test_retry_delay_doubles_up_to_the_maximum() -> void:
	var delay := HttpStatsSink.next_retry_delay(0.0)
	assert_eq(delay, HttpStatsSink.MIN_RETRY_DELAY)
	delay = HttpStatsSink.next_retry_delay(delay)
	assert_eq(delay, HttpStatsSink.MIN_RETRY_DELAY * 2.0)
	for i in 20:
		delay = HttpStatsSink.next_retry_delay(delay)
	assert_eq(delay, HttpStatsSink.MAX_RETRY_DELAY)


# ----- ayudas -----

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean_temp_dir() -> void:
	for file_name in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR.path_join(file_name))
