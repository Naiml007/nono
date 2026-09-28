extends SceneTree
## Full-run playthrough bot (throwaway, not part of the test suite).
## Plays NONO from wave 1 through the wave-50 boss using the REAL game logic:
## - player is kept invulnerable so enemy contact kills enemies (real die path)
## - upgrade cards are picked via the real _on_upgrade_choice_index handler
## - the boss is damaged via the real dash-through path (boss._tick_dash_damage)
## Logs every wave + the boss fight + camera limits, and reports anomalies.

var _frame := 0
var _game: Node2D
var _last_wave := 0
var _boss_seen := false
var _boss_done := false
var _boss_hp_last := -1
var _start_ms := 0
var _picks := 0

func _process(_delta: float) -> bool:
	if _frame == 0:
		_start_ms = Time.get_ticks_msec()
		root.size = Vector2i(1280, 720)
		_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
		root.add_child(_game)
	_frame += 1
	Engine.time_scale = 5.0

	var player: Node2D = _game.get("player")
	if player == null:
		return false

	# --- keep the bot alive: invulnerable player ---
	player._invuln_left = 999.0

	var rt := (Time.get_ticks_msec() - _start_ms) / 1000.0
	var wave: int = _game.get("_wave")
	var alive: int = _game.get("_alive_enemies")

	# --- 1) pick upgrade card whenever the panel is up ---
	var panel: Control = _game.get("upgrade_panel")
	if panel != null and panel.visible and _game.get_tree().paused:
		var choices: Array = _game.get("_current_choices")
		if not choices.is_empty():
			_picks += 1
			_game._on_upgrade_choice_index(0)

	# --- 2) boss fight: drive real dash-through damage ---
	var boss: Node2D = null
	for n in get_nodes_in_group("boss"):
		if is_instance_valid(n):
			boss = n
			break
	if boss != null:
		if not _boss_seen:
			_boss_seen = true
			print("[%6.1fs] BOSS FIGHT at wave %d, hp %d/%d" % [rt, wave, boss.hp, boss.max_hp])
		player.is_dashing = true
		player._dash_dir = (boss.global_position - player.global_position).normalized()
		player.global_position = boss.global_position + Vector2(50, 0)
		if boss.hp != _boss_hp_last:
			_boss_hp_last = boss.hp
			print("[%6.1fs]   boss hp -> %d/%d" % [rt, boss.hp, boss.max_hp])
	elif _boss_seen and not _boss_done:
		_boss_done = true
		print("[%6.1fs] BOSS DIED -> wave now %d, score %d" % [rt, wave, _game.get("GameState").score])
		return true
	else:
		# --- 3) normal waves: teleport player to each enemy for real contact kills ---
		var enemies := get_nodes_in_group("enemies")
		if enemies.size() > 0:
			var e: Node2D = enemies[0]
			if is_instance_valid(e):
				player.global_position = e.global_position + Vector2(18, 18)
		player.is_dashing = false

	# --- wave-transition log + anomaly checks ---
	if wave != _last_wave:
		var coins := get_nodes_in_group("coins")
		var oob := 0
		for c in coins:
			if is_instance_valid(c):
				var p: Vector2 = c.global_position
				if p.x < -2 or p.x > 1282 or p.y < -2 or p.y > 722:
					oob += 1
		print("[%6.1fs] wave %d alive=%d enemies=%d coins=%d hearts=%d oob_coins=%d score=%d hp=%d picks=%d" % [
			rt, wave, alive, get_nodes_in_group("enemies").size(), coins.size(),
			get_nodes_in_group("heart_pickup").size(), oob, _game.get("GameState").score, player.hp, _picks])
		_last_wave = wave

	# safety
	if rt > 200.0:
		print("[%6.1fs] SAFETY TIMEOUT at wave %d" % [rt, wave])
		Engine.time_scale = 1.0
		return true
	return false
