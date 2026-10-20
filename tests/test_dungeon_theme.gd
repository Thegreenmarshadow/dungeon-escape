@tool
extends McpTestSuite
## Pruebas de los temas de mazmorra: qué tema le toca a cada nivel
## (DungeonTheme), el tileset recoloreado (tools/retheme.py) y la colocación
## de la decoración (ThemeDecor).

const LEVELS := [5, 8, 9, 12, 13, 16, 20]
const SEEDS_PER_LEVEL := 25
const THEMES: Array[StringName] = [DungeonTheme.ICE, DungeonTheme.LAVA, DungeonTheme.MOSS]
const BASE_TILESET := "res://tilesets/dungeon_tileset.tres"
const TILE := 16
## Tiles del atlas que retheme.py no puede tocar: puertas (6..8 × 3..6 y 9:3),
## objetos de la fila 6 y 7 (4..8 y 4..7) y cofres, monedas, llaves, pociones
## y antorchas (filas 8 y 9).
const PROTECTED_TILES: Array[Vector2i] = [
	Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3), Vector2i(9, 3),
	Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4),
	Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5),
	Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6),
	Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7),
]
const PROTECTED_ROWS := [8, 9]

var _cache := {}


func suite_name() -> String:
	return "dungeon_theme"


# ---------------------------------------------------------------------------
# Nivel -> tema
# ---------------------------------------------------------------------------

func test_levels_map_to_their_theme() -> void:
	var expected := {
		1: DungeonTheme.DUNGEON, 4: DungeonTheme.DUNGEON,
		5: DungeonTheme.ICE, 8: DungeonTheme.ICE,
		9: DungeonTheme.LAVA, 12: DungeonTheme.LAVA,
		13: DungeonTheme.MOSS, 16: DungeonTheme.MOSS,
		17: DungeonTheme.ICE, 21: DungeonTheme.LAVA, 25: DungeonTheme.MOSS, 29: DungeonTheme.ICE,
	}
	for level in expected:
		assert_eq(DungeonTheme.for_level(level), expected[level], "nivel %d" % level)


func test_boss_levels_close_their_theme_band() -> void:
	# Los jefes van en 8, 12 y 16: último nivel de su tema, uno por tema.
	var bosses := {8: DungeonTheme.ICE, 12: DungeonTheme.LAVA, 16: DungeonTheme.MOSS}
	for level in bosses:
		assert_eq(DungeonTheme.for_level(level), bosses[level], "jefe del nivel %d" % level)
		assert_ne(DungeonTheme.for_level(level + 1), bosses[level], "el tema sigue tras el nivel %d" % level)
		assert_eq(DungeonTheme.for_level(level - DungeonTheme.BAND_LENGTH + 1), bosses[level],
				"el tema no empieza en el nivel %d" % (level - 3))


func test_every_theme_has_its_assets() -> void:
	for theme in THEMES:
		assert_true(ResourceLoader.exists(DungeonTheme.tileset_texture_path(theme)), "tileset de %s" % theme)
		for object in ["torch", "banner", "emblem", "floor_rune", "floor_patch", "prop", "scatter"]:
			assert_true(ResourceLoader.exists(DungeonTheme.asset_path(theme, object)), "%s de %s" % [object, theme])
		var frames := ThemeDecor.torch_frames(theme)
		assert_true(frames != null and frames.has_animation(ThemeDecor.ANIMATION), "antorcha de %s" % theme)
	assert_eq(ThemeDecor.torch_frames(DungeonTheme.DUNGEON), null)


# ---------------------------------------------------------------------------
# Tileset del tema
# ---------------------------------------------------------------------------

func test_themed_tile_set_only_swaps_the_texture() -> void:
	var base: TileSet = load(BASE_TILESET)
	var base_source := base.get_source(0) as TileSetAtlasSource
	var base_path := base_source.texture.resource_path
	assert_eq(DungeonTheme.themed_tile_set(base, DungeonTheme.DUNGEON), base)
	for theme in THEMES:
		var themed := DungeonTheme.themed_tile_set(base, theme)
		var source := themed.get_source(0) as TileSetAtlasSource
		assert_ne(themed, base)
		assert_eq(source.texture.resource_path, DungeonTheme.tileset_texture_path(theme))
		assert_eq(source.get_tiles_count(), base_source.get_tiles_count(), "tiles de %s" % theme)
		assert_eq(themed.get_physics_layer_collision_layer(0), base.get_physics_layer_collision_layer(0))
		for i in base_source.get_tiles_count():
			var coords := base_source.get_tile_id(i)
			assert_eq(source.get_tile_data(coords, 0).get_collision_polygons_count(0),
					base_source.get_tile_data(coords, 0).get_collision_polygons_count(0),
					"colisión de %s en %s" % [str(coords), theme])
	# El recurso compartido no cambia.
	assert_eq((base.get_source(0) as TileSetAtlasSource).texture.resource_path, base_path)


