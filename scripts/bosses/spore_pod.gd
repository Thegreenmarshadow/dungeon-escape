class_name SporePod
extends EnemyBase
## Vaina de esporas del Guardián musgoso (sección 9.4 de
## docs/assets-pack/03-jefes.md): aparece con la habilidad de las esporas, a
## los costados del jefe. Se rompe con un golpe; si nadie la rompe en
## bloom_time segundos, florece: le cura heal_amount de vida a heal_target (el
## jefe) y desaparece.
##
## Es un EnemyBase (capa 4) para que la espada la golpee, pero no se mueve, no
## lastima ni suelta nada. El jefe la crea con spawn_minion, así no entra en el
## contador de muertes del HUD y se borra si el jefe muere.
##
## Estructura de la escena: la de EnemyBase. Su SpriteFrames tiene una sola
## animación ("default", con loop), que se usa para todos los estados.

## La vaina floreció y curó (o intentó curar) a heal_target.
signal bloomed(pod: SporePod)

## Segundos que tarda en romperse sola al morir (se desvanece).
const BREAK_FADE_TIME := 0.2

## Vida que le cura al jefe si florece.
@export var heal_amount: int = 2
## Segundos hasta florecer si nadie la rompe.
@export var bloom_time: float = 6.0

## A quién cura al florecer. Lo pone el jefe al crearla.
var heal_target: EnemyBase

var _bloom_left: float = 0.0
var _has_bloomed: bool = false


func _ready() -> void:
	super()
	_bloom_left = bloom_time


## Segundos que le faltan para florecer.
func time_to_bloom() -> float:
	return maxf(_bloom_left, 0.0)


func has_bloomed() -> bool:
	return _has_bloomed


## No se mueve: el paso de física solo cuenta el tiempo hasta florecer.
func _get_move_velocity(delta: float) -> Vector2:
	_bloom_left -= delta
	if _bloom_left <= 0.0:
		_bloom()
	return Vector2.ZERO


## Cura al jefe y desaparece. Una sola vez, y nunca si ya la rompieron.
func _bloom() -> void:
	if _has_bloomed or is_dying:
		return
	_has_bloomed = true
	# Desde acá no recibe golpes (take_hit ignora a los que mueren).
	is_dying = true
	if is_instance_valid(heal_target):
		heal_target.heal(heal_amount)
	bloomed.emit(self)
	queue_free()


## Rota de un golpe: sin animación de muerte propia, se desvanece rápido.
func _die() -> void:
	super()
	sprite.stop()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, BREAK_FADE_TIME)
	tween.tween_callback(queue_free)
