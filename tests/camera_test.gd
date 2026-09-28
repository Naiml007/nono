extends Node
## Camera verification for the Phantom Camera setup.
##
## Two things are covered:
##  1. The priority-based zoom switch (player cam 1.0 <-> boss cam 1.2 at 16:9).
##  2. The camera-bounds invariant: for a matrix of viewport sizes and for both
##     the wave-1 (player) and wave-50 (boss) camera, the camera's visible world
##     rect must stay INSIDE Rect2(0, 0, 1280, 720). Before the min-zoom floor
##     this failed on any non-16:9 viewport (void above/below the arena).
##
## NOTE: resizing the root viewport only takes effect once real PHYSICS frames
## tick (idle frames do not move the camera), so every change waits on
## `physics_frame`. Headless boots with a square 1280x1280 viewport, so the
## 16:9 base checks pin the size explicitly.

const ARENA := Rect2(0, 0, 1280, 720)
const SETTLE_FRAMES := 70   # > the 1.0s PhantomCamera tween at 60 Hz

var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	var game: Game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera2D = game.get_node("Camera")
	var host: Node = game.get_node("Camera/PhantomCameraHost")

	# --- Base zoom switch at a true 16:9 viewport ---------------------------------
	get_tree().root.size = Vector2i(1280, 720)
	await _physics_wait(SETTLE_FRAMES)
	var active: Node = host.get("_active_pcam_2d")
	_check(active == game.player_cam, "player cam active at start")
	_check((cam.zoom - Vector2.ONE).length() < 0.05,
		"player camera zoom is 1.0 at 16:9 (got %.3f)" % cam.zoom.x)

	# Raise boss cam priority -> boss cam active, zoom tweens to 1.2.
	game.boss_cam.set("priority", 40)
	await _physics_wait(SETTLE_FRAMES)
	active = host.get("_active_pcam_2d")
	_check(active == game.boss_cam, "boss cam active when priority raised")
	_check((cam.zoom - Vector2(1.2, 1.2)).length() < 0.05,
		"camera zoom reaches 1.2 with boss cam (got %.3f)" % cam.zoom.x)

	# Lower boss priority -> back to player cam, zoom tweens back to 1.0.
	game.boss_cam.set("priority", 0)
	await _physics_wait(SETTLE_FRAMES)
	active = host.get("_active_pcam_2d")
	_check(active == game.player_cam, "player cam active again after boss priority reset")
	_check((cam.zoom - Vector2.ONE).length() < 0.05,
		"camera zoom back to 1.0 (got %.3f)" % cam.zoom.x)

	# --- Containment matrix: visible world rect must stay inside the arena -------
	var sizes: Array[Vector2i] = [
		Vector2i(1280, 720), Vector2i(1280, 1024),
		Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1280, 1600)]
	for size: Vector2i in sizes:
		get_tree().root.size = size
		await _physics_wait(10)

		# Wave 1: player cam.
		game.debug_goto_wave(1)
		game._reset_boss_cam()
		await _physics_wait(SETTLE_FRAMES)
		var limits_ok := cam.limit_left == 0 and cam.limit_top == 0 \
				and cam.limit_right == 1280 and cam.limit_bottom == 720
		_check(limits_ok, "host limits pinned to arena @ %s (got %d/%d/%d/%d)" % [
			size, cam.limit_left, cam.limit_top, cam.limit_right, cam.limit_bottom])
		_check_inside(cam, "wave 1", size)

		# Wave 50: boss cam (debug_goto_wave(50) routes through _start_boss_wave,
		# which raises boss-cam priority to 40 and spawns the boss).
		game.debug_goto_wave(50)
		await _physics_wait(SETTLE_FRAMES)
		_check_inside(cam, "wave 50", size)

	_summary()

func _check_inside(cam: Camera2D, label: String, size: Vector2i) -> void:
	var half: Vector2 = get_viewport().get_visible_rect().size / (cam.zoom * 2.0)
	var rect := Rect2(cam.get_screen_center_position() - half, half * 2.0)
	print("  %s @ %s: zoom=%.3f view=(%.1f,%.1f)-(%.1f,%.1f)" % [
		label, size, cam.zoom.x, rect.position.x, rect.position.y, rect.end.x, rect.end.y])
	_check(ARENA.encloses(rect), "visible rect inside arena: %s @ %s" % [label, size])

func _physics_wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== CAMERA TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
