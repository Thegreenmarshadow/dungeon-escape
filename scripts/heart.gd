class_name Heart
extends Area2D
## Corazón recolectable que sueltan los enemigos al morir: al tocarlo, el
## jugador recupera un corazón. Si el jugador ya tiene la vida llena, el
## corazón se queda en el suelo para que pueda volver a buscarlo más tarde.
##
## También define la unidad de la vida del jugador: el medio corazón. La vida,
## el daño y las curaciones del jugador se cuentan en medios corazones
## (HALF_HEARTS_PER_HEART por corazón); la HUD la dibuja con corazones llenos,
## medios y vacíos, y las estadísticas y la telemetría la informan en
## corazones (to_hearts), la misma unidad que tenían cuando se contaban vidas
## enteras.

## Medios corazones que hay en un corazón.
const HALF_HEARTS_PER_HEART := 2

## Medios corazones que recupera al recogerlo: un corazón entero.
@export var heal_amount: int = HALF_HEARTS_PER_HEART
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
## Columnas del dibujo que forman el medio corazón (get_half_texture): de la 0
## a la central (4) del dibujo de 9 columnas.
const HALF_COLUMNS := 5

# Textura compartida por todos los corazones; se genera una sola vez.
static var _texture: Texture2D
# Medio corazón para la HUD; se genera una sola vez a partir de PIXELS.
static var _half_texture: Texture2D

# Evita curar dos veces si se toca otra vez antes de liberarse.
var _collected: bool = false

@onready var sprite: Sprite2D = $Sprite2D


## Medios corazones convertidos a corazones (3 -> 1.5): la unidad con la que
## la telemetría, las estadísticas y los informes muestran la vida y el daño
## del jugador.
static func to_hearts(half_hearts: int) -> float:
	return half_hearts / float(HALF_HEARTS_PER_HEART)


## Medios corazones como texto en corazones: "2", "1.5", "0.5".
static func format_hearts(half_hearts: int) -> String:
	return format_heart_amount(to_hearts(half_hearts))


## Corazones (con medios, como los de la telemetría) como texto corto: sin
## decimales si son enteros ("3", no "3.0") y con uno si no ("2.5").
static func format_heart_amount(hearts: float) -> String:
	if is_equal_approx(hearts, roundf(hearts)):
		return str(roundi(hearts))
	return String.num(hearts, 1)


## Decide si un enemigo suelta un corazón. chance es la probabilidad (0 a 1) y
## roll un número aleatorio entre 0 y 1. Con chance 1 suelta siempre, aunque
## roll sea exactamente 1 (randf() puede devolverlo).
static func should_drop(chance: float, roll: float) -> bool:
	if chance >= 1.0:
		return true
	return roll < chance


func _ready() -> void:
	sprite.texture = get_texture()
	_start_bob()


func _physics_process(_delta: float) -> void:
	# Se revisa cada frame en lugar de usar body_entered: si el jugador está
	# parado encima con la vida llena y luego recibe daño, igual lo recoge.
	for body in get_overlapping_bodies():
		if try_collect(body):
			# El sonido va acá y no en try_collect, que queda como lógica pura.
			Sfx.play(&"heart_pickup")
			return


## Intenta curar a body. Si lo cura, el corazón desaparece y devuelve true; si
## body no puede curarse o ya tiene la vida llena, el corazón se queda.
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


## Dibujo del corazón; lo comparten los corazones del suelo y la vida de la
## HUD.
static func get_texture() -> Texture2D:
	if _texture == null:
		_texture = ImageTexture.create_from_image(_draw_pixels(PIXELS[0].length()))
	return _texture


## Medio corazón de la HUD: el mismo dibujo, recortado píxel a píxel a sus
## primeras HALF_COLUMNS columnas (la mitad izquierda más la columna central,
## así el corte cae en el medio del dibujo de 9 columnas). Tiene el mismo
## tamaño que el corazón entero y el resto queda transparente, así la HUD lo
## dibuja encima de un corazón vacío sin moverlo.
static func get_half_texture() -> Texture2D:
	if _half_texture == null:
		_half_texture = ImageTexture.create_from_image(_draw_pixels(HALF_COLUMNS))
	return _half_texture


## Imagen del dibujo con solo sus primeras columns columnas pintadas.
static func _draw_pixels(columns: int) -> Image:
	var image := Image.create_empty(PIXELS[0].length(), PIXELS.size(), false, Image.FORMAT_RGBA8)
	for y in PIXELS.size():
		var row: String = PIXELS[y]
		for x in mini(row.length(), columns):
			if PIXEL_COLORS.has(row[x]):
				image.set_pixel(x, y, PIXEL_COLORS[row[x]])
	return image
