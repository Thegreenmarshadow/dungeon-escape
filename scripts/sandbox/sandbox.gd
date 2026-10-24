extends Node2D
## Zona de pruebas: una sala cerrada con el jugador y un panel para equipar
## cualquier arma, hacer aparecer cualquier enemigo y revisar cómo se ven y se
## juegan. Solo se abre desde el menú en builds de depuración.
##
## No es una partida: no toca Game (salvo para volver al menú), no empieza ni
## registra partidas en RunTracker (esta escena no es Level y nunca emite
## Game.run_started), no guarda puntajes y los enemigos no sueltan monedas ni
## corazones. Al salir deja como estaban la velocidad del juego y la vista de
## colisiones.
##
## Teclas: 1-9 hacen aparecer al enemigo de ese número, Q/E cambian de arma,
## K mata a todos, L limpia, I invencible, F enemigos quietos, H hitboxes,
## T cámara lenta y Y cambia el tema. Escape abre la pausa.

const EXPLORATION_MUSIC := preload("res://assets/music/dungeon_exploration.ogg")

## Celdas de la grilla de la sala, con las paredes del borde incluidas.
const ARENA_SIZE := Vector2i(22, 13)
## Celda donde empieza el jugador.
const PLAYER_CELL := Vector2i(6, 6)
## Píxeles por delante del jugador donde aparece un enemigo nuevo, y cuánto se
## corre al azar para que varios no queden encimados.
const SPAWN_DISTANCE := 36.0
const SPAWN_JITTER := 6.0
## Velocidad del juego con la cámara lenta.
const SLOW_MOTION_SCALE := 0.25
## Ancho del panel en píxeles de pantalla; la cámara deja ese espacio a la
## derecha para que el panel no tape la sala.
const PANEL_WIDTH := 360.0

## Temas de la sala: id de DungeonTheme y texto del botón.
const THEMES: Array[Dictionary] = [
	{"id": DungeonTheme.DUNGEON, "name": "Original"},
	{"id": DungeonTheme.ICE, "name": "Hielo"},
	{"id": DungeonTheme.LAVA, "name": "Lava"},
	{"id": DungeonTheme.MOSS, "name": "Musgo"},
]

@onready var dungeon: TileMapLayer = $Dungeon
@onready var background_floor: TileMapLayer = $Background/Floor
@onready var spawned: Node2D = $Spawned
@onready var player: CharacterBody2D = $Player
@onready var status_label: Label = %StatusLabel
@onready var weapon_info_label: Label = %WeaponInfoLabel
@onready var weapon_grid: GridContainer = %WeaponGrid
@onready var enemy_grid: GridContainer = %EnemyGrid
@onready var theme_box: HBoxContainer = %ThemeBox
@onready var kill_all_button: Button = %KillAllButton
@onready var clear_button: Button = %ClearButton
@onready var invincible_check: CheckButton = %InvincibleCheck
@onready var freeze_check: CheckButton = %FreezeCheck
@onready var hitboxes_check: CheckButton = %HitboxesCheck
@onready var slow_check: CheckButton = %SlowCheck
@onready var back_button: Button = %BackButton

var weapons: Array[WeaponData] = []
var enemies: Array[Dictionary] = []
var current_theme: StringName = DungeonTheme.DUNGEON
var enemies_frozen := false

var _weapon_buttons: Array[Button] = []
var _theme_buttons: Array[Button] = []
var _enemy_scenes: Dictionary[StringName, PackedScene] = {}
var _base_tile_set: TileSet
var _base_background_tile_set: TileSet
var _themed_tile_sets: Dictionary[StringName, TileSet] = {}
# Lo que había antes de entrar, para dejarlo igual al salir.
var _previous_time_scale := 1.0
var _previous_collisions_hint := false


