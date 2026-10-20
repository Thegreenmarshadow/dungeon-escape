class_name DifficultyProbe
extends Node
## Sonda del modo prueba. El nivel la agrega solo cuando Game.test_mode está
## activo; no cambia nada del juego, solo escucha señales que ya existen:
##   - Player.lives_changed: daño recibido (vidas perdidas) y curaciones.
##   - Player.died y Door.player_escaped: fin del nivel y resultado.
##   - EnemyBase.died: enemigos eliminados.
##   - EnemyBase.dodged: golpes esquivados (solo en la superposición).
##   - Player.damaged: daño por fuente y causa de la muerte (columnas medidas).
## Muestra una superposición con los parámetros del nivel, su índice de
## dificultad y las métricas en vivo, y al terminar el nivel agrega una fila a
## PLAYTEST_CSV_PATH.
##
## Columnas medidas (agregadas al final para no romper los archivos ya
## acumulados; un archivo con el encabezado viejo se completa con celdas
## vacías al escribir la primera fila nueva):
##   damage_per_min  vidas perdidas por minuto jugado (como LevelStats)
##   damage_sources  daño por fuente, "fuente:cantidad" separados por ";"
##   death_cause     fuente del último daño si el resultado es died

## Archivo donde se acumulan las partidas de prueba (una fila por nivel jugado).
const PLAYTEST_CSV_PATH := "user://difficulty_playtest.csv"
const CSV_HEADER := [
	"date", "run_seed", "level", "index", "enemies", "bosses", "hazards",
	"seconds", "lives_lost", "hearts_healed", "kills", "enemies_total", "outcome",
	"damage_per_min", "damage_sources", "death_cause",
]
const OUTCOME_ESCAPED := "escaped"
const OUTCOME_DIED := "died"
## El nivel se cerró sin terminar (por ejemplo, al cerrar el juego).
const OUTCOME_ABANDONED := "abandoned"
## Capa de la superposición: por encima de la HUD.
const OVERLAY_LAYER := 50

var _level := 0
var _params: LevelGenerator.Params
var _index := 0.0
var _seconds := 0.0
var _lives := 0
var _lives_lost := 0
var _hearts_healed := 0
var _kills := 0
var _dodges := 0
var _enemies_total := 0
var _damage_by_source := {}
var _death_cause := ""
var _player: Node
var _finished := false
var _label: Label


func _ready() -> void:
	# Se guarda el nivel ahora: al escapar, Game.complete_level lo avanza antes
	# de que esta sonda reciba la señal.
	_level = Game.current_level
	_params = LevelGenerator.params_for_level(_level)
	_index = DifficultyCurve.index_for(_params)

	var level := get_parent()
	var player: Node = level.get_node("Player")
	_player = player
	_lives = player.lives
	player.lives_changed.connect(_on_lives_changed)
	player.damaged.connect(_on_player_damaged)
	player.died.connect(_on_player_died)
	level.get_node("ExitDoor").player_escaped.connect(_finish.bind(OUTCOME_ESCAPED))
	var enemies := get_tree().get_nodes_in_group("enemies")
	_enemies_total = enemies.size()
	for enemy in enemies:
		enemy.died.connect(_on_enemy_died)
		enemy.dodged.connect(_on_enemy_dodged)

	_build_overlay()
	_update_overlay()


## Con el árbol en pausa (pantallas finales) no corre, así el tiempo solo
## cuenta mientras se juega.
func _process(delta: float) -> void:
	if _finished:
		return
	_seconds += delta
	_update_overlay()


func _exit_tree() -> void:
	if not _finished:
		_finish(OUTCOME_ABANDONED)


func _on_lives_changed(lives: int) -> void:
	if lives < _lives:
		_lives_lost += _lives - lives
	elif lives > _lives:
		_hearts_healed += lives - _lives
	_lives = lives
	_update_overlay()


func _on_player_damaged(amount: int, source: StringName) -> void:
	var key := LevelStats.source_name(source)
	_damage_by_source[key] = _damage_by_source.get(key, 0) + amount


