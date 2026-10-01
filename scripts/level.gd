extends Node2D
## Coordina el nivel: conecta al jugador, la puerta y los enemigos con la
## interfaz y maneja el fin del nivel (superado o derrota).

const LEVEL_MUSIC := preload("res://assets/music/dungeon_ambient_jaggedstone.ogg")
## Celdas de margen alrededor del mapa generado que la cámara puede mostrar,
## para no ver el borde exacto de las paredes.
const GENERATED_CAMERA_MARGIN := 3
const HEART_SCENE := preload("res://scenes/Heart.tscn")

@onready var dungeon: TileMapLayer = $Dungeon
@onready var player: CharacterBody2D = $Player
@onready var exit_door: Area2D = $ExitDoor
@onready var hud: CanvasLayer = $HUD

var _enemies_total: int = 0
var _enemies_killed: int = 0


func _ready() -> void:
	Music.play_track(LEVEL_MUSIC)

	# El nivel 1 es el mapa hecho a mano de esta escena; del 2 en adelante se
	# reemplaza por uno generado. Debe ocurrir antes de contar a los enemigos.
	var camera_margin := 0
	if Game.current_level >= LevelGenerator.FIRST_GENERATED_LEVEL:
		_build_generated_level()
		camera_margin = GENERATED_CAMERA_MARGIN
	_fit_camera_to_map(camera_margin)

	# Las vidas vienen del estado global, así se conservan entre niveles.
	# Se asignan acá porque el jugador ya ejecutó su _ready: Godot inicializa
	# a los hijos antes que al padre.
	player.lives = Game.lives

	# Estado inicial de la interfaz.
	hud.set_lives(player.lives, player.max_lives)
	hud.set_has_key(player.has_key)

	# Cada enemigo se agrega al grupo "enemies" en EnemyBase._ready.
	var enemies := get_tree().get_nodes_in_group("enemies")
	_enemies_total = enemies.size()
	for enemy in enemies:
		enemy.died.connect(_on_enemy_died)
		enemy.died.connect(_try_drop_heart)
	hud.set_kills(_enemies_killed, _enemies_total)

	player.lives_changed.connect(_on_lives_changed)
	player.key_collected.connect(hud.set_has_key.bind(true))
	player.died.connect(_on_player_died)
	exit_door.player_escaped.connect(_on_player_escaped)
	exit_door.locked_touched.connect(hud.show_message.bind("Necesitas la llave"))
	hud.show_message("Nivel %d" % Game.current_level)


## Genera el mapa de Game.current_level (determinista con Game.run_seed) y lo
## dibuja en esta escena.
func _build_generated_level() -> void:
	var layout := LevelGenerator.generate(Game.current_level, Game.run_seed)
	LevelBuilder.new().build(self, layout)
	print("Mapa generado, %s (semilla de partida %d)" % [layout.summary(), Game.run_seed])


func _on_lives_changed(lives: int) -> void:
	Game.lives = lives
	hud.set_lives(lives, player.max_lives)


func _on_enemy_died(_enemy: EnemyBase) -> void:
	# El conteo local es del nivel (para el HUD); el global suma puntos.
	_enemies_killed += 1
	Game.register_kill()
	hud.set_kills(_enemies_killed, _enemies_total)


## Según la probabilidad del enemigo, deja un corazón donde murió. El enemigo
## no sabe nada de los corazones: solo expone heart_drop_chance.
func _try_drop_heart(enemy: EnemyBase) -> void:
	if not Heart.should_drop(enemy.heart_drop_chance, randf()):
		return
	# Diferido: la muerte ocurre durante un callback de física, donde no se
	# pueden agregar áreas al mundo.
	_spawn_heart.call_deferred(to_local(enemy.global_position))


func _spawn_heart(at: Vector2) -> void:
	var heart: Node2D = HEART_SCENE.instantiate()
	heart.position = at
	add_child(heart)


func _on_player_died() -> void:
	# Los niveles no terminan nunca: la derrota es el único fin de una partida,
	# así que acá se registra en la tabla de puntajes. El jugador emite died
	# una sola vez (take_damage se ignora con 0 vidas).
	var run := ScoreBoard.record_run(Game.score, Game.current_level, Game.enemies_killed)
	# Conexiones normales (no de un solo uso): la HUD emite una sola de las dos
	# señales y desactiva los botones, y el cambio de escena libera la HUD.
	hud.retry_pressed.connect(Game.start_new_game)
	hud.menu_pressed.connect(Game.go_to_menu)
	hud.show_game_over(Game.current_level, Game.enemies_killed, Game.score,
			run["is_new_record"], _record_text(run))
	get_tree().paused = true


## Línea de récord de Game Over cuando la partida no superó el récord: el
## puesto alcanzado (si entró en la tabla) y el mejor puntaje. Vacía si todavía
## no hay ningún récord, para no mostrar "Récord: 0".
func _record_text(run: Dictionary) -> String:
	var best: int = run["previous_best"]
	if best <= 0:
		best = ScoreBoard.best_score(run["board"])
	if best <= 0:
		return ""
	var record := "Récord: %d" % best
	if run["recorded"]:
		return "Puesto #%d · %s" % [run["rank"], record]
	return record


func _on_player_escaped() -> void:
	var completed_level := Game.current_level
	Game.complete_level()
	var stats := "Nivel %d · Enemigos eliminados: %d/%d\nPuntos: %d" % [
		completed_level, _enemies_killed, _enemies_total, Game.score]
	_end_level("¡Nivel superado!", stats, "Siguiente nivel", Game.start_level)


## Pausa el juego y muestra la pantalla de nivel superado. El botón de la
## pantalla ejecuta action. La interfaz sigue funcionando en pausa.
func _end_level(title: String, details: String, action_text: String, action: Callable) -> void:
	hud.show_end_screen(title, details, action_text)
	hud.action_pressed.connect(action, CONNECT_ONE_SHOT)
	get_tree().paused = true


## Limita la cámara del jugador al área ocupada por el mapa, para que no muestre
## el vacío fuera de los bordes. Se calcula desde los tiles, así se adapta
## automáticamente si el mapa cambia de tamaño. margin_tiles agranda esa área.
func _fit_camera_to_map(margin_tiles: int = 0) -> void:
	var used := dungeon.get_used_rect().grow(margin_tiles)
	var tile_size := dungeon.tile_set.tile_size
	var camera: Camera2D = player.get_node("Camera2D")
	camera.limit_left = used.position.x * tile_size.x
	camera.limit_top = used.position.y * tile_size.y
	camera.limit_right = used.end.x * tile_size.x
	camera.limit_bottom = used.end.y * tile_size.y
