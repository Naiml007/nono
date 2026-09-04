extends Node
## Headless camera verification for the Phantom Camera setup.
## The arena is exactly one viewport (1280x720), so camera limits clamp the
## follow position to (640,360) - the observable behavior is the priority-based
## zoom switch between the player cam (1.0) and the boss cam (1.2).

var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	var game: Node2D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var cam: Camera2D = game.get_node("Camera")
	var host: Node = game.get_node("Camera/PhantomCameraHost")
	var player_cam: Node = game.get_node("PlayerCam")
	var boss_cam: Node = game.get_node("BossCam")

	var active: Node = host.get("_active_pcam_2d")
	_check(active == player_cam, "player cam active at start")

	# Raise boss cam priority -> boss cam active, zoom tweens to 1.2.
	boss_cam.set("priority", 40)
	for i in 180:
		await get_tree().process_frame
	active = host.get("_active_pcam_2d")
	print("active after boss priority: ", active, " cam zoom: ", cam.zoom)
	_check(active == boss_cam, "boss cam active when priority raised")
	_check((cam.zoom - Vector2(1.2, 1.2)).length() < 0.05, "camera zoom reaches 1.2 with boss cam (got %.3f)" % cam.zoom.x)

	# Lower boss priority -> back to player cam, zoom tweens back to 1.0.
	boss_cam.set("priority", 0)
	for i in 180:
		await get_tree().process_frame
	active = host.get("_active_pcam_2d")
	print("active after reset: ", active, " cam zoom: ", cam.zoom)
	_check(active == player_cam, "player cam active again after boss priority reset")
	_check((cam.zoom - Vector2.ONE).length() < 0.05, "camera zoom back to 1.0 (got %.3f)" % cam.zoom.x)

	_summary()
	get_tree().quit()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== CAMERA TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
