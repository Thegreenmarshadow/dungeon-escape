extends Node
## Estado global de la partida. Se registra como Autoload ("Game") para que
## sobreviva a los cambios de escena: el nivel, el menú y las pantallas finales
## leen y escriben acá en lugar de guardar estos datos ellos mismos.

## Se emite al empezar una partida nueva (normal o de prueba), con el estado ya
## reiniciado. Lo escucha RunTracker para registrar la partida.
signal run_started
## Se emite cada vez que cambian las monedas (al recoger o al comprar).
signal coins_changed(coins: int)
## Se emite al volver al menú, antes de cambiar de escena y de reiniciar el
## estado de la demo: RunTracker cierra ahí la partida con sus totales.
signal returning_to_menu
## Se emite al comprar un artículo de la tienda (ver Shop), con lo que se pagó.
## Lo escucha RunTracker para registrar la compra.
signal item_bought(item: StringName, price: int)

## Vida con la que empieza cada partida nueva, en medios corazones (ver
## Heart.HALF_HEARTS_PER_HEART): 3 corazones.
const STARTING_HEALTH := 3 * Heart.HALF_HEARTS_PER_HEART
## Puntos por cada enemigo eliminado.
const POINTS_PER_KILL := 10
## Puntos por cada nivel superado.
const POINTS_PER_LEVEL := 100

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const LEVEL_SCENE := "res://scenes/Level.tscn"
const DIFFICULTY_REPORT_SCENE := "res://scenes/DifficultyReport.tscn"
const SANDBOX_SCENE := "res://scenes/Sandbox.tscn"
const DEMO_SCENE := "res://scenes/DemoLevel.tscn"
const PROFILE_SELECT_SCENE := "res://scenes/ProfileSelect.tscn"
const SETTINGS_SCENE := "res://scenes/SettingsMenu.tscn"
## Vida de la demo, en medios corazones: 5 corazones, más que en una partida
## normal, para que quien prueba el juego por primera vez no tenga que
## empezar de nuevo.
const DEMO_HEALTH := 5 * Heart.HALF_HEARTS_PER_HEART

## Nivel que se está jugando, empezando en 1.
var current_level: int = 1
## Vida restante del jugador, en medios corazones; se conserva entre niveles.
var health: int = STARTING_HEALTH
## Enemigos eliminados en toda la partida.
var enemies_killed: int = 0
var score: int = 0
## Monedas para gastar en la tienda; se conservan entre niveles.
var coins: int = 0
## Daño extra de cada golpe, comprado en la tienda. El nivel se lo asigna al
## jugador al empezar.
var damage_bonus: int = 0
## Arma equipada (id de WeaponData). Se compra en la tienda, se conserva entre
## niveles y el nivel se la da al jugador al empezar.
var weapon_id: StringName = WeaponData.STARTING_ID
## Semilla de la partida. Junto con el número de nivel determina el mapa que
## se genera del nivel 2 en adelante, así un nivel se puede reproducir.
var run_seed: int = 0
## true en las partidas iniciadas desde el modo prueba. Solo hace que el nivel
## agregue la sonda de dificultad (DifficultyProbe); el juego no cambia.
var test_mode := false
## Nivel en el que empezó la partida de prueba actual. "Reintentar" vuelve a
## empezar desde acá.
var test_start_level: int = 1
## true mientras se juega la demo (el nivel hecho a mano para quien no conoce
## el juego). No guarda puntajes y RunTracker la registra con modo "demo". Nada
## de la demo pasa a una partida normal: new_game() lo reinicia todo.
var demo_mode := false
## Id de la partida para la telemetría y los perfiles (32 caracteres
## hexadecimales). Lo crea new_game(); "Continuar" recupera el guardado, así
## los niveles de una partida retomada quedan en la misma carpeta.
var run_id: String = ""


## Reinicia todo el estado para empezar una partida desde el nivel 1.
func new_game() -> void:
	current_level = 1
	health = STARTING_HEALTH
	enemies_killed = 0
	score = 0
	coins = 0
	damage_bonus = 0
	weapon_id = WeaponData.STARTING_ID
	run_seed = randi()
	test_mode = false
	demo_mode = false
	# Crypto y no randi(): no consume el generador global del juego.
	run_id = RunRecorder.new_run_id()


func register_kill() -> void:
	enemies_killed += 1
	score += POINTS_PER_KILL


## Suma monedas recogidas. Ignora cantidades no positivas.
func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	coins_changed.emit(coins)


## Multiplicador de la vida de los enemigos del nivel actual. Las monedas y el
## precio de la vida de la tienda siguen esta misma escala.
func level_scale() -> float:
	return LevelGenerator.enemy_health_scale(current_level)


## Veces que se compró item en esta partida. La vida no necesita contarse: su
## precio no depende de cuántas se compraron. Un arma cuenta 1 si es la
## equipada, así la tienda no la vuelve a ofrecer.
func times_bought(item: StringName) -> int:
	if Shop.is_weapon(item):
		return 1 if item == weapon_id else 0
	return damage_bonus if item == Shop.ITEM_DAMAGE else 0


