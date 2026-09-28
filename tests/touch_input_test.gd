extends Node
## Verifies the touch controls: the virtual joystick drives the same move_*
## actions as the keyboard, DASH/PAUSE buttons route through the existing game
## code paths, auto-show/hide on touch vs keyboard, emulated-mouse swallowing
## (no accidental dash from a joystick touch), safe-area layout, and the
## persisted touch_controls setting.

var _failures := 0
var _game: Node2D = null
var _tc: TouchControls = null
var _player: Player = null

func _ready() -> void:
	var backup := UserFilesHelper.snapshot()
	await get_tree().process_frame

	# Force a 1280x720 logical viewport so button hit-rects sit in the corners
	# like they do on a real device (headless default is 64x64).
	var win := get_window()
	win.content_scale_size = Vector2i(1280, 720)
	DisplayServer.window_set_size(Vector2i(1280, 720), 0)
	await get_tree().process_frame

	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(_game)
	await get_tree().process_frame
	await get_tree().process_frame

	_tc = _game.touch_controls
	_player = _game.player
	# Quiet the arena so enemy/coin motion can't interfere with assertions.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	for c in get_tree().get_nodes_in_group("coins"):
		c.queue_free()
	await get_tree().process_frame

	_check(GameState.touch_controls, "touch controls setting defaults ON")
	_check(_tc != null and _tc.dash_button != null and _tc.pause_button != null,
		"game scene has a TouchControls layer with dash + pause buttons")
	_check(not _tc._touch_mode, "touch mode off before any touch")
	_check(not _tc.dash_button.visible and not _tc.pause_button.visible,
		"buttons hidden before first touch")

	# --- Auto-show on touch (end-to-end through _input) ---
	_send_touch(0, Vector2(300, 300), true)
	await get_tree().process_frame
	_check(_tc._touch_mode, "first touch activates touch mode")
	_check(_tc.dash_button.visible and _tc.pause_button.visible, "buttons visible in touch mode")

	# Joystick handlers are driven directly with viewport-space events:
	# Input.parse_input_event scales ScreenTouch/Drag coordinates by the
	# window/viewport stretch factor in headless, which pushes a finger at
	# (300,300) outside the joystick zone. The handlers themselves take
	# viewport-space positions, so this is the environment-independent check.
	_tc._on_screen_touch(_touch_ev(0, Vector2(300, 300), true))
	_check(_tc._active_finger == 0, "joystick anchors on a touch in the left zone")
	_tc._on_screen_drag(_drag_ev(0, Vector2(370, 300)))  # +70 px right => stick at (1, 0)
	for i in 3:  # let the per-frame re-assert in _process run
		await get_tree().process_frame
	_check(Input.get_action_strength("move_right") > 0.9,
		"joystick right drives move_right action (strength %.2f)" % Input.get_action_strength("move_right"))
	_check(Input.get_vector("move_left", "move_right", "move_up", "move_down").length() > 0.9,
		"Input.get_vector reads the joystick (player.gd needs no touch code)")

	_tc._on_screen_touch(_touch_ev(0, Vector2(370, 300), false))  # release
	await get_tree().process_frame
	await get_tree().process_frame
	_check(Input.get_action_strength("move_right") < 0.01,
		"joystick release clears the move action")

	# --- Emulated-mouse swallow. Godot synthesizes mouse events from touches;
	# in headless Input.is_emulating_mouse_from_touch() is always true, which is
	# exactly the phone-touch case. While touch mode is ON, a stray emulated
	# click (not on a button) must NOT trigger the mouse-click dash — the DASH
	# button is the only touch dash path.
	_reset_dash(_player)
	_send_mouse_click_at(Vector2(300, 300))
	await get_tree().process_frame
	_check(not _player.is_dashing, "touch mode: emulated mouse click is swallowed (no dash)")

	# --- DASH button: button_down -> dash_pressed signal -> player.try_dash ---
	_reset_dash(_player)
	_tc.dash_pressed.emit()
	await get_tree().process_frame
	_check(_player.is_dashing, "DASH button (dash_pressed signal) triggers the dash")

	# --- Task 5: the upgrade panel disables / hides the touch controls ---
	# (touch mode is ON here, so visibility tracks `enabled` exactly)
	_game._offer_upgrades()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_game.upgrade_panel.visible, "upgrade panel open for touch test")
	_check(not _tc.enabled, "touch controls disabled while the upgrade panel is open")
	_check(not _tc.dash_button.visible, "dash button hidden while the upgrade panel is open")
	_reset_dash(_player)
	_tc._on_dash_down()  # goes through the enabled guard
	await get_tree().process_frame
	_check(not _player.is_dashing, "dash is ignored while the upgrade panel is open")
	_game._on_upgrade_choice_index(0)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_tc.enabled, "touch controls re-enabled after the upgrade choice")

	# --- Auto-hide on keyboard ---
	_send_key(KEY_A)
	await get_tree().process_frame
	_check(not _tc._touch_mode, "keyboard event leaves touch mode")
	_check(not _tc.dash_button.visible and not _tc.pause_button.visible,
		"buttons hidden after keyboard event")

	# --- With touch mode OFF a mouse click dashes again (desktop mouse_dash
	# path, never swallowed). ---
	_reset_dash(_player)
	_send_mouse_click_at(Vector2(1100, 300))
	await get_tree().process_frame
	_check(_player.is_dashing, "mouse click dashes when touch mode is off (mouse_dash path)")

	# --- Player clamps to the fixed 1280x720 arena, not the viewport ---
	_player.global_position = Vector2(2000, -500)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p: Vector2 = _player.global_position
	_check(p.x >= 0.0 and p.x <= 1280.0 and p.y >= 0.0 and p.y <= 720.0,
		"player clamps inside the arena (got %s)" % p)

	# --- Safe-area layout: buttons anchored to the bottom corners and at least
	# 88px. Asserted via anchors/offsets (device-independent) because the
	# headless viewport size is not the 1280x720 design size. ---
	var dr: Rect2 = _tc.dash_button.get_global_rect()
	var pr: Rect2 = _tc.pause_button.get_global_rect()
	_check(_tc.dash_button.anchor_left == 1.0 and _tc.dash_button.anchor_top == 1.0,
		"dash button anchored to the bottom-right corner")
	_check(_tc.pause_button.anchor_left == 0.0 and _tc.pause_button.anchor_top == 1.0,
		"pause button anchored to the bottom-left corner")
	_check(_tc.dash_button.offset_left < 0.0 and _tc.dash_button.offset_top < 0.0,
		"dash button offsets point inward from the bottom-right")
	_check(_tc.pause_button.offset_left >= 0.0 and _tc.pause_button.offset_top < 0.0,
		"pause button offsets point inward from the bottom-left")
	_check(dr.size.x >= 88.0 and dr.size.y >= 88.0, "dash button >= 88px touch target (%s)" % dr.size)
	_check(pr.size.x >= 88.0 and pr.size.y >= 88.0, "pause button >= 88px touch target (%s)" % pr.size)

	# --- Setting persists + disables touch controls ---
	GameState.set_touch_controls(false)
	_check(not GameState.touch_controls, "set_touch_controls(false) stores the value")
	_send_touch(0, Vector2(300, 300), true)
	await get_tree().process_frame
	_check(not _tc._touch_mode, "touch does nothing while touch controls are disabled")
	GameState.set_touch_controls(true)
	GameState.load_settings()
	_check(GameState.touch_controls, "touch_controls value survives save/load round-trip")

	UserFilesHelper.restore(backup)
	_summary()

func _reset_dash(p: Player) -> void:
	p.is_dashing = false
	p._cd_left = 0.0
	p._invuln_left = 0.0

# --- Input synthesis --------------------------------------------------------

func _touch_ev(index: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	return ev

func _drag_ev(index: int, pos: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	return ev

func _send_touch(index: int, pos: Vector2, pressed: bool) -> void:
	Input.parse_input_event(_touch_ev(index, pos, pressed))

func _send_key(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.physical_keycode = key
	Input.parse_input_event(ev)

## Click at a VIEWPORT-space position. Input.parse_input_event expects
## window-space coordinates and the engine scales them to viewport space by the
## stretch factor (20x in headless, 1x on a real 1280x720 window), so convert
## first to make the test environment-independent.
func _send_mouse_click_at(vp_pos: Vector2) -> void:
	var k := get_viewport().get_visible_rect().size / Vector2(DisplayServer.window_get_size())
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = vp_pos / k
	Input.parse_input_event(ev)

# --- Assertions -------------------------------------------------------------

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== TOUCH INPUT TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
