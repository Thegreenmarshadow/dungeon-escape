extends CharacterBody2D
## Jugador controlable con movimiento en 8 direcciones, vida, invulnerabilidad
## y ataque con el arma equipada (WeaponData). El arma se ve en WeaponPivot,
## que gira hacia donde mira el jugador y lleva la hitbox y la estela del golpe.
##
## La vida se cuenta en medios corazones (Heart.HALF_HEARTS_PER_HEART por
## corazón): max_health 6 son los 3 corazones de la HUD, un golpe base de
## enemigo quita 2 (un corazón) y un corazón del suelo cura 2.

## Se emite cada vez que cambia la vida, en medios corazones.
signal health_changed(health: int)
## Se emite al recoger la llave.
signal key_collected
## Se emite al recoger monedas, con cuántas suma.
signal coins_collected(amount: int)
## Se emite cuando el jugador se queda sin vida.
signal died
## Se emite en lugar de died cuando el jugador se queda sin vida con
## revives_on_death activo: el nivel decide dónde lo revive (revive()).
signal knocked_out
## Se emite al revivir, con la vida (medios corazones) con la que vuelve.
## revive() también lo teletransporta: la telemetría corta ahí la línea del
## recorrido.
signal revived(health: int)
## Se emite al recibir daño, con los medios corazones perdidos y quién lo hizo (source):
## el tipo de enemigo (RunRecorder.enemy_kind), &"spikes", el id del jefe para
## sus efectos de suelo... Vacío si quien llamó no lo dijo. Solo lo observan
## las estadísticas; el juego no depende de esta señal.
signal damaged(amount: int, source: StringName)
## Se emite una vez por golpe, al terminar su ventana activa: hit es true si
## tocó algo golpeable (enemigo o proyectil). Solo observa.
signal attacked(hit: bool)
## Se emite cuando equip_weapon cambia el arma por otra distinta, con su id.
signal weapon_changed(weapon_id: StringName)

## Velocidad de movimiento en píxeles por segundo.
@export var speed: float = 80.0
## Vida máxima, en medios corazones (6 = 3 corazones). Con ella empieza.
@export var max_health: int = 6
## Segundos de invulnerabilidad después de recibir daño.
@export var invulnerability_time: float = 1.5
## Parpadeos por segundo mientras dura la invulnerabilidad.
@export var blink_rate: float = 10.0
## Píxeles que retrocede al recibir un golpe de un enemigo.
@export var knockback_distance: float = 14.0

@export_group("Ataque")
## Arma equipada: de ella salen el daño, la hitbox, los tiempos y el retroceso
## de cada golpe. El nivel la reemplaza por la de la partida (Game.weapon_id).
@export var weapon: WeaponData = preload("res://assets/weapons/sword/sword.tres")
## Píxeles que el sprite se adelanta al golpear.
@export var attack_lunge: float = 3.0

@export_group("Caminata")
## Grados que se inclina el sprite hacia cada lado al caminar.
@export var walk_tilt_degrees: float = 8.0
## Píxeles que sube el sprite en cada paso.
@export var walk_bounce_height: float = 1.5
## Pasos por segundo.
@export var walk_step_rate: float = 8.0

# Duración del retroceso en segundos.
const KNOCKBACK_TIME := 0.15
## Mano derecha del caballero respecto de WeaponPivot, mirando a la derecha: ahí
## queda la empuñadura (held_grip) del arma.
const HAND_POSITION := Vector2(3, 2)
## Ángulo del arma en reposo, en el espacio del pivote: la hoja levantada hacia
## adelante, como la espada que traía dibujada el sprite original.
const REST_ANGLE := -PI / 4.0
## Medio arco que recorre el arma en un tajo: va de -SWING_HALF_ANGLE (arriba) a
## +SWING_HALF_ANGLE (abajo), como la estela de la espada.
const SWING_HALF_ANGLE := PI * 5.0 / 12.0
## Píxeles que avanza el arma en una estocada.
const THRUST_DISTANCE := 4.0
## Animación de la estela en effect_frames.
const EFFECT_ANIMATION := &"default"

