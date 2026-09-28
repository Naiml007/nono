extends Node
## Task 3 regression: _retry() must clear SceneTree.paused (and Engine.time_scale)
## BEFORE reload_current_scene(), otherwise the freshly loaded run never processes
## input or physics again — an unplayable, frozen-looking but dead screen.
##
## This exercises the real path: the tree is paused (and time frozen), then
## game._retry() reloads THIS scene. The post-reload _ready asserts the state was
## cleared. Phase is carried across the reload via autoload metadata.

var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	var phase: int = int(GameState.get_meta("retry_test_phase", 0))
	if phase == 0:
		GameState.set_meta("retry_test_phase", 1)
		var game: Node2D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
		add_child(game)
		await get_tree().process_frame
		# Simulate a retry from a paused / hit-stopped state.
		get_tree().paused = true
		Engine.time_scale = 0.0
		game._retry()  # reloads this scene
		return
	# Second boot, after the real reload.
	_check(not get_tree().paused, "retry leaves the tree unpaused (no frozen run)")
	_check(Engine.time_scale == 1.0, "retry resets Engine.time_scale to 1.0")
	GameState.remove_meta("retry_test_phase")
	_summary()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== RETRY TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()