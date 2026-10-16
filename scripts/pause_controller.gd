@tool
class_name PauseController
extends RefCounted
## Lógica del menú de pausa, separada de la interfaz para probarla sin escenas
## y sin pausar el árbol real. Pausa y reanuda tree: el SceneTree del juego o,
## en las pruebas, cualquier objeto con una propiedad paused.
##
## Reglas:
##   - Solo abre si el árbol no está en pausa: las pantallas de fin de nivel ya
##     lo pausan y el menú no debe abrirse encima de ellas.
##   - Una vez terminado el nivel (mark_level_ended) no vuelve a abrir y, si
##     estaba abierto, se cierra sin reanudar: la pausa pasa a ser de la
##     pantalla final.
##   - Reanudar solo quita la pausa que puso este menú.

var tree: Object
var _open := false
var _level_ended := false


func _init(p_tree: Object) -> void:
	tree = p_tree


func is_open() -> bool:
	return _open


func can_open() -> bool:
	return not _open and not _level_ended and not tree.paused


## Pausa el árbol y marca el menú como abierto. Devuelve false si no se puede
## abrir (ya abierto, nivel terminado o árbol ya en pausa).
func open() -> bool:
	if not can_open():
		return false
	_open = true
	tree.paused = true
	return true


## Cierra el menú y quita la pausa, salvo que el nivel haya terminado mientras
## estaba abierto. Devuelve false si el menú no estaba abierto.
func resume() -> bool:
	if not _open:
		return false
	_open = false
	if not _level_ended:
		tree.paused = false
	return true


## Abre o cierra el menú. Devuelve si quedó abierto.
func toggle() -> bool:
	if _open:
		resume()
	else:
		open()
	return _open


## El nivel terminó (derrota o nivel superado): el menú no vuelve a abrirse y
## la pausa queda en manos de la pantalla final.
func mark_level_ended() -> void:
	_level_ended = true
	_open = false