func _ready() -> void:
	_previous_time_scale = Engine.time_scale
	_previous_collisions_hint = get_tree().debug_collisions_hint
	_base_tile_set = dungeon.tile_set
	_base_background_tile_set = background_floor.tile_set
	Music.play_track(EXPLORATION_MUSIC)

	_build_arena()
	var tile_size := Vector2(dungeon.tile_set.tile_size)
	player.position = (Vector2(PLAYER_CELL) + Vector2(0.5, 0.5)) * tile_size
	_fit_camera()
	# El jugador nunca muere acá: si se queda sin vida vuelve a tenerla toda.
	player.died.connect(_revive_player)

	weapons = SandboxCatalog.load_weapons()
	enemies = SandboxCatalog.enemy_entries()
	_build_weapon_buttons()
	_build_enemy_buttons()
	_build_theme_buttons()
	kill_all_button.pressed.connect(kill_all_enemies)
	clear_button.pressed.connect(clear_spawned)
	invincible_check.toggled.connect(func(on: bool) -> void: player.invincible = on)
	freeze_check.toggled.connect(set_enemies_frozen)
	hitboxes_check.toggled.connect(set_hitboxes_visible)
	slow_check.toggled.connect(set_slow_motion)
	back_button.pressed.connect(_on_back_pressed)
	equip_weapon_id(player.weapon.id)


func _exit_tree() -> void:
	Engine.time_scale = _previous_time_scale
	get_tree().debug_collisions_hint = _previous_collisions_hint


func _process(_delta: float) -> void:
	status_label.text = "Vida: %s/%s corazones · Enemigos: %d" % [Heart.format_hearts(player.health),
			Heart.format_hearts(player.max_health), alive_enemy_count()]


## Atajos de teclado del panel. Los botones del panel no toman el foco, así
## Espacio sigue siendo atacar y las flechas siguen moviendo al jugador.
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var handled := true
	match key.keycode:
		KEY_Q:
			_cycle_weapon(-1)
		KEY_E:
			_cycle_weapon(1)
		KEY_K:
			kill_all_enemies()
		KEY_L:
			clear_spawned()
		KEY_I:
			invincible_check.button_pressed = not invincible_check.button_pressed
		KEY_F:
			freeze_check.button_pressed = not freeze_check.button_pressed
		KEY_H:
			hitboxes_check.button_pressed = not hitboxes_check.button_pressed
		KEY_T:
			slow_check.button_pressed = not slow_check.button_pressed
		KEY_Y:
			_cycle_theme()
		_:
			var index := key.keycode - KEY_1
			if index >= 0 and index < mini(enemies.size(), 9):
				spawn_enemy(index)
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


# ----- armas -----

## Equipa el arma weapon_id en el jugador y la marca en el panel. Solo cambia
## al jugador de esta escena: Game.weapon_id (el arma de la partida) no se toca.
## Devuelve false si el arma no existe.
func equip_weapon_id(weapon_id: StringName) -> bool:
	var index := _weapon_index(weapon_id)
	if index < 0:
		return false
	player.equip_weapon(weapons[index])
	# Sin señal: los botones ya están conectados a esta función.
	for i in _weapon_buttons.size():
		_weapon_buttons[i].set_pressed_no_signal(i == index)
	_show_weapon_info(weapons[index])
	return true


func _weapon_index(weapon_id: StringName) -> int:
	for i in weapons.size():
		if weapons[i].id == weapon_id:
			return i
	return -1


func _cycle_weapon(step: int) -> void:
	if weapons.is_empty():
		return
	var index := wrapi(_weapon_index(player.weapon.id) + step, 0, weapons.size())
	equip_weapon_id(weapons[index].id)


func _show_weapon_info(weapon: WeaponData) -> void:
	var kind := "mecánicas completas" if SandboxCatalog.has_full_mechanics(weapon.id) \
			else "solo stats base"
	weapon_info_label.text = "%s (%s)\nDaño %d · anticipación %.2f s · golpe %.2f s · enfriamiento %.2f s\n%s" % [
		weapon.display_name, kind, weapon.damage, weapon.windup, weapon.active_time,
		weapon.cooldown, weapon.description]


func _build_weapon_buttons() -> void:
	var group := ButtonGroup.new()
	for weapon in weapons:
		var full := SandboxCatalog.has_full_mechanics(weapon.id)
		var button := _make_button("%s%s" % [weapon.display_name, " ★" if full else ""])
		button.icon = weapon.icon
		button.expand_icon = true
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = "%s: %s" % [weapon.display_name, "mecánicas completas" if full
				else "solo stats base, sus mecánicas propias todavía no están hechas"]
		if not full:
			button.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
		button.pressed.connect(equip_weapon_id.bind(weapon.id))
		weapon_grid.add_child(button)
		_weapon_buttons.append(button)


