class_name EnemyBase
extends CharacterBody2D
## Base reutilizable para enemigos: vida, movimiento con colisión contra las
## paredes, daño por contacto, reacción al recibir golpes (animación, parpadeo
## rojo y retroceso), esquiva y muerte.
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
## Se emite cuando el enemigo esquiva un golpe del jugador.
signal dodged(enemy: EnemyBase)
## Se emite al recibir un golpe que no esquivó, con el daño. Solo lo observa
## GameFeel (vibración, hit-stop, número flotante).
signal hit_received(enemy: EnemyBase, amount: int)

## Golpes que aguanta antes de morir.
@export var max_health: int = 2
## Velocidad de movimiento en píxeles por segundo.
@export var speed: float = 35.0
## Daño que hace al jugador al tocarlo, en medios corazones (2 = un corazón).
## Es el de la escena: el nivel le suma su bonus (apply_damage_bonus).
@export var contact_damage: int = 2
## Distancia en píxeles que retrocede al recibir un golpe.
@export var knockback_distance: float = 10.0
## Probabilidad (de 0 a 1) de soltar un corazón al morir. El nivel la consulta
## y crea el corazón; los jefes la tienen en 1 para soltarlo siempre.
@export_range(0.0, 1.0, 0.01) var heart_drop_chance: float = 0.18
## Probabilidad (de 0 a 1) de soltar una moneda al morir, y entre qué valores
## (incluidos) se sortea cuánto vale. Igual que con los corazones, el nivel las
## consulta y crea la moneda.
@export_range(0.0, 1.0, 0.01) var coin_drop_chance: float = 0.25
@export_range(1, 20) var coin_min_value: int = 1
@export_range(1, 20) var coin_max_value: int = 2
## Probabilidad (de 0 a 1) de esquivar un golpe del jugador: no recibe daño y
## da un paso atrás. Tras esquivar no puede volver a hacerlo durante
## DODGE_COOLDOWN, así que nunca esquiva dos golpes seguidos. DifficultyCurve
## guarda una copia de los valores de cada escena (una prueba los compara).
@export_range(0.0, 1.0, 0.01) var dodge_chance: float = 0.15
## Distancia en píxeles del paso atrás al esquivar.
@export var dodge_distance: float = 8.0

@export_group("Animaciones")
@export var idle_animation: StringName = &"idle"
@export var move_animation: StringName = &"walk"
## Debe estar configurada sin loop.
@export var hurt_animation: StringName = &"hurt"
## Debe estar configurada sin loop.
@export var death_animation: StringName = &"death"

# Duración del retroceso en segundos.
const KNOCKBACK_TIME := 0.15
## Segundos después de esquivar en los que el enemigo no puede volver a esquivar.
const DODGE_COOLDOWN := 1.0
## Capa de física del jugador ("player", capa 2).
const PLAYER_COLLISION_LAYER := 2
## Píxeles por lado que crece ContactArea para tocar al jugador sin atravesarlo.
const CONTACT_MARGIN := 3.0
## Destello al esquivar: blanco y translúcido, para no confundirlo con el rojo
## de un golpe recibido.
const DODGE_TINT := Color(1.6, 1.6, 1.6, 0.35)
const DODGE_FLASH_TIME := 0.3
## Texto flotante que aparece sobre el enemigo al esquivar.
const DODGE_TEXT := "¡Esquiva!"
const DODGE_TEXT_SIZE := 7
const DODGE_TEXT_TIME := 0.6

var health: int
var is_dying: bool = false

## Medios corazones que el nivel suma a cada golpe de este enemigo al jugador
## (apply_damage_bonus). 0 hasta que se aplica.
var damage_bonus: int = 0

# Vida de la escena antes de escalarla; -1 hasta la primera vez que se escala.
var _base_health: int = -1
# Daño por contacto de la escena antes del bonus; -1 hasta la primera vez.
var _base_contact_damage: int = -1

