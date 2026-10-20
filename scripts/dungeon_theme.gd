@tool
class_name DungeonTheme
extends RefCounted
## Tema visual de la mazmorra según el nivel: qué textura usa el tileset y qué
## objetos decorativos (antorchas, estandartes, braseros...) se colocan.
##
## Los niveles se agrupan en tramos de BAND_LENGTH. Los primeros conservan el
## calabozo original; después cada tramo tiene un tema y termina en su nivel
## de jefe (8 hielo, 12 lava, 16 musgo). Pasado el último tema los tramos
## siguen rotando en el mismo orden, así cada cuarto nivel cierra un tema.
##
## Los tilesets de los temas son el mismo atlas recoloreado con
## tools/retheme.py: las coordenadas de los tiles y sus colisiones no cambian,
## así que alcanza con cambiar la textura del TileSetAtlasSource.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

const DUNGEON := &"dungeon"
const ICE := &"ice"
const LAVA := &"lava"
const MOSS := &"moss"

## Temas nuevos, en el orden en que aparecen.
const ROTATION: Array[StringName] = [ICE, LAVA, MOSS]
## Primer nivel con un tema nuevo; los anteriores usan el calabozo original.
const FIRST_THEMED_LEVEL := 5
## Niveles por tema. El último de cada tramo es el nivel del jefe del tema.
const BAND_LENGTH := 4

const TILESET_DIR := "res://assets/dungeon/character_and_tileset/"
const THEME_ASSETS_DIR := "res://assets/dungeon_themes/%s/"


## Tema del nivel dado.
static func for_level(level: int) -> StringName:
	if level < FIRST_THEMED_LEVEL:
		return DUNGEON
	var band := (level - FIRST_THEMED_LEVEL) / BAND_LENGTH
	return ROTATION[band % ROTATION.size()]


## true si el tema trae objetos y tileset propios (todos menos el original).
static func is_custom(theme: StringName) -> bool:
	return theme != DUNGEON


## Ruta del atlas del tileset para el tema.
static func tileset_texture_path(theme: StringName) -> String:
	if not is_custom(theme):
		return TILESET_DIR + "Dungeon_Tileset.png"
	return TILESET_DIR + "Dungeon_Tileset_%s.png" % theme


## Ruta de un objeto del tema, p. ej. asset_path(&"ice", "torch") ->
## res://assets/dungeon_themes/ice/ice_torch.png. Con suffix "_frames.tres"
## devuelve su SpriteFrames.
static func asset_path(theme: StringName, object: String, suffix := ".png") -> String:
	return (THEME_ASSETS_DIR % theme) + "%s_%s%s" % [theme, object, suffix]


## Copia de base con la textura del tema en todas sus fuentes de atlas. Nunca
## modifica base: es el recurso compartido que carga Level.tscn (y quedaría
## cambiado para el resto de la partida). Para el tema original devuelve base.
static func themed_tile_set(base: TileSet, theme: StringName) -> TileSet:
	if not is_custom(theme):
		return base
	var texture: Texture2D = load(tileset_texture_path(theme))
	# Copia profunda: las fuentes de atlas (con sus tiles y colisiones) también
	# se copian, así cambiar la textura no toca a base. Las pruebas lo vigilan.
	var tile_set: TileSet = base.duplicate(true)
	for i in tile_set.get_source_count():
		var atlas := tile_set.get_source(tile_set.get_source_id(i)) as TileSetAtlasSource
		if atlas != null:
			atlas.texture = texture
	return tile_set
