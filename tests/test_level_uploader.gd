@tool
extends McpTestSuite
## Pruebas de LevelUploader, el nodo que sube los archivos de nivel: espera a
## que la partida exista en el servidor, no sube nada con la telemetría
## apagada, conserva los pendientes al cerrar el juego y decide qué hacer con
## cada respuesta. Sin servidor: la dirección apunta a un puerto cerrado y las
## respuestas se simulan (_answer). Todo en una carpeta temporal de user://,
## que se borra al terminar.

const TEMP_DIR := "user://test_level_uploader"
const CLOSED_URL := "http://127.0.0.1:1"
const RUN_A := "aaaaaaaaaaaaaaaa"
const RUN_B := "bbbbbbbbbbbbbbbb"

var _pending_path := ""
var _settings_path := ""


func suite_name() -> String:
	return "level_uploader"


func setup() -> void:
	JsonFile.remove_tree(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	_pending_path = TEMP_DIR.path_join("level_uploads.json")
	_settings_path = TEMP_DIR.path_join("settings.cfg")


func teardown() -> void:
	JsonFile.remove_tree(TEMP_DIR)


func test_a_level_waits_until_its_run_reaches_the_server() -> void:
	var stats := StatsQueue.new()
	stats.push(StatsQueue.KIND_RUN_STARTED, RUN_A, {"id": RUN_A})
	var uploader := _make_uploader(stats)
	var file := _write_level("level_1.json")
	uploader.enqueue(file, RUN_A, 1, 1)
	assert_false(uploader.is_uploading(), "el inicio de la partida sigue en la cola de eventos")
	assert_false(uploader._retry_timer.is_stopped(), "vuelve a mirar más tarde")

	stats.remove(stats.next_batch(10))
	_wake(uploader)
	assert_true(uploader.is_uploading(), "creada la partida, sube el nivel")
	assert_eq(uploader._in_flight["file"], file)
	assert_eq(uploader._in_flight["run_id"], RUN_A)
	_answer(uploader, HTTPRequest.RESULT_SUCCESS, 201)
	assert_true(uploader.pending.is_empty(), "subido, sale de la lista")
	assert_true(LevelUploadQueue.load_from(_pending_path).is_empty(), "también del disco")


func test_nothing_is_uploaded_while_telemetry_is_off() -> void:
	GameSettings.set_telemetry_enabled(false, _settings_path)
	var uploader := _make_uploader()
	uploader.enqueue(_write_level("level_1.json"), RUN_A, 1, 1)
	assert_false(uploader.is_uploading())
	assert_eq(LevelUploadQueue.load_from(_pending_path).size(), 1, "queda anotado en disco")

	GameSettings.set_telemetry_enabled(true, _settings_path)
	_wake(uploader)
	assert_true(uploader.is_uploading(), "al activarla sube lo pendiente sin esperar otro nivel")


func test_offline_uploads_are_retried_and_survive_a_restart() -> void:
	var file := _write_level("level_2.json")
	var uploader := _make_uploader()
	uploader.enqueue(file, RUN_A, 2, 1)
	assert_true(uploader.is_uploading())
	_answer(uploader, HTTPRequest.RESULT_CANT_CONNECT, 0)
	assert_eq(uploader.pending.size(), 1, "servidor apagado: queda pendiente")
	assert_eq(uploader._retry_timer.wait_time, HttpStatsSink.MIN_RETRY_DELAY)
	_wake(uploader)
	_answer(uploader, HTTPRequest.RESULT_SUCCESS, 503)
	assert_eq(uploader._retry_timer.wait_time, HttpStatsSink.MIN_RETRY_DELAY * 2.0, "la espera se duplica")

	# Cerrar el juego y volver a abrirlo.
	uploader.get_parent().remove_child(uploader)
	uploader.free()
	var restarted := _make_uploader()
	assert_eq(restarted.pending.size(), 1)
	assert_true(restarted.is_uploading(), "lo reintenta al abrir")
	assert_eq(restarted._in_flight["file"], file)
	_answer(restarted, HTTPRequest.RESULT_SUCCESS, 200)
	assert_true(restarted.pending.is_empty(), "200: el servidor ya lo tenía")


func test_rejected_or_missing_files_are_dropped() -> void:
	var uploader := _make_uploader()
	uploader.enqueue(TEMP_DIR.path_join("no_existe.json"), RUN_A, 1, 1)
	assert_false(uploader.is_uploading())
	assert_true(uploader.pending.is_empty(), "un archivo que ya no está no se sube")

	uploader.enqueue(_write_level("level_1.json"), RUN_A, 1, 1)
	_answer(uploader, HTTPRequest.RESULT_SUCCESS, 422)
	assert_true(uploader.pending.is_empty(), "422: el servidor no lo acepta")

	uploader.enqueue(_write_level("level_2.json"), RUN_B, 2, 1)
	_answer(uploader, HTTPRequest.RESULT_SUCCESS, 404)
	assert_true(uploader.pending.is_empty(), "404 sin el inicio en la cola: la partida no va a llegar")


func test_levels_without_a_server_run_are_not_queued() -> void:
	var uploader := _make_uploader()
	uploader.enqueue(_write_level("level_1.json"), "", 1, 1)
	assert_true(uploader.pending.is_empty())
	assert_false(FileAccess.file_exists(_pending_path))


# ----- ayudas -----

## LevelUploader en el árbol, con todo en TEMP_DIR y un servidor que no existe.
func _make_uploader(stats: StatsQueue = null) -> LevelUploader:
	var uploader := LevelUploader.new()
	uploader.base_url = CLOSED_URL
	uploader.pending_path = _pending_path
	uploader.settings_path = _settings_path
	uploader.stats_queue = stats
	track(uploader)
	(Engine.get_main_loop() as SceneTree).root.add_child(uploader)
	return uploader


## Archivo de nivel mínimo en TEMP_DIR; devuelve su ruta.
func _write_level(file_name: String) -> String:
	var path := TEMP_DIR.path_join(file_name)
	JsonFile.write(path, {"schema_version": 1, "level": 1, "outcome": "completed", "map": {"size": [1, 1]}})
	return path


## Como si venciera la espera del reintento.
func _wake(uploader: LevelUploader) -> void:
	uploader._retry_timer.stop()
	uploader.flush()


## Responde al pedido en camino como si llegara del servidor.
func _answer(uploader: LevelUploader, result: int, response_code: int) -> void:
	uploader._http.cancel_request()
	uploader._on_request_completed(result, response_code, PackedStringArray(), PackedByteArray())
