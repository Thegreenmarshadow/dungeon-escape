class_name TouchActionButton
extends TouchScreenButton
## Botón táctil redondo. Usa la propiedad action de TouchScreenButton: al
## tocarlo se aprieta esa acción del Input Map (attack, jump, parry, pause), la
## misma que la tecla o el botón del mando. Cada TouchScreenButton sigue a su
## propio dedo, así se puede apretar mientras otro dedo maneja el joystick.
##
## No usa texturas: se dibuja solo (un círculo con un ícono del juego o una
## figura y un rótulo) y su forma de toque es un círculo del mismo diámetro,
## centrado en la posición del nodo.

## Figura que se dibuja si no hay icon.
enum Glyph { NONE, JUMP, PAUSE }

const COLOR_FILL := Color(0.07, 0.05, 0.1)
const COLOR_LINE := Color(1.0, 0.86, 0.5)
const COLOR_TEXT := Color(1.0, 0.95, 0.85)

## Diámetro del botón en píxeles de la vista (también el del área de toque).
@export var diameter: float = 112.0:
	set(value):
		diameter = maxf(value, 8.0)
		_update_shape()
		queue_redraw()
## Ícono del centro (por ejemplo, el de la espada). Se escala sin suavizar.
@export var icon: Texture2D:
	set(value):
		icon = value
		queue_redraw()
## Figura dibujada cuando no hay ícono.
@export var glyph: Glyph = Glyph.NONE:
	set(value):
		glyph = value
		queue_redraw()
## Rótulo bajo el ícono; vacío no muestra nada.
@export var caption := "":
	set(value):
		caption = value
		queue_redraw()
## Opacidad de lo dibujado (0 a 1).
@export_range(0.0, 1.0, 0.05) var opacity: float = 0.55:
	set(value):
		opacity = clampf(value, 0.0, 1.0)
		queue_redraw()


func _ready() -> void:
	visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	pressed.connect(queue_redraw)
	released.connect(queue_redraw)
	_update_shape()


func _update_shape() -> void:
	var circle := CircleShape2D.new()
	circle.radius = diameter / 2.0
	shape = circle


func _draw() -> void:
	var radius := diameter / 2.0
	var down := is_pressed()
	var alpha := minf(opacity * (1.5 if down else 1.0), 1.0)
	draw_circle(Vector2.ZERO, radius, Color(COLOR_FILL, alpha * (0.75 if down else 0.5)))
	draw_arc(Vector2.ZERO, radius - 1.5, 0.0, TAU, 48, Color(COLOR_LINE, alpha), 3.0, true)
	if down:
		draw_circle(Vector2.ZERO, radius * 0.9, Color(COLOR_LINE, alpha * 0.25))
	var icon_center := Vector2(0.0, -radius * 0.12 if caption != "" else 0.0)
	var icon_size := diameter * 0.42
	if icon != null:
		var rect := Rect2(icon_center - Vector2.ONE * icon_size / 2.0, Vector2.ONE * icon_size)
		draw_texture_rect(icon, rect, false, Color(1, 1, 1, alpha))
	else:
		_draw_glyph(icon_center, icon_size, Color(COLOR_TEXT, alpha))
	if caption != "":
		var font := ThemeDB.fallback_font
		var font_size := int(maxf(diameter * 0.13, 10.0))
		draw_string(font, Vector2(-radius, radius * 0.62), caption, HORIZONTAL_ALIGNMENT_CENTER,
				diameter, font_size, Color(COLOR_TEXT, alpha))


func _draw_glyph(center: Vector2, glyph_size: float, color: Color) -> void:
	var half := glyph_size / 2.0
	match glyph:
		Glyph.JUMP:
			# Flecha hacia arriba con una raya de suelo: despegar.
			var tip := center + Vector2(0.0, -half)
			draw_polyline(PackedVector2Array([center + Vector2(-half * 0.8, -half * 0.05), tip,
					center + Vector2(half * 0.8, -half * 0.05)]), color, glyph_size * 0.13, true)
			draw_line(tip, center + Vector2(0.0, half * 0.55), color, glyph_size * 0.13, true)
			draw_line(center + Vector2(-half * 0.8, half * 0.9), center + Vector2(half * 0.8, half * 0.9),
					color, glyph_size * 0.1, true)
		Glyph.PAUSE:
			var bar := Vector2(glyph_size * 0.22, glyph_size * 0.8)
			draw_rect(Rect2(center + Vector2(-half * 0.6, -bar.y / 2.0), bar), color)
			draw_rect(Rect2(center + Vector2(half * 0.6 - bar.x, -bar.y / 2.0), bar), color)
