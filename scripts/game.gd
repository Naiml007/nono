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
const BATTLE_TIER_SIZE := 5   # waves per battle-music intensity tier

const ARENA := Vector2(1280, 720)
## Boss-cam zoom-in relative to the player cam (reads as 20% tighter). Applied
## on top of the aspect-driven minimum zoom so it survives non-16:9 viewports.
const BOSS_ZOOM := 1.2
const COMBO_WINDOW := 3.0
const COMBO_STEP := 4   # Coins collected per multiplier step.
## The PhantomCameraHost processes at priority 300; running Game's camera-zoom
## floor afterwards guarantees the clamp wins for the frame.
const CAMERA_PROCESS_PRIORITY := 400

# Wave-clear upgrade pool. "stack" = max times that buff can be stacked;
# "one_off" = picked at most once per run.
const BUFFS := {
	"speed": {"name": "Speed Boost", "desc": "+20% move speed", "icon": "res://assets/generated/icon_bolt_frame_0.png", "stack": 5},
	"dash": {"name": "Dash Mastery", "desc": "-25% dash cooldown, +35% dash distance", "icon": "res://assets/generated/icon_swirl_frame_0.png", "stack": 4},
	"magnet": {"name": "Magnet Coil", "desc": "Permanent magnet radius +110", "icon": "res://assets/generated/powerup_magnet_frame_0.png", "stack": 4},
	"shield": {"name": "Shield Charge", "desc": "Absorb one hit", "icon": "res://assets/generated/powerup_shield_frame_0.png", "one_off": true},
	"heal": {"name": "Nano Repair", "desc": "Repair +2 HP", "icon": "res://assets/generated/powerup_heart_frame_0.png", "one_off": true},
	"maxhp": {"name": "Overclock", "desc": "+1 max HP and repair 1", "icon": "res://assets/generated/powerup_heart_frame_0.png", "one_off": true},
	"combo": {"name": "Combo Sense", "desc": "Combo window +2.0s", "icon": "res://assets/generated/icon_star_frame_0.png", "stack": 4},
	"value": {"name": "Coin Value", "desc": "Coins are worth +2 each", "icon": "res://assets/generated/icon_arrow_frame_0.png", "stack": 6},
	"shock": {"name": "Shockwave", "desc": "Dash blasts enemies nearby", "icon": "res://assets/generated/icon_shock_frame_0.png", "one_off": true},
	# Repeatable, always-eligible entries ("repeat": true, never exhausted). The
	# finite stacks above alone run dry around wave 10; these keep the wave-clear
	# panel populated for the whole 50-wave run (and their effects are bounded so
	# a very long endless run can't run away).
	"overcharge": {"name": "Overcharge", "desc": "+250 score, +3% move speed", "icon": "res://assets/generated/icon_bolt_frame_0.png", "repeat": true},
	"repair": {"name": "Nano Patch", "desc": "Repair +2 HP (or +150 score if full)", "icon": "res://assets/generated/powerup_heart_frame_0.png", "repeat": true},
	"reserve": {"name": "Reserve Cells", "desc": "Gain a shield (or +250 score if shielded)", "icon": "res://assets/generated/powerup_shield_frame_0.png", "repeat": true},
}

@onready var player: Player = %Player
@onready var enemies: Node2D = %Enemies
@onready var debris_field: DebrisFieldSpawner = %DebrisFieldSpawner
@onready var camera: Camera2D = %Camera
@onready var score_label: Label = %ScoreLabel
@onready var wave_label: Label = %WaveLabel
@onready var combo_label: Label = %ComboLabel
@onready var hearts: HBoxContainer = %Hearts
@onready var hearts_backing: Panel = %HeartsBacking
@onready var shield_icon: TextureRect = %ShieldIcon
@onready var magnet_icon: TextureRect = %MagnetIcon
@onready var banner: Label = %Banner
@onready var hit_tint: ColorRect = %HitTint
@onready var game_over_panel: Control = %GameOverPanel
@onready var final_score: Label = %FinalScore
@onready var final_best: Label = %FinalBest
@onready var new_best: Label = %NewBest
@onready var retry_button: Button = %RetryButton
@onready var menu_button: Button = %MenuButton
@onready var upgrade_panel: Control = %UpgradePanel
@onready var upgrade_cards: HBoxContainer = %Cards
@onready var upgrade_hint: Label = %Hint
@onready var boss_bar: Control = %BossBar
@onready var boss_health: ProgressBar = %BossHealth
@onready var player_cam: Node2D = %PlayerCam
@onready var boss_cam: Node2D = %BossCam
@onready var pause_panel: PauseMenu = %PausePanel
@onready var touch_controls: TouchControls = %TouchControls
@onready var hud_canvas: CanvasLayer = $HUD

