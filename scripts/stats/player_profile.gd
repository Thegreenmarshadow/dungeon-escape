@tool
class_name PlayerProfile
extends RefCounted
## Nombre del jugador, guardado en user:// para recordarlo entre sesiones. Lo
## edita el menú principal y RunTracker lo envía con cada partida. Las
## funciones reciben la ruta del archivo, así las pruebas usan una temporal.

const DEFAULT_PATH := "user://player.cfg"
const DEFAULT_NAME := "Jugador"
const MAX_NAME_LENGTH := 24
const _SECTION := "player"
const _KEY := "name"


## Nombre válido: sin espacios en los extremos ni caracteres de control, con
## largo máximo MAX_NAME_LENGTH. Vacío da DEFAULT_NAME.
static func sanitize(raw_name: String) -> String:
	var clean := ""
	for character in raw_name:
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127:
			clean += character
	clean = clean.strip_edges().left(MAX_NAME_LENGTH).strip_edges()
	return clean if not clean.is_empty() else DEFAULT_NAME


static func load_name(path: String = DEFAULT_PATH) -> String:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return DEFAULT_NAME
	return sanitize(str(config.get_value(_SECTION, _KEY, DEFAULT_NAME)))


## Guarda el nombre (ya saneado) y lo devuelve.
static func save_name(raw_name: String, path: String = DEFAULT_PATH) -> String:
	var player_name := sanitize(raw_name)
	var config := ConfigFile.new()
	config.set_value(_SECTION, _KEY, player_name)
	var error := config.save(path)
	if error != OK:
		push_warning("PlayerProfile: no se pudo guardar %s (%s)" % [path, error_string(error)])
	return player_name
