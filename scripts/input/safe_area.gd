class_name SafeArea
extends RefCounted
## Márgenes de la zona segura de la pantalla (notch, esquinas redondeadas,
## barras del sistema) en píxeles de la vista, para que la interfaz y los
## controles táctiles no queden debajo. Salen de
## DisplayServer.get_display_safe_area(). En PC no hay notch: en Windows la
## "zona segura" es el escritorio sin la barra de tareas, así que fuera de
## Android e iOS devuelve márgenes en cero.


## Márgenes { left, top, right, bottom } de la zona segura para viewport.
static func insets(viewport: Viewport) -> Dictionary:
	if not OS.has_feature("mobile") or viewport == null:
		return zero()
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return zero()
	# Con stretch canvas_items la vista no mide lo mismo que la ventana.
	var factor := viewport.get_visible_rect().size / window
	return insets_from(DisplayServer.get_display_safe_area(), DisplayServer.screen_get_size(), factor)


## Márgenes de la zona segura safe dentro de una pantalla screen_size (ambas en
## píxeles de pantalla), pasados a píxeles de la vista con factor. Una zona
## vacía (el sistema no la informó) da cero.
static func insets_from(safe: Rect2i, screen_size: Vector2i, factor: Vector2) -> Dictionary:
	if safe.size.x <= 0 or safe.size.y <= 0:
		return zero()
	return {
		"left": maxf(safe.position.x, 0.0) * factor.x,
		"top": maxf(safe.position.y, 0.0) * factor.y,
		"right": maxf(screen_size.x - safe.end.x, 0.0) * factor.x,
		"bottom": maxf(screen_size.y - safe.end.y, 0.0) * factor.y,
	}


static func zero() -> Dictionary:
	return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
