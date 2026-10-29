@tool
extends McpTestSuite
## Pruebas de los controles táctiles: ajustes guardados, cuándo se ven, que los
## botones aprieten acciones del Input Map (con multitouch) y que el input
## buffering y el coyote time funcionen igual con ellos, vibración y zona segura.

const CONTROLS_RIG := preload("res://tests/touch_controls_rig.gd")
const PLAYER_RIG := preload("res://tests/player_rig.gd")
const PIT_SCRIPT := preload("res://scripts/pit.gd")
const GAME_FEEL_SCRIPT := preload("res://scripts/game_feel.gd")
const SETTINGS_PATH := "user://test_control_settings.cfg"
const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down",
		&"attack", &"jump", &"parry", &"pause"]
const DT := 0.016

var _emulation_before := false


func suite_name() -> String:
	return "touch_controls"


func setup() -> void:
	_emulation_before = Input.emulate_touch_from_mouse
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func teardown() -> void:
	for action in ACTIONS:
		Input.action_release(action)
	Input.emulate_touch_from_mouse = _emulation_before
	Haptics.enabled = true
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


# --- Ajustes ---------------------------------------------------------------------

func test_settings_default_without_file() -> void:
	var settings := ControlSettings.load_settings(SETTINGS_PATH)
	assert_eq(settings[ControlSettings.KEY_TOUCH_MODE], ControlSettings.TouchMode.AUTO)
	assert_eq(settings[ControlSettings.KEY_OPACITY], ControlSettings.DEFAULT_OPACITY)
	assert_eq(settings[ControlSettings.KEY_SCALE], ControlSettings.DEFAULT_SCALE)
	assert_eq(settings[ControlSettings.KEY_DEADZONE], ControlSettings.DEFAULT_DEADZONE)
	assert_eq(settings[ControlSettings.KEY_VIBRATION], true)


func test_settings_are_saved() -> void:
	assert_true(ControlSettings.save_value(ControlSettings.KEY_TOUCH_MODE, ControlSettings.TouchMode.NEVER, SETTINGS_PATH))
	ControlSettings.save_value(ControlSettings.KEY_OPACITY, 0.8, SETTINGS_PATH)
	ControlSettings.save_value(ControlSettings.KEY_SCALE, 1.25, SETTINGS_PATH)
	ControlSettings.save_value(ControlSettings.KEY_DEADZONE, 0.3, SETTINGS_PATH)
	ControlSettings.save_value(ControlSettings.KEY_VIBRATION, false, SETTINGS_PATH)
	var settings := ControlSettings.load_settings(SETTINGS_PATH)
	assert_eq(settings[ControlSettings.KEY_TOUCH_MODE], ControlSettings.TouchMode.NEVER)
	assert_eq(settings[ControlSettings.KEY_OPACITY], 0.8)
	assert_eq(settings[ControlSettings.KEY_SCALE], 1.25)
	assert_eq(settings[ControlSettings.KEY_DEADZONE], 0.3)
	assert_eq(settings[ControlSettings.KEY_VIBRATION], false)


func test_settings_keep_the_telemetry_setting() -> void:
	GameSettings.set_telemetry_enabled(false, SETTINGS_PATH)
	ControlSettings.save_value(ControlSettings.KEY_OPACITY, 0.7, SETTINGS_PATH)
	assert_false(GameSettings.telemetry_enabled(SETTINGS_PATH), "comparten archivo sin pisarse")


func test_settings_out_of_range_are_clamped() -> void:
	var config := ConfigFile.new()
	config.set_value("controls", ControlSettings.KEY_TOUCH_MODE, "sideways")
	config.set_value("controls", ControlSettings.KEY_OPACITY, 5.0)
	config.set_value("controls", ControlSettings.KEY_SCALE, 0.1)
	config.set_value("controls", ControlSettings.KEY_DEADZONE, "mucho")
	config.save(SETTINGS_PATH)
	var settings := ControlSettings.load_settings(SETTINGS_PATH)
	assert_eq(settings[ControlSettings.KEY_TOUCH_MODE], ControlSettings.TouchMode.AUTO)
	assert_eq(settings[ControlSettings.KEY_OPACITY], ControlSettings.OPACITY_MAX)
	assert_eq(settings[ControlSettings.KEY_SCALE], ControlSettings.SCALE_MIN)
	assert_eq(settings[ControlSettings.KEY_DEADZONE], ControlSettings.DEFAULT_DEADZONE)


func test_apply_settings_sizes_and_fades_controls() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS, 1.5)
	assert_eq(controls.attack_button.diameter, controls.ATTACK_DIAMETER * 1.5)
	assert_eq(controls.attack_button.position, controls.ATTACK_POSITION * 1.5)
	assert_eq(controls.joystick.radius, controls.JOYSTICK_RADIUS * 1.5)
	assert_eq(controls.joystick.deadzone, 0.25)
	assert_eq(controls.jump_button.opacity, 0.5)
	assert_true(controls.pause_button.diameter >= 96.0, "hasta la pausa se usa con el pulgar")


