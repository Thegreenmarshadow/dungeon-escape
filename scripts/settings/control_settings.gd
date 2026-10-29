@tool
class_name ControlSettings
extends RefCounted
## Ajustes de los controles táctiles y de la vibración, guardados en la sección
## [controls] de user://settings.cfg (el mismo archivo que GameSettings). Los
## edita SettingsMenu y los aplica TouchControls. Las funciones reciben la ruta
## del archivo, así las pruebas usan una temporal. Un archivo ausente o dañado
## da los valores por defecto, y un valor fuera de rango se recorta al límite.

## Cuándo se ven los controles táctiles (ver TouchControls).
enum TouchMode { AUTO, ALWAYS, NEVER }

const DEFAULT_PATH := GameSettings.DEFAULT_PATH
const KEY_TOUCH_MODE := "touch_mode"
const KEY_OPACITY := "opacity"
const KEY_SCALE := "scale"
const KEY_DEADZONE := "deadzone"
const KEY_VIBRATION := "vibration"

## Nombre con que se guarda cada TouchMode.
const MODE_NAMES: Array[String] = ["auto", "always", "never"]
const DEFAULT_TOUCH_MODE := TouchMode.AUTO
## Opacidad de joystick y botones (0 a 1).
const OPACITY_MIN := 0.2
const OPACITY_MAX := 1.0
const DEFAULT_OPACITY := 0.55
## Tamaño de joystick y botones, multiplicando los de TouchControls.
const SCALE_MIN := 0.75
const SCALE_MAX := 1.5
const DEFAULT_SCALE := 1.0
## Zona muerta del joystick, en fracción de su radio.
const DEADZONE_MIN := 0.05
const DEADZONE_MAX := 0.5
const DEFAULT_DEADZONE := 0.2
const DEFAULT_VIBRATION := true

const _SECTION := "controls"


## Todos los ajustes de controles, ya validados: touch_mode (TouchMode),
## opacity, scale, deadzone (float) y vibration (bool).
static func load_settings(path: String = DEFAULT_PATH) -> Dictionary:
	var config := ConfigFile.new()
	var loaded := config.load(path) == OK
	var read := func(key: String, fallback: Variant) -> Variant:
		return config.get_value(_SECTION, key, fallback) if loaded else fallback
	var mode_name := str(read.call(KEY_TOUCH_MODE, MODE_NAMES[DEFAULT_TOUCH_MODE]))
	var mode := MODE_NAMES.find(mode_name)
	return {
		KEY_TOUCH_MODE: mode if mode != -1 else DEFAULT_TOUCH_MODE,
		KEY_OPACITY: _clamped(read.call(KEY_OPACITY, DEFAULT_OPACITY), OPACITY_MIN, OPACITY_MAX, DEFAULT_OPACITY),
		KEY_SCALE: _clamped(read.call(KEY_SCALE, DEFAULT_SCALE), SCALE_MIN, SCALE_MAX, DEFAULT_SCALE),
		KEY_DEADZONE: _clamped(read.call(KEY_DEADZONE, DEFAULT_DEADZONE), DEADZONE_MIN, DEADZONE_MAX, DEFAULT_DEADZONE),
		KEY_VIBRATION: bool(read.call(KEY_VIBRATION, DEFAULT_VIBRATION)),
	}


## Guarda un ajuste (key es una de las KEY_*). touch_mode se pasa como
## TouchMode. Devuelve true si se pudo escribir el archivo.
static func save_value(key: String, value: Variant, path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	config.load(path)
	if key == KEY_TOUCH_MODE:
		value = MODE_NAMES[clampi(int(value), 0, MODE_NAMES.size() - 1)]
	config.set_value(_SECTION, key, value)
	var error := config.save(path)
	if error != OK:
		push_warning("ControlSettings: no se pudo guardar %s (%s)" % [path, error_string(error)])
	return error == OK


static func _clamped(value: Variant, low: float, high: float, fallback: float) -> float:
	if not (value is float or value is int):
		return fallback
	return clampf(float(value), low, high)
