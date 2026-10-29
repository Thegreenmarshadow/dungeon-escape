extends CanvasLayer
## Controles táctiles (Autoload "TouchControls", escena TouchControls.tscn):
## joystick flotante a la izquierda, botones de ataque, salto y parry abajo a
## la derecha (donde descansa el pulgar) y pausa arriba a la derecha. Solo
## aprietan acciones del Input Map, así el jugador lee lo mismo con teclado,
## mando o pantalla táctil, y el input buffering y el coyote time funcionan
## igual. Como GameFeel, encuentra al jugador al entrar al árbol.
##
## Se ven en partida (hay un jugador vivo y el juego no está en pausa ni en una
## pantalla final), según el modo de Ajustes (ControlSettings):
## - Auto: en un celular (DisplayServer.is_touchscreen_available()) siempre. En
##   una PC con pantalla táctil, que Godot no informa en Windows, desde el
##   primer toque real hasta que se usa el teclado o un mando.
## - Siempre: modo de depuración. En una PC sin pantalla táctil activa
##   Input.emulate_touch_from_mouse para probarlos con el mouse.
## - Nunca.
## preview los muestra sin jugador y en cualquier modo salvo Nunca: es la vista
## previa del menú de Ajustes.

## Posición del centro de cada botón respecto de su esquina y su diámetro, a
## tamaño 100 %. El tamaño de Ajustes multiplica ambos.
const ATTACK_POSITION := Vector2(-140.0, -140.0)
const ATTACK_DIAMETER := 132.0
const JUMP_POSITION := Vector2(-300.0, -100.0)
const JUMP_DIAMETER := 112.0
const PARRY_POSITION := Vector2(-115.0, -300.0)
const PARRY_DIAMETER := 100.0
## Pausa, desde la esquina de arriba a la derecha: a la izquierda del minimapa.
const PAUSE_POSITION := Vector2(-300.0, 64.0)
const PAUSE_DIAMETER := 96.0
## Radio del joystick a tamaño 100 %.
const JOYSTICK_RADIUS := 100.0
## Margen mínimo con los bordes aunque la zona segura sea toda la pantalla.
const EDGE_MARGIN := 8.0
## Inclinación de un stick a partir de la cual cuenta como usar el mando.
const JOYPAD_USE_THRESHOLD := 0.5

## Vista previa (menú de Ajustes): se ven sin jugador y el joystick no se mueve.
var preview := false:
	set(value):
		preview = value
		if is_node_ready():
			joystick.interactive = not value
## Ajustes en uso (ver ControlSettings.load_settings).
var settings: Dictionary = {}

# El jugador de la escena actual (null en los menús).
var _player: Node2D
# Auto en una PC con pantalla táctil: true desde un toque real hasta que se usa
# el teclado o el mando.
var _touch_seen := false
# true si este nodo encendió Input.emulate_touch_from_mouse (modo Siempre).
var _emulating_touch := false
# DisplayServer.is_touchscreen_available() al arrancar, antes de emular toques:
# con la emulación encendida esa función da true en cualquier PC.
var _native_touchscreen := false

@onready var safe_root: Control = %Safe
@onready var joystick: TouchJoystick = %Joystick
@onready var attack_button: TouchActionButton = %AttackButton
@onready var jump_button: TouchActionButton = %JumpButton
@onready var parry_button: TouchActionButton = %ParryButton
@onready var pause_button: TouchActionButton = %PauseButton


func _enter_tree() -> void:
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	# Sigue con el juego en pausa: así se oculta al pausar y vuelve al seguir.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_native_touchscreen = DisplayServer.is_touchscreen_available() and not Input.emulate_touch_from_mouse
	joystick.interactive = not preview
	get_viewport().size_changed.connect(_apply_safe_area)
	reload_settings()
	_apply_safe_area()
	visible = false


## Vuelve a leer los ajustes de controles y los aplica. Lo llama el menú de
## Ajustes al cambiar algo.
func reload_settings(path: String = ControlSettings.DEFAULT_PATH) -> void:
	apply_settings(ControlSettings.load_settings(path))


