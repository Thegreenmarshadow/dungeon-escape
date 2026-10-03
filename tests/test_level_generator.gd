@tool
extends McpTestSuite
## Pruebas del generador procedural de niveles (LevelGenerator) y de la
## traducción de paredes a tiles (LevelBuilder.wall_tile_for). Se ejecutan con
## muchas semillas y niveles: cada mapa generado debe cumplir todas las
## invariantes, comprobadas aquí de forma independiente al generador.

const LEVELS := [2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 20]
const SEEDS_PER_LEVEL := 40
## Tiles del atlas con colisión (ver tilesets/dungeon_tileset.tres).
const COLLIDING_TILES := [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0),
	Vector2i(0, 1), Vector2i(5, 1), Vector2i(0, 2), Vector2i(5, 2), Vector2i(0, 3), Vector2i(5, 3),
	Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4),
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5),
]
const N := Vector2i(0, -1)
const S := Vector2i(0, 1)
const W := Vector2i(-1, 0)
const E := Vector2i(1, 0)
## Lados de cada tile de pared con la mitad oscura (el vacío de afuera) ya
## dibujada en el atlas: ahí nunca puede haber suelo.
const DARK_SIDES := {
	LevelBuilder.WALL_TOP: [],
	LevelBuilder.WALL_BOTTOM: [S, S + W, S + E],
	LevelBuilder.WALL_LEFT: [W, W + N, W + S],
	LevelBuilder.WALL_RIGHT: [E, E + N, E + S],
	LevelBuilder.CORNER_TOP_LEFT: [W, W + N, W + S],
	LevelBuilder.CORNER_TOP_RIGHT: [E, E + N, E + S],
	LevelBuilder.CORNER_BOTTOM_LEFT: [W, W + N, W + S, S, S + E],
	LevelBuilder.CORNER_BOTTOM_RIGHT: [E, E + N, E + S, S, S + W],
	LevelBuilder.INNER_NORTH_EAST: [W, S, S + W],
	LevelBuilder.INNER_NORTH_WEST: [E, S, S + E],
}


var _cache := {}


func suite_name() -> String:
	return "level_generator"


func test_same_seed_gives_same_level() -> void:
	for level in [2, 5, 9]:
		# Sin caché: hay que generar dos veces de verdad.
		var a := LevelGenerator.generate(level, 987654)
		var b := LevelGenerator.generate(level, 987654)
		assert_eq(_signature(a), _signature(b), "nivel %d no es determinista" % level)


func test_different_seeds_give_different_levels() -> void:
	var signatures := {}
	for run_seed in 20:
		signatures[_signature(_gen(4, run_seed))] = true
	assert_gt(signatures.size(), 15, "las semillas casi no cambian el mapa")


func test_different_levels_differ_for_same_run() -> void:
	assert_ne(_signature(_gen(2, 55)), _signature(_gen(3, 55)))


func test_all_generated_levels_pass_validation() -> void:
	var fallbacks := 0
	var total := 0
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			total += 1
			if layout.used_fallback:
				fallbacks += 1
			assert_eq(LevelGenerator.validate(layout), "", "nivel %d semilla %d" % [level, run_seed])
	# El diseño de emergencia tiene que ser rarísimo.
	assert_true(fallbacks * 20 <= total, "demasiados diseños de emergencia: %d de %d" % [fallbacks, total])


func test_fallback_layout_is_valid_at_every_level() -> void:
	for level in LEVELS:
		for run_seed in 5:
			var layout := LevelGenerator.build_fallback(level, run_seed)
			assert_eq(LevelGenerator.validate(layout), "", "emergencia nivel %d semilla %d" % [level, run_seed])
			assert_true(layout.used_fallback)


func test_everything_is_reachable_from_the_player() -> void:
	# Flood fill propio (no usa distances_from del generador).
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			var reached := _flood(layout, layout.player_cell)
			var where := "nivel %d semilla %d" % [level, run_seed]
			for cell in layout.door_floor_cells():
				assert_true(reached.has(cell), "puerta inalcanzable, " + where)
			assert_true(reached.has(layout.key_cell), "llave inalcanzable, " + where)
			for enemy in layout.enemies:
				assert_true(reached.has(enemy.cell), "enemigo inalcanzable, " + where)
				assert_true(reached.has(enemy.cell + enemy.patrol), "patrulla inalcanzable, " + where)
			for trap in layout.hazards:
				assert_true(reached.has(trap.cell), "trampa inalcanzable, " + where)
			for i in layout.rooms.size():
				assert_true(reached.has(layout.room_center(i)), "sala inalcanzable, " + where)