# ----- enemigos -----

## Hace aparecer al enemigo enemies[index] delante del jugador, dentro de la
## sala. Devuelve el enemigo creado, o null si index no existe.
func spawn_enemy(index: int) -> Node2D:
	if index < 0 or index >= enemies.size():
		return null
	var enemy: Node2D = _enemy_scene(index).instantiate()
	var jitter := Vector2(randf_range(-SPAWN_JITTER, SPAWN_JITTER), randf_range(-SPAWN_JITTER, SPAWN_JITTER))
	# Antes de entrar al árbol: el esqueleto y los perseguidores toman su punto
	# de partida en _ready.
	enemy.position = _clamp_to_arena(player.position + player.facing * SPAWN_DISTANCE + jitter)
	spawned.add_child(enemy)
	# Después de _ready, que vuelve a activar el proceso de física.
	_set_frozen(enemy, enemies_frozen)
	return enemy


func _enemy_scene(index: int) -> PackedScene:
	var entry := enemies[index]
	var id: StringName = entry["id"]
	if not _enemy_scenes.has(id):
		_enemy_scenes[id] = load(entry["scene"])
	return _enemy_scenes[id]


## Mata a todos los enemigos con su animación de muerte. Los proyectiles en el
## aire siguen; "Limpiar" los quita.
func kill_all_enemies() -> void:
	for node in spawned.get_children():
		var enemy := node as EnemyBase
		if enemy != null and not enemy.is_dying:
			# El camino normal de la muerte de cada enemigo, sin pasar por la
			# vida ni la esquiva.
			enemy._die()


## Quita al instante todo lo que apareció: enemigos y proyectiles.
func clear_spawned() -> void:
	for node in spawned.get_children():
		spawned.remove_child(node)
		node.queue_free()


func alive_enemy_count() -> int:
	var count := 0
	for node in spawned.get_children():
		if node is EnemyBase and not node.is_dying:
			count += 1
	return count


func _build_enemy_buttons() -> void:
	for i in enemies.size():
		var entry := enemies[i]
		var text: String = entry["name"]
		if i < 9:
			text = "%d. %s" % [i + 1, text]
		var button := _make_button(text)
		button.icon = _enemy_icon(i)
		button.expand_icon = true
		button.pressed.connect(func() -> void: spawn_enemy(i))
		enemy_grid.add_child(button)


## Primer cuadro de la animación de reposo del enemigo, para el botón.
func _enemy_icon(index: int) -> Texture2D:
	var enemy := _enemy_scene(index).instantiate()
	var sprite := enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var icon: Texture2D = null
	if sprite != null and sprite.sprite_frames != null:
		var animation := sprite.animation
		if not sprite.sprite_frames.has_animation(animation):
			animation = sprite.sprite_frames.get_animation_names()[0]
		if sprite.sprite_frames.get_frame_count(animation) > 0:
			icon = sprite.sprite_frames.get_frame_texture(animation, 0)
	enemy.free()
	return icon


# ----- opciones -----

## Con frozen en true los enemigos y sus proyectiles no se mueven, no atacan ni
## lastiman, pero siguen animados y reciben golpes (se ven el golpe y la muerte).
func set_enemies_frozen(frozen: bool) -> void:
	enemies_frozen = frozen
	for node in spawned.get_children():
		_set_frozen(node, frozen)


func _set_frozen(node: Node, frozen: bool) -> void:
	node.set_physics_process(not frozen)


## Muestra las formas de colisión: la hitbox del arma, los cuerpos y las áreas
## de los enemigos, los proyectiles y las paredes.
func set_hitboxes_visible(show_shapes: bool) -> void:
	get_tree().debug_collisions_hint = show_shapes
	dungeon.collision_visibility_mode = TileMapLayer.DEBUG_VISIBILITY_MODE_FORCE_SHOW if show_shapes \
			else TileMapLayer.DEBUG_VISIBILITY_MODE_FORCE_HIDE
	# Las formas solo se dibujan de nuevo si se les pide.
	_redraw_shapes(self)