## Vida actual, en medios corazones.
var health: int
var has_key: bool = false
## Daño extra de cada golpe, comprado en la tienda. El nivel lo asigna desde
## Game.damage_bonus; se suma al daño del arma.
var damage_bonus: int = 0
## Última dirección de movimiento; hacia ella se lanza el golpe.
var facing: Vector2 = Vector2.RIGHT
## true ignora todo el daño (sin retroceso ni invulnerabilidad). Solo lo usa la
## zona de pruebas; en una partida siempre es false.
var invincible := false
## true: quedarse sin vida no termina la partida. El jugador se detiene y
## emite knocked_out en lugar de died, y el nivel lo revive con revive(). Solo
## lo usa la demo (puntos de control); en una partida normal es false.
var revives_on_death := false
## Quién hizo el último daño (el source de take_damage): con él se registra la
## causa de la muerte. Vacío hasta el primer golpe.
var last_damage_source: StringName = &""

# Tiempo restante de invulnerabilidad; mayor que cero significa invulnerable.
var _invulnerable_left: float = 0.0
# Tiempo restante de anticipación (el arma se levanta, la hitbox todavía no
# está activa), con la hitbox activa y hasta poder volver a atacar.
var _windup_left: float = 0.0
var _attack_left: float = 0.0
var _cooldown_left: float = 0.0
# Movimiento del arma en la mano durante el golpe.
var _weapon_tween: Tween
# Objetivos ya golpeados en el golpe actual, para no pegarles dos veces.
var _hit_this_swing: Array[Node] = []
# Fase del ciclo de caminata; cada paso avanza PI radianes.
var _walk_phase: float = 0.0
# Velocidad inicial del retroceso y tiempo que le queda; mientras dura, el
# jugador no controla su movimiento.
var _knockback: Vector2 = Vector2.ZERO
var _knockback_left: float = 0.0
# Freno de un efecto (frío de la liche, esporas del Guardián): multiplicador de
# la velocidad y tiempo que le queda. Se marca con partículas, no con tinte.
var _slow_factor: float = 1.0
var _slow_left: float = 0.0
var _slow_particles: CPUParticles2D

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var held: Sprite2D = $WeaponPivot/Held
@onready var effect: AnimatedSprite2D = $WeaponPivot/Effect
@onready var hitbox: Area2D = $WeaponPivot/Hitbox
@onready var hitbox_shape: CollisionShape2D = $WeaponPivot/Hitbox/CollisionShape2D


func _ready() -> void:
	health = max_health
	# Inicia la animación de reposo.
	sprite.play("idle")
	# La hitbox detecta cuerpos (enemigos) y también áreas, por si algún
	# objetivo golpeable es un Area2D.
	hitbox.area_entered.connect(_on_hitbox_touched)
	hitbox.body_entered.connect(_on_hitbox_touched)
	# La estela no tiene loop: al terminar se oculta.
	effect.animation_finished.connect(effect.hide)
	_apply_weapon()
	_aim_weapon()


func _physics_process(delta: float) -> void:
	_update_invulnerability(delta)
	_update_attack(delta)
	_update_slow(delta)

	# Combina las cuatro acciones de movimiento en un solo vector.
	# get_vector lo normaliza, por lo que en diagonal no se avanza más rápido.
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _knockback_left > 0.0:
		velocity = _knockback_step(delta)
	else:
		velocity = direction * speed * _move_speed_factor()

	if direction != Vector2.ZERO:
		facing = direction.normalized()
	# Voltea el sprite solo cuando hay componente horizontal,
	# así al moverse en vertical conserva la última orientación.
	if direction.x != 0.0:
		sprite.flip_h = direction.x < 0.0
	# Durante el golpe el arma y la hitbox quedan hacia donde se lanzó.
	if not is_attacking():
		_aim_weapon()

	if Input.is_action_just_pressed("attack"):
		_try_attack()

	# Aplica el movimiento y resuelve las colisiones con las paredes.
	move_and_slide()

	# Usa la velocidad real, así no "camina en el lugar" al empujar una pared.
	_update_walk_animation(delta, get_real_velocity().length() > 1.0)


