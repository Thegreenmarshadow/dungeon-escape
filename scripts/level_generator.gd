@tool
class_name LevelGenerator
extends RefCounted
## Generador procedural de mapas de mazmorra (niveles 2 en adelante).
##
## Es lógica pura: trabaja con una grilla de celdas y no crea nodos ni escenas,
## así se puede probar con miles de semillas. Un nivel es una función
## determinista de (semilla de la partida, número de nivel): con los mismos dos
## valores siempre sale el mismo mapa. Quien lo dibuja es LevelBuilder.
##
## Pasos de un intento:
##   1. Salas rectangulares al azar, sin solaparse.
##   2. Corredores en L de 2 celdas siguiendo un árbol de expansión mínimo, más
##      algunos lazos extra para que haya más de un camino.
##   3. Sala de inicio y sala de salida (la más lejana por camino real).
##   4. Llave, jefes, enemigos, trampas y antorchas.
##   5. Validación de invariantes. Si falla, se reintenta con la siguiente
##      semilla derivada; agotados los intentos se usa un diseño simple y
##      garantizado.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

# ---------------------------------------------------------------------------
# Configuración. Todos los números de balance y de forma están acá.
# ---------------------------------------------------------------------------

## Primer nivel generado; el nivel 1 es el mapa hecho a mano.
const FIRST_GENERATED_LEVEL := 2
## Nivel desde el que aparece la parca que guarda la salida.
const BOSS_FIRST_LEVEL := 3
## Nivel desde el que una segunda parca guarda la llave.
const SECOND_BOSS_LEVEL := 6

## Tamaño de la grilla en celdas (nivel 2) y cuánto crece por nivel.
const GRID_BASE := Vector2i(44, 30)
const GRID_GROWTH := Vector2i(5, 3)
const GRID_MAX := Vector2i(96, 64)

## Salas: cantidad inicial (más una por nivel) y tope.
const ROOM_COUNT_BASE := 5
const ROOM_COUNT_MAX := 12
## Tamaño de las salas en celdas: mínimo fijo, máximo que crece con el nivel.
const ROOM_SIZE_MIN := Vector2i(6, 6)
const ROOM_SIZE_MAX_BASE := Vector2i(8, 7)
const ROOM_SIZE_MAX_CAP := Vector2i(15, 12)
## Corredores extra (lazos) además del árbol que conecta todas las salas.
const EXTRA_LINKS_MAX := 4

## Enemigos comunes (sin contar jefes): base, aumento por nivel y tope.
const ENEMIES_BASE := 6
const ENEMIES_PER_LEVEL := 2
const ENEMIES_MAX := 24
## Proporción de perseguidores (vampiros) entre los enemigos comunes.
const CHASER_SHARE_BASE := 0.3
const CHASER_SHARE_PER_LEVEL := 0.07
const CHASER_SHARE_MAX := 0.7
## Trampas de picos.
const HAZARDS_BASE := 5
const HAZARDS_PER_LEVEL := 1
const HAZARDS_MAX := 18

# ---------------------------------------------------------------------------
# Reglas de forma y de colocación
# ---------------------------------------------------------------------------

const MAX_ATTEMPTS := 24
const MIN_ROOMS := 4
## Celdas vacías mínimas entre dos salas.
const ROOM_SPACING := 3
const ROOM_PLACEMENT_TRIES := 40
const CORRIDOR_WIDTH := 2
## Ningún enemigo ni trampa a menos de estas celdas del inicio del jugador.
const SPAWN_SAFE_RADIUS := 9.0
## Alrededor de la puerta se deja libre este radio (en celdas).
const DOOR_CLEAR_RADIUS := 2
## Separación mínima (distancia de tablero, en celdas) entre entidades.
const ENEMY_SPACING := 3
const HAZARD_SPACING := 2
## Largo de la patrulla de un esqueleto, en celdas.
const PATROL_MIN := 3
const PATROL_MAX := 7
## Distancia de la parca a su punto de guardia (puerta o llave), en celdas.
const BOSS_DISTANCE_MIN := 3.0
const BOSS_DISTANCE_MAX := 8.0
const TORCHES_PER_ROOM := 2
const TORCH_SPACING := 3
## Camino mínimo (en celdas) entre el inicio y la puerta.
const MIN_EXIT_PATH := 20
## Si se colocan menos enemigos que esta fracción de los pedidos, el intento
## se descarta.
const MIN_ENEMY_RATIO := 0.5
## Diseño de emergencia: tres salas en fila.
const FALLBACK_SIZE := Vector2i(40, 16)
const FALLBACK_ROOMS: Array[Rect2i] = [
	Rect2i(2, 4, 8, 8), Rect2i(16, 4, 8, 8), Rect2i(30, 4, 8, 8),
]

