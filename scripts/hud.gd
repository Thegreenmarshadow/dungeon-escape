extends CanvasLayer
## Interfaz del jugador: vida (corazones llenos, medios y vacíos), indicador de llave, enemigos eliminados,
## monedas, barra de vida del jefe, minimapa, mensajes, pantallas de fin de
## partida, el resumen del nivel (RunSummary) y la tienda entre niveles.
## Solo muestra información; el nivel decide cuándo actualizarla y qué pasa al
## comprar.

## Se emite al pulsar el botón de la pantalla de fin de partida.
signal action_pressed
## Se emiten al elegir una opción en la pantalla de Game Over. Cada vez que se
## muestra la pantalla se emite como mucho una de las dos.
signal retry_pressed
signal menu_pressed
## Se emite al pulsar un artículo de la tienda (un Shop.ITEM_*). El nivel hace
## la compra y vuelve a llamar a show_shop.
signal buy_pressed(item: StringName)

## Duración del fundido de entrada de la pantalla de Game Over, en segundos.
const GAME_OVER_FADE_TIME := 0.5
## Tamaño de cada corazón de vida: el dibujo de 9x8 escalado x3.
const LIFE_ICON_SIZE := Vector2(27, 24)
## Opacidad de la parte vacía de un corazón (la vida perdida), igual que la
## llave que todavía no se tiene.
const EMPTY_HEART_ALPHA := 0.25
## Nombre de cada artículo de la tienda y el texto que se muestra cuando no está
## disponible. Las armas muestran además su ícono.
const ITEM_NAMES := {Shop.ITEM_DAMAGE: "+1 daño", Shop.ITEM_LIFE: "+1 corazón",
		Shop.ITEM_SPEAR: "Lanza", Shop.ITEM_DAGGER: "Daga"}
const ITEM_UNAVAILABLE_TEXT := {Shop.ITEM_DAMAGE: "al máximo", Shop.ITEM_LIFE: "vida completa",
		Shop.ITEM_SPEAR: "equipada", Shop.ITEM_DAGGER: "equipada"}
## Ancho del ícono de las armas en los botones de la tienda (16 px escalado x2).
const ITEM_ICON_WIDTH := 32

## El resumen del nivel (RunSummary) se abre solo al morir o al superar un
## nivel, encima de la pantalla final. Con false solo se abre con el botón
## "Ver recorrido". Sin telemetría no hay resumen ni botón.
@export var summary_on_death := true
@export var summary_on_complete := true

@onready var lives_hearts: HBoxContainer = %LivesHearts
@onready var key_icon: TextureRect = %KeyIcon
@onready var kills_label: Label = %KillsLabel
@onready var coins_label: Label = %CoinsLabel
@onready var message_label: Label = %MessageLabel
@onready var message_timer: Timer = %MessageTimer
@onready var end_screen: Control = %EndScreen
@onready var end_title: Label = %EndTitle
@onready var end_stats: Label = %EndStats
@onready var action_button: Button = %ActionButton
@onready var shop: Control = %Shop
@onready var shop_coins_label: Label = %ShopCoinsLabel
@onready var shop_items: HFlowContainer = %ShopItems
@onready var game_over_screen: Control = %GameOverScreen
@onready var new_record_label: Label = %NewRecordLabel
@onready var record_label: Label = %RecordLabel
@onready var breakdown_label: Label = %BreakdownLabel
@onready var retry_button: Button = %RetryButton
@onready var back_to_menu_button: Button = %BackToMenuButton
@onready var boss_bar: BossHealthBar = %BossBar
@onready var minimap: Minimap = %Minimap
@onready var run_summary: RunSummary = %RunSummary
@onready var end_summary_button: Button = %EndSummaryButton
@onready var game_over_summary_button: Button = %GameOverSummaryButton
@onready var top_bar: Control = $TopBar

var _game_over_tween: Tween
# Márgenes de la escena de lo que va pegado a los bordes; la zona segura (notch)
# se les suma en _apply_safe_area.
var _edge_offsets: Dictionary[Control, Vector4] = {}
# Segundos de un mensaje sin duración propia (el wait_time de la escena).
var _message_time := 1.5
# Botón de cada artículo de la tienda; se crean la primera vez que se muestra.
var _shop_buttons: Dictionary[StringName, Button] = {}
# Último nivel terminado que registró la telemetría (lo muestra el resumen).
var _summary_data: Dictionary = {}


func _ready() -> void:
	end_screen.hide()
	shop.hide()
	game_over_screen.hide()
	message_label.hide()
	_message_time = message_timer.wait_time
	message_timer.timeout.connect(message_label.hide)
	action_button.pressed.connect(action_pressed.emit)
	retry_button.pressed.connect(_on_game_over_choice.bind(retry_pressed))
	back_to_menu_button.pressed.connect(_on_game_over_choice.bind(menu_pressed))
	set_has_key(false)
	end_summary_button.pressed.connect(show_run_summary)
	game_over_summary_button.pressed.connect(show_run_summary)
	var telemetry := get_node_or_null(^"/root/Telemetry")
	if telemetry != null:
		telemetry.level_finished.connect(_on_level_finished)
	for control: Control in [top_bar, minimap, boss_bar]:
		_edge_offsets[control] = Vector4(control.offset_left, control.offset_top,
				control.offset_right, control.offset_bottom)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