## Caminata simulada: el caballero solo tiene animación de reposo, así que al
## moverse se balancea de lado a lado y rebota en cada paso.
func _update_walk_animation(delta: float, moving: bool) -> void:
	if moving:
		# Pausa el reposo para que su rebote no se sume al de la caminata.
		if sprite.is_playing():
			sprite.pause()
		_walk_phase = fmod(_walk_phase + delta * walk_step_rate * PI, TAU)
		sprite.rotation = sin(_walk_phase) * deg_to_rad(walk_tilt_degrees)
		# abs() hace que rebote una vez por paso, no una vez por ciclo.
		sprite.offset.y = -absf(sin(_walk_phase)) * walk_bounce_height
	else:
		# Vuelve suavemente a la pose normal y retoma la animación de reposo.
		var blend := minf(1.0, delta * 15.0)
		sprite.rotation = lerpf(sprite.rotation, 0.0, blend)
		sprite.offset.y = lerpf(sprite.offset.y, 0.0, blend)
		_walk_phase = 0.0
		if not sprite.is_playing():
			sprite.play("idle")


## Resta amount medios corazones salvo que el jugador esté en su ventana de
## invulnerabilidad. Lo llaman las trampas y los enemigos. Si se pasa
## from_position (de dónde vino el golpe), el jugador retrocede en la
## dirección contraria; sin ella, como en los picos, solo pierde vida. source
## dice quién lo lastimó (ver damaged); no cambia nada del juego.
func take_damage(amount: int, from_position: Vector2 = Vector2.INF, source: StringName = &"") -> void:
	if invincible or _invulnerable_left > 0.0 or health <= 0:
		return

	var health_before := health
	health = max(health - amount, 0)
	last_damage_source = source
	health_changed.emit(health)
	if health < health_before:
		damaged.emit(health_before - health, source)
	Sfx.play(&"player_hurt")

	if health == 0:
		_die()
		return

	# Activa la invulnerabilidad y marca al jugador semitransparente.
	_invulnerable_left = invulnerability_time
	sprite.modulate.a = 0.5
	_apply_knockback(from_position)


## Empuja al jugador lejos de from_position. Vector2.INF significa "sin origen".
func _apply_knockback(from_position: Vector2) -> void:
	if from_position == Vector2.INF:
		return
	# Velocidad inicial para recorrer knockback_distance mientras decae a cero.
	var push_speed := 2.0 * knockback_distance / KNOCKBACK_TIME
	_knockback = (global_position - from_position).normalized() * push_speed
	_knockback_left = KNOCKBACK_TIME


## Avanza el retroceso y devuelve su velocidad actual, que decae hasta cero.
func _knockback_step(delta: float) -> Vector2:
	_knockback_left -= delta
	return _knockback * maxf(_knockback_left, 0.0) / KNOCKBACK_TIME


## Suma amount medios corazones sin superar max_health. Devuelve true si
## recuperó algo; false si ya tenía la vida llena o está muerto. La llaman los
## corazones.
func heal(amount: int = Heart.HALF_HEARTS_PER_HEART) -> bool:
	if amount <= 0 or health <= 0 or health >= max_health:
		return false
	health = mini(health + amount, max_health)
	health_changed.emit(health)
	return true


## Avisa que recogió amount monedas; el nivel las suma a Game.coins. La llaman
## las monedas.
func collect_coins(amount: int) -> void:
	if amount > 0:
		coins_collected.emit(amount)


## Daño total de cada golpe: el del arma más lo comprado en la tienda.
func get_hit_damage() -> int:
	return weapon.damage + maxi(damage_bonus, 0)


## Cambia el arma equipada y actualiza lo que se ve y la hitbox. Ignora null.
## Lo llama el nivel con el arma de la partida.
func equip_weapon(new_weapon: WeaponData) -> void:
	if new_weapon == null:
		return
	var changed := weapon == null or weapon.id != new_weapon.id
	weapon = new_weapon
	if is_node_ready():
		_apply_weapon()
		_aim_weapon()
	if changed:
		weapon_changed.emit(weapon.id)


## true desde que empieza un golpe (anticipación incluida) hasta que su hitbox
## deja de estar activa.
func is_attacking() -> bool:
	return _windup_left > 0.0 or _attack_left > 0.0


## Marca que el jugador tiene la llave. La llama la llave al ser tocada.
func collect_key() -> void:
	has_key = true
	key_collected.emit()


func _try_attack() -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = weapon.cooldown
	_hit_this_swing.clear()
	Sfx.play(&"sword_swing")

	# Orienta el arma, la hitbox y la estela hacia donde mira el jugador.
	_aim_weapon()
	_play_attack_motion()
	if weapon.windup > 0.0:
		_windup_left = weapon.windup
	else:
		_start_active_time()


