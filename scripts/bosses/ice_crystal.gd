class_name IceCrystal
extends EnemyBase
## Cristal escudo de la Reina liche (sección 9.3, habilidad 3 de la fase 2).
## Mientras alguno siga en pie la liche no recibe daño. Aguanta max_health
## golpes (2), no se mueve, no lastima, no esquiva y no suelta nada.
##
## Lo crea LichBoss con spawn_minion, así no entra en el contador de enemigos
## del nivel y se borra si la liche muere.

## Segundos que tarda en encogerse al romperse (lo que dura la animación death).
const SHATTER_TIME := 0.33


func _can_dodge() -> bool:
	return false


func _die() -> void:
	super()
	# Se rompe encogiéndose: los tintes ya tienen significado (2.3).
	var shrink := create_tween()
	shrink.tween_property(sprite, "scale", Vector2(1.4, 0.2), SHATTER_TIME)