var _rng := RandomNumberGenerator.new()
var _wave := 0
var _battle_tier := 1   # current battle-music intensity tier (1..10)
var _alive_enemies := 0
var _combo := 0
var _combo_left := 0.0
var _game_over := false
var _pending_wave := false
var _combo_window: float = COMBO_WINDOW
var _coin_value_bonus := 0
var _taken_one_offs: Array[String] = []
var _stack_counts: Dictionary = {}
var _repeat_counts: Dictionary = {}
var _banner_tween: Tween
var _current_choices: Array[String] = []
var _coins_collected := 0
var _max_combo_mult := 0
var _hit_this_wave := false
## Low-health visual state: the health cluster pulses (colour AND motion) once
## HP drops to a single heart, so the warning reads even without colour vision.
var _low_hp := false
var _low_hp_tween: Tween

var _heart_tex := preload("res://assets/generated/powerup_heart_frame_0.png")
var _heart_rects: Array[TextureRect] = []
## Cached live coins (rebuilt each wave, pruned as they are collected) so the
## magnet tick doesn't allocate a fresh group Array every frame.
var _coins: Array[Coin] = []
## Minimum camera zoom for the current viewport (see _apply_camera_bounds). The
## visible world rect is viewport/zoom, so this floor keeps it inside the arena.
var _camera_floor := 1.0
## Bumped by a debug wave jump so a stale pending next-wave coroutine aborts
## instead of clobbering the jump one second later.
var _wave_epoch := 0

func _ready() -> void:
	_rng.randomize()
	# Defensive: a hitstop overlapping a scene change could otherwise leave the
	# engine frozen at time_scale == 0 for the whole new run.
	Engine.time_scale = 1.0
	GameState.reset_run()
	Fx.setup(self, camera)
	upgrade_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hearts()
	_wire()
	_update_hearts()
	_update_power_icons()
	_update_ui()
	_update_hud_layout()
	if not get_viewport().size_changed.is_connected(_update_hud_layout):
		get_viewport().size_changed.connect(_update_hud_layout)
	# Camera bounds must be in place before the first frame renders: apply them
	# now, keep them correct when the window/viewport is resized, and re-pin the
	# host limits whenever the PhantomCamera addon forwards its own.
	process_priority = CAMERA_PROCESS_PRIORITY
	_apply_camera_bounds()
	if not get_viewport().size_changed.is_connected(_apply_camera_bounds):
		get_viewport().size_changed.connect(_apply_camera_bounds)
	var pcam_manager := get_node_or_null("/root/PhantomCameraManager")
	if pcam_manager != null and pcam_manager.has_signal("limit_2d_changed") \
			and not pcam_manager.limit_2d_changed.is_connected(_on_pcam_limit_changed):
		pcam_manager.limit_2d_changed.connect(_on_pcam_limit_changed)
	Debug.register(self)
	Music.play("battle")
	_start_wave(1)

func _exit_tree() -> void:
	Debug.unregister(self)
	# Pooled VFX children die with the world; detach the singleton only when it
	# still points at this scene (test harnesses may briefly host multiple games).
	if Fx._world == self:
		Fx.setup(null, null)

func _process(delta: float) -> void:
	# Enforce the aspect-driven zoom floor on the live host camera every frame so
	# the invariant holds even mid-tween (e.g. resizing during the boss zoom-in).
	_enforce_camera_floor()
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
	if touch_controls != null:
		# Keep the touch buttons off the pause overlay.
		touch_controls.set_controls_enabled(not paused)

func _on_resume_pressed() -> void:
	_set_paused(false)

## Pause button on the touch controls: same handler the ESC path reaches, so
## the exact same guards (game over / upgrade panel) apply.
func _on_touch_pause_requested() -> void:
	if _game_over or upgrade_panel.visible:
		return
	_set_paused(true)

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
	touch_controls.dash_pressed.connect(player.try_dash)
	touch_controls.pause_requested.connect(_on_touch_pause_requested)