# Mientras es true el enemigo está aturdido: no se mueve ni hace daño.
var _is_hurt: bool = false
var _knockback: Vector2 = Vector2.ZERO
var _knockback_left: float = 0.0
var _dodge_cooldown_left: float = 0.0
# Multiplicador del retroceso del golpe que se está recibiendo (lo pasa el arma
# del jugador en take_hit; 1 fuera de un golpe).
var _hit_knockback_scale: float = 1.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var contact_area: Area2D = $ContactArea


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	# Sólido para el jugador: lo frena en vez de atravesarlo. Como los cuerpos ya
	# no se superponen, la zona de contacto crece CONTACT_MARGIN para seguir
	# tocándolo.
	collision_mask |= PLAYER_COLLISION_LAYER
	_grow_contact_area(CONTACT_MARGIN)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play(idle_animation)


## Agranda margin píxeles por lado la forma de ContactArea (una copia, para no
## cambiar el recurso de la escena).
func _grow_contact_area(margin: float) -> void:
	for child in contact_area.get_children():
		if not child is CollisionShape2D or child.shape == null:
			continue
		var shape: Shape2D = child.shape.duplicate()
		if shape is RectangleShape2D:
			shape.size += Vector2(margin, margin) * 2.0
		elif shape is CircleShape2D:
			shape.radius += margin
		elif shape is CapsuleShape2D:
			shape.radius += margin
			shape.height += margin * 2.0
		child.shape = shape


func _physics_process(delta: float) -> void:
	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)
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


## Multiplica la vida base (la de la escena) por multiplier, redondeando, y
## nunca la deja por debajo de la base. El enemigo no sabe de niveles: el nivel
## le pasa el multiplicador. Ajusta también la vida actual porque _ready ya la
## igualó a la máxima. Llamarla otra vez parte de la base, no se acumula.
func apply_health_scale(multiplier: float) -> void:
	if _base_health < 0:
		_base_health = max_health
	max_health = maxi(roundi(_base_health * multiplier), _base_health)
	health = max_health


## Suma bonus medios corazones a cada golpe de este enemigo al jugador
## (LevelGenerator.enemy_damage_bonus del nivel), con el tope de
## LevelGenerator.scaled_hit. Igual que apply_health_scale: el enemigo no sabe
## de niveles y llamarla otra vez parte del daño de la escena. Las subclases
## que lastiman de otra forma (ataque, proyectiles, efectos) usan
## scaled_damage con el daño base de cada golpe.
func apply_damage_bonus(bonus: int) -> void:
	if _base_contact_damage < 0:
		_base_contact_damage = contact_damage
	damage_bonus = maxi(bonus, 0)
	contact_damage = scaled_damage(_base_contact_damage)


## Daño al jugador de un golpe de base medios corazones con el bonus de este
## enemigo (ver LevelGenerator.scaled_hit).
func scaled_damage(base: int) -> int:
	return LevelGenerator.scaled_hit(base, damage_bonus)


## Recupera amount de vida sin pasar de max_health (sección 9.5 de la biblia:
## las vainas y el musgo curan al Guardián). No cura a un enemigo muriendo.
## Devuelve cuánto curó de verdad.
func heal(amount: int) -> int:
	if is_dying or amount <= 0:
		return 0
	var before := health
	health = mini(health + amount, max_health)
	return health - before


## true mientras el enemigo va tras el jugador o prepara un ataque. El nivel lo
## usa para cambiar la música. Las subclases con ese comportamiento lo
## sobrescriben; por defecto un enemigo nunca está en alerta.
func is_alerted() -> bool:
	return false


## Velocidad deseada según el comportamiento de cada enemigo.
## Las subclases la sobrescriben; por defecto se queda quieto.
func _get_move_velocity(_delta: float) -> Vector2:
	return Vector2.ZERO


## Decide si un enemigo esquiva un golpe. chance es la probabilidad (0 a 1) y
## roll un número aleatorio entre 0 y 1, igual que en Heart.should_drop: con
## chance 1 esquiva siempre y con chance 0 nunca.
static func should_dodge(chance: float, roll: float) -> bool:
	if chance >= 1.0:
		return true
	return roll < chance


## Recibe un golpe del jugador. from_position es desde dónde vino el golpe,
## y se usa para empujar al enemigo en la dirección contraria. knockback_scale
## multiplica knockback_distance: lo da el arma (1 con la espada; negativo lo
## jala hacia el jugador). Antes de recibirlo intenta esquivarlo.
func take_hit(amount: int, from_position: Vector2, knockback_scale: float = 1.0) -> void:
	if is_dying:
		return
	if try_dodge(from_position, randf()):
		return
	_hit_knockback_scale = knockback_scale
	_receive_hit(amount, from_position)
	_hit_knockback_scale = 1.0
	hit_received.emit(self, amount)


