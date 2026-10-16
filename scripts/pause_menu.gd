extends CanvasLayer
## Menú de pausa del nivel. La acción "pause" (Escape) lo abre y lo cierra;
## ofrece continuar o volver al menú principal. La lógica de cuándo puede
## abrirse vive en PauseController; esta escena solo la muestra.
##
## Tiene process_mode = Always (en la escena) para recibir teclas con el árbol
## en pausa, y la capa 60 para quedar por encima de la HUD y de la sonda del
## modo prueba. Escucha el fin del nivel (Player.died y Door.player_escaped)
## para no abrirse sobre las pantallas finales.

@onready var pause_screen: Control = %PauseScreen
@onready var continue_button: Button = %ContinueButton
@onready var back_to_menu_button: Button = %BackToMenuButton

var controller: PauseController


func _ready() -> void:
	controller = PauseController.new(get_tree())
	pause_screen.hide()
	continue_button.pressed.connect(_resume)
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	var level := get_parent()
	level.get_node("Player").died.connect(_on_level_ended)
	level.get_node("ExitDoor").player_escaped.connect(_on_level_ended)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if controller.is_open():
		_resume()
	elif controller.open():
		_show()
	else:
		return
	get_viewport().set_input_as_handled()


func _show() -> void:
	_set_buttons_enabled(true)
	pause_screen.show()
	# Con el foco en Continuar se navega con las flechas y se elige con Enter.
	continue_button.grab_focus()


func _resume() -> void:
	controller.resume()
	pause_screen.hide()


## Desactiva los botones antes de cambiar de escena, así una segunda tecla en
## el mismo cuadro no dispara otra acción. Game.go_to_menu quita la pausa.
func _on_back_to_menu_pressed() -> void:
	_set_buttons_enabled(false)
	Game.go_to_menu()


func _on_level_ended() -> void:
	controller.mark_level_ended()
	pause_screen.hide()


func _set_buttons_enabled(enabled: bool) -> void:
	continue_button.disabled = not enabled
	back_to_menu_button.disabled = not enabled
