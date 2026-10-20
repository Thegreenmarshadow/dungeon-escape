@tool
class_name BossRegistry
extends RefCounted
## Qué jefe cierra cada tema y en qué niveles aparece (docs/assets-pack/03-jefes.md,
## sección 9.1).
##
## Un jefe aparece en el último nivel de cada tramo de tema de DungeonTheme
## (8 hielo, 12 lava, 16 musgo) y, como los tramos siguen rotando, también en
## los siguientes cierres de tramo (20 hielo, 24 lava, 28 musgo...). En su
## nivel reemplaza a la parca que guarda la puerta y lleva la llave.
##
## Para sumar un jefe alcanza con completar su línea en SCENES con la ruta de
## su escena. Mientras la línea esté vacía (o la escena no exista) su nivel se
## juega como uno normal, con la parca en la puerta y la llave en su sala.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

const LICH := &"lich"
const FORGE := &"forge"
const WARDEN := &"warden"

## Jefe de cada tema nuevo. El calabozo original no tiene jefe propio.
const THEME_BOSSES := {
	DungeonTheme.ICE: LICH,
	DungeonTheme.LAVA: FORGE,
	DungeonTheme.MOSS: WARDEN,
}

## Escena de cada jefe. "" significa que todavía no existe. Cada jefe tiene su
## propia línea, separadas por la del Forjador, así dos ramas que completan
## jefes distintos no chocan al unirse.
const SCENES := {
	LICH: "",  # TODO paso 2: "res://scenes/bosses/lich/Lich.tscn"
	FORGE: "res://scenes/bosses/forge/Forge.tscn",
	WARDEN: "",  # TODO paso 2: "res://scenes/bosses/warden/Warden.tscn"
}


## true si el nivel cierra un tramo de tema: ahí va el jefe del tema.
static func is_boss_level(level: int) -> bool:
	if level < DungeonTheme.FIRST_THEMED_LEVEL:
		return false
	var position_in_band := (level - DungeonTheme.FIRST_THEMED_LEVEL) % DungeonTheme.BAND_LENGTH
	return position_in_band == DungeonTheme.BAND_LENGTH - 1


## Jefe que corresponde al nivel según su tema, exista o no su escena. &"" si
## el nivel no es de jefe.
static func planned_boss_for_level(level: int) -> StringName:
	if not is_boss_level(level):
		return &""
	return THEME_BOSSES.get(DungeonTheme.for_level(level), &"")


## Jefe que de verdad aparece en el nivel: el planeado, si su escena existe.
## &"" si el nivel no es de jefe o su jefe todavía no está hecho. scenes
## permite probar con otro registro.
static func boss_for_level(level: int, scenes: Dictionary = SCENES) -> StringName:
	var boss_id := planned_boss_for_level(level)
	if boss_id == &"" or not is_available(boss_id, scenes):
		return &""
	return boss_id


## Ruta de la escena del jefe, o "" si no está registrada.
static func scene_path(boss_id: StringName, scenes: Dictionary = SCENES) -> String:
	return scenes.get(boss_id, "")


## true si el jefe tiene una escena registrada que existe.
static func is_available(boss_id: StringName, scenes: Dictionary = SCENES) -> bool:
	var path := scene_path(boss_id, scenes)
	return not path.is_empty() and ResourceLoader.exists(path)


## Escena del jefe, o null si no está disponible.
static func load_scene(boss_id: StringName) -> PackedScene:
	if not is_available(boss_id):
		return null
	return load(scene_path(boss_id))