## Tipos de entidad que el generador coloca (LevelBuilder los traduce a escenas).
const SKELETON := &"skeleton"
const VAMPIRE := &"vampire"
const REAPER := &"reaper"
const SPIKES := &"spikes"

const DIRS4: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## Dificultad de un nivel: todos los números que dependen del nivel.
class Params extends RefCounted:
	var level := 0
	var grid_size := Vector2i.ZERO
	var room_count := 0
	var room_min := Vector2i.ZERO
	var room_max := Vector2i.ZERO
	var extra_links := 0
	## Enemigos comunes, sin jefes.
	var enemy_count := 0
	var chaser_share := 0.0
	var boss_count := 0
	var hazard_count := 0


## Algo que el generador coloca en una celda: un enemigo o una trampa.
class Spawn extends RefCounted:
	var kind: StringName
	var cell: Vector2i
	## Desplazamiento de la patrulla en celdas (solo esqueletos). Cero = quieto.
	var patrol := Vector2i.ZERO
	## Frame inicial de la animación (solo trampas).
	var frame := 0

	func _init(p_kind: StringName, p_cell: Vector2i) -> void:
		kind = p_kind
		cell = p_cell


## Mapa generado: grilla de suelo y todo lo que hay que colocar encima.
## Las celdas que no son suelo son pared (si tocan suelo) o vacío.
class Layout extends RefCounted:
	var level := 0
	var seed_used := 0
	## Intento (0..MAX_ATTEMPTS-1) que pasó la validación; MAX_ATTEMPTS = diseño de emergencia.
	var attempt := 0
	var used_fallback := false
	var size := Vector2i.ZERO
	## Un byte por celda: 1 = suelo.
	var floor_cells := PackedByteArray()
	var rooms: Array[Rect2i] = []
	var links: Array[Vector2i] = []
	var start_room := -1
	var exit_room := -1
	var key_room := -1
	var player_cell := Vector2i.ZERO
	var key_cell := Vector2i.ZERO
	## Celda de suelo bajo la mitad izquierda de la puerta. La puerta ocupa dos
	## celdas de la pared superior de la sala de salida, justo encima.
	var door_cell := Vector2i.ZERO
	var enemies: Array[Spawn] = []
	var hazards: Array[Spawn] = []
	## Celdas de pared (fila superior de una sala) donde va una antorcha.
	var torches: Array[Vector2i] = []

	func _init(p_size: Vector2i) -> void:
		size = p_size
		floor_cells.resize(size.x * size.y)

	func in_bounds(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y

	func is_floor(c: Vector2i) -> bool:
		return in_bounds(c) and floor_cells[c.y * size.x + c.x] == 1

	func set_floor(c: Vector2i) -> void:
		if in_bounds(c):
			floor_cells[c.y * size.x + c.x] = 1

	## Convierte en suelo un rectángulo, sin tocar el borde de la grilla (ahí
	## tiene que quedar siempre pared).
	func carve_rect(rect: Rect2i) -> void:
		for y in range(maxi(rect.position.y, 1), mini(rect.end.y, size.y - 1)):
			for x in range(maxi(rect.position.x, 1), mini(rect.end.x, size.x - 1)):
				floor_cells[y * size.x + x] = 1

	## Pared: no es suelo pero toca suelo (incluidas las diagonales).
	func is_wall(c: Vector2i) -> bool:
		if is_floor(c):
			return false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if is_floor(c + Vector2i(dx, dy)):
					return true
		return false

	## Suelo rodeado de suelo en las 8 direcciones: cabe un cuerpo sin rozar paredes.
	func is_interior(c: Vector2i) -> bool:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not is_floor(c + Vector2i(dx, dy)):
					return false
		return true

	## Recorre la grilla buscando paredes finas: celdas de pared con suelo en
	## lados opuestos (arriba y abajo, izquierda y derecha, o en diagonales
	## enfrentadas). Con open = true las convierte en suelo. Devuelve cuántas
	## encontró. Accede al arreglo directamente porque es lo más costoso de la
	## generación; solo mira celdas interiores, el borde siempre es pared.
	func process_thin_walls(open: bool) -> int:
		var w := size.x
		var count := 0
		for y in range(1, size.y - 1):
			for x in range(1, w - 1):
				var i := y * w + x
				if floor_cells[i] == 1:
					continue
				var thin := (floor_cells[i - w] == 1 and floor_cells[i + w] == 1) \
						or (floor_cells[i - 1] == 1 and floor_cells[i + 1] == 1) \
						or (floor_cells[i - w + 1] == 1 and floor_cells[i + w - 1] == 1) \
						or (floor_cells[i - w - 1] == 1 and floor_cells[i + w + 1] == 1)
				if thin:
					count += 1
					if open:
						floor_cells[i] = 1
		return count

	func wall_cells() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for y in size.y:
			for x in size.x:
				if is_wall(Vector2i(x, y)):
					out.append(Vector2i(x, y))
		return out

	func room_center(index: int) -> Vector2i:
		return rooms[index].get_center()

	## Las dos celdas de suelo que detectan al jugador frente a la puerta.
	func door_floor_cells() -> Array[Vector2i]:
		return [door_cell, door_cell + Vector2i(1, 0)]

	## Rectángulo mínimo con todo el suelo.
	func floor_bounds() -> Rect2i:
		var min_c := size
		var max_c := Vector2i(-1, -1)
		for y in size.y:
			for x in size.x:
				if floor_cells[y * size.x + x] == 1:
					min_c = Vector2i(mini(min_c.x, x), mini(min_c.y, y))
					max_c = Vector2i(maxi(max_c.x, x), maxi(max_c.y, y))
		if max_c.x < 0:
			return Rect2i()
		return Rect2i(min_c, max_c - min_c + Vector2i.ONE)

	## Distancia en pasos (4 direcciones) desde origin a cada celda de suelo;
	## -1 donde no se llega. Se indexa con dist_at().
	func distances_from(origin: Vector2i) -> PackedInt32Array:
		var dist := PackedInt32Array()
		dist.resize(size.x * size.y)
		dist.fill(-1)
		if not is_floor(origin):
			return dist
		var queue: Array[Vector2i] = [origin]
		dist[origin.y * size.x + origin.x] = 0
		var head := 0
		while head < queue.size():
			var current := queue[head]
			head += 1
			var next_dist := dist[current.y * size.x + current.x] + 1
			for dir in LevelGenerator.DIRS4:
				var n := current + dir
				if is_floor(n) and dist[n.y * size.x + n.x] < 0:
					dist[n.y * size.x + n.x] = next_dist
					queue.append(n)
		return dist

	func dist_at(dist: PackedInt32Array, c: Vector2i) -> int:
		return dist[c.y * size.x + c.x] if in_bounds(c) else -1

	func summary() -> String:
		return "nivel %d: %d salas, %d enemigos, %d trampas, intento %d%s" % [
			level, rooms.size(), enemies.size(), hazards.size(), attempt,
			" (diseño de emergencia)" if used_fallback else ""]


# ---------------------------------------------------------------------------
# API pública
# ---------------------------------------------------------------------------

## Números de dificultad del nivel. Sube con el nivel: más y más grandes
## salas, más enemigos y una mayor proporción de perseguidores.
static func params_for_level(level: int) -> Params:
	var p := Params.new()
	p.level = level
	# Escalón de dificultad: 1 en el primer nivel generado.
	var step := maxi(level - FIRST_GENERATED_LEVEL + 1, 1)
	p.grid_size = Vector2i(
		mini(GRID_BASE.x + GRID_GROWTH.x * step, GRID_MAX.x),
		mini(GRID_BASE.y + GRID_GROWTH.y * step, GRID_MAX.y))
	p.room_count = mini(ROOM_COUNT_BASE + step, ROOM_COUNT_MAX)
	p.room_min = ROOM_SIZE_MIN
	p.room_max = Vector2i(
		mini(ROOM_SIZE_MAX_BASE.x + step, ROOM_SIZE_MAX_CAP.x),
		mini(ROOM_SIZE_MAX_BASE.y + step, ROOM_SIZE_MAX_CAP.y))
	p.extra_links = mini(1 + floori(step / 3.0), EXTRA_LINKS_MAX)
	p.enemy_count = mini(ENEMIES_BASE + ENEMIES_PER_LEVEL * step, ENEMIES_MAX)
	p.chaser_share = minf(CHASER_SHARE_BASE + CHASER_SHARE_PER_LEVEL * step, CHASER_SHARE_MAX)
	if level >= SECOND_BOSS_LEVEL:
		p.boss_count = 2
	elif level >= BOSS_FIRST_LEVEL:
		p.boss_count = 1
	p.hazard_count = mini(HAZARDS_BASE + HAZARDS_PER_LEVEL * step, HAZARDS_MAX)
	return p


## Semilla del intento dado. Mezcla los tres valores para que niveles e
## intentos contiguos no den mapas parecidos.
static func derive_seed(run_seed: int, level: int, attempt: int = 0) -> int:
	return _mix(_mix(_mix(run_seed) + level) + attempt)


## Genera el mapa del nivel. Nunca devuelve null: si ningún intento pasa la
## validación, devuelve el diseño de emergencia.
static func generate(level: int, run_seed: int) -> Layout:
	var params := params_for_level(level)
	for attempt in MAX_ATTEMPTS:
		var layout := _try_generate(params, derive_seed(run_seed, level, attempt))
		if layout != null:
			layout.attempt = attempt
			return layout
	var fallback := build_fallback(level, derive_seed(run_seed, level, MAX_ATTEMPTS))
	fallback.attempt = MAX_ATTEMPTS
	return fallback


## Diseño simple garantizado: tres salas en fila unidas por corredores rectos.
## Es público para poder probarlo directamente.
static func build_fallback(level: int, seed_value: int) -> Layout:
	var params := params_for_level(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var layout := Layout.new(FALLBACK_SIZE)
	layout.level = level
	layout.seed_used = seed_value
	layout.used_fallback = true
	for room in FALLBACK_ROOMS:
		layout.rooms.append(room)
		layout.carve_rect(room)
	for i in range(1, layout.rooms.size()):
		layout.links.append(Vector2i(i - 1, i))
		_carve_corridor(layout, layout.room_center(i - 1), layout.room_center(i), true)
	var error := _finish(layout, params, rng)
	if not error.is_empty():
		push_error("LevelGenerator: el diseño de emergencia no es válido: %s" % error)
	return layout


## Comprueba todas las invariantes del mapa. Devuelve "" si está bien o la
## descripción del primer problema encontrado.
static func validate(layout: Layout) -> String:
	var size := layout.size

	# Ningún suelo toca el borde de la grilla: siempre hay una pared afuera.
	for x in size.x:
		if layout.is_floor(Vector2i(x, 0)) or layout.is_floor(Vector2i(x, size.y - 1)):
			return "hay suelo en el borde de la grilla (columna %d)" % x
	for y in size.y:
		if layout.is_floor(Vector2i(0, y)) or layout.is_floor(Vector2i(size.x - 1, y)):
			return "hay suelo en el borde de la grilla (fila %d)" % y

	# No quedan paredes de una sola celda entre dos zonas de suelo.
	if layout.process_thin_walls(false) > 0:
		return "quedan paredes finas"

	if not layout.is_floor(layout.player_cell):
		return "el inicio del jugador no es suelo"
	var reach := layout.distances_from(layout.player_cell)

	# Puerta: suelo debajo, pared encima y alcanzable.
	for cell in layout.door_floor_cells():
		if not layout.is_floor(cell):
			return "la puerta no tiene suelo delante en %s" % str(cell)
		if layout.dist_at(reach, cell) < 0:
			return "la puerta es inalcanzable"
		if layout.is_floor(cell + Vector2i(0, -1)):
			return "la puerta no está sobre una pared en %s" % str(cell)
	if layout.dist_at(reach, layout.door_cell) < MIN_EXIT_PATH:
		return "la puerta queda demasiado cerca del inicio"

	# Llave.
	if not layout.is_floor(layout.key_cell):
		return "la llave no está sobre suelo"
	if layout.dist_at(reach, layout.key_cell) < 0:
		return "la llave es inalcanzable"

	# Todas las salas se alcanzan desde el inicio.
	for i in layout.rooms.size():
		if layout.dist_at(reach, layout.room_center(i)) < 0:
			return "la sala %d es inalcanzable" % i

	var occupied := {}
	for enemy in layout.enemies:
		var error := _validate_spawn(layout, reach, enemy)
		if not error.is_empty():
			return "enemigo %s: %s" % [enemy.kind, error]
		if occupied.has(enemy.cell):
			return "dos enemigos en la misma celda %s" % str(enemy.cell)
		occupied[enemy.cell] = true
		if enemy.kind != SKELETON and enemy.patrol != Vector2i.ZERO:
			return "solo los esqueletos patrullan"
		var error_patrol := _validate_patrol(layout, reach, enemy)
		if not error_patrol.is_empty():
			return "esqueleto en %s: %s" % [str(enemy.cell), error_patrol]
	for hazard in layout.hazards:
		var error := _validate_spawn(layout, reach, hazard)
		if not error.is_empty():
			return "trampa: %s" % error
		if hazard.frame < 0 or hazard.frame > 3:
			return "frame de trampa fuera de rango"
	for torch in layout.torches:
		if layout.is_floor(torch) or not layout.is_wall(torch):
			return "antorcha fuera de una pared en %s" % str(torch)
		if not layout.is_floor(torch + Vector2i(0, 1)):
			return "antorcha sin suelo debajo en %s" % str(torch)
	return ""


# ---------------------------------------------------------------------------
# Generación de un intento
# ---------------------------------------------------------------------------

## Un intento completo con esta semilla. Devuelve null si no pasa la validación.
static func _try_generate(params: Params, seed_value: int) -> Layout:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var layout := Layout.new(params.grid_size)
	layout.level = params.level
	layout.seed_used = seed_value

	for room in _place_rooms(params, rng):
		layout.rooms.append(room)
		layout.carve_rect(room)
	if layout.rooms.size() < MIN_ROOMS:
		return null

	_link_rooms(layout, params.extra_links, rng)
	if not _finish(layout, params, rng).is_empty():
		return null
	# Un nivel casi vacío no sirve: mejor probar otra semilla.
	if layout.enemies.size() < ceili(params.enemy_count * MIN_ENEMY_RATIO):
		return null
	return layout


## Todo lo que sigue a tener las salas y los corredores. Devuelve "" si el
## resultado es válido.
static func _finish(layout: Layout, params: Params, rng: RandomNumberGenerator) -> String:
	_remove_thin_walls(layout)
	var error := _choose_rooms_and_door(layout, rng)
	if not error.is_empty():
		return error
	error = _place_key(layout, rng)
	if not error.is_empty():
		return error

	# Celdas ya ocupadas, para separar entidades. La llave y la puerta cuentan.
	var taken: Array[Vector2i] = [layout.key_cell]
	taken.append_array(layout.door_floor_cells())
	_place_bosses(layout, params, rng, taken)
	_place_enemies(layout, params, rng, taken)
	_place_hazards(layout, params, rng, taken)
	_place_torches(layout, rng)
	return validate(layout)


static func _place_rooms(params: Params, rng: RandomNumberGenerator) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = []
	var tries := params.room_count * ROOM_PLACEMENT_TRIES
	while rooms.size() < params.room_count and tries > 0:
		tries -= 1
		var w := rng.randi_range(params.room_min.x, params.room_max.x)
		var h := rng.randi_range(params.room_min.y, params.room_max.y)
		# El suelo va de la celda 1 a size-2: afuera queda la pared.
		var max_x := params.grid_size.x - 1 - w
		var max_y := params.grid_size.y - 1 - h
		if max_x < 1 or max_y < 1:
			continue
		var room := Rect2i(rng.randi_range(1, max_x), rng.randi_range(1, max_y), w, h)
		var grown := room.grow(ROOM_SPACING)
		var overlaps := false
		for other in rooms:
			if grown.intersects(other):
				overlaps = true
				break
		if not overlaps:
			rooms.append(room)
	return rooms


## Une todas las salas con un árbol de expansión mínimo (Prim sobre la
## distancia entre centros) y agrega algunos lazos con las parejas más cercanas
## que aún no estén unidas.
static func _link_rooms(layout: Layout, extra_links: int, rng: RandomNumberGenerator) -> void:
	var count := layout.rooms.size()
	var in_tree := PackedByteArray()
	in_tree.resize(count)
	in_tree[0] = 1
	for _step in count - 1:
		var best := Vector2i(-1, -1)
		var best_dist := INF
		for a in count:
			if in_tree[a] == 0:
				continue
			for b in count:
				if in_tree[b] == 1:
					continue
				var d := _room_distance(layout, a, b)
				if d < best_dist:
					best_dist = d
					best = Vector2i(a, b)
		layout.links.append(best)
		in_tree[best.y] = 1

	var candidates: Array[Vector2i] = []
	for a in count:
		for b in range(a + 1, count):
			if not _is_linked(layout, a, b):
				candidates.append(Vector2i(a, b))
	# Desempate por índice para que el orden sea siempre el mismo.
	candidates.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		var dp := _room_distance(layout, p.x, p.y)
		var dq := _room_distance(layout, q.x, q.y)
		if dp != dq:
			return dp < dq
		return p.x * count + p.y < q.x * count + q.y)
	var pool: Array[Vector2i] = []
	pool.assign(candidates.slice(0, extra_links * 2))
	_shuffle(pool, rng)
	for i in mini(extra_links, pool.size()):
		layout.links.append(pool[i])

	for link in layout.links:
		_carve_corridor(layout, layout.room_center(link.x), layout.room_center(link.y),
				rng.randi_range(0, 1) == 0)


static func _room_distance(layout: Layout, a: int, b: int) -> float:
	return Vector2(layout.room_center(a)).distance_squared_to(Vector2(layout.room_center(b)))


static func _is_linked(layout: Layout, a: int, b: int) -> bool:
	for link in layout.links:
		if (link.x == a and link.y == b) or (link.x == b and link.y == a):
			return true
	return false


## Corredor en L entre dos puntos. Cada tramo es un rectángulo de
## CORREDOR_WIDTH celdas; con horizontal_first va primero por la fila de a y
## después por la columna de b, y al revés si no.
static func _carve_corridor(layout: Layout, a: Vector2i, b: Vector2i, horizontal_first: bool) -> void:
	var w := CORRIDOR_WIDTH
	if horizontal_first:
		layout.carve_rect(Rect2i(mini(a.x, b.x), a.y, absi(b.x - a.x) + w, w))
		layout.carve_rect(Rect2i(b.x, mini(a.y, b.y), w, absi(b.y - a.y) + w))
	else:
		layout.carve_rect(Rect2i(a.x, mini(a.y, b.y), w, absi(b.y - a.y) + w))
		layout.carve_rect(Rect2i(mini(a.x, b.x), b.y, absi(b.x - a.x) + w, w))


## Abre las paredes que separan dos zonas de suelo con una sola celda (por
## ejemplo un corredor que pasa a una celda de una sala). Solo agrega suelo,
## así que la conectividad nunca empeora. Termina porque cada pasada agrega
## suelo y la grilla es finita.
static func _remove_thin_walls(layout: Layout) -> void:
	while layout.process_thin_walls(true) > 0:
		pass


## Elige la sala de inicio (el extremo del mapa), la de salida (la más lejana
## por camino real desde el inicio que tenga sitio para la puerta) y coloca al
## jugador y la puerta.
static func _choose_rooms_and_door(layout: Layout, rng: RandomNumberGenerator) -> String:
	# Doble barrido: la sala más lejana de la primera es un buen extremo.
	var from_first := layout.distances_from(layout.room_center(0))
	var farthest := -1
	for i in layout.rooms.size():
		var d := layout.dist_at(from_first, layout.room_center(i))
		if d < 0:
			return "la sala %d es inalcanzable" % i
		if d > farthest:
			farthest = d
			layout.start_room = i
	layout.player_cell = layout.room_center(layout.start_room)

	var from_start := layout.distances_from(layout.player_cell)
	var order: Array[int] = []
	for i in layout.rooms.size():
		if i != layout.start_room:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da := layout.dist_at(from_start, layout.room_center(a))
		var db := layout.dist_at(from_start, layout.room_center(b))
		if da != db:
			return da > db
		return a < b)

	for room_index in order:
		var door := _find_door(layout, room_index, rng)
		if door.x >= 0:
			layout.exit_room = room_index
			layout.door_cell = door
			return ""
	return "ninguna sala tiene sitio para la puerta"


