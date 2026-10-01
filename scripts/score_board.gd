@tool
class_name ScoreBoard
extends RefCounted
## Tabla de mejores puntajes guardada en disco (JSON local, sin red).
##
## Es lógica pura: no crea nodos y todas las funciones reciben la ruta del
## archivo, así las pruebas pueden usar una ruta temporal y no tocan el archivo
## real del jugador. Nunca lanza errores por problemas de disco: un archivo
## ausente o dañado da una tabla vacía y una falla al guardar solo devuelve
## false con un aviso en el log.
##
## Un "tablero" (board) es un Dictionary con:
##   entries:    Array de entradas ordenadas de mejor a peor (máximo MAX_ENTRIES).
##   best_level: nivel más alto alcanzado alguna vez. Se guarda aparte porque
##               una partida que llegó lejos pero sumó pocos puntos puede caer
##               fuera del top 10 sin que el récord de nivel deba perderse.
## Una entrada (entry) es un Dictionary con: score, level, kills y date (fecha
## y hora locales en ISO 8601, por ejemplo "2026-09-29T14:38:00").
##
## Orden: más puntos primero; si empatan, el nivel más alto; si vuelven a
## empatar, la partida más reciente. Una entrada idéntica a una existente queda
## detrás de ella.
##
## Formato del archivo (versión 1):
##   {"version": 1, "best_level": 3, "entries": [{"score": 250, "level": 3,
##    "kills": 9, "date": "2026-09-29T14:38:00"}, ...]}

const DEFAULT_PATH := "user://scores.json"
const VERSION := 1
const MAX_ENTRIES := 10
## Límites para valores leídos del disco: un archivo editado a mano no puede
## meter números absurdos que rompan la interfaz.
const MAX_SCORE := 999_999_999
const MAX_LEVEL := 9_999
const MAX_KILLS := 999_999
## Largo exacto de una fecha ISO 8601 sin zona horaria ("2026-09-29T14:38:00").
const DATE_LENGTH := 19

## Patrón de fecha válida. Se compila una sola vez, la primera vez que se usa.
static var _date_regex: RegEx


static func empty_board() -> Dictionary:
	return {"entries": [], "best_level": 0}


## Crea una entrada válida (valores acotados). date vacío usa la hora actual.
static func make_entry(score: int, level: int, kills: int, date: String = "") -> Dictionary:
	return {
		"score": clampi(score, 0, MAX_SCORE),
		"level": clampi(level, 1, MAX_LEVEL),
		"kills": clampi(kills, 0, MAX_KILLS),
		"date": date if not date.is_empty() else Time.get_datetime_string_from_system(false),
	}


