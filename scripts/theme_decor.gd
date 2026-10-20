@tool
class_name ThemeDecor
extends RefCounted
## Viste un mapa generado con el tema de su nivel (ver DungeonTheme): cambia la
## textura del tileset y coloca los objetos decorativos del tema.
##
## La colocación (plan) es lógica pura y determinista: la misma semilla y el
## mismo mapa dan siempre la misma decoración. No cambia el mapa ni lo que
## coloca el generador, y nunca ocupa celdas reservadas (inicio, llave, puerta,
## enemigos con su patrulla, trampas, monedas).
##
## Qué va dónde (docs/assets-pack/04-temas-mazmorra.md):
## - Antorchas: las celdas de layout.torches, con las animaciones del tema
##   (las coloca LevelBuilder usando torch_frames()).
## - Estandartes y emblemas: pared frontal de las salas, lejos de antorchas y
##   de la puerta.
## - Runa de suelo: marca la sala de la llave, junto a ella.
## - Manchas (floor_patch) y piedritas (scatter): suelo de las salas.
## - Objeto grande (prop: brasero, cristal o seta): suelo, con colisión de una
##   celda. Solo va en celdas rodeadas de suelo y separado de todo lo demás,
##   así nunca corta un camino.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

const BANNER := &"banner"
const EMBLEM := &"emblem"
const FLOOR_RUNE := &"floor_rune"
const FLOOR_PATCH := &"floor_patch"
const PROP := &"prop"
const SCATTER := &"scatter"

## Animación de los SpriteFrames del pack.
const ANIMATION := &"default"
## Grupos de los nodos que pueden interesarle a la jugabilidad (p. ej. el
## Guardián musgoso se cura sobre las manchas de musgo).
const FLOOR_PATCH_GROUP := &"theme_floor_patches"
const FLOOR_RUNE_GROUP := &"theme_floor_runes"

## Estandartes o emblemas por sala.
const WALL_ITEMS_PER_ROOM := 1
## Distancia mínima (en celdas, sobre la misma fila) entre un objeto de pared y
## una antorcha u otro objeto de pared.
const WALL_ITEM_SPACING := 2
## Probabilidad de una mancha de suelo por sala.
const FLOOR_PATCH_CHANCE := 0.6
## Piedritas por sala (entre 0 y este valor).
const SCATTER_PER_ROOM_MAX := 3
const SCATTER_VARIANTS := 3
## Probabilidad de un objeto grande por sala (nunca en la sala de inicio).
const PROP_CHANCE := 0.5
## Distancia de tablero mínima entre un objeto grande y cualquier celda
## reservada, y entre dos objetos grandes.
const PROP_CLEARANCE := 2
const PROP_SPACING := 3
## Distancia de tablero máxima entre la runa y la llave.
const RUNE_MAX_DISTANCE := 2
## Tamaño de la colisión del objeto grande (una celda, un poco menor para no
## enganchar al jugador en las esquinas).
const PROP_COLLISION_SIZE := Vector2(12, 12)
## Capa de colisión de las paredes del tileset (physics_layer_0).
const WALL_COLLISION_LAYER := 1


## Un objeto decorativo en una celda. variant elige la piedrita (0..2).
class Item extends RefCounted:
	var kind: StringName
	var cell: Vector2i
	var variant := 0

	func _init(p_kind: StringName, p_cell: Vector2i, p_variant: int = 0) -> void:
		kind = p_kind
		cell = p_cell
		variant = p_variant


## Resultado de plan(): objetos de pared y de suelo.
class Plan extends RefCounted:
	var wall_items: Array[Item] = []
	var floor_items: Array[Item] = []

	## Celdas con colisión (solo los objetos grandes).
	func blocking_cells() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for item in floor_items:
			if item.kind == ThemeDecor.PROP:
				out.append(item.cell)
		return out

	func all_items() -> Array[Item]:
		var out: Array[Item] = []
		out.append_array(wall_items)
		out.append_array(floor_items)
		return out


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

## SpriteFrames de las antorchas del tema, o null para el calabozo original
## (LevelBuilder usa entonces Torch.tscn tal cual).
static func torch_frames(theme: StringName) -> SpriteFrames:
	if not DungeonTheme.is_custom(theme):
		return null
	return load(DungeonTheme.asset_path(theme, "torch", "_frames.tres"))