## Busca dónde poner la puerta en la pared superior de la sala: dos celdas de
## pared seguidas con suelo debajo, y pared también a los costados para que la
## fila quede continua. Devuelve la celda de suelo bajo la mitad izquierda, o
## (-1, -1) si no hay sitio.
static func _find_door(layout: Layout, room_index: int, rng: RandomNumberGenerator) -> Vector2i:
	var room := layout.rooms[room_index]
	var y := room.position.y
	var options: Array[Vector2i] = []
	for x in range(room.position.x + 1, room.end.x - 2):
		var ok := true
		for dx in range(-1, 3):
			# La fila de pared de la puerta y sus vecinas no pueden ser suelo.
			if layout.is_floor(Vector2i(x + dx, y - 1)):
				ok = false
		for dx in range(0, 2):
			for dy in range(0, 2):
				if not layout.is_floor(Vector2i(x + dx, y + dy)):
					ok = false
		if ok:
			options.append(Vector2i(x, y))
	if options.is_empty():
		return Vector2i(-1, -1)
	return options[rng.randi_range(0, options.size() - 1)]


## La llave va en la sala más apartada del camino entre el inicio y la puerta,
## para que haya que explorar.
static func _place_key(layout: Layout, rng: RandomNumberGenerator) -> String:
	var from_start := layout.distances_from(layout.player_cell)
	var from_exit := layout.distances_from(layout.room_center(layout.exit_room))
	var best_score := -1
	for i in layout.rooms.size():
		if i == layout.start_room or i == layout.exit_room:
			continue
		var center := layout.room_center(i)
		var score := layout.dist_at(from_start, center) + layout.dist_at(from_exit, center)
		if score > best_score:
			best_score = score
			layout.key_room = i
	if layout.key_room < 0:
		return "no hay sala para la llave"
	var cells := _spawnable_cells(layout, layout.key_room)
	if cells.is_empty():
		return "no hay celda para la llave"
	layout.key_cell = cells[rng.randi_range(0, cells.size() - 1)]
	return ""


