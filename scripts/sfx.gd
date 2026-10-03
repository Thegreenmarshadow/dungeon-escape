extends Node
## Efectos de sonido. Se registra como Autoload ("Sfx") para que los sonidos no
## se corten al liberarse quien los pidió (un enemigo que muere, una llave
## recogida) ni al cambiar de escena. Usa varios reproductores para que los
## sonidos se puedan superponer. Uso: Sfx.play(&"sword_swing").
##
## También agrega el sonido de clic a todos los botones de la interfaz, así el
## menú y la HUD no necesitan saber nada del audio.

## Volumen de los efectos; un poco más alto que la música.
const VOLUME_DB := -6.0
## Cantidad de sonidos que pueden sonar a la vez.
const POOL_SIZE := 8
## Variación máxima del tono (en proporción) para los sonidos repetitivos.
const PITCH_VARIATION := 0.1

const SOUNDS := {
	&"sword_swing": preload("res://assets/sfx/sword_swing.ogg"),
	&"enemy_hit": preload("res://assets/sfx/enemy_hit.ogg"),
	&"enemy_death": preload("res://assets/sfx/enemy_death.ogg"),
	&"player_hurt": preload("res://assets/sfx/player_hurt.ogg"),
	&"game_over": preload("res://assets/sfx/game_over.ogg"),
	&"key_pickup": preload("res://assets/sfx/key_pickup.ogg"),
	&"door_open": preload("res://assets/sfx/door_open.ogg"),
	&"heart_pickup": preload("res://assets/sfx/heart_pickup.ogg"),
	&"level_complete": preload("res://assets/sfx/level_complete.ogg"),
	&"ui_click": preload("res://assets/sfx/ui_click.ogg"),
}
## Sonidos que se repiten seguido: varían un poco el tono para no cansar.
const VARIED_PITCH: Array[StringName] = [&"sword_swing", &"enemy_hit", &"player_hurt"]

# Ordenados del menos al más recientemente usado.
var _players: Array[AudioStreamPlayer] = []


func _enter_tree() -> void:
	# Se conecta acá y no en _ready: la escena inicial entra al árbol antes de
	# que se ejecute el _ready de los Autoloads, y sus botones se perderían.
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	# Los sonidos de Game Over, nivel superado y los clics suenan con el juego
	# en pausa.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.volume_db = VOLUME_DB
		add_child(player)
		_players.append(player)


## Reproduce el sonido sound (una clave de SOUNDS) una vez.
func play(sound: StringName) -> void:
	var stream: AudioStream = SOUNDS.get(sound)
	if stream == null:
		push_warning("Sfx: sonido desconocido '%s'" % sound)
		return
	var player := _take_player()
	player.stream = stream
	player.pitch_scale = 1.0
	if sound in VARIED_PITCH:
		player.pitch_scale = randf_range(1.0 - PITCH_VARIATION, 1.0 + PITCH_VARIATION)
	player.play()


## Devuelve un reproductor libre; si todos suenan, el usado hace más tiempo.
func _take_player() -> AudioStreamPlayer:
	var chosen := _players[0]
	for player in _players:
		if not player.playing:
			chosen = player
			break
	# Pasa al final de la lista: es el más recientemente usado.
	_players.erase(chosen)
	_players.append(chosen)
	return chosen


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(play.bind(&"ui_click"))
