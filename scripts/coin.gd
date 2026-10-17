class_name Coin
extends Area2D
## Moneda recolectable: la sueltan los enemigos al morir y algunas aparecen
## sueltas en los mapas generados. Al tocarla, el jugador suma su valor a las
## monedas de la partida (Game.coins), que se gastan en la tienda entre niveles.

## Monedas que suma al recogerla.
@export var value: int = 1

# Evita sumar dos veces si se toca otra vez antes de liberarse.
var _collected: bool = false


## Decide si un enemigo suelta una moneda. Misma regla que los corazones:
## chance es la probabilidad (0 a 1) y roll un número aleatorio entre 0 y 1.
static func should_drop(chance: float, roll: float) -> bool:
	return Heart.should_drop(chance, roll)


## Valor de una moneda soltada, repartido por igual entre min_value y max_value
## (ambos incluidos). roll es un número aleatorio entre 0 y 1; con roll 1
## (randf() puede devolverlo) da max_value.
static func value_for(min_value: int, max_value: int, roll: float) -> int:
	var low := mini(min_value, max_value)
	var high := maxi(min_value, max_value)
	return mini(low + int(roll * (high - low + 1)), high)


## Valor de una moneda en un nivel cuyos enemigos tienen la vida multiplicada
## por scale (LevelGenerator.enemy_health_scale): crece igual que ellos, se
## redondea y nunca baja del valor base. Así los enemigos más duros pagan más y
## lo que se gana sigue el ritmo de lo que cuesta la tienda.
static func scaled_value(value: int, scale: float) -> int:
	return maxi(roundi(value * scale), value)


## Elige hasta count celdas del mapa para monedas sueltas, siempre las mismas
## para el mismo seed_value. Solo usa celdas interiores de las salas (lejos de
## las paredes) que no ocupan el jugador, la llave, la puerta, los enemigos ni
## las trampas. No cambia el mapa ni lo que el generador coloca.
static func scatter_cells(layout: LevelGenerator.Layout, seed_value: int, count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if layout.rooms.is_empty() or count <= 0:
		return cells
	var taken := {
		layout.player_cell: true,
		layout.key_cell: true,
		layout.door_cell: true,
		layout.door_cell + Vector2i(1, 0): true,
	}
	for spawn in layout.enemies + layout.hazards:
		taken[spawn.cell] = true

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Intentos acotados: un mapa muy lleno puede dar menos monedas, nunca un
	# bucle infinito.
	var tries := count * 20
	while cells.size() < count and tries > 0:
		tries -= 1
		var room: Rect2i = layout.rooms[rng.randi_range(0, layout.rooms.size() - 1)]
		var cell := Vector2i(rng.randi_range(room.position.x, room.end.x - 1),
				rng.randi_range(room.position.y, room.end.y - 1))
		if taken.has(cell) or not layout.is_interior(cell):
			continue
		taken[cell] = true
		cells.append(cell)
	return cells


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	$AnimatedSprite2D.play("idle")


func _on_body_entered(body: Node2D) -> void:
	if try_collect(body):
		# El sonido va acá y no en try_collect, que queda como lógica pura.
		Sfx.play(&"key_pickup")


## Le entrega la moneda a body si puede recogerla (el jugador). Devuelve true
## si la recogió; en ese caso la moneda desaparece.
func try_collect(body: Node) -> bool:
	if _collected or not body.has_method("collect_coins"):
		return false
	_collected = true
	body.collect_coins(value)
	queue_free()
	return true