## Parcas: una guarda la puerta y, en niveles altos, otra guarda la llave.
static func _place_bosses(layout: Layout, params: Params, rng: RandomNumberGenerator,
		taken: Array[Vector2i]) -> void:
	if params.boss_count >= 1:
		_place_guard(layout, rng, taken, layout.exit_room, layout.door_cell)
	if params.boss_count >= 2:
		_place_guard(layout, rng, taken, layout.key_room, layout.key_cell)


## Coloca una parca en la sala, a distancia media de su punto de guardia. Si
## no hay ninguna celda a esa distancia, usa cualquiera libre de la sala.
static func _place_guard(layout: Layout, rng: RandomNumberGenerator, taken: Array[Vector2i],
		room_index: int, anchor: Vector2i) -> void:
	var cells := _spawnable_cells(layout, room_index)
	_shuffle(cells, rng)
	var fallback := Vector2i(-1, -1)
	for cell in cells:
		if not _is_spaced(cell, taken, ENEMY_SPACING):
			continue
		var d := Vector2(cell).distance_to(Vector2(anchor))
		if d >= BOSS_DISTANCE_MIN and d <= BOSS_DISTANCE_MAX:
			layout.enemies.append(Spawn.new(REAPER, cell))
			taken.append(cell)
			return
		if fallback.x < 0:
			fallback = cell
	if fallback.x >= 0:
		layout.enemies.append(Spawn.new(REAPER, fallback))
		taken.append(fallback)