# --- Waves -----------------------------------------------------------------

func _start_wave(n: int) -> void:
	_clear_leftover_hearts()
	_clear_leftover_coins()
	_clear_leftover_powerups()
	if n == BOSS_WAVE:
		_start_boss_wave()
		return
	_wave = n
	GameState.wave = n
	_hit_this_wave = false
	if _wave >= 10:
		Achievements.unlock("wave_10")
	if _wave >= 25:
		Achievements.unlock("wave_25")
	_show_banner("WAVE %d" % n)
	Sfx.play("wave")
	_scatter_coins()
	var count := _enemy_count_for_wave(n)
	_alive_enemies = count
	for i in count:
		_spawn_enemy_later(i * 0.35 + _rng.randf_range(0.0, 0.2))
	_update_ui()
	_maybe_switch_battle_tier()

## Battle music intensifies every BATTLE_TIER_SIZE waves: wave -> tier is fully
## deterministic, and a tier only ever plays once per run (no repeated renders).
func _battle_tier_for_wave(n: int) -> int:
	return clampi(1 + floori(float(n - 1) / float(BATTLE_TIER_SIZE)), 1, ChiptuneGenerator.BATTLE_TIER_COUNT)

func _maybe_switch_battle_tier() -> void:
	if _wave >= BOSS_WAVE:
		return
	var tier := _battle_tier_for_wave(_wave)
	if tier != _battle_tier:
		_battle_tier = tier
		Music.play_battle_tier(tier)

func _enemy_count_for_wave(n: int) -> int:
	# Cap the simultaneous-drone count so late waves stay hard but readable.
	return mini(2 + n, 24)

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
	_hit_this_wave = false
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
	Fx.screen_flash(Color(1.0, 0.42, 0.18), 0.10, 0.26)
	Fx.zoom_punch(0.055, 0.24)
	Fx.shake(7.0, 0.32)
	Fx.ring(b.global_position, Color(1.0, 0.48, 0.2, 0.9), 120.0, 5.0, 0.42)

func _on_boss_health_changed(current: int, max_hp: int) -> void:
	if boss_bar.visible:
		boss_health.max_value = max_hp
		boss_health.value = current

func _show_boss_ui(boss: Boss) -> void:
	Fx.aim_line(boss.global_position, player.global_position, Color(1.0, 0.34, 0.23, 0.7), 0.5)
	Fx.ring(boss.global_position, Color(1.0, 0.45, 0.2, 0.65), 160.0, 3.0, 0.65)
	boss_bar.visible = true
	boss_health.max_value = boss.max_hp
	boss_health.value = boss.hp

func _hide_boss_ui() -> void:
	boss_bar.visible = false

## Restore the normal (player) camera. Also called on player death so the
## game-over screen never renders through the still-active boss camera.
func _reset_boss_cam() -> void:
	if boss_cam != null:
		boss_cam.set("priority", 0)

func _on_boss_died(boss: Boss) -> void:
	_alive_enemies -= 1
	_hide_boss_ui()
	_reset_boss_cam()
	# Endless mode continues past wave 50: hand the music back to the
	# intensified battle track instead of letting the boss theme play forever.
	Music.play_battle_tier(_battle_tier)
	_maybe_drop_powerup(boss.global_position)
	_maybe_drop_powerup(boss.global_position + Vector2(26, -22))
	GameState.add_score(500)
	Fx.popup(boss.global_position, "+500", Color(1.0, 0.7, 0.3), 30)
	Fx.screen_flash(Color(1.0, 0.56, 0.18), 0.16, 0.32)
	Fx.zoom_punch(0.07, 0.3)
	Fx.vignette(false)
	if boss.solo_attacker_id() != -1:
		Achievements.unlock("let_me_solo_her")
	if _alive_enemies <= 0 and not _game_over and not _pending_wave:
		_maybe_unlock_untouchable()
		_pending_wave = true
		_start_next_wave()

## Heart pickups persist until collected; drop any leftovers when a new wave
## begins so they don't carry over from the previous wave.
func _clear_leftover_hearts() -> void:
	for node in get_tree().get_nodes_in_group("heart_pickup"):
		if is_instance_valid(node):
			node.queue_free()