## Intenta esquivar un golpe que viene desde from_position con la tirada roll
## (0 a 1). Si esquiva, no recibe daño: da un paso atrás, parpadea en blanco,
## muestra DODGE_TEXT, avisa con dodged y empieza el enfriamiento de la esquiva.
## Devuelve true si esquivó. Sin sonido propio: ya suena el tajo del jugador y
## falta el de golpe recibido.
func try_dodge(from_position: Vector2, roll: float) -> bool:
	if not _can_dodge() or not should_dodge(dodge_chance, roll):
		return false
	_dodge_cooldown_left = DODGE_COOLDOWN
	_push_away(from_position, dodge_distance)
	_flash_dodge()
	_show_dodge_text()
	dodged.emit(self)
	return true


## Si en este momento puede esquivar: no esquiva muriendo, aturdido ni durante
## el enfriamiento. Las subclases agregan sus propias ventanas de castigo (por
## ejemplo, mientras atacan).
func _can_dodge() -> bool:
	return not is_dying and not _is_hurt and _dodge_cooldown_left <= 0.0


## Aplica un golpe que no esquivó: resta vida, parpadea en rojo, retrocede y
## queda aturdido, o muere. Las subclases que reaccionan al golpe sobrescriben
## esta función y no take_hit, así la esquiva se decide antes.
func _receive_hit(amount: int, from_position: Vector2) -> void:
	health -= amount
	_flash_red()
	Sfx.play(&"enemy_hit")

	if health <= 0:
		_die()
		return

	_push_away(from_position, hit_knockback_distance())
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
	# Un enemigo con contact_damage en 0 solo daña con su ataque; llamar a
	# take_damage(0) igualmente activaría la invulnerabilidad del jugador.
	if contact_damage <= 0:
		return
	# Revisa cada frame en lugar de usar body_entered, así también lastima si el
	# jugador se queda pegado. La invulnerabilidad del jugador evita daño repetido.
	for body in contact_area.get_overlapping_bodies():
		if body.has_method("take_damage"):
			body.take_damage(contact_damage, global_position, damage_source())


## Retroceso del golpe que se está recibiendo: knockback_distance por el
## multiplicador del arma del jugador.
func hit_knockback_distance() -> float:
	return knockback_distance * _hit_knockback_scale


## Empuja al enemigo distance píxeles en dirección contraria a from_position.
## El empuje decae en KNOCKBACK_TIME y se aplica con move_and_slide, así no
## atraviesa paredes.
func _push_away(from_position: Vector2, distance: float) -> void:
	var push_speed := 2.0 * distance / KNOCKBACK_TIME
	_knockback = (global_position - from_position).normalized() * push_speed
	_knockback_left = KNOCKBACK_TIME


func _flash_dodge() -> void:
	sprite.modulate = DODGE_TINT
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, DODGE_FLASH_TIME)


## Texto chico que sube y se desvanece sobre el enemigo.
func _show_dodge_text() -> void:
	var label := Label.new()
	label.text = DODGE_TEXT
	label.add_theme_font_size_override("font_size", DODGE_TEXT_SIZE)
	label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1))
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(48.0, 10.0)
	label.position = Vector2(-24.0, -26.0)
	label.z_index = 10
	add_child(label)
	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 8.0, DODGE_TEXT_TIME)
	tween.tween_property(label, "modulate:a", 0.0, DODGE_TEXT_TIME)
	tween.chain().tween_callback(label.queue_free)


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
	Sfx.play(&"enemy_death")
	died.emit(self)


func _on_animation_finished() -> void:
	if sprite.animation == death_animation:
		# Se elimina recién cuando termina la animación de muerte.
		queue_free()
	elif sprite.animation == hurt_animation:
		_is_hurt = false
		sprite.play(idle_animation)


## Nombre con el que este enemigo figura como fuente del daño que hace
## (Player.damaged): el mismo de RunRecorder.enemy_kind (Skeleton, Forge...).
func damage_source() -> StringName:
	return StringName(RunRecorder.enemy_kind(self))
