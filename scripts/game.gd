class_name Game
extends Node2D
## Endless space survival arcade: dodge chaser drones, grab energy cores,
## chain score combos, grab power-ups, and survive as long as you can.
## Every cleared wave offers a choice of upgrade buffs.

signal upgrade_chosen(id: String)

const COIN_SCENE := preload("res://scenes/coin.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const POWERUP_SCENE := preload("res://scenes/power_up.tscn")
const BOSS_SCENE := preload("res://scenes/boss.tscn")
const BOSS_WAVE := 50

const ARENA := Vector2(1280, 720)
const COMBO_WINDOW := 3.0
const COMBO_STEP := 4   # Coins collected per multiplier step.

# Wave-clear upgrade pool. "stack" = max times that buff can be stacked;
# "one_off" = picked at most once per run.
const BUFFS := {
	"speed": {"name": "Speed Boost", "desc": "+20% move speed", "icon": "res://assets/generated/icon_bolt_frame_0.png", "stack": 3},
	"dash": {"name": "Dash Mastery", "desc": "-25% dash cooldown, +35% dash distance", "icon": "res://assets/generated/icon_swirl_frame_0.png", "stack": 3},
	"magnet": {"name": "Magnet Coil", "desc": "Permanent magnet radius +110", "icon": "res://assets/generated/powerup_magnet_frame_0.png", "stack": 3},
	"shield": {"name": "Shield Charge", "desc": "Absorb one hit", "icon": "res://assets/generated/powerup_shield_frame_0.png", "one_off": true},
	"heal": {"name": "Nano Repair", "desc": "Repair +1 HP", "icon": "res://assets/generated/powerup_heart_frame_0.png", "one_off": true},
	"maxhp": {"name": "Overclock", "desc": "+1 max HP and repair 1", "icon": "res://assets/generated/powerup_heart_frame_0.png", "one_off": true},
	"combo": {"name": "Combo Sense", "desc": "Combo window +2.0s", "icon": "res://assets/generated/icon_star_frame_0.png", "stack": 3},
	"value": {"name": "Coin Value", "desc": "Coins are worth +2 each", "icon": "res://assets/generated/icon_arrow_frame_0.png", "stack": 5},
	"shock": {"name": "Shockwave", "desc": "Dash blasts enemies nearby", "icon": "res://assets/generated/icon_shock_frame_0.png", "one_off": true},
}

@onready var player: Player = %Player
@onready var enemies: Node2D = %Enemies
@onready var debris_field: DebrisFieldSpawner = %DebrisFieldSpawner
@onready var camera: Camera2D = %Camera
@onready var score_label: Label = %ScoreLabel
@onready var wave_label: Label = %WaveLabel
@onready var combo_label: Label = %ComboLabel
@onready var hearts: HBoxContainer = %Hearts
@onready var shield_icon: TextureRect = %ShieldIcon
@onready var magnet_icon: TextureRect = %MagnetIcon
@onready var banner: Label = %Banner
@onready var hit_tint: ColorRect = %HitTint
@onready var game_over_panel: Control = %GameOverPanel
@onready var final_score: Label = %FinalScore
@onready var final_best: Label = %FinalBest
@onready var retry_button: Button = %RetryButton
@onready var menu_button: Button = %MenuButton
@onready var upgrade_panel: Control = %UpgradePanel
@onready var upgrade_cards: HBoxContainer = %Cards
@onready var boss_bar: Control = %BossBar
@onready var boss_health: ProgressBar = %BossHealth
@onready var player_cam: Node2D = %PlayerCam
@onready var boss_cam: Node2D = %BossCam
@onready var pause_panel: PauseMenu = %PausePanel

var _rng := RandomNumberGenerator.new()
var _wave := 0
var _alive_enemies := 0
var _combo := 0
var _combo_left := 0.0
var _game_over := false
var _pending_wave := false
var _combo_window: float = COMBO_WINDOW
var _coin_value_bonus := 0
var _taken_one_offs: Array[String] = []
var _stack_counts: Dictionary = {}
var _current_choices: Array[String] = []

var _heart_tex := preload("res://assets/generated/powerup_heart_frame_0.png")
var _heart_rects: Array[TextureRect] = []

func _ready() -> void:
	_rng.randomize()
	GameState.reset_run()
	Fx.setup(self, camera)
	upgrade_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hearts()
	_wire()
	_update_hearts()
	_update_power_icons()
	_update_ui()
	Music.play("battle")
	_start_wave(1)

func _process(delta: float) -> void:
	if _game_over:
		return
	_tick_combo(delta)
	_tick_magnet(delta)

## ESC pauses the game. Opening is handled here because the tree is not paused
## yet; closing is handled by PauseMenu (which runs in PROCESS_MODE_ALWAYS).
func _unhandled_input(event: InputEvent) -> void:
	if _game_over or upgrade_panel.visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_set_paused(true)

func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_panel.visible = paused

func _on_resume_pressed() -> void:
	_set_paused(false)

func _wire() -> void:
	menu_button.pressed.connect(_to_menu)
	retry_button.pressed.connect(_retry)
	# Resume/Menu buttons are wired in the scene file; PauseMenu emits
	# resume_requested when ESC is pressed while the overlay is visible.
	pause_panel.resume_requested.connect(_on_resume_pressed)
	GameState.score_changed.connect(_on_score_changed)
	player.health_changed.connect(_on_health_changed)
	player.shield_changed.connect(_on_shield_changed)
	player.magnet_changed.connect(_on_magnet_changed)
	player.took_hit.connect(_on_player_hit)
	player.died.connect(_on_player_died)
	upgrade_panel.choice_requested.connect(_on_upgrade_choice_index)

# --- Waves -----------------------------------------------------------------

func _start_wave(n: int) -> void:
	_clear_leftover_hearts()
	if n == BOSS_WAVE:
		_start_boss_wave()
		return
	_wave = n
	GameState.wave = n
	_show_banner("WAVE %d" % n)
	Sfx.play("wave")
	_scatter_coins()
	var count := _enemy_count_for_wave(n)
	_alive_enemies = count
	for i in count:
		_spawn_enemy_later(i * 0.35 + _rng.randf_range(0.0, 0.2))
	_update_ui()

func _enemy_count_for_wave(n: int) -> int:
	return 2 + n

func _spawn_enemy_later(delay: float) -> void:
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func() -> void:
		if _game_over or not is_inside_tree():
			return
		_spawn_enemy())

