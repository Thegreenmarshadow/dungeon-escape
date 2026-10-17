extends ChaserEnemy
## Esqueleto soldado. Patrulla entre dos puntos; si el jugador se acerca a su
## ruta, la deja, va hacia él y ataca con una estocada de espada con aviso
## previo. El ataque y la persecución vienen de ChaserEnemy: aquí solo se
## definen la patrulla (en lugar de esperar en un puesto), la zona que guarda
## (toda la ruta, no un punto) y el paso de guardia. Si el jugador se aleja,
## vuelve a la ruta.
##
## Paso de guardia: cada golpe que recibe y aguanta lo hace retroceder más que
## a los demás enemigos (abre distancia, así el jugador tiene que volver a
## acercarse) y retrasa su próximo ataque. Junto con la esquiva evita que se lo
## pueda tumbar a golpes sin moverse.

## Desplazamiento del segundo punto de patrulla respecto de la posición inicial.
## En cero el esqueleto no patrulla: espera en su puesto como un guardián.
@export var patrol_offset: Vector2 = Vector2(112, 0)

@export_group("Paso de guardia")
## Píxeles que retrocede de más al recibir un golpe y sobrevivir, sumados a
## knockback_distance.
@export var guard_step_distance: float = 12.0
## Segundos mínimos sin atacar después del paso de guardia. Reemplaza al
## enfriamiento del ataque si es mayor.
@export var guard_attack_delay: float = 1.8

var _point_a: Vector2
var _point_b: Vector2
var _target: Vector2


func _ready() -> void:
	super()
	# El primer punto es donde se colocó el esqueleto en el nivel (su puesto).
	_point_a = global_position
	_point_b = global_position + patrol_offset
	_target = _point_b


## Sin el jugador cerca patrulla. Al llegar a un extremo cambia de destino; la
## dirección se calcula en cada frame, así retoma la ruta después de perseguir
## al jugador o de que un golpe lo desvíe.
func _get_idle_velocity(delta: float) -> Vector2:
	if _point_a == _point_b:
		return super(delta)
	if global_position.distance_to(_target) < 2.0:
		_target = _point_a if _target == _point_b else _point_b
	return global_position.direction_to(_target) * speed


## La zona que guarda es toda la ruta: la distancia se mide al punto más
## cercano del tramo entre los dos extremos.
func _distance_to_zone(point: Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, _point_a, _point_b))


func _receive_hit(amount: int, from_position: Vector2) -> void:
	super(amount, from_position)
	if is_dying:
		return
	_push_away(from_position, knockback_distance + guard_step_distance)
	_attack_cooldown_left = maxf(_attack_cooldown_left, guard_attack_delay)
