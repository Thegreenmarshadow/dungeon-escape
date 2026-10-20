@tool
extends McpTestSuite
## Pruebas de las cuentas del informe de patrones (PatternAnalysis): el
## tiempo de cada muestra del recorrido va a su celda según el hueco hasta la
## siguiente, y las distancias caminando a la puerta caen en la barra justa.


func suite_name() -> String:
	return "pattern_analysis"


## Pasillo de 4 celdas de suelo, puerta en la última. Recorrido: 3 s en la
## celda 0 (dos muestras), 0.5 s en la 1 y la última muestra (celda 2) se
## queda hasta el final del nivel (4 s).
func _corridor_level() -> Dictionary:
	return TelemetryStore.normalize_level({
		"level": 2,
		"duration_s": 4.0,
		"map": {"size": [4, 1], "cell_px": 16, "origin": [0, 0], "floor": "0,4", "door": [3, 0]},
		"path": [[0.0, 8.0, 8.0], [1.0, 8.0, 8.0], [3.0, 24.0, 8.0], [3.5, 40.0, 8.0]],
		"events": [
			{"t": 2.0, "type": "damage", "x": 8.0, "y": 8.0, "amount": 2, "source": "spikes"},
			{"t": 3.5, "type": "death", "x": 40.0, "y": 8.0, "cause": "spikes"},
		],
	})


func test_heat_grid_weights_samples_by_time_gap() -> void:
	var data := _corridor_level()
	var levels: Array[Dictionary] = [data, data]
	var time := PatternAnalysis.heat_grid(data["map"], levels, PatternAnalysis.LAYER_TIME)
	assert_eq(Array(time), [6.0, 1.0, 1.0, 0.0], "dos niveles iguales suman el doble")
	var damage := PatternAnalysis.heat_grid(data["map"], levels, PatternAnalysis.LAYER_DAMAGE)
	assert_eq(Array(damage), [4.0, 0.0, 0.0, 0.0], "el daño pesa su amount")
	var deaths := PatternAnalysis.heat_grid(data["map"], levels, PatternAnalysis.LAYER_DEATHS)
	assert_eq(Array(deaths), [0.0, 0.0, 2.0, 0.0])


func test_distance_histogram_uses_walking_distance_bins() -> void:
	var data := _corridor_level()
	var field := PatternAnalysis.distance_field(data["map"], Vector2i(3, 0))
	assert_eq(Array(field), [3, 2, 1, 0])
	assert_eq(PatternAnalysis.distance_bin(1, 2, 2), 0)
	assert_eq(PatternAnalysis.distance_bin(2, 2, 2), 1)
	assert_eq(PatternAnalysis.distance_bin(99, 2, 2), 1, "la última barra junta lo más lejano")
	var levels: Array[Dictionary] = [data]
	var histogram := PatternAnalysis.distance_histogram(levels, PatternAnalysis.LAYER_TIME, "door", 2, 2)
	# Celda 2 (distancia 1): 0.5 s. Celdas 0 y 1 (distancias 3 y 2): 3.5 s.
	assert_eq(Array(histogram["values"]), [0.5, 3.5])
	assert_eq(histogram["skipped"], 0)
	var no_key := PatternAnalysis.distance_histogram(levels, PatternAnalysis.LAYER_TIME, "key", 2, 2)
	assert_eq(no_key["skipped"], 1, "sin llave en el mapa, el nivel no entra")
