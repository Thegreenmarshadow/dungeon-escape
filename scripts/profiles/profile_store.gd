@tool
class_name ProfileStore
extends RefCounted
## Perfiles de jugador guardados en disco: nombre (o apodo), tiempo jugado
## acumulado entre sesiones y la partida guardada para "Continuar". Es lógica
## pura: no conoce nodos ni el estado global (el Autoload Profiles se lo pasa),
## así se prueba con una carpeta temporal (base_dir).
##
## Estructura en disco (base_dir, por defecto user://profiles):
##   profiles.cfg                 perfil elegido y si ya se migró player.cfg
##   <slug>/profile.json          datos del perfil (ver make_profile)
##   <slug>/runs/<run_id>/...     telemetría de cada nivel (TelemetryStore)
## El slug es la carpeta, sacada del nombre (ver slug_for).
##
## profile.json:
##   schema_version  SCHEMA_VERSION
##   name            nombre tal como se muestra (PlayerProfile.sanitize)
##   created_at      fecha UTC de creación ("2026-10-20T12:00:00Z")
##   total_time_s    segundos jugados en total (sin pausas)
##   runs            {run_id: {time_s, mode, started_at}}: tiempo de cada partida
##   save            partida guardada (ver SAVE_KEYS) o {} si no hay
## Cargar un archivo viejo o incompleto nunca falla: lo que falta toma el valor
## por defecto. Una partida guardada antes de los medios corazones tiene
## "lives" (vidas enteras) en lugar de "health": se convierte al cargarla (ver
## saved_health).

const DEFAULT_BASE_DIR := "user://profiles"
const SCHEMA_VERSION := 1
const PROFILE_FILE := "profile.json"
const INDEX_FILE := "profiles.cfg"
## Largo máximo de la carpeta de un perfil.
const MAX_SLUG_LENGTH := 32
## Carpeta de un nombre sin letras ni números ("???").
const FALLBACK_SLUG := "perfil"
## Datos de la partida guardada. level, health, weapon_id, run_seed, coins,
## damage_bonus y mode son los que restaura "Continuar"; score,
## enemies_killed y run_id conservan el puntaje y la carpeta de telemetría.
## health es la vida en medios corazones; el nombre de la clave es también la
## marca de unidad: las partidas viejas guardaban LEGACY_LIVES_KEY en vidas
## enteras (ver saved_health).
const SAVE_KEYS: Array[String] = ["level", "health", "weapon_id", "run_seed", "coins",
		"damage_bonus", "mode", "score", "enemies_killed", "run_id"]
## Clave de la vida en las partidas guardadas antes de los medios corazones:
## vidas enteras, cada una de Heart.HALF_HEARTS_PER_HEART medios corazones.
const LEGACY_LIVES_KEY := "lives"
const _INDEX_SECTION := "profiles"
## Letras con tilde que el slug pasa a su forma simple.
const _ACCENTS := {
	"á": "a", "à": "a", "ä": "a", "â": "a", "ã": "a", "å": "a",
	"é": "e", "è": "e", "ë": "e", "ê": "e",
	"í": "i", "ì": "i", "ï": "i", "î": "i",
	"ó": "o", "ò": "o", "ö": "o", "ô": "o", "õ": "o",
	"ú": "u", "ù": "u", "ü": "u", "û": "u",
	"ñ": "n", "ç": "c",
}

var base_dir: String


func _init(p_base_dir: String = DEFAULT_BASE_DIR) -> void:
	base_dir = p_base_dir


# ---------------------------------------------------------------------------
# Nombres y carpetas
# ---------------------------------------------------------------------------

## Nombre válido de un perfil (las mismas reglas que PlayerProfile).
static func sanitize_name(raw_name: String) -> String:
	return PlayerProfile.sanitize(raw_name)


## Carpeta de un nombre: minúsculas sin tildes, letras y números unidos por
## guiones ("Iñaki Núñez" -> "inaki-nunez"). Sin letras ni números da
## FALLBACK_SLUG.
static func slug_for(player_name: String) -> String:
	var slug := ""
	for raw_character in player_name.to_lower():
		var character: String = _ACCENTS.get(raw_character, raw_character)
		var code := character.unicode_at(0)
		var is_alnum := (code >= 97 and code <= 122) or (code >= 48 and code <= 57)
		if is_alnum:
			slug += character
		elif not slug.is_empty() and not slug.ends_with("-"):
			slug += "-"
	slug = slug.left(MAX_SLUG_LENGTH).trim_suffix("-")
	return slug if not slug.is_empty() else FALLBACK_SLUG


## Carpeta del perfil slug.
func profile_dir(slug: String) -> String:
	return base_dir.path_join(slug)


func profile_path(slug: String) -> String:
	return profile_dir(slug).path_join(PROFILE_FILE)


func has_profile(slug: String) -> bool:
	return not slug.is_empty() and FileAccess.file_exists(profile_path(slug))


