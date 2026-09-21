extends Node2D
## Coordina el nivel: conecta al jugador y a la puerta con la interfaz
## y maneja el fin de la partida (victoria, derrota y reinicio).

@onready var dungeon: TileMapLayer = $Dungeon
@onready var player: CharacterBody2D = $Player
@onready var exit_door: Area2D = $ExitDoor
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	_fit_camera_to_map()

	# Estado inicial de la interfaz. El jugador ya ejecutó su _ready,
	# porque Godot inicializa a los hijos antes que al padre.
	hud.set_lives(player.lives)
	hud.set_has_key(player.has_key)

	player.lives_changed.connect(hud.set_lives)
	player.key_collected.connect(hud.set_has_key.bind(true))
	player.died.connect(_end_game.bind("Game Over"))
	exit_door.player_escaped.connect(_end_game.bind("¡Escapaste!"))
	exit_door.locked_touched.connect(hud.show_message.bind("Necesitas la llave"))
	hud.restart_requested.connect(_restart)


## Pausa el juego y muestra la pantalla final.
## La interfaz sigue funcionando en pausa para poder reiniciar.
func _end_game(title: String) -> void:
	hud.show_end_screen(title)
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
