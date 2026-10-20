class_name WeaponData
extends Resource
## Datos de un arma del caballero. Un .tres por arma en res://assets/weapons/<id>/.
## Los valores de la espada son los que ya usa player.gd; el resto son propuestas para probar.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## &"common", &"rare" o &"epic": sirve para el color del nombre en el HUD.
@export var rarity: StringName = &"common"
## Primer nivel en el que puede aparecer en el suelo o en un cofre.
@export var min_level := 1

@export_group("Arte")
## Ícono de 16x16 para el suelo y el HUD.
@export var icon: Texture2D
## Sprite en la mano, apuntando a la derecha. Rotar el nodo pivote hacia donde mira el jugador.
@export var held_texture: Texture2D
## Píxel de la empuñadura dentro de held_texture (queda sobre la mano).
@export var held_grip := Vector2(3, 8)
## Estela/impacto. Cada frame está centrado en el jugador y apunta a la derecha.
@export var effect_frames: SpriteFrames

@export_group("Golpe")
@export var damage := 1
## Tamaño de la hitbox (largo x ancho, sin rotar) y distancia de su centro al jugador.
@export var hitbox_size := Vector2(12, 18)
@export var hitbox_distance := 10.0
## Si es > 0 la hitbox es un círculo de este radio (maza, martillo, mangual).
@export var hitbox_radius := 0.0
## Si es > 0, golpea todo lo que esté en un sector de este ángulo (grados) y radio hitbox_distance.
@export var sweep_degrees := 0.0
## Tiempo antes de que la hitbox se active (el jugador ve el arma levantarse).
@export var windup := 0.0
@export var active_time := 0.2
@export var cooldown := 0.4
## Retroceso aplicado al enemigo (px). Negativo = lo jala hacia el jugador (látigo).
@export var knockback := 10.0
## Multiplicador de velocidad del jugador mientras ataca.
@export var move_speed_while_attacking := 1.0
## Segundos que el enemigo queda aturdido (0 = nada).
@export var stun_time := 0.0
## Probabilidad de hacer el doble de daño.
@export_range(0.0, 1.0) var crit_chance := 0.0
## Si es true, el golpe atraviesa y daña a todos los enemigos dentro de la hitbox.
@export var pierce := true

@export_group("Combo y giro")
## Golpes seguidos por pulsación (garras = 3) y pausa entre ellos.
@export var combo_hits := 1
@export var combo_gap := 0.0
## Mangual: mientras se mantiene el botón gira y daña cada spin_tick segundos.
@export var spin := false
@export var spin_tick := 0.35

@export_group("Proyectil")
@export var projectile_frames: SpriteFrames
@export var projectile_speed := 0.0
@export var projectile_range := 0.0
## Bumerán: vuelve al jugador después de recorrer projectile_range.
@export var projectile_returns := false
@export var projectile_pierce := false
## Radio de explosión al chocar (0 = sin explosión) y su animación.
@export var impact_radius := 0.0
@export var impact_frames: SpriteFrames

@export_group("Efecto de estado")
## &"", &"burn" (quema: 1 de daño extra a los status_time s), &"slow" (enemigo al 50 %),
## &"bleed" (sangrado: 1 de daño extra a los status_time s).
@export var status_effect: StringName = &""
@export_range(0.0, 1.0) var status_chance := 1.0
@export var status_time := 0.0
## Cura 1 vida cada N golpes acertados (0 = nunca).
@export var heal_every_hits := 0
## Cura 1 vida cada N enemigos eliminados (0 = nunca).
@export var heal_every_kills := 0

@export_group("Escudo")
## Solo escudo: bloquea el daño que viene de frente dentro de este ángulo (grados).
@export var block_angle := 0.0
@export var move_speed_while_blocking := 1.0
