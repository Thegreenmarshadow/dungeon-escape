extends Area2D
## Llave recolectable: al tocarla el jugador la obtiene y la llave desaparece.


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	$AnimatedSprite2D.play("idle")


func _on_body_entered(body: Node2D) -> void:
	# Solo reacciona a cuerpos que pueden recoger la llave (el jugador).
	if not body.has_method("collect_key"):
		return
	body.collect_key()
	queue_free()
