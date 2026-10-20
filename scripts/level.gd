extends Node2D
## Coordina el nivel: conecta al jugador, la puerta y los enemigos con la
## interfaz y maneja el fin del nivel (superado o derrota).

## Música base del nivel y la que la reemplaza mientras hay enemigos en alerta.
const EXPLORATION_MUSIC := preload("res://assets/music/dungeon_exploration.ogg")
const DANGER_MUSIC := preload("res://assets/music/dungeon_danger.ogg")
## Segundos que sigue la música de peligro después de que el último enemigo
## deja de estar en alerta, para que no cambie de pista a cada rato.
const DANGER_HOLD_TIME := 4.0
## Duración del fundido entre las dos pistas, en segundos.
const MUSIC_FADE_TIME := 1.5
## Celdas de margen alrededor del mapa generado que la cámara puede mostrar,
## para no ver el borde exacto de las paredes.
const GENERATED_CAMERA_MARGIN := 3
const HEART_SCENE := preload("res://scenes/Heart.tscn")
const COIN_SCENE := preload("res://scenes/Coin.tscn")
## Monedas sueltas (de valor 1) que se reparten en cada mapa generado.
const LOOSE_COINS_PER_LEVEL := 1
## Desplazamiento de la moneda soltada respecto del enemigo, para que no quede
## tapada por un corazón soltado en el mismo lugar.
const COIN_DROP_OFFSET := Vector2(6, 2)

@onready var dungeon: TileMapLayer = $Dungeon
@onready var player: CharacterBody2D = $Player
@onready var exit_door: Area2D = $ExitDoor
@onready var hud: CanvasLayer = $HUD

var _enemies_total: int = 0
var _enemies_killed: int = 0
var _danger_left: float = 0.0


func _ready() -> void:
	Music.play_track(EXPLORATION_MUSIC)

	# El nivel 1 es el mapa hecho a mano de esta escena; del 2 en adelante se
	# reemplaza por uno generado. Debe ocurrir antes de contar a los enemigos.
	var camera_margin := 0
	if Game.current_level >= LevelGenerator.FIRST_GENERATED_LEVEL:
		_build_generated_level()
		camera_margin = GENERATED_CAMERA_MARGIN
	_fit_camera_to_map(camera_margin)

	# Las vidas vienen del estado global, así se conservan entre niveles.
	# Se asignan acá porque el jugador ya ejecutó su _ready: Godot inicializa
	# a los hijos antes que al padre.
	player.lives = Game.lives
	# Igual con las mejoras compradas en la tienda.
	player.damage_bonus = Game.damage_bonus
	player.equip_weapon(WeaponData.load_by_id(Game.weapon_id))

	# Estado inicial de la interfaz.
	hud.set_lives(player.lives, player.max_lives)
	hud.set_has_key(player.has_key)
	hud.set_coins(Game.coins)

	# Cada enemigo se agrega al grupo "enemies" en EnemyBase._ready. La vida se
	# escala acá, después de ese _ready, según el nivel (×1 en el nivel 1).
	var enemies := get_tree().get_nodes_in_group("enemies")
	_enemies_total = enemies.size()
	var health_scale := LevelGenerator.enemy_health_scale(Game.current_level)
	for enemy in enemies:
		enemy.apply_health_scale(health_scale)
		enemy.died.connect(_on_enemy_died)
		enemy.died.connect(_try_drop_heart)
		enemy.died.connect(_try_drop_coin)
	hud.set_kills(_enemies_killed, _enemies_total)

	player.lives_changed.connect(_on_lives_changed)
	player.key_collected.connect(hud.set_has_key.bind(true))
	player.coins_collected.connect(Game.add_coins)
	# La conexión se borra sola cuando la HUD se libera al cambiar de escena.
	Game.coins_changed.connect(hud.set_coins)
	hud.buy_pressed.connect(_on_buy_pressed)
	player.died.connect(_on_player_died)
	exit_door.player_escaped.connect(_on_player_escaped)
	exit_door.locked_touched.connect(hud.show_message.bind("Necesitas la llave"))
	hud.show_message("Nivel %d" % Game.current_level)
	# Modo prueba: la sonda solo observa señales; el nivel no cambia.
	if Game.test_mode: add_child(DifficultyProbe.new())


