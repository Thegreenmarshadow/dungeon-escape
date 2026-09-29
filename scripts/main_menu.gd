extends Control
## Pantalla de inicio: primera escena del juego.

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton


func _ready() -> void:
	play_button.pressed.connect(Game.start_new_game)
	quit_button.pressed.connect(get_tree().quit)
	# Con el foco en "Jugar" el menú también se maneja con el teclado.
	play_button.grab_focus()