## Enemigos comunes: esqueletos con patrulla y vampiros perseguidores.
static func _place_enemies(layout: Layout, params: Params, rng: RandomNumberGenerator,
		taken: Array[Vector2i]) -> void:
	var cells := _all_spawnable_cells(layout)
	_shuffle(cells, rng)
	var chasers := roundi(params.enemy_count * params.chaser_share)
	var skeletons := params.enemy_count - chasers
	var skeletons_placed := 0
	var chasers_placed := 0

	# Los esqueletos van primero porque necesitan un pasillo libre para patrullar.
	for cell in cells:
		if skeletons_placed >= skeletons:
			break
		if not _is_spaced(cell, taken, ENEMY_SPACING):
			continue
		var patrol := _find_patrol(layout, cell, rng)
		if patrol == Vector2i.ZERO:
			continue
		var skeleton := Spawn.new(SKELETON, cell)
		skeleton.patrol = patrol
		layout.enemies.append(skeleton)
		# Se reserva todo el recorrido, no solo los extremos.
		var dir := Vector2i(signi(patrol.x), signi(patrol.y))
		for step in maxi(absi(patrol.x), absi(patrol.y)) + 1:
			taken.append(cell + dir * step)
		skeletons_placed += 1

	for cell in cells:
		if chasers_placed >= chasers:
			break
		if not _is_spaced(cell, taken, ENEMY_SPACING):
			continue
		layout.enemies.append(Spawn.new(VAMPIRE, cell))
		taken.append(cell)
		chasers_placed += 1

	# Si faltaron esqueletos por falta de pasillos, se colocan quietos: sin
	# patrulla no pueden meterse en una pared.
	for cell in cells:
		if skeletons_placed >= skeletons:
			break
		if not _is_spaced(cell, taken, ENEMY_SPACING):
			continue
		layout.enemies.append(Spawn.new(SKELETON, cell))
		taken.append(cell)
		skeletons_placed += 1