func test_retheme_keeps_doors_chests_and_items_untouched() -> void:
	var original := _load_png(DungeonTheme.tileset_texture_path(DungeonTheme.DUNGEON))
	var protected := PROTECTED_TILES.duplicate()
	for row in PROTECTED_ROWS:
		for col in original.get_width() / TILE:
			protected.append(Vector2i(col, row))
	for theme in THEMES:
		var themed := _load_png(DungeonTheme.tileset_texture_path(theme))
		assert_eq(themed.get_size(), original.get_size(), "tamaño de %s" % theme)
		var changed := 0
		for tile in protected:
			changed += _changed_pixels(original, themed, tile)
		assert_eq(changed, 0, "píxeles de objetos recoloreados en %s" % theme)
		# El suelo y las paredes sí cambian.
		for tile in [LevelBuilder.FLOOR_TILE, LevelBuilder.WALL_TOP, LevelBuilder.WALL_LEFT]:
			assert_gt(_changed_pixels(original, themed, tile), 0, "%s sin recolorear en %s" % [str(tile), theme])


# ---------------------------------------------------------------------------
# Colocación de la decoración
# ---------------------------------------------------------------------------

func test_same_seed_gives_same_decor() -> void:
	for level in [5, 9, 13]:
		var layout := _gen(level, 4242)
		var a := ThemeDecor.plan(layout, 777)
		var b := ThemeDecor.plan(layout, 777)
		assert_eq(_signature(a), _signature(b), "nivel %d no es determinista" % level)


func test_different_seeds_give_different_decor() -> void:
	var layout := _gen(9, 31)
	var signatures := {}
	for seed_value in 10:
		signatures[_signature(ThemeDecor.plan(layout, seed_value))] = true
	assert_gt(signatures.size(), 7, "la semilla casi no cambia la decoración")


func test_decor_never_uses_reserved_cells() -> void:
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			var coins: Array[Vector2i] = [_any_room_cell(layout, run_seed)]
			var decor := ThemeDecor.plan(layout, run_seed * 7 + level, coins)
			var where := "nivel %d semilla %d" % [level, run_seed]
			# Reservadas calculadas acá, sin usar ThemeDecor.reserved_cells.
			var reserved := {layout.player_cell: true, layout.key_cell: true, coins[0]: true}
			for cell in layout.door_floor_cells():
				reserved[cell] = true
			for spawn in layout.enemies + layout.hazards:
				reserved[spawn.cell] = true
				if spawn.patrol != Vector2i.ZERO:
					var dir := Vector2i(signi(spawn.patrol.x), signi(spawn.patrol.y))
					for step in maxi(absi(spawn.patrol.x), absi(spawn.patrol.y)) + 1:
						reserved[spawn.cell + dir * step] = true
			var floor_used := {}
			for item in decor.floor_items:
				assert_true(layout.is_floor(item.cell), "objeto de suelo fuera del suelo, " + where)
				assert_false(reserved.has(item.cell), "%s sobre una celda reservada %s, %s" % [item.kind, str(item.cell), where])
				assert_false(floor_used.has(item.cell), "dos objetos en %s, %s" % [str(item.cell), where])
				floor_used[item.cell] = true
			var torches := {}
			for torch in layout.torches:
				torches[torch] = true
			var door_wall := layout.door_cell + Vector2i(0, -1)
			for item in decor.wall_items:
				assert_true(ThemeDecor.is_front_wall(layout, item.cell), "objeto de pared fuera de la pared, " + where)
				assert_false(torches.has(item.cell), "objeto de pared sobre una antorcha, " + where)
				assert_true(item.cell != door_wall and item.cell != door_wall + Vector2i(1, 0),
						"objeto de pared sobre la puerta, " + where)


func test_props_never_block_a_path() -> void:
	for level in LEVELS:
		for run_seed in SEEDS_PER_LEVEL:
			var layout := _gen(level, run_seed)
			var decor := ThemeDecor.plan(layout, run_seed + level * 1000)
			var blocked := {}
			for cell in decor.blocking_cells():
				blocked[cell] = true
				assert_true(layout.is_interior(cell), "objeto grande pegado a una pared")
			var where := "nivel %d semilla %d" % [level, run_seed]
			var before := _flood(layout, layout.player_cell, {})
			var after := _flood(layout, layout.player_cell, blocked)
			# Todo lo que se alcanzaba se sigue alcanzando, salvo las celdas de los objetos.
			assert_eq(after.size(), before.size() - blocked.size(), "un objeto corta un camino, " + where)
			for cell in layout.door_floor_cells() + [layout.key_cell]:
				assert_true(after.has(cell), "puerta o llave aislada, " + where)
			for spawn in layout.enemies + layout.hazards:
				assert_true(after.has(spawn.cell), "entidad aislada, " + where)


