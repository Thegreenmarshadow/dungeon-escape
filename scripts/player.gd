extends CharacterBody2D
## Jugador controlable con movimiento en 8 direcciones, vidas, invulnerabilidad
## y ataque con espada.

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

@export_group("Ataque")
## Daño que hace cada golpe de espada.
@export var attack_damage: int = 1
## Segundos que la hitbox del golpe permanece activa.
@export var attack_active_time: float = 0.2
## Segundos mínimos entre el inicio de un golpe y el siguiente.
@export var attack_cooldown: float = 0.4
## Píxeles que el sprite se adelanta al golpear.
@export var attack_lunge: float = 3.0

var lives: int
var has_key: bool = false
## Última dirección de movimiento; hacia ella se lanza el golpe.
var facing: Vector2 = Vector2.RIGHT

# Tiempo restante de invulnerabilidad; mayor que cero significa invulnerable.
var _invulnerable_left: float = 0.0
# Tiempo restante con la hitbox activa y hasta poder volver a atacar.
var _attack_left: float = 0.0
var _cooldown_left: float = 0.0
# Objetivos ya golpeados en el golpe actual, para no pegarles dos veces.
var _hit_this_swing: Array[Node] = []

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_pivot: Node2D = $AttackPivot
@onready var hitbox: Area2D = $AttackPivot/Hitbox
@onready var slash: Line2D = $AttackPivot/Slash


func _ready() -> void:
	lives = max_lives
	# Inicia la animación de reposo.
	sprite.play("idle")
	# La hitbox detecta tanto áreas (esqueleto) como cuerpos (futuros enemigos).
	hitbox.area_entered.connect(_on_hitbox_touched)
	hitbox.body_entered.connect(_on_hitbox_touched)


func _physics_process(delta: float) -> void:
	_update_invulnerability(delta)
	_update_attack(delta)

	# Combina las cuatro acciones de movimiento en un solo vector.
	# get_vector lo normaliza, por lo que en diagonal no se avanza más rápido.
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = direction * speed

	if direction != Vector2.ZERO:
		facing = direction.normalized()
	# Voltea el sprite solo cuando hay componente horizontal,
	# así al moverse en vertical conserva la última orientación.
	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0

	if Input.is_action_just_pressed("attack"):
		_try_attack()

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


func _try_attack() -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = attack_cooldown
	_attack_left = attack_active_time
	_hit_this_swing.clear()

	# Orienta la hitbox y el efecto hacia donde mira el jugador.
	attack_pivot.rotation = facing.angle()
	# Diferido: cambiar el monitoreo durante el paso de física no es seguro.
	hitbox.set_deferred("monitoring", true)
	_play_attack_effect()


func _update_attack(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	if _attack_left > 0.0:
		_attack_left -= delta
		# Al terminar la ventana activa, la hitbox deja de detectar.
		if _attack_left <= 0.0:
			hitbox.set_deferred("monitoring", false)


func _on_hitbox_touched(target: Node) -> void:
	# Solo golpea a lo que sabe recibir golpes, y una vez por ataque.
	if target in _hit_this_swing or not target.has_method("take_hit"):
		return
	_hit_this_swing.append(target)
	target.take_hit(attack_damage, global_position)


## Efecto visual del golpe: un arco blanco que se desvanece y un pequeño
## avance del sprite, porque el caballero no tiene animación de ataque.
func _play_attack_effect() -> void:
	slash.modulate.a = 1.0
	slash.show()
	var fade := create_tween()
	fade.tween_property(slash, "modulate:a", 0.0, attack_active_time)
	fade.tween_callback(slash.hide)

	var lunge := create_tween()
	lunge.tween_property(sprite, "position", facing * attack_lunge, attack_active_time * 0.4)
	lunge.tween_property(sprite, "position", Vector2.ZERO, attack_active_time * 0.6)


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