func test_no_entity_is_on_a_wall_or_outside_the_grid() -> void:
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			var where := "nivel %d semilla %d" % [level, run_seed]
			assert_true(layout.is_floor(layout.player_cell), "jugador fuera del suelo, " + where)
			assert_true(layout.is_floor(layout.key_cell), "llave fuera del suelo, " + where)
			for spawn in layout.enemies + layout.hazards:
				assert_true(layout.is_floor(spawn.cell), "entidad sobre pared, " + where)
				assert_true(layout.is_interior(spawn.cell), "entidad pegada a una pared, " + where)
			for torch in layout.torches:
				assert_true(layout.is_wall(torch), "antorcha fuera de la pared, " + where)
			var door_wall := layout.door_cell + Vector2i(0, -1)
			assert_true(layout.is_wall(door_wall) and layout.is_wall(door_wall + Vector2i(1, 0)),
					"la puerta no está sobre pared, " + where)


func test_floor_never_touches_the_grid_border() -> void:
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			var bounds := layout.floor_bounds()
			assert_true(bounds.position.x >= 1 and bounds.position.y >= 1, "nivel %d semilla %d" % [level, run_seed])
			assert_true(bounds.end.x <= layout.size.x - 1 and bounds.end.y <= layout.size.y - 1,
					"nivel %d semilla %d" % [level, run_seed])


func test_skeleton_patrols_are_straight_and_on_clear_floor() -> void:
	var patrols := 0
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			for enemy in layout.enemies:
				if enemy.kind != LevelGenerator.SKELETON:
					assert_eq(enemy.patrol, Vector2i.ZERO, "solo los esqueletos patrullan")
					continue
				if enemy.patrol == Vector2i.ZERO:
					continue
				patrols += 1
				assert_true(enemy.patrol.x == 0 or enemy.patrol.y == 0, "patrulla en diagonal")
				var dir := Vector2i(signi(enemy.patrol.x), signi(enemy.patrol.y))
				var steps := maxi(absi(enemy.patrol.x), absi(enemy.patrol.y))
				for step in steps + 1:
					var cell: Vector2i = enemy.cell + dir * step
					assert_true(layout.is_interior(cell),
							"patrulla pasa por %s, nivel %d semilla %d" % [str(cell), level, run_seed])
	assert_gt(patrols, 100, "casi no hay esqueletos que patrullen")


func test_entities_keep_away_from_the_player_start() -> void:
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			for spawn in layout.enemies + layout.hazards:
				var d := Vector2(spawn.cell).distance_to(Vector2(layout.player_cell))
				assert_true(d >= LevelGenerator.SPAWN_SAFE_RADIUS,
						"entidad a %.1f celdas del inicio, nivel %d semilla %d" % [d, level, run_seed])


func test_exit_is_in_a_different_room_and_far_away() -> void:
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			assert_ne(layout.exit_room, layout.start_room)
			assert_ne(layout.key_room, layout.start_room)
			assert_ne(layout.key_room, layout.exit_room)
			var reached := _flood(layout, layout.player_cell)
			assert_gt(reached[layout.door_cell], LevelGenerator.MIN_EXIT_PATH - 1, "puerta demasiado cerca")


func test_difficulty_scales_with_level() -> void:
	var previous := LevelGenerator.params_for_level(2)
	assert_eq(previous.boss_count, 0, "el nivel 2 no debe tener jefe")
	for level in range(3, 21):
		var p := LevelGenerator.params_for_level(level)
		assert_true(p.enemy_count >= previous.enemy_count, "enemigos no bajan, nivel %d" % level)
		assert_true(p.chaser_share >= previous.chaser_share, "perseguidores no bajan, nivel %d" % level)
		assert_true(p.room_count >= previous.room_count)
		assert_true(p.hazard_count >= previous.hazard_count)
		assert_true(p.grid_size.x >= previous.grid_size.x and p.grid_size.y >= previous.grid_size.y)
		assert_true(p.boss_count >= previous.boss_count)
		previous = p
	assert_eq(LevelGenerator.params_for_level(3).boss_count, 1)
	assert_eq(LevelGenerator.params_for_level(LevelGenerator.SECOND_BOSS_LEVEL).boss_count, 2)


