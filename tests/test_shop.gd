@tool
extends McpTestSuite
## Pruebas de la tienda: precios y reglas de compra (Shop), incluidas las armas,
## y la compra sobre el estado de la partida (Game.buy). Usan una copia de Game
## cuya start_level no cambia de escena.

const GAME_SCRIPT := "res://scripts/game.gd"
## Vida máxima del jugador en medios corazones: 3 corazones.
const MAX_HEALTH := 6


var _game: Node


func suite_name() -> String:
	return "shop"


func setup() -> void:
	var stub := GDScript.new()
	stub.source_code = "extends \"%s\"\n\n\nfunc start_level() -> void:\n\tpass\n" % GAME_SCRIPT
	stub.reload()
	_game = stub.new()
	_game.new_game()


func teardown() -> void:
	_game.free()


func test_damage_price_escalates_with_each_purchase() -> void:
	assert_eq(Shop.price_for(Shop.ITEM_DAMAGE, 0), 10)
	assert_eq(Shop.price_for(Shop.ITEM_DAMAGE, 1), 20)
	assert_eq(Shop.price_for(Shop.ITEM_DAMAGE, 2), 30)
	assert_eq(Shop.price_for(Shop.ITEM_DAMAGE, Shop.MAX_DAMAGE_BONUS - 1), 100)


func test_life_price_is_fixed_and_unknown_items_have_no_price() -> void:
	assert_eq(Shop.price_for(Shop.ITEM_LIFE, 0), Shop.LIFE_PRICE)
	assert_eq(Shop.price_for(Shop.ITEM_LIFE, 5), Shop.LIFE_PRICE)
	assert_eq(Shop.price_for(&"sword", 0), -1)


func test_life_price_follows_the_enemy_scale() -> void:
	assert_eq(Shop.price_for(Shop.ITEM_LIFE, 0, 1.0), Shop.LIFE_PRICE)
	assert_eq(Shop.price_for(Shop.ITEM_LIFE, 0, 2.0), Shop.LIFE_PRICE * 2)
	assert_eq(Shop.price_for(Shop.ITEM_LIFE, 0, 8.92), roundi(Shop.LIFE_PRICE * 8.92))
	assert_eq(Shop.price_for(Shop.ITEM_LIFE, 0, 0.3), Shop.LIFE_PRICE, "nunca baja del precio base")
	assert_eq(Shop.price_for(Shop.ITEM_DAMAGE, 1, 8.92), 20, "el daño no sigue la escala")
	assert_false(Shop.can_buy(Shop.ITEM_LIFE, Shop.LIFE_PRICE, 0, 1, MAX_HEALTH, 2.0))
	assert_true(Shop.can_buy(Shop.ITEM_LIFE, Shop.LIFE_PRICE * 2, 0, 1, MAX_HEALTH, 2.0))


func test_game_charges_the_life_price_of_the_current_level() -> void:
	_game.current_level = 11
	_game.health = 1
	var price := roundi(Shop.LIFE_PRICE * LevelGenerator.enemy_health_scale(11))
	_game.add_coins(price - 1)
	assert_false(_game.buy(Shop.ITEM_LIFE, MAX_HEALTH))
	_game.add_coins(1)
	assert_true(_game.buy(Shop.ITEM_LIFE, MAX_HEALTH))
	assert_eq(_game.coins, 0)


func test_damage_is_available_until_its_cap() -> void:
	assert_true(Shop.is_available(Shop.ITEM_DAMAGE, 0, 3, MAX_HEALTH))
	assert_true(Shop.is_available(Shop.ITEM_DAMAGE, Shop.MAX_DAMAGE_BONUS - 1, 3, MAX_HEALTH))
	assert_false(Shop.is_available(Shop.ITEM_DAMAGE, Shop.MAX_DAMAGE_BONUS, 3, MAX_HEALTH))


func test_life_is_only_available_below_max_health() -> void:
	assert_true(Shop.is_available(Shop.ITEM_LIFE, 0, 4, MAX_HEALTH))
	assert_true(Shop.is_available(Shop.ITEM_LIFE, 0, MAX_HEALTH - 1, MAX_HEALTH), "falta medio corazón")
	assert_false(Shop.is_available(Shop.ITEM_LIFE, 0, MAX_HEALTH, MAX_HEALTH), "con la vida llena no se vende")
	assert_false(Shop.is_available(Shop.ITEM_LIFE, 0, 0, MAX_HEALTH), "un jugador muerto no compra")
	assert_false(Shop.is_available(&"sword", 0, 1, MAX_HEALTH))


func test_can_buy_needs_enough_coins() -> void:
	assert_false(Shop.can_buy(Shop.ITEM_DAMAGE, 9, 0, 3, MAX_HEALTH))
	assert_true(Shop.can_buy(Shop.ITEM_DAMAGE, 10, 0, 3, MAX_HEALTH), "alcanza con el precio justo")
	assert_false(Shop.can_buy(Shop.ITEM_DAMAGE, 999, Shop.MAX_DAMAGE_BONUS, 3, MAX_HEALTH), "tope alcanzado")
	assert_false(Shop.can_buy(Shop.ITEM_LIFE, 999, 0, MAX_HEALTH, MAX_HEALTH), "vida completa")


