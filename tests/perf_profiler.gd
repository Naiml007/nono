extends Node
## Performance / memory-leak profiler for the NONO audit.
##
## Measures live Performance monitors (objects, nodes, orphan nodes) around the
## suspected leak points, then runs a 10+ wave continuous sim and records the
## per-wave trend. Prints a [SECTION] line per measurement so before/after runs
## can be diffed.
##
## Run via run_tests on this file (headless: no draw calls) OR by running the
## matching perf_profiler.tscn in the editor/Game tab (real render -> draw calls).

var _game: Node2D
var _sim_game: Node2D
var _failures := 0

# Wave-sim driver state.
var _sim_active := false
var _sim_target := 11
var _last_sampled_wave := 0
var _pending_sample := 0
var _emitted_upgrade := false
var _sim_timeout := 0.0
var _wave_samples: Array[Dictionary] = []

const M_OBJECT := "OBJECT_COUNT"
const M_NODES := "OBJECT_NODE_COUNT"
const M_ORPHAN := "OBJECT_ORPHAN_NODE_COUNT"
const M_DRAW := "RENDER_TOTAL_DRAW_CALLS_IN_FRAME"

func _snapshot(tag: String) -> Dictionary:
	var s := {
		"tag": tag,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draw": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	}
	print("[SNAP] %-28s objects=%-6d nodes=%-6d orphans=%-4d draw=%d" % [
		tag, s["objects"], s["nodes"], s["orphans"], s["draw"]])
	return s

func _report(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] ", name, " ", detail)
	else:
		_failures += 1
		print("[FAIL] ", name, " ", detail)

var _started := false

func _ready() -> void:
	_start_profile()

## Entry point for Ziva's run_tests (which invokes test_* methods).
func test_profile() -> void:
	_start_profile()

func _start_profile() -> void:
	if _started:
		return
	_started = true
	# Keep driving while the wave-clear upgrade panel pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var packed := load("res://scenes/game.tscn") as PackedScene
	_game = packed.instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	print("===== PROFILER: game booted, wave=%d =====" % _game._wave)
	# Freeze this game's wave flow for the isolated section tests: keep
	# _alive_enemies high so wave-advance (and its extra coin scatters /
	# upgrade-pause) never fires mid-measurement.
	_game._alive_enemies = 999999
	_snapshot("baseline")

	await _enemy_churn()
	await _bolt_churn()
	await _fx_churn()
	await _sfx_churn()

	# Start the continuous 10+ wave sim on a FRESH game instance (wave 1 -> N),
	# isolated from the section tests' residual coins/enemies. Drop the section
	# game first so its coins don't pollute the sim's per-wave coin counts.
	print("===== PROFILER: starting %d-wave continuous sim =====" % _sim_target)
	_game.queue_free()
	_game = null
	await get_tree().process_frame
	await get_tree().process_frame
	_sim_game = packed.instantiate()
	add_child(_sim_game)
	await get_tree().process_frame
	await get_tree().process_frame
	_sim_active = true
	_last_sampled_wave = 0
	_pending_sample = 0
	_sim_timeout = 300.0

func _process(delta: float) -> void:
	if _sim_active:
		_drive_sim(delta)
	else:
		# During the section tests, keep the booted game from sitting paused on
		# the wave-clear upgrade panel (a paused tree freezes audio/timers and
		# would corrupt the sfx/fx measurements).
		_auto_pick_upgrade(_game)

func _auto_pick_upgrade(g: Node2D) -> void:
	if g == null or not is_instance_valid(g):
		return
	if g.upgrade_panel.visible and get_tree().paused and not _emitted_upgrade:
		_emitted_upgrade = true
		g.upgrade_chosen.emit("speed")
	if not g.upgrade_panel.visible:
		_emitted_upgrade = false

func _drive_sim(delta: float) -> void:
	if _sim_game == null or not is_instance_valid(_sim_game):
		print("[FAIL] wave sim lost game node")
		_finish()
		return
	_sim_timeout -= delta
	if _sim_timeout <= 0.0:
		print("[FAIL] wave sim timed out (reached wave %d)" % _sim_game._wave)
		_finish()
		return
	# Keep the pilot alive so death can never stall the run.
	_sim_game.player.hp = _sim_game.player.max_hp
	# Aggressively clear the field so waves progress as fast as real play allows.
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and is_instance_valid(e) and not e._dead:
			e.die(true)
	for node in get_tree().get_nodes_in_group("boss"):
		var b := node as Boss
		if b != null and is_instance_valid(b) and not b._dead:
			b.take_damage(999, 1)
	_auto_pick_upgrade(_sim_game)
	# Sample whenever the wave counter advances (settle one frame so deferred
	# queue_frees from wave-start cleanup have been processed).
	var w: int = _sim_game._wave
	if w != _last_sampled_wave and w >= 1:
		if _pending_sample != 0:
			var sampled: int = _pending_sample
			_pending_sample = 0
			_last_sampled_wave = sampled
			var snap := _snapshot("wave %d" % sampled)
			snap["coins"] = get_tree().get_nodes_in_group("coins").size()
			_wave_samples.append(snap)
			if sampled >= _sim_target:
				_finish()
		else:
			_pending_sample = w

func _enemy_churn() -> void:
	print("===== SECTION 1b: enemy spawn/kill churn (wave-50 scale) =====")
	var before := _snapshot("enemies before")
	for i in 52:
		_game._spawn_enemy()
	await get_tree().process_frame
	await get_tree().process_frame
	var spawned: int = get_tree().get_nodes_in_group("enemies").size()
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and is_instance_valid(e):
			e.die(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var after := _snapshot("enemies after kill")
	var remaining: int = get_tree().get_nodes_in_group("enemies").size()
	_report("enemies free on death", remaining == 0, "spawned=%d remaining=%d" % [spawned, remaining])
	_report("no orphan growth from enemy churn",
		after["orphans"] - before["orphans"] <= 2,
		"orphans %d -> %d" % [before["orphans"], after["orphans"]])

func _bolt_churn() -> void:
	print("===== SECTION 1c: boss bolt churn (radial bursts) =====")
	_game._spawn_boss()
	await get_tree().process_frame
	await get_tree().process_frame
	var boss: Boss = null
	for child in _game.get_node("Enemies").get_children():
		if child is Boss:
			boss = child
			break
	if boss == null:
		_report("bolt churn: boss spawned", false)
		return
	var before := _snapshot("bolts before")
	for i in 5:
		boss._fire_burst()
	var in_flight: int = get_tree().get_nodes_in_group("boss_bolts").size()
	print("[DATA] bolts in flight after 5 bursts: %d" % in_flight)
	# Stop the boss's own AI so it can't fire fresh bursts during the wait
	# (which would look like non-expiring bolts).
	boss.set_physics_process(false)
	# Bolts have a 3s life; give them time to expire and free (real-time wait:
	# --headless runs process_frame uncapped, so frame counts != wall time).
	await get_tree().create_timer(3.8).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var after := _snapshot("bolts after expiry")
	var remaining: int = get_tree().get_nodes_in_group("boss_bolts").size()
	_report("bolts free on expiry / hit", remaining == 0, "remaining=%d" % remaining)
	_report("no orphan growth from bolt churn",
		after["orphans"] - before["orphans"] <= 2,
		"orphans %d -> %d" % [before["orphans"], after["orphans"]])

func _fx_churn() -> void:
	print("===== SECTION 1d: Fx particle/popup churn =====")
	# Flush any in-flight particles from earlier sections.
	await get_tree().create_timer(0.4).timeout
	var before := _snapshot("fx before")
	for i in 40:
		Fx.burst(Vector2(100 + i, 200), Color(1, 1, 1), 12, 200, 0.4, 1.0)
		Fx.popup(Vector2(100 + i, 300), "+1", Color(1, 1, 1), 18)
	# Particles free at lifetime+0.4; popups free at 0.7s tween end. Wait past both.
	await get_tree().create_timer(1.6).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	var after := _snapshot("fx after cleanup")
	var orphan_delta: int = after["orphans"] - before["orphans"]
	_report("Fx nodes return to baseline after cleanup",
		after["nodes"] - before["nodes"] <= 4,
		"nodes %d -> %d (delta %d)" % [before["nodes"], after["nodes"], after["nodes"] - before["nodes"]])
	_report("Fx leaves no orphan nodes", orphan_delta <= 2, "orphans %d -> %d" % [before["orphans"], after["orphans"]])

func _sfx_churn() -> void:
	print("===== SECTION 1e: Sfx one-shot player churn =====")
	await get_tree().create_timer(0.4).timeout
	var s: Node = get_node_or_null("/root/Sfx")
	if s == null:
		_report("sfx autoload present", false)
		return
	var before: int = s.get_child_count()
	for i in 40:
		Sfx.play("explode", randf_range(0.9, 1.1))
	# Real-time wait (headless process_frame is uncapped); the tree is kept
	# unpaused by _auto_pick_upgrade so `finished` fires and players free.
	await get_tree().create_timer(1.3).timeout
	await get_tree().process_frame
	var after: int = s.get_child_count()
	_report("Sfx one-shot players free via finished->queue_free",
		after <= before + 1,
		"Sfx children %d -> %d (coin poly player + live players)" % [before, after])

func _finish() -> void:
	_sim_active = false
	print("===== PROFILER SUMMARY: failures=%d =====" % _failures)
	for s in _wave_samples:
		print("  [WAVE] %-28s nodes=%-6d orphans=%d coins=%d" % [
			s["tag"], s["nodes"], s["orphans"], s.get("coins", -1)])
	get_tree().quit()
