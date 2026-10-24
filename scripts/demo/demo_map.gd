@tool
class_name DemoMap
extends RefCounted
## Mapa hecho a mano de la demo: una fila de salas unidas por corredores, de
## izquierda a derecha, cada una pensada para enseñar una sola cosa. Es lógica
## pura (como LevelGenerator): arma un LevelGenerator.Layout que LevelBuilder
## dibuja igual que un mapa generado, más lo propio de la demo (rejas entre
## salas, armas en el suelo, corazones, punto de control y textos de ayuda).
## DemoLevel lo convierte en nodos.
##
## Orden de las salas:
##   0 Entrada            moverse y atacar contra dos esqueletos
##   1 Pasillo de arqueros esquivar flechas y romperlas con la espada
##   2 Sala del mago      devolverle el orbe dorado
##   3 Tesoro falso       un cofre que es un mímico
##   4 Armería            elegir lanza o daga
##   5 Antesala (lava)    probar el arma, corazones y punto de control
##   6 Arena (lava)       el Forjador de magma; la llave abre la salida
##
## Entre una sala y la siguiente hay una reja (gates[i] separa la sala i de la
## i + 1) que se abre al vencer a los enemigos de la sala i, o al elegir un arma
## en la armería. Como el mapa es una sola fila, las rejas hacen el recorrido
## lineal: no se puede llegar al jefe sin pasar por todas las salas.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

## Cómo se abre la reja de salida de una sala.
const CLEAR_BY_ENEMIES := &"enemies"
const CLEAR_BY_WEAPON := &"weapon"
## La arena no tiene reja de salida: la salida es la puerta con llave.
const CLEAR_BY_BOSS := &"boss"

const SIZE := Vector2i(116, 20)
## Fila superior de los corredores (tienen 2 celdas de alto).
const CORRIDOR_Y := 9
## Desde esta columna el mapa usa el tema de lava (el del Forjador).
const LAVA_FROM_X := 80
## Columna de la reja dentro del corredor, contada desde la pared de la sala.
const GATE_OFFSET := 1

## Ids de las armas de la armería.
const ARMORY_WEAPONS: Array[StringName] = [&"spear", &"dagger"]


## Una sala de la demo.
class Room extends RefCounted:
	var id: StringName
	## Suelo de la sala, en celdas.
	var rect: Rect2i
	## Ayuda que aparece al entrar por primera vez (corta, en imperativo).
	var hint: String
	var theme: StringName
	## Cómo se abre su reja de salida (CLEAR_BY_*).
	var clear_by: StringName
	## Celda donde reaparece el jugador si cae después de entrar acá.
	var respawn_cell: Vector2i

	func _init(p_id: StringName, p_rect: Rect2i, p_hint: String, p_theme: StringName,
			p_clear_by: StringName) -> void:
		id = p_id
		rect = p_rect
		hint = p_hint
		theme = p_theme
		clear_by = p_clear_by
		# Por defecto, justo al entrar desde el corredor de la izquierda.
		respawn_cell = Vector2i(rect.position.x + 1, CORRIDOR_Y)


var layout: LevelGenerator.Layout
var rooms: Array[Room] = []
## Celda superior de cada reja; ocupa esa celda y la de abajo (el corredor).
var gates: Array[Vector2i] = []
## Armas en el suelo: id -> celda.
var weapon_cells: Dictionary[StringName, Vector2i] = {}
var heart_cells: Array[Vector2i] = []
## Monedas de cebo alrededor del mímico.
var coin_cells: Array[Vector2i] = []
## Vela del punto de control, antes del jefe.
var checkpoint_cell := Vector2i.ZERO
## Abismos (Pit) en celdas: partes del recorrido que se pasan saltando (K).
## Los de la parte de lava se dibujan como lava.
var pit_rects: Array[Rect2i] = []
## Carteles en la pared: celda -> texto corto que explica la mecánica de ese
## tramo (salto, coyote time, picos, parry).
var signs: Dictionary[Vector2i, String] = {}
## Estandartes del calabozo original (en la pared frontal de algunas salas).
var banner_cells: Array[Vector2i] = []