func test_decor_has_every_kind_somewhere() -> void:
	var kinds := {}
	for run_seed in 10:
		for item in ThemeDecor.plan(_gen(9, run_seed), run_seed).all_items():
			kinds[item.kind] = true
	for kind in [ThemeDecor.BANNER, ThemeDecor.EMBLEM, ThemeDecor.FLOOR_RUNE,
			ThemeDecor.FLOOR_PATCH, ThemeDecor.PROP, ThemeDecor.SCATTER]:
		assert_true(kinds.has(kind), "nunca se coloca %s" % kind)


func test_apply_themes_tiles_and_adds_decor() -> void:
	var root := _fake_level()
	var layout := _gen(9, 3)
	ThemeDecor.apply(root, layout, DungeonTheme.LAVA, 99)
	var dungeon: TileMapLayer = root.get_node("Dungeon")
	var texture := (dungeon.tile_set.get_source(0) as TileSetAtlasSource).texture
	assert_eq(texture.resource_path, DungeonTheme.tileset_texture_path(DungeonTheme.LAVA))
	assert_eq(root.get_node("Background/Floor").tile_set, dungeon.tile_set)
	var decor_plan := ThemeDecor.plan(layout, 99)
	var decor := root.get_node("Decor")
	assert_eq(decor.get_child_count(), decor_plan.all_items().size())
	var bodies := 0
	for child in decor.get_children():
		if child is StaticBody2D:
			bodies += 1
			assert_eq(child.collision_layer, ThemeDecor.WALL_COLLISION_LAYER)
	assert_eq(bodies, decor_plan.blocking_cells().size())
	root.free()


func test_apply_leaves_the_original_theme_alone() -> void:
	var root := _fake_level()
	var base: TileSet = root.get_node("Dungeon").tile_set
	ThemeDecor.apply(root, _gen(3, 3), DungeonTheme.DUNGEON, 99)
	assert_eq(root.get_node("Dungeon").tile_set, base)
	assert_eq(root.get_node("Decor").get_child_count(), 0)
	root.free()


# ---------------------------------------------------------------------------
# Ayudas
# ---------------------------------------------------------------------------

func _gen(level: int, run_seed: int) -> LevelGenerator.Layout:
	var key := Vector2i(level, run_seed)
	if not _cache.has(key):
		_cache[key] = LevelGenerator.generate(level, run_seed)
	return _cache[key]


func _signature(decor: ThemeDecor.Plan) -> String:
	var parts := PackedStringArray()
	for item in decor.all_items():
		parts.append("%s%s%d" % [item.kind, str(item.cell), item.variant])
	return "|".join(parts)


func _flood(layout: LevelGenerator.Layout, origin: Vector2i, blocked: Dictionary) -> Dictionary:
	var reached := {origin: true}
	var queue: Array[Vector2i] = [origin]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for dir in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
			var n: Vector2i = c + dir
			if layout.is_floor(n) and not blocked.has(n) and not reached.has(n):
				reached[n] = true
				queue.append(n)
	return reached


func _any_room_cell(layout: LevelGenerator.Layout, index: int) -> Vector2i:
	return layout.room_center(index % layout.rooms.size())


func _fake_level() -> Node2D:
	var base: TileSet = load(BASE_TILESET)
	var root := Node2D.new()
	var dungeon := TileMapLayer.new()
	dungeon.name = "Dungeon"
	dungeon.tile_set = base
	root.add_child(dungeon)
	var background := Node2D.new()
	background.name = "Background"
	root.add_child(background)
	var floor_layer := TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = base
	background.add_child(floor_layer)
	var decor := Node2D.new()
	decor.name = "Decor"
	root.add_child(decor)
	return root


func _load_png(path: String) -> Image:
	return Image.load_from_file(ProjectSettings.globalize_path(path))


func _changed_pixels(a: Image, b: Image, tile: Vector2i) -> int:
	var changed := 0
	for y in TILE:
		for x in TILE:
			var p := tile * TILE + Vector2i(x, y)
			if a.get_pixelv(p) != b.get_pixelv(p):
				changed += 1
	return changed