## Activa la hitbox durante active_time y muestra la estela.
func _start_active_time() -> void:
	_attack_left = weapon.active_time
	# Diferido: cambiar el monitoreo durante el paso de física no es seguro.
	hitbox.set_deferred("monitoring", true)
	_play_effect()


func _update_attack(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	if _windup_left > 0.0:
		_windup_left -= delta
		if _windup_left <= 0.0:
			_start_active_time()
	elif _attack_left > 0.0:
		_attack_left -= delta
		# Al terminar la ventana activa, la hitbox deja de detectar.
		if _attack_left <= 0.0:
			hitbox.set_deferred("monitoring", false)
			attacked.emit(not _hit_this_swing.is_empty())


## Multiplicador de la velocidad: el arma puede frenar al jugador mientras ataca
## y un efecto (apply_slow) mientras dure.
func _move_speed_factor() -> float:
	var factor: float = weapon.move_speed_while_attacking if is_attacking() else 1.0
	return factor * slow_multiplier()


## Frena al jugador: multiplica su velocidad por factor (0 a 1) durante
## duration segundos. Si ya estaba frenado se queda con el freno más fuerte y
## el tiempo más largo. Lo usan los jefes (frío de la liche, esporas del
## Guardián). Se ve con partículas del color dado alrededor del jugador: los
## tintes ya tienen significado (sección 2.3 de la biblia).
func apply_slow(factor: float, duration: float, color: Color = Color(0.85, 0.95, 1.0)) -> void:
	if duration <= 0.0 or factor >= 1.0:
		return
	factor = clampf(factor, 0.0, 1.0)
	_slow_factor = minf(_slow_factor, factor) if _slow_left > 0.0 else factor
	_slow_left = maxf(_slow_left, duration)
	var particles := _get_slow_particles()
	particles.color = color
	particles.emitting = true


## Multiplicador de velocidad del freno actual (1 sin freno).
func slow_multiplier() -> float:
	return _slow_factor if _slow_left > 0.0 else 1.0


func _update_slow(delta: float) -> void:
	if _slow_left <= 0.0:
		return
	_slow_left -= delta
	if _slow_left <= 0.0:
		_slow_factor = 1.0
		if _slow_particles:
			_slow_particles.emitting = false


## Partículas del freno; se crean la primera vez que hacen falta.
func _get_slow_particles() -> CPUParticles2D:
	if _slow_particles == null:
		_slow_particles = CPUParticles2D.new()
		_slow_particles.amount = 6
		_slow_particles.lifetime = 0.6
		_slow_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		_slow_particles.emission_sphere_radius = 7.0
		_slow_particles.direction = Vector2.UP
		_slow_particles.spread = 30.0
		_slow_particles.gravity = Vector2.ZERO
		_slow_particles.initial_velocity_min = 4.0
		_slow_particles.initial_velocity_max = 8.0
		_slow_particles.scale_amount_min = 1.0
		_slow_particles.scale_amount_max = 2.0
		add_child(_slow_particles)
	return _slow_particles


func _on_hitbox_touched(target: Node) -> void:
	# Solo golpea a lo que sabe recibir golpes, y una vez por ataque. Un arma
	# que no atraviesa (pierce en false) solo golpea al primero.
	if target in _hit_this_swing or not target.has_method("take_hit"):
		return
	if not weapon.pierce and not _hit_this_swing.is_empty():
		return
	_hit_this_swing.append(target)
	# Solo los enemigos entienden el retroceso del arma; otros objetivos (por
	# ejemplo, proyectiles que se rompen) reciben el golpe de siempre.
	if target is EnemyBase:
		target.take_hit(get_hit_damage(), global_position, weapon.knockback_scale())
	else:
		target.take_hit(get_hit_damage(), global_position)


## Muestra el arma equipada: su sprite con la empuñadura en la mano, su estela y
## la forma y distancia de su hitbox.
func _apply_weapon() -> void:
	if _weapon_tween:
		_weapon_tween.kill()
	held.texture = weapon.held_texture
	if weapon.held_texture:
		# Con centered, el píxel held_grip queda en el origen del Sprite2D.
		held.offset = weapon.held_texture.get_size() / 2.0 - weapon.held_grip
	held.position = HAND_POSITION
	held.rotation = REST_ANGLE
	effect.sprite_frames = weapon.effect_frames
	effect.stop()
	effect.hide()
	hitbox_shape.shape = weapon.make_hitbox_shape()
	hitbox_shape.position = Vector2(weapon.hitbox_distance, 0.0)


## Gira el pivote hacia facing. Si el caballero mira a la izquierda el pivote se
## refleja en vertical, así el arma queda en su mano y no boca abajo. Mirando
## hacia arriba el arma se dibuja detrás del cuerpo.
func _aim_weapon() -> void:
	weapon_pivot.rotation = facing.angle()
	weapon_pivot.scale.y = -1.0 if sprite.flip_h else 1.0
	held.z_index = -1 if facing.y < -0.5 else 0


## Movimiento del arma en la mano y pequeño avance del sprite, porque el
## caballero no tiene animación de ataque. Un tajo recorre un arco de arriba
## abajo; una estocada empuja el arma hacia adelante. La anticipación (windup)
## prepara el golpe y el resto dura active_time.
func _play_attack_motion() -> void:
	if _weapon_tween:
		_weapon_tween.kill()
	var active := weapon.active_time
	_weapon_tween = create_tween()
	if weapon.is_thrust():
		held.rotation = 0.0
		var back := HAND_POSITION - Vector2(THRUST_DISTANCE * 0.5, 0.0)
		if weapon.windup > 0.0:
			_weapon_tween.tween_property(held, "position", back, weapon.windup)
		_weapon_tween.tween_property(held, "position", HAND_POSITION + Vector2(THRUST_DISTANCE, 0.0), active * 0.4)
		_weapon_tween.tween_property(held, "position", HAND_POSITION, active * 0.6)
	else:
		if weapon.windup > 0.0:
			_weapon_tween.tween_property(held, "rotation", -SWING_HALF_ANGLE, weapon.windup)
		else:
			held.rotation = -SWING_HALF_ANGLE
		_weapon_tween.tween_property(held, "rotation", SWING_HALF_ANGLE, active * 0.4) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_weapon_tween.tween_interval(active * 0.6)
	_weapon_tween.tween_property(held, "rotation", REST_ANGLE, weapon.cooldown * 0.25)

	var lunge := create_tween()
	if weapon.windup > 0.0:
		lunge.tween_interval(weapon.windup)
	lunge.tween_property(sprite, "position", facing * attack_lunge, active * 0.4)
	lunge.tween_property(sprite, "position", Vector2.ZERO, active * 0.6)


## Estela del arma, centrada en el jugador y apuntando a la derecha del pivote.
func _play_effect() -> void:
	if effect.sprite_frames == null or not effect.sprite_frames.has_animation(EFFECT_ANIMATION):
		return
	effect.show()
	effect.stop()
	effect.play(EFFECT_ANIMATION)


func _update_invulnerability(delta: float) -> void:
	if _invulnerable_left <= 0.0:
		return
	_invulnerable_left -= delta
	# Al terminar la invulnerabilidad el sprite vuelve a ser opaco.
	if _invulnerable_left <= 0.0:
		sprite.modulate.a = 1.0
		return
	# Parpadea para que se note que el jugador es invulnerable y por cuánto.
	var blink_on := int(_invulnerable_left * blink_rate * 2.0) % 2 == 0
	sprite.modulate.a = 0.3 if blink_on else 0.8


func _die() -> void:
	# Deja de moverse y avisa; el nivel decide qué hacer (mostrar Game Over o,
	# en la demo, revivirlo en el punto de control).
	set_physics_process(false)
	if revives_on_death:
		knocked_out.emit()
		return
	died.emit()


## Vuelve a la vida en la posición global at con new_health medios corazones
## (entre 1 y max_health), sin retroceso, frenos ni golpe en curso y con la
## invulnerabilidad de un golpe recibido, para que no lo lastimen apenas
## aparece. No emite health_changed: el nivel actualiza lo que se ve con
## revived.
func revive(at: Vector2, new_health: int) -> void:
	global_position = at
	velocity = Vector2.ZERO
	health = clampi(new_health, 1, max_health)
	last_damage_source = &""
	_knockback_left = 0.0
	_slow_left = 0.0
	_slow_factor = 1.0
	if _slow_particles:
		_slow_particles.emitting = false
	_windup_left = 0.0
	_attack_left = 0.0
	hitbox.set_deferred("monitoring", false)
	_invulnerable_left = invulnerability_time
	sprite.modulate.a = 0.5
	set_physics_process(true)
	revived.emit(health)