## true si ahora se puede comprar item. max_health es la vida máxima del
## jugador (medios corazones), que Game no conoce.
func can_buy(item: StringName, max_health: int) -> bool:
	return Shop.can_buy(item, coins, times_bought(item), health, max_health, level_scale())


## Compra item si las reglas de Shop lo permiten: descuenta el precio y aplica
## la mejora (más daño, un corazón más de vida sin pasar de max_health o el
## arma nueva). Devuelve false sin cambiar nada si no se puede comprar.
func buy(item: StringName, max_health: int) -> bool:
	if not can_buy(item, max_health):
		return false
	var price := Shop.price_for(item, times_bought(item), level_scale())
	coins -= price
	match item:
		Shop.ITEM_DAMAGE:
			damage_bonus += 1
		Shop.ITEM_LIFE:
			health = mini(health + Shop.LIFE_HEAL, max_health)
		_:
			if Shop.is_weapon(item):
				weapon_id = item
	coins_changed.emit(coins)
	item_bought.emit(item, price)
	return true


## Suma los puntos del nivel superado y avanza al siguiente.
func complete_level() -> void:
	score += POINTS_PER_LEVEL
	current_level += 1


## Empieza una partida nueva desde el nivel 1.
func start_new_game() -> void:
	new_game()
	run_started.emit()
	start_level()


## "Continuar": retoma la partida guardada de un perfil (ver
## ProfileStore.SAVE_KEYS) desde el principio del nivel en el que estaba, con
## la vida, el arma, las monedas, las mejoras y la semilla de ese momento. Una
## partida guardada antes de los medios corazones (vidas enteras) se
## convierte con ProfileStore.saved_health.
func continue_run(save: Dictionary) -> void:
	new_game()
	current_level = maxi(int(save.get("level", 1)), 1)
	health = ProfileStore.saved_health(save, STARTING_HEALTH)
	coins = maxi(int(save.get("coins", 0)), 0)
	damage_bonus = maxi(int(save.get("damage_bonus", 0)), 0)
	var saved_weapon := StringName(str(save.get("weapon_id", WeaponData.STARTING_ID)))
	if WeaponData.load_by_id(saved_weapon) != null:
		weapon_id = saved_weapon
	run_seed = int(save.get("run_seed", run_seed))
	score = maxi(int(save.get("score", 0)), 0)
	enemies_killed = maxi(int(save.get("enemies_killed", 0)), 0)
	if not str(save.get("run_id", "")).is_empty():
		run_id = str(save["run_id"])
	run_started.emit()
	start_level()


## Empieza una partida de prueba directamente en el nivel dado, con la sonda
## de dificultad activa. Los niveles siguientes también son de prueba.
func start_test_run(level: int) -> void:
	new_game()
	current_level = maxi(level, 1)
	test_mode = true
	test_start_level = current_level
	run_started.emit()
	start_level()


## Empieza la demo desde su primera sala, con DEMO_HEALTH de vida y la espada.
## Es un nivel aparte (DEMO_SCENE): current_level queda en 1, así los enemigos
## tienen su vida base.
func start_demo() -> void:
	new_game()
	demo_mode = true
	health = DEMO_HEALTH
	run_started.emit()
	_change_scene(DEMO_SCENE)


## "Reintentar" tras perder: repite la misma clase de partida. Una partida de
## prueba vuelve a empezar en su nivel inicial; la demo, desde su primera sala;
## una normal, desde el nivel 1.
func retry() -> void:
	if demo_mode:
		start_demo()
	elif test_mode:
		start_test_run(test_start_level)
	else:
		start_new_game()


## Carga el nivel actual. Siempre es la escena Level: el nivel 1 usa el mapa
## hecho a mano y del 2 en adelante Level genera el mapa con current_level y
## run_seed.
func start_level() -> void:
	_change_scene(LEVEL_SCENE)


## Vuelve al menú. Al salir de la demo se reinicia todo el estado (vida, arma,
## monedas...), así nada de la demo llega a la próxima partida.
func go_to_menu() -> void:
	returning_to_menu.emit()
	if demo_mode:
		new_game()
	_change_scene(MENU_SCENE)


## Abre la pantalla del modo prueba con el informe de la curva de dificultad.
func go_to_difficulty_report() -> void:
	_change_scene(DIFFICULTY_REPORT_SCENE)


## Abre la pantalla de perfiles (elegir, crear o borrar).
func go_to_profile_select() -> void:
	_change_scene(PROFILE_SELECT_SCENE)


## Abre los ajustes (telemetría).
func go_to_settings() -> void:
	_change_scene(SETTINGS_SCENE)


## Abre la zona de pruebas (solo en builds de depuración). No empieza ninguna
## partida ni toca el estado de acá: nada de lo que pase ahí cuenta.
func go_to_sandbox() -> void:
	_change_scene(SANDBOX_SCENE)


func _change_scene(path: String) -> void:
	# Las pantallas finales pausan el juego; la escena nueva debe arrancar
	# sin pausa.
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
