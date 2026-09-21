class_name EnemyBase
extends CharacterBody2D
## Base reutilizable para enemigos: vida, movimiento con colisión contra las
## paredes, daño por contacto, reacción al recibir golpes (animación, parpadeo
## rojo y retroceso) y muerte.
##
## Estructura esperada de la escena:
##   Enemigo (CharacterBody2D)   <- choca con las paredes
##   ├── AnimatedSprite2D
##   ├── CollisionShape2D        <- cuerpo físico
##   └── ContactArea (Area2D)    <- detecta al jugador para el daño por contacto
##       └── CollisionShape2D
##
## Cada enemigo concreto hereda de esta clase y sobrescribe
## _get_move_velocity() para decidir hacia dónde moverse.

## Se emite cuando el enemigo empieza a morir.
signal died(enemy: EnemyBase)

## Golpes que aguanta antes de morir.
@export var max_health: int = 2
## Velocidad de movimiento en píxeles por segundo.
@export var speed: float = 35.0
## Daño que hace al jugador al tocarlo.
@export var contact_damage: int = 1
## Distancia en píxeles que retrocede al recibir un golpe.
@export var knockback_distance: float = 10.0

@export_group("Animaciones")
@export var idle_animation: StringName = &"idle"
@export var move_animation: StringName = &"walk"
## Debe estar configurada sin loop.
@export var hurt_animation: StringName = &"hurt"
## Debe estar configurada sin loop.
@export var death_animation: StringName = &"death"

# Duración del retroceso en segundos.
const KNOCKBACK_TIME := 0.15

var health: int
var is_dying: bool = false

# Mientras es true el enemigo está aturdido: no se mueve ni hace daño.
var _is_hurt: bool = false
var _knockback: Vector2 = Vector2.ZERO
var _knockback_left: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var contact_area: Area2D = $ContactArea


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play(idle_animation)


func _physics_process(delta: float) -> void:
	if _knockback_left > 0.0:
		# El retroceso decae hasta cero y se aplica con move_and_slide,
		# así el enemigo no atraviesa paredes al ser empujado.
		_knockback_left -= delta
		velocity = _knockback * maxf(_knockback_left, 0.0) / KNOCKBACK_TIME
	elif is_dying or _is_hurt:
		velocity = Vector2.ZERO
	else:
		velocity = _get_move_velocity(delta)
		_update_animation()

	move_and_slide()

	# Un enemigo que muere o está aturdido no lastima.
	if not is_dying and not _is_hurt:
		_damage_touching_bodies()


## Velocidad deseada según el comportamiento de cada enemigo.
## Las subclases la sobrescriben; por defecto se queda quieto.
func _get_move_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO


## Recibe un golpe del jugador. from_position es desde dónde vino el golpe,
## y se usa para empujar al enemigo en la dirección contraria.
func take_hit(amount: int, from_position: Vector2) -> void:
	if is_dying:
		return

	health -= amount
	_flash_red()

	if health <= 0:
		_die()
		return

	var push_speed := 2.0 * knockback_distance / KNOCKBACK_TIME
	_knockback = (global_position - from_position).normalized() * push_speed
	_knockback_left = KNOCKBACK_TIME
	_is_hurt = true
	# Reinicia la animación aunque ya estuviera reproduciéndose por otro golpe.
	sprite.play(hurt_animation)
	sprite.frame = 0


func _update_animation() -> void:
	if velocity.length() > 1.0:
		sprite.play(move_animation)
		# El sprite mira a la derecha por defecto; se voltea al ir a la izquierda.
		if absf(velocity.x) > 0.1:
			sprite.flip_h = velocity.x < 0.0
	else:
		sprite.play(idle_animation)


func _damage_touching_bodies() -> void:
	# Revisa cada frame en lugar de usar body_entered, así también lastima si el
	# jugador se queda pegado. La invulnerabilidad del jugador evita daño repetido.
	for body in contact_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(contact_damage)


func _flash_red() -> void:
	# Tiñe el sprite de rojo y lo devuelve a su color original.
	sprite.modulate = Color(1.0, 0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.25)


func _die() -> void:
	is_dying = true
	_knockback_left = 0.0
	velocity = Vector2.ZERO
	# Se desactiva diferido porque puede ocurrir durante un callback de física.
	body_shape.set_deferred("disabled", true)
	contact_area.set_deferred("monitoring", false)
	sprite.play(death_animation)
	died.emit(self)


func _on_animation_finished() -> void:
	if sprite.animation == death_animation:
		# Se elimina recién cuando termina la animación de muerte.
		queue_free()
	elif sprite.animation == hurt_animation:
		_is_hurt = false
		sprite.play(idle_animation)