func test_buying_damage_spends_coins_and_raises_the_bonus() -> void:
	var bought: Array = []
	_game.item_bought.connect(func(item: StringName, price: int) -> void: bought.append([item, price]))
	_game.add_coins(35)
	assert_true(_game.buy(Shop.ITEM_DAMAGE, MAX_HEALTH))
	assert_eq(_game.damage_bonus, 1)
	assert_eq(_game.coins, 25)
	assert_true(_game.buy(Shop.ITEM_DAMAGE, MAX_HEALTH))
	assert_eq(_game.damage_bonus, 2)
	assert_eq(_game.coins, 5)
	assert_eq(bought, [[Shop.ITEM_DAMAGE, 10], [Shop.ITEM_DAMAGE, 20]])


func test_buying_a_life_adds_one_heart_up_to_the_cap() -> void:
	assert_eq(Shop.LIFE_HEAL, Heart.HALF_HEARTS_PER_HEART, "la vida comprada es un corazón")
	_game.health = 1
	_game.add_coins(Shop.LIFE_PRICE * 4)
	assert_true(_game.buy(Shop.ITEM_LIFE, MAX_HEALTH))
	assert_eq(_game.health, 3, "medio corazón + uno entero")
	assert_true(_game.buy(Shop.ITEM_LIFE, MAX_HEALTH))
	assert_eq(_game.health, 5)
	assert_true(_game.buy(Shop.ITEM_LIFE, MAX_HEALTH), "falta medio corazón: se puede comprar")
	assert_eq(_game.health, MAX_HEALTH, "pero no supera max_health")
	assert_false(_game.buy(Shop.ITEM_LIFE, MAX_HEALTH), "con la vida llena no se compra")
	assert_eq(_game.health, MAX_HEALTH)
	assert_eq(_game.coins, Shop.LIFE_PRICE, "la compra rechazada no cobra")


func test_failed_purchase_changes_nothing() -> void:
	var signals := [0]
	_game.coins_changed.connect(func(_coins: int) -> void: signals[0] += 1)
	_game.item_bought.connect(func(_item: StringName, _price: int) -> void: signals[0] += 1)
	_game.coins = 9
	assert_false(_game.buy(Shop.ITEM_DAMAGE, MAX_HEALTH))
	assert_false(_game.buy(&"sword", MAX_HEALTH))
	assert_eq(_game.coins, 9)
	assert_eq(_game.damage_bonus, 0)
	assert_eq(signals[0], 0, "sin compra no hay señales")


func test_add_coins_ignores_non_positive_amounts() -> void:
	var emitted: Array[int] = []
	_game.coins_changed.connect(func(coins: int) -> void: emitted.append(coins))
	_game.add_coins(2)
	_game.add_coins(0)
	_game.add_coins(-3)
	assert_eq(_game.coins, 2)
	assert_eq(emitted, [2])


func test_weapon_prices_and_availability() -> void:
	assert_eq(Shop.price_for(Shop.ITEM_SPEAR, 0), 15)
	assert_eq(Shop.price_for(Shop.ITEM_DAGGER, 0), 25)
	assert_eq(Shop.price_for(Shop.ITEM_DAGGER, 0, 8.92), 25, "no sigue la escala del nivel")
	assert_true(Shop.is_weapon(Shop.ITEM_SPEAR))
	assert_false(Shop.is_weapon(Shop.ITEM_DAMAGE))
	assert_true(Shop.is_available(Shop.ITEM_SPEAR, 0, 3, MAX_HEALTH))
	assert_false(Shop.is_available(Shop.ITEM_SPEAR, 1, 3, MAX_HEALTH), "la equipada no se ofrece")
	assert_true(Shop.ITEM_SPEAR in Shop.ITEMS and Shop.ITEM_DAGGER in Shop.ITEMS)
	for item in Shop.WEAPON_PRICES:
		assert_true(WeaponData.load_by_id(item) != null, "%s es un arma que existe" % item)


func test_buying_a_weapon_equips_it() -> void:
	var bought: Array = []
	_game.item_bought.connect(func(item: StringName, price: int) -> void: bought.append([item, price]))
	_game.add_coins(14)
	assert_false(_game.buy(Shop.ITEM_SPEAR, MAX_HEALTH), "faltan monedas")
	assert_eq(_game.weapon_id, &"sword")
	_game.add_coins(26)
	assert_true(_game.buy(Shop.ITEM_SPEAR, MAX_HEALTH))
	assert_eq(_game.weapon_id, &"spear")
	assert_eq(_game.coins, 25)
	assert_false(_game.buy(Shop.ITEM_SPEAR, MAX_HEALTH), "ya la tiene equipada")
	assert_true(_game.buy(Shop.ITEM_DAGGER, MAX_HEALTH))
	assert_eq(_game.weapon_id, &"dagger", "reemplaza a la lanza")
	assert_eq(_game.coins, 0)
	assert_eq(_game.times_bought(Shop.ITEM_SPEAR), 0, "la lanza se vuelve a ofrecer")
	assert_eq(bought, [[Shop.ITEM_SPEAR, 15], [Shop.ITEM_DAGGER, 25]])
	assert_eq(_game.damage_bonus, 0, "comprar un arma no toca el daño extra")


func test_bought_weapon_lasts_until_the_run_ends() -> void:
	_game.add_coins(Shop.price_for(Shop.ITEM_DAGGER, 0))
	assert_true(_game.buy(Shop.ITEM_DAGGER, MAX_HEALTH))
	_game.complete_level()
	_game.start_level()
	assert_eq(_game.weapon_id, &"dagger", "el siguiente nivel la conserva")
	_game.retry()
	assert_eq(_game.weapon_id, WeaponData.STARTING_ID, "la partida nueva vuelve a la espada")
	assert_true(Shop.is_available(Shop.ITEM_DAGGER, _game.times_bought(Shop.ITEM_DAGGER), _game.health, MAX_HEALTH))
