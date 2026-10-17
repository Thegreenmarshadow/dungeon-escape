@tool
extends McpTestSuite
## Pruebas de la tienda: precios y reglas de compra (Shop) y la compra sobre el
## estado de la partida (Game.buy). Usan una copia de Game cuya start_level no
## cambia de escena.

const GAME_SCRIPT := "res://scripts/game.gd"
const MAX_LIVES := 3


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
	assert_false(Shop.can_buy(Shop.ITEM_LIFE, Shop.LIFE_PRICE, 0, 1, MAX_LIVES, 2.0))
	assert_true(Shop.can_buy(Shop.ITEM_LIFE, Shop.LIFE_PRICE * 2, 0, 1, MAX_LIVES, 2.0))


func test_game_charges_the_life_price_of_the_current_level() -> void:
	_game.current_level = 11
	_game.lives = 1
	var price := roundi(Shop.LIFE_PRICE * LevelGenerator.enemy_health_scale(11))
	_game.add_coins(price - 1)
	assert_false(_game.buy(Shop.ITEM_LIFE, MAX_LIVES))
	_game.add_coins(1)
	assert_true(_game.buy(Shop.ITEM_LIFE, MAX_LIVES))
	assert_eq(_game.coins, 0)


func test_damage_is_available_until_its_cap() -> void:
	assert_true(Shop.is_available(Shop.ITEM_DAMAGE, 0, 3, MAX_LIVES))
	assert_true(Shop.is_available(Shop.ITEM_DAMAGE, Shop.MAX_DAMAGE_BONUS - 1, 3, MAX_LIVES))
	assert_false(Shop.is_available(Shop.ITEM_DAMAGE, Shop.MAX_DAMAGE_BONUS, 3, MAX_LIVES))


func test_life_is_only_available_below_max_lives() -> void:
	assert_true(Shop.is_available(Shop.ITEM_LIFE, 0, 2, MAX_LIVES))
	assert_false(Shop.is_available(Shop.ITEM_LIFE, 0, 3, MAX_LIVES), "con todas las vidas no se vende")
	assert_false(Shop.is_available(Shop.ITEM_LIFE, 0, 0, MAX_LIVES), "un jugador muerto no compra")
	assert_false(Shop.is_available(&"sword", 0, 1, MAX_LIVES))


func test_can_buy_needs_enough_coins() -> void:
	assert_false(Shop.can_buy(Shop.ITEM_DAMAGE, 9, 0, 3, MAX_LIVES))
	assert_true(Shop.can_buy(Shop.ITEM_DAMAGE, 10, 0, 3, MAX_LIVES), "alcanza con el precio justo")
	assert_false(Shop.can_buy(Shop.ITEM_DAMAGE, 999, Shop.MAX_DAMAGE_BONUS, 3, MAX_LIVES), "tope alcanzado")
	assert_false(Shop.can_buy(Shop.ITEM_LIFE, 999, 0, 3, MAX_LIVES), "vidas completas")


func test_buying_damage_spends_coins_and_raises_the_bonus() -> void:
	var bought: Array = []
	_game.item_bought.connect(func(item: StringName, price: int) -> void: bought.append([item, price]))
	_game.add_coins(35)
	assert_true(_game.buy(Shop.ITEM_DAMAGE, MAX_LIVES))
	assert_eq(_game.damage_bonus, 1)
	assert_eq(_game.coins, 25)
	assert_true(_game.buy(Shop.ITEM_DAMAGE, MAX_LIVES))
	assert_eq(_game.damage_bonus, 2)
	assert_eq(_game.coins, 5)
	assert_eq(bought, [[Shop.ITEM_DAMAGE, 10], [Shop.ITEM_DAMAGE, 20]])


func test_buying_a_life_adds_one_up_to_the_cap() -> void:
	_game.lives = 1
	_game.add_coins(Shop.LIFE_PRICE * 3)
	assert_true(_game.buy(Shop.ITEM_LIFE, MAX_LIVES))
	assert_true(_game.buy(Shop.ITEM_LIFE, MAX_LIVES))
	assert_eq(_game.lives, 3)
	assert_false(_game.buy(Shop.ITEM_LIFE, MAX_LIVES), "no supera max_lives")
	assert_eq(_game.lives, 3)
	assert_eq(_game.coins, Shop.LIFE_PRICE, "la compra rechazada no cobra")


func test_failed_purchase_changes_nothing() -> void:
	var signals := [0]
	_game.coins_changed.connect(func(_coins: int) -> void: signals[0] += 1)
	_game.item_bought.connect(func(_item: StringName, _price: int) -> void: signals[0] += 1)
	_game.coins = 9
	assert_false(_game.buy(Shop.ITEM_DAMAGE, MAX_LIVES))
	assert_false(_game.buy(&"sword", MAX_LIVES))
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
