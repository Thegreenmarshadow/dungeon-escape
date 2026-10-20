extends Node
## Registra las partidas para el servidor de estadísticas. Se registra como
## Autoload ("RunTracker", después de Game) y no cambia nada del juego: solo
## escucha señales que ya existen y le pasa los datos a un RunRecorder, que los
## envía con un HttpStatsSink (cola en disco, nunca bloquea).
##
## Señales que observa:
##   - Game.run_started: partida nueva (normal, de prueba o la demo, según
##     Game.test_mode y Game.demo_mode).
##   - Game.item_bought: compra en la tienda entre niveles.
##   - Game.returning_to_menu: volver al menú cierra la partida como abandonada
##     ("quit") antes de que Game reinicie el estado de la demo.
##   - SceneTree.node_added: carga de un nivel o de otra pantalla. Una pantalla
##     que no es un nivel (menú, modo prueba) con una partida en curso la cierra
##     como abandonada ("quit").
##   - En cada nivel: Player.lives_changed, Player.key_collected,
##     Player.coins_collected, Player.died, Player.revived (puntos de control
##     de la demo), Player.weapon_changed, Door.player_escaped, EnemyBase.died y EnemyBase.dodged.
##     La demo (Game.DEMO_SCENE) cuenta como nivel.
## Cerrar la ventana a mitad de partida también la cierra como abandonada.
##
## Sin class_name a propósito: chocaría con el nombre del Autoload.

var sink: StatsSink
var recorder: RunRecorder


func _ready() -> void:
	sink = HttpStatsSink.new()
	sink.name = "HttpStatsSink"
	add_child(sink)
	recorder = RunRecorder.new(sink)
	Game.run_started.connect(_on_run_started)
	Game.item_bought.connect(_on_item_bought)
	Game.returning_to_menu.connect(_quit_current_run)
	get_tree().node_added.connect(_on_node_added)


## Con el árbol en pausa (pantallas finales) no corre: el tiempo de la partida
## solo cuenta mientras se juega.
func _process(delta: float) -> void:
	recorder.advance(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_current_run()


func _on_run_started() -> void:
	recorder.start_run(RunRecorder.new_run_id(), PlayerProfile.current_name(), current_mode(),
			Game.run_seed, Game.current_level)


## Modo con el que se registra la partida que empieza según Game.
func current_mode() -> String:
	if Game.demo_mode:
		return RunRecorder.MODE_DEMO
	return RunRecorder.MODE_TEST if Game.test_mode else RunRecorder.MODE_NORMAL


## Solo interesan las escenas principales (hijas directas de la raíz que vienen
## de un archivo .tscn); los Autoload de script no tienen scene_file_path.
func _on_node_added(node: Node) -> void:
	if node.get_parent() != get_tree().root or node.scene_file_path.is_empty():
		return
	if node.scene_file_path in [Game.LEVEL_SCENE, Game.DEMO_SCENE]:
		# Hasta su _ready el nivel no generó el mapa ni hay enemigos en el grupo.
		node.ready.connect(_on_level_ready.bind(node), CONNECT_ONE_SHOT)
	else:
		_quit_current_run()


func _on_level_ready(level: Node) -> void:
	var player: Node = level.get_node("Player")
	var enemies: Array[Node] = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if level.is_ancestor_of(enemy):
			enemies.append(enemy)
	recorder.start_level(Game.current_level, player.lives, enemies.size())

	# El nivel conectó sus señales antes (en su _ready), así que cuando llegan
	# acá Game ya tiene el puntaje y las muertes actualizados.
	# take_damage guarda last_damage_source antes de emitir lives_changed.
	player.lives_changed.connect(func(lives: int) -> void:
		recorder.record_lives(lives, String(player.last_damage_source)))
	player.key_collected.connect(recorder.record_key)
	player.coins_collected.connect(recorder.record_coins)
	player.died.connect(func() -> void:
		recorder.record_death(Game.score, Game.enemies_killed, String(player.last_damage_source)))
	player.weapon_changed.connect(func(weapon_id: StringName) -> void: recorder.record_weapon(String(weapon_id)))
	player.revived.connect(recorder.record_respawn)
	level.get_node("ExitDoor").player_escaped.connect(func() -> void: recorder.complete_level(Game.score))
	for enemy in enemies:
		enemy.died.connect(_on_enemy_died)
		enemy.dodged.connect(_on_enemy_dodged)


func _on_enemy_died(enemy: EnemyBase) -> void:
	recorder.record_kill(RunRecorder.enemy_kind(enemy), Game.enemies_killed, Game.score)


func _on_enemy_dodged(enemy: EnemyBase) -> void:
	recorder.record_dodge(RunRecorder.enemy_kind(enemy))


func _on_item_bought(item: StringName, price: int) -> void:
	recorder.record_purchase(String(item), price)


func _quit_current_run() -> void:
	if recorder.is_running():
		recorder.finish_run(RunRecorder.OUTCOME_QUIT, Game.score, Game.enemies_killed)