func _spawn_enemy() -> void:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.speed = minf(120.0 + _wave * 8.0, 210.0)
	e.global_position = _edge_spawn_pos()
	e.died.connect(_on_enemy_died)
	enemies.add_child(e)

func _edge_spawn_pos() -> Vector2:
	var edge := _rng.randi_range(0, 3)
	match edge:
		0: return Vector2(_rng.randf_range(0.0, ARENA.x), -40.0)
		1: return Vector2(_rng.randf_range(0.0, ARENA.x), ARENA.y + 40.0)
		2: return Vector2(-40.0, _rng.randf_range(0.0, ARENA.y))
		_: return Vector2(ARENA.x + 40.0, _rng.randf_range(0.0, ARENA.y))

# --- Boss wave --------------------------------------------------------------

func _start_boss_wave() -> void:
	_wave = BOSS_WAVE
	GameState.wave = BOSS_WAVE
	_show_banner("WAVE 50 — BOSS")
	Music.play("boss")
	Sfx.play("wave")
	_scatter_coins()
	_alive_enemies = 1
	_spawn_boss()
	_update_ui()

func _spawn_boss() -> void:
	var b: Boss = BOSS_SCENE.instantiate()
	b.global_position = Vector2(ARENA.x * 0.5, -70.0)
	b.boss_died.connect(_on_boss_died)
	b.health_changed.connect(_on_boss_health_changed)
	enemies.add_child(b)
	_show_boss_ui(b)
	if boss_cam != null:
		boss_cam.set("priority", 40)
	Fx.burst(b.global_position, Color(1.0, 0.5, 0.2), 40, 420, 0.8, 1.4)

