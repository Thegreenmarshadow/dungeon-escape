@tool
extends McpTestSuite
## Pruebas de la lista de archivos de nivel pendientes de subir
## (LevelUploadQueue): orden, espera a que la partida exista en el servidor,
## tope, guardado y qué hacer con cada respuesta. Sin red: solo lógica y
## archivos en una carpeta temporal de user://, que se borra al terminar.

const TEMP_DIR := "user://test_level_upload_queue"
const RUN_A := "aaaaaaaaaaaaaaaa"
const RUN_B := "bbbbbbbbbbbbbbbb"

var _path := ""


func suite_name() -> String:
	return "level_upload_queue"


func setup() -> void:
	JsonFile.remove_tree(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	_path = TEMP_DIR.path_join("level_uploads.json")


func teardown() -> void:
	JsonFile.remove_tree(TEMP_DIR)


func test_files_wait_until_their_run_reaches_the_server() -> void:
	var queue := LevelUploadQueue.new()
	queue.push("a_level_1.json", RUN_A, 1, 1)
	queue.push("b_level_1.json", RUN_B, 1, 1)
	queue.push("a_level_2.json", RUN_A, 2, 1)

	var stats := StatsQueue.new()
	stats.push(StatsQueue.KIND_RUN_STARTED, RUN_A, {"id": RUN_A})
	var blocked := func(run_id: String) -> bool: return stats.has_run_start(run_id)
	assert_eq(queue.next_ready(blocked)["file"], "b_level_1.json", "la partida A todavía no existe")

	stats.remove(stats.next_batch(10))
	var first := queue.next_ready(blocked)
	assert_eq(first["file"], "a_level_1.json", "creada la partida, sale el más viejo")
	queue.remove(first["id"])
	assert_eq(queue.next_ready(blocked)["file"], "b_level_1.json")
	assert_true(LevelUploadQueue.new().next_ready(blocked).is_empty())


func test_the_same_file_is_not_queued_twice_and_bad_entries_are_ignored() -> void:
	var queue := LevelUploadQueue.new()
	queue.push("level_1.json", RUN_A, 1, 1)
	queue.push("level_1.json", RUN_A, 1, 1)
	queue.push("", RUN_A, 1, 1)
	queue.push("level_2.json", "", 2, 1)
	assert_eq(queue.size(), 1)


func test_cap_drops_the_oldest_files() -> void:
	var queue := LevelUploadQueue.new(2)
	assert_eq(queue.push("1.json", RUN_A, 1, 1), 0)
	assert_eq(queue.push("2.json", RUN_A, 2, 1), 0)
	assert_eq(queue.push("3.json", RUN_A, 3, 1), 1, "descarta uno")
	assert_eq(queue.items.map(func(item: Dictionary) -> String: return item["file"]), ["2.json", "3.json"])


func test_save_and_load_round_trip() -> void:
	var queue := LevelUploadQueue.new()
	queue.push("user://profiles/ana/runs/x/level_2_2.json", RUN_A, 2, 2)
	queue.push("user://profiles/ana/runs/x/level_3.json", RUN_A, 3, 1)
	queue.remove(queue.items[0]["id"])
	assert_true(queue.save(_path))

	var loaded := LevelUploadQueue.load_from(_path)
	assert_eq(loaded.size(), 1)
	var item := loaded.items[0]
	assert_eq(item["file"], "user://profiles/ana/runs/x/level_3.json")
	assert_eq(item["run_id"], RUN_A)
	assert_eq(typeof(item["level"]), TYPE_INT, "los números vuelven a ser enteros")
	assert_eq(item["level"], 3)
	loaded.push("level_4.json", RUN_A, 4, 1)
	assert_gt(loaded.items[1]["id"], item["id"], "los ids siguen creciendo")


func test_missing_or_damaged_file_gives_an_empty_list() -> void:
	assert_true(LevelUploadQueue.load_from(_path).is_empty())
	assert_false(FileAccess.file_exists(_path), "cargar no crea el archivo")
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{roto")
	file.close()
	assert_true(LevelUploadQueue.load_from(_path).is_empty())
	JsonFile.write(_path, {"items": [{"id": 1, "file": "ok.json", "run_id": RUN_A}, {"id": 2}, "x"]})
	assert_eq(LevelUploadQueue.load_from(_path).size(), 1, "descarta los elementos inválidos")


func test_what_to_do_with_each_answer() -> void:
	var ok := HTTPRequest.RESULT_SUCCESS
	assert_eq(LevelUploadQueue.decide(ok, 201, false), LevelUploadQueue.Action.DONE)
	assert_eq(LevelUploadQueue.decide(ok, 200, false), LevelUploadQueue.Action.DONE, "ya lo tenía")
	assert_eq(LevelUploadQueue.decide(ok, 404, true), LevelUploadQueue.Action.WAIT,
			"la partida está por llegar")
	assert_eq(LevelUploadQueue.decide(ok, 404, false), LevelUploadQueue.Action.DROP,
			"la partida no va a llegar nunca")
	assert_eq(LevelUploadQueue.decide(ok, 422, false), LevelUploadQueue.Action.DROP)
	assert_eq(LevelUploadQueue.decide(ok, 413, false), LevelUploadQueue.Action.DROP)
	assert_eq(LevelUploadQueue.decide(ok, 503, false), LevelUploadQueue.Action.RETRY)
	assert_eq(LevelUploadQueue.decide(ok, 429, false), LevelUploadQueue.Action.RETRY)
	assert_eq(LevelUploadQueue.decide(HTTPRequest.RESULT_CANT_CONNECT, 0, false),
			LevelUploadQueue.Action.RETRY, "servidor apagado")