func test_vibration_setting_reaches_haptics() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	var settings: Dictionary = controls.settings.duplicate()
	settings[ControlSettings.KEY_VIBRATION] = false
	controls.apply_settings(settings)
	assert_false(Haptics.enabled)


# --- Cuándo se ven ---------------------------------------------------------------

func test_hidden_without_a_player() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	assert_false(controls.should_show(), "en los menús no se ven")


func test_always_mode_shows_them_in_gameplay() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	controls._player = _make_player()
	assert_true(controls.should_show())


func test_never_mode_hides_them() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.NEVER)
	controls._player = _make_player()
	controls.preview = true
	assert_false(controls.should_show())


func test_preview_shows_them_without_player() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.AUTO)
	controls.preview = true
	assert_true(controls.should_show(), "la vista previa de Ajustes se ve en Auto")
	assert_false(controls.joystick.interactive, "en la vista previa el joystick no camina")


func test_hidden_when_paused_or_dead() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	var player := _make_player()
	controls._player = player
	player.set_physics_process(false)
	assert_false(controls.should_show(), "muerto el jugador no se ven")


func test_auto_mode_follows_the_last_device() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.AUTO)
	controls._native_touchscreen = false
	controls._player = _make_player()
	assert_false(controls.should_show(), "en una PC sin tocar la pantalla no se ven")
	var emulated := _touch(0, Vector2(10, 10), true)
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	controls._input(emulated)
	assert_false(controls.should_show(), "el mouse que emula toques no cuenta")
	controls._input(_touch(0, Vector2(10, 10), true))
	assert_true(controls.should_show(), "con un toque real aparecen")
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.pressed = true
	controls._input(key)
	assert_false(controls.should_show(), "al usar el teclado se ocultan")
	controls._input(_touch(0, Vector2(10, 10), true))
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 0.9
	controls._input(stick)
	assert_false(controls.should_show(), "al usar el mando se ocultan")


func test_auto_mode_on_a_touchscreen_device() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.AUTO)
	controls._native_touchscreen = true
	controls._player = _make_player()
	assert_true(controls.should_show(), "en el celular se ven siempre")


func test_always_mode_emulates_touch_on_pc() -> void:
	var controls := _make_controls(ControlSettings.TouchMode.AUTO)
	controls._native_touchscreen = false
	Input.emulate_touch_from_mouse = false
	controls.apply_settings(_settings(ControlSettings.TouchMode.ALWAYS))
	assert_true(Input.emulate_touch_from_mouse, "Siempre en PC: el mouse fabrica toques")
	controls.apply_settings(_settings(ControlSettings.TouchMode.AUTO))
	assert_false(Input.emulate_touch_from_mouse, "al salir de Siempre se apaga")


# --- Botones, multitouch, buffer y coyote ----------------------------------------

func test_touch_button_presses_its_action() -> void:
	if _skip_in_editor():
		return
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	_press(controls.attack_button, 1)
	assert_true(Input.is_action_pressed(&"attack"), "el botón aprieta la acción del Input Map")
	assert_true(Input.is_action_just_pressed(&"attack"))
	_lift(controls.attack_button, 1)
	assert_false(Input.is_action_pressed(&"attack"))


func test_touch_attack_reaches_the_player() -> void:
	if _skip_in_editor():
		return
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	var player := _make_player()
	_press(controls.attack_button, 1)
	player._update_attack_buffer(DT, Input.is_action_just_pressed(&"attack"))
	assert_true(player._cooldown_left > 0.0, "ataca igual que con la tecla")


func test_move_and_jump_at_the_same_time() -> void:
	if _skip_in_editor():
		return
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	var stick_start: Vector2 = controls.joystick.get_global_rect().get_center()
	_push(_touch(0, stick_start, true))
	_push(_drag(0, stick_start + Vector2(80, 0)))
	_press(controls.jump_button, 1)
	assert_true(Input.is_action_pressed(&"move_right"), "un dedo camina")
	assert_true(Input.is_action_pressed(&"jump"), "y otro salta a la vez")
	_lift(controls.jump_button, 1)
	assert_true(Input.is_action_pressed(&"move_right"), "levantar el botón no suelta el joystick")
	_push(_touch(0, stick_start + Vector2(80, 0), false))
	assert_false(Input.is_action_pressed(&"move_right"))


func test_touch_jump_is_buffered_in_the_air() -> void:
	if _skip_in_editor():
		return
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	var player := _make_player()
	var used: Array = []
	player.buffered_action_used.connect(func(action, _waited): used.append(action))
	player._update_jump(DT, true)
	# Toca saltar poco antes de aterrizar.
	player._jump_left = 0.05
	_press(controls.jump_button, 1)
	player._update_jump(DT, Input.is_action_just_pressed(&"jump"))
	_lift(controls.jump_button, 1)
	for i in 4:
		player._update_jump(DT, false)
	assert_true(player.is_jumping(), "el salto tocado en el aire sale al aterrizar")
	assert_true(used.has(&"jump"))


