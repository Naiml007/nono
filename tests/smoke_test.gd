extends Node
## End-to-end smoke test: boot a fresh run, advance through normal waves and
## the wave milestone, reach the wave-50 boss, kill it, die to the boss, and
## verify the game-over panel shows score + best and a retry starts clean.
## Mirrors the "wave 1 -> 50 -> game over" flow without running the full 1s
## real-time path; user files are snapshotted/restored.

var _failures := 0
var _backup: Dictionary = {}

func _ready() -> void:
	_backup = UserFilesHelper.snapshot()
	await get_tree().process_frame
	var game: Node2D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- Fresh run boots at wave 1 ---
	_check(game._wave == 1, "run starts at wave 1")
	_check(not game._game_over, "not game over at start")
	_check(GameState.score == 0, "score starts at 0")

	# --- Normal wave progression (entry path, no upgrade pause) ---
	game._start_wave(2)
	await get_tree().process_frame
	_check(game._wave == 2 and GameState.wave == 2, "advanced to wave 2")
	_check(game._enemy_count_for_wave(2) == 4, "wave 2 spawns 4 drones")

	# --- Wave milestones unlock achievements ---
	game._start_wave(10)
	await get_tree().process_frame
	_check(Achievements.is_unlocked("wave_10"), "wave 10 unlocks Marathoner")

	# --- Late-wave enemy count is capped (readable but hard) ---
	_check(game._enemy_count_for_wave(30) <= 24, "wave 30 drone count capped at 24")

	# --- Boss wave ---
	game._start_boss_wave()
	await get_tree().process_frame
	await get_tree().process_frame
	var boss: Boss = null
	for child in game.get_node("Enemies").get_children():
		if child is Boss:
			boss = child
			break
	_check(boss != null, "wave 50 boss spawned")
	if boss == null:
		UserFilesHelper.restore(_backup)
		_summary()
		return
	_check(game.boss_bar.visible, "boss healthbar shown")

	# --- Kill boss: +500, bar/cam reset, untouchable achievement on a clean wave ---
	var score_before: int = GameState.score
	boss.take_damage(boss.hp, 1)
	_check(GameState.score - score_before == 500, "boss kill grants +500")
	_check(not game.boss_bar.visible, "boss healthbar hidden after death")
	_check(game.boss_cam.get("priority") == 0, "boss cam priority reset")
	_check(Achievements.is_unlocked("untouchable"), "clean boss wave unlocks Untouchable")

	# --- Player dies to the boss -> game over panel shows score + best ---
	game.player._dead = false
	game.player.hp = 1
	game.player._invuln_left = 0.0
	# Task 9: dying while the boss camera is active must reset it.
	game.boss_cam.set("priority", 40)
	game.player.apply_boss_damage()
	_check(game._game_over, "player death sets game over")
	_check(game.boss_cam.get("priority") == 0, "boss cam reset to player cam on death during boss fight")
	_check(Engine.time_scale == 0.0, "hit-stop freezes time on player death")
	await get_tree().create_timer(0.6).timeout  # freeze is 0.28s real, then recovers
	_check(Engine.time_scale == 1.0, "hit-stop restores time_scale")
	for i in 30:
		await get_tree().process_frame  # ~0.5s; _on_player_died waits 0.8s real
	await get_tree().create_timer(0.9).timeout
	_check(game.game_over_panel.visible, "game over panel shown")
	_check(("Score: %d" % GameState.score) == game.final_score.text, "final score label populated")
	_check(game.final_best.text.begins_with("Best:"), "final best label populated")
	_check(GameState.best_score >= GameState.score, "best score saved on death")

	# --- Retry semantics: _ready() calls reset_run() so a reload is clean ---
	GameState.reset_run()
	_check(GameState.score == 0 and GameState.kills == 0 and GameState.wave == 0,
		"retry resets run state (score/kills/wave)")

	# --- Menu unpauses and switches cleanly ---
	game._set_paused(false)
	_check(not get_tree().paused, "menu path unpauses")

	# --- Task 8: a hitstop overlapping a pause still restores time_scale ---
	# Fx runs with PROCESS_MODE_ALWAYS, so its restore fires even while paused;
	# without that guard time_scale would stay 0 and freeze the game forever.
	Fx.hitstop(0.25)
	get_tree().paused = true
	await get_tree().create_timer(0.6).timeout
	_check(Engine.time_scale == 1.0, "time_scale restored even while the tree is paused (hitstop + pause)")
	get_tree().paused = false

	UserFilesHelper.restore(_backup)
	_summary()
	get_tree().quit()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== SMOKE TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
