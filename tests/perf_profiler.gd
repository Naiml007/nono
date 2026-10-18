extends Node
## Performance / lifecycle profiler for NONO.
##
## Isolated churn checks run first, followed by a continuous multi-wave sim that
## uses real enemy death, wave transitions, upgrade choices, and wave cleanup.
## Performance counters are observations only; this script does not claim an FPS
## improvement from them. Scene runs auto-start; run_tests gets one startup and
## waits for profile cleanup before reporting.

var _game: Game
var _sim_game: Game
var _failures: int = 0
var _wave_samples: Array[Dictionary] = []

var _sim_active: bool = false
var _sim_target: int = 11
var _last_sampled_wave: int = 0
var _pending_sample: int = 0
var _emitted_upgrade: bool = false
var _sim_timeout: float = 180.0
var _started: bool = false
var _profile_complete: bool = false
var _cleanup_complete: bool = false
var _cleanup_step: int = 0
var _scene_run: bool = false

signal _test_finished

func _ready() -> void:
	_scene_run = get_tree().current_scene == self
	if _scene_run:
		call_deferred("_start_scene_test")

func _start_scene_test() -> void:
	if _started:
		return
	_start_profile()

func _snapshot(tag: String) -> Dictionary:
	var snapshot: Dictionary = {
		"tag": tag,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draw": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	}
	print("[SNAP] %-28s objects=%-6d nodes=%-6d orphans=%-4d draw=%d" % [
		tag, snapshot["objects"], snapshot["nodes"], snapshot["orphans"], snapshot["draw"]])
	return snapshot

func _report(check_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] ", check_name, " ", detail)
	else:
		_failures += 1
		print("[FAIL] ", check_name, " ", detail)

## Entry point for run_tests; waits for the async profiling run and cleanup.
func test_profile() -> void:
	if not _started:
		_start_profile()
	if not _cleanup_complete:
		await _test_finished
	assert(_failures == 0, "Performance profiler found %d failure(s)" % _failures)

func _start_profile() -> void:
	if _started:
		return
	_started = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var packed: PackedScene = load("res://scenes/game.tscn") as PackedScene
	_game = packed.instantiate() as Game
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	# Keep the real initial wave alive while measuring synthetic churn. Invalidate
	# its delayed spawn callbacks and avoid creating a second full wave by hand.
	_game._wave_epoch += 1
	_game._alive_enemies = 999999
	_snapshot("baseline")
	_enemy_churn()
	await _bolt_churn()
	await _fx_churn()
	await _sfx_churn()

	# Drop the isolated-measurement world so the continuous run has clean groups
	# and a fresh FX owner.
	_game.queue_free()
	_game = null
	await get_tree().process_frame
	await get_tree().process_frame

	print("===== PROFILER: starting %d-wave continuous sim =====" % _sim_target)
	_sim_game = packed.instantiate() as Game
	add_child(_sim_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_sim_active = true
	_last_sampled_wave = _sim_game._wave
	_pending_sample = _sim_game._wave
	_sim_timeout = 180.0
	_drive_sim(0.0)

func _process(delta: float) -> void:
	if _cleanup_step > 0:
		_cleanup_step += 1
		if _cleanup_step >= 8:
			_cleanup_complete = true
			_test_finished.emit()
			if _scene_run:
				get_tree().quit()
			_cleanup_step = 0
		return
	if _sim_active:
		# Test-only acceleration: preserve gameplay transitions while reducing
		# the wall-clock time needed to sample 11 waves.
		Engine.time_scale = 5.0
		_drive_sim(delta)
		if not _profile_complete and is_instance_valid(_sim_game):
			_sim_game.player.hp = _sim_game.player.max_hp
			if _pending_sample != 0 and _sim_game._wave == _pending_sample \
					and _sim_game._alive_enemies <= 0:
				_record_pending_wave()
	elif is_instance_valid(_game):
		_auto_pick_upgrade(_game)

func _record_pending_wave() -> void:
	var sampled_wave: int = _pending_sample
	_pending_sample = 0
	var snapshot: Dictionary = _snapshot("wave %d" % sampled_wave)
	snapshot["coins"] = get_tree().get_nodes_in_group("coins").size()
	snapshot["powerups"] = get_tree().get_nodes_in_group("powerups").size()
	_wave_samples.append(snapshot)
	if sampled_wave >= _sim_target:
		_finish()

func _auto_pick_upgrade(game: Game) -> void:
	if not is_instance_valid(game):
		return
	if game.upgrade_panel.visible and get_tree().paused and not _emitted_upgrade:
		_emitted_upgrade = true
		game._on_upgrade_chosen("speed")
	elif not game.upgrade_panel.visible:
		_emitted_upgrade = false

func _drive_sim(delta: float) -> void:
	if not _sim_active or _profile_complete:
		return
	if not is_instance_valid(_sim_game):
		print("[FAIL] continuous sim lost its Game node")
		_finish()
		return
	if delta > 0.0:
		_sim_timeout -= delta
	if _sim_timeout <= 0.0:
		print("[FAIL] continuous sim timed out at wave %d" % _sim_game._wave)
		_finish()
		return

	# Keep the pilot alive and clear enemies through the real death handlers.
	# Avoid touching enemies on a paused upgrade screen; the wave starts after
	# _on_upgrade_chosen resumes the tree.
	_sim_game.player.hp = _sim_game.player.max_hp
	if not get_tree().paused and _sim_game._alive_enemies > 0:
		_sim_game.debug_kill_all_enemies()
	_auto_pick_upgrade(_sim_game)

	var current_wave: int = _sim_game._wave
	if current_wave != _last_sampled_wave:
		_last_sampled_wave = current_wave
		_pending_sample = current_wave

func _enemy_churn() -> void:
	print("===== SECTION 1b: enemy spawn/kill churn (wave-50 scale) =====")
	# The baseline's delayed spawn callbacks were invalidated before this batch.
	# The existing wave enemies are deliberately retained until the simulation
	# world is discarded; only this synthetic batch is checked for deferral.
	var before: Dictionary = _snapshot("enemies before")
	var spawned_enemies: Array[Enemy] = []
	for i: int in range(52):
		_game._spawn_enemy()
		var enemy: Enemy = _game.enemies.get_child(_game.enemies.get_child_count() - 1) as Enemy
		if enemy != null:
			spawned_enemies.append(enemy)
	var spawned: int = spawned_enemies.size()

	# Use die(false) to exercise the real removal signal and deferred-free path
	# without scoring; set a high alive count to suppress a wave transition.
	for enemy_to_kill: Enemy in spawned_enemies:
		enemy_to_kill.die(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var after: Dictionary = _snapshot("enemies after kill")
	var remaining_synthetic: int = 0
	for enemy_to_check: Enemy in spawned_enemies:
		if is_instance_valid(enemy_to_check) and enemy_to_check.is_inside_tree():
			remaining_synthetic += 1
	_report("enemy churn frees all spawned nodes", spawned == 52 and remaining_synthetic == 0,
		"spawned=%d remaining_synthetic=%d" % [spawned, remaining_synthetic])
	_report("no orphan growth from enemy churn", after["orphans"] - before["orphans"] <= 2,
		"orphans %d -> %d" % [before["orphans"], after["orphans"]])

func _bolt_churn() -> void:
	print("===== SECTION 1c: boss bolt churn (radial bursts) =====")
	_game._spawn_boss()
	await get_tree().process_frame
	await get_tree().process_frame
	var boss: Boss = null
	for child: Node in _game.enemies.get_children():
		if child is Boss:
			boss = child as Boss
			break
	if boss == null:
		_report("bolt churn boss spawn", false, "boss node missing")
		return

	var before: Dictionary = _snapshot("bolts before")
	for i: int in range(5):
		boss._fire_burst()
	var in_flight: int = get_tree().get_nodes_in_group("boss_bolts").size()
	print("[DATA] bolts in flight after 5 bursts: %d" % in_flight)
	boss.set_physics_process(false)
	# Boss bolts expire after 3 seconds; this timer runs on real time.
	await get_tree().create_timer(3.8).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var after: Dictionary = _snapshot("bolts after expiry")
	var remaining: int = get_tree().get_nodes_in_group("boss_bolts").size()
	_report("boss bolts free on expiry", in_flight == 40 and remaining == 0,
		"in_flight=%d remaining=%d" % [in_flight, remaining])
	_report("no orphan growth from bolt churn", after["orphans"] - before["orphans"] <= 2,
		"orphans %d -> %d" % [before["orphans"], after["orphans"]])

func _fx_churn() -> void:
	print("===== SECTION 1d: Fx particle/popup churn =====")
	await get_tree().create_timer(0.4).timeout
	var before: Dictionary = _snapshot("fx before")
	for i: int in range(40):
		Fx.burst(Vector2(100.0 + i, 200.0), Color.WHITE, 12, 200.0, 0.4, 1.0)
		Fx.popup(Vector2(100.0 + i, 300.0), "+1", Color.WHITE, 18)
		Fx.ring(Vector2(100.0 + i, 200.0), Color.CYAN, 24.0, 2.0, 0.2)
		Fx.flash(Vector2(100.0 + i, 200.0), Color.CYAN, 0.5, 0.1)
		Fx.screen_flash(Color.CYAN, 0.05, 0.1)
	await get_tree().create_timer(1.6).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var after: Dictionary = _snapshot("fx after cleanup")
	var orphan_delta: int = int(after["orphans"]) - int(before["orphans"])
	var node_delta: int = int(after["nodes"]) - int(before["nodes"])
	print("[VFX PERF] caps particles=%d lines=%d sprites=%d screens=%d; active post-cleanup particles=%d lines=%d sprites=%d overlays=%d; node_delta=%d draw=%d" % [
		Fx.MAX_PARTICLE_POOL, Fx.MAX_LINE_POOL, Fx.MAX_SPRITE_POOL, Fx.MAX_SCREEN_POOL,
		Fx._active_particles.size(), Fx._active_lines.size(), Fx._active_sprites.size(), Fx._active_screens.size(),
		node_delta, after["draw"]])
	_report("Fx pooled nodes stay bounded after cleanup", node_delta <= 124,
		"nodes %d -> %d (delta %d; particle24+popup32+line16+sprite48+screen4 caps)" % [before["nodes"], after["nodes"], node_delta])
	_report("Fx leaves no orphan nodes", orphan_delta <= 2,
		"orphans %d -> %d" % [before["orphans"], after["orphans"]])
	var active_particles: int = Fx._active_particles.size()
	var active_lines: int = Fx._active_lines.size()
	var active_sprites: int = Fx._active_sprites.size()
	var active_screens: int = Fx._active_screens.size()
	_report("Fx active lists stay within their caps",
		active_particles <= Fx.MAX_PARTICLE_POOL and active_lines <= Fx.MAX_LINE_POOL
		and active_sprites <= Fx.MAX_SPRITE_POOL and active_screens <= Fx.MAX_SCREEN_POOL,
		"particles=%d lines=%d sprites=%d screens=%d" % [
			Fx._active_particles.size(), Fx._active_lines.size(), Fx._active_sprites.size(), Fx._active_screens.size()])

func _sfx_churn() -> void:
	print("===== SECTION 1e: Sfx one-shot player churn =====")
	await get_tree().create_timer(0.4).timeout
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx == null:
		_report("Sfx autoload present", false)
		return
	var before: int = sfx.get_child_count()
	for i: int in range(40):
		Sfx.play("explode", randf_range(0.9, 1.1))
	await get_tree().create_timer(1.3).timeout
	await get_tree().process_frame
	var after: int = sfx.get_child_count()
	_report("Sfx one-shot players free", after <= before + 1,
		"Sfx children %d -> %d" % [before, after])

func _finish() -> void:
	if _profile_complete:
		return
	_sim_active = false
	Engine.time_scale = 1.0
	var samples_complete: bool = _wave_samples.size() >= _sim_target
	_report("continuous sim reaches target wave", samples_complete,
		"samples=%d target=%d reached_wave=%d" % [
			_wave_samples.size(), _sim_target, _sim_game._wave if is_instance_valid(_sim_game) else -1])

	var powerup_counts: Array[int] = []
	var powerup_max: int = 0
	for sample: Dictionary in _wave_samples:
		var count: int = int(sample.get("powerups", 0))
		powerup_counts.append(count)
		powerup_max = maxi(powerup_max, count)
	if not powerup_counts.is_empty():
		_report("powerups do not accumulate across waves", powerup_max <= 8,
			"max=%d per-wave=%s" % [powerup_max, str(powerup_counts)])

	print("===== PROFILER SUMMARY: failures=%d =====" % _failures)
	for sample: Dictionary in _wave_samples:
		print("  [WAVE] %-28s nodes=%-6d orphans=%d coins=%d powerups=%d" % [
			sample["tag"], sample["nodes"], sample["orphans"],
			sample.get("coins", -1), sample.get("powerups", -1)])

	_profile_complete = true
	if is_instance_valid(_sim_game):
		_sim_game.queue_free()
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_cleanup_after_finish()

func _cleanup_after_finish() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_sim_game = null
	_cleanup_step = 1
