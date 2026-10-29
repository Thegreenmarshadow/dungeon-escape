@tool
extends McpTestSuite
## Pruebas del joystick virtual: zona muerta, dirección, acciones del Input Map
## que aprieta y suelta, y que sigue a un solo dedo (multitouch).

const JOYSTICK_SCRIPT := preload("res://scripts/input/touch_joystick.gd")
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]


func suite_name() -> String:
	return "touch_joystick"


func teardown() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)


func test_inside_deadzone_gives_no_direction() -> void:
	assert_eq(TouchJoystick.compute_output(Vector2(15, 0), 100.0, 0.2), Vector2.ZERO)
	assert_eq(TouchJoystick.compute_output(Vector2(0, -20), 100.0, 0.2), Vector2.ZERO, "el borde de la zona muerta todavía no mueve")
	assert_eq(TouchJoystick.compute_output(Vector2.ZERO, 100.0, 0.0), Vector2.ZERO)


func test_outside_deadzone_gives_full_direction() -> void:
	var output := TouchJoystick.compute_output(Vector2(30, 0), 100.0, 0.2)
	assert_eq(output, Vector2.RIGHT, "fuera de la zona muerta sale con fuerza completa")
	var diagonal := TouchJoystick.compute_output(Vector2(-50, 50), 100.0, 0.2)
	assert_true(diagonal.is_equal_approx(Vector2(-1, 1).normalized()))


func test_larger_deadzone_ignores_more() -> void:
	assert_eq(TouchJoystick.compute_output(Vector2(30, 0), 100.0, 0.4), Vector2.ZERO)
	assert_eq(TouchJoystick.compute_output(Vector2(45, 0), 100.0, 0.4), Vector2.RIGHT)


func test_drag_presses_move_actions() -> void:
	var joystick := _make_joystick()
	joystick.begin_touch(0, Vector2(200, 200))
	joystick.drag_to(Vector2(260, 200))
	assert_true(Input.is_action_pressed(&"move_right"))
	assert_false(Input.is_action_pressed(&"move_left"))
	var direction := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	assert_true(direction.x > 0.9, "el jugador lee la acción como con el teclado")
	joystick.drag_to(Vector2(200, 140))
	assert_false(Input.is_action_pressed(&"move_right"), "al cambiar de dirección suelta la anterior")
	assert_true(Input.is_action_pressed(&"move_up"))


func test_release_lets_go_of_actions() -> void:
	var joystick := _make_joystick()
	joystick.begin_touch(0, Vector2(200, 200))
	joystick.drag_to(Vector2(140, 260))
	assert_true(Input.is_action_pressed(&"move_left"))
	assert_true(Input.is_action_pressed(&"move_down"))
	joystick.release()
	for action in MOVE_ACTIONS:
		assert_false(Input.is_action_pressed(action), "%s queda suelta" % action)
	assert_false(joystick.is_active())


func test_does_not_release_a_key_it_did_not_press() -> void:
	var joystick := _make_joystick()
	Input.action_press(&"move_up")
	joystick.begin_touch(0, Vector2(200, 200))
	joystick.drag_to(Vector2(260, 200))
	joystick.release()
	assert_true(Input.is_action_pressed(&"move_up"), "una tecla mantenida sigue apretada")


func test_follows_only_its_finger() -> void:
	var joystick := _make_joystick()
	joystick._input(_touch(0, Vector2(200, 300), true))
	assert_true(joystick.is_active())
	# Otro dedo (los botones) apoya y arrastra en otro lado: no lo mueve.
	joystick._input(_touch(1, Vector2(100, 300), true))
	joystick._input(_drag(1, Vector2(20, 300)))
	assert_false(Input.is_action_pressed(&"move_left"), "el segundo dedo no mueve el joystick")
	joystick._input(_drag(0, Vector2(280, 300)))
	assert_true(Input.is_action_pressed(&"move_right"))
	joystick._input(_touch(1, Vector2(20, 300), false))
	assert_true(joystick.is_active(), "levantar el otro dedo no lo suelta")
	joystick._input(_touch(0, Vector2(280, 300), false))
	assert_false(joystick.is_active())
	assert_false(Input.is_action_pressed(&"move_right"))


func test_touch_outside_its_zone_is_ignored() -> void:
	var joystick := _make_joystick()
	joystick._input(_touch(0, Vector2(900, 300), true))
	assert_false(joystick.is_active(), "un toque fuera de su zona es de los botones")


func test_center_stays_inside_the_zone() -> void:
	var joystick := _make_joystick()
	joystick.begin_touch(0, Vector2(5, 395))
	assert_eq(joystick._center, Vector2(100, 300), "se corre para que el círculo entre entero")


func test_hiding_releases_the_finger() -> void:
	var joystick := _make_joystick()
	joystick.begin_touch(0, Vector2(200, 200))
	joystick.drag_to(Vector2(260, 200))
	joystick.hide()
	assert_false(joystick.is_active())
	assert_false(Input.is_action_pressed(&"move_right"), "al ocultarse no queda caminando")


## Joystick de 400 x 400 en el origen, con radio 100 y zona muerta 0.2.
func _make_joystick() -> TouchJoystick:
	var joystick: TouchJoystick = track(JOYSTICK_SCRIPT.new())
	(Engine.get_main_loop() as SceneTree).root.add_child(joystick)
	joystick.position = Vector2.ZERO
	joystick.size = Vector2(400, 400)
	joystick.radius = 100.0
	joystick.deadzone = 0.2
	return joystick


func _touch(index: int, at: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	return event


func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	return event