## Cambia a la música de peligro mientras algún enemigo esté en alerta y vuelve
## a la de exploración cuando pasa un rato sin ninguno. No corre con el árbol
## pausado, así que las pantallas finales conservan la pista que sonaba.
func _process(delta: float) -> void:
	_danger_left = maxf(_danger_left - delta, 0.0)
	if _any_enemy_alerted():
		_danger_left = DANGER_HOLD_TIME
	Music.play_track(DANGER_MUSIC if _danger_left > 0.0 else EXPLORATION_MUSIC, MUSIC_FADE_TIME)


func _any_enemy_alerted() -> bool:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.is_alerted():
			return true
	return false


## Genera el mapa de Game.current_level (determinista con Game.run_seed) y lo
## dibuja en esta escena.
func _build_generated_level() -> void:
	var layout := LevelGenerator.generate(Game.current_level, Game.run_seed)
	LevelBuilder.new().build(self, layout)
	_scatter_loose_coins(layout)
	print("Mapa generado, %s (semilla de partida %d)" % [layout.summary(), Game.run_seed])


## Reparte monedas sueltas por las salas del mapa generado. Las celdas salen de
## Game.run_seed y el nivel, así el mismo mapa tiene siempre las mismas monedas;
## no cambian el mapa ni lo que coloca el generador.
func _scatter_loose_coins(layout: LevelGenerator.Layout) -> void:
	var seed_value := hash([Game.run_seed, Game.current_level, "monedas"])
	for cell in Coin.scatter_cells(layout, seed_value, LOOSE_COINS_PER_LEVEL):
		_spawn_coin(to_local(dungeon.to_global(dungeon.map_to_local(cell))),
				Coin.scaled_value(1, Game.level_scale()))


func _on_lives_changed(lives: int) -> void:
	Game.lives = lives
	hud.set_lives(lives, player.max_lives)


func _on_enemy_died(_enemy: EnemyBase) -> void:
	# El conteo local es del nivel (para el HUD); el global suma puntos.
	_enemies_killed += 1
	Game.register_kill()
	hud.set_kills(_enemies_killed, _enemies_total)


## Según la probabilidad del enemigo, deja un corazón donde murió. El enemigo
## no sabe nada de los corazones: solo expone heart_drop_chance.
func _try_drop_heart(enemy: EnemyBase) -> void:
	if not Heart.should_drop(enemy.heart_drop_chance, randf()):
		return
	# Diferido: la muerte ocurre durante un callback de física, donde no se
	# pueden agregar áreas al mundo.
	_spawn_heart.call_deferred(to_local(enemy.global_position))


func _spawn_heart(at: Vector2) -> void:
	var heart: Node2D = HEART_SCENE.instantiate()
	heart.position = at
	add_child(heart)


## Según la probabilidad del enemigo, deja una moneda donde murió, con un valor
## sorteado en su rango. Igual que con los corazones, el enemigo solo expone los
## datos (coin_drop_chance, coin_min_value y coin_max_value). El valor sorteado
## se multiplica por la escala del nivel, igual que la vida de los enemigos.
func _try_drop_coin(enemy: EnemyBase) -> void:
	if not Coin.should_drop(enemy.coin_drop_chance, randf()):
		return
	var value := Coin.value_for(enemy.coin_min_value, enemy.coin_max_value, randf())
	value = Coin.scaled_value(value, Game.level_scale())
	# Diferido por el mismo motivo que los corazones.
	_spawn_coin.call_deferred(to_local(enemy.global_position) + COIN_DROP_OFFSET, value)


func _spawn_coin(at: Vector2, value: int) -> void:
	var coin: Coin = COIN_SCENE.instantiate()
	coin.position = at
	coin.value = value
	add_child(coin)


