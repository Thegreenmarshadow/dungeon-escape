extends Node2D
## Coordina el nivel: conecta al jugador, la puerta y los enemigos con la
## interfaz y maneja el fin de la partida (victoria, derrota y reinicio).

@onready var dungeon: TileMapLayer = $Dungeon
@onready var player: CharacterBody2D = $Player
@onready var exit_door: Area2D = $ExitDoor
@onready var hud: CanvasLayer = $HUD

var _enemies_total: int = 0
var _enemies_killed: int = 0


func _ready() -> void:
	_fit_camera_to_map()

	# Estado inicial de la interfaz. El jugador y los enemigos ya ejecutaron
	# su _ready, porque Godot inicializa a los hijos antes que al padre.
	hud.set_lives(player.lives)
	hud.set_has_key(player.has_key)

	# Cada enemigo se agrega al grupo "enemies" en EnemyBase._ready.
	var enemies := get_tree().get_nodes_in_group("enemies")
	_enemies_total = enemies.size()
	for enemy in enemies:
		enemy.died.connect(_on_enemy_died)
	hud.set_kills(_enemies_killed, _enemies_total)

	player.lives_changed.connect(hud.set_lives)
	player.key_collected.connect(hud.set_has_key.bind(true))
	player.died.connect(_end_game.bind("Game Over", ""))
	exit_door.player_escaped.connect(_on_player_escaped)
	exit_door.locked_touched.connect(hud.show_message.bind("Necesitas la llave"))
	hud.restart_requested.connect(_restart)


func _on_enemy_died(_enemy: EnemyBase) -> void:
	_enemies_killed += 1
	hud.set_kills(_enemies_killed, _enemies_total)


func _on_player_escaped() -> void:
	var stats := "Enemigos eliminados: %d/%d" % [_enemies_killed, _enemies_total]
	_end_game("¡Escapaste!", stats)


## Pausa el juego y muestra la pantalla final.
## La interfaz sigue funcionando en pausa para poder reiniciar.
func _end_game(title: String, details: String) -> void:
	hud.show_end_screen(title, details)
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


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