func test_bosses_appear_from_the_configured_level() -> void:
	for run_seed in SEEDS_PER_LEVEL:
		assert_eq(_count_kind(_gen(2, run_seed), LevelGenerator.REAPER), 0)
		assert_gt(_count_kind(_gen(3, run_seed), LevelGenerator.REAPER), 0,
				"sin jefe en el nivel 3, semilla %d" % run_seed)


func test_skulls_appear_from_the_configured_level() -> void:
	var first := LevelGenerator.SKULL_FIRST_LEVEL
	assert_eq(LevelGenerator.params_for_level(first - 1).skull_count, 0)
	assert_gt(LevelGenerator.params_for_level(first).skull_count, 0)
	var skulls_before := 0
	var skulls_after := 0
	for run_seed in SEEDS_PER_LEVEL:
		skulls_before += _count_kind(_gen(first - 1, run_seed), LevelGenerator.SKULL)
		skulls_after += _count_kind(_gen(first + 2, run_seed), LevelGenerator.SKULL)
	assert_eq(skulls_before, 0, "no debe haber calaveras antes del nivel configurado")
	assert_gt(skulls_after, 0, "debe haber calaveras desde el nivel configurado")


func test_builder_has_a_scene_for_every_generated_enemy_kind() -> void:
	for kind in [LevelGenerator.SKELETON, LevelGenerator.VAMPIRE, LevelGenerator.REAPER, LevelGenerator.SKULL]:
		assert_true(LevelBuilder.ENEMY_SCENES.has(kind), "sin escena para %s" % kind)
	for run_seed in SEEDS_PER_LEVEL:
		for enemy in _gen(LevelGenerator.SKULL_FIRST_LEVEL + 2, run_seed).enemies:
			assert_true(LevelBuilder.ENEMY_SCENES.has(enemy.kind), "el generador pidió %s" % enemy.kind)


func test_skull_count_never_exceeds_the_chasers() -> void:
	for level in [4, 8, 14]:
		var p := LevelGenerator.params_for_level(level)
		assert_true(p.skull_count <= LevelGenerator.chaser_count(p),
				"nivel %d: más calaveras que perseguidores" % level)


func test_higher_levels_have_more_enemies() -> void:
	var low := 0
	var high := 0
	for run_seed in SEEDS_PER_LEVEL:
		low += _gen(2, run_seed).enemies.size()
		high += _gen(10, run_seed).enemies.size()
	assert_gt(high, low * 2, "el nivel 10 debería tener bastantes más enemigos que el 2")


func test_every_wall_cell_gets_a_colliding_tile() -> void:
	for level in [2, 4, 8, 12]:
		for run_seed in 10:
			var layout := _gen(level, run_seed)
			for cell in layout.wall_cells():
				var tile := LevelBuilder.wall_tile_for(layout, cell)
				assert_true(tile in COLLIDING_TILES,
						"la pared %s no tiene tile con colisión, nivel %d semilla %d" % [str(cell), level, run_seed])
			# Las celdas que no son pared no reciben tile de pared.
			assert_eq(LevelBuilder.wall_tile_for(layout, layout.player_cell), LevelBuilder.NO_TILE)


func test_dark_side_of_wall_tiles_never_faces_floor() -> void:
	for level in [2, 4, 8, 12]:
		for run_seed in 10:
			var layout := _gen(level, run_seed)
			for cell in layout.wall_cells():
				var tile := LevelBuilder.wall_tile_for(layout, cell)
				for side in DARK_SIDES[tile]:
					assert_false(layout.is_floor(cell + side),
							"el tile %s de %s tiene suelo en su lado oscuro %s, nivel %d semilla %d"
							% [str(tile), str(cell), str(side), level, run_seed])


# Los mapas de prueba pasan por la misma limpieza de paredes finas que el
# generador: por eso cada boca de corredor termina en un escalón diagonal.