func _redraw_shapes(node: Node) -> void:
	if node is CollisionShape2D or node is CollisionPolygon2D:
		(node as CanvasItem).queue_redraw()
	for child in node.get_children():
		_redraw_shapes(child)


func set_slow_motion(slow: bool) -> void:
	Engine.time_scale = SLOW_MOTION_SCALE if slow else 1.0


# ----- tema -----

## Cambia el tileset de la sala (y del fondo) al del tema.
func set_theme(theme: StringName) -> void:
	current_theme = theme
	if not _themed_tile_sets.has(theme):
		_themed_tile_sets[theme] = DungeonTheme.themed_tile_set(_base_tile_set, theme)
	dungeon.tile_set = _themed_tile_sets[theme]
	var background_key := StringName("background_%s" % theme)
	if not _themed_tile_sets.has(background_key):
		_themed_tile_sets[background_key] = DungeonTheme.themed_tile_set(_base_background_tile_set, theme)
	background_floor.tile_set = _themed_tile_sets[background_key]
	for i in THEMES.size():
		_theme_buttons[i].set_pressed_no_signal(THEMES[i]["id"] == theme)


func _cycle_theme() -> void:
	var index := 0
	for i in THEMES.size():
		if THEMES[i]["id"] == current_theme:
			index = i
	set_theme(THEMES[(index + 1) % THEMES.size()]["id"])


func _build_theme_buttons() -> void:
	var group := ButtonGroup.new()
	for entry in THEMES:
		var button := _make_button(entry["name"])
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(set_theme.bind(entry["id"]))
		theme_box.add_child(button)
		_theme_buttons.append(button)
	_theme_buttons[0].set_pressed_no_signal(true)


# ----- sala -----

## Dibuja la sala: suelo con un borde de pared, con los mismos tiles (y
## colisiones) que los mapas generados.
func _build_arena() -> void:
	var layout := LevelGenerator.Layout.new(ARENA_SIZE)
	# carve_rect deja siempre pared en el borde de la grilla.
	layout.carve_rect(Rect2i(Vector2i.ZERO, ARENA_SIZE))
	dungeon.clear()
	for y in ARENA_SIZE.y:
		for x in ARENA_SIZE.x:
			var cell := Vector2i(x, y)
			if layout.is_floor(cell):
				dungeon.set_cell(cell, LevelBuilder.SOURCE_ID, LevelBuilder.FLOOR_TILE)
			else:
				var tile := LevelBuilder.wall_tile_for(layout, cell)
				if tile != LevelBuilder.NO_TILE:
					dungeon.set_cell(cell, LevelBuilder.SOURCE_ID, tile)


## Lleva position al suelo de la sala, a media celda de las paredes.
func _clamp_to_arena(position_in_room: Vector2) -> Vector2:
	var tile_size := Vector2(dungeon.tile_set.tile_size)
	var low := tile_size * 1.5
	var high := Vector2(ARENA_SIZE) * tile_size - tile_size * 1.5
	return position_in_room.clamp(low, high)


## Limita la cámara a la sala, con lugar a la derecha para el panel.
func _fit_camera() -> void:
	var tile_size := Vector2(dungeon.tile_set.tile_size)
	var camera: Camera2D = player.get_node("Camera2D")
	var margin := tile_size * 2.0
	camera.limit_left = int(-margin.x)
	camera.limit_top = int(-margin.y)
	camera.limit_right = int(ARENA_SIZE.x * tile_size.x + margin.x + PANEL_WIDTH / camera.zoom.x)
	camera.limit_bottom = int(ARENA_SIZE.y * tile_size.y + margin.y)


# ----- otros -----

## El jugador se quedó sin vida: vuelve a tenerla toda y sigue jugando.
func _revive_player() -> void:
	player.health = player.max_health
	player.set_physics_process(true)


func _on_back_pressed() -> void:
	back_button.disabled = true
	Game.go_to_menu()


## Botón del panel: sin foco, así no se roba las teclas del jugador.
func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 30)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Los nombres largos se recortan en lugar de ensanchar el panel.
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	button.add_theme_font_size_override("font_size", 14)
	return button
