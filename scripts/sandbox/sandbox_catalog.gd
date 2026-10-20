@tool
class_name SandboxCatalog
extends RefCounted
## Qué se puede probar en la zona de pruebas: todas las armas de
## res://assets/weapons/ y los enemigos que se pueden hacer aparecer.
##
## Las armas salen de la carpeta (una subcarpeta <id>/<id>.tres por arma), así
## un arma nueva aparece sola. Los enemigos se listan a mano en ENEMIES: es la
## única lista de la zona de pruebas, para agregar uno basta con sumar su
## entrada.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

const WEAPONS_DIR := "res://assets/weapons"
## Armas con todas sus mecánicas: las que se consiguen en una partida. Las demás
## se juegan solo con los valores base de WeaponData (daño, hitbox, tiempos,
## retroceso y perforación); sus mecánicas propias (proyectiles, combos,
## estados, escudo...) todavía no están hechas.
const FULL_MECHANICS_WEAPONS: Array[StringName] = [&"sword", &"dagger", &"spear"]

## Enemigos que se pueden hacer aparecer, en el orden de los botones (las teclas
## 1-9 hacen aparecer los nueve primeros). id es el de LevelGenerator.
const ENEMIES: Array[Dictionary] = [
	{"id": &"skeleton", "name": "Esqueleto soldado", "scene": "res://scenes/Skeleton.tscn"},
	{"id": &"vampire", "name": "Vampiro", "scene": "res://scenes/Vampire.tscn"},
	{"id": &"skull", "name": "Calavera", "scene": "res://scenes/Skull.tscn"},
	{"id": &"reaper", "name": "Parca", "scene": "res://scenes/Reaper.tscn"},
	{"id": &"archer", "name": "Esqueleto arquero", "scene": "res://scenes/Archer.tscn"},
	{"id": &"skull_turret", "name": "Torre de calaveras", "scene": "res://scenes/SkullTurret.tscn"},
	{"id": &"mage", "name": "Mago del orbe", "scene": "res://scenes/Mage.tscn"},
	{"id": &"mimic", "name": "Cofre mímico", "scene": "res://scenes/Mimic.tscn"},
]


## Ids de todas las armas: primero las de FULL_MECHANICS_WEAPONS (en ese orden)
## y después el resto por orden alfabético. Solo cuenta las carpetas que tienen
## su <id>.tres.
static func weapon_ids() -> Array[StringName]:
	var others: Array[StringName] = []
	for dir_name in DirAccess.get_directories_at(WEAPONS_DIR):
		var id := StringName(dir_name)
		if id not in FULL_MECHANICS_WEAPONS and ResourceLoader.exists(WeaponData.PATH_FORMAT % [id, id]):
			others.append(id)
	others.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var ids: Array[StringName] = []
	for id in FULL_MECHANICS_WEAPONS:
		if WeaponData.load_by_id(id) != null:
			ids.append(id)
	ids.append_array(others)
	return ids


## Todas las armas, en el orden de weapon_ids().
static func load_weapons() -> Array[WeaponData]:
	var weapons: Array[WeaponData] = []
	for id in weapon_ids():
		weapons.append(WeaponData.load_by_id(id))
	return weapons


## true si el arma tiene todas sus mecánicas; false si solo usa los valores base.
static func has_full_mechanics(weapon_id: StringName) -> bool:
	return weapon_id in FULL_MECHANICS_WEAPONS


## Todo lo que se puede hacer aparecer: ENEMIES y después los jefes. Cada
## entrada tiene id, name (texto del botón) y scene (ruta de la escena).
static func enemy_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = ENEMIES.duplicate(true)
	entries.append_array(boss_entries())
	return entries


## Jefes para la lista de enemigos, con el mismo formato que ENEMIES.
##
## GANCHO PARA LOS JEFES: cuando exista el registro de jefes (lo está haciendo
## otra rama), esta función debe armar una entrada por jefe a partir de él, por
## ejemplo:
##     for boss in BossRegistry.all():
##         entries.append({"id": boss.id, "name": boss.display_name, "scene": boss.scene_path})
## Mientras tanto no hay jefes y la zona de pruebas no depende de ese registro.
static func boss_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	return entries
