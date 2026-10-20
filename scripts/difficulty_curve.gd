@tool
class_name DifficultyCurve
extends RefCounted
## Análisis de la curva de dificultad de los niveles generados.
##
## Resume los números de LevelGenerator.params_for_level en un índice de
## dificultad por nivel y mide cuánto crece de un nivel al siguiente. Se
## considera que un nivel sube la dificultad de forma significativa cuando su
## índice crece al menos TARGET_GROWTH respecto del nivel anterior.
##
## Es lógica pura y sin estado (solo funciones estáticas), igual que
## LevelGenerator: la usan la pantalla del modo prueba y las pruebas.
##
## @tool: así las pruebas del editor pueden ejecutarlo.

# ---------------------------------------------------------------------------
# Pesos del índice. Son supuestos ajustables, no mediciones: expresan cuánto
# más peligroso se considera cada elemento respecto de un esqueleto. Conviene
# revisarlos con los datos de las partidas de prueba (difficulty_playtest.csv).
# ---------------------------------------------------------------------------

## Esqueleto soldado. La referencia (1.0) era el esqueleto original, que solo
## patrullaba un tramo recto y lastimaba por contacto. Ahora además deja la
## ruta para ir hacia el jugador y lo ataca con una estocada con aviso, y su
## paso de guardia lo aleja al recibir un golpe: se sube a 1.5, por debajo del
## vampiro, que lo persigue más lejos (sin ruta que lo ate) y es más rápido.
const WEIGHT_SKELETON := 1.5
## Vampiro: persigue al jugador y muerde con aviso previo.
const WEIGHT_VAMPIRE := 2.0
## Calavera: persigue y embiste.
const WEIGHT_SKULL := 2.5
## Parca (jefe): guarda la puerta o la llave.
const WEIGHT_BOSS := 6.0
## Trampa de picos: estática y predecible.
const WEIGHT_HAZARD := 0.5
## Esqueleto arquero: el primer peligro a distancia; guarda distancia y
## dispara flechas con aviso (la biblia propone 2.5).
const WEIGHT_ARCHER := 2.5
## Torre de calaveras: dispara orbes pero no se mueve; basta con no quedarse
## en su línea o rodearla.
const WEIGHT_SKULL_TURRET := 1.5
## Cofre mímico: emboscada cuerpo a cuerpo, aguanta más que el vampiro.
const WEIGHT_MIMIC := 2.5
## Mago del orbe: a distancia y con más vida que el arquero, aunque su orbe es
## más lento y se puede devolver con la espada.
const WEIGHT_MAGE := 3.0

## Probabilidad de esquivar de cada tipo: copia de dodge_chance de sus escenas
## (Skeleton, Vampire, Skull, Reaper, Archer, SkullTurret, Mimic y Mage.tscn);
## una prueba comprueba que coincidan.
## La esquiva cuenta como vida extra: con probabilidad p de esquivar, hacen
## falta en promedio 1 / (1 - p) golpes por cada golpe que llega. Es una cota
## superior: el enfriamiento de la esquiva (EnemyBase.DODGE_COOLDOWN) y las
## ventanas en que no puede esquivar la bajan en la práctica.
const DODGE_SKELETON := 0.15
const DODGE_VAMPIRE := 0.20
const DODGE_SKULL := 0.10
const DODGE_BOSS := 0.10
const DODGE_ARCHER := 0.15
## La torre es un pedestal: no esquiva.
const DODGE_SKULL_TURRET := 0.0
const DODGE_MIMIC := 0.10
const DODGE_MAGE := 0.15

## Crecimiento mínimo del índice respecto del nivel anterior para considerar
## que el nivel sube la dificultad de forma significativa (+10 %).
const TARGET_GROWTH := 0.10
## Por debajo de este crecimiento se considera que la curva está en meseta.
const PLATEAU_GROWTH := 0.01
## Último nivel que cubre el análisis.
const LAST_LEVEL := 100
## Archivo donde se exporta el informe de la curva.
const CSV_PATH := "user://difficulty_report.csv"

## Nombres de los topes de LevelGenerator que puede alcanzar un nivel.
const CAP_ENEMIES := &"ENEMIES_MAX"
const CAP_CHASER_SHARE := &"CHASER_SHARE_MAX"
const CAP_HAZARDS := &"HAZARDS_MAX"
const CAP_GRID := &"GRID_MAX"
const CAP_ROOMS := &"ROOM_COUNT_MAX"


