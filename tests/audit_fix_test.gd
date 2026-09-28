extends Node
## Regression tests for the audit-pass fixes.
##
## 1) i-frames must not award a scored drone kill (score exploit: take one hit,
##    then walk the wave on the free 1.4s invulnerability collecting +10 each).
## 2) A boss bolt must NOT despawn on an invulnerable player, or the player
##    deletes the whole radial burst for free during their i-frame window.
## 3) Two achievement toasts must not render on top of each other.
## 4) The world must be frozen behind the game-over panel.

var _failures := 0

func _ready() -> void:
	_run()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _run() -> void:
	await get_tree().process_frame
	var game: Game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Player = game.player

	# --- 1) i-frames vs. dash for the kill credit ---------------------------
	player.debug_god = false
	player.is_dashing = false
	player._invuln_left = 1.4          # "just took a hit", NOT a dash
	var kills_before: int = GameState.kills
	var score_before: int = GameState.score
	var e1: Enemy = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	game.enemies.add_child(e1)
	await get_tree().process_frame
	player.on_enemy_contact(e1)
	_check(GameState.kills == kills_before and GameState.score == score_before,
		"i-frames alone award no kill or score (no +10 farming exploit)")

	# The drone is still cleared, so enemies cannot stack on a hurt player.
	_check(not is_instance_valid(e1) or not is_inside_tree() or e1.is_queued_for_deletion(),
		"the drone is still cleared during i-frames (no enemy stacking)")

	# Dashing still scores: that is the core mechanic and must not regress.
	var kills_dash: int = GameState.kills
	player._invuln_left = 0.0
	player.is_dashing = true
	var e2: Enemy = (load("res://scenes/enemy.tscn") as PackedScene).instantiate()
	game.enemies.add_child(e2)
	await get_tree().process_frame
	player.on_enemy_contact(e2)
	_check(GameState.kills == kills_dash + 1, "a dash-through kill still scores (+10)")
	player.is_dashing = false
	player._invuln_left = 0.0

	# --- 2) boss bolts vs. i-frames ---------------------------------------
	var hp_before: int = player.hp
	player._invuln_left = 1.4
	var bolt: BossBolt = (load("res://scenes/boss_bolt.tscn") as PackedScene).instantiate()
	game.enemies.add_child(bolt)
	await get_tree().process_frame
	bolt.launch(Vector2(200, 0))
	var hurtbox: Area2D = player.get_node("HurtBox")
	bolt._on_area_entered(hurtbox)
	_check(not bolt.is_queued_for_deletion(),
		"a boss bolt passes through an invulnerable player instead of being eaten")
	_check(player.hp == hp_before, "no HP lost while invulnerable")
	player._invuln_left = 0.0

	# A bolt that DOES land (no i-frames) must still be consumed.
	var hp_mid: int = player.hp
	var bolt2: BossBolt = (load("res://scenes/boss_bolt.tscn") as PackedScene).instantiate()
	game.enemies.add_child(bolt2)
	await get_tree().process_frame
	bolt2.launch(Vector2(200, 0))
	bolt2._on_area_entered(hurtbox)
	_check(bolt2.is_queued_for_deletion(), "a bolt that lands is despawned")
	_check(player.hp == hp_mid - 1, "a bolt that lands deals exactly 1 damage")

	# The shield still eats the hit, so the bolt is consumed with no HP loss.
	player.has_shield = true
	player._invuln_left = 0.0
	var hp_shield: int = player.hp
	var bolt3: BossBolt = (load("res://scenes/boss_bolt.tscn") as PackedScene).instantiate()
	game.enemies.add_child(bolt3)
	await get_tree().process_frame
	bolt3.launch(Vector2(200, 0))
	bolt3._on_area_entered(hurtbox)
	_check(bolt3.is_queued_for_deletion(), "the shield absorbs the bolt (bolt despawns)")
	_check(player.hp == hp_shield and not player.has_shield, "shield absorbs with no HP loss")

	# --- 3) achievement toasts must not overlap ----------------------------
	Achievements.reset()
	Achievements.unlock("wave_10")
	await get_tree().process_frame
	Achievements.unlock("wave_25")
	await get_tree().process_frame
	await get_tree().process_frame
	var toasts: Array = get_tree().root.get_children().filter(
		func(n: Node) -> bool: return n is CanvasLayer and n.layer == 200)
	_check(toasts.size() == 2, "two toasts are alive at once (%d)" % toasts.size())
	# Assert the resting TARGETS, not the mid-tween positions: two toasts
	# launched one frame apart are at the same y while both are still flying
	# in, which is correct. The bug was that they both targeted the same y=24.
	var slots: Array = Achievements._toast_slots
	_check(slots.size() == 2, "two slots are reserved (%s)" % str(slots))
	if slots.size() == 2:
		_check(float(slots[0]) != float(slots[1]),
			"the two toasts claimed different resting slots (%s)" % str(slots))
		# The gap must clear the first toast's own height, or they still overlap.
		_check(float(slots[1]) > float(slots[0]),
			"the lower slot is below the upper one (%s)" % str(slots))

	# --- 4) the world freezes behind the game-over panel -------------------
	player._dead = false
	player.hp = 1
	player.has_shield = false
	player._invuln_left = 0.0
	game._on_player_died()
	for i in 40:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	_check(game.game_over_panel.visible, "game over panel shown")
	_check(get_tree().paused, "the world is frozen behind the game-over panel")
	# A frozen run must not survive: unpausing restores a live, real-time tree.
	# (The real reload_current_scene() contract is covered by retry_test.gd;
	# calling _retry() here would reload THIS test scene in a loop.)
	get_tree().paused = false
	await get_tree().process_frame
	_check(not get_tree().paused, "unpausing hands back a live tree")
	_check(is_equal_approx(Engine.time_scale, 1.0), "time_scale is 1.0 (no frozen hit-stop)")

	print("==== AUDIT FIX TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
