extends Area2D
## Trampa de picos animada: hace daño solo mientras los picos están arriba.

## Fuente del daño de los picos (Player.damaged).
const DAMAGE_SOURCE := &"spikes"

## Daño que recibe el jugador al pisar los picos levantados, en medios
## corazones (2 = un corazón). No sube con el nivel: las trampas no reciben el
## bonus de daño de los enemigos.
@export var damage: int = 2
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
	# La invulnerabilidad del jugador evita que pierda vida varias veces seguidas.
	for body in get_overlapping_bodies():
		# Saltando se pasa por encima de los picos.
		if body.has_method("is_jumping") and body.is_jumping():
			continue
		if body.has_method("take_damage"):
			body.take_damage(damage, Vector2.INF, DAMAGE_SOURCE)


func are_spikes_up() -> bool:
	return sprite.frame == SPIKES_UP_FRAME