# ---------------------------------------------------------------------------
# Índice y crecimiento
# ---------------------------------------------------------------------------

## Índice de dificultad de un conjunto de parámetros: suma de enemigos por
## tipo y jefes, cada uno con su peso efectivo (effective_weight, que suma la
## esquiva), multiplicada por el multiplicador de vida de los enemigos (cuantos
## más golpes aguantan, más peligrosos), más las trampas, que no se escalan.
static func index_for(params: LevelGenerator.Params) -> float:
	var counts := _enemy_counts(params)
	var enemies: float = counts["skeletons"] * effective_weight(WEIGHT_SKELETON, DODGE_SKELETON) \
			+ counts["vampires"] * effective_weight(WEIGHT_VAMPIRE, DODGE_VAMPIRE) \
			+ counts["skulls"] * effective_weight(WEIGHT_SKULL, DODGE_SKULL) \
			+ params.boss_count * effective_weight(WEIGHT_BOSS, DODGE_BOSS)
	for kind: StringName in params.special_counts:
		enemies += params.special_counts[kind] * special_effective_weight(kind)
	return enemies * params.enemy_health_scale + params.hazard_count * WEIGHT_HAZARD


## Peso de un enemigo contando su esquiva como vida extra: weight / (1 - dodge).
static func effective_weight(weight: float, dodge: float) -> float:
	return weight / (1.0 - dodge)


## Peso efectivo de un enemigo especial de LevelGenerator.SPECIAL_ENEMIES.
static func special_effective_weight(kind: StringName) -> float:
	match kind:
		LevelGenerator.ARCHER:
			return effective_weight(WEIGHT_ARCHER, DODGE_ARCHER)
		LevelGenerator.SKULL_TURRET:
			return effective_weight(WEIGHT_SKULL_TURRET, DODGE_SKULL_TURRET)
		LevelGenerator.MIMIC:
			return effective_weight(WEIGHT_MIMIC, DODGE_MIMIC)
		LevelGenerator.MAGE:
			return effective_weight(WEIGHT_MAGE, DODGE_MAGE)
	push_error("DifficultyCurve: enemigo especial sin peso: %s" % kind)
	return 0.0


static func index_for_level(level: int) -> float:
	return index_for(LevelGenerator.params_for_level(level))


## Crecimiento relativo del índice respecto del nivel anterior (0.1 = +10 %).
## El primer nivel generado no tiene anterior con el que compararse: devuelve
## NAN, igual que si el índice anterior fuera cero.
static func growth(level: int) -> float:
	if level <= LevelGenerator.FIRST_GENERATED_LEVEL:
		return NAN
	var previous := index_for_level(level - 1)
	if previous <= 0.0:
		return NAN
	return index_for_level(level) / previous - 1.0


# ---------------------------------------------------------------------------
# Informe por nivel
# ---------------------------------------------------------------------------

## Una fila por nivel entre first y last (incluidos) con la composición del
## nivel, su índice, su crecimiento y los topes que ya alcanzó. Claves:
## level, enemies, skeletons, vampires, skulls, archers, skull_turrets, mimics,
## mages (los especiales no cuentan en enemies), bosses, hazards, grid, rooms,
## health_scale (multiplicador de vida de los enemigos), index, growth (NAN si no hay nivel anterior), meets_target (true si no hay
## con qué comparar) y capped_params (Array[StringName]).
static func report(first: int = LevelGenerator.FIRST_GENERATED_LEVEL, last: int = LAST_LEVEL) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for level in range(first, last + 1):
		var params := LevelGenerator.params_for_level(level)
		var counts := _enemy_counts(params)
		var level_growth := growth(level)
		rows.append({
			"level": level,
			"enemies": params.enemy_count,
			"skeletons": counts["skeletons"],
			"vampires": counts["vampires"],
			"skulls": counts["skulls"],
			"archers": counts["archers"],
			"skull_turrets": counts["skull_turrets"],
			"mimics": counts["mimics"],
			"mages": counts["mages"],
			"bosses": params.boss_count,
			"hazards": params.hazard_count,
			"grid": params.grid_size,
			"rooms": params.room_count,
			"health_scale": params.enemy_health_scale,
			"index": index_for(params),
			"growth": level_growth,
			"meets_target": is_nan(level_growth) or level_growth >= TARGET_GROWTH,
			"capped_params": capped_params(params),
		})
	return rows


