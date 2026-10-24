class_name RunSummary
extends CanvasLayer
## Pantalla "Resumen de la partida": el mapa del nivel recién jugado con la
## ruta del jugador coloreada por tiempo, los íconos de los eventos (calavera
## = muerte, X roja = daño, llave, puerta, ...) y un deslizador para
## reproducir el recorrido. La abre la HUD al morir o al superar un nivel, por
## encima de la pantalla final; "Continuar" la cierra y vuelve a esa pantalla.
##
## show_level acepta Telemetry.last_level_data o un archivo de
## TelemetryStore.load_level_file. Funciona con el árbol en pausa
## (process_mode Always) y no cambia nada del juego.

## Se cerró (Continuar o Esc).
signal closed

## Una reproducción completa dura más o menos esto, en segundos: los niveles
## largos se reproducen más rápido.
const REPLAY_TARGET_SECONDS := 12.0
## Nunca más lento que el tiempo real.
const MIN_REPLAY_SPEED := 1.0
## Leyenda: tipo de evento (o marcador) y texto.
const LEGEND: Array[Array] = [
	[RouteMapView.MARKER_START, "Inicio"],
	[TelemetryStore.EVENT_DEATH, "Muerte"],
	[TelemetryStore.EVENT_DAMAGE, "Daño recibido"],
	[TelemetryStore.EVENT_KEY, "Llave"],
	[TelemetryStore.EVENT_DOOR, "Puerta"],
	[TelemetryStore.EVENT_ENEMY_KILLED, "Enemigo eliminado"],
	[TelemetryStore.EVENT_HEART, "Corazón"],
	[TelemetryStore.EVENT_WEAPON_CHANGED, "Cambio de arma"],
	[TelemetryStore.EVENT_REVIVE, "Reaparece"],
]
const OUTCOME_TEXT := {
	TelemetryRecorder.OUTCOME_DIED: "Derrota",
	TelemetryRecorder.OUTCOME_COMPLETED: "Nivel superado",
	TelemetryRecorder.OUTCOME_ABANDONED: "Abandonado",
	TelemetryRecorder.OUTCOME_IN_PROGRESS: "En curso",
}
## Nombres de las fuentes de daño que no son un enemigo.
const SOURCE_NAMES := {"spikes": "picos", "projectile": "proyectil", "boss_hazard": "trampa del jefe", "": "desconocida"}
const PLAY_TEXT := "Reproducir"
const PAUSE_TEXT := "Pausa"

@onready var map_view: RouteMapView = %MapView
@onready var subtitle_label: Label = %SubtitleLabel
@onready var stats_label: Label = %StatsLabel
@onready var legend_box: HFlowContainer = %Legend
@onready var play_button: Button = %PlayButton
@onready var replay_slider: HSlider = %ReplaySlider
@onready var time_label: Label = %TimeLabel
@onready var close_button: Button = %CloseButton

## Datos del nivel que se muestra (normalizados).
var data: Dictionary = {}
## Segundos del nivel por segundo real al reproducir.
var replay_speed := 1.0
var playing := false
var _focus_before: Control


func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS
	play_button.pressed.connect(toggle_playback)
	close_button.pressed.connect(close)
	replay_slider.value_changed.connect(_on_slider_changed)
	_build_legend()
	_trap_focus([play_button, replay_slider, close_button])


## Muestra el resumen de un nivel. Con datos vacíos se ve el aviso "Sin
## recorrido registrado" y la reproducción queda desactivada.
func show_level(level_data: Dictionary) -> void:
	data = TelemetryStore.normalize_level(level_data) if not level_data.is_empty() else {}
	map_view.set_data(data)
	var duration := map_view.replay.duration
	replay_speed = maxf(MIN_REPLAY_SPEED, duration / REPLAY_TARGET_SECONDS)
	replay_slider.max_value = maxf(duration, 0.01)
	replay_slider.set_value_no_signal(duration)
	_on_slider_changed(duration)
	var can_replay := map_view.has_route()
	replay_slider.editable = can_replay
	play_button.disabled = not can_replay
	_set_playing(false)
	subtitle_label.text = subtitle_for(data)
	stats_label.text = stats_for(data)
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focused != null and not is_ancestor_of(focused):
		_focus_before = focused
	show()
	(play_button if can_replay else close_button).grab_focus()


## Cierra el resumen y devuelve el foco a lo que lo tenía antes (el botón de
## la pantalla final).
func close() -> void:
	if not visible:
		return
	_set_playing(false)
	hide()
	if is_instance_valid(_focus_before) and _focus_before.is_visible_in_tree():
		_focus_before.grab_focus()
	_focus_before = null
	closed.emit()


## Reproduce desde donde está el deslizador (desde el inicio si está al final)
## o pausa.
func toggle_playback() -> void:
	if playing:
		_set_playing(false)
		return
	if replay_slider.value >= replay_slider.max_value:
		replay_slider.value = 0.0
	_set_playing(true)


