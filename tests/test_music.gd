@tool
extends McpTestSuite
## Pruebas de la música: las pistas del nivel se importan como audio válido y
## Music cambia de pista sin repetir pedidos ni cortar de golpe cuando se pide
## un fundido.

const MUSIC_SCRIPT := preload("res://scripts/music.gd")
const EXPLORATION_PATH := "res://assets/music/dungeon_exploration.ogg"
const DANGER_PATH := "res://assets/music/dungeon_danger.ogg"
## Pista de la que se parte; cualquier otra sirve para probar el cambio.
const OTHER_PATH := "res://assets/music/dungeon_yd.ogg"


func suite_name() -> String:
	return "music"


func test_level_tracks_import_as_ogg_streams() -> void:
	for path in [EXPLORATION_PATH, DANGER_PATH]:
		var stream := load(path)
		assert_true(stream is AudioStreamOggVorbis, "%s no se importó como ogg" % path)
		assert_gt(stream.get_length(), 20.0, "%s es demasiado corta para un bucle" % path)


func test_play_track_without_fade_switches_immediately() -> void:
	var music := _make_music()
	music.play_track(load(EXPLORATION_PATH))
	assert_eq(music._player.stream, load(EXPLORATION_PATH))
	music.play_track(load(DANGER_PATH))
	assert_eq(music._player.stream, load(DANGER_PATH), "sin fundido cambia al instante")
	assert_eq(music._player.volume_db, MUSIC_SCRIPT.VOLUME_DB)
	music._player.stop()


func test_same_track_request_does_not_restart_it() -> void:
	var music := _make_music()
	var stream: AudioStream = load(EXPLORATION_PATH)
	music.play_track(stream)
	assert_true(music._player.playing, "debe estar sonando")
	music._player.seek(5.0)
	music.play_track(stream)
	music.play_track(stream, 1.5)
	assert_true(music._player.get_playback_position() >= 4.0, "no debe reiniciarse")
	assert_true(music._fade == null, "pedir la misma pista no debe armar un fundido")
	music._player.stop()


func test_fade_keeps_old_track_until_it_is_out() -> void:
	var music := _make_music()
	var first: AudioStream = load(EXPLORATION_PATH)
	var second: AudioStream = load(DANGER_PATH)
	music.play_track(first)
	assert_true(music._player.playing)
	music.play_track(second, 1.5)
	assert_eq(music._player.stream, first, "con fundido la pista vieja sigue hasta bajar")
	assert_true(music._fade != null, "debe haber un fundido en curso")
	assert_eq(music._target, second)
	music._player.stop()


func test_new_request_during_fade_replaces_the_pending_target() -> void:
	var music := _make_music()
	var first: AudioStream = load(EXPLORATION_PATH)
	var second: AudioStream = load(DANGER_PATH)
	music.play_track(first)
	music.play_track(second, 1.5)
	music.play_track(first, 1.5)
	assert_eq(music._target, first, "pedir la pista original durante el fundido la vuelve a fijar")
	music._player.stop()


## Music armado con su script y metido en el árbol para que corra su _ready.
func _make_music() -> Node:
	var music: Node = MUSIC_SCRIPT.new()
	track(music)
	(Engine.get_main_loop() as SceneTree).root.add_child(music)
	return music
