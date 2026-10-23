@tool
class_name Shop
extends RefCounted
## Reglas de la tienda de la pantalla de nivel superado: qué artículos hay,
## cuánto cuestan y cuándo se pueden comprar. Es lógica pura (sin nodos ni
## estado global): Game guarda las monedas y las mejoras compradas, y la HUD
## solo muestra lo que estas funciones responden.
##
## Artículos:
##   damage  +1 de daño en cada golpe de espada. El precio sube con cada
##           compra (10, 20, 30...) y se puede comprar como mucho
##           MAX_DAMAGE_BONUS veces por partida.
##   life    +1 corazón de vida (LIFE_HEAL medios corazones). Solo si al
##           jugador le falta vida: nunca supera max_health, igual que los
##           corazones del suelo. El id sigue siendo "life" para que las
##           compras viejas y nuevas cuenten juntas en las estadísticas.
##   spear,  armas (el artículo es el id de WeaponData). Reemplazan al arma
##   dagger  equipada hasta el final de la partida, a precio fijo. No se
##           ofrece la que ya está equipada: para las armas, times_bought es 1
##           si es la equipada y 0 si no.
##
## La vida de los enemigos crece con el nivel y las monedas que sueltan crecen
## igual (Coin.scaled_value), así que lo que vale el dinero tiene que seguir el
## mismo ritmo: el precio de la vida se multiplica por la escala del nivel
## (LevelGenerator.enemy_health_scale). El del daño no, porque ya sube con cada
## compra; así las mejoras de daño se abaratan frente al nivel y alcanzan a los
## enemigos más fuertes.

const ITEM_DAMAGE := &"damage"
const ITEM_LIFE := &"life"
const ITEM_SPEAR := &"spear"
const ITEM_DAGGER := &"dagger"
## Artículos en el orden en que se muestran.
const ITEMS: Array[StringName] = [ITEM_DAMAGE, ITEM_LIFE, ITEM_SPEAR, ITEM_DAGGER]

## Precio de la primera mejora de daño y cuánto sube con cada compra.
const DAMAGE_BASE_PRICE := 10
const DAMAGE_PRICE_STEP := 10
## Mejoras de daño que se pueden comprar en una partida: con las diez, la
## espada pega 11, suficiente para los enemigos de los niveles más altos.
const MAX_DAMAGE_BONUS := 10
const LIFE_PRICE := 6
## Medios corazones que cura la vida comprada: un corazón, como los del suelo.
const LIFE_HEAL := Heart.HALF_HEARTS_PER_HEART
## Precio de cada arma. No sigue la escala del nivel, igual que el daño. La
## lanza alcanza más pero pega más lento; la daga pega el doble de seguido que
## la espada (el doble de daño por segundo, pero de cerca), por eso cuesta más.
## Con las monedas de los primeros niveles, la lanza llega hacia el nivel 3 y
## la daga hacia el 4.
const WEAPON_PRICES: Dictionary[StringName, int] = {ITEM_SPEAR: 15, ITEM_DAGGER: 25}


## Precio de item después de haberlo comprado times_bought veces en la partida.
## scale es el multiplicador de vida del nivel (1.0 en el nivel 1); solo afecta
## a la vida, y nunca la deja por debajo de LIFE_PRICE. Devuelve -1 si item no
## existe.
static func price_for(item: StringName, times_bought: int, scale: float = 1.0) -> int:
	match item:
		ITEM_DAMAGE:
			return DAMAGE_BASE_PRICE + DAMAGE_PRICE_STEP * maxi(times_bought, 0)
		ITEM_LIFE:
			return maxi(roundi(LIFE_PRICE * scale), LIFE_PRICE)
	return WEAPON_PRICES.get(item, -1)


## true si item es un arma: al comprarla se equipa en lugar de la actual.
static func is_weapon(item: StringName) -> bool:
	return WEAPON_PRICES.has(item)


## true si item se puede ofrecer, sin mirar las monedas: la mejora de daño no
## llegó a su tope; para la vida, el jugador está vivo y le falta vida (health
## y max_health en medios corazones); y un arma, si no es la equipada
## (times_bought en 0).
static func is_available(item: StringName, times_bought: int, health: int, max_health: int) -> bool:
	match item:
		ITEM_DAMAGE:
			return times_bought < MAX_DAMAGE_BONUS
		ITEM_LIFE:
			return health > 0 and health < max_health
	return is_weapon(item) and times_bought == 0


## true si item está disponible y coins alcanza para pagarlo (scale como en
## price_for).
static func can_buy(item: StringName, coins: int, times_bought: int, health: int,
		max_health: int, scale: float = 1.0) -> bool:
	return is_available(item, times_bought, health, max_health) \
			and coins >= price_for(item, times_bought, scale)
