@tool
extends McpTestSuite
## Pruebas de RouteReplay, lo frágil del resumen del nivel: el recorrido se
## corta en cada revive, la posición se interpola por tiempo (no por índice) y
## el paso del mundo a la vista no deforma el mapa ni lo saca de la vista.


func suite_name() -> String:
	return "route_replay"


## Recorrido de ejemplo: quieto 1 s, camina 32 px, cae, revive lejos.
func _sample_data() -> Dictionary:
	return {
		"duration_s": 6.0,
		"map": {"size": [10, 5], "cell_px": 16, "origin": [0, 0], "floor": "50"},
		"path": [[0.0, 8.0, 8.0], [1.0, 8.0, 8.0], [1.5, 40.0, 8.0], [3.0, 40.0, 8.0], [4.0, 120.0, 56.0], [5.0, 136.0, 56.0]],
		"events": [
			{"t": 3.0, "type": "death", "x": 40.0, "y": 8.0, "final": false},
			{"t": 4.0, "type": "revive", "x": 120.0, "y": 56.0, "path_index": 4},
		],
	}


func test_route_breaks_at_revive_path_index() -> void:
	var replay := RouteReplay.from_data(_sample_data())
	assert_eq(replay.segments.size(), 2, "dos tramos")
	assert_eq(replay.segments[0].size(), 4)
	assert_eq(replay.segments[1][0], Vector2(120, 56), "el tramo nuevo empieza en el revive")
	assert_eq(replay.duration, 6.0)


func test_position_is_interpolated_by_time() -> void:
	var replay := RouteReplay.from_data(_sample_data())
	assert_eq(replay.position_at(0.5), Vector2(8, 8), "quieto")
	assert_eq(replay.position_at(1.25), Vector2(24, 8), "a mitad de camino en tiempo")
	assert_eq(replay.position_at(3.5), Vector2(40, 8), "caído: se queda donde cayó, no cruza el mapa")
	assert_eq(replay.position_at(4.5), Vector2(128, 56), "después del revive, en el tramo nuevo")
	assert_eq(replay.position_at(99.0), Vector2(136, 56), "después del final, el último punto")
	assert_eq(replay.points_until(0, 1.5), 3)


func test_fit_keeps_aspect_and_stays_inside_the_view() -> void:
	var world := RouteReplay.map_rect(_sample_data()["map"])
	assert_eq(world, Rect2(0, 0, 160, 80))
	var view := Vector2(400, 400)
	var xf := RouteReplay.fit(world, view, 10.0)
	assert_eq(xf.get_scale(), Vector2(2.375, 2.375), "escala uniforme, limitada por el ancho")
	var top_left := xf * world.position
	var bottom_right := xf * world.end
	assert_eq(top_left.x, 10.0, "margen a la izquierda")
	assert_eq(bottom_right.x, 390.0, "margen a la derecha")
	assert_eq((top_left.y + bottom_right.y) / 2.0, 200.0, "centrado en vertical")


func test_world_rect_without_map_uses_the_route() -> void:
	var data := {"path": [[0.0, 100.0, 100.0], [1.0, 200.0, 150.0]]}
	var rect := RouteReplay.from_data(data).world_rect
	assert_true(rect.has_point(Vector2(100, 100)) and rect.has_point(Vector2(200, 150)), "contiene el recorrido")
	assert_true(RouteReplay.from_data({}).is_empty(), "sin datos no falla")
