class_name BossHazard
extends Node2D
## Efecto de suelo de un jefe que lastima al jugador: la onda del martillazo,
## las marcas de brasas, los charcos de lava (y, con otras texturas, picos de
## hielo, raíces o la nova de escarcha).
##
## Sigue el patrón de spike_trap.gd: solo lastima en ciertos frames de su
## animación, así el aviso es lo que se ve. En lugar de un Area2D compara la
## distancia al jugador con radius: no depende del paso de física (la onda
## lastima en el mismo frame en que aparece) y se puede probar sin física.
##
## Estructura de la escena:
##   Efecto (Node2D, este script)
##   └── AnimatedSprite2D   <- SpriteFrames del fx, animación "default"
##
## Modos:
## - Golpe único (continuous = false): lastima una vez, en el primer frame de
##   active_frames que alcance. Si la animación no tiene loop, se borra al
##   terminar (onda, marca, pico).
## - Continuo (continuous = true): lastima en cada paso de física mientras está
##   en active_frames (charco). La invulnerabilidad del jugador evita el daño
##   repetido. Con lifetime > 0 se borra a los lifetime segundos.

## Lastimó al jugador (o a lo que tenga en target).
signal struck(target: Node2D)

## Fuente del daño (Player.damaged) de un efecto sin source asignado.
const DEFAULT_SOURCE := &"boss_hazard"

## Daño que hace.
@export var damage: int = 1
## Radio en píxeles alrededor del efecto en el que alcanza al jugador.
@export var radius: float = 12.0
## Primer y último frame (incluidos) en los que lastima. Los anteriores son el
## aviso. Con y < 0 lastima desde x hasta el final.
@export var active_frames: Vector2i = Vector2i(0, -1)
## true: lastima mientras siga activo; false: una sola vez.
@export var continuous: bool = false
## Segundos hasta borrarse. 0: se borra cuando termina la animación (sin loop).
@export var lifetime: float = 0.0
## Multiplica la velocidad del jugador mientras está dentro (1 = no frena). Lo
## usan efectos como la nube de esporas; necesita apply_slow en el jugador.
@export_range(0.0, 1.0, 0.05) var slow_factor: float = 1.0

## Quién puede recibir el daño. spawn_hazard del jefe pone al jugador; si queda
## en null, se busca el primer nodo del grupo "player".
var target: Node2D
## Fuente del daño (Player.damaged): spawn_hazard del jefe pone su boss_id.
## Vacía usa DEFAULT_SOURCE.
var source: StringName = &""

var _time_left: float = 0.0
var _has_struck: bool = false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	if target == null and is_inside_tree():
		target = get_tree().get_first_node_in_group("player")
	_time_left = lifetime
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play()
	# Un efecto que lastima desde el frame 0 (la onda) golpea al aparecer.
	_on_frame_changed()


func _physics_process(delta: float) -> void:
	if lifetime > 0.0:
		_time_left -= delta
		if _time_left <= 0.0:
			queue_free()
			return
	if continuous:
		try_strike()


## true si el frame actual lastima.
func is_active() -> bool:
	var last := active_frames.y if active_frames.y >= 0 else sprite.sprite_frames.get_frame_count(sprite.animation) - 1
	return sprite.frame >= active_frames.x and sprite.frame <= last


## true si target está dentro de radius.
func is_target_inside() -> bool:
	return is_instance_valid(target) and global_position.distance_to(target.global_position) <= radius


## Lastima a target si el efecto está activo y lo alcanza. Devuelve true si lo
## lastimó. En modo de golpe único lastima como mucho una vez.
func try_strike() -> bool:
	if not is_active() or not is_target_inside():
		return false
	if not continuous and _has_struck:
		return false
	_has_struck = true
	if slow_factor < 1.0 and target.has_method("apply_slow"):
		target.apply_slow(slow_factor, 0.2)
	if damage > 0 and target.has_method("take_damage"):
		target.take_damage(damage, global_position, source if source != &"" else DEFAULT_SOURCE)
	struck.emit(target)
	return true


func _on_frame_changed() -> void:
	if not continuous:
		try_strike()


func _on_animation_finished() -> void:
	if lifetime <= 0.0:
		queue_free()
