@tool
class_name LevelBuilder
extends RefCounted
## Dibuja un mapa generado (LevelGenerator.Layout) dentro de la escena del
## nivel: pinta los tiles de suelo y pared y crea las escenas de enemigos,
## trampas y antorchas. No decide nada del mapa, solo lo traduce a nodos.
##
## Reutiliza los nodos que ya trae Level.tscn (Dungeon, Props, Decor, Traps,
## Enemies, Player, Key y ExitDoor): borra el contenido hecho a mano y coloca
## de nuevo esos mismos nodos. El jugador, la interfaz, el fondo y la cámara no
## se tocan.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

const SOURCE_ID := 0
const NO_TILE := Vector2i(-1, -1)

## Tiles del atlas usados por el mapa hecho a mano.
const FLOOR_TILE := Vector2i(1, 1)
## Pared frontal: tiene suelo debajo.
const WALL_TOP := Vector2i(2, 0)
## Borde inferior: tiene suelo arriba.
const WALL_BOTTOM := Vector2i(2, 4)
## Pared lateral izquierda: tiene suelo a la derecha.
const WALL_LEFT := Vector2i(0, 2)
## Pared lateral derecha: tiene suelo a la izquierda.
const WALL_RIGHT := Vector2i(5, 2)
## Esquinas exteriores, nombradas por el lado del mapa donde quedan.
const CORNER_TOP_LEFT := Vector2i(0, 0)
const CORNER_TOP_RIGHT := Vector2i(5, 0)
const CORNER_BOTTOM_LEFT := Vector2i(0, 4)
const CORNER_BOTTOM_RIGHT := Vector2i(5, 4)
## Esquinas interiores (fila 5 del atlas): borde inferior que se une con una
## pared lateral que sigue hacia abajo. Nombradas por los lados con suelo.
## Suelo arriba y a la derecha: lo oscuro queda abajo a la izquierda.
const INNER_NORTH_EAST := Vector2i(5, 5)
## Suelo arriba y a la izquierda: lo oscuro queda abajo a la derecha.
const INNER_NORTH_WEST := Vector2i(0, 5)

const ENEMY_SCENES := {
	LevelGenerator.SKELETON: preload("res://scenes/Skeleton.tscn"),
	LevelGenerator.VAMPIRE: preload("res://scenes/Vampire.tscn"),
	LevelGenerator.REAPER: preload("res://scenes/Reaper.tscn"),
	LevelGenerator.SKULL: preload("res://scenes/Skull.tscn"),
}
const SPIKE_TRAP_SCENE := preload("res://scenes/SpikeTrap.tscn")
const TORCH_SCENE := preload("res://scenes/props/Torch.tscn")


## Reemplaza el contenido del nivel por el del mapa generado. root es la
## escena Level; se llama desde su _ready, antes de que registre a los enemigos.
func build(root: Node2D, layout: LevelGenerator.Layout) -> void:
	var dungeon: TileMapLayer = root.get_node("Dungeon")
	var tile_size := Vector2(dungeon.tile_set.tile_size)

	_clear_handmade_content(root)
	_paint_tiles(dungeon, layout)

	var player: Node2D = root.get_node("Player")
	player.position = _cell_center(layout.player_cell, tile_size)
	var key: Node2D = root.get_node("Key")
	key.position = _cell_center(layout.key_cell, tile_size)
	root.get_node("ExitDoor").position = door_position(layout, tile_size)

	var enemies_root: Node = root.get_node("Enemies")
	for spawn in layout.enemies:
		enemies_root.add_child(_make_enemy(spawn, tile_size))
	var traps_root: Node = root.get_node("Traps")
	for spawn in layout.hazards:
		traps_root.add_child(_make_trap(spawn, tile_size))
	var decor_root: Node = root.get_node("Decor")
	for cell in layout.torches:
		var torch: Node2D = TORCH_SCENE.instantiate()
		torch.position = _cell_center(cell, tile_size)
		decor_root.add_child(torch)


