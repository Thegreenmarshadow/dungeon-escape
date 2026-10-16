@tool
extends McpTestSuite
## Pruebas de la lógica del menú de pausa (PauseController): cuándo pausa y
## reanuda el árbol y que nunca interfiera con la pausa de las pantallas de fin
## de nivel. Usa un árbol falso para no pausar el árbol del editor.

const CONTROLLER_SCRIPT := preload("res://scripts/pause_controller.gd")


## Árbol falso: solo la propiedad que usa el controlador.
class FakeTree:
	var paused := false


var _tree: FakeTree
var _controller: RefCounted


func suite_name() -> String:
	return "pause_menu"


func setup() -> void:
	_tree = FakeTree.new()
	_controller = CONTROLLER_SCRIPT.new(_tree)


func test_toggle_pauses_and_resumes_the_tree() -> void:
	assert_true(_controller.toggle(), "el primer toggle abre el menú")
	assert_true(_tree.paused, "abrir el menú pausa el árbol")
	assert_false(_controller.toggle(), "el segundo toggle lo cierra")
	assert_false(_tree.paused, "cerrar el menú quita la pausa")
	assert_true(_controller.toggle(), "se puede volver a abrir")
	assert_true(_tree.paused)


func test_does_not_open_after_the_level_ended() -> void:
	# Así queda el árbol al morir el jugador o superar el nivel.
	_controller.mark_level_ended()
	_tree.paused = true
	assert_false(_controller.open(), "no debe abrirse sobre la pantalla final")
	assert_false(_controller.toggle())
	assert_false(_controller.is_open())
	assert_true(_tree.paused, "la pantalla final sigue en pausa")


func test_does_not_open_while_the_tree_is_already_paused() -> void:
	_tree.paused = true
	assert_false(_controller.open(), "la pausa es de otro: el menú no la toma")
	assert_false(_controller.resume(), "sin menú abierto no hay nada que reanudar")
	assert_true(_tree.paused, "no debe quitar una pausa ajena")


func test_resume_does_not_unpause_a_level_that_ended() -> void:
	assert_true(_controller.open())
	_controller.mark_level_ended()
	assert_false(_controller.is_open(), "el fin del nivel cierra el menú")
	assert_false(_controller.resume())
	assert_false(_controller.toggle(), "tampoco se reabre con toggle")
	assert_true(_tree.paused, "el nivel terminado sigue en pausa")
