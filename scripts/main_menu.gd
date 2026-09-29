extends Control
## Pantalla de inicio: primera escena del juego.

const MENU_MUSIC := preload("res://assets/music/dungeon_yd.ogg")
## Segundos que tarda en aparecer el menú.
const FADE_IN_TIME := 0.8

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton
@onready var title: Label = %Title


func _ready() -> void:
	Music.play_track(MENU_MUSIC)
	play_button.pressed.connect(Game.start_new_game)
	quit_button.pressed.connect(get_tree().quit)
	# Con el foco en "Jugar" el menú también se maneja con el teclado.
	play_button.grab_focus()
	_fade_in()
	_pulse_title()
	_flicker_flames()


func _fade_in() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, FADE_IN_TIME)


func _pulse_title() -> void:
	# El contenedor fija el tamaño después de _ready, por eso el pivote se
	# recalcula cada vez que el título cambia de tamaño.
	title.resized.connect(func() -> void: title.pivot_offset = title.size / 2.0)
	var tween := create_tween().set_loops()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(title, "scale", Vector2(1.03, 1.03), 1.6)
	tween.tween_property(title, "scale", Vector2.ONE, 1.6)


func _flicker_flames() -> void:
	# Cada resplandor de antorcha parpadea a su propio ritmo.
	for glow: Node in get_tree().get_nodes_in_group("flame_glow"):
		var tween := glow.create_tween().set_loops()
		tween.tween_property(glow, "modulate:a", randf_range(0.55, 0.8), randf_range(0.15, 0.3))
		tween.tween_property(glow, "modulate:a", 1.0, randf_range(0.15, 0.3))
