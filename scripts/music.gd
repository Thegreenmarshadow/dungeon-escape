extends Node
## Música de fondo. Se registra como Autoload ("Music") para que el reproductor
## sobreviva a los cambios de escena: si la pista pedida ya está sonando no se
## reinicia, y si es otra se reemplaza sin superponerse (hay un solo reproductor).

## Volumen de la música. Igual al de los efectos de sonido: las pistas del nivel
## vienen normalizadas casi al máximo y más alto tapaban los efectos.
const VOLUME_DB := -6.0
## Volumen al que baja la pista que sale antes de cambiar a la siguiente.
const FADE_FLOOR_DB := -40.0

var _player := AudioStreamPlayer.new()
# Última pista pedida. Puede ir por delante de _player.stream mientras dura el
# fundido, y evita pedir dos veces el mismo cambio.
var _target: AudioStream
var _fade: Tween


func _ready() -> void:
	# La música sigue sonando en las pantallas finales, que pausan el árbol.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.volume_db = VOLUME_DB
	add_child(_player)


## Reproduce stream en bucle. No hace nada si esa pista ya está sonando.
## Con fade_time mayor que cero y otra pista sonando, la actual baja, se cambia
## y la nueva sube; fade_time es la duración total de ambos tramos.
func play_track(stream: AudioStream, fade_time: float = 0.0) -> void:
	if stream == _target and _player.playing:
		return
	_target = stream
	# El bucle real es el ajuste "loop" del importador del .ogg; esto solo
	# asegura que siga en bucle si alguien lo desactiva por error.
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	if _fade:
		_fade.kill()
		_fade = null

	if fade_time <= 0.0 or not _player.playing:
		_player.volume_db = VOLUME_DB
		_start(stream)
		return

	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", FADE_FLOOR_DB, fade_time / 2.0)
	_fade.tween_callback(_start.bind(stream))
	_fade.tween_property(_player, "volume_db", VOLUME_DB, fade_time / 2.0)


func _start(stream: AudioStream) -> void:
	_player.stream = stream
	_player.play()