func _process(delta: float) -> void:
	if not playing or not visible:
		return
	var next := minf(replay_slider.value + delta * replay_speed, replay_slider.max_value)
	replay_slider.value = next
	if next >= replay_slider.max_value:
		_set_playing(false)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _set_playing(value: bool) -> void:
	playing = value
	play_button.text = PAUSE_TEXT if value else PLAY_TEXT


func _on_slider_changed(value: float) -> void:
	map_view.replay_time = value
	time_label.text = "%s / %s" % [format_time(value), format_time(map_view.replay.duration)]


## Línea debajo del título: nivel, modo y resultado (con la causa de muerte).
static func subtitle_for(level_data: Dictionary) -> String:
	if level_data.is_empty():
		return "Sin datos del nivel"
	var parts: Array[String] = ["Nivel %d" % int(level_data.get("level", 1))]
	match str(level_data.get("mode", "")):
		"demo":
			parts[0] = "Demo"
		"test":
			parts.append("Modo prueba")
	var outcome := str(level_data.get("outcome", ""))
	var outcome_text: String = OUTCOME_TEXT.get(outcome, outcome)
	if outcome == TelemetryRecorder.OUTCOME_DIED:
		var deaths := TelemetryStore.events_of_type(level_data, TelemetryStore.EVENT_DEATH)
		if not deaths.is_empty():
			outcome_text += " (%s)" % source_name(str(deaths[-1].get("cause", "")))
	parts.append(outcome_text)
	return " · ".join(parts)


## Resumen en texto: tiempo, daño por fuente, enemigos, corazones y armas.
static func stats_for(level_data: Dictionary) -> String:
	if level_data.is_empty():
		return "La telemetría no registró este nivel."
	# El daño de la telemetría está en corazones y puede tener medios.
	var damage := 0.0
	var sources := {}
	for event: Dictionary in TelemetryStore.events_of_type(level_data, TelemetryStore.EVENT_DAMAGE):
		var amount := JsonFile.to_float(event.get("amount", 1.0))
		var source := source_name(str(event.get("source", "")))
		damage += amount
		sources[source] = float(sources.get(source, 0.0)) + amount
	var lines: Array[String] = ["Tiempo: %s" % format_time(float(level_data.get("duration_s", 0.0)))]
	lines.append("Daño recibido: %s %s" % [Heart.format_heart_amount(damage), "corazón" if damage == 1.0 else "corazones"])
	for source: String in sources:
		lines.append("   %s: %s" % [source, Heart.format_heart_amount(sources[source])])
	lines.append("Enemigos eliminados: %d" % TelemetryStore.events_of_type(level_data, TelemetryStore.EVENT_ENEMY_KILLED).size())
	var hearts := TelemetryStore.events_of_type(level_data, TelemetryStore.EVENT_HEART).size()
	if hearts > 0:
		lines.append("Corazones: %d" % hearts)
	var attacks := TelemetryStore.events_of_type(level_data, TelemetryStore.EVENT_ATTACK)
	if not attacks.is_empty():
		var hits := attacks.filter(func(event: Dictionary) -> bool: return event.get("hit", false))
		lines.append("Golpes acertados: %d/%d" % [hits.size(), attacks.size()])
	var weapons: Array = level_data.get("weapons_used", [])
	if not weapons.is_empty():
		lines.append("Armas: %s" % ", ".join(PackedStringArray(weapons)))
	return "\n".join(lines)


static func source_name(source: String) -> String:
	return SOURCE_NAMES.get(source, source)


## Tiempo en minutos y segundos (1:05).
static func format_time(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	return "%d:%02d" % [total / 60, total % 60]


func _build_legend() -> void:
	for entry in LEGEND:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var icon := LegendIcon.new()
		icon.type = entry[0]
		row.add_child(icon)
		var label := Label.new()
		label.text = entry[1]
		label.add_theme_font_size_override("font_size", 16)
		row.add_child(label)
		legend_box.add_child(row)


## El foco no sale del resumen hacia los botones de la pantalla de abajo:
## cada control apunta solo a los del resumen.
func _trap_focus(controls: Array[Control]) -> void:
	for i in controls.size():
		var control := controls[i]
		var previous := controls[(i - 1 + controls.size()) % controls.size()]
		var next := controls[(i + 1) % controls.size()]
		control.focus_neighbor_left = control.get_path_to(previous)
		control.focus_neighbor_right = control.get_path_to(next)
		control.focus_neighbor_top = control.get_path_to(control)
		control.focus_neighbor_bottom = control.get_path_to(control)
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)


## Ícono de la leyenda: el mismo dibujo que en el mapa.
class LegendIcon extends Control:
	var type := ""

	func _init() -> void:
		custom_minimum_size = Vector2(22, 22)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		RouteMapView.draw_event_icon(self, type, size / 2.0, 16.0, {"state": "escaped"} if type == TelemetryStore.EVENT_DOOR else {})