## Uncollected energy cores persist too, and each wave scatters a fresh field.
## Clearing leftovers at the wave boundary keeps the arena's node count flat
## over a long run instead of accumulating ~20 coins per wave forever.
func _clear_leftover_coins() -> void:
	for node in get_tree().get_nodes_in_group("coins"):
		if is_instance_valid(node):
			node.queue_free()

## Magnet and shield power-ups are not heart pickups, so they used to survive
## every wave boundary and accumulate for the whole run (each one an Area2D
## running _process and drawing through a shader). Clear the whole "powerups"
## group at the wave boundary to keep the arena's node count flat.
func _clear_leftover_powerups() -> void:
	for node in get_tree().get_nodes_in_group("powerups"):
		if is_instance_valid(node):
			node.queue_free()

func _on_enemy_died(e: Enemy) -> void:
	_alive_enemies -= 1
	_maybe_drop_powerup(e.global_position)
	if _alive_enemies <= 0 and not _game_over and not _pending_wave:
		_maybe_unlock_untouchable()
		_pending_wave = true
		_start_next_wave()

## "Untouchable" fires when a wave is cleared with zero player hits.
func _maybe_unlock_untouchable() -> void:
	if _wave >= 2 and not _hit_this_wave:
		Achievements.unlock("untouchable")

func _start_next_wave() -> void:
	# Capture the epoch: a debug wave jump bumps it, so a pending next-wave
	# coroutine aborts rather than clobbering the jump a moment later.
	var epoch := _wave_epoch
	await get_tree().create_timer(1.0).timeout
	if _game_over or not is_inside_tree() or epoch != _wave_epoch:
		return
	_pending_wave = false
	await _offer_upgrades()
	if _game_over or not is_inside_tree() or epoch != _wave_epoch:
		return
	_start_wave(_wave + 1)

# --- Camera bounds ---------------------------------------------------------
#
# The visible world rect is `viewport_size / zoom`. With stretch aspect "expand"
# the viewport can be larger than the 1280x720 arena (any non-16:9 window, and
# landscape phones), so no camera limit alone can keep the view inside the
# arena: the rect itself is bigger. We therefore enforce a minimum zoom derived
# from the arena, and pin the host Camera2D limits to the arena so the existing
# clamp can actually centre the (now arena-sized-or-smaller) view.

## Arena rect in world space, the single source of truth for camera bounds.
func arena_rect() -> Rect2:
	return Rect2(Vector2.ZERO, ARENA)

## Recompute the zoom floor for the current viewport and apply it to both
## PhantomCameras, then pin the host camera limits. Called on _ready and on
## every viewport size change, and re-pins limits whenever the addon forwards
## its own (it emits unlimited defaults when a pcam tween begins).
func _apply_camera_bounds() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var floor_zoom := 1.0
	if view.x > 0.0 and view.y > 0.0:
		floor_zoom = maxf(view.x / ARENA.x, view.y / ARENA.y)
	# A viewport smaller than the arena is already contained; don't zoom below
	# 1:1 (that would only blur the arena).
	_camera_floor = maxf(floor_zoom, 1.0)
	player_cam.set("zoom", Vector2(_camera_floor, _camera_floor))
	boss_cam.set("zoom", Vector2(BOSS_ZOOM * _camera_floor, BOSS_ZOOM * _camera_floor))
	_apply_host_limits()
	# Mirror the arena onto the PhantomCameras so the addon re-emits it (rather
	# than its own defaults) whenever it talks to the host camera.
	for pcam: Node2D in [player_cam, boss_cam]:
		pcam.set("limit_left", 0)
		pcam.set("limit_top", 0)
		pcam.set("limit_right", int(ARENA.x))
		pcam.set("limit_bottom", int(ARENA.y))
	# Also clamp the live camera immediately, so a resize that happens while the
	# tree is paused (the host won't tick) still can't show beyond the arena.
	_enforce_camera_floor()

## Hard-pin the host Camera2D limits to the arena.
func _apply_host_limits() -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(ARENA.x)
	camera.limit_bottom = int(ARENA.y)

## The addon emits limit changes through the manager singleton; re-pin the
## arena so its unlimited defaults can never leak into the host camera.
func _on_pcam_limit_changed(_side: int, _limit: int) -> void:
	_apply_host_limits()