func _on_boss_health_changed(current: int, max_hp: int) -> void:
	if boss_bar.visible:
		boss_health.max_value = max_hp
		boss_health.value = current

func _show_boss_ui(boss: Boss) -> void:
	boss_bar.visible = true
	boss_health.max_value = boss.max_hp
	boss_health.value = boss.hp

func _hide_boss_ui() -> void:
	boss_bar.visible = false

func _on_boss_died(boss: Boss) -> void:
	_alive_enemies -= 1
	_hide_boss_ui()
	if boss_cam != null:
		boss_cam.set("priority", 0)
	_maybe_drop_powerup(boss.global_position)
	_maybe_drop_powerup(boss.global_position + Vector2(26, -22))
	GameState.add_score(500)
	Fx.popup(boss.global_position, "+500", Color(1.0, 0.7, 0.3), 30)
	if boss.solo_attacker_id() != -1:
		Achievements.unlock("let_me_solo_her")
	if _alive_enemies <= 0 and not _game_over and not _pending_wave:
		_pending_wave = true
		_start_next_wave()

## Heart pickups persist until collected; drop any leftovers when a new wave
## begins so they don't carry over from the previous wave.
func _clear_leftover_hearts() -> void:
	for node in get_tree().get_nodes_in_group("heart_pickup"):
		if is_instance_valid(node):
			node.queue_free()

func _on_enemy_died(e: Enemy) -> void:
	_alive_enemies -= 1
	_maybe_drop_powerup(e.global_position)
	if _alive_enemies <= 0 and not _game_over and not _pending_wave:
		_pending_wave = true
		_start_next_wave()

func _start_next_wave() -> void:
	await get_tree().create_timer(1.0).timeout
	if _game_over or not is_inside_tree():
		return
	_pending_wave = false
	await _offer_upgrades()
	if _game_over or not is_inside_tree():
		return
	_start_wave(_wave + 1)

# --- Coins / debris field --------------------------------------------------

func _scatter_coins() -> void:
	debris_field.coin_prefab = COIN_SCENE
	debris_field.cell_size = 140
	debris_field.max_jitter = 44
	debris_field.spawn_density = 0.5
	debris_field.generate_debris_field(int(ARENA.x), int(ARENA.y))
	for node in get_tree().get_nodes_in_group("coins"):
		var c := node as Coin
		if c != null and not c.collected.is_connected(_on_coin_collected):
			c.collected.connect(_on_coin_collected)

func _on_coin_collected(c: Coin) -> void:
	_combo += 1
	_combo_left = _combo_window
	var mult := _combo_multiplier()
	var pts := (1 + _coin_value_bonus) * mult
	GameState.add_score(pts)
	_update_combo_ui()
	Fx.popup(c.global_position, "+%d" % pts, Color(1.0, 0.85, 0.25), 22)
	Sfx.play("coin", randf_range(0.92, 1.2))
	_update_ui()

func _combo_multiplier() -> int:
	return mini(1 + int(float(_combo) / COMBO_STEP), 5)

func _tick_combo(delta: float) -> void:
	if _combo > 0:
		_combo_left -= delta
		if _combo_left <= 0.0:
			_combo = 0
			_update_combo_ui()

func _update_combo_ui() -> void:
	var mult := _combo_multiplier()
	if _combo > 0 and mult > 1:
		combo_label.text = "COMBO x%d" % mult
		combo_label.modulate = Color(1.0, 0.62, 0.2)
	else:
		combo_label.text = ""