## Aplica unos ajustes (con el formato de ControlSettings.load_settings).
func apply_settings(new_settings: Dictionary) -> void:
	settings = new_settings
	var scale_factor: float = settings[ControlSettings.KEY_SCALE]
	var opacity: float = settings[ControlSettings.KEY_OPACITY]
	joystick.radius = JOYSTICK_RADIUS * scale_factor
	joystick.deadzone = settings[ControlSettings.KEY_DEADZONE]
	joystick.opacity = opacity
	_place(attack_button, ATTACK_POSITION, ATTACK_DIAMETER, scale_factor, opacity)
	_place(jump_button, JUMP_POSITION, JUMP_DIAMETER, scale_factor, opacity)
	_place(parry_button, PARRY_POSITION, PARRY_DIAMETER, scale_factor, opacity)
	_place(pause_button, PAUSE_POSITION, PAUSE_DIAMETER, scale_factor, opacity)
	Haptics.enabled = settings[ControlSettings.KEY_VIBRATION]
	_update_touch_emulation()


func touch_mode() -> ControlSettings.TouchMode:
	return settings.get(ControlSettings.KEY_TOUCH_MODE, ControlSettings.DEFAULT_TOUCH_MODE)


## true si hay que mostrar los controles ahora (ver la descripción del script).
func should_show() -> bool:
	var mode := touch_mode()
	if mode == ControlSettings.TouchMode.NEVER:
		return false
	if preview or mode == ControlSettings.TouchMode.ALWAYS:
		return preview or _in_gameplay()
	if not _in_gameplay():
		return false
	return _native_touchscreen or _touch_seen


func _in_gameplay() -> bool:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		return false
	# Muerto, el jugador deja de procesar física; las pantallas finales y la
	# pausa detienen el árbol.
	return _player.is_physics_processing() and not get_tree().paused


func _process(_delta: float) -> void:
	var show_now := should_show()
	if show_now != visible:
		visible = show_now
		if not show_now:
			release_all()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		# Los toques que Godot fabrica con el mouse no cuentan como pantalla táctil.
		if event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
			_touch_seen = true
	elif _touch_seen and not _native_touchscreen and _is_keyboard_or_joypad(event):
		_touch_seen = false


## Ancho que ocupan los controles a la izquierda (el joystick en reposo) y a la
## derecha (los botones de abajo), en píxeles de la vista, con un respiro de
## gap. El menú de Ajustes deja ese lugar libre para la vista previa.
func reserved_width(gap := 16.0) -> Vector2:
	var scale_factor: float = settings.get(ControlSettings.KEY_SCALE, ControlSettings.DEFAULT_SCALE)
	var left := safe_root.offset_left + joystick.radius * 2.0 + TouchJoystick.REST_MARGIN + gap
	var right := -safe_root.offset_right + (-JUMP_POSITION.x + JUMP_DIAMETER / 2.0) * scale_factor + gap
	return Vector2(left, right)


## Suelta todo lo que estén apretando el joystick y los botones (al ocultarse,
## así el personaje no sigue caminando con la pausa).
func release_all() -> void:
	joystick.release()
	for button: TouchActionButton in [attack_button, jump_button, parry_button, pause_button]:
		if button.is_pressed() and button.action != &"":
			Input.action_release(button.action)


static func _is_keyboard_or_joypad(event: InputEvent) -> bool:
	if event is InputEventKey or event is InputEventJoypadButton:
		return event.is_pressed() and not event.is_echo()
	if event is InputEventJoypadMotion:
		return absf(event.axis_value) >= JOYPAD_USE_THRESHOLD
	return false


func _place(button: TouchActionButton, corner_offset: Vector2, diameter: float, scale_factor: float, opacity: float) -> void:
	button.position = corner_offset * scale_factor
	button.diameter = diameter * scale_factor
	button.opacity = opacity


## Corre los controles dentro de la zona segura (notch y bordes redondeados).
func _apply_safe_area() -> void:
	var insets := SafeArea.insets(get_viewport())
	safe_root.offset_left = maxf(insets["left"], EDGE_MARGIN)
	safe_root.offset_top = maxf(insets["top"], EDGE_MARGIN)
	safe_root.offset_right = -maxf(insets["right"], EDGE_MARGIN)
	safe_root.offset_bottom = -maxf(insets["bottom"], EDGE_MARGIN)


## Modo Siempre en una PC sin pantalla táctil: el mouse fabrica toques para
## poder usar el joystick y los botones. No se activa en el proyecto porque
## entonces DisplayServer.is_touchscreen_available() daría true en toda PC.
func _update_touch_emulation() -> void:
	var want := touch_mode() == ControlSettings.TouchMode.ALWAYS and not _native_touchscreen
	if want and not Input.emulate_touch_from_mouse:
		Input.emulate_touch_from_mouse = true
		_emulating_touch = true
	elif not want and _emulating_touch:
		Input.emulate_touch_from_mouse = false
		_emulating_touch = false


func _on_node_added(node: Node) -> void:
	if node is CharacterBody2D and node.has_signal(&"buffered_action_used"):
		_player = node
