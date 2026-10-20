extends CanvasLayer
## Interfaz del jugador: vidas, indicador de llave, enemigos eliminados,
## monedas, barra de vida del jefe, mensajes, pantallas de fin de partida y la tienda entre niveles.
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
## Nombre de cada artículo de la tienda y el texto que se muestra cuando no está
## disponible. Las armas muestran además su ícono.
const ITEM_NAMES := {Shop.ITEM_DAMAGE: "+1 daño", Shop.ITEM_LIFE: "+1 vida",
		Shop.ITEM_SPEAR: "Lanza", Shop.ITEM_DAGGER: "Daga"}
const ITEM_UNAVAILABLE_TEXT := {Shop.ITEM_DAMAGE: "al máximo", Shop.ITEM_LIFE: "vidas completas",
		Shop.ITEM_SPEAR: "equipada", Shop.ITEM_DAGGER: "equipada"}
## Ancho del ícono de las armas en los botones de la tienda (16 px escalado x2).
const ITEM_ICON_WIDTH := 32

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

var _game_over_tween: Tween
# Botón de cada artículo de la tienda; se crean la primera vez que se muestra.
var _shop_buttons: Dictionary[StringName, Button] = {}


func _ready() -> void:
	end_screen.hide()
	shop.hide()
	game_over_screen.hide()
	message_label.hide()
	message_timer.timeout.connect(message_label.hide)
	action_button.pressed.connect(action_pressed.emit)
	retry_button.pressed.connect(_on_game_over_choice.bind(retry_pressed))
	back_to_menu_button.pressed.connect(_on_game_over_choice.bind(menu_pressed))
	set_has_key(false)


## Muestra un corazón por cada vida máxima: llenos los que quedan y apagados
## los perdidos, igual que la llave.
func set_lives(lives: int, max_lives: int) -> void:
	var count := maxi(lives, max_lives)
	while lives_hearts.get_child_count() < count:
		lives_hearts.add_child(_make_life_icon())
	while lives_hearts.get_child_count() > count:
		var extra := lives_hearts.get_child(lives_hearts.get_child_count() - 1)
		lives_hearts.remove_child(extra)
		extra.queue_free()
	for i in count:
		var icon: TextureRect = lives_hearts.get_child(i)
		icon.modulate = Color.WHITE if i < lives else Color(1, 1, 1, 0.25)


func _make_life_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = Heart.get_texture()
	icon.custom_minimum_size = LIFE_ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


## Muestra la llave opaca si el jugador la tiene y apagada si no.
func set_has_key(has_key: bool) -> void:
	key_icon.modulate = Color.WHITE if has_key else Color(1, 1, 1, 0.25)


func set_kills(killed: int, total: int) -> void:
	kills_label.text = "Enemigos: %d/%d" % [killed, total]


func set_coins(coins: int) -> void:
	coins_label.text = str(coins)


## Muestra la barra de vida de boss (nombre y vida) mientras esté vivo y en
## alerta. La barra se actualiza sola.
func track_boss(boss: BossBase) -> void:
	boss_bar.track(boss)


## Muestra un mensaje temporal en la parte inferior de la pantalla.
func show_message(text: String) -> void:
	message_label.text = text
	message_label.show()
	message_timer.start()


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