func test_corridor_entering_a_room_side_joins_the_room_wall() -> void:
	# Sala a la derecha (x 6..9), corredor de 2 de alto que entra por la izquierda.
	var left := _hand_layout(Vector2i(12, 10), [Rect2i(6, 2, 4, 6), Rect2i(1, 4, 5, 2)])
	_assert_tile(left, Vector2i(5, 2), LevelBuilder.WALL_TOP, "anillo de la sala sobre la boca")
	_assert_tile(left, Vector2i(4, 3), LevelBuilder.WALL_TOP, "pared de arriba del corredor")
	_assert_tile(left, Vector2i(4, 6), LevelBuilder.INNER_NORTH_EAST, "pared de abajo del corredor")
	_assert_tile(left, Vector2i(5, 7), LevelBuilder.INNER_NORTH_EAST, "anillo de la sala bajo la boca")
	_assert_tile(left, Vector2i(4, 7), LevelBuilder.CORNER_BOTTOM_LEFT, "escalón")
	_assert_tile(left, Vector2i(3, 6), LevelBuilder.WALL_BOTTOM)
	# Lo mismo en espejo: el corredor entra por la derecha de la sala.
	var right := _hand_layout(Vector2i(12, 10), [Rect2i(2, 2, 4, 6), Rect2i(6, 4, 5, 2)])
	_assert_tile(right, Vector2i(6, 2), LevelBuilder.WALL_TOP, "anillo de la sala sobre la boca")
	_assert_tile(right, Vector2i(7, 3), LevelBuilder.WALL_TOP, "pared de arriba del corredor")
	_assert_tile(right, Vector2i(7, 6), LevelBuilder.INNER_NORTH_WEST, "pared de abajo del corredor")
	_assert_tile(right, Vector2i(6, 7), LevelBuilder.INNER_NORTH_WEST, "anillo de la sala bajo la boca")
	_assert_tile(right, Vector2i(7, 7), LevelBuilder.CORNER_BOTTOM_RIGHT, "escalón")


func test_corridor_leaving_the_top_of_a_room() -> void:
	# Sala abajo (y 5..8), corredor de 2 de ancho que sube por x 4..5.
	var layout := _hand_layout(Vector2i(10, 10), [Rect2i(2, 5, 6, 4), Rect2i(4, 1, 2, 4)])
	_assert_tile(layout, Vector2i(2, 4), LevelBuilder.WALL_TOP, "anillo de la sala, izquierda")
	_assert_tile(layout, Vector2i(7, 4), LevelBuilder.WALL_TOP, "anillo de la sala, derecha")
	_assert_tile(layout, Vector2i(3, 3), LevelBuilder.WALL_TOP, "pie de la pared izquierda del corredor")
	_assert_tile(layout, Vector2i(6, 3), LevelBuilder.WALL_TOP, "pie de la pared derecha del corredor")
	_assert_tile(layout, Vector2i(3, 2), LevelBuilder.WALL_LEFT)
	_assert_tile(layout, Vector2i(6, 2), LevelBuilder.WALL_RIGHT)


func test_corridor_leaving_the_bottom_of_a_room() -> void:
	# Sala arriba (y 1..4), corredor de 2 de ancho que baja por x 4..5.
	var layout := _hand_layout(Vector2i(10, 10), [Rect2i(2, 1, 6, 4), Rect2i(4, 5, 2, 4)])
	_assert_tile(layout, Vector2i(2, 5), LevelBuilder.INNER_NORTH_EAST, "anillo de la sala, izquierda")
	_assert_tile(layout, Vector2i(7, 5), LevelBuilder.INNER_NORTH_WEST, "anillo de la sala, derecha")
	_assert_tile(layout, Vector2i(3, 6), LevelBuilder.INNER_NORTH_EAST, "cabeza de la pared izquierda del corredor")
	_assert_tile(layout, Vector2i(6, 6), LevelBuilder.INNER_NORTH_WEST, "cabeza de la pared derecha del corredor")
	_assert_tile(layout, Vector2i(3, 7), LevelBuilder.WALL_LEFT)
	_assert_tile(layout, Vector2i(6, 7), LevelBuilder.WALL_RIGHT)


