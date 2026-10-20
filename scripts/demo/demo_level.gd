extends "res://scripts/level.gd"
## Nivel de la demo: un recorrido hecho a mano (DemoMap) para quien nunca jugó.
## Hereda todo el nivel normal (HUD, enemigos, corazones, jefe con su barra y
## la llave, menú de pausa, estadísticas) y le suma lo propio de la demo:
##
## - El mapa de DemoMap, dibujado con LevelBuilder. Desde DemoMap.LAVA_FROM_X
##   los tiles pasan a una capa con el tileset de lava, así se ve el cambio de
##   tema antes del Forjador.
## - Rejas (DemoGate) entre salas: la de cada sala se abre al vencer a sus
##   enemigos (o al elegir un arma en la armería). El recorrido es lineal.
## - Una ayuda corta al entrar por primera vez en cada sala (mensaje de la HUD).
## - Generosidad: Game.DEMO_LIVES vidas y nunca hay Game Over. Al quedarse sin
##   vidas el jugador vuelve, con todas, a la entrada de la última sala a la que
##   llegó; antes del jefe, a la vela del punto de control.
## - Al salir por la puerta con la llave del jefe, la pantalla de
##   agradecimiento (DemoEndScreen) en lugar de pasar de nivel.
##
## No guarda puntajes (no hay muerte que los registre) y RunTracker la anota
## con modo "demo" porque Game.demo_mode está activo.

const WEAPON_PICKUP_SCENE := preload("res://scenes/WeaponPickup.tscn")
const BANNER_SCENE := preload("res://scenes/props/Banner.tscn")

## Celdas de margen que la cámara puede mostrar alrededor del mapa.
const CAMERA_MARGIN := 2
## Segundos que se ve la ayuda de cada sala y los avisos cortos.
const HINT_TIME := 4.0
const NOTICE_TIME := 2.5
## Semilla de la decoración de lava: siempre la misma.
const DECOR_SEED := 7_202_610

const GATE_OPENED_TEXT := "¡Puerta abierta!"
const GATE_LOCKED_TEXT := {
	DemoMap.CLEAR_BY_ENEMIES: "Vence a todos para abrir",
	DemoMap.CLEAR_BY_WEAPON: "Elige un arma para seguir",
}
const WEAPON_EQUIPPED_TEXT := "¡%s equipada!"
const CHECKPOINT_TEXT := "Punto de control guardado"
const RESPAWN_TEXT := "¡De vuelta al punto de control!"

var demo_map: DemoMap
## Capa con los tiles de la parte de lava del mapa.
var lava_layer: TileMapLayer
## Rejas en orden: gates[i] separa la sala i de la i + 1.
var gates: Array[DemoGate] = []
var weapon_pickups: Array[WeaponPickup] = []
var checkpoint: DemoCheckpoint
## Sala más avanzada a la que llegó el jugador (-1 antes de empezar).
var current_room := -1
## Dónde reaparece el jugador si se queda sin vidas.
var respawn_position := Vector2.ZERO
## Segundos jugados (no corre con el juego en pausa).
var run_time := 0.0
## Veces que el jugador reapareció.
var respawns := 0

var _visited: Dictionary[int, bool] = {}
## Enemigos vivos de cada sala (índice de sala -> enemigos).
var _room_enemies: Dictionary[int, Array] = {}
var _respawn_pending := false
var _end_screen: DemoEndScreen
var _background_tile_sets: Dictionary[StringName, TileSet] = {}


func _ready() -> void:
	super()
	_assign_room_enemies()
	player.knocked_out.connect(_on_player_knocked_out)
	player.revived.connect(_on_player_revived)
	enter_room(0)


func _process(delta: float) -> void:
	super(delta)
	run_time += delta


# ---------------------------------------------------------------------------
# Construcción (la llama Level._ready antes de contar a los enemigos)
# ---------------------------------------------------------------------------