## Aplica el tema a la escena del nivel ya construida por LevelBuilder: cambia
## el tileset del mapa y del fondo y agrega la decoración a Decor. Con el tema
## original no hace nada. extra_reserved son celdas que la decoración tiene que
## dejar libres además de las del mapa (p. ej. las monedas sueltas).
static func apply(root: Node2D, layout: LevelGenerator.Layout, theme: StringName,
		seed_value: int, extra_reserved: Array[Vector2i] = []) -> void:
	if not DungeonTheme.is_custom(theme):
		return
	var dungeon: TileMapLayer = root.get_node("Dungeon")
	var themed := DungeonTheme.themed_tile_set(dungeon.tile_set, theme)
	dungeon.tile_set = themed
	var background := root.get_node_or_null("Background/Floor") as TileMapLayer
	if background != null:
		background.tile_set = themed
	var decor_plan := plan(layout, seed_value, extra_reserved)
	build(root.get_node("Decor"), decor_plan, theme, Vector2(dungeon.tile_set.tile_size))


## Celdas que ningún objeto puede ocupar: inicio, llave, las dos de la puerta,
## enemigos con todo el recorrido de su patrulla, jefe, trampas y extra.
static func reserved_cells(layout: LevelGenerator.Layout,
		extra: Array[Vector2i] = []) -> Dictionary:
	var reserved := {layout.player_cell: true, layout.key_cell: true}
	for cell in layout.door_floor_cells():
		reserved[cell] = true
	for spawn in layout.enemies:
		reserved[spawn.cell] = true
		var length := maxi(absi(spawn.patrol.x), absi(spawn.patrol.y))
		var dir := Vector2i(signi(spawn.patrol.x), signi(spawn.patrol.y))
		for step in range(1, length + 1):
			reserved[spawn.cell + dir * step] = true
	for spawn in layout.hazards:
		reserved[spawn.cell] = true
	if layout.boss != null:
		reserved[layout.boss.cell] = true
	for cell in extra:
		reserved[cell] = true
	return reserved


## Decide qué objeto va en cada celda. Determinista con seed_value.
static func plan(layout: LevelGenerator.Layout, seed_value: int,
		extra_reserved: Array[Vector2i] = []) -> Plan:
	var result := Plan.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var reserved := reserved_cells(layout, extra_reserved)
	var used := {}
	var wall_used: Array[Vector2i] = layout.torches.duplicate()
	var props: Array[Vector2i] = []

	for i in layout.rooms.size():
		var room := layout.rooms[i]
		_plan_wall_items(layout, room, rng, reserved, wall_used, result)

		var cells := _free_room_cells(layout, room, reserved)
		_shuffle(cells, rng)
		# La arena del jefe queda sin objetos grandes que estorben la pelea.
		var is_arena := layout.boss != null and i == layout.exit_room
		if i != layout.start_room and not is_arena and rng.randf() < PROP_CHANCE:
			for cell in cells:
				if _is_prop_cell(layout, cell, reserved, props):
					props.append(cell)
					_add_floor(result, used, Item.new(PROP, cell))
					break
		if i == layout.key_room:
			for cell in cells:
				var d := cell - layout.key_cell
				if not used.has(cell) and maxi(absi(d.x), absi(d.y)) <= RUNE_MAX_DISTANCE:
					_add_floor(result, used, Item.new(FLOOR_RUNE, cell))
					break
		if rng.randf() < FLOOR_PATCH_CHANCE:
			var cell := _next_free(cells, used)
			if cell != LevelBuilder.NO_TILE:
				_add_floor(result, used, Item.new(FLOOR_PATCH, cell))
		for _n in rng.randi_range(0, SCATTER_PER_ROOM_MAX):
			var cell := _next_free(cells, used)
			if cell == LevelBuilder.NO_TILE:
				break
			_add_floor(result, used, Item.new(SCATTER, cell, rng.randi_range(0, SCATTER_VARIANTS - 1)))
	return result


## Pared frontal donde puede ir un objeto de pared: pared recta con suelo
## debajo (el tile es el frontal) y fuera de la puerta y su marco.
static func is_front_wall(layout: LevelGenerator.Layout, cell: Vector2i) -> bool:
	if layout.is_floor(cell) or not layout.is_wall(cell):
		return false
	if layout.is_floor(cell + Vector2i(-1, 0)) or layout.is_floor(cell + Vector2i(1, 0)):
		return false
	if not layout.is_floor(cell + Vector2i(0, 1)):
		return false
	var door_wall_y := layout.door_cell.y - 1
	return not (cell.y == door_wall_y and cell.x >= layout.door_cell.x - 1 and cell.x <= layout.door_cell.x + 2)


## Crea los nodos del plan dentro de decor_root. Los de suelo van primero para
## quedar dibujados debajo de los objetos grandes.
static func build(decor_root: Node, decor_plan: Plan, theme: StringName, tile_size: Vector2) -> void:
	for item in decor_plan.floor_items:
		decor_root.add_child(_make_item(item, theme, tile_size))
	for item in decor_plan.wall_items:
		decor_root.add_child(_make_item(item, theme, tile_size))


# ---------------------------------------------------------------------------
# Colocación
# ---------------------------------------------------------------------------