func test_corridor_bends() -> void:
	# Tramo horizontal (y 2..3) que gira hacia abajo por x 5..6.
	var down := _hand_layout(Vector2i(10, 10), [Rect2i(1, 2, 6, 2), Rect2i(5, 2, 2, 7)])
	_assert_tile(down, Vector2i(7, 1), LevelBuilder.CORNER_TOP_RIGHT, "esquina exterior")
	_assert_tile(down, Vector2i(3, 4), LevelBuilder.INNER_NORTH_EAST, "esquina interior")
	_assert_tile(down, Vector2i(4, 5), LevelBuilder.INNER_NORTH_EAST, "esquina interior")
	_assert_tile(down, Vector2i(3, 5), LevelBuilder.CORNER_BOTTOM_LEFT, "escalón")
	_assert_tile(down, Vector2i(4, 6), LevelBuilder.WALL_LEFT)
	_assert_tile(down, Vector2i(7, 4), LevelBuilder.WALL_RIGHT)
	# Tramo horizontal (y 6..7) que gira hacia arriba por x 5..6.
	var up := _hand_layout(Vector2i(10, 10), [Rect2i(1, 6, 6, 2), Rect2i(5, 1, 2, 7)])
	_assert_tile(up, Vector2i(7, 8), LevelBuilder.CORNER_BOTTOM_RIGHT, "esquina exterior")
	_assert_tile(up, Vector2i(3, 5), LevelBuilder.WALL_TOP, "esquina interior")
	_assert_tile(up, Vector2i(4, 4), LevelBuilder.WALL_TOP, "esquina interior")
	_assert_tile(up, Vector2i(3, 4), LevelBuilder.CORNER_TOP_LEFT, "escalón")
	_assert_tile(up, Vector2i(4, 3), LevelBuilder.WALL_LEFT)


func test_seed_derivation_is_stable_and_distinct() -> void:
	assert_eq(LevelGenerator.derive_seed(1, 2, 3), LevelGenerator.derive_seed(1, 2, 3))
	var seen := {}
	for level in range(2, 12):
		for attempt in 8:
			seen[LevelGenerator.derive_seed(42, level, attempt)] = true
	assert_eq(seen.size(), 80, "colisión de semillas derivadas")


# ----- ayudas -----

## Genera una sola vez cada (nivel, semilla) durante toda la suite: generar
## es lo más lento y el resultado es determinista.
func _gen(level: int, run_seed: int) -> LevelGenerator.Layout:
	var key := Vector2i(level, run_seed)
	if not _cache.has(key):
		_cache[key] = LevelGenerator.generate(level, run_seed)
	return _cache[key]


## Mapa armado a mano con rectángulos de suelo, limpiado de paredes finas
## igual que lo hace el generador.
func _hand_layout(size: Vector2i, floors: Array[Rect2i]) -> LevelGenerator.Layout:
	var layout := LevelGenerator.Layout.new(size)
	for rect in floors:
		layout.carve_rect(rect)
	while layout.process_thin_walls(true) > 0:
		pass
	return layout


func _assert_tile(layout: LevelGenerator.Layout, cell: Vector2i, expected: Vector2i, what: String = "") -> void:
	assert_eq(LevelBuilder.wall_tile_for(layout, cell), expected, "%s %s" % [str(cell), what])


## Firma completa de un mapa para comparar dos generaciones.
func _signature(layout: LevelGenerator.Layout) -> String:
	var parts := PackedStringArray()
	parts.append(str(layout.size))
	parts.append(str(layout.floor_cells.hex_encode()))
	parts.append(str(layout.player_cell) + str(layout.key_cell) + str(layout.door_cell))
	for enemy in layout.enemies:
		parts.append("%s%s%s" % [enemy.kind, str(enemy.cell), str(enemy.patrol)])
	for trap in layout.hazards:
		parts.append("t%s%d" % [str(trap.cell), trap.frame])
	for torch in layout.torches:
		parts.append("l" + str(torch))
	return "|".join(parts)


func _count_kind(layout: LevelGenerator.Layout, kind: StringName) -> int:
	var count := 0
	for enemy in layout.enemies:
		if enemy.kind == kind:
			count += 1
	return count


## Flood fill independiente: devuelve {celda: distancia} de todo el suelo
## alcanzable en 4 direcciones desde origin.
func _flood(layout: LevelGenerator.Layout, origin: Vector2i) -> Dictionary:
	var reached := {origin: 0}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = c + dir
			if layout.is_floor(n) and not reached.has(n):
				reached[n] = reached[c] + 1
				queue.append(n)
	return reached
