extends Area2D
## Trampa de picos animada: hace daño solo mientras los picos están arriba.

## Daño que recibe el jugador al pisar los picos levantados.
@export var damage: int = 1
## Frame de la animación en el que la trampa arranca. Sirve para desfasar varias trampas.
@export var start_frame: int = 0

# Índice del frame de la animación "cycle" en el que los picos están arriba.
const SPIKES_UP_FRAME := 3

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	sprite.play("cycle")
	sprite.frame = start_frame


func _physics_process(_delta: float) -> void:
	if not are_spikes_up():
		return
	# Revisa cada frame en lugar de usar body_entered, así también lastima
	# a quien ya estaba parado encima cuando los picos suben.
	# La invulnerabilidad del jugador evita que pierda varias vidas seguidas.
	for body in get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(damage)


func are_spikes_up() -> bool:
	return sprite.frame == SPIKES_UP_FRAME
