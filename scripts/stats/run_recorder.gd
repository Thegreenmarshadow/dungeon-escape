@tool
class_name RunRecorder
extends RefCounted
## Convierte lo que pasa en una partida en eventos de estadísticas y los entrega
## a un StatsSink. Es lógica pura: no conoce nodos, señales ni el estado global
## (RunTracker se los pasa), así se prueba sin red y sin escenas.
##
## Ciclo de una partida: start_run -> (start_level -> eventos ->
## complete_level)* -> record_death o finish_run. Los eventos fuera de un nivel
## activo se ignoran, salvo las compras: la tienda está en la pantalla de nivel
## superado, entre un nivel y el siguiente.
##
## Cada evento lleva seq (orden dentro de la partida, desde 0), type, level,
## t_run_s (segundos jugados desde el inicio, sin contar las pausas), payload y
## at (fecha UTC). Tipos que se envían hoy:
##   level_started   {lives, enemies_total}
##   enemy_killed    {enemy}            nombre de la escena: Skeleton, Vampire…
##   enemy_dodged    {enemy}            un enemigo esquivó un golpe del jugador
##   damage_taken    {amount, lives, source}  vidas perdidas, las que quedan y
##                                      quién lastimó (Player.damaged: tipo de
##                                      enemigo, "spikes", id del jefe...)
##   heart_picked    {amount, lives}    vidas recuperadas (solo curan los corazones)
##   key_picked      {}
##   coin_picked     {amount}           monedas recogidas
##   item_bought     {item, price}      compra en la tienda (damage, life o el id
##                                      de un arma: spear, dagger); lleva
##                                      el nivel recién superado
##   level_completed {duration_s, kills, enemies_total, score}
##   player_died     {score, cause}     cause: source del último daño
##   weapon_changed  {weapon}           id del arma nueva (pickup, demo)
##   player_respawned {lives}           la demo revivió al jugador en un punto
##                                      de control (no termina la partida)
##   run_quit        {score}            la partida terminó sin morir
## El servidor acepta cualquier otro tipo, así se pueden sumar más adelante.

const MODE_NORMAL := "normal"
const MODE_TEST := "test"
## La demo hecha a mano (Game.demo_mode). El servidor la deja fuera de la tabla
## de puntajes.
const MODE_DEMO := "demo"
const OUTCOME_DIED := "died"
const OUTCOME_QUIT := "quit"

const EVENT_LEVEL_STARTED := "level_started"
const EVENT_ENEMY_KILLED := "enemy_killed"
const EVENT_ENEMY_DODGED := "enemy_dodged"
const EVENT_DAMAGE_TAKEN := "damage_taken"
const EVENT_HEART_PICKED := "heart_picked"
const EVENT_KEY_PICKED := "key_picked"
const EVENT_COIN_PICKED := "coin_picked"
const EVENT_ITEM_BOUGHT := "item_bought"
const EVENT_LEVEL_COMPLETED := "level_completed"
const EVENT_PLAYER_DIED := "player_died"
const EVENT_RUN_QUIT := "run_quit"
const EVENT_PLAYER_RESPAWNED := "player_respawned"
const EVENT_WEAPON_CHANGED := "weapon_changed"

var sink: StatsSink
## Partida en curso; vacío si no hay ninguna.
var run_id := ""

var _seq := 0
var _run_time := 0.0
var _level_time := 0.0
var _level := 0
var _level_reached := 0
var _level_active := false
var _lives := 0
var _level_kills := 0
var _enemies_total := 0
# Últimos totales conocidos de la partida, para cerrarla sin el estado global.
var _score := 0
var _kills := 0


func _init(p_sink: StatsSink) -> void:
	sink = p_sink


func is_running() -> bool:
	return not run_id.is_empty()


func is_level_active() -> bool:
	return _level_active


## Id nuevo de partida: 32 caracteres hexadecimales aleatorios.
static func new_run_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


## Nombre del tipo de enemigo: el de su escena (Skeleton.tscn -> "Skeleton") o,
## si no viene de una escena, el del nodo.
static func enemy_kind(enemy: Node) -> String:
	if not enemy.scene_file_path.is_empty():
		return enemy.scene_file_path.get_file().get_basename()
	return String(enemy.name)


## Empieza una partida. Si había otra en curso, la cierra como abandonada.
func start_run(new_run_id: String, player_name: String, mode: String, run_seed: int, start_level: int) -> void:
	if is_running():
		finish_run(OUTCOME_QUIT)
	run_id = new_run_id
	_seq = 0
	_run_time = 0.0
	_level = 0
	_level_reached = start_level
	_level_active = false
	_score = 0
	_kills = 0
	sink.start_run({
		"id": run_id,
		"player_name": player_name,
		"mode": mode,
		"run_seed": run_seed,
		"start_level": start_level,
		"started_at": _now(),
	})