func _build_map() -> int:
	demo_map = DemoMap.create()
	map_layout = demo_map.layout
	LevelBuilder.new().build(self, demo_map.layout)
	_split_lava_tiles()
	_add_decor()
	var items := Node2D.new()
	items.name = "DemoItems"
	add_child(items)
	# Debajo del jugador y de los enemigos, como las trampas.
	move_child(items, get_node("Traps").get_index() + 1)
	_add_gates(items)
	_add_pickups(items)
	_add_room_triggers(items)
	# Más vidas que en una partida normal; los corazones curan hasta este tope.
	player.max_lives = Game.DEMO_LIVES
	player.revives_on_death = true
	return CAMERA_MARGIN


## La parte de lava del mapa va a una capa propia con el tileset de lava: los
## tiles (y sus colisiones) son los mismos, solo cambia la textura. También
## cambian las antorchas de esa parte.
func _split_lava_tiles() -> void:
	lava_layer = TileMapLayer.new()
	lava_layer.name = "DungeonLava"
	lava_layer.tile_set = DungeonTheme.themed_tile_set(dungeon.tile_set, DungeonTheme.LAVA)
	add_child(lava_layer)
	move_child(lava_layer, dungeon.get_index() + 1)
	for cell in dungeon.get_used_cells():
		if demo_map.theme_at(cell) == DungeonTheme.LAVA:
			lava_layer.set_cell(cell, dungeon.get_cell_source_id(cell), dungeon.get_cell_atlas_coords(cell))
			dungeon.erase_cell(cell)
	var lava_torches := ThemeDecor.torch_frames(DungeonTheme.LAVA)
	for torch in get_node("Decor").get_children():
		if torch is AnimatedSprite2D and demo_map.theme_at(_cell_of(torch.position)) == DungeonTheme.LAVA:
			torch.sprite_frames = lava_torches
			torch.play(ThemeDecor.ANIMATION)


## Estandartes en las salas del calabozo y la decoración del tema en las de lava
## (ThemeDecor, la misma de los niveles generados).
func _add_decor() -> void:
	var decor: Node = get_node("Decor")
	for cell in demo_map.banner_cells:
		var banner: Node2D = BANNER_SCENE.instantiate()
		banner.position = _cell_center(cell)
		decor.add_child(banner)

	var layout := demo_map.layout
	var lava := LevelGenerator.Layout.new(layout.size)
	lava.floor_cells = layout.floor_cells
	lava.door_cell = layout.door_cell
	lava.player_cell = layout.player_cell
	lava.key_cell = layout.key_cell
	lava.boss = layout.boss
	lava.enemies = layout.enemies
	lava.torches = layout.torches
	for i in demo_map.rooms.size():
		if demo_map.rooms[i].theme == DungeonTheme.LAVA:
			lava.rooms.append(demo_map.rooms[i].rect)
			if i == layout.exit_room:
				lava.exit_room = lava.rooms.size() - 1
	ThemeDecor.build(decor, ThemeDecor.plan(lava, DECOR_SEED, _reserved_cells()),
			DungeonTheme.LAVA, Vector2(dungeon.tile_set.tile_size))


## Celdas que la decoración debe dejar libres: lo que coloca la demo, las rejas
## y las entradas de las salas (por ahí se camina).
func _reserved_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.append_array(demo_map.heart_cells)
	cells.append_array(demo_map.coin_cells)
	cells.append_array(demo_map.weapon_cells.values())
	cells.append(demo_map.checkpoint_cell)
	for i in demo_map.gates.size():
		cells.append_array(demo_map.gate_cells(i))
	for room in demo_map.rooms:
		cells.append(room.respawn_cell)
		for y in [DemoMap.CORRIDOR_Y, DemoMap.CORRIDOR_Y + 1]:
			cells.append(Vector2i(room.rect.position.x, y))
			cells.append(Vector2i(room.rect.end.x - 1, y))
	return cells


func _add_gates(parent: Node) -> void:
	for i in demo_map.gates.size():
		var cell := demo_map.gates[i]
		var gate := DemoGate.new()
		var texture: Texture2D = load(DungeonTheme.tileset_texture_path(demo_map.theme_at(cell)))
		gate.setup(i, cell, Vector2(dungeon.tile_set.tile_size), texture)
		gate.locked_touched.connect(_on_gate_locked_touched)
		parent.add_child(gate)
		gates.append(gate)


