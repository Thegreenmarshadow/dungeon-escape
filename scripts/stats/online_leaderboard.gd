class_name OnlineLeaderboard
extends Node
## Pide la tabla de mejores puntajes al servidor local de estadísticas
## (GET /api/leaderboard). Es asíncrono: emite loaded con los datos o failed si
## el servidor no está, tarda demasiado o responde algo inválido. Si el nodo se
## libera antes de la respuesta (por ejemplo, al salir del menú), no emite nada.

## entries: Array de Dictionary con name, score, level y date (como en
## ScoreBoard, más el nombre del jugador). best_level: nivel más alto de las
## partidas normales terminadas.
signal loaded(entries: Array, best_level: int)
signal failed

var base_url := StatsServer.BASE_URL


func fetch(limit: int) -> void:
	var http := HTTPRequest.new()
	http.timeout = StatsServer.REQUEST_TIMEOUT
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(http))
	var url := "%s/api/leaderboard?limit=%d" % [base_url, limit]
	if http.request(url, StatsServer.JSON_HEADERS) != OK:
		http.queue_free()
		failed.emit()


## Convierte la respuesta del servidor. Devuelve null si el pedido falló o el
## cuerpo no tiene la forma esperada; si no, {"entries": [...], "best_level": n}.
static func parse_response(result: int, response_code: int, body: PackedByteArray) -> Variant:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return null
	# JSON.new().parse no llena el log de errores con una respuesta inválida.
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return null
	var data: Variant = json.data
	if not data is Dictionary or not data.get("entries") is Array:
		return null
	var entries := []
	for raw: Variant in data["entries"]:
		if not raw is Dictionary or not raw.get("player_name") is String \
				or not raw.get("score") is float or not raw.get("level_reached") is float:
			return null
		var ended_at: Variant = raw.get("ended_at")
		entries.append({
			"name": raw["player_name"],
			"score": int(raw["score"]),
			"level": int(raw["level_reached"]),
			"date": ended_at if ended_at is String else "",
		})
	var best_level: Variant = data.get("best_level", 0)
	return {"entries": entries, "best_level": int(best_level) if best_level is float else 0}


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()
	var board: Variant = parse_response(result, response_code, body)
	if board == null:
		failed.emit()
	else:
		loaded.emit(board["entries"], board["best_level"])
