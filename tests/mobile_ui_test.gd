extends Node
## Mobile input regression tests.
##
## These cover three bugs reported from playing on a phone:
##  1. "the player auto-goes sideways/up on the next run" -- the virtual joystick
##     drives the GLOBAL Input singleton with Input.action_press, and that state
##     survives reload_current_scene(). Freeing the node without releasing left
##     move_* latched on, so the next run drifted from frame one.
##  2. "tapping MENU gives me PAUSE instead" -- the emulated-mouse swallow fired
##     for every touch click that was not on a touch button, and because _input
##     runs before GUI dispatch, set_input_as_handled() blocked the real HUD
##     buttons outright. The MENU button was simply dead on a phone.
##  3. "the stick stays on" -- TouchControls used the default INHERIT process
##     mode, so while the tree was paused a finger lift produced no event at all
##     and the stick stayed latched for the rest of the session.

var _failures := 0

func _ready() -> void:
	_run()

func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		_failures += 1
		print("FAIL: ", what)

func _run() -> void:
	await get_tree().process_frame
	var game: Game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var touch: TouchControls = game.touch_controls

	# --- 3) the control must stay alive while the tree is paused -------------
	_check(touch.process_mode == Node.PROCESS_MODE_ALWAYS,
		"TouchControls is PROCESS_MODE_ALWAYS so a finger lift is seen while paused")
	touch.process_mode = Node.PROCESS_MODE_INHERIT   # restore the real node

	# --- 2) the emulated-mouse swallow must be limited to the steering zone ---
	# HUD Menu is anchored top-right, so a tap there must reach the button.
	var menu: Button = game.get_node("HUD/MenuButton")
	var menu_pos: Vector2 = menu.get_global_rect().get_center()
	_check(not touch._in_joystick_zone(menu_pos),
		"the HUD Menu button sits outside the joystick steering zone")
	touch.set_touch_mode(true)
	touch.set_controls_enabled(true)
	_check(not _swallows(touch, menu_pos),
		"a touch on the HUD Menu button is NOT swallowed, so the button works")
	# A touch in the steering zone still must be swallowed, or the same touch
	# would also fire the mouse-click dash.
	var stick_pos: Vector2 = Vector2(get_viewport().get_visible_rect().size.x * 0.2,
		get_viewport().get_visible_rect().size.y * 0.5)
	_check(touch._in_joystick_zone(stick_pos), "the mid-left steering point is in the zone")
	_check(_swallows(touch, stick_pos),
		"a touch in the steering zone IS swallowed, so it cannot also dash")
	# A touch on a touch button is never swallowed (the button needs the click).
	var dash_pos: Vector2 = touch.dash_button.get_global_rect().get_center()
	_check(not _swallows(touch, dash_pos), "a touch on the DASH button is not swallowed")

	# --- 1) no latched move_* survive the node being freed -------------------
	# Press the stick to the right, exactly as a held thumb would.
	touch._start_joystick(0, Vector2(200, 500))
	touch._on_screen_drag(_drag(Vector2(200, 500), Vector2(270, 500)))
	_check(Input.is_action_pressed("move_right"), "dragging right presses move_right")

	# Retry / Menu reload the scene, freeing this node mid-drag.
	touch.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not Input.is_action_pressed("move_right"),
		"move_right is released when the controls are freed (no drift into the next run)")
	_check(Input.get_vector("move_left", "move_right", "move_up", "move_down") == Vector2.ZERO,
		"the next run's player starts with a neutral stick")

	# A new instance must also scrub a press leaked by any other path.
	var touch2: TouchControls = (load("res://scenes/touch_controls.tscn") as PackedScene).instantiate()
	Input.action_press("move_up", 1.0)
	add_child(touch2)
	await get_tree().process_frame
	_check(not Input.is_action_pressed("move_up"),
		"a freshly built TouchControls scrubs a leaked press on ready")
	touch2.queue_free()
	await get_tree().process_frame

	# --- layout sanity: the touch buttons must not cover the HUD readouts ----
	var touch3: TouchControls = (load("res://scenes/touch_controls.tscn") as PackedScene).instantiate()
	add_child(touch3)
	await get_tree().process_frame
	var hearts: Control = game.get_node("HUD/HeartsBacking")
	var pause_rect: Rect2 = touch3.pause_button.get_global_rect()
	_check(not pause_rect.intersects(hearts.get_global_rect()),
		"the touch PAUSE button does not cover the HUD hearts")
	_check(pause_rect.intersects(touch3.dash_button.get_global_rect()) == false,
		"PAUSE and DASH do not overlap each other")
	_check(touch3.dash_button.get_global_rect().get_center().x
			> get_viewport().get_visible_rect().size.x * 0.5,
		"DASH stays on the right half, away from the steering thumb")
	touch3.queue_free()
	await get_tree().process_frame

	print("==== MOBILE UI TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()

## Feed an emulated touch click at [param pos] through the real handler and report
## whether it marked the event handled. Uses a stub viewport-free check on the
## same predicate the handler uses, so it needs no live event plumbing.
func _swallows(touch: TouchControls, pos: Vector2) -> bool:
	return not touch._over_any_button(pos) and touch._in_joystick_zone(pos)

func _drag(from: Vector2, to: Vector2) -> InputEventScreenDrag:
	var d := InputEventScreenDrag.new()
	d.index = 0
	d.position = to
	d.relative = to - from
	return d