func _add_pickups(parent: Node) -> void:
	for weapon_id in demo_map.weapon_cells:
		var pickup: WeaponPickup = WEAPON_PICKUP_SCENE.instantiate()
		pickup.weapon_id = weapon_id
		pickup.position = _cell_center(demo_map.weapon_cells[weapon_id])
		pickup.swapped.connect(_on_weapon_swapped)
		parent.add_child(pickup)
		weapon_pickups.append(pickup)
	for cell in demo_map.heart_cells:
		var heart: Node2D = HEART_SCENE.instantiate()
		heart.position = _cell_center(cell)
		parent.add_child(heart)
	for cell in demo_map.coin_cells:
		var coin: Coin = COIN_SCENE.instantiate()
		coin.position = _cell_center(cell)
		coin.value = 1
		parent.add_child(coin)
	checkpoint = DemoCheckpoint.new()
	checkpoint.position = _cell_center(demo_map.checkpoint_cell)
	checkpoint.activated.connect(_on_checkpoint_activated)
	parent.add_child(checkpoint)


## Un área por sala que avisa cuando el jugador entra.
func _add_room_triggers(parent: Node) -> void:
	var tile_size := Vector2(dungeon.tile_set.tile_size)
	for i in demo_map.rooms.size():
		var rect := demo_map.rooms[i].rect
		var area := Area2D.new()
		area.name = "RoomTrigger%d" % i
		area.collision_layer = 0
		area.collision_mask = 2
		area.position = (Vector2(rect.position) + Vector2(rect.size) / 2.0) * tile_size
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(rect.size) * tile_size
		shape.shape = box
		area.add_child(shape)
		area.body_entered.connect(_on_room_trigger_entered.bind(i))
		parent.add_child(area)


## Reparte a los enemigos comunes por sala según dónde aparecen. El jefe no
## cuenta: su sala no tiene reja de salida.
func _assign_room_enemies() -> void:
	for i in demo_map.rooms.size():
		_room_enemies[i] = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_ancestor_of(enemy) or enemy is BossBase:
			continue
		var room := demo_map.room_at(_cell_of(to_local(enemy.global_position)))
		if room < 0:
			continue
		_room_enemies[room].append(enemy)
		enemy.died.connect(_on_room_enemy_died.bind(room))


# ---------------------------------------------------------------------------
# Recorrido
# ---------------------------------------------------------------------------

## El jugador entra en la sala index: la primera vez muestra su ayuda. Si es la
## más avanzada hasta ahora, reaparecerá en su entrada. El fondo toma el tema
## de la sala.
func enter_room(index: int) -> void:
	if index < 0 or index >= demo_map.rooms.size():
		return
	var room := demo_map.rooms[index]
	_set_background_theme(room.theme)
	if index > current_room:
		current_room = index
		respawn_position = _cell_center(room.respawn_cell)
	if not _visited.has(index):
		_visited[index] = true
		hud.show_message(room.hint, HINT_TIME)


## Enemigos de la sala index que siguen vivos.
func room_enemies_alive(index: int) -> int:
	return _room_enemies.get(index, []).size()


## Abre la reja de salida de la sala index. Devuelve false si no tiene o ya
## estaba abierta.
func open_gate(index: int, announce: bool = true) -> bool:
	if index < 0 or index >= gates.size() or gates[index].is_open():
		return false
	gates[index].open()
	if announce:
		hud.show_message(GATE_OPENED_TEXT, NOTICE_TIME)
	return true


func _on_room_trigger_entered(body: Node2D, index: int) -> void:
	if body == player:
		enter_room(index)


func _on_room_enemy_died(enemy: EnemyBase, room: int) -> void:
	var alive: Array = _room_enemies[room]
	alive.erase(enemy)
	if alive.is_empty() and demo_map.rooms[room].clear_by == DemoMap.CLEAR_BY_ENEMIES:
		open_gate(room)


