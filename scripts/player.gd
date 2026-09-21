extends CharacterBody2D
## Jugador controlable con movimiento en 8 direcciones, vidas e invulnerabilidad.

## Se emite cada vez que cambia la cantidad de vidas.
signal lives_changed(lives: int)
## Se emite al recoger la llave.
signal key_collected
## Se emite cuando el jugador se queda sin vidas.
signal died

## Velocidad de movimiento en píxeles por segundo.
@export var speed: float = 80.0
## Vidas con las que empieza el jugador.
@export var max_lives: int = 3
## Segundos de invulnerabilidad después de recibir daño.
@export var invulnerability_time: float = 0.5

var lives: int
var has_key: bool = false

# Tiempo restante de invulnerabilidad; mayor que cero significa invulnerable.
var _invulnerable_left: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	lives = max_lives
	# Inicia la animación de reposo.
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	_update_invulnerability(delta)

	# Combina las cuatro acciones de movimiento en un solo vector.
	# get_vector lo normaliza, por lo que en diagonal no se avanza más rápido.
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed

	# Voltea el sprite solo cuando hay componente horizontal,
	# así al moverse en vertical conserva la última orientación.
	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0

	# Aplica el movimiento y resuelve las colisiones con las paredes.
	move_and_slide()


## Resta vidas salvo que el jugador esté en su ventana de invulnerabilidad.
## Lo llaman las trampas y los enemigos.
func take_damage(amount: int) -> void:
	if _invulnerable_left > 0.0 or lives <= 0:
		return

	lives = max(lives - amount, 0)
	lives_changed.emit(lives)

	if lives == 0:
		_die()
		return

	# Activa la invulnerabilidad y marca al jugador semitransparente.
	_invulnerable_left = invulnerability_time
	sprite.modulate.a = 0.5


## Marca que el jugador tiene la llave. La llama la llave al ser tocada.
func collect_key() -> void:
	has_key = true
	key_collected.emit()


func _update_invulnerability(delta: float) -> void:
	if _invulnerable_left <= 0.0:
		return
	_invulnerable_left -= delta
	# Al terminar la invulnerabilidad el sprite vuelve a ser opaco.
	if _invulnerable_left <= 0.0:
		sprite.modulate.a = 1.0


func _die() -> void:
	# Deja de moverse y avisa; el nivel decide qué hacer (mostrar Game Over).
	set_physics_process(false)
	died.emit()