func _on_player_died() -> void:
	if is_instance_valid(_player):
		_death_cause = LevelStats.source_name(_player.last_damage_source)
	_finish(OUTCOME_DIED)


func _on_enemy_died(_enemy: EnemyBase) -> void:
	_kills += 1
	_update_overlay()


func _on_enemy_dodged(_enemy: EnemyBase) -> void:
	_dodges += 1
	_update_overlay()


func _finish(outcome: String) -> void:
	if _finished:
		return
	_finished = true
	_update_overlay(outcome)
	var error := _append_row(outcome)
	if error != OK:
		push_warning("DifficultyProbe: no se pudo escribir %s (error %d)" % [PLAYTEST_CSV_PATH, error])


func _append_row(outcome: String) -> Error:
	var sources := PackedStringArray()
	var keys := _damage_by_source.keys()
	keys.sort()
	for source: String in keys:
		sources.append("%s:%d" % [source, _damage_by_source[source]])
	var damage_per_min := _lives_lost / (_seconds / 60.0) if _seconds > 0.0 else 0.0
	return append_playtest_row(PLAYTEST_CSV_PATH, PackedStringArray([
		Time.get_datetime_string_from_system(), str(Game.run_seed), str(_level),
		"%.3f" % _index, str(_params.enemy_count), str(_params.boss_count),
		str(_params.hazard_count), "%.1f" % _seconds, str(_lives_lost),
		str(_hearts_healed), str(_kills), str(_enemies_total), outcome,
		"%.3f" % damage_per_min, ";".join(sources),
		_death_cause if outcome == OUTCOME_DIED else "",
	]))


## Agrega una fila al CSV de partidas de prueba. Si el archivo no existe lo
## crea con CSV_HEADER; si tiene un encabezado viejo (menos columnas) lo
## reescribe con el encabezado actual y completa las filas viejas con celdas
## vacías, así todas las filas tienen las mismas columnas.
static func append_playtest_row(path: String, row: PackedStringArray) -> Error:
	if FileAccess.file_exists(path):
		var error := _upgrade_header(path)
		if error != OK:
			return error
	var is_new := not FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.WRITE if is_new else FileAccess.READ_WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if is_new:
		file.store_csv_line(PackedStringArray(CSV_HEADER))
	file.seek_end()
	file.store_csv_line(row)
	return OK


static func _upgrade_header(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var rows: Array[PackedStringArray] = []
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() == 1 and line[0].is_empty():
			continue
		rows.append(line)
	file.close()
	# Solo se completa un encabezado viejo de este mismo formato (prefijo del
	# actual); cualquier otro archivo se deja como está.
	var header := PackedStringArray(CSV_HEADER)
	if rows.is_empty() or rows[0].size() >= header.size() or rows[0] != header.slice(0, rows[0].size()):
		return OK
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_csv_line(PackedStringArray(CSV_HEADER))
	for i in range(1, rows.size()):
		var row := rows[i]
		while row.size() < CSV_HEADER.size():
			row.append("")
		file.store_csv_line(row)
	return OK


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = OVERLAY_LAYER
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -12.0
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	panel.add_child(_label)


func _update_overlay(outcome: String = "") -> void:
	if _label == null:
		return
	var p := _params
	var lines := PackedStringArray([
		"MODO PRUEBA · nivel %d · índice %.1f" % [_level, _index],
		"Enemigos %d (perseguidores %d, calaveras %d) · jefes %d · trampas %d · vida ×%.1f" % [
			p.enemy_count, LevelGenerator.chaser_count(p), p.skull_count, p.boss_count, p.hazard_count,
			p.enemy_health_scale],
		"Grilla %dx%d · salas %d" % [p.grid_size.x, p.grid_size.y, p.room_count],
		"Tiempo %.1f s · vidas perdidas %d · eliminados %d/%d · esquivas %d" % [
			_seconds, _lives_lost, _kills, _enemies_total, _dodges],
	])
	if not outcome.is_empty():
		lines.append("Resultado: %s (guardado en %s)" % [outcome, PLAYTEST_CSV_PATH])
	_label.text = "\n".join(lines)