## Arma el mapa completo de la demo. Siempre es el mismo.
static func create() -> DemoMap:
	var map := DemoMap.new()
	map._build()
	return map


## Índice de la sala que contiene cell, o -1 si cell no está en ninguna (un
## corredor o fuera del mapa).
func room_at(cell: Vector2i) -> int:
	for i in rooms.size():
		if rooms[i].rect.has_point(cell):
			return i
	return -1


func room_index(id: StringName) -> int:
	for i in rooms.size():
		if rooms[i].id == id:
			return i
	return -1


## Las dos celdas de la reja index.
func gate_cells(index: int) -> Array[Vector2i]:
	return [gates[index], gates[index] + Vector2i(0, 1)]


## Tema de la celda: lava desde LAVA_FROM_X, el calabozo original antes.
func theme_at(cell: Vector2i) -> StringName:
	return DungeonTheme.LAVA if cell.x >= LAVA_FROM_X else DungeonTheme.DUNGEON


## Salas a las que se llega a pie desde el inicio con las primeras open_gates
## rejas abiertas (las demás cerradas), de menor a mayor.
func reachable_rooms(open_gates: int) -> Array[int]:
	var blocked := {}
	for i in range(open_gates, gates.size()):
		for cell in gate_cells(i):
			blocked[cell] = true
	var seen := {layout.player_cell: true}
	var queue: Array[Vector2i] = [layout.player_cell]
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for dir in LevelGenerator.DIRS4:
			var next: Vector2i = current + dir
			if layout.is_floor(next) and not blocked.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	var out: Array[int] = []
	for i in rooms.size():
		if seen.has(rooms[i].rect.get_center()):
			out.append(i)
	return out


func _build() -> void:
	rooms = [
		Room.new(&"entrance", Rect2i(2, 5, 12, 10),
				"Ataca con Espacio, salta con K", DungeonTheme.DUNGEON, CLEAR_BY_ENEMIES),
		Room.new(&"archers", Rect2i(18, 6, 16, 8),
				"Parry con L: devuelve las flechas", DungeonTheme.DUNGEON, CLEAR_BY_ENEMIES),
		Room.new(&"mage", Rect2i(38, 4, 13, 12),
				"Salta los picos, devuelve el orbe", DungeonTheme.DUNGEON, CLEAR_BY_ENEMIES),
		Room.new(&"mimic", Rect2i(55, 6, 9, 8),
				"Ese cofre se movió…", DungeonTheme.DUNGEON, CLEAR_BY_ENEMIES),
		Room.new(&"armory", Rect2i(68, 6, 10, 8),
				"Elige tu arma: lanza o daga", DungeonTheme.DUNGEON, CLEAR_BY_WEAPON),
		Room.new(&"antechamber", Rect2i(82, 5, 12, 10),
				"Prueba tu nueva arma aquí", DungeonTheme.LAVA, CLEAR_BY_ENEMIES),
		Room.new(&"arena", Rect2i(98, 3, 15, 14),
				"Esquiva el martillo y contraataca", DungeonTheme.LAVA, CLEAR_BY_BOSS),
	]
	layout = LevelGenerator.Layout.new(SIZE)
	layout.level = 1
	for room in rooms:
		layout.rooms.append(room.rect)
		layout.carve_rect(room.rect)
	# Corredores de 2 celdas entre salas vecinas, con su reja.
	for i in rooms.size() - 1:
		var from_x := rooms[i].rect.end.x
		var to_x := rooms[i + 1].rect.position.x
		layout.carve_rect(Rect2i(from_x, CORRIDOR_Y, to_x - from_x, 2))
		layout.links.append(Vector2i(i, i + 1))
		gates.append(Vector2i(from_x + GATE_OFFSET, CORRIDOR_Y))

	layout.start_room = 0
	layout.exit_room = rooms.size() - 1
	layout.player_cell = Vector2i(4, CORRIDOR_Y)
	# Puerta de salida en la pared superior de la arena, sobre el jefe.
	layout.door_cell = Vector2i(104, 3)

	var entrance_skeleton := _add_enemy(LevelGenerator.SKELETON, Vector2i(9, 7))
	entrance_skeleton.patrol = Vector2i(2, 0)
	var second_skeleton := _add_enemy(LevelGenerator.SKELETON, Vector2i(10, 12))
	second_skeleton.patrol = Vector2i(-2, 0)
	_add_enemy(LevelGenerator.ARCHER, Vector2i(31, 10))
	_add_enemy(LevelGenerator.MAGE, Vector2i(47, 9))
	_add_enemy(LevelGenerator.MIMIC, Vector2i(61, 10))
	_add_enemy(LevelGenerator.VAMPIRE, Vector2i(89, 7))
	_add_enemy(LevelGenerator.SKULL_TURRET, Vector2i(91, 13))

	# El Forjador espera en el centro de la arena y guarda la llave (BossFight).
	layout.boss = LevelGenerator.Spawn.new(BossRegistry.FORGE, Vector2i(105, 9))
	layout.key_cell = layout.boss.cell
	layout.key_room = layout.exit_room

	_add_feel_sections()

	weapon_cells = {ARMORY_WEAPONS[0]: Vector2i(71, 8), ARMORY_WEAPONS[1]: Vector2i(74, 8)}
	coin_cells = [Vector2i(60, 8), Vector2i(62, 12), Vector2i(59, 11)]
	heart_cells = [Vector2i(84, 6), Vector2i(84, 13)]
	checkpoint_cell = Vector2i(92, 8)
	# Antes del jefe se reaparece en la vela, también si se cae en la arena.
	rooms[room_index(&"arena")].respawn_cell = checkpoint_cell + Vector2i(0, 1)
	banner_cells = [Vector2i(7, 4), Vector2i(72, 5)]

	# Dos antorchas en la pared frontal de cada sala.
	for room in rooms:
		var y := room.rect.position.y - 1
		layout.torches.append(Vector2i(room.rect.position.x + 2, y))
		layout.torches.append(Vector2i(room.rect.end.x - 3, y))


