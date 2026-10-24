extends Control
## Pantalla de inicio: primera escena del juego.

const MENU_MUSIC := preload("res://assets/music/dungeon_yd.ogg")
## Segundos que tarda en aparecer el menú.
const FADE_IN_TIME := 0.8
## Cuántos puntajes de la tabla se muestran en el menú.
const SHOWN_SCORES := 5
## Informe de patrones de la telemetría (herramienta del equipo).
const ANALYTICS_REPORT_SCENE := "res://scenes/AnalyticsReport.tscn"

@onready var play_button: Button = %PlayButton
@onready var demo_button: Button = %DemoButton
@onready var test_mode_button: Button = %TestModeButton
@onready var analytics_button: Button = %AnalyticsButton
@onready var sandbox_button: Button = %SandboxButton
@onready var quit_button: Button = %QuitButton
@onready var title: Label = %Title
@onready var best_level_label: Label = %BestLevelLabel
@onready var scores_grid: GridContainer = %ScoresGrid
@onready var no_scores_label: Label = %NoScoresLabel
@onready var last_column_header: Label = %DateHeader
@onready var scores_source_label: Label = %ScoresSourceLabel
@onready var continue_button: Button = %ContinueButton
@onready var settings_button: Button = %SettingsButton
@onready var profile_label: Label = %ProfileLabel
@onready var profile_button: Button = %ProfileButton


func _ready() -> void:
	Music.play_track(MENU_MUSIC)
	play_button.pressed.connect(Game.start_new_game)
	# La demo está en todas las builds: es para quien todavía no conoce el juego.
	demo_button.pressed.connect(Game.start_demo)
	test_mode_button.pressed.connect(Game.go_to_difficulty_report)
	# El informe de analítica es para el equipo, no para quien juega: igual
	# que la zona de pruebas, solo en el editor y en builds de depuración.
	analytics_button.visible = OS.is_debug_build()
	analytics_button.pressed.connect(func() -> void: get_tree().change_scene_to_file(ANALYTICS_REPORT_SCENE))
	# La zona de pruebas es una herramienta de desarrollo: solo en el editor y
	# en builds de depuración, nunca en la versión publicada.
	sandbox_button.visible = OS.is_debug_build()
	sandbox_button.pressed.connect(Game.go_to_sandbox)
	quit_button.pressed.connect(get_tree().quit)
	continue_button.pressed.connect(Profiles.continue_saved_game)
	settings_button.pressed.connect(Game.go_to_settings)
	profile_button.pressed.connect(Game.go_to_profile_select)
	_show_profile()
	# Con el foco en "Continuar" (o en "Jugar" si no hay partida guardada) el
	# menú también se maneja con el teclado.
	if continue_button.disabled:
		play_button.grab_focus()
	else:
		continue_button.grab_focus()
	_show_scores()
	_fetch_online_scores()
	_fade_in()
	_pulse_title()
	_flicker_flames()


## Llena el panel de puntajes con el nivel máximo y los mejores puntajes
## guardados en este equipo. Sin puntajes muestra un mensaje en lugar de la
## tabla. Es lo que se ve mientras llega (o si no llega) la tabla en línea.
func _show_scores() -> void:
	var board := ScoreBoard.load_board()
	var rows: Array[PackedStringArray] = []
	for entry: Dictionary in board["entries"]:
		rows.append(PackedStringArray([str(entry["score"]), str(entry["level"]),
				ScoreBoard.display_date(entry)]))
	_fill_scores(rows, board["best_level"], "Fecha", "Fuente: local")


## Pide la tabla al servidor de estadísticas. Si responde, reemplaza a la
## local; si falla o tarda demasiado, queda la local.
func _fetch_online_scores() -> void:
	var online := OnlineLeaderboard.new()
	add_child(online)
	online.loaded.connect(_show_online_scores)
	online.fetch(SHOWN_SCORES)


func _show_online_scores(entries: Array, best_level: int) -> void:
	var rows: Array[PackedStringArray] = []
	for entry: Dictionary in entries:
		rows.append(PackedStringArray([str(entry["score"]), str(entry["level"]), entry["name"]]))
	_fill_scores(rows, best_level, "Jugador", "Fuente: en línea")


## rows: puntos, nivel y el texto de la última columna (fecha o jugador), de
## mejor a peor.
func _fill_scores(rows: Array[PackedStringArray], best_level: int, last_column: String, source: String) -> void:
	best_level_label.text = "Nivel máximo: %d" % best_level
	best_level_label.visible = best_level > 0
	last_column_header.text = last_column
	scores_source_label.text = source

	# La grilla trae la fila de encabezados; se quitan las filas anteriores.
	for i in range(scores_grid.get_child_count() - 1, scores_grid.columns - 1, -1):
		var cell := scores_grid.get_child(i)
		scores_grid.remove_child(cell)
		cell.queue_free()
	scores_grid.visible = not rows.is_empty()
	no_scores_label.visible = rows.is_empty()
	for i in mini(rows.size(), SHOWN_SCORES):
		var row := rows[i]
		_add_score_cell("#%d" % (i + 1))
		_add_score_cell(row[0], HORIZONTAL_ALIGNMENT_RIGHT)
		_add_score_cell(row[1], HORIZONTAL_ALIGNMENT_RIGHT)
		_add_score_cell(row[2])


## Perfil elegido (lo crea si todavía no hay ninguno), su tiempo jugado y si
## tiene una partida para continuar.
func _show_profile() -> void:
	var profile := Profiles.ensure_profile()
	profile_label.text = "Perfil: %s · %s" % [profile["name"],
			ProfileStore.format_duration(profile["total_time_s"])]
	var save: Dictionary = profile["save"]
	continue_button.disabled = save.is_empty()
	# Sin partida guardada no se muestra: un botón gris solo suma ruido.
	continue_button.visible = not save.is_empty()
	continue_button.tooltip_text = "Seguir la partida guardada de este perfil" if save.is_empty() \
			else "Seguir desde el nivel %d" % save["level"]


func _add_score_cell(text: String, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var cell := Label.new()
	cell.text = text
	cell.horizontal_alignment = alignment
	scores_grid.add_child(cell)


func _fade_in() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_IN_TIME)


func _pulse_title() -> void:
	# El contenedor fija el tamaño después de _ready, por eso el pivote se
	# recalcula cada vez que el título cambia de tamaño.
	title.resized.connect(func() -> void: title.pivot_offset = title.size / 2.0)
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(title, "scale", Vector2(1.03, 1.03), 1.6)
	tween.tween_property(title, "scale", Vector2.ONE, 1.6)


func _flicker_flames() -> void:
	# Cada resplandor de antorcha parpadea a su propio ritmo.
	for glow: Node in get_tree().get_nodes_in_group("flame_glow"):
		var tween := glow.create_tween().set_loops()
		tween.tween_property(glow, "modulate:a", randf_range(0.55, 0.8), randf_range(0.15, 0.3))
		tween.tween_property(glow, "modulate:a", 1.0, randf_range(0.15, 0.3))