# ---------------------------------------------------------------------------
# Perfiles
# ---------------------------------------------------------------------------

## Perfil nuevo (sin guardar) con todos los campos en su valor inicial.
static func make_profile(player_name: String, slug: String) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"slug": slug,
		"name": sanitize_name(player_name),
		"created_at": _now(),
		"total_time_s": 0.0,
		"runs": {},
		"save": {},
	}


## Todos los perfiles guardados, ordenados por nombre.
func list_profiles() -> Array[Dictionary]:
	var profiles: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(base_dir):
		return profiles
	for slug in DirAccess.get_directories_at(base_dir):
		if has_profile(slug):
			profiles.append(load_profile(slug))
	profiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]).naturalnocasecmp_to(b["name"]) < 0)
	return profiles


## Perfil con ese nombre (sin distinguir mayúsculas), o {} si no hay.
func find_by_name(player_name: String) -> Dictionary:
	var wanted := sanitize_name(player_name).to_lower()
	for profile in list_profiles():
		if String(profile["name"]).to_lower() == wanted:
			return profile
	return {}


## Crea y guarda un perfil con ese nombre. Si ya hay uno con el mismo nombre
## devuelve ese, sin duplicarlo. Dos nombres con la misma carpeta ("Ana" y
## "ana!") reciben carpetas distintas ("ana", "ana-2").
func create_profile(raw_name: String) -> Dictionary:
	var existing := find_by_name(raw_name)
	if not existing.is_empty():
		return existing
	var player_name := sanitize_name(raw_name)
	var base_slug := slug_for(player_name)
	var slug := base_slug
	var suffix := 2
	while DirAccess.dir_exists_absolute(profile_dir(slug)):
		slug = "%s-%d" % [base_slug, suffix]
		suffix += 1
	var profile := make_profile(player_name, slug)
	save_profile(profile)
	return profile


## Perfil guardado en la carpeta slug, con valores por defecto para todo lo que
## falte. {} si no existe. Nunca falla con un archivo viejo o dañado.
func load_profile(slug: String) -> Dictionary:
	if not has_profile(slug):
		return {}
	var raw: Variant = JsonFile.read(profile_path(slug))
	return normalize_profile(raw if raw is Dictionary else {}, slug)


## Completa un perfil leído del disco: tipos correctos y valores por defecto.
static func normalize_profile(raw: Dictionary, slug: String) -> Dictionary:
	var profile := make_profile(str(raw.get("name", "")) if raw.get("name") is String else slug, slug)
	profile["schema_version"] = JsonFile.to_int(raw.get("schema_version"), SCHEMA_VERSION)
	if raw.get("created_at") is String:
		profile["created_at"] = raw["created_at"]
	profile["total_time_s"] = maxf(JsonFile.to_float(raw.get("total_time_s")), 0.0)
	var runs: Dictionary = {}
	if raw.get("runs") is Dictionary:
		for run_id: Variant in raw["runs"]:
			var run: Variant = raw["runs"][run_id]
			if run is Dictionary:
				runs[str(run_id)] = {
					"time_s": maxf(JsonFile.to_float(run.get("time_s")), 0.0),
					"mode": str(run.get("mode", "")),
					"started_at": str(run.get("started_at", "")),
				}
	profile["runs"] = runs
	profile["save"] = normalize_save(raw.get("save"))
	return profile


## Guarda el perfil (su carpeta es profile["slug"]).
func save_profile(profile: Dictionary) -> bool:
	var slug := str(profile.get("slug", ""))
	if slug.is_empty():
		return false
	return JsonFile.write(profile_path(slug), profile, "\t")


## Borra el perfil con toda su telemetría. Si era el elegido, ya no hay
## ninguno elegido.
func delete_profile(slug: String) -> bool:
	if slug.is_empty() or not DirAccess.dir_exists_absolute(profile_dir(slug)):
		return false
	if selected_slug() == slug:
		_set_index_value("selected", "")
	return JsonFile.remove_tree(profile_dir(slug))


# ---------------------------------------------------------------------------
# Perfil elegido
# ---------------------------------------------------------------------------

## Carpeta del perfil elegido, o "" si no hay (o si se borró).
func selected_slug() -> String:
	var slug := str(_index().get_value(_INDEX_SECTION, "selected", ""))
	return slug if has_profile(slug) else ""


## Perfil elegido, o {} si no hay.
func selected_profile() -> Dictionary:
	return load_profile(selected_slug())


func select_profile(slug: String) -> bool:
	if not has_profile(slug):
		return false
	_set_index_value("selected", slug)
	return true


