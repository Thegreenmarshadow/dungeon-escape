extends Node2D
## Coordina el nivel: conecta al jugador, la puerta y los enemigos con la
## interfaz y maneja el fin del nivel (superado o derrota).

@onready var dungeon: TileMapLayer = $Dungeon
@onready var player: CharacterBody2D = $Player
@onready var exit_door: Area2D = $ExitDoor
@onready var hud: CanvasLayer = $HUD

var _enemies_total: int = 0
var _enemies_killed: int = 0


func _ready() -> void:
	_fit_camera_to_map()

	# Las vidas vienen del estado global, así se conservan entre niveles.
	# Se asignan acá porque el jugador ya ejecutó su _ready: Godot inicializa
	# a los hijos antes que al padre.
	player.lives = Game.lives

	# Estado inicial de la interfaz.
	hud.set_lives(player.lives)
	hud.set_has_key(player.has_key)

	# Cada enemigo se agrega al grupo "enemies" en EnemyBase._ready.
	var enemies := get_tree().get_nodes_in_group("enemies")
	_enemies_total = enemies.size()
	for enemy in enemies:
		enemy.died.connect(_on_enemy_died)
	hud.set_kills(_enemies_killed, _enemies_total)

	player.lives_changed.connect(_on_lives_changed)
	player.key_collected.connect(hud.set_has_key.bind(true))
	player.died.connect(_on_player_died)
	exit_door.player_escaped.connect(_on_player_escaped)
	exit_door.locked_touched.connect(hud.show_message.bind("Necesitas la llave"))


func _on_lives_changed(lives: int) -> void:
	Game.lives = lives
	hud.set_lives(lives)


func _on_enemy_died(_enemy: EnemyBase) -> void:
	# El conteo local es del nivel (para el HUD); el global suma puntos.
	_enemies_killed += 1
	Game.register_kill()
	hud.set_kills(_enemies_killed, _enemies_total)


func _on_player_died() -> void:
	_end_level("Game Over", "Puntos: %d" % Game.score, "Volver al menú", Game.go_to_menu)


func _on_player_escaped() -> void:
	var completed_level := Game.current_level
	Game.complete_level()
	var stats := "Nivel %d · Enemigos eliminados: %d/%d\nPuntos: %d" % [
		completed_level, _enemies_killed, _enemies_total, Game.score]
	_end_level("¡Nivel superado!", stats, "Siguiente nivel", Game.start_level)


## Pausa el juego y muestra la pantalla final. El botón de la pantalla
## ejecuta action. La interfaz sigue funcionando en pausa.
func _end_level(title: String, details: String, action_text: String, action: Callable) -> void:
	hud.show_end_screen(title, details, action_text)
	hud.action_pressed.connect(action, CONNECT_ONE_SHOT)
	get_tree().paused = true


## Limita la cámara del jugador al área ocupada por el mapa, para que no muestre
## el vacío fuera de los bordes. Se calcula desde los tiles, así se adapta
## automáticamente si el mapa cambia de tamaño.
func _fit_camera_to_map() -> void:
	var used := dungeon.get_used_rect()
	var tile_size := dungeon.tile_set.tile_size
	var camera: Camera2D = player.get_node("Camera2D")
	camera.limit_left = used.position.x * tile_size.x
	camera.limit_top = used.position.y * tile_size.y
	camera.limit_right = used.end.x * tile_size.x
	camera.limit_bottom = used.end.y * tile_size.y
