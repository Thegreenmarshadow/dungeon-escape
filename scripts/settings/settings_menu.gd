extends Control
## Pantalla de ajustes (se abre desde el menú principal). Por ahora solo la
## telemetría: encendida (por defecto) guarda en este equipo el recorrido y lo
## que pasa en cada nivel; apagada no se registra nada. Se guarda al cambiarla.

@onready var telemetry_toggle: CheckButton = %TelemetryToggle
@onready var back_button: Button = %BackButton


func _ready() -> void:
	telemetry_toggle.button_pressed = GameSettings.telemetry_enabled()
	telemetry_toggle.toggled.connect(func(enabled: bool) -> void: GameSettings.set_telemetry_enabled(enabled))
	back_button.pressed.connect(Game.go_to_menu)
	telemetry_toggle.grab_focus()