## Carga la tabla desde path. Nunca falla: si el archivo no existe o está
## dañado devuelve una tabla vacía. Un archivo dañado se conserva como
## "<path>.bak" en lugar de borrarse.
static func load_board(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return empty_board()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ScoreBoard: no se pudo abrir %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return empty_board()
	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		_set_aside_corrupt_file(path, "JSON inválido: %s" % json.get_error_message())
		return empty_board()
	var board: Variant = _board_from_data(json.data)
	if board == null:
		_set_aside_corrupt_file(path, "estructura no reconocida")
		return empty_board()
	return board


## Guarda la tabla en path. Escribe primero a un archivo temporal y luego lo
## renombra, así un corte a mitad de escritura no deja el archivo a medias.
## Devuelve false (con un aviso) si algo falla.
static func save_board(board: Dictionary, path: String = DEFAULT_PATH) -> bool:
	var data := {
		"version": VERSION,
		"best_level": board.get("best_level", 0),
		"entries": board.get("entries", []),
	}
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("ScoreBoard: no se pudo escribir %s (%s)" % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_warning("ScoreBoard: falló la escritura de %s (%s)" % [temp_path, error_string(write_error)])
		DirAccess.remove_absolute(temp_path)
		return false
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		push_warning("ScoreBoard: no se pudo reemplazar %s (%s)" % [path, error_string(rename_error)])
		DirAccess.remove_absolute(temp_path)
		return false
	return true


## Mejor puntaje de la tabla, o 0 si está vacía.
static func best_score(board: Dictionary) -> int:
	var entries: Array = board.get("entries", [])
	return 0 if entries.is_empty() else int(entries[0]["score"])


## Incorpora entry a una copia de board (board no se modifica). Devuelve un
## Dictionary con:
##   board: la tabla resultante (best_level se actualiza aunque entry quede
##          fuera del top).
##   rank:  posición (desde 1) que ocupa entry, o 0 si quedó fuera del top.
static func with_entry(board: Dictionary, entry: Dictionary) -> Dictionary:
	var entries: Array = board.get("entries", []).duplicate()
	var rank := 1
	for existing: Dictionary in entries:
		if _is_better(entry, existing):
			break
		rank += 1
	var result := {
		"entries": entries,
		"best_level": maxi(int(board.get("best_level", 0)), int(entry["level"])),
	}
	if rank > MAX_ENTRIES:
		return {"board": result, "rank": 0}
	entries.insert(rank - 1, entry)
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)
	return {"board": result, "rank": rank}


## Registra una partida terminada: carga la tabla, agrega la entrada y guarda.
## No registra partidas de 0 puntos: no dicen nada y solo ensucian la tabla.
## Devuelve un Dictionary con:
##   recorded:      true si la partida entró en la tabla.
##   is_new_record: true si superó el mejor puntaje anterior (o es la primera
##                  partida con puntos).
##   rank:          posición en la tabla (desde 1), 0 si no entró.
##   previous_best: mejor puntaje antes de esta partida.
##   saved:         true si el archivo se escribió bien.
##   board:         la tabla resultante.
static func record_run(score: int, level: int, kills: int, path: String = DEFAULT_PATH, date: String = "") -> Dictionary:
	var board := load_board(path)
	var previous_best := best_score(board)
	var result := {
		"recorded": false,
		"is_new_record": false,
		"rank": 0,
		"previous_best": previous_best,
		"saved": false,
		"board": board,
	}
	if score <= 0:
		return result
	var added := with_entry(board, make_entry(score, level, kills, date))
	result["board"] = added["board"]
	result["rank"] = added["rank"]
	result["recorded"] = added["rank"] > 0
	result["is_new_record"] = score > previous_best
	result["saved"] = save_board(added["board"], path)
	return result


## Fecha para mostrar en la interfaz ("29/09/2026"), o "--" si la entrada no
## tiene una fecha válida.
static func display_date(entry: Dictionary) -> String:
	var date := str(entry.get("date", ""))
	if not _is_valid_date(date):
		return "--"
	return "%s/%s/%s" % [date.substr(8, 2), date.substr(5, 2), date.substr(0, 4)]


# Devuelve una tabla saneada a partir de los datos leídos del JSON, o null si
# la estructura general no es válida. Las entradas individuales inválidas se
# descartan sin invalidar el resto.
static func _board_from_data(data: Variant) -> Variant:
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var version: Variant = _read_number(data.get("version"), 0, VERSION + 1)
	if version == null or int(version) < 1 or int(version) > VERSION:
		return null
	if typeof(data.get("entries")) != TYPE_ARRAY:
		return null

	var entries: Array = []
	var skipped := 0
	for raw: Variant in data["entries"]:
		var entry: Variant = _entry_from_data(raw)
		if entry == null:
			skipped += 1
		else:
			entries.append(entry)
	if skipped > 0:
		push_warning("ScoreBoard: se ignoraron %d entradas inválidas" % skipped)
	entries.sort_custom(ScoreBoard._is_better)
	if entries.size() > MAX_ENTRIES:
		entries.resize(MAX_ENTRIES)

	var best_level := 0
	var stored_best: Variant = _read_number(data.get("best_level"), 0, MAX_LEVEL)
	if stored_best != null:
		best_level = int(stored_best)
	for entry: Dictionary in entries:
		best_level = maxi(best_level, int(entry["level"]))
	return {"entries": entries, "best_level": best_level}


static func _entry_from_data(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var score: Variant = _read_number(raw.get("score"), 0, MAX_SCORE)
	var level: Variant = _read_number(raw.get("level"), 1, MAX_LEVEL)
	var kills: Variant = _read_number(raw.get("kills"), 0, MAX_KILLS)
	if score == null or level == null or kills == null or int(score) <= 0:
		return null
	var date := ""
	if typeof(raw.get("date")) == TYPE_STRING and _is_valid_date(raw["date"]):
		date = raw["date"]
	return {"score": int(score), "level": int(level), "kills": int(kills), "date": date}


## Convierte un valor del JSON a entero acotado a [min_value, max_value].
## Devuelve null si no es un número finito (los booleanos y textos no valen).
static func _read_number(value: Variant, min_value: int, max_value: int) -> Variant:
	var value_type := typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return null
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return null
	return int(clampf(number, min_value, max_value))


static func _is_valid_date(date: String) -> bool:
	if date.length() != DATE_LENGTH:
		return false
	if _date_regex == null:
		_date_regex = RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$")
	return _date_regex.search(date) != null


## true si a va estrictamente antes que b en la tabla.
static func _is_better(a: Dictionary, b: Dictionary) -> bool:
	if a["score"] != b["score"]:
		return a["score"] > b["score"]
	if a["level"] != b["level"]:
		return a["level"] > b["level"]
	# Las fechas ISO se ordenan como texto; una fecha vacía (inválida) es la
	# más antigua.
	return str(a["date"]) > str(b["date"])


static func _set_aside_corrupt_file(path: String, reason: String) -> void:
	var backup_path := path + ".bak"
	push_warning("ScoreBoard: %s está dañado (%s); se guarda como %s y se empieza con una tabla vacía" % [path, reason, backup_path])
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	var error := DirAccess.rename_absolute(path, backup_path)
	if error != OK:
		push_warning("ScoreBoard: no se pudo renombrar %s (%s)" % [path, error_string(error)])
