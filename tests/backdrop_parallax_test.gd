extends Node
## Verifies the layered parallax response and that reduced-motion freezes it.

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
	_run_backdrop_parallax()

func test_backdrop_parallax() -> void:
	if not _started:
		_started = true
		_run_backdrop_parallax()
	if not _finished:
		await _test_finished
	assert(_failures == 0, "Backdrop parallax regression checks found %d failure(s)" % _failures)

func _run_backdrop_parallax() -> void:
	await get_tree().process_frame
	var previous_reduce_motion: bool = GameState.reduce_motion
	GameState.set_reduce_motion(false)
	var packed_game: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var game: Game = packed_game.instantiate() as Game
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var backdrop: SpaceBackdrop = game.get_node("SpaceBackdrop") as SpaceBackdrop
	var far_material: ShaderMaterial = backdrop.get_node("Background/DistantStars").material as ShaderMaterial
	var near_material: ShaderMaterial = backdrop.get_node("Background/NearStars").material as ShaderMaterial
	var far_origin: Vector2 = far_material.get_shader_parameter("parallax_uv_offset")
	var near_origin: Vector2 = near_material.get_shader_parameter("parallax_uv_offset")
	var plate_origin: Vector2 = backdrop.base_plate.position
	var far_layer_origin: Vector2 = backdrop.get_node("Background/DistantStars").position
	var near_layer_origin: Vector2 = backdrop.get_node("Background/NearStars").position
	_check(backdrop.is_processing(), "gameplay backdrop processes while parallax motion is enabled")

	game.player.global_position = Vector2(1180.0, 580.0)
	backdrop._process(1.0)
	var far_offset: Vector2 = far_material.get_shader_parameter("parallax_uv_offset")
	var near_offset: Vector2 = near_material.get_shader_parameter("parallax_uv_offset")
	_check(backdrop.base_plate.position != plate_origin, "authored space plate shifts with player movement")
	_check(backdrop.base_plate.position.distance_to(plate_origin) > 1.0,
		"authored plate parallax is visibly more than one pixel")
	_check(backdrop.base_plate.material == null,
		"authored plate is sampled directly without a replacement shader")
	_check(backdrop.get_node("Background/DistantStars").position.distance_to(far_layer_origin) > 1.0,
		"distant star plane visibly shifts with player movement")
	_check(backdrop.get_node("Background/NearStars").position.distance_to(near_layer_origin) > 1.0,
		"near star plane visibly shifts with player movement")
	_check(backdrop.get_node("Background/NearStars").position.distance_to(near_layer_origin) > backdrop.get_node("Background/DistantStars").position.distance_to(far_layer_origin),
		"near star plane shifts more than the distant plane")
	_check(far_offset != far_origin, "distant star field shifts with player movement")
	_check(near_offset != near_origin, "near star field shifts with player movement")
	_check(far_offset.distance_to(far_origin) < near_offset.distance_to(near_origin),
		"near star layer has stronger parallax than the distant layer")
	_check(near_offset.distance_to(near_origin) > 0.01,
		"near star parallax is visible in the procedural field")

	GameState.set_reduce_motion(true)
	_check(backdrop._parallax_amount == Vector2.ZERO,
		"enabling reduced motion immediately resets reactive parallax")
	await get_tree().process_frame
	var frozen_plate_position: Vector2 = backdrop.base_plate.position
	var frozen_far_position: Vector2 = backdrop.get_node("Background/DistantStars").position
	var frozen_near_position: Vector2 = backdrop.get_node("Background/NearStars").position
	var frozen_far_offset: Vector2 = far_material.get_shader_parameter("parallax_uv_offset")
	var frozen_near_offset: Vector2 = near_material.get_shader_parameter("parallax_uv_offset")
	_check(not backdrop.is_processing(), "reduced motion disables gameplay parallax processing")
	_check(is_zero_approx(far_material.get_shader_parameter("motion_scale")), "reduced motion freezes procedural star drift")
	game.player.global_position = Vector2(160.0, 100.0)
	await _process_wait(8)
	_check(backdrop.base_plate.position == frozen_plate_position,
		"reduced motion keeps the plate fixed when the player moves")
	_check(backdrop.get_node("Background/DistantStars").position == frozen_far_position,
		"reduced motion keeps distant star plane fixed")
	_check(backdrop.get_node("Background/NearStars").position == frozen_near_position,
		"reduced motion keeps near star plane fixed")
	_check(far_material.get_shader_parameter("parallax_uv_offset") == frozen_far_offset,
		"reduced motion keeps the distant stars fixed")
	_check(near_material.get_shader_parameter("parallax_uv_offset") == frozen_near_offset,
		"reduced motion keeps the near stars fixed")

	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Fx.setup(null, null)
	await get_tree().process_frame
	GameState.set_reduce_motion(previous_reduce_motion)
	print("==== BACKDROP PARALLAX TEST SUMMARY: failures=%d ====" % _failures)
	_finished = true
	_test_finished.emit()
	if _failures > 0:
		assert(false, "Backdrop parallax regression checks found %d failure(s)" % _failures)
	if get_tree().current_scene == self:
		get_tree().quit()

func _process_wait(frames: int) -> void:
	for _frame: int in frames:
		await get_tree().process_frame

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		_failures += 1
		print("FAIL: ", message)
