extends Node
## Estado global de la partida. Se registra como Autoload ("Game") para que
## sobreviva a los cambios de escena: el nivel, el menú y las pantallas finales
## leen y escriben acá en lugar de guardar estos datos ellos mismos.

## Vidas con las que empieza cada partida nueva.
const STARTING_LIVES := 3
## Puntos por cada enemigo eliminado.
const POINTS_PER_KILL := 10
## Puntos por cada nivel superado.
const POINTS_PER_LEVEL := 100

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const LEVEL_SCENE := "res://scenes/Level.tscn"

## Nivel que se está jugando, empezando en 1.
var current_level: int = 1
## Vidas restantes; se conservan entre niveles.
var lives: int = STARTING_LIVES
## Enemigos eliminados en toda la partida.
var enemies_killed: int = 0
var score: int = 0


## Reinicia todo el estado para empezar una partida desde el nivel 1.
func new_game() -> void:
	current_level = 1
	lives = STARTING_LIVES
	enemies_killed = 0
	score = 0


func register_kill() -> void:
	enemies_killed += 1
	score += POINTS_PER_KILL


## Suma los puntos del nivel superado y avanza al siguiente.
func complete_level() -> void:
	score += POINTS_PER_LEVEL
	current_level += 1


## Empieza una partida nueva desde el nivel 1.
func start_new_game() -> void:
	new_game()
	start_level()


## Carga el nivel actual. Por ahora todos los niveles usan el mismo mapa.
func start_level() -> void:
	_change_scene(LEVEL_SCENE)


func go_to_menu() -> void:
	_change_scene(MENU_SCENE)


func _change_scene(path: String) -> void:
	# Las pantallas finales pausan el juego; la escena nueva debe arrancar
	# sin pausa.
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
