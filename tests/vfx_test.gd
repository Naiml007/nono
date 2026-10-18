extends Node
## Regression coverage for Fx real-time lifetime, pool bounds, and arena clamping.

var _failures: int = 0
var _game: Node2D
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
	_run_vfx_effect_lifecycle()

func test_vfx_effect_lifecycle() -> void:
	if not _started:
		_started = true
		_run_vfx_effect_lifecycle()
	if not _finished:
		await _test_finished
	assert(_failures == 0, "VFX lifecycle regression checks found %d failure(s)" % _failures)

func _run_vfx_effect_lifecycle() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var packed: PackedScene = load("res://scenes/game.tscn") as PackedScene
	_game = packed.instantiate() as Node2D
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame
	var base_nodes: int = _game.get_child_count()
	Fx.ring(Vector2(-200.0, 900.0), Color.CYAN, 30.0, 2.0, 0.05)
	Fx.aim_line(Vector2(10.0, 10.0), Vector2(400.0, 400.0), Color.RED, 0.05)
	Fx.burst(Vector2(-100.0, 800.0), Color.CYAN, 4, 100.0, 0.05, 1.0)
	Fx.debris(Vector2(600.0, 300.0), Color.ORANGE, 4, 100.0, 0.05)
	Fx.popup(Vector2(600.0, 300.0), "TEST", Color.WHITE, 18)
	Fx.flash(Vector2(600.0, 300.0), Color.CYAN, 0.5, 0.05)
	Fx.screen_flash(Color.RED, 0.2, 0.05)
	Fx.zoom_punch(0.03, 0.05)
	Fx.slowmo(0.4, 0.06)
	_check(Engine.time_scale < 1.0, "slowmo immediately scales game time")
	await create_timer_real(1.0)
	_check(is_equal_approx(Engine.time_scale, 1.0), "slowmo restores using real elapsed time")
	_check(_game != null and is_instance_valid(_game) and _game.get_child_count() <= base_nodes + 20, "effects stay within pooled node budget")
	_check(Fx._active_lines.is_empty(), "ring and line retire without scene-tree timers")
	_check(Fx._active_popups.is_empty(), "popup retires after real-time duration")
	_check(Fx._active_screens.is_empty(), "screen flash retires after real-time duration")
	_check(Fx._active_particles.is_empty(), "particle bursts recycle after lifetime")
	_check(Fx._screen_allocated <= 4, "screen overlay cap is four")
	_check(Fx._sprite_allocated <= 48, "sprite pool cap is fixed")
	_check(Fx._particle_allocated <= 24, "particle pool cap is fixed")
	# Simulate a pooled node being freed by external scene code. Acquisition must
	# discard it safely rather than assigning a freed object to a typed variable.
	if not Fx._particle_pool.is_empty():
		var stale_particle: Variant = Fx._particle_pool.back()
		stale_particle.free()
		var recovered_particle: CPUParticles2D = Fx._particle_effect(
			Vector2(320.0, 240.0), Color.WHITE, 2, 80.0, 0.05, 1.0,
			Vector2.UP, 180.0, false)
		_check(is_instance_valid(recovered_particle), "freed pooled particle is discarded and replaced safely")
		_check(Fx._particle_allocated == Fx._particle_pool.size() + Fx._active_particles.size(),
			"particle allocation count remains consistent after stale pool recovery")
	else:
		_check(false, "particle pool contains a node for stale-reference regression")
	# External scene cleanup must not leave stale typed-array references; all
	# pooled children disappear with their owning game world.
	_game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_game = null
	_check(Fx._particle_pool.is_empty(), "world replacement clears pooled particle references")
	_check(Fx._active_particles.is_empty(), "world replacement clears active particle references")
	_check(Fx._line_pool.is_empty(), "world replacement clears pooled line references")
	_check(Fx._active_lines.is_empty(), "world replacement clears active line references")
	_check(Fx._popup_pool.is_empty(), "world replacement clears pooled popup references")
	_check(Fx._sprite_pool.is_empty(), "world replacement clears pooled sprite references")
	_check(Fx._screen_pool.is_empty(), "world replacement clears pooled screen references")
	await get_tree().process_frame
	Fx.setup(null, null)
	_game = null
	await get_tree().process_frame
	await get_tree().process_frame
	if get_tree().current_scene == self:
		get_tree().quit()
	print("==== VFX TEST SUMMARY: failures=%d ====" % _failures)
	_finished = true
	_test_finished.emit()

func create_timer_real(seconds: float) -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(seconds, true, false, true)
	await timer.timeout

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		_failures += 1
		print("FAIL: ", message)
