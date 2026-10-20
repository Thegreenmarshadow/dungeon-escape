class_name DemoEndScreen
extends CanvasLayer
## Pantalla final de la demo: agradece, resume la partida (tiempo y enemigos
## derrotados) e invita al juego completo. Tiene tres botones: abrir la página
## de descarga (OS.shell_open), jugar la demo otra vez y volver al menú. Sigue
## el estilo de las pantallas finales de la HUD (fondo oscuro, título grande).
##
## Funciona con el árbol en pausa (process_mode Always), como la HUD.

signal replay_pressed
signal menu_pressed

const FULL_GAME_URL := "https://github.com/Thegreenmarshadow/dungeon-escape/releases/latest"
const TITLE := "¡Gracias por jugar!"
const PITCH := "En el juego completo te esperan niveles sin fin,\nuna tienda y más jefes."
const FADE_TIME := 0.5
## Por encima de la HUD y del menú de pausa.
const LAYER := 70

var title_label: Label
var stats_label: Label
var download_button: Button
var replay_button: Button
var menu_button: Button


func _init() -> void:
	name = "DemoEndScreen"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## Tiempo en minutos y segundos (5:07).
static func format_time(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	return "%d:%02d" % [total / 60, total % 60]


## Muestra el resumen y aparece con un fundido. El foco queda en descargar.
func show_summary(run_time: float, enemies_defeated: int) -> void:
	stats_label.text = "Tiempo: %s · Enemigos derrotados: %d" % [format_time(run_time), enemies_defeated]
	var root := get_child(0) as Control
	root.modulate.a = 0.0
	visible = true
	download_button.grab_focus()
	create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) \
			.tween_property(root, "modulate:a", 1.0, FADE_TIME)


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 0.8)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	background.add_child(box)

	title_label = _add_label(box, TITLE, 56, Color(1, 0.86, 0.5))
	stats_label = _add_label(box, "", 28, Color.WHITE)
	_add_label(box, PITCH, 22, Color(0.8, 0.75, 0.85))
	_add_label(box, FULL_GAME_URL, 14, Color(0.8, 0.75, 0.65, 0.7))

	download_button = _add_button(box, "Descargar el juego completo")
	download_button.pressed.connect(open_full_game_page)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	replay_button = _add_button(row, "Jugar otra vez")
	replay_button.pressed.connect(_choose.bind(replay_pressed))
	menu_button = _add_button(row, "Menú")
	menu_button.pressed.connect(_choose.bind(menu_pressed))


func open_full_game_page() -> void:
	OS.shell_open(FULL_GAME_URL)


## Desactiva los botones que cambian de escena antes de avisar, así un segundo
## clic en el mismo cuadro no dispara otra acción.
func _choose(choice: Signal) -> void:
	replay_button.disabled = true
	menu_button.disabled = true
	choice.emit()


func _add_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _add_button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 24)
	parent.add_child(button)
	return button
