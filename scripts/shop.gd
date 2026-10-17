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
##   life    +1 vida. Solo si al jugador le faltan vidas: nunca supera
##           max_lives, igual que los corazones.
##
## La vida de los enemigos crece con el nivel y las monedas que sueltan crecen
## igual (Coin.scaled_value), así que lo que vale el dinero tiene que seguir el
## mismo ritmo: el precio de la vida se multiplica por la escala del nivel
## (LevelGenerator.enemy_health_scale). El del daño no, porque ya sube con cada
## compra; así las mejoras de daño se abaratan frente al nivel y alcanzan a los
## enemigos más fuertes.

const ITEM_DAMAGE := &"damage"
const ITEM_LIFE := &"life"
## Artículos en el orden en que se muestran.
const ITEMS: Array[StringName] = [ITEM_DAMAGE, ITEM_LIFE]

## Precio de la primera mejora de daño y cuánto sube con cada compra.
const DAMAGE_BASE_PRICE := 10
const DAMAGE_PRICE_STEP := 10
## Mejoras de daño que se pueden comprar en una partida: con las diez, la
## espada pega 11, suficiente para los enemigos de los niveles más altos.
const MAX_DAMAGE_BONUS := 10
const LIFE_PRICE := 6


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
	return -1


## true si item se puede ofrecer, sin mirar las monedas: la mejora de daño no
## llegó a su tope y, para la vida, el jugador está vivo y le faltan vidas.
static func is_available(item: StringName, times_bought: int, lives: int, max_lives: int) -> bool:
	match item:
		ITEM_DAMAGE:
			return times_bought < MAX_DAMAGE_BONUS
		ITEM_LIFE:
			return lives > 0 and lives < max_lives
	return false


## true si item está disponible y coins alcanza para pagarlo (scale como en
## price_for).
static func can_buy(item: StringName, coins: int, times_bought: int, lives: int,
		max_lives: int, scale: float = 1.0) -> bool:
	return is_available(item, times_bought, lives, max_lives) \
			and coins >= price_for(item, times_bought, scale)
