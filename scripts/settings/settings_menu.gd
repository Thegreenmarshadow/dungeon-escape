extends Control
## Pantalla de ajustes (se abre desde el menú principal):
## - Telemetría: encendida (por defecto) guarda en este equipo el recorrido y lo
##   que pasa en cada nivel; apagada no se registra nada.
## - Controles táctiles (ControlSettings): cuándo se ven, opacidad, tamaño, zona
##   muerta del joystick y vibración. Mientras está abierta se ve una vista
##   previa de los controles con los valores elegidos.
## Cada cambio se guarda en el acto.

## Texto de cada modo de ControlSettings.TouchMode, en su orden.
const MODE_TEXTS: Array[String] = ["Auto (pantalla táctil)", "Siempre (depuración)", "Nunca"]
const MODE_HINTS: Array[String] = [
	"Auto: en el celular siempre; en una PC con pantalla táctil, al tocarla (el teclado o el mando los ocultan).",
	"Siempre: también en PC; sin pantalla táctil se usan con el mouse.",
	"Nunca: solo teclado y mando.",
]

@onready var telemetry_toggle: CheckButton = %TelemetryToggle
@onready var touch_mode_option: OptionButton = %TouchModeOption
@onready var opacity_slider: HSlider = %OpacitySlider
@onready var opacity_value: Label = %OpacityValue
@onready var size_slider: HSlider = %SizeSlider
@onready var size_value: Label = %SizeValue
@onready var deadzone_slider: HSlider = %DeadzoneSlider
@onready var deadzone_value: Label = %DeadzoneValue
@onready var vibration_toggle: CheckButton = %VibrationToggle
@onready var controls_hint: Label = %ControlsHint
@onready var back_button: Button = %BackButton
@onready var center: Control = $Center
@onready var content: Control = $Center/VBox


func _ready() -> void:
	telemetry_toggle.button_pressed = GameSettings.telemetry_enabled()
	telemetry_toggle.toggled.connect(func(enabled: bool) -> void: GameSettings.set_telemetry_enabled(enabled))
	_setup_controls(ControlSettings.load_settings())
	back_button.pressed.connect(Game.go_to_menu)
	telemetry_toggle.grab_focus()
	var touch_controls := _touch_controls()
	if touch_controls != null:
		touch_controls.preview = true
	get_viewport().size_changed.connect(_fit_beside_preview)
	_fit_beside_preview()


func _exit_tree() -> void:
	var touch_controls := _touch_controls()
	if touch_controls != null:
		touch_controls.preview = false


func _setup_controls(settings: Dictionary) -> void:
	for text in MODE_TEXTS:
		touch_mode_option.add_item(text)
	touch_mode_option.select(settings[ControlSettings.KEY_TOUCH_MODE])
	touch_mode_option.item_selected.connect(_on_touch_mode_selected)
	_setup_slider(opacity_slider, ControlSettings.OPACITY_MIN, ControlSettings.OPACITY_MAX,
			settings[ControlSettings.KEY_OPACITY], ControlSettings.KEY_OPACITY)
	_setup_slider(size_slider, ControlSettings.SCALE_MIN, ControlSettings.SCALE_MAX,
			settings[ControlSettings.KEY_SCALE], ControlSettings.KEY_SCALE)
	_setup_slider(deadzone_slider, ControlSettings.DEADZONE_MIN, ControlSettings.DEADZONE_MAX,
			settings[ControlSettings.KEY_DEADZONE], ControlSettings.KEY_DEADZONE)
	vibration_toggle.button_pressed = settings[ControlSettings.KEY_VIBRATION]
	vibration_toggle.toggled.connect(_on_vibration_toggled)
	_update_labels()


func _setup_slider(slider: HSlider, low: float, high: float, value: float, key: String) -> void:
	slider.min_value = low
	slider.max_value = high
	slider.value = value
	slider.value_changed.connect(func(new_value: float) -> void: _save(key, new_value))


func _on_touch_mode_selected(index: int) -> void:
	_save(ControlSettings.KEY_TOUCH_MODE, index)


func _on_vibration_toggled(enabled: bool) -> void:
	_save(ControlSettings.KEY_VIBRATION, enabled)
	# Al encenderla, una vibración corta de muestra.
	if enabled:
		Haptics.vibrate(Haptics.PICKUP_MS)


func _save(key: String, value: Variant) -> void:
	ControlSettings.save_value(key, value)
	var touch_controls := _touch_controls()
	if touch_controls != null:
		touch_controls.reload_settings()
	else:
		Haptics.enabled = vibration_toggle.button_pressed
	_update_labels()
	_fit_beside_preview()


## Con la vista previa de los controles a la vista, corre el contenido al
## espacio libre entre el joystick y los botones. Si no entra (controles muy
## grandes o pantalla angosta), lo deja centrado.
func _fit_beside_preview() -> void:
	var touch_controls := _touch_controls()
	var reserved := Vector2.ZERO
	if touch_controls != null and touch_controls.should_show():
		reserved = touch_controls.reserved_width()
		var free_width := get_viewport_rect().size.x - reserved.x - reserved.y
		if free_width < content.get_combined_minimum_size().x:
			reserved = Vector2.ZERO
	center.offset_left = reserved.x
	center.offset_right = -reserved.y


func _update_labels() -> void:
	opacity_value.text = "%d %%" % roundi(opacity_slider.value * 100.0)
	size_value.text = "%d %%" % roundi(size_slider.value * 100.0)
	deadzone_value.text = "%.2f" % deadzone_slider.value
	controls_hint.text = MODE_HINTS[touch_mode_option.selected]


func _touch_controls() -> Node:
	return get_node_or_null(^"/root/TouchControls")
