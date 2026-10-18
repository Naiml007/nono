extends Node
## Regression coverage for magnet movement and its squared-distance range checks.

var _failures: int = 0
var _started: bool = false
var _finished: bool = false

signal _test_finished

func _ready() -> void:
	if get_tree().current_scene == self:
		call_deferred("_start_scene_test")

func _start_scene_test() -> void:
	if _started:
		return
	_started = true
	_run_magnet_squared_distance()

func test_magnet_squared_distance() -> void:
	if not _started:
		_started = true
		_run_magnet_squared_distance()
	if not _finished:
		await _test_finished
	assert(_failures == 0, "Magnet regression checks found %d failure(s)" % _failures)

func _run_magnet_squared_distance() -> void:
	var packed: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var game: Game = packed.instantiate() as Game
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	for coin: Coin in game._coins:
		if is_instance_valid(coin):
			coin.queue_free()
	game._coins.clear()
	await get_tree().process_frame

	var target: Vector2 = Vector2(640.0, 360.0)
	game.player.global_position = target
	game.player.magnet_radius = 100.0
	game.player.magnet_left = 1.0
	game._coins.clear()

	var coin_packed: PackedScene = load("res://scenes/coin.tscn") as PackedScene
	var near_coin: Coin = coin_packed.instantiate() as Coin
	near_coin.global_position = target + Vector2(80.0, 0.0)
	game.add_child(near_coin)
	var boundary_coin: Coin = coin_packed.instantiate() as Coin
	boundary_coin.global_position = target + Vector2(100.0, 0.0)
	game.add_child(boundary_coin)
	var close_coin: Coin = coin_packed.instantiate() as Coin
	close_coin.global_position = target + Vector2(1.0, 0.0)
	game.add_child(close_coin)
	var far_coin: Coin = coin_packed.instantiate() as Coin
	far_coin.global_position = target + Vector2(101.0, 0.0)
	game.add_child(far_coin)
	game._coins.append(near_coin)
	game._coins.append(boundary_coin)
	game._coins.append(close_coin)
	game._coins.append(far_coin)

	game._tick_magnet(0.1)
	_check(is_equal_approx(near_coin.global_position.distance_to(target), 16.0),
		"coin strictly inside magnet radius moves at the existing pull speed")
	_check(boundary_coin.global_position == target + Vector2(100.0, 0.0),
		"coin exactly at magnet radius remains outside (strict boundary preserved)")
	_check(close_coin.global_position == target + Vector2(1.0, 0.0),
		"coin at the one-pixel dead zone is not pulled")
	_check(far_coin.global_position == target + Vector2(101.0, 0.0),
		"coin outside magnet radius is not pulled")

	near_coin.queue_free()
	boundary_coin.queue_free()
	close_coin.queue_free()
	far_coin.queue_free()
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if get_tree().current_scene == self:
		get_tree().quit()
	print("==== MAGNET TEST SUMMARY: failures=%d ====" % _failures)
	_finished = true
	_test_finished.emit()

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		_failures += 1
		print("FAIL: ", message)
