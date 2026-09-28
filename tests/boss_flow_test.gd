extends Node
## Headless verification for the 4-task rework:
## 1) wave-50 boss (spawn, HP, dash damage, boss bar, boss cam)
## 2) 'let_me_solo_her' achievement (sole-attacker tracking + unlock + toast path)
## 3) heart pickups despawn between waves (group cleanup)
## 4) coin SFX polyphonic (shared AudioStreamPlayer, no per-pickup players)

var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	var game: Node2D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(game.player != null, "game boots, player present")

	# --- Coin SFX: rapid plays must not create per-pickup players ---
	var coin_children_before: int = Sfx.get_child_count()
	Sfx.play("coin", 0.9)
	Sfx.play("coin", 1.0)
	Sfx.play("coin", 1.12)
	await get_tree().process_frame
	var coin_children_after: int = Sfx.get_child_count()
	_check(Sfx.get("_coin_player") != null and coin_children_after == coin_children_before,
		"coin sfx uses shared polyphonic player, no per-pickup nodes (%d -> %d children)" % [coin_children_before, coin_children_after])

	# --- Heart pickups: spawn one, then clear at wave start ---
	var pu: Area2D = (load("res://scenes/power_up.tscn") as PackedScene).instantiate()
	pu.type = 2  # HEART
	game.get_node("Enemies").add_child(pu)
	await get_tree().process_frame
	var hearts_before: int = get_tree().get_nodes_in_group("heart_pickup").size()
	game._clear_leftover_hearts()
	await get_tree().process_frame
	var hearts_after: int = get_tree().get_nodes_in_group("heart_pickup").size()
	_check(hearts_before == 1 and hearts_after == 0,
		"heart pickups despawn between waves (%d -> %d)" % [hearts_before, hearts_after])

	# --- Task 6: magnet/shield power-ups are also cleared at a wave boundary ---
	var mp: Area2D = (load("res://scenes/power_up.tscn") as PackedScene).instantiate()
	mp.type = 0  # MAGNET
	game.get_node("Enemies").add_child(mp)
	var sp: Area2D = (load("res://scenes/power_up.tscn") as PackedScene).instantiate()
	sp.type = 1  # SHIELD
	game.get_node("Enemies").add_child(sp)
	await get_tree().process_frame
	var pu_before: int = get_tree().get_nodes_in_group("powerups").size()
	game._clear_leftover_powerups()
	await get_tree().process_frame
	var pu_after: int = get_tree().get_nodes_in_group("powerups").size()
	_check(pu_before >= 2 and pu_after == 0,
		"magnet/shield powerups cleared at wave boundary (%d -> %d)" % [pu_before, pu_after])

	# --- Task 13: FX are pooled (no node churn per effect) ---
	var p_before := _count_particles(game)
	Fx.burst(Vector2(100, 100), Color.RED, 2, 60.0, 0.05, 0.5)
	await get_tree().create_timer(0.25).timeout
	var p_one := _count_particles(game)
	_check(p_one == p_before + 1, "first burst creates one particle node (%d -> %d)" % [p_before, p_one])
	Fx.burst(Vector2(140, 100), Color.RED, 2, 60.0, 0.05, 0.5)
	await get_tree().create_timer(0.25).timeout
	_check(_count_particles(game) == p_one, "a later burst reuses the pooled node (no churn)")

	# --- Task 14: frequent sfx share a polyphonic player (no per-play nodes) ---
	var sc_before: int = Sfx.get_child_count()
	for i in 5:
		Sfx.play("explode")
		Sfx.play("powerup")
	await get_tree().process_frame
	_check(Sfx.get_child_count() == sc_before,
		"explode/powerup sfx use polyphonic players (no per-play nodes, %d -> %d)" % [sc_before, Sfx.get_child_count()])

	# --- Boss wave ---
	game._start_boss_wave()
	await get_tree().process_frame
	await get_tree().process_frame
	var boss: Boss = null
	for child in game.get_node("Enemies").get_children():
		if child is Boss:
			boss = child
			break
	_check(boss != null, "boss spawned at wave 50")
	if boss == null:
		_summary()
		return
	_check(boss.hp == boss.max_hp, "boss hp initialized (%d/%d)" % [boss.hp, boss.max_hp])
	_check(game.boss_bar.visible, "boss healthbar visible")
	_check(game.boss_health.max_value == boss.max_hp, "boss healthbar max_value set")
	_check(game.boss_cam.get("priority") == 40, "boss cam priority raised to 40")

	# --- Task 4: standing inside the boss keeps dealing damage across the
	# whole overlap (area_entered only fires once, on enter). ---
	var hp0: int = game.player.hp
	game.player._invuln_left = 0.0
	game.player.is_dashing = false
	# Put both inside the arena so the player's arena clamp can't push it out of
	# contact range (the boss spawns partly off-screen at the top).
	boss.global_position = Vector2(640, 360)
	game.player.global_position = Vector2(672, 360)
	for i in 12:
		await get_tree().physics_frame
	_check(game.player.hp < hp0,
		"standing inside the boss damages the player (%d -> %d)" % [hp0, game.player.hp])
	# Reset for the rest of the flow.
	game.player.hp = game.player.max_hp
	game.player._invuln_left = 0.0
	game.player.is_dashing = false

	# --- Dash-through damage (real dash so _dash_left is set) ---
	game.player._facing = (boss.global_position - game.player.global_position).normalized()
	game.player._try_dash()
	boss.global_position = game.player.global_position + game.player._facing * 30.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(boss.hp == boss.max_hp - 1, "dash-through damages boss (%d -> %d)" % [boss.max_hp, boss.hp])

	# --- Sole attacker tracking ---
	var attacker: int = boss.solo_attacker_id()
	_check(attacker == 1, "sole attacker tracked (id=%d)" % attacker)

	# --- Kill boss: achievement + score + UI reset + wave advance path ---
	# All boss-death effects (score, bar hide, cam reset, unlock) fire
	# synchronously on the boss_died signal, so assert the +500 immediately.
	# Waiting frames here lets a random magnet power-up (dropped on the pinned
	# headless player) pull coins and add stray +1s to the score delta.
	# --- Task 11: health_changed must never emit a negative value ---
	var neg := [false]
	var hb := func(cur: int, _mx: int) -> void:
		if cur < 0:
			neg[0] = true
	boss.health_changed.connect(hb)
	var score_before: int = GameState.score
	boss.take_damage(boss.hp, attacker)
	_check(not neg[0], "boss health_changed never emits a negative value")
	_check(GameState.score - score_before == 500, "boss kill grants +500 score")
	for i in 20:
		await get_tree().process_frame
	_check(Achievements.is_unlocked("let_me_solo_her"), "achievement 'let_me_solo_her' unlocked")
	_check(not game.boss_bar.visible, "boss healthbar hidden after death")
	_check(game.boss_cam.get("priority") == 0, "boss cam priority reset to 0")

	_summary()
	get_tree().quit()

func _count_particles(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is CPUParticles2D:
			n += 1
	return n

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