func _tick_magnet(delta: float) -> void:
	if player.magnet_left <= 0.0:
		return
	for node in get_tree().get_nodes_in_group("coins"):
		var c := node as Coin
		if c == null or not is_instance_valid(c):
			continue
		var d := c.global_position.distance_to(player.global_position)
		if d < player.effective_magnet_radius() and d > 1.0:
			c.global_position = c.global_position.move_toward(player.global_position, 640.0 * delta)

# --- Power-ups -------------------------------------------------------------

func _maybe_drop_powerup(at: Vector2) -> void:
	var roll := _rng.randf()
	if roll < 0.12:
		_drop_powerup(at, PowerUp.Type.MAGNET)
	elif roll < 0.22:
		_drop_powerup(at, PowerUp.Type.SHIELD)
	elif roll < 0.29:
		_drop_powerup(at, PowerUp.Type.HEART)

func _drop_powerup(at: Vector2, type: PowerUp.Type) -> void:
	var p: PowerUp = POWERUP_SCENE.instantiate()
	p.type = type
	p.global_position = at
	p.collected.connect(_on_power_collected)
	enemies.add_child.call_deferred(p)
	Sfx.play("powerup")

func _on_power_collected(p: PowerUp) -> void:
	Fx.burst(p.global_position, Color(0.4, 0.9, 1.0), 12, 220, 0.5, 1.1)
	Sfx.play("powerup")
	match p.type:
		PowerUp.Type.MAGNET:
			player.magnet_left = 9.0
			player.magnet_changed.emit(true)
			Fx.popup(p.global_position, "MAGNET!", Color(0.4, 0.9, 1.0), 26)
		PowerUp.Type.SHIELD:
			player.has_shield = true
			player.shield_changed.emit(true)
			Fx.popup(p.global_position, "SHIELD!", Color(0.4, 1.0, 0.85), 26)
		PowerUp.Type.HEART:
			player.heal(2)
			Fx.popup(p.global_position, "+2 HP", Color(1.0, 0.4, 0.55), 26)
	_update_power_icons()

# --- Wave-clear upgrades ---------------------------------------------------

func _offer_upgrades() -> void:
	_current_choices = _pick_upgrade_choices()
	if _current_choices.is_empty():
		return
	_show_upgrade_panel(_current_choices)
	get_tree().paused = true
	var id: String = await upgrade_chosen
	if not is_inside_tree():
		return
	_hide_upgrade_panel()
	get_tree().paused = false
	if _game_over:
		return
	_apply_buff(id)

func _pick_upgrade_choices() -> Array[String]:
	var pool: Array[String] = []
	for id in BUFFS:
		var meta: Dictionary = BUFFS[id]
		if meta.has("one_off") and _taken_one_offs.has(id):
			continue
		if meta.has("stack") and int(_stack_counts.get(id, 0)) >= int(meta["stack"]):
			continue
		pool.append(id)
	pool.shuffle()
	var choices: Array[String] = []
	while choices.size() < 3 and not pool.is_empty():
		choices.append(pool.pop_back())
	return choices

func _show_upgrade_panel(choices: Array[String]) -> void:
	for child in upgrade_cards.get_children():
		child.queue_free()
	for id in choices:
		upgrade_cards.add_child(_build_card(id))
	upgrade_panel.visible = true

func _hide_upgrade_panel() -> void:
	upgrade_panel.visible = false
	for child in upgrade_cards.get_children():
		child.queue_free()

func _build_card(id: String) -> Button:
	var meta: Dictionary = BUFFS[id]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(230, 300)
	btn.focus_mode = Control.FOCUS_ALL
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.texture = load(str(meta["icon"]))
	icon.custom_minimum_size = Vector2(64, 64)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var name_label := Label.new()
	name_label.text = str(meta["name"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 24)
	box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = str(meta["desc"])
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 15)
	box.add_child(desc_label)
	btn.add_child(box)
	btn.pressed.connect(_on_upgrade_chosen.bind(id))
	return btn