func _on_gate_locked_touched(gate: DemoGate) -> void:
	var clear_by := demo_map.rooms[gate.index].clear_by
	hud.show_message(GATE_LOCKED_TEXT.get(clear_by, GATE_LOCKED_TEXT[DemoMap.CLEAR_BY_ENEMIES]), NOTICE_TIME)


## El arma elegida pasa a ser la de la demo (Game.weapon_id) y la primera
## elección abre la reja de la armería.
func _on_weapon_swapped(new_weapon: WeaponData, _old_weapon: WeaponData) -> void:
	Game.weapon_id = new_weapon.id
	var text: String = WEAPON_EQUIPPED_TEXT % new_weapon.display_name
	if open_gate(demo_map.room_index(&"armory"), false):
		text += " " + GATE_OPENED_TEXT
	hud.show_message(text, NOTICE_TIME)


func _on_checkpoint_activated(_checkpoint: DemoCheckpoint) -> void:
	respawn_position = _cell_center(demo_map.checkpoint_cell + Vector2i(0, 1))
	current_room = maxi(current_room, demo_map.room_index(&"antechamber"))
	hud.show_message(CHECKPOINT_TEXT, NOTICE_TIME)


# ---------------------------------------------------------------------------
# Generosidad: puntos de control en lugar de Game Over
# ---------------------------------------------------------------------------

## El jugador se quedó sin vidas: reaparece en el punto de control. Diferido,
## porque el golpe llega durante un callback de física.
func _on_player_knocked_out() -> void:
	_respawn_pending = true
	respawn_player.call_deferred()


## Revive al jugador en respawn_position con todas las vidas de la demo. Solo
## hace algo si quedó pendiente (el jugador se quedó sin vidas).
func respawn_player() -> void:
	if not _respawn_pending:
		return
	_respawn_pending = false
	respawns += 1
	player.revive(respawn_position, Game.DEMO_LIVES)


func _on_player_revived(lives: int) -> void:
	Game.lives = lives
	hud.set_lives(lives, player.max_lives)
	hud.show_message(RESPAWN_TEXT, NOTICE_TIME)


## En la demo el jugador nunca muere (revives_on_death); por si acaso, morir
## también lleva al punto de control y nunca guarda un puntaje.
func _on_player_died() -> void:
	_on_player_knocked_out()


# ---------------------------------------------------------------------------
# Final
# ---------------------------------------------------------------------------

## Salió por la puerta con la llave del Forjador: pantalla de agradecimiento.
func _on_player_escaped() -> void:
	if _end_screen != null:
		return
	Sfx.play(&"level_complete")
	hud.message_label.hide()
	_end_screen = DemoEndScreen.new()
	add_child(_end_screen)
	_end_screen.replay_pressed.connect(Game.start_demo)
	_end_screen.menu_pressed.connect(Game.go_to_menu)
	_end_screen.show_summary(run_time, Game.enemies_killed)
	get_tree().paused = true


func end_screen() -> DemoEndScreen:
	return _end_screen


# ---------------------------------------------------------------------------
# Ayudas
# ---------------------------------------------------------------------------

func _map_used_rect() -> Rect2i:
	var used := dungeon.get_used_rect()
	if lava_layer != null:
		used = used.merge(lava_layer.get_used_rect())
	return used


## El fondo de piedra toma el tileset del tema de la sala.
func _set_background_theme(theme: StringName) -> void:
	var background := get_node_or_null("Background/Floor") as TileMapLayer
	if background == null:
		return
	if _background_tile_sets.is_empty():
		_background_tile_sets[DungeonTheme.DUNGEON] = background.tile_set
	if not _background_tile_sets.has(theme):
		_background_tile_sets[theme] = DungeonTheme.themed_tile_set(
				_background_tile_sets[DungeonTheme.DUNGEON], theme)
	background.tile_set = _background_tile_sets[theme]


func _cell_center(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * Vector2(dungeon.tile_set.tile_size)


func _cell_of(local_position: Vector2) -> Vector2i:
	return Vector2i((local_position / Vector2(dungeon.tile_set.tile_size)).floor())
