@tool
class_name StatsSink
extends Node
## Puerto de salida de las estadísticas: lo que RunRecorder necesita para
## guardar una partida, sin saber cómo ni dónde se guarda. Esta clase base no
## hace nada (sirve como destino nulo); HttpStatsSink es la implementación que
## envía los datos al servidor local y las pruebas usan una que solo anota.
##
## Ninguna función puede bloquear ni fallar: si el destino no está disponible,
## la implementación decide si guarda los datos para más tarde o los descarta.
##
## run (start_run):     id, player_name, mode, run_seed, start_level, started_at.
## event (add_event):   seq, type, level, t_run_s, payload, at.
## summary (finish_run): outcome, score, level_reached, enemies_killed,
##                       duration_s, ended_at.


func start_run(_run: Dictionary) -> void:
	pass


func add_event(_run_id: String, _event: Dictionary) -> void:
	pass


func finish_run(_run_id: String, _summary: Dictionary) -> void:
	pass
