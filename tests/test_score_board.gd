@tool
extends McpTestSuite
## Pruebas de la tabla de mejores puntajes (ScoreBoard). Cada prueba usa un
## archivo propio dentro de una carpeta temporal en user://, así nunca toca el
## archivo real del jugador; la carpeta se borra al terminar cada prueba.

const TEMP_DIR := "user://test_score_board"
const DATE := "2026-09-29T14:38:00"


var _path := ""


func suite_name() -> String:
	return "score_board"


func setup() -> void:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	_path = TEMP_DIR.path_join("scores.json")
	_clean_temp_dir()


func teardown() -> void:
	_clean_temp_dir()
	DirAccess.remove_absolute(TEMP_DIR)


func test_missing_file_gives_empty_board() -> void:
	var board := ScoreBoard.load_board(_path)
	assert_eq(board["entries"], [])
	assert_eq(board["best_level"], 0)
	assert_eq(ScoreBoard.best_score(board), 0)
	assert_false(FileAccess.file_exists(_path), "cargar no debe crear el archivo")


func test_empty_file_gives_empty_board() -> void:
	_write(_path, "")
	var board := ScoreBoard.load_board(_path)
	assert_eq(board["entries"], [])
	assert_eq(board["best_level"], 0)


func test_save_and_load_round_trip() -> void:
	var board := ScoreBoard.empty_board()
	board = ScoreBoard.with_entry(board, ScoreBoard.make_entry(250, 3, 9, DATE))["board"]
	board = ScoreBoard.with_entry(board, ScoreBoard.make_entry(80, 1, 8, "2026-09-28T10:00:00"))["board"]
	assert_true(ScoreBoard.save_board(board, _path))
	assert_false(FileAccess.file_exists(_path + ".tmp"), "quedó el archivo temporal")

	var loaded := ScoreBoard.load_board(_path)
	assert_eq(loaded, board)
	assert_eq(loaded["entries"][0], {"score": 250, "level": 3, "kills": 9, "date": DATE})
	assert_eq(ScoreBoard.best_score(loaded), 250)


func test_entries_are_ordered_with_tie_breaks() -> void:
	var board := ScoreBoard.empty_board()
	var older_low := ScoreBoard.make_entry(100, 2, 1, "2026-01-01T00:00:00")
	var newer_low := ScoreBoard.make_entry(100, 2, 2, "2026-02-01T00:00:00")
	var higher_level := ScoreBoard.make_entry(100, 4, 3, "2025-01-01T00:00:00")
	var best := ScoreBoard.make_entry(300, 1, 4, "2025-01-01T00:00:00")
	for entry in [older_low, best, newer_low, higher_level]:
		board = ScoreBoard.with_entry(board, entry)["board"]
	# Más puntos primero; con empate, más nivel; con empate, más reciente.
	assert_eq(board["entries"], [best, higher_level, newer_low, older_low])

	# Una entrada idéntica a una existente queda detrás de ella.
	var twin := older_low.duplicate()
	var added := ScoreBoard.with_entry(board, twin)
	assert_eq(added["rank"], 5)


func test_loading_sorts_unsorted_file_entries() -> void:
	_write(_path, JSON.stringify({"version": 1, "best_level": 0, "entries": [
		{"score": 10, "level": 1, "kills": 1, "date": DATE},
		{"score": 30, "level": 1, "kills": 3, "date": DATE},
		{"score": 20, "level": 5, "kills": 2, "date": DATE},
		{"score": 20, "level": 7, "kills": 2, "date": DATE},
	]}))
	var board := ScoreBoard.load_board(_path)
	var scores := []
	var levels := []
	for entry: Dictionary in board["entries"]:
		scores.append(entry["score"])
		levels.append(entry["level"])
	assert_eq(scores, [30, 20, 20, 10])
	assert_eq(levels, [1, 7, 5, 1])
	assert_eq(board["best_level"], 7, "best_level sale de las entradas si el guardado es menor")


func test_board_keeps_top_ten_and_rank_zero_when_outside() -> void:
	var board := ScoreBoard.empty_board()
	for i in ScoreBoard.MAX_ENTRIES:
		var added := ScoreBoard.with_entry(board, ScoreBoard.make_entry((i + 1) * 100, 1, 0, DATE))
		board = added["board"]
		assert_eq(added["rank"], 1, "cada entrada nueva es la mejor")
	assert_eq(board["entries"].size(), ScoreBoard.MAX_ENTRIES)

	# Peor que todas: queda fuera y la tabla no cambia.
	var outside := ScoreBoard.with_entry(board, ScoreBoard.make_entry(50, 1, 0, DATE))
	assert_eq(outside["rank"], 0)
	assert_eq(outside["board"]["entries"], board["entries"])

	# En el medio: entra en su puesto y la peor sale.
	var middle := ScoreBoard.with_entry(board, ScoreBoard.make_entry(550, 1, 0, DATE))
	assert_eq(middle["rank"], 6)
	var entries: Array = middle["board"]["entries"]
	assert_eq(entries.size(), ScoreBoard.MAX_ENTRIES)
	assert_eq(entries[5]["score"], 550)
	assert_eq(entries[-1]["score"], 200, "la peor (100) debe salir de la tabla")

	# with_entry no modifica la tabla original.
	assert_eq(board["entries"].size(), ScoreBoard.MAX_ENTRIES)
	assert_eq(board["entries"][-1]["score"], 100)


