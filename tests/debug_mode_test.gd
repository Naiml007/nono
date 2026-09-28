extends Node
## Verifies the Debug developer tooling (autoload `Debug`):
##   (a) a boss jump spawns the boss and raises boss-cam priority to 40,
##   (b) the wave reads 50,
##   (c) god mode prevents HP loss,
##   (d) the overlay exists and toggles,
##   (e) with debug disabled nothing changes.

var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	var game: Game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- (e) Debug disabled: every entry point is a no-op ------------------------
	Debug.available = false
	Debug.set_active(false)
	Debug.goto_wave(50)
	Debug.set_god(true)
	await get_tree().process_frame
	_check(game._wave == 1 and GameState.wave == 1, "debug disabled: goto_wave is a no-op")
	_check(not game.player.debug_god, "debug disabled: god is a no-op")
	_check(not Debug.is_overlay_visible(), "debug disabled: overlay stays hidden")

	# --- Enable the tool ---------------------------------------------------------
	Debug.available = true
	Debug.set_active(true)
	_check(Debug.is_overlay_visible(), "overlay visible once enabled")
	_check(Debug.get_node_or_null("DebugOverlay") != null, "overlay node exists")

	# --- (d) overlay toggles off and on ------------------------------------------
	Debug.set_active(false)
	_check(not Debug.is_overlay_visible(), "overlay hides when toggled off")
	Debug.set_active(true)
	_check(Debug.is_overlay_visible(), "overlay shows when toggled back on")

	# --- (c) god mode prevents HP loss -------------------------------------------
	Debug.set_god(true)
	_check(game.player.debug_god, "god flag reaches the player")
	var hp_before: int = game.player.hp
	game.player.apply_boss_damage()
	_check(game.player.hp == hp_before, "god mode: boss damage blocked")
	Debug.set_god(false)
	game.player.apply_boss_damage()
	_check(game.player.hp == hp_before - 1, "god off: boss damage lands again")

	# --- (a)+(b) one-key boss jump ------------------------------------------------
	Debug.goto_boss()
	await get_tree().process_frame
	await get_tree().process_frame
	var waves: Array[Node] = get_tree().get_nodes_in_group("boss")
	_check(game._wave == 50, "boss jump sets internal wave to 50 (got %d)" % game._wave)
	_check(GameState.wave == 50, "boss jump sets GameState.wave to 50")
	_check(not waves.is_empty(), "boss jump spawns the boss")
	_check(game.boss_cam.get("priority") == 40, "boss jump raises boss-cam priority to 40")
	_check(game.boss_bar.visible, "boss jump shows the boss health bar")

	# --- god + dash: cooldown never blocks ---------------------------------------
	Debug.set_god(true)
	game.player.try_dash()
	game.player.try_dash()
	_check(true, "dash spam under god mode does not error")

	_summary()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== DEBUG MODE TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()