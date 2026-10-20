@tool
class_name GameSettings
extends RefCounted
## Ajustes del jugador guardados en user://settings.cfg (los edita
## SettingsMenu). Las funciones reciben la ruta del archivo, así las pruebas
## usan una temporal. Un archivo ausente o dañado da los valores por defecto.

const DEFAULT_PATH := "user://settings.cfg"
## La telemetría (Telemetry) está activa salvo que el jugador la apague.
const DEFAULT_TELEMETRY_ENABLED := true
const _SECTION := "privacy"
const _TELEMETRY_KEY := "telemetry_enabled"


## true si la telemetría (recorrido y eventos de cada nivel) está activa.
static func telemetry_enabled(path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return DEFAULT_TELEMETRY_ENABLED
	return bool(config.get_value(_SECTION, _TELEMETRY_KEY, DEFAULT_TELEMETRY_ENABLED))


static func set_telemetry_enabled(enabled: bool, path: String = DEFAULT_PATH) -> bool:
	var config := ConfigFile.new()
	config.load(path)
	config.set_value(_SECTION, _TELEMETRY_KEY, enabled)
	var error := config.save(path)
	if error != OK:
		push_warning("GameSettings: no se pudo guardar %s (%s)" % [path, error_string(error)])
	return error == OK
