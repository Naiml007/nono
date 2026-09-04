extends Node
## Verifies coins spawned by the DebrisFieldSpawner land inside the arena
## (0..1280 x 0..720) and never at negative coordinates.

var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	var game: Node2D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	# Wait for wave 1 coins + boss-wave coins to scatter.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var coins: Array = get_tree().get_nodes_in_group("coins")
	print("coins found: ", coins.size())
	var out := 0
	var min_x := 1e9
	var min_y := 1e9
	var max_x := -1e9
	var max_y := -1e9
	for c in coins:
		var p: Vector2 = c.global_position
		min_x = mini(min_x, p.x)
		min_y = mini(min_y, p.y)
		max_x = maxi(max_x, p.x)
		max_y = maxi(max_y, p.y)
		if p.x < 0.0 or p.y < 0.0 or p.x > 1280.0 or p.y > 720.0:
			out += 1
			if out <= 5:
				print("  OFF-MAP coin at ", p)
	print("bounds: x[%.0f..%.0f] y[%.0f..%.0f]" % [min_x, max_x, min_y, max_y])
	_check(out == 0, "all coins inside arena (%d off-map)" % out)

	# Also test boss-wave scatter.
	game._start_boss_wave()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var coins2: Array = get_tree().get_nodes_in_group("coins")
	var out2 := 0
	for c in coins2:
		var p: Vector2 = c.global_position
		if p.x < 0.0 or p.y < 0.0 or p.x > 1280.0 or p.y > 720.0:
			out2 += 1
			if out2 <= 5:
				print("  OFF-MAP (boss wave) coin at ", p)
	_check(out2 == 0, "boss-wave coins inside arena (%d off-map)" % out2)

	_summary()
	get_tree().quit()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== COIN TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