static func _plan_wall_items(layout: LevelGenerator.Layout, room: Rect2i,
		rng: RandomNumberGenerator, reserved: Dictionary, wall_used: Array[Vector2i],
		result: Plan) -> void:
	var y := room.position.y - 1
	var xs: Array[int] = []
	for x in range(room.position.x, room.end.x):
		var cell := Vector2i(x, y)
		if is_front_wall(layout, cell) and not reserved.has(cell):
			xs.append(x)
	_shuffle(xs, rng)
	var placed := 0
	for x in xs:
		if placed >= WALL_ITEMS_PER_ROOM:
			break
		var cell := Vector2i(x, y)
		if not _is_wall_spaced(cell, wall_used):
			continue
		var kind := BANNER if rng.randi_range(0, 1) == 0 else EMBLEM
		result.wall_items.append(Item.new(kind, cell))
		wall_used.append(cell)
		placed += 1


static func _is_wall_spaced(cell: Vector2i, wall_used: Array[Vector2i]) -> bool:
	for other in wall_used:
		if other.y == cell.y and absi(other.x - cell.x) < WALL_ITEM_SPACING:
			return false
	return true


## Celdas de suelo libres de la sala, en orden de lectura.
static func _free_room_cells(layout: LevelGenerator.Layout, room: Rect2i,
		reserved: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			var cell := Vector2i(x, y)
			if layout.is_floor(cell) and not reserved.has(cell):
				out.append(cell)
	return out


## Un objeto grande solo va en una celda rodeada de suelo, lejos de todo lo
## reservado, de la puerta y de los otros objetos grandes. Así su anillo de
## 8 vecinos queda libre y siempre se puede rodear: no corta ningún camino.
static func _is_prop_cell(layout: LevelGenerator.Layout, cell: Vector2i,
		reserved: Dictionary, props: Array[Vector2i]) -> bool:
	if not layout.is_interior(cell):
		return false
	for other in reserved:
		if _board_distance(cell, other) < PROP_CLEARANCE:
			return false
	for door_cell in layout.door_floor_cells():
		if _board_distance(cell, door_cell) <= LevelGenerator.DOOR_CLEAR_RADIUS:
			return false
	for other in props:
		if _board_distance(cell, other) < PROP_SPACING:
			return false
	return true


static func _next_free(cells: Array[Vector2i], used: Dictionary) -> Vector2i:
	for cell in cells:
		if not used.has(cell):
			return cell
	return LevelBuilder.NO_TILE


static func _add_floor(result: Plan, used: Dictionary, item: Item) -> void:
	result.floor_items.append(item)
	used[item.cell] = true


static func _board_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Baraja con el generador dado (Array.shuffle() usa el global y rompería el
## determinismo), igual que LevelGenerator.
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


# ---------------------------------------------------------------------------
# Nodos
# ---------------------------------------------------------------------------

static func _make_item(item: Item, theme: StringName, tile_size: Vector2) -> Node2D:
	var position := (Vector2(item.cell) + Vector2(0.5, 0.5)) * tile_size
	if item.kind == PROP:
		return _make_prop(theme, position)
	var node: Node2D
	if item.kind == SCATTER:
		node = _make_scatter(theme, item.variant, tile_size)
	else:
		node = _make_visual(theme, item.kind)
	node.position = position
	if item.kind == FLOOR_PATCH:
		node.add_to_group(FLOOR_PATCH_GROUP)
	elif item.kind == FLOOR_RUNE:
		node.add_to_group(FLOOR_RUNE_GROUP)
	return node


## Animado si el pack trae SpriteFrames; si no, la imagen fija.
static func _make_visual(theme: StringName, kind: StringName) -> Node2D:
	var frames_path := DungeonTheme.asset_path(theme, kind, "_frames.tres")
	if ResourceLoader.exists(frames_path):
		var animated := AnimatedSprite2D.new()
		animated.sprite_frames = load(frames_path)
		animated.animation = ANIMATION
		animated.autoplay = ANIMATION
		return animated
	var sprite := Sprite2D.new()
	sprite.texture = load(DungeonTheme.asset_path(theme, kind))
	return sprite


## Una de las variantes de la tira de piedritas.
static func _make_scatter(theme: StringName, variant: int, tile_size: Vector2) -> Sprite2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(DungeonTheme.asset_path(theme, SCATTER))
	atlas.region = Rect2(Vector2(variant * tile_size.x, 0), tile_size)
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	return sprite


## Objeto grande: cuerpo estático en la capa de las paredes con el sprite.
static func _make_prop(theme: StringName, position: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = position
	body.collision_layer = WALL_COLLISION_LAYER
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = PROP_COLLISION_SIZE
	shape.shape = rect
	body.add_child(shape)
	body.add_child(_make_visual(theme, PROP))
	return body
