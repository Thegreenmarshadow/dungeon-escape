class_name WeaponPickup
extends Area2D
## Arma en el suelo. Al tocarla el jugador la equipa y deja en su lugar la que
## tenía: siempre es un intercambio, así se puede volver a la anterior pasando
## otra vez por encima. Muestra el ícono del arma flotando y su nombre.
##
## Detecta al jugador con body_entered (capa 2, como las monedas y la llave):
## hay que salir y volver a entrar para cambiar otra vez.

## Se emite al intercambiar, con el arma que se equipó el jugador y la que dejó.
signal swapped(new_weapon: WeaponData, old_weapon: WeaponData)

## Id del arma que está en el suelo (ver WeaponData.load_by_id).
@export var weapon_id: StringName = &"spear"
## Píxeles que sube y baja al flotar, y segundos que tarda en subir.
@export var bob_height: float = 1.5
@export var bob_time: float = 0.6

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_refresh()
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "position:y", sprite.position.y - bob_height, bob_time)
	tween.tween_property(sprite, "position:y", sprite.position.y, bob_time)


## Arma que está en el suelo, o null si el id no existe.
func weapon() -> WeaponData:
	return WeaponData.load_by_id(weapon_id)


## Equipa el arma del suelo en body y deja en el suelo la que tenía. Devuelve
## false sin cambiar nada si body no puede equiparse armas o si el arma del
## suelo no existe. Es pública para las pruebas; en el juego la llama el
## contacto con el jugador.
func try_swap(body: Node) -> bool:
	if not body.has_method("equip_weapon") or not "weapon" in body:
		return false
	var new_weapon := weapon()
	if new_weapon == null:
		return false
	var old_weapon: WeaponData = body.weapon
	body.equip_weapon(new_weapon)
	Sfx.play(&"key_pickup")
	swapped.emit(new_weapon, old_weapon)
	if old_weapon == null:
		queue_free()
		return true
	weapon_id = old_weapon.id
	_refresh()
	return true


func _on_body_entered(body: Node2D) -> void:
	# Diferido: cambiar la hitbox del arma no se puede durante el aviso de
	# física que trae body_entered.
	try_swap.call_deferred(body)


func _refresh() -> void:
	var data := weapon()
	sprite.texture = data.icon if data else null
	name_label.text = data.display_name if data else ""