## Tile de una celda de pared, o NO_TILE si la celda no es pared.
##
## Se resuelve solo por los vecinos, igual en salas y corredores: la mitad
## oscura de cada tile (el vacío de afuera) nunca puede quedar mirando al suelo.
## Así las uniones entre corredor y sala y los codos de los corredores siguen
## la pared sin cortes. Como ya no quedan paredes finas, una celda tiene suelo
## a lo sumo en dos lados contiguos.
static func wall_tile_for(layout: LevelGenerator.Layout, cell: Vector2i) -> Vector2i:
	if not layout.is_wall(cell):
		return NO_TILE
	var n := layout.is_floor(cell + Vector2i(0, -1))
	var s := layout.is_floor(cell + Vector2i(0, 1))
	var w := layout.is_floor(cell + Vector2i(-1, 0))
	var e := layout.is_floor(cell + Vector2i(1, 0))
	# La pared frontal no tiene mitad oscura: sirve también cuando además hay
	# suelo a un lado (la celda sobre la boca de un corredor).
	if s:
		return WALL_TOP
	if n:
		# Suelo arriba y a un lado: el borde inferior gira y sigue como pared
		# lateral hacia abajo (la celda bajo la boca de un corredor).
		if e:
			return INNER_NORTH_EAST
		if w:
			return INNER_NORTH_WEST
		return WALL_BOTTOM
	if w:
		return WALL_RIGHT
	if e:
		return WALL_LEFT
	# Sin vecinos directos: solo toca suelo en una diagonal, es una esquina.
	if layout.is_floor(cell + Vector2i(1, 1)):
		return CORNER_TOP_LEFT
	if layout.is_floor(cell + Vector2i(-1, 1)):
		return CORNER_TOP_RIGHT
	if layout.is_floor(cell + Vector2i(1, -1)):
		return CORNER_BOTTOM_LEFT
	return CORNER_BOTTOM_RIGHT


## Posición de la puerta de salida: centrada en las dos celdas de pared que
## quedan sobre las celdas de suelo de layout.door_cell.
static func door_position(layout: LevelGenerator.Layout, tile_size: Vector2) -> Vector2:
	return Vector2((layout.door_cell.x + 1) * tile_size.x, layout.door_cell.y * tile_size.y - tile_size.y / 2.0)


## Quita todo lo que el mapa hecho a mano dejó en la escena. Los nodos se
## liberan al instante (no con queue_free) para que ya no estén en el grupo
## "enemies" cuando el nivel cuente a los enemigos.
func _clear_handmade_content(root: Node) -> void:
	root.get_node("Dungeon").clear()
	root.get_node("Props").clear()
	for container_name in ["Decor", "Traps", "Enemies"]:
		var container: Node = root.get_node(container_name)
		for child in container.get_children():
			container.remove_child(child)
			child.free()


func _paint_tiles(dungeon: TileMapLayer, layout: LevelGenerator.Layout) -> void:
	for y in layout.size.y:
		for x in layout.size.x:
			var cell := Vector2i(x, y)
			if layout.is_floor(cell):
				dungeon.set_cell(cell, SOURCE_ID, FLOOR_TILE)
			else:
				var tile := wall_tile_for(layout, cell)
				if tile != NO_TILE:
					dungeon.set_cell(cell, SOURCE_ID, tile)


func _make_enemy(spawn: LevelGenerator.Spawn, tile_size: Vector2) -> Node2D:
	var enemy: Node2D = ENEMY_SCENES[spawn.kind].instantiate()
	# La posición se asigna antes de entrar al árbol: el esqueleto y los
	# perseguidores toman su punto de partida en _ready.
	enemy.position = _cell_center(spawn.cell, tile_size)
	if spawn.kind == LevelGenerator.SKELETON:
		enemy.set("patrol_offset", Vector2(spawn.patrol) * tile_size)
	return enemy


func _make_trap(spawn: LevelGenerator.Spawn, tile_size: Vector2) -> Node2D:
	var trap: Node2D = SPIKE_TRAP_SCENE.instantiate()
	trap.position = _cell_center(spawn.cell, tile_size)
	trap.set("start_frame", spawn.frame)
	return trap


static func _cell_center(cell: Vector2i, tile_size: Vector2) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * tile_size