## Corre la barra de arriba, el minimapa y la barra del jefe dentro de la zona
## segura (en un celular con notch; en PC los márgenes son cero).
func _apply_safe_area() -> void:
	var insets := SafeArea.insets(get_viewport())
	for control: Control in _edge_offsets:
		var base: Vector4 = _edge_offsets[control]
		# La barra de arriba va a la izquierda y el minimapa a la derecha; la
		# del jefe está centrada, solo baja.
		var shift_x: float = insets["left"] if control == top_bar \
				else -insets["right"] if control == minimap else 0.0
		control.offset_left = base.x + shift_x
		control.offset_right = base.z + shift_x
		control.offset_top = base.y + insets["top"]
		control.offset_bottom = base.w + insets["top"]


## Muestra la vida (health y max_health en medios corazones) con un corazón
## por cada HALF_HEARTS_PER_HEART de la vida máxima: llenos, medios o vacíos
## según heart_fills. La parte vacía se ve apagada, igual que la llave.
func set_health(health: int, max_health: int) -> void:
	var fills := heart_fills(health, max_health)
	while lives_hearts.get_child_count() < fills.size():
		lives_hearts.add_child(_make_life_icon())
	while lives_hearts.get_child_count() > fills.size():
		var extra := lives_hearts.get_child(lives_hearts.get_child_count() - 1)
		lives_hearts.remove_child(extra)
		extra.queue_free()
	for i in fills.size():
		var fill: TextureRect = lives_hearts.get_child(i).get_child(0)
		fill.visible = fills[i] > 0
		fill.texture = Heart.get_texture() if fills[i] >= Heart.HALF_HEARTS_PER_HEART \
				else Heart.get_half_texture()


## Medios corazones llenos de cada corazón de la HUD, de izquierda a derecha:
## HALF_HEARTS_PER_HEART (lleno), 1 (medio) o 0 (vacío). Hay un corazón por
## cada corazón de la vida máxima, o de la vida si la supera (la demo empieza
## con más). Con 5 de 6: [2, 2, 1].
static func heart_fills(health: int, max_health: int) -> Array[int]:
	var per_heart := Heart.HALF_HEARTS_PER_HEART
	var count := ceili(maxi(maxi(health, max_health), 0) / float(per_heart))
	var fills: Array[int] = []
	for i in count:
		fills.append(clampi(health - i * per_heart, 0, per_heart))
	return fills


## Un corazón de la HUD: el dibujo entero apagado (la parte vacía) y encima,
## como hijo, el lleno o el medio corazón opacos. El apagado va en
## self_modulate para no apagar también al hijo.
func _make_life_icon() -> TextureRect:
	var icon := _make_heart_rect(Heart.get_texture())
	icon.custom_minimum_size = LIFE_ICON_SIZE
	icon.self_modulate = Color(1, 1, 1, EMPTY_HEART_ALPHA)
	var fill := _make_heart_rect(Heart.get_texture())
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(fill)
	return icon


