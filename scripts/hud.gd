extends CanvasLayer
## Interfaz del jugador: vidas, indicador de llave, enemigos eliminados, mensajes
## y pantallas de fin de partida. Solo muestra información; el nivel decide
## cuándo actualizarla.

## Se emite al pulsar el botón de la pantalla de fin de partida.
signal action_pressed

@onready var lives_label: Label = %LivesLabel
@onready var key_icon: TextureRect = %KeyIcon
@onready var kills_label: Label = %KillsLabel
@onready var message_label: Label = %MessageLabel
@onready var message_timer: Timer = %MessageTimer
@onready var end_screen: Control = %EndScreen
@onready var end_title: Label = %EndTitle
@onready var end_stats: Label = %EndStats
@onready var action_button: Button = %ActionButton


func _ready() -> void:
	end_screen.hide()
	message_label.hide()
	message_timer.timeout.connect(message_label.hide)
	action_button.pressed.connect(action_pressed.emit)
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