## Topes de LevelGenerator que estos parámetros ya alcanzaron: a partir de ahí
## ese valor deja de crecer con el nivel.
static func capped_params(params: LevelGenerator.Params) -> Array[StringName]:
	var caps: Array[StringName] = []
	if params.enemy_count >= LevelGenerator.ENEMIES_MAX:
		caps.append(CAP_ENEMIES)
	if params.chaser_share >= LevelGenerator.CHASER_SHARE_MAX - 0.0001:
		caps.append(CAP_CHASER_SHARE)
	if params.hazard_count >= LevelGenerator.HAZARDS_MAX:
		caps.append(CAP_HAZARDS)
	if params.grid_size.x >= LevelGenerator.GRID_MAX.x and params.grid_size.y >= LevelGenerator.GRID_MAX.y:
		caps.append(CAP_GRID)
	if params.room_count >= LevelGenerator.ROOM_COUNT_MAX:
		caps.append(CAP_ROOMS)
	return caps


## Niveles del informe cuyo crecimiento queda por debajo de TARGET_GROWTH.
static func failing_levels(rows: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for row in rows:
		if not row["meets_target"]:
			out.append(row["level"])
	return out


## Primer nivel del informe que no alcanza TARGET_GROWTH, o -1 si todos lo alcanzan.
static func first_below_target(rows: Array[Dictionary]) -> int:
	var failing := failing_levels(rows)
	return failing[0] if not failing.is_empty() else -1


## Primer nivel desde el que todos los siguientes del informe crecen menos que
## PLATEAU_GROWTH, o -1 si la curva no llega a una meseta.
static func plateau_start(rows: Array[Dictionary]) -> int:
	var start := -1
	for i in range(rows.size() - 1, -1, -1):
		var level_growth: float = rows[i]["growth"]
		if is_nan(level_growth) or level_growth >= PLATEAU_GROWTH:
			break
		start = rows[i]["level"]
	return start


## Lista compacta de niveles: [8, 9, 10, 12] -> "8-10, 12".
static func format_levels(levels: Array[int]) -> String:
	var parts := PackedStringArray()
	var i := 0
	while i < levels.size():
		var j := i
		while j + 1 < levels.size() and levels[j + 1] == levels[j] + 1:
			j += 1
		parts.append(str(levels[i]) if i == j else "%d-%d" % [levels[i], levels[j]])
		i = j + 1
	return ", ".join(parts)


## Escribe el informe en CSV (por defecto en CSV_PATH). Devuelve OK o el error
## de apertura del archivo.
static func save_csv(rows: Array[Dictionary], path: String = CSV_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_csv_line(PackedStringArray([
		"level", "enemies", "skeletons", "vampires", "skulls",
		"archers", "skull_turrets", "mimics", "mages", "bosses", "hazards",
		"grid_x", "grid_y", "rooms", "health_scale", "index", "growth", "meets_target",
		"capped_params"]))
	for row in rows:
		var grid: Vector2i = row["grid"]
		var level_growth: float = row["growth"]
		var caps := PackedStringArray()
		for cap: StringName in row["capped_params"]:
			caps.append(cap)
		file.store_csv_line(PackedStringArray([
			str(row["level"]), str(row["enemies"]), str(row["skeletons"]), str(row["vampires"]),
			str(row["skulls"]), str(row["archers"]), str(row["skull_turrets"]),
			str(row["mimics"]), str(row["mages"]), str(row["bosses"]), str(row["hazards"]),
			str(grid.x), str(grid.y), str(row["rooms"]),
			"%.2f" % row["health_scale"],
			"%.3f" % row["index"],
			"" if is_nan(level_growth) else "%.4f" % level_growth,
			str(row["meets_target"]),
			";".join(caps)]))
	return OK


# ---------------------------------------------------------------------------
# Capacidad del mapa
# ---------------------------------------------------------------------------

## Genera de verdad el mapa del nivel con esa semilla y compara lo pedido con
## lo colocado. Sirve para responder si el mapa admitiría más enemigos o
## trampas si se subieran ENEMIES_MAX o HAZARDS_MAX. Claves:
##   level, seed, requested_enemies / placed_enemies (incluye jefes y especiales),
##   requested_hazards / placed_hazards, used_fallback, attempt,
##   spawnable_cells: celdas aptas para una entidad en todo el mapa,
##   free_cells: de esas, las que respetan ENEMY_SPACING con todo lo colocado,
##   extra_enemy_slots / extra_hazard_slots: cuántos enemigos (o trampas) más
##   cabrían colocándolos uno a uno con su separación mínima, sobre el mapa ya
##   poblado. Es una estimación conservadora: el generador real coloca primero
##   a los enemigos y después las trampas.
static func capacity_report(level: int, run_seed: int) -> Dictionary:
	var params := LevelGenerator.params_for_level(level)
	var layout := LevelGenerator.generate(level, run_seed)
	var cells := LevelGenerator.spawnable_cells(layout)

	# Lo mismo que el generador considera ocupado al separar entidades.
	var taken: Array[Vector2i] = [layout.key_cell]
	taken.append_array(layout.door_floor_cells())
	for enemy in layout.enemies:
		var dir := Vector2i(signi(enemy.patrol.x), signi(enemy.patrol.y))
		for step in maxi(absi(enemy.patrol.x), absi(enemy.patrol.y)) + 1:
			taken.append(enemy.cell + dir * step)
	for hazard in layout.hazards:
		taken.append(hazard.cell)

	var enemy_mask := _spacing_mask(layout.size, taken, LevelGenerator.ENEMY_SPACING)
	var free_cells := 0
	for cell in cells:
		if enemy_mask[cell.y * layout.size.x + cell.x] == 0:
			free_cells += 1

	return {
		"level": level,
		"seed": run_seed,
		"requested_enemies": params.enemy_count + params.boss_count
				+ LevelGenerator.special_total(params),
		"placed_enemies": layout.enemies.size(),
		"requested_hazards": params.hazard_count,
		"placed_hazards": layout.hazards.size(),
		"used_fallback": layout.used_fallback,
		"attempt": layout.attempt,
		"spawnable_cells": cells.size(),
		"free_cells": free_cells,
		"extra_enemy_slots": _greedy_slots(layout.size, cells, enemy_mask, LevelGenerator.ENEMY_SPACING),
		"extra_hazard_slots": _greedy_slots(layout.size, cells,
				_spacing_mask(layout.size, taken, LevelGenerator.HAZARD_SPACING), LevelGenerator.HAZARD_SPACING),
	}


# ---------------------------------------------------------------------------
# Ayudas
# ---------------------------------------------------------------------------

## Cuántos enemigos de cada tipo pide el nivel: los comunes con el mismo
## reparto que LevelGenerator._place_enemies, y los especiales.
static func _enemy_counts(params: LevelGenerator.Params) -> Dictionary:
	var chasers := LevelGenerator.chaser_count(params)
	return {
		"skeletons": params.enemy_count - chasers,
		"vampires": chasers - params.skull_count,
		"skulls": params.skull_count,
		"archers": params.special_counts.get(LevelGenerator.ARCHER, 0),
		"skull_turrets": params.special_counts.get(LevelGenerator.SKULL_TURRET, 0),
		"mimics": params.special_counts.get(LevelGenerator.MIMIC, 0),
		"mages": params.special_counts.get(LevelGenerator.MAGE, 0),
	}


## Máscara de la grilla: 1 en las celdas a menos de min_dist (distancia de
## tablero) de alguna celda ocupada, igual que LevelGenerator._is_spaced.
static func _spacing_mask(size: Vector2i, taken: Array[Vector2i], min_dist: int) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	for cell in taken:
		_block_around(mask, size, cell, min_dist)
	return mask


static func _block_around(mask: PackedByteArray, size: Vector2i, cell: Vector2i, min_dist: int) -> void:
	var r := min_dist - 1
	for y in range(maxi(cell.y - r, 0), mini(cell.y + r + 1, size.y)):
		for x in range(maxi(cell.x - r, 0), mini(cell.x + r + 1, size.x)):
			mask[y * size.x + x] = 1


## Coloca entidades una a una en las celdas libres de la máscara (en el orden
## de cells) respetando min_dist entre ellas, y devuelve cuántas entraron.
## Modifica una copia de la máscara.
static func _greedy_slots(size: Vector2i, cells: Array[Vector2i], mask: PackedByteArray, min_dist: int) -> int:
	var blocked := mask.duplicate()
	var slots := 0
	for cell in cells:
		if blocked[cell.y * size.x + cell.x] == 0:
			slots += 1
			_block_around(blocked, size, cell, min_dist)
	return slots
