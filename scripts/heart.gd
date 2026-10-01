class_name Heart
extends Area2D
## Corazón recolectable que sueltan los enemigos al morir: al tocarlo, el
## jugador recupera una vida. Si el jugador ya tiene todas sus vidas, el
## corazón se queda en el suelo para que pueda volver a buscarlo más tarde.

## Vidas que recupera al recogerlo.
@export var heal_amount: int = 1
## Píxeles que sube y baja al flotar.
@export var bob_height: float = 1.5
## Segundos que tarda en subir (y lo mismo en bajar).
@export var bob_time: float = 0.6

# Dibujo del corazón en pixel art: "o" borde, "r" relleno, "h" brillo.
const PIXELS := [
	".oo...oo.",
	"ohro.orro",
	"ohrrorrro",
	"orrrrrrro",
	".orrrrro.",
	"..orrro..",
	"...oro...",
	"....o....",
]
const PIXEL_COLORS := {
	"o": Color(0.24, 0.04, 0.07),
	"r": Color(0.85, 0.15, 0.2),
	"h": Color(1.0, 0.62, 0.62),
}

# Textura compartida por todos los corazones; se genera una sola vez.
static var _texture: Texture2D

# Evita curar dos veces si se toca otra vez antes de liberarse.
var _collected: bool = false

@onready var sprite: Sprite2D = $Sprite2D


## Decide si un enemigo suelta un corazón. chance es la probabilidad (0 a 1) y
## roll un número aleatorio entre 0 y 1. Con chance 1 suelta siempre, aunque
## roll sea exactamente 1 (randf() puede devolverlo).
static func should_drop(chance: float, roll: float) -> bool:
	if chance >= 1.0:
		return true
	return roll < chance


func _ready() -> void:
	sprite.texture = _get_texture()
	_start_bob()


func _physics_process(_delta: float) -> void:
	# Se revisa cada frame en lugar de usar body_entered: si el jugador está
	# parado encima con todas sus vidas y luego recibe daño, igual lo recoge.
	for body in get_overlapping_bodies():
		if try_collect(body):
			return


## Intenta curar a body. Si lo cura, el corazón desaparece y devuelve true; si
## body no puede curarse o ya tiene todas sus vidas, el corazón se queda.
func try_collect(body: Node) -> bool:
	if _collected or not body.has_method("heal"):
		return false
	if not body.heal(heal_amount):
		return false
	_collected = true
	set_physics_process(false)
	queue_free()
	return true


## Flota suavemente subiendo y bajando el dibujo; el área de recolección queda
## fija en el lugar.
func _start_bob() -> void:
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "position:y", -bob_height, bob_time)
	tween.tween_property(sprite, "position:y", 0.0, bob_time)


static func _get_texture() -> Texture2D:
	if _texture == null:
		var image := Image.create_empty(PIXELS[0].length(), PIXELS.size(), false, Image.FORMAT_RGBA8)
		for y in PIXELS.size():
			var row: String = PIXELS[y]
			for x in row.length():
				if PIXEL_COLORS.has(row[x]):
					image.set_pixel(x, y, PIXEL_COLORS[row[x]])
		_texture = ImageTexture.create_from_image(image)
	return _texture
