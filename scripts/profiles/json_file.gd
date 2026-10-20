@tool
class_name JsonFile
extends RefCounted
## Lectura y escritura de archivos JSON sin fallar nunca: los perfiles
## (ProfileStore) y la telemetría (TelemetryStore) guardan así sus datos.
##
## La escritura es atómica (primero un .tmp y después se renombra), así un
## cierre a mitad de camino no deja un archivo cortado.


## Guarda data como JSON en path y crea las carpetas que falten. indent vacío
## escribe todo en una línea. Devuelve false (con un aviso) si no pudo.
static func write(path: String, data: Variant, indent: String = "") -> bool:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(dir)
		if dir_error != OK:
			push_warning("JsonFile: no se pudo crear %s (%s)" % [dir, error_string(dir_error)])
			return false
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("JsonFile: no se pudo escribir %s (%s)" % [temp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, indent, false))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		push_warning("JsonFile: falló la escritura de %s (%s)" % [temp_path, error_string(write_error)])
		DirAccess.remove_absolute(temp_path)
		return false
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		push_warning("JsonFile: no se pudo reemplazar %s (%s)" % [path, error_string(rename_error)])
		DirAccess.remove_absolute(temp_path)
		return false
	return true


## Contenido de path ya interpretado, o null si no existe o está dañado (esto
## último con un aviso).
static func read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("JsonFile: %s está dañado (%s)" % [path, json.get_error_message()])
		return null
	return json.data


## Borra la carpeta path con todo lo que tenga adentro. Devuelve true si ya no
## existe.
static func remove_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(dir_name))
	return DirAccess.remove_absolute(path) == OK


## Número de un JSON (siempre float) como int; default si no es un número.
static func to_int(value: Variant, default: int = 0) -> int:
	if value is int:
		return value
	if value is float and is_finite(value):
		return int(value)
	return default


## Número de un JSON como float; default si no es un número.
static func to_float(value: Variant, default: float = 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return default
