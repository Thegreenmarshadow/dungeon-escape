class_name TouchJoystick
extends Control
## Joystick virtual flotante para pantallas táctiles. El dedo que apoya dentro
## de este control (la parte izquierda de la pantalla, ver TouchControls) fija
## ahí el centro del joystick y, al arrastrar, mueve la perilla. Sin dedo se
## dibuja tenue en su lugar de reposo, abajo a la izquierda.
##
## El desplazamiento se convierte en las acciones del Input Map move_left,
## move_right, move_up y move_down con Input.action_press: el jugador las lee
## igual que el teclado o un mando y no sabe qué dispositivo lo mueve.
##
## Sigue un solo dedo (por su índice de toque), así los demás quedan libres para
## los botones (multitouch). Fuera de la zona muerta la dirección sale con
## fuerza completa: el caballero camina a una sola velocidad, como con teclado.

const ACTION_LEFT := &"move_left"
const ACTION_RIGHT := &"move_right"
const ACTION_UP := &"move_up"
const ACTION_DOWN := &"move_down"
## Separación entre el joystick en reposo y los bordes del control, en píxeles.
const REST_MARGIN := 28.0
## Radio de la perilla respecto del radio del joystick.
const KNOB_RATIO := 0.42
## Colores de la paleta del juego (el dorado de los títulos).
const COLOR_FILL := Color(0.07, 0.05, 0.1)
const COLOR_LINE := Color(1.0, 0.86, 0.5)

## Radio del círculo base, en píxeles de la vista. La perilla llega hasta él.
@export var radius: float = 100.0:
	set(value):
		radius = maxf(value, 1.0)
		queue_redraw()
## Fracción del radio (0 a 1) en la que el joystick todavía no mueve al
## personaje: evita que un pulgar apoyado sin querer lo haga caminar.
@export_range(0.0, 0.9, 0.01) var deadzone: float = 0.2:
	set(value):
		deadzone = clampf(value, 0.0, 0.9)
		queue_redraw()
## Opacidad de lo dibujado (0 a 1).
@export_range(0.0, 1.0, 0.05) var opacity: float = 0.55:
	set(value):
		opacity = clampf(value, 0.0, 1.0)
		queue_redraw()
## false: solo se dibuja, sin leer toques (la vista previa de Ajustes).
@export var interactive := true

# Índice del dedo que maneja el joystick; -1 = ninguno.
var _touch_index := -1
# Centro del joystick y desplazamiento de la perilla, en coordenadas locales.
var _center := Vector2.ZERO
var _knob := Vector2.ZERO
# Acciones que este joystick dejó apretadas; solo suelta esas, así no corta
# una tecla que el jugador mantiene a la vez.
var _pressed_actions: Dictionary[StringName, bool] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_center = rest_center()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()
	elif what == NOTIFICATION_EXIT_TREE:
		release()


func _input(event: InputEvent) -> void:
	if not interactive or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var local := _to_local(event.position)
		if event.pressed:
			if _touch_index == -1 and Rect2(Vector2.ZERO, size).has_point(local):
				begin_touch(event.index, local)
		elif event.index == _touch_index:
			release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		drag_to(_to_local(event.position))


## Empieza a seguir al dedo index, apoyado en at (coordenadas locales). El
## centro queda donde apoyó, corrido lo justo para que el círculo entre entero.
func begin_touch(index: int, at: Vector2) -> void:
	_touch_index = index
	var low := Vector2.ONE * radius
	var high := (size - Vector2.ONE * radius).max(low)
	_center = at.clamp(low, high)
	drag_to(at)


## Mueve la perilla hacia at (coordenadas locales), sin salirse del radio, y
## actualiza las acciones de movimiento.
func drag_to(at: Vector2) -> void:
	_knob = (at - _center).limit_length(radius)
	_apply(output())
	queue_redraw()


## Suelta el dedo: la perilla vuelve al centro, el joystick a su lugar de
## reposo y se sueltan las acciones que había apretado.
func release() -> void:
	_touch_index = -1
	_knob = Vector2.ZERO
	_center = rest_center()
	_apply(Vector2.ZERO)
	queue_redraw()


## true mientras un dedo maneja el joystick.
func is_active() -> bool:
	return _touch_index != -1


## Dirección que manda ahora el joystick (largo 0 o 1).
func output() -> Vector2:
	return compute_output(_knob, radius, deadzone)


## Dirección del joystick para un desplazamiento offset de la perilla: cero
## dentro de la zona muerta (deadzone, fracción de radius) y, fuera de ella, la
## dirección con largo 1.
static func compute_output(offset: Vector2, joystick_radius: float, dead: float) -> Vector2:
	if joystick_radius <= 0.0 or offset == Vector2.ZERO:
		return Vector2.ZERO
	if offset.length() / joystick_radius <= dead:
		return Vector2.ZERO
	return offset.normalized()


## Centro del joystick sin dedo: abajo a la izquierda del control.
func rest_center() -> Vector2:
	return Vector2(radius + REST_MARGIN, size.y - radius - REST_MARGIN)


func _apply(direction: Vector2) -> void:
	_set_axis(ACTION_LEFT, ACTION_RIGHT, direction.x)
	_set_axis(ACTION_UP, ACTION_DOWN, direction.y)


func _set_axis(negative: StringName, positive: StringName, value: float) -> void:
	_set_action(positive, maxf(value, 0.0))
	_set_action(negative, maxf(-value, 0.0))


func _set_action(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
		_pressed_actions[action] = true
	elif _pressed_actions.has(action):
		Input.action_release(action)
		_pressed_actions.erase(action)


func _to_local(viewport_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * viewport_position


func _on_resized() -> void:
	if not is_active():
		_center = rest_center()
	queue_redraw()


func _draw() -> void:
	# En reposo se ve más tenue: indica dónde está sin tapar el juego.
	var alpha := opacity if is_active() else opacity * 0.6
	draw_circle(_center, radius, Color(COLOR_FILL, alpha * 0.55))
	draw_arc(_center, radius, 0.0, TAU, 48, Color(COLOR_LINE, alpha), 3.0, true)
	if deadzone > 0.0:
		draw_arc(_center, radius * deadzone, 0.0, TAU, 32, Color(COLOR_LINE, alpha * 0.4), 2.0, true)
	draw_circle(_center + _knob, radius * KNOB_RATIO, Color(COLOR_LINE, alpha * 0.85))
