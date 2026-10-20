@tool
extends RefCounted
## Arma un jugador para las pruebas con el script y los hijos que necesita su
## _ready (sprite con los frames reales de Player.tscn y WeaponPivot con el
## arma, la estela y la hitbox). En el editor un script que no es @tool solo
## corre si se instancia con el script y no con la escena. La prueba debe
## rastrear (track) y agregar al árbol el jugador devuelto.

const PLAYER_SCRIPT := preload("res://scripts/player.gd")


static func make_player() -> CharacterBody2D:
	var source: Node = ResourceLoader.load("res://scenes/Player.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	var player: CharacterBody2D = PLAYER_SCRIPT.new()
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	sprite.sprite_frames = source.get_node("AnimatedSprite2D").sprite_frames
	source.free()
	player.add_child(sprite)
	var pivot := Node2D.new()
	pivot.name = "WeaponPivot"
	var held := Sprite2D.new()
	held.name = "Held"
	pivot.add_child(held)
	var effect := AnimatedSprite2D.new()
	effect.name = "Effect"
	pivot.add_child(effect)
	var hitbox := Area2D.new()
	hitbox.name = "Hitbox"
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	hitbox.add_child(shape)
	pivot.add_child(hitbox)
	player.add_child(pivot)
	return player