func _make_heart_rect(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return rect


## Muestra la llave opaca si el jugador la tiene y apagada si no.
func set_has_key(has_key: bool) -> void:
	key_icon.modulate = Color.WHITE if has_key else Color(1, 1, 1, 0.25)


func set_kills(killed: int, total: int) -> void:
	kills_label.text = "Enemigos: %d/%d" % [killed, total]


func set_coins(coins: int) -> void:
	# Feedback: el contador rebota y se pone dorado cuando suben las monedas.
	var gained := coins_label.text.is_valid_int() and coins > int(coins_label.text)
	coins_label.text = str(coins)
	if gained:
		coins_label.pivot_offset = coins_label.size / 2.0
		coins_label.scale = Vector2(1.5, 1.5)
		coins_label.modulate = Color(1.0, 0.85, 0.2)
		var tween := coins_label.create_tween().set_parallel()
		tween.tween_property(coins_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(coins_label, "modulate", Color.WHITE, 0.3)


## Muestra la barra de vida de boss (nombre y vida) mientras esté vivo y en
## alerta. La barra se actualiza sola.
func track_boss(boss: BossBase) -> void:
	boss_bar.track(boss)


## Muestra un mensaje temporal en la parte inferior de la pantalla. duration
## son los segundos que se ve; 0 usa el tiempo de MessageTimer.
func show_message(text: String, duration: float = 0.0) -> void:
	message_label.text = text
	message_label.show()
	# start(segundos) cambia wait_time: siempre se pasa el tiempo, así un
	# mensaje largo no alarga los siguientes.
	message_timer.start(duration if duration > 0.0 else _message_time)


## Muestra la pantalla de fin de partida. details es una línea opcional
## debajo del título (por ejemplo, las estadísticas de la partida) y
## action_text es el texto del botón, que emite action_pressed.
func show_end_screen(title: String, details: String, action_text: String) -> void:
	message_label.hide()
	end_title.text = title
	end_stats.text = details
	end_stats.visible = not details.is_empty()
	action_button.text = action_text
	end_screen.show()
	# Con el foco en el botón se puede continuar con Enter o Espacio.
	action_button.grab_focus()


## Muestra la tienda dentro de la pantalla de fin de nivel, o la actualiza si ya
## se ve. offers tiene un diccionario por artículo con item (un Shop.ITEM_*),
## price, available (si se ofrece) y affordable (si se puede comprar ahora con
## coins). Solo se pueden pulsar los artículos que se pueden comprar.
func show_shop(coins: int, offers: Array[Dictionary]) -> void:
	shop_coins_label.text = "Monedas: %d" % coins
	for offer in offers:
		var item: StringName = offer["item"]
		var button: Button = _shop_buttons.get(item)
		if button == null:
			button = _make_shop_button(item)
		var status: String = "%d monedas" % offer["price"] if offer["available"] \
				else ITEM_UNAVAILABLE_TEXT.get(item, "no disponible")
		button.text = "%s · %s" % [ITEM_NAMES.get(item, String(item)), status]
		button.disabled = not offer["affordable"]
	shop.show()
	# Un botón recién desactivado (por ejemplo, tras comprar) no debe quedarse
	# con el foco: se pasa al de continuar.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is BaseButton and focused.disabled:
		action_button.grab_focus()


func _make_shop_button(item: StringName) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(240, 44)
	button.add_theme_font_size_override("font_size", 22)
	if Shop.is_weapon(item):
		var weapon := WeaponData.load_by_id(item)
		if weapon:
			button.icon = weapon.icon
			button.add_theme_constant_override("icon_max_width", ITEM_ICON_WIDTH)
	button.pressed.connect(buy_pressed.emit.bind(item))
	shop_items.add_child(button)
	_shop_buttons[item] = button
	return button


## Muestra la pantalla de Game Over con el resumen de la partida y un fundido
## de entrada. Si is_new_record es true se destaca el récord nuevo; si no, se
## muestra record_text (puesto y récord), que puede estar vacío. Los botones
## emiten retry_pressed o menu_pressed.
func show_game_over(level: int, kills: int, score: int, is_new_record: bool, record_text: String) -> void:
	message_label.hide()
	new_record_label.visible = is_new_record
	record_label.text = record_text
	record_label.visible = not is_new_record and not record_text.is_empty()
	breakdown_label.text = "Nivel alcanzado: %d\nEnemigos eliminados: %d\nPuntos: %d" % [
		level, kills, score]
	_set_game_over_buttons_enabled(true)

	game_over_screen.modulate.a = 0.0
	game_over_screen.show()
	retry_button.grab_focus()

	# El nivel pausa el árbol al mostrar esta pantalla: el tween debe seguir
	# corriendo en pausa (la HUD además tiene process_mode = Always).
	if _game_over_tween:
		_game_over_tween.kill()
	_game_over_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_game_over_tween.tween_property(game_over_screen, "modulate:a", 1.0, GAME_OVER_FADE_TIME)


## Desactiva los dos botones antes de emitir la elección, así un segundo clic
## o tecla (el cambio de escena ocurre recién al final del frame) no dispara
## otra acción.
func _on_game_over_choice(choice: Signal) -> void:
	_set_game_over_buttons_enabled(false)
	choice.emit()


func _set_game_over_buttons_enabled(enabled: bool) -> void:
	retry_button.disabled = not enabled
	back_to_menu_button.disabled = not enabled


## Abre el resumen del último nivel terminado (mapa, ruta y reproducción).
## No hace nada si la telemetría no registró ninguno.
func show_run_summary() -> void:
	if not _summary_data.is_empty():
		run_summary.show_level(_summary_data)


## La telemetría escribió el nivel: se guarda para el resumen, aparece el botón
## "Ver recorrido" en la pantalla final y, según summary_on_death /
## summary_on_complete, se abre el resumen. Los niveles abandonados no tienen
## pantalla final.
func _on_level_finished(data: Dictionary, _path: String) -> void:
	var outcome: String = data.get("outcome", "")
	var died := outcome == TelemetryRecorder.OUTCOME_DIED
	if not died and outcome != TelemetryRecorder.OUTCOME_COMPLETED:
		return
	_summary_data = data
	end_summary_button.show()
	game_over_summary_button.show()
	if summary_on_death if died else summary_on_complete:
		show_run_summary()