func _on_player_died() -> void:
	# Los niveles no terminan nunca: la derrota es el único fin de una partida,
	# así que acá se registra en la tabla de puntajes. El jugador emite died
	# una sola vez (take_damage se ignora con 0 vidas). Las partidas del modo
	# prueba no se registran: empiezan en cualquier nivel y darían récords falsos.
	var run := ScoreBoard.unrecorded_run() if Game.test_mode \
			else ScoreBoard.record_run(Game.score, Game.current_level, Game.enemies_killed)
	# Conexiones normales (no de un solo uso): la HUD emite una sola de las dos
	# señales y desactiva los botones, y el cambio de escena libera la HUD.
	hud.retry_pressed.connect(Game.retry)
	hud.menu_pressed.connect(Game.go_to_menu)
	hud.show_game_over(Game.current_level, Game.enemies_killed, Game.score,
			run["is_new_record"], _record_text(run))
	Sfx.play(&"game_over")
	get_tree().paused = true


## Línea de récord de Game Over cuando la partida no superó el récord: el
## puesto alcanzado (si entró en la tabla) y el mejor puntaje. Vacía si todavía
## no hay ningún récord, para no mostrar "Récord: 0".
func _record_text(run: Dictionary) -> String:
	var best: int = run["previous_best"]
	if best <= 0:
		best = ScoreBoard.best_score(run["board"])
	if best <= 0:
		return ""
	var record := "Récord: %d" % best
	if run["recorded"]:
		return "Puesto #%d · %s" % [run["rank"], record]
	return record


func _on_player_escaped() -> void:
	var completed_level := Game.current_level
	Game.complete_level()
	var stats := "Nivel %d · Enemigos eliminados: %d/%d\nPuntos: %d" % [
		completed_level, _enemies_killed, _enemies_total, Game.score]
	Sfx.play(&"level_complete")
	_end_level("¡Nivel superado!", stats, "Siguiente nivel", Game.start_level)
	# Antes de seguir se pueden gastar las monedas.
	_refresh_shop()


## Compra pedida desde la tienda de la HUD. Game aplica las reglas de Shop; acá
## solo se actualiza lo que se ve. La vida comprada queda en Game.lives y el
## próximo nivel se la da al jugador.
func _on_buy_pressed(item: StringName) -> void:
	if not Game.buy(item, player.max_lives):
		return
	hud.set_lives(Game.lives, player.max_lives)
	_refresh_shop()


## Muestra (o actualiza) la tienda con el precio y el estado de cada artículo.
func _refresh_shop() -> void:
	var offers: Array[Dictionary] = []
	for item in Shop.ITEMS:
		var times := Game.times_bought(item)
		offers.append({
			"item": item,
			"price": Shop.price_for(item, times, Game.level_scale()),
			"available": Shop.is_available(item, times, Game.lives, player.max_lives),
			"affordable": Game.can_buy(item, player.max_lives),
		})
	hud.show_shop(Game.coins, offers)


## Pausa el juego y muestra la pantalla de nivel superado. El botón de la
## pantalla ejecuta action. La interfaz sigue funcionando en pausa.
func _end_level(title: String, details: String, action_text: String, action: Callable) -> void:
	hud.show_end_screen(title, details, action_text)
	hud.action_pressed.connect(action, CONNECT_ONE_SHOT)
	get_tree().paused = true


## Limita la cámara del jugador al área ocupada por el mapa, para que no muestre
## el vacío fuera de los bordes. Se calcula desde los tiles, así se adapta
## automáticamente si el mapa cambia de tamaño. margin_tiles agranda esa área.
func _fit_camera_to_map(margin_tiles: int = 0) -> void:
	var used := dungeon.get_used_rect().grow(margin_tiles)
	var tile_size := dungeon.tile_set.tile_size
	var camera: Camera2D = player.get_node("Camera2D")
	camera.limit_left = used.position.x * tile_size.x
	camera.limit_top = used.position.y * tile_size.y
	camera.limit_right = used.end.x * tile_size.x
	camera.limit_bottom = used.end.y * tile_size.y