## Tramos donde se usan las mecánicas de game feel (ver "Game feel" en el
## README): cada uno se pasa con el salto, el coyote time o el parry.
func _add_feel_sections() -> void:
	pit_rects = [
		# Entrada: el primer abismo. Se salta o se rodea por abajo.
		Rect2i(8, 5, 1, 7),
		# Pasillo entrada -> arqueros: corta el pasillo, hay que saltar.
		Rect2i(16, CORRIDOR_Y, 1, 2),
		# Pasillo arqueros -> mago: 2 celdas, justo lo que cubre un salto.
		# Saltando antes del borde no se llega; el coyote time deja saltar
		# un poco después de pisar el hueco.
		Rect2i(36, CORRIDOR_Y, 2, 2),
		# Antesala de lava: una zanja de lado a lado.
		Rect2i(86, 5, 1, 10),
	]
	# Sala del mago: una fila de picos de pared a pared, todos al mismo ritmo.
	# Se pasa saltando (en el aire no lastiman) o esperando a que bajen.
	for y in range(4, 16):
		layout.hazards.append(LevelGenerator.Spawn.new(LevelGenerator.SPIKES, Vector2i(43, y)))
	signs = {
		Vector2i(16, CORRIDOR_Y - 1): "K: saltar",
		Vector2i(23, 5): "L: parry",
		Vector2i(36, CORRIDOR_Y - 1): "Salta al borde",
		Vector2i(43, 3): "Salta los picos",
		Vector2i(86, 4): "¡Salta la lava!",
	}


## Celdas de todos los abismos.
func pit_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for rect in pit_rects:
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				cells.append(Vector2i(x, y))
	return cells


func _add_enemy(kind: StringName, cell: Vector2i) -> LevelGenerator.Spawn:
	var spawn := LevelGenerator.Spawn.new(kind, cell)
	layout.enemies.append(spawn)
	return spawn
