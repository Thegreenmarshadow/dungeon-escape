extends Node
## Música de fondo. Se registra como Autoload ("Music") para que el reproductor
## sobreviva a los cambios de escena: si la pista pedida ya está sonando no se
## reinicia, y si es otra se reemplaza sin superponerse (hay un solo reproductor).

## Volumen de la música, bajo para que no tape el resto del audio.
const VOLUME_DB := -8.0

var _player := AudioStreamPlayer.new()


func _ready() -> void:
	# La música sigue sonando en las pantallas finales, que pausan el árbol.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.volume_db = VOLUME_DB
	add_child(_player)


## Reproduce stream en bucle. No hace nada si esa pista ya está sonando.
func play_track(stream: AudioStream) -> void:
	if _player.playing and _player.stream == stream:
		return
	# El bucle real es el ajuste "loop" del importador del .ogg; esto solo
	# asegura que siga en bucle si alguien lo desactiva por error.
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_player.stream = stream
	_player.play()
