class_name BossFight
extends RefCounted
## Reglas del nivel de jefe que no son del jefe mismo: el jefe lleva la llave.
##
## Al empezar el nivel la llave sale del mapa (no se ve ni se puede tocar) y,
## cuando el jefe muere, aparece donde cayó. Como la puerta necesita la llave,
## la salida espera a que el jefe esté derrotado. Level crea un BossFight si el
## nivel tiene jefe y se queda con la referencia.

## Se emite cuando la llave vuelve al mapa.
signal key_released(key: Node2D)

var boss: BossBase
var key: Node2D
## Nodo donde vuelve la llave (el nivel).
var key_parent: Node

var _key_held: bool = false


## Saca la llave del mapa hasta que boss muera. key_parent es el nodo donde
## vuelve; si la llave ya estaba recogida o no existe, no hace nada con ella.
func _init(p_boss: BossBase, p_key: Node2D, p_key_parent: Node) -> void:
	boss = p_boss
	key = p_key
	key_parent = p_key_parent
	if is_instance_valid(key) and key.is_inside_tree():
		key.get_parent().remove_child(key)
		_key_held = true
	boss.died.connect(_on_boss_died)


## true mientras el jefe tiene la llave.
func is_key_held() -> bool:
	return _key_held


## Devuelve la llave al mapa, en la posición del jefe. Es pública para las
## pruebas; en el juego la llama la muerte del jefe, diferida.
func release_key() -> void:
	if not _key_held or not is_instance_valid(key) or not is_instance_valid(key_parent):
		return
	_key_held = false
	var at := boss.global_position if is_instance_valid(boss) else key.position
	key.position = key_parent.to_local(at) if key_parent is Node2D else at
	key_parent.add_child(key)
	key_released.emit(key)


## Libera la llave si el nivel termina sin que el jefe muera (la llave fuera
## del árbol no se libera sola).
func dispose() -> void:
	if _key_held and is_instance_valid(key):
		key.free()
	_key_held = false


func _on_boss_died(_boss: EnemyBase) -> void:
	# Diferido: la muerte ocurre durante un callback de física, donde no se
	# pueden agregar áreas al mundo (la llave es un Area2D).
	release_key.call_deferred()