## Busca un tramo recto de patrulla desde cell. Todas las celdas del recorrido
## tienen que ser interiores (el cuerpo no roza paredes) y estar lejos del
## inicio. Prueba las cuatro direcciones y acorta el tramo hasta PATROL_MIN;
## devuelve cero si no hay ninguno.
static func _find_patrol(layout: Layout, cell: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var dirs: Array[Vector2i] = DIRS4.duplicate()
	_shuffle(dirs, rng)
	var first_length := rng.randi_range(PATROL_MIN, PATROL_MAX)
	for dir in dirs:
		for length in range(first_length, PATROL_MIN - 1, -1):
			var clear := true
			for step in length + 1:
				if not _is_spawnable(layout, cell + dir * step):
					clear = false
					break
			if clear:
				return dir * length
	return Vector2i.ZERO


static func _place_hazards(layout: Layout, params: Params, rng: RandomNumberGenerator,
		taken: Array[Vector2i]) -> void:
	var cells := _all_spawnable_cells(layout)
	_shuffle(cells, rng)
	var placed := 0
	for cell in cells:
		if placed >= params.hazard_count:
			break
		if not _is_spaced(cell, taken, HAZARD_SPACING):
			continue
		var trap := Spawn.new(SPIKES, cell)
		# Desfasa las trampas: unas arrancan con los picos arriba y otras abajo.
		trap.frame = 3 if rng.randi_range(0, 1) == 1 else 0
		layout.hazards.append(trap)
		taken.append(cell)
		placed += 1


## Antorchas en la pared superior de cada sala (donde el tile es de pared
## frontal), separadas y lejos de la puerta.
static func _place_torches(layout: Layout, rng: RandomNumberGenerator) -> void:
	for room in layout.rooms:
		var y := room.position.y - 1
		var xs: Array[int] = []
		for x in range(room.position.x + 1, room.end.x - 1):
			if _is_torch_wall(layout, Vector2i(x, y)):
				xs.append(x)
		_shuffle(xs, rng)
		var chosen: Array[int] = []
		for x in xs:
			if chosen.size() >= TORCHES_PER_ROOM:
				break
			var spaced := true
			for other in chosen:
				if absi(x - other) < TORCH_SPACING:
					spaced = false
			if spaced:
				chosen.append(x)
				layout.torches.append(Vector2i(x, y))


static func _is_torch_wall(layout: Layout, c: Vector2i) -> bool:
	# Pared recta: suelo debajo y pared a los lados, así el tile es el frontal.
	if layout.is_floor(c) or layout.is_floor(c + Vector2i(-1, 0)) or layout.is_floor(c + Vector2i(1, 0)):
		return false
	if not layout.is_floor(c + Vector2i(0, 1)):
		return false
	# No sobre la puerta ni pegada a ella.
	var door_wall_y := layout.door_cell.y - 1
	if c.y == door_wall_y and c.x >= layout.door_cell.x - 1 and c.x <= layout.door_cell.x + 2:
		return false
	return true


# ---------------------------------------------------------------------------
# Ayudas de colocación
# ---------------------------------------------------------------------------

## Celda donde puede haber una entidad: interior (rodeada de suelo), lejos del
## inicio del jugador y fuera del área de la puerta.
static func _is_spawnable(layout: Layout, cell: Vector2i) -> bool:
	if not layout.is_interior(cell):
		return false
	if Vector2(cell).distance_to(Vector2(layout.player_cell)) < SPAWN_SAFE_RADIUS:
		return false
	for door_cell in layout.door_floor_cells():
		if maxi(absi(cell.x - door_cell.x), absi(cell.y - door_cell.y)) <= DOOR_CLEAR_RADIUS:
			return false
	return true


static func _spawnable_cells(layout: Layout, room_index: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var room := layout.rooms[room_index]
	for y in range(room.position.y, room.end.y):
		for x in range(room.position.x, room.end.x):
			if _is_spawnable(layout, Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


static func _all_spawnable_cells(layout: Layout) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in layout.rooms.size():
		out.append_array(_spawnable_cells(layout, i))
	return out


## true si cell está al menos a min_dist celdas (distancia de tablero) de todas
## las ya ocupadas.
static func _is_spaced(cell: Vector2i, taken: Array[Vector2i], min_dist: int) -> bool:
	for other in taken:
		if maxi(absi(cell.x - other.x), absi(cell.y - other.y)) < min_dist:
			return false
	return true


## Baraja con el generador dado. No se usa Array.shuffle() porque usa el
## generador global y rompería el determinismo.
static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = items[i]
		items[i] = items[j]
		items[j] = tmp


static func _mix(value: int) -> int:
	# Mezcla de bits tipo splitmix64; el desborde de enteros es intencional.
	var x := value
	x = (x ^ (x >> 30)) * -4658895280553007687
	x = (x ^ (x >> 27)) * -7723592293110705685
	return x ^ (x >> 31)


# ---------------------------------------------------------------------------
# Validación de entidades
# ---------------------------------------------------------------------------

static func _validate_spawn(layout: Layout, reach: PackedInt32Array, spawn: Spawn) -> String:
	if not layout.is_interior(spawn.cell):
		return "no está sobre suelo despejado en %s" % str(spawn.cell)
	if layout.dist_at(reach, spawn.cell) < 0:
		return "inalcanzable en %s" % str(spawn.cell)
	if Vector2(spawn.cell).distance_to(Vector2(layout.player_cell)) < SPAWN_SAFE_RADIUS:
		return "demasiado cerca del inicio en %s" % str(spawn.cell)
	for door_cell in layout.door_floor_cells():
		if maxi(absi(spawn.cell.x - door_cell.x), absi(spawn.cell.y - door_cell.y)) <= DOOR_CLEAR_RADIUS:
			return "dentro del área de la puerta en %s" % str(spawn.cell)
	return ""


## La patrulla es recta, del largo permitido y todo su recorrido es suelo
## despejado, alcanzable y lejos del inicio.
static func _validate_patrol(layout: Layout, reach: PackedInt32Array, spawn: Spawn) -> String:
	var patrol := spawn.patrol
	if patrol == Vector2i.ZERO:
		return ""
	if patrol.x != 0 and patrol.y != 0:
		return "la patrulla no es recta"
	var length := maxi(absi(patrol.x), absi(patrol.y))
	if length < PATROL_MIN or length > PATROL_MAX:
		return "largo de patrulla fuera de rango"
	var dir := Vector2i(signi(patrol.x), signi(patrol.y))
	for step in length + 1:
		var c := spawn.cell + dir * step
		if not _is_spawnable(layout, c) or layout.dist_at(reach, c) < 0:
			return "el recorrido pasa por una celda no válida %s" % str(c)
	return ""
