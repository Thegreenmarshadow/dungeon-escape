extends CanvasLayer
## Interfaz del jugador: vidas, indicador de llave, enemigos eliminados, mensajes
## y pantallas de fin de partida. Solo muestra información; el nivel decide
## cuándo actualizarla.

## Se emite cuando el jugador pide reiniciar desde una pantalla de fin de partida.
signal restart_requested

@onready var lives_label: Label = %LivesLabel
@onready var key_icon: TextureRect = %KeyIcon
@onready var kills_label: Label = %KillsLabel
@onready var message_label: Label = %MessageLabel
@onready var message_timer: Timer = %MessageTimer
@onready var end_screen: Control = %EndScreen
@onready var end_title: Label = %EndTitle
@onready var end_stats: Label = %EndStats


func _ready() -> void:
	end_screen.hide()
	message_label.hide()
	message_timer.timeout.connect(message_label.hide)
	set_has_key(false)


func _unhandled_input(event: InputEvent) -> void:
	# Solo se puede reiniciar cuando hay una pantalla de fin de partida visible.
	if end_screen.visible and event.is_action_pressed("restart"):
		restart_requested.emit()


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
## debajo del título (por ejemplo, las estadísticas de la partida).
func show_end_screen(title: String, details: String = "") -> void:
	message_label.hide()
	end_title.text = title
	end_stats.text = details
	end_stats.visible = not details.is_empty()
	end_screen.show()
