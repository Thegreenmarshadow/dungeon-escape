class_name RangedEnemy
extends EnemyBase
## Enemigo a distancia: guarda distancia con el jugador y le dispara
## proyectiles con aviso previo. Lo usan el esqueleto arquero, el mago del orbe
## y la torre de calaveras con distintos parámetros (la torre tiene speed 0 y
## nunca se mueve), igual que ChaserEnemy sirve al vampiro y a la parca.
##
## Estados:
##   IDLE   -> el jugador entra en detect_radius            -> ALERT
##   ALERT  -> se aleja si está a menos de retreat_distance, se acerca si está a
##             más de approach_distance; con el enfriamiento listo, el jugador
##             a menos de attack_range y sin paredes en medio  -> ATTACK
##   ALERT  -> el jugador sale de lose_radius                 -> IDLE
##   ATTACK -> quieto mientras dura attack_animation: sigue al jugador hasta
##             aim_lock_frame, ahí fija la dirección, y en release_frame suelta
##             el proyectil. Al terminar la animación empieza el enfriamiento.
## Un golpe del jugador cancela el ataque y empieza el enfriamiento.

enum State { IDLE, ALERT, ATTACK }

## Distancia a la que detecta al jugador.
@export var detect_radius: float = 140.0
## Distancia a la que lo pierde (mayor que detect_radius para no alternar).
@export var lose_radius: float = 180.0
## Si el jugador está más cerca que esto, se aleja.
@export var retreat_distance: float = 56.0
## Si el jugador está más lejos que esto, se acerca.
@export var approach_distance: float = 120.0

@export_group("Ataque")
## Animación del disparo, configurada sin loop.
@export var attack_animation: StringName = &"attack"
## Distancia máxima al jugador para empezar a disparar.
@export var attack_range: float = 160.0
## Frame del disparo en el que fija la dirección. Hasta ahí sigue al jugador;
## después ya no, así el jugador puede salirse de la línea.
@export var aim_lock_frame: int = 3
## Frame en el que suelta el proyectil.
@export var release_frame: int = 5
## Segundos de espera entre el fin de un disparo y el inicio del siguiente.
@export var attack_cooldown: float = 1.6
## Escena del proyectil (Projectile).
@export var projectile_scene: PackedScene
## Posición de salida del proyectil respecto del enemigo mirando a la derecha.
## Ya incluye el offset (0, -5) del sprite; la X se invierte con flip_h.
@export var projectile_offset: Vector2 = Vector2(8, -2)
## Muestra una línea roja tenue hacia el jugador mientras apunta.
@export var show_aim_line: bool = true

## Color de la línea de apuntado.
const AIM_LINE_COLOR := Color(0.75, 0.17, 0.15, 0.35)
## Capa de las paredes para el rayo de línea de visión.
const WORLD_MASK := 1

var _state: State = State.IDLE
var _cooldown_left: float = 0.0
var _aim_direction: Vector2 = Vector2.RIGHT
var _aim_locked: bool = false
var _released: bool = false
var _player: Node2D
var _aim_line: Line2D


func _ready() -> void:
	super()
	_player = get_tree().get_first_node_in_group("player")
	sprite.frame_changed.connect(_on_sprite_frame_changed)
	_aim_line = Line2D.new()
	_aim_line.width = 1.0
	_aim_line.default_color = AIM_LINE_COLOR
	_aim_line.visible = false
	_aim_line.z_index = -1
	add_child(_aim_line)


func _get_move_velocity(delta: float) -> Vector2:
	if _state == State.ATTACK:
		_update_aim()
		return Vector2.ZERO
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if not is_instance_valid(_player):
		_state = State.IDLE
		return Vector2.ZERO

	var to_player := _player.global_position - global_position
	var distance := to_player.length()
	if _state == State.IDLE:
		if distance < detect_radius:
			_state = State.ALERT
		else:
			return Vector2.ZERO
	elif distance > lose_radius:
		_state = State.IDLE
		return Vector2.ZERO

	if _cooldown_left <= 0.0 and distance <= attack_range and _has_line_of_sight(_player.global_position):
		_start_attack()
		return Vector2.ZERO
	if speed <= 0.0 or distance <= 0.0:
		_face(to_player)
		return Vector2.ZERO
	if distance < retreat_distance:
		return -to_player / distance * speed
	if distance > approach_distance:
		return to_player / distance * speed
	_face(to_player)
	return Vector2.ZERO


func is_alerted() -> bool:
	return not is_dying and _state != State.IDLE


## Disparando no esquiva: es la ventana para castigarlo.
func _can_dodge() -> bool:
	return _state != State.ATTACK and super()


## Un golpe cancela el disparo (si todavía no soltó el proyectil, ya no lo
## suelta) y empieza el enfriamiento.
func _receive_hit(amount: int, from_position: Vector2) -> void:
	if _state == State.ATTACK:
		_end_attack()
	super(amount, from_position)


func _die() -> void:
	_aim_line.visible = false
	super()


# Mientras dispara, la animación de ataque no se pisa con idle/walk.
func _update_animation() -> void:
	if _state == State.ATTACK:
		return
	super()


func _on_animation_finished() -> void:
	if _state == State.ATTACK and sprite.animation == attack_animation:
		_end_attack()
		sprite.play(idle_animation)
		return
	super()


func _start_attack() -> void:
	_state = State.ATTACK
	_aim_locked = false
	_released = false
	_update_aim()
	sprite.play(attack_animation)
	sprite.frame = 0
	_aim_line.visible = show_aim_line


func _end_attack() -> void:
	_state = State.ALERT
	_cooldown_left = attack_cooldown
	_aim_line.visible = false


## Hasta aim_lock_frame sigue al jugador; después la dirección queda fija.
func _update_aim() -> void:
	if not _aim_locked and is_instance_valid(_player):
		var to_player := _player.global_position - projectile_spawn_position()
		if to_player != Vector2.ZERO:
			_aim_direction = to_player.normalized()
		_face(_player.global_position - global_position)
	if _aim_line.visible:
		var from := projectile_spawn_position() - global_position
		_aim_line.points = PackedVector2Array([from, from + _aim_direction * attack_range])


## Posición global de salida del proyectil según hacia dónde mira.
func projectile_spawn_position() -> Vector2:
	var offset := projectile_offset
	if sprite.flip_h:
		offset.x = -offset.x
	return global_position + offset


func _face(toward: Vector2) -> void:
	if absf(toward.x) > 0.1:
		sprite.flip_h = toward.x < 0.0


## true si no hay paredes entre el enemigo y target.
func _has_line_of_sight(target: Vector2) -> bool:
	if not is_inside_tree():
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target, WORLD_MASK)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _on_sprite_frame_changed() -> void:
	if _state != State.ATTACK or sprite.animation != attack_animation:
		return
	if not _aim_locked and sprite.frame >= aim_lock_frame:
		_update_aim()
		_aim_locked = true
	if not _released and sprite.frame >= release_frame:
		_released = true
		_aim_line.visible = false
		_fire()


## Crea el proyectil junto al enemigo (no como hijo, así no se mueve con él).
func _fire() -> Projectile:
	if projectile_scene == null or get_parent() == null:
		return null
	var projectile: Projectile = projectile_scene.instantiate()
	projectile.shooter = self
	get_parent().add_child(projectile)
	projectile.launch(projectile_spawn_position(), _aim_direction)
	return projectile