## Keep the live host camera at or above the zoom floor. Runs after the
## PhantomCameraHost each frame so a mid-tween zoom can't dip below the floor.
func _enforce_camera_floor() -> void:
	if camera.zoom.x >= _camera_floor and camera.zoom.y >= _camera_floor:
		return
	var z := camera.zoom
	if z.x < _camera_floor:
		z.x = _camera_floor
	if z.y < _camera_floor:
		z.y = _camera_floor
	camera.zoom = z

# --- Debug hooks (driven by the Debug autoload; inert otherwise) -----------

## Jump straight to wave `n`. Routes through _start_wave so n == BOSS_WAVE
## still takes the boss path. Clears the current wave's spawns first.
func debug_goto_wave(n: int) -> void:
	if _game_over:
		return
	_wave_epoch += 1
	_pending_wave = false
	_clear_enemies_now()
	_start_wave(clampi(n, 1, BOSS_WAVE))

## Instantly clear the current wave and advance one wave.
func debug_skip_wave() -> void:
	if _game_over:
		return
	_wave_epoch += 1
	_pending_wave = false
	_clear_enemies_now()
	_start_wave(mini(_wave + 1, BOSS_WAVE))

## Kill every enemy (and the boss) without scoring. Existing death handlers
## advance the wave, so this doubles as a fast wave clearer.
func debug_kill_all_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e != null and is_instance_valid(e):
			e.die(false)
	for node in get_tree().get_nodes_in_group("boss"):
		var b := node as Boss
		if b != null and is_instance_valid(b):
			b.die(false)

## Restart the run back to wave 1. Reloads the scene when this Game is the
## current scene (full reset); otherwise resets in place (test harnesses).
func debug_reset_run() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	if get_tree().current_scene == self:
		get_tree().reload_current_scene()
		return
	_wave_epoch += 1
	GameState.reset_run()
	_clear_enemies_now()
	_clear_leftover_powerups()
	_clear_leftover_coins()
	_pending_wave = false
	_game_over = false
	game_over_panel.visible = false
	player.hp = player.max_hp
	player.has_shield = false
	player.magnet_left = 0.0
	player.shield_changed.emit(false)
	_update_power_icons()
	_start_wave(1)

## Free every enemy/boss instantly (deferred) and reset the wave counter. Used
## by the debug jumps so leftovers never stack onto the new wave.
func _clear_enemies_now() -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(node):
			node.queue_free()
	for node in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(node):
			node.queue_free()
	_alive_enemies = 0

# --- Coins / debris field --------------------------------------------------

func _scatter_coins() -> void:
	debris_field.coin_prefab = COIN_SCENE
	debris_field.cell_size = 140
	debris_field.max_jitter = 44
	debris_field.spawn_density = 0.5
	debris_field.generate_debris_field(int(ARENA.x), int(ARENA.y))
	_coins.clear()
	for node in get_tree().get_nodes_in_group("coins"):
		var c := node as Coin
		if c == null:
			continue
		_coins.append(c)
		if not c.collected.is_connected(_on_coin_collected):
			c.collected.connect(_on_coin_collected)