func test_record_run_with_zero_points_is_not_recorded() -> void:
	var result := ScoreBoard.record_run(0, 4, 0, _path, DATE)
	assert_false(result["recorded"])
	assert_false(result["is_new_record"])
	assert_eq(result["rank"], 0)
	assert_false(FileAccess.file_exists(_path), "una partida sin puntos no debe escribir el archivo")


func test_record_run_reports_new_records() -> void:
	var first := ScoreBoard.record_run(100, 1, 10, _path, DATE)
	assert_true(first["recorded"])
	assert_true(first["is_new_record"], "la primera partida con puntos es récord")
	assert_true(first["saved"])
	assert_eq(first["rank"], 1)
	assert_eq(first["previous_best"], 0)

	var lower := ScoreBoard.record_run(60, 1, 6, _path, DATE)
	assert_false(lower["is_new_record"])
	assert_eq(lower["rank"], 2)
	assert_eq(lower["previous_best"], 100)

	var tie := ScoreBoard.record_run(100, 1, 10, _path, DATE)
	assert_false(tie["is_new_record"], "igualar el récord no es récord nuevo")

	var higher := ScoreBoard.record_run(150, 2, 5, _path, DATE)
	assert_true(higher["is_new_record"])
	assert_eq(higher["rank"], 1)

	var stored := ScoreBoard.load_board(_path)
	assert_eq(stored["entries"].size(), 4)
	assert_eq(ScoreBoard.best_score(stored), 150)


func test_best_level_is_kept_when_run_falls_out_of_top_ten() -> void:
	for i in ScoreBoard.MAX_ENTRIES:
		ScoreBoard.record_run(1000 + i, 2, 0, _path, DATE)
	var result := ScoreBoard.record_run(10, 9, 1, _path, DATE)
	assert_false(result["recorded"])
	assert_eq(result["rank"], 0)
	assert_true(result["saved"], "se guarda igual para conservar best_level")

	var stored := ScoreBoard.load_board(_path)
	assert_eq(stored["best_level"], 9)
	assert_eq(stored["entries"].size(), ScoreBoard.MAX_ENTRIES)
	for entry: Dictionary in stored["entries"]:
		assert_ne(entry["level"], 9)


func test_corrupt_json_is_moved_to_backup() -> void:
	_write(_path, "{esto no es json")
	var board := ScoreBoard.load_board(_path)
	assert_eq(board, ScoreBoard.empty_board())
	assert_false(FileAccess.file_exists(_path))
	assert_true(FileAccess.file_exists(_path + ".bak"))
	assert_eq(FileAccess.get_file_as_string(_path + ".bak"), "{esto no es json")

	# Después se puede volver a registrar con normalidad.
	assert_true(ScoreBoard.record_run(40, 1, 4, _path, DATE)["saved"])
	assert_eq(ScoreBoard.best_score(ScoreBoard.load_board(_path)), 40)


func test_unknown_structure_is_moved_to_backup() -> void:
	for text in ["[1, 2, 3]", "{\"version\": 99, \"entries\": []}", "{\"version\": 1, \"entries\": 5}"]:
		_write(_path, text)
		assert_eq(ScoreBoard.load_board(_path), ScoreBoard.empty_board(), text)
		assert_true(FileAccess.file_exists(_path + ".bak"), text)
		assert_eq(FileAccess.get_file_as_string(_path + ".bak"), text)


func test_invalid_entries_are_skipped() -> void:
	_write(_path, JSON.stringify({"version": 1, "best_level": 2, "entries": [
		{"score": 120, "level": 2, "kills": 3, "date": DATE},
		"no soy una entrada",
		{"score": "999", "level": 1, "kills": 0, "date": DATE},
		{"score": 0, "level": 1, "kills": 0, "date": DATE},
		{"score": -5, "level": 1, "kills": 0, "date": DATE},
		{"score": true, "level": 1, "kills": 0, "date": DATE},
		{"level": 1, "kills": 0, "date": DATE},
		{"score": 70, "level": 99999, "kills": -3, "date": "ayer"},
	]}))
	var board := ScoreBoard.load_board(_path)
	assert_false(FileAccess.file_exists(_path + ".bak"), "entradas inválidas no dañan el archivo")
	assert_eq(board["entries"], [
		{"score": 120, "level": 2, "kills": 3, "date": DATE},
		# Valores acotados y fecha inválida descartada.
		{"score": 70, "level": ScoreBoard.MAX_LEVEL, "kills": 0, "date": ""},
	])
	assert_eq(board["best_level"], ScoreBoard.MAX_LEVEL)


func test_display_date() -> void:
	assert_eq(ScoreBoard.display_date({"date": DATE}), "29/09/2026")
	assert_eq(ScoreBoard.display_date({"date": ""}), "--")
	assert_eq(ScoreBoard.display_date({"date": "2026-09-29"}), "--")
	assert_eq(ScoreBoard.display_date({"date": "2026-09-29T14:38:0x"}), "--")
	assert_eq(ScoreBoard.display_date({}), "--")
	# make_entry sin fecha usa la hora actual, que debe ser mostrable.
	assert_ne(ScoreBoard.display_date(ScoreBoard.make_entry(10, 1, 1)), "--")


# ----- ayudas -----

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Borra todos los archivos de la carpeta temporal (scores.json, .bak, .tmp).
func _clean_temp_dir() -> void:
	for file_name in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR.path_join(file_name))