func test_touch_jump_uses_coyote_time() -> void:
	if _skip_in_editor():
		return
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	var player := _make_player_next_to_pit()
	player.global_position = Vector2(108, 8)
	player._update_jump(DT, false)
	assert_true(player.coyote_left() > 0.0, "pisó el abismo: corre el coyote time")
	_press(controls.jump_button, 1)
	player._update_jump(DT, Input.is_action_just_pressed(&"jump"))
	assert_true(player.is_jumping(), "el botón táctil salta dentro del coyote time")
	assert_false(player._falling)


func test_hiding_releases_pressed_buttons() -> void:
	if _skip_in_editor():
		return
	var controls := _make_controls(ControlSettings.TouchMode.ALWAYS)
	_press(controls.jump_button, 1)
	controls.visible = false
	controls.release_all()
	assert_false(Input.is_action_pressed(&"jump"), "al pausar no queda apretado")
	controls.visible = true
	_lift(controls.jump_button, 1)
	_press(controls.jump_button, 2)
	assert_true(Input.is_action_pressed(&"jump"), "al volver, el botón responde a un dedo nuevo")


# --- Vibración y zona segura -----------------------------------------------------

func test_game_feel_vibrates_on_key_moments() -> void:
	var feel: Node = track(GAME_FEEL_SCRIPT.new())
	Haptics.last_requested_ms = 0
	feel._on_player_damaged(2, &"")
	assert_eq(Haptics.last_requested_ms, Haptics.DAMAGE_MS, "recibir daño vibra")
	feel._on_player_key()
	assert_eq(Haptics.last_requested_ms, Haptics.PICKUP_MS, "recoger la llave vibra")


func test_no_vibration_when_disabled() -> void:
	Haptics.enabled = false
	Haptics.last_requested_ms = 0
	assert_false(Haptics.vibrate(Haptics.DAMAGE_MS))
	assert_eq(Haptics.last_requested_ms, 0)


func test_safe_area_insets() -> void:
	# Pantalla de 2400 x 1080 con un notch de 80 px a la izquierda, vista a la mitad.
	var insets := SafeArea.insets_from(Rect2i(80, 0, 2320, 1040), Vector2i(2400, 1080), Vector2(0.5, 0.5))
	assert_eq(insets["left"], 40.0)
	assert_eq(insets["top"], 0.0)
	assert_eq(insets["right"], 0.0)
	assert_eq(insets["bottom"], 20.0)
	assert_eq(SafeArea.insets_from(Rect2i(), Vector2i(2400, 1080), Vector2.ONE), SafeArea.zero())


# --- Ayudas ----------------------------------------------------------------------

func _settings(mode: ControlSettings.TouchMode, scale_factor := 1.0) -> Dictionary:
	return {
		ControlSettings.KEY_TOUCH_MODE: mode,
		ControlSettings.KEY_OPACITY: 0.5,
		ControlSettings.KEY_SCALE: scale_factor,
		ControlSettings.KEY_DEADZONE: 0.25,
		ControlSettings.KEY_VIBRATION: true,
	}


func _make_controls(mode: ControlSettings.TouchMode, scale_factor := 1.0) -> CanvasLayer:
	var controls: CanvasLayer = track(CONTROLS_RIG.make_controls())
	(Engine.get_main_loop() as SceneTree).root.add_child(controls)
	controls.apply_settings(_settings(mode, scale_factor))
	controls.visible = true
	return controls


func _make_player() -> CharacterBody2D:
	var player: CharacterBody2D = track(PLAYER_RIG.make_player())
	(Engine.get_main_loop() as SceneTree).root.add_child(player)
	return player


## Jugador en (40, 8) y un abismo de 16 px de ancho en x = 100..116 (como en
## test_coyote_time.gd).
func _make_player_next_to_pit() -> CharacterBody2D:
	var root := (Engine.get_main_loop() as SceneTree).root
	var pit: Node2D = track(PIT_SCRIPT.new())
	pit.position = Vector2(100, 0)
	pit.size = Vector2(16, 16)
	root.add_child(pit)
	var player := _make_player()
	player.global_position = Vector2(40, 8)
	player._last_safe_position = player.global_position
	return player


## En el editor TouchScreenButton no lee toques: esas pruebas corren con el
## juego (o con Godot sin editor).
func _skip_in_editor() -> bool:
	if Engine.is_editor_hint():
		skip("TouchScreenButton no recibe toques en el editor")
		return true
	return false


func _press(button: TouchScreenButton, index: int) -> void:
	_push(_touch(index, button.get_global_transform_with_canvas().origin, true))


func _lift(button: TouchScreenButton, index: int) -> void:
	_push(_touch(index, button.get_global_transform_with_canvas().origin, false))


func _push(event: InputEvent) -> void:
	(Engine.get_main_loop() as SceneTree).root.push_input(event, true)


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