func _on_coin_collected(c: Coin) -> void:
	var prev_mult := _combo_multiplier()
	_combo += 1
	_combo_left = _combo_window
	var mult := _combo_multiplier()
	var pts := (1 + _coin_value_bonus) * mult
	GameState.add_score(pts)
	_update_combo_ui()
	Fx.burst(c.global_position, Color(1.0, 0.85, 0.25), 6, 150, 0.35, 0.7)
	Fx.ring(c.global_position, Color(1.0, 0.82, 0.22, 0.8), 30.0, 2.0, 0.16)
	Fx.popup(c.global_position, "+%d" % pts, Color(1.0, 0.85, 0.25), 22)
	Sfx.play("coin", randf_range(0.92, 1.2))
	# Combo milestone: a distinct audio/visual beat so it's felt, not just read.
	if mult > prev_mult and mult >= 2:
		_max_combo_mult = maxi(_max_combo_mult, mult)
		Fx.popup(player.global_position + Vector2(0, -48), "COMBO x%d!" % mult, Color(1.0, 0.62, 0.2), 30)
		Fx.burst(player.global_position, Color(1.0, 0.62, 0.2), 14, 260, 0.5, 1.0)
		Fx.ring(player.global_position, Color(1.0, 0.62, 0.2, 0.9), 72.0, 3.0, 0.24)
		Fx.hitstop(0.035)
		Fx.shake(3.0, 0.12)
		Sfx.play("powerup", 1.05 + 0.08 * mult)
		if _max_combo_mult >= 5:
			Achievements.unlock("combo_x5")
	_coins_collected += 1
	_coins.erase(c)
	if _coins_collected >= 100:
		Achievements.unlock("coins_100")
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
		var label := "COMBO x%d" % mult
		var stepped_up := combo_label.text != label
		combo_label.text = label
		combo_label.modulate = Color(1.0, 0.62, 0.2)
		if stepped_up:
			combo_label.pivot_offset = combo_label.size * 0.5
			combo_label.scale = Vector2(1.25, 1.25)
			var tw := combo_label.create_tween()
			tw.tween_property(combo_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		combo_label.text = ""
		combo_label.scale = Vector2.ONE

func _tick_magnet(delta: float) -> void:
	if player.magnet_left <= 0.0:
		return
	var radius: float = player.effective_magnet_radius()
	if radius <= 0.0:
		return
	var radius_squared: float = radius * radius
	var target: Vector2 = player.global_position
	for coin_ref: Variant in _coins:
		if not is_instance_valid(coin_ref):
			continue
		var coin: Coin = coin_ref as Coin
		var offset: Vector2 = target - coin.global_position
		var distance_squared: float = offset.length_squared()
		if distance_squared < radius_squared and distance_squared > 1.0:
			coin.global_position = coin.global_position.move_toward(target, 640.0 * delta)

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
	# The touch buttons render above this panel; disable them so a paused-tree
	# tap can't fire a phantom dash that burns the cooldown, and so they don't
	# sit on top of the cards.
	if touch_controls != null:
		touch_controls.set_controls_enabled(false)
	var id: String = await upgrade_chosen
	if not is_inside_tree():
		return
	_hide_upgrade_panel()
	get_tree().paused = false
	if _game_over:
		return
	# Re-enable the on-screen controls only on a live resume (a game over keeps
	# them disabled so they never float over the game-over panel).
	if touch_controls != null:
		touch_controls.set_controls_enabled(true)
	_apply_buff(id)

func _pick_upgrade_choices() -> Array[String]:
	var pool: Array[String] = []
	for id in BUFFS:
		var meta: Dictionary = BUFFS[id]
		# Repeatable entries are always available, so the pool can never empty.
		if meta.get("repeat", false):
			pool.append(id)
			continue
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
	# Reflect the real card count in the hint instead of hardcoding "1 / 2 / 3".
	if choices.size() >= 3:
		upgrade_hint.text = "Press 1 / 2 / 3 or click to choose"
	else:
		var keys := PackedStringArray()
		for i in choices.size():
			keys.append(str(i + 1))
		upgrade_hint.text = "Press %s or click to choose" % " / ".join(keys)
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
	btn.theme_type_variation = &"Card"
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
	name_label.theme_type_variation = &"Heading"
	box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = str(meta["desc"])
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.theme_type_variation = &"Small"
	box.add_child(desc_label)
	# Footer chip: makes stack-vs-one-off clarity impossible to miss.
	var chip := Label.new()
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if meta.has("one_off"):
		chip.text = "ONCE PER RUN"
		chip.theme_type_variation = &"ChipOnce"
	elif meta.get("repeat", false):
		chip.text = "REPEATABLE  (taken %d)" % int(_repeat_counts.get(id, 0))
		chip.theme_type_variation = &"ChipRepeat"
	else:
		var used := int(_stack_counts.get(id, 0))
		chip.text = "STACK  %d / %d" % [used + 1, int(meta["stack"])]
		chip.theme_type_variation = &"ChipStack"
	box.add_child(chip)
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
			player.heal(2)
		"maxhp":
			player.increase_max_hp(1)
			_build_hearts()
		"combo":
			_combo_window += 2.0
		"value":
			_coin_value_bonus += 2
		"shock":
			player.shockwave = true
		"overcharge":
			GameState.add_score(250)
			player.speed_mult = minf(player.speed_mult * 1.03, 2.6)
		"repair":
			if player.hp < player.max_hp:
				player.heal(2)
			else:
				GameState.add_score(150)
		"reserve":
			if not player.has_shield:
				player.has_shield = true
				player.shield_changed.emit(true)
			else:
				GameState.add_score(250)
	if meta.has("one_off"):
		_taken_one_offs.append(id)
	elif meta.get("repeat", false):
		_repeat_counts[id] = int(_repeat_counts.get(id, 0)) + 1
	else:
		_stack_counts[id] = int(_stack_counts.get(id, 0)) + 1
	_update_power_icons()
	_update_hearts()

# --- Damage / death --------------------------------------------------------

func _on_player_hit() -> void:
	_combo = 0
	_hit_this_wave = true
	_update_combo_ui()
	_flash_tint()
	Sfx.play("hurt")
	Fx.shake(8.0, 0.25)
	Fx.hitstop(0.12)

func _on_player_died() -> void:
	_game_over = true
	# Dying during the wave-50 fight must not leave the boss camera zoom active
	# behind the game-over screen.
	_reset_boss_cam()
	touch_controls.set_controls_enabled(false)
	Fx.burst(player.global_position, Color(1.0, 0.5, 0.3), 42, 460, 1.0, 1.8)
	Fx.shake(16.0, 0.5)
	Fx.hitstop(0.28)
	Sfx.play("gameover")
	Music.play("gameover")
	# A new record beats the stored best at the moment of death; show it as a
	# distinct badge without disturbing the existing "Best:" line format.
	var is_new_best := GameState.score > 0 and GameState.score >= GameState.best_score
	GameState.save_best()
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	game_over_panel.visible = true
	# Freeze the world behind the panel: otherwise the surviving drones keep
	# swarming the corpse and the boss keeps firing at a dead player for as long
	# as the game-over screen is up. The panel itself is PROCESS_MODE_ALWAYS, so
	# Retry / Menu stay live; _retry() and _to_menu() both unpause first.
	get_tree().paused = true
	final_score.text = "Score: %d" % GameState.score
	final_best.text = "Best: %d" % GameState.best_score
	new_best.visible = is_new_best

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
	_set_low_hp(player.hp <= 1)

## Low HP must read as danger: the whole health cluster pulses red (colour +
## motion) rather than just recolouring one heart.
func _set_low_hp(low: bool) -> void:
	if low == _low_hp:
		return
	_low_hp = low
	if _low_hp_tween != null and _low_hp_tween.is_valid():
		_low_hp_tween.kill()
	if low:
		hearts_backing.pivot_offset = hearts_backing.size * 0.5
		_low_hp_tween = hearts_backing.create_tween().set_loops()
		_low_hp_tween.set_parallel(true)
		_low_hp_tween.tween_property(hearts_backing, "modulate", Color(1.0, 0.45, 0.4, 1.0), 0.35)
		_low_hp_tween.tween_property(hearts_backing, "scale", Vector2(1.06, 1.06), 0.35)
		_low_hp_tween.chain().set_parallel(true)
		_low_hp_tween.tween_property(hearts_backing, "modulate", Color.WHITE, 0.35)
		_low_hp_tween.tween_property(hearts_backing, "scale", Vector2.ONE, 0.35)
	else:
		hearts_backing.modulate = Color.WHITE
		hearts_backing.scale = Vector2.ONE

func _on_shield_changed(_active: bool) -> void:
	_update_power_icons()

func _on_magnet_changed(_active: bool) -> void:
	_update_power_icons()

func _update_power_icons() -> void:
	shield_icon.visible = player.has_shield
	magnet_icon.visible = player.magnet_left > 0.0

func _on_score_changed(_new: int) -> void:
	_update_ui()

func _update_hud_layout() -> void:
	if not is_node_ready():
		return
	GameUILayout.apply(hud_canvas, get_viewport_rect().size)

func _update_ui() -> void:
	score_label.text = "Score: %d" % GameState.score
	wave_label.text = "Wave: %d" % _wave

func _show_banner(text: String) -> void:
	banner.text = text
	banner.modulate.a = 0.0
	banner.scale = Vector2(0.6, 0.6)
	banner.visible = true
	# Kill any in-flight banner tween: its fade-out callback could otherwise
	# hide a banner that was just shown.
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	var tw := banner.create_tween()
	_banner_tween = tw
	tw.set_parallel(true)
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.7)
	tw.tween_property(banner, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void: banner.visible = false)

func _retry() -> void:
	# reload_current_scene() does NOT reset SceneTree.paused or the engine time
	# scale, so a retry from a paused/over state would boot a frozen run.
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()

func _to_menu() -> void:
	# Leave paused state first so the menu isn't frozen.
	Engine.time_scale = 1.0
	_set_paused(false)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