func _on_upgrade_chosen(id: String) -> void:
	if not get_tree().paused:
		return
	upgrade_chosen.emit(id)

func _on_upgrade_choice_index(idx: int) -> void:
	if idx >= 0 and idx < _current_choices.size():
		_on_upgrade_chosen(_current_choices[idx])

func _apply_buff(id: String) -> void:
	var meta: Dictionary = BUFFS[id]
	Sfx.play("powerup")
	Fx.popup(player.global_position, str(meta["name"]), Color(0.55, 0.9, 1.0), 24)
	match id:
		"speed":
			player.speed_mult *= 1.20
		"dash":
			player.dash_cd_mult *= 0.75
			player.dash_speed_mult *= 1.35
		"magnet":
			player.magnet_radius_bonus += 110.0
		"shield":
			player.has_shield = true
			player.shield_changed.emit(true)
		"heal":
			player.heal(1)
		"maxhp":
			player.increase_max_hp(1)
			_build_hearts()
		"combo":
			_combo_window += 2.0
		"value":
			_coin_value_bonus += 2
		"shock":
			player.shockwave = true
	if meta.has("one_off"):
		_taken_one_offs.append(id)
	else:
		_stack_counts[id] = int(_stack_counts.get(id, 0)) + 1
	_update_power_icons()
	_update_hearts()

# --- Damage / death --------------------------------------------------------

func _on_player_hit() -> void:
	_combo = 0
	_update_combo_ui()
	_flash_tint()
	Sfx.play("hurt")
	Fx.shake(8.0, 0.25)

func _on_player_died() -> void:
	_game_over = true
	Fx.burst(player.global_position, Color(1.0, 0.5, 0.3), 42, 460, 1.0, 1.8)
	Fx.shake(16.0, 0.5)
	Sfx.play("gameover")
	Music.play("gameover")
	GameState.save_best()
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	game_over_panel.visible = true
	final_score.text = "Score: %d" % GameState.score
	final_best.text = "Best: %d" % GameState.best_score

func _flash_tint() -> void:
	hit_tint.color.a = 0.4
	var tw := hit_tint.create_tween()
	tw.tween_property(hit_tint, "color:a", 0.0, 0.45)

# --- UI --------------------------------------------------------------------

func _build_hearts() -> void:
	for child in hearts.get_children():
		hearts.remove_child(child)
		child.queue_free()
	_heart_rects.clear()
	for i in player.max_hp:
		var rect := TextureRect.new()
		rect.texture = _heart_tex
		rect.custom_minimum_size = Vector2(26, 26)
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hearts.add_child(rect)
		_heart_rects.append(rect)

func _on_health_changed(_current: int, _max_hp: int) -> void:
	_update_hearts()

func _update_hearts() -> void:
	for i in _heart_rects.size():
		var filled := i < player.hp
		_heart_rects[i].modulate = Color.WHITE if filled else Color(1, 1, 1, 0.22)

func _on_shield_changed(_active: bool) -> void:
	_update_power_icons()

func _on_magnet_changed(_active: bool) -> void:
	_update_power_icons()

func _update_power_icons() -> void:
	shield_icon.visible = player.has_shield
	magnet_icon.visible = player.magnet_left > 0.0

func _on_score_changed(_new: int) -> void:
	_update_ui()

func _update_ui() -> void:
	score_label.text = "Score: %d" % GameState.score
	wave_label.text = "Wave: %d" % _wave

func _show_banner(text: String) -> void:
	banner.text = text
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.6, 0.6)
	banner.visible = true
	var tw := banner.create_tween()
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.7)
	tw.tween_property(banner, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void: banner.visible = false)

func _retry() -> void:
	get_tree().reload_current_scene()

func _to_menu() -> void:
	# Leave paused state first so the menu isn't frozen.
	_set_paused(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
