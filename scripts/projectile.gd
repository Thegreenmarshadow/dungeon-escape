class_name Projectile
extends Area2D
## Proyectil de los enemigos a distancia (flecha, orbes). Viaja en línea recta,
## lastima al jugador al tocarlo y desaparece al chocar con una pared o al
## recorrer max_range píxeles.
##
## Estructura esperada de la escena:
##   Proyectil (Area2D)   <- capa 3 (valor 4) para que la espada lo detecte;
##   │                       máscara 1 + 2 (paredes y jugador)
##   ├── AnimatedSprite2D
##   └── CollisionShape2D
##
## La espada del jugador lo rompe (take_hit). Si reflectable está activo, en
## lugar de romperse sale despedido hacia quien lo disparó (shooter) y lastima
## a los enemigos que toque. Sin tirador vivo sale en sentido contrario al
## golpe.

## Se emite cuando el proyectil desaparece por cualquier motivo.
signal finished(projectile: Projectile)

## Velocidad en píxeles por segundo (la sección 6.1 de la biblia pide ≤ 140).
@export var speed: float = 120.0
## Daño que hace al jugador, en medios corazones (2 = un corazón). RangedEnemy
## le suma el bonus de daño del nivel al dispararlo.
@export var damage: int = 2
## Daño que hace a un enemigo si el jugador lo devolvió, en golpes de la vida
## del enemigo (la misma unidad que el arma del jugador). No cambia con el
## nivel ni con los medios corazones.
@export var reflected_damage: int = 1
## Distancia máxima que recorre antes de desaparecer.
@export var max_range: float = 200.0
## Si es true el sprite gira para apuntar en la dirección de vuelo (flecha).
## Los orbes son redondos y no lo necesitan.
@export var rotate_to_direction: bool = false
## Si es true la espada lo devuelve en vez de romperlo.
@export var reflectable: bool = false

## Capas de física (ver la sección 3 de la biblia): 1 mundo, 2 jugador, 3 enemigos.
const WORLD_MASK := 1
const PLAYER_MASK := 2
const ENEMY_MASK := 4
## Color del proyectil devuelto por el jugador.
const REFLECTED_TINT := Color(0.7, 0.9, 1.0)
## Color del proyectil devuelto con un parry.
const PARRIED_TINT := Color(1.6, 1.3, 0.4)
## Grupo con todos los proyectiles en vuelo (el parry del jugador los busca).
const GROUP := &"projectiles"
## Fuente del daño (Player.damaged) de un proyectil sin source asignado.
const DEFAULT_SOURCE := &"projectile"

var direction: Vector2 = Vector2.RIGHT
## true después de que el jugador lo devolvió: ya no lo lastima a él sino a
## los enemigos.
var is_reflected: bool = false
## Enemigo que lo disparó (lo asigna RangedEnemy). Al devolverlo vuelve a su
## cuerpo: el proyectil sale a la altura de la mano o del orbe, más arriba que
## el cuerpo, y volviendo por el mismo camino le pasaría por encima.
var shooter: Node2D
## Fuente del daño al jugador (Player.damaged): RangedEnemy pone su tipo al
## disparar. Vacía usa DEFAULT_SOURCE.
var source: StringName = &""

var _travelled: float = 0.0
var _done: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)
	_apply_rotation()


## Prepara el disparo: posición global de salida y dirección de vuelo. Se llama
## antes o después de agregarlo al árbol.
func launch(from_position: Vector2, toward: Vector2) -> void:
	global_position = from_position
	direction = toward.normalized() if toward != Vector2.ZERO else Vector2.RIGHT
	_apply_rotation()


func _physics_process(delta: float) -> void:
	advance(delta)


## Avanza el vuelo delta segundos. Es pública para poder probarla sin física.
func advance(delta: float) -> void:
	if _done:
		return
	var step := speed * delta
	position += direction * step
	_travelled += step
	if _travelled >= max_range:
		_finish()


## La espada del jugador lo rompe o, si es reflectable, lo devuelve.
func take_hit(_amount: int, from_position: Vector2) -> void:
	if _done or is_reflected:
		return
	if not reflectable:
		_finish()
		return
	_reflect(from_position)


## Parry del jugador: lo devuelve aunque no sea reflectable, speed_multiplier
## veces más rápido y con reflected_damage + bonus_damage. Devuelve false si ya
## no se podía (terminado o ya devuelto).
func parry(from_position: Vector2, speed_multiplier: float, bonus_damage: int) -> bool:
	if _done or is_reflected:
		return false
	_reflect(from_position)
	speed *= speed_multiplier
	reflected_damage += bonus_damage
	modulate = PARRIED_TINT
	return true


## Lo da vuelta: ahora vuela hacia el tirador y lastima a los enemigos.
func _reflect(from_position: Vector2) -> void:
	is_reflected = true
	# Sale hacia el tirador o, si ya no está, alejándose del jugador, con el
	# alcance completo otra vez.
	var away := global_position - from_position
	direction = away.normalized() if away != Vector2.ZERO else -direction
	var target := _shooter_target()
	if target != Vector2.INF and target != global_position:
		direction = global_position.direction_to(target)
	_travelled = 0.0
	collision_mask = WORLD_MASK | ENEMY_MASK
	modulate = REFLECTED_TINT
	_apply_rotation()


func _on_body_entered(body: Node) -> void:
	if _done:
		return
	if is_reflected:
		if body is EnemyBase:
			body.take_hit(reflected_damage, global_position)
	elif body.has_method("take_damage"):
		body.take_damage(damage, global_position, source if source != &"" else DEFAULT_SOURCE)
	# Lo que sea que haya tocado (jugador, enemigo o pared) lo detiene.
	_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(self)
	queue_free()


## Centro del cuerpo del tirador (su forma de colisión), o Vector2.INF si no
## hay tirador vivo.
func _shooter_target() -> Vector2:
	if not is_instance_valid(shooter) or shooter.get("is_dying") == true:
		return Vector2.INF
	var body := shooter.get("body_shape") as Node2D
	return body.global_position if body != null else shooter.global_position


func _apply_rotation() -> void:
	if rotate_to_direction:
		rotation = direction.angle()