## Pasa el nombre del menú anterior (player.cfg de PlayerProfile) a un primer
## perfil y lo elige. Solo una vez: después ya no mira legacy_path. Devuelve el
## perfil creado, o {} si no había nada que migrar o ya se había hecho.
func migrate_legacy(legacy_path: String = PlayerProfile.DEFAULT_PATH) -> Dictionary:
	if bool(_index().get_value(_INDEX_SECTION, "legacy_migrated", false)):
		return {}
	_set_index_value("legacy_migrated", true)
	if not FileAccess.file_exists(legacy_path):
		return {}
	var profile := create_profile(PlayerProfile.load_name(legacy_path))
	if selected_slug().is_empty():
		select_profile(profile["slug"])
	return profile


# ---------------------------------------------------------------------------
# Tiempo jugado
# ---------------------------------------------------------------------------

## Suma seconds al tiempo total del perfil y, si se da run_id, al de esa
## partida (que se crea con mode). Devuelve el perfil actualizado, o {} si no
## existe.
func add_play_time(slug: String, seconds: float, run_id: String = "", mode: String = "") -> Dictionary:
	var profile := load_profile(slug)
	if profile.is_empty():
		return {}
	seconds = maxf(seconds, 0.0)
	profile["total_time_s"] = _hundredths(float(profile["total_time_s"]) + seconds)
	if not run_id.is_empty():
		var runs: Dictionary = profile["runs"]
		if not runs.has(run_id):
			runs[run_id] = {"time_s": 0.0, "mode": mode, "started_at": _now()}
		runs[run_id]["time_s"] = _hundredths(float(runs[run_id]["time_s"]) + seconds)
	save_profile(profile)
	return profile


## Tiempo legible: "45 s", "12 min", "1 h 05 min".
static func format_duration(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	if total < 60:
		return "%d s" % total
	var minutes := total / 60
	if minutes < 60:
		return "%d min" % minutes
	return "%d h %02d min" % [minutes / 60, minutes % 60]


# ---------------------------------------------------------------------------
# Partida guardada
# ---------------------------------------------------------------------------

## Partida guardada con todos sus campos, o {} si raw no es una partida.
static func normalize_save(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.is_empty():
		return {}
	return {
		"level": maxi(JsonFile.to_int(raw.get("level"), 1), 1),
		"health": saved_health(raw),
		"weapon_id": str(raw.get("weapon_id", WeaponData.STARTING_ID)),
		"run_seed": JsonFile.to_int(raw.get("run_seed")),
		"coins": maxi(JsonFile.to_int(raw.get("coins")), 0),
		"damage_bonus": maxi(JsonFile.to_int(raw.get("damage_bonus")), 0),
		"mode": str(raw.get("mode", RunRecorder.MODE_NORMAL)),
		"score": maxi(JsonFile.to_int(raw.get("score")), 0),
		"enemies_killed": maxi(JsonFile.to_int(raw.get("enemies_killed")), 0),
		"run_id": str(raw.get("run_id", "")),
	}


## Vida (medios corazones, al menos 1) de una partida guardada. Si tiene
## "health" ya está en medios corazones. Si solo tiene LEGACY_LIVES_KEY es de
## antes de los medios corazones: cada vida entera vale
## Heart.HALF_HEARTS_PER_HEART (3 vidas -> 6). Sin ninguna de las dos devuelve
## default.
static func saved_health(save: Dictionary, default: int = Heart.HALF_HEARTS_PER_HEART) -> int:
	if save.has("health"):
		return maxi(JsonFile.to_int(save["health"], default), 1)
	if save.has(LEGACY_LIVES_KEY):
		return maxi(JsonFile.to_int(save[LEGACY_LIVES_KEY], 1), 1) * Heart.HALF_HEARTS_PER_HEART
	return maxi(default, 1)


## Guarda la partida del perfil (ver SAVE_KEYS).
func set_save(slug: String, save: Dictionary) -> bool:
	var profile := load_profile(slug)
	if profile.is_empty():
		return false
	profile["save"] = normalize_save(save)
	return save_profile(profile)


func clear_save(slug: String) -> bool:
	var profile := load_profile(slug)
	if profile.is_empty():
		return false
	if (profile["save"] as Dictionary).is_empty():
		return true
	profile["save"] = {}
	return save_profile(profile)


## Partida guardada del perfil, o {} si no tiene.
func get_save(slug: String) -> Dictionary:
	var profile := load_profile(slug)
	return profile.get("save", {}) if not profile.is_empty() else {}


# ---------------------------------------------------------------------------
# Internos
# ---------------------------------------------------------------------------

func _index() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(base_dir.path_join(INDEX_FILE))
	return config


func _set_index_value(key: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(base_dir)
	var config := _index()
	config.set_value(_INDEX_SECTION, key, value)
	var error := config.save(base_dir.path_join(INDEX_FILE))
	if error != OK:
		push_warning("ProfileStore: no se pudo guardar %s (%s)" % [INDEX_FILE, error_string(error)])


## Redondea a centésimas: el archivo no acumula decimales de más.
static func _hundredths(value: float) -> float:
	return roundf(value * 100.0) / 100.0


static func _now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