func start_level(level: int, lives: int, enemies_total: int) -> void:
	if not is_running():
		return
	_level = level
	_level_reached = maxi(_level_reached, level)
	_level_active = true
	_level_time = 0.0
	_lives = lives
	_level_kills = 0
	_enemies_total = enemies_total
	_emit(EVENT_LEVEL_STARTED, {"lives": lives, "enemies_total": enemies_total})


## Suma tiempo jugado. Solo cuenta mientras hay un nivel activo.
func advance(delta: float) -> void:
	if _level_active:
		_run_time += delta
		_level_time += delta


## total_kills y score son los totales de la partida después de esta muerte.
func record_kill(kind: String, total_kills: int, score: int) -> void:
	if not _level_active:
		return
	_level_kills += 1
	_kills = total_kills
	_score = score
	_emit(EVENT_ENEMY_KILLED, {"enemy": kind})


## Un enemigo de tipo kind esquivó un golpe del jugador.
func record_dodge(kind: String) -> void:
	if _level_active:
		_emit(EVENT_ENEMY_DODGED, {"enemy": kind})


## Recibe cada cambio de vidas del jugador: una baja es daño y una suba es un
## corazón recogido (los corazones son lo único que cura). source es quién hizo
## el daño (Player.last_damage_source); vacío si no se sabe.
func record_lives(lives: int, source: String = "") -> void:
	if not _level_active:
		return
	if lives < _lives:
		_emit(EVENT_DAMAGE_TAKEN, {"amount": _lives - lives, "lives": lives, "source": source})
	elif lives > _lives:
		_emit(EVENT_HEART_PICKED, {"amount": lives - _lives, "lives": lives})
	_lives = lives


func record_key() -> void:
	if _level_active:
		_emit(EVENT_KEY_PICKED, {})


func record_coins(amount: int) -> void:
	if _level_active and amount > 0:
		_emit(EVENT_COIN_PICKED, {"amount": amount})


## Compra en la tienda. Solo pide una partida en curso porque se compra con el
## nivel ya superado; el evento lleva el número de ese nivel.
func record_purchase(item: String, price: int) -> void:
	if is_running():
		_emit(EVENT_ITEM_BOUGHT, {"item": item, "price": price})


## score es el puntaje total ya con los puntos del nivel superado.
func complete_level(score: int) -> void:
	if not _level_active:
		return
	_score = score
	_emit(EVENT_LEVEL_COMPLETED, {
		"duration_s": _tenths(_level_time),
		"kills": _level_kills,
		"enemies_total": _enemies_total,
		"score": score,
	})
	_level_active = false


## La muerte del jugador termina la partida. cause es quién hizo el último
## daño (Player.last_damage_source).
func record_death(score: int, total_kills: int, cause: String = "") -> void:
	if not _level_active:
		return
	_score = score
	_kills = total_kills
	_emit(EVENT_PLAYER_DIED, {"score": score, "cause": cause})
	finish_run(OUTCOME_DIED)


## El jugador cambió de arma (Player.weapon_changed) durante el nivel.
func record_weapon(weapon: String) -> void:
	if _level_active:
		_emit(EVENT_WEAPON_CHANGED, {"weapon": weapon})


## La demo revivió al jugador con lives vidas: la partida sigue. Las vidas
## recuperadas no cuentan como corazones.
func record_respawn(lives: int) -> void:
	if not _level_active:
		return
	_lives = lives
	_emit(EVENT_PLAYER_RESPAWNED, {"lives": lives})


## Cierra la partida en curso. score y total_kills negativos usan los últimos
## totales conocidos.
func finish_run(outcome: String, score: int = -1, total_kills: int = -1) -> void:
	if not is_running():
		return
	if score >= 0:
		_score = score
	if total_kills >= 0:
		_kills = total_kills
	if outcome == OUTCOME_QUIT:
		_emit(EVENT_RUN_QUIT, {"score": _score})
	sink.finish_run(run_id, {
		"outcome": outcome,
		"score": _score,
		"level_reached": maxi(_level_reached, 1),
		"enemies_killed": _kills,
		"duration_s": _tenths(_run_time),
		"ended_at": _now(),
	})
	run_id = ""
	_level_active = false


func _emit(type: String, payload: Dictionary) -> void:
	sink.add_event(run_id, {
		"seq": _seq,
		"type": type,
		"level": _level if _level > 0 else null,
		"t_run_s": _tenths(_run_time),
		"payload": payload,
		"at": _now(),
	})
	_seq += 1


## Redondea a décimas sin el error de snappedf (35 * 0.1 = 3.5000000000000004).
static func _tenths(value: float) -> float:
	return roundf(value * 10.0) / 10.0


static func _now() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"
