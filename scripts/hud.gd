extends CanvasLayer
## Interfaz del jugador: vidas, indicador de llave, enemigos eliminados, mensajes
## y pantallas de fin de partida. Solo muestra información; el nivel decide
## cuándo actualizarla.

## Se emite al pulsar el botón de la pantalla de fin de partida.
signal action_pressed
## Se emiten al elegir una opción en la pantalla de Game Over. Cada vez que se
## muestra la pantalla se emite como mucho una de las dos.
signal retry_pressed
signal menu_pressed

## Duración del fundido de entrada de la pantalla de Game Over, en segundos.
const GAME_OVER_FADE_TIME := 0.5

@onready var lives_label: Label = %LivesLabel
@onready var key_icon: TextureRect = %KeyIcon
@onready var kills_label: Label = %KillsLabel
@onready var message_label: Label = %MessageLabel
@onready var message_timer: Timer = %MessageTimer
@onready var end_screen: Control = %EndScreen
@onready var end_title: Label = %EndTitle
@onready var end_stats: Label = %EndStats
@onready var action_button: Button = %ActionButton
@onready var game_over_screen: Control = %GameOverScreen
@onready var new_record_label: Label = %NewRecordLabel
@onready var record_label: Label = %RecordLabel
@onready var breakdown_label: Label = %BreakdownLabel
@onready var retry_button: Button = %RetryButton
@onready var back_to_menu_button: Button = %BackToMenuButton

var _game_over_tween: Tween


func _ready() -> void:
	end_screen.hide()
	game_over_screen.hide()
	message_label.hide()
	message_timer.timeout.connect(message_label.hide)
	action_button.pressed.connect(action_pressed.emit)
	retry_button.pressed.connect(_on_game_over_choice.bind(retry_pressed))
	back_to_menu_button.pressed.connect(_on_game_over_choice.bind(menu_pressed))
	set_has_key(false)


func set_lives(lives: int) -> void:
	lives_label.text = "Vidas: %d" % lives


## Muestra la llave opaca si el jugador la tiene y apagada si no.
func set_has_key(has_key: bool) -> void:
	key_icon.modulate = Color.WHITE if has_key else Color(1, 1, 1, 0.25)


func set_kills(killed: int, total: int) -> void:
	kills_label.text = "Enemigos: %d/%d" % [killed, total]


## Muestra un mensaje temporal en la parte inferior de la pantalla.
func show_message(text: String) -> void:
	message_label.text = text
	message_label.show()
	message_timer.start()


## Muestra la pantalla de fin de partida. details es una línea opcional
## debajo del título (por ejemplo, las estadísticas de la partida) y
## action_text es el texto del botón, que emite action_pressed.
func show_end_screen(title: String, details: String, action_text: String) -> void:
	message_label.hide()
	end_title.text = title
	end_stats.text = details
	end_stats.visible = not details.is_empty()
	action_button.text = action_text
	end_screen.show()
	# Con el foco en el botón se puede continuar con Enter o Espacio.
	action_button.grab_focus()


## Muestra la pantalla de Game Over con el resumen de la partida y un fundido
## de entrada. Si is_new_record es true se destaca el récord nuevo; si no, se
## muestra record_text (puesto y récord), que puede estar vacío. Los botones
## emiten retry_pressed o menu_pressed.
func show_game_over(level: int, kills: int, score: int, is_new_record: bool, record_text: String) -> void:
	message_label.hide()
	new_record_label.visible = is_new_record
	record_label.text = record_text
	record_label.visible = not is_new_record and not record_text.is_empty()
	breakdown_label.text = "Nivel alcanzado: %d\nEnemigos eliminados: %d\nPuntos: %d" % [
		level, kills, score]
	_set_game_over_buttons_enabled(true)

	game_over_screen.modulate.a = 0.0
	game_over_screen.show()
	retry_button.grab_focus()

	# El nivel pausa el árbol al mostrar esta pantalla: el tween debe seguir
	# corriendo en pausa (la HUD además tiene process_mode = Always).
	if _game_over_tween:
		_game_over_tween.kill()
	_game_over_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_game_over_tween.tween_property(game_over_screen, "modulate:a", 1.0, GAME_OVER_FADE_TIME)


## Desactiva los dos botones antes de emitir la elección, así un segundo clic
## o tecla (el cambio de escena ocurre recién al final del frame) no dispara
## otra acción.
func _on_game_over_choice(choice: Signal) -> void:
	_set_game_over_buttons_enabled(false)
	choice.emit()


func _set_game_over_buttons_enabled(enabled: bool) -> void:
	retry_button.disabled = not enabled
	back_to_menu_button.disabled = not enabled
