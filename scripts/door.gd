extends Area2D
## Puerta de salida: deja escapar al jugador solo si tiene la llave.

## Se emite cuando el jugador llega a la puerta con la llave.
signal player_escaped
## Se emite cuando el jugador llega a la puerta sin la llave.
signal locked_touched


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Solo reacciona a cuerpos que pueden llevar la llave (el jugador).
	if not "has_key" in body:
		return
	if body.has_key:
		player_escaped.emit()
	else:
		locked_touched.emit()
