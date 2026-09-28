class_name TouchControls
extends CanvasLayer
## On-screen touch controls for phones: a thumb-anchored virtual joystick that
## drives the SAME move_* input actions as the keyboard (so player.gd has zero
## touch code), plus DASH and PAUSE buttons.
##
## - The joystick appears where the thumb touches (left side of the screen) and
##   feeds the move actions via Input.action_press/release with analog strength.
## - Auto-shows on the first touch; auto-hides on any keyboard or real-mouse
##   event (a touch-emulated mouse is ignored for hiding).
## - DASH emits dash_pressed -> game.gd routes it through player.try_dash(), the
##   single dash implementation shared with keyboard and mouse. PAUSE emits
##   pause_requested -> game.gd opens the existing pause overlay.
## - Godot synthesizes mouse events from touches; while touch mode is active the
##   ones landing in the joystick zone (and not on a button) are swallowed so a
##   joystick touch never also triggers the mouse-click dash.

signal dash_pressed
signal pause_requested

const BUTTON_SIZE := 97.0
const BUTTON_MARGIN := 18.0
const JOYSTICK_RADIUS := 70.0
const KNOB_RADIUS := 30.0
const DEAD_ZONE := 0.18
## The joystick may only anchor in the left JOYSTICK_ZONE_X fraction of the
## screen, so a thumb tap on the right never fights the dash button.
const JOYSTICK_ZONE_X := 0.62

## Cleared by game.gd while a menu is up (pause / game over / upgrades) so the
## controls don't float over it.
var enabled := true

var _touch_mode := false
var _active_finger := -1
var _origin := Vector2.ZERO
var _vec := Vector2.ZERO
## Move actions this joystick currently holds (via Input.action_press). Only
## these are released, so a simultaneously-held keyboard key is never dropped.
var _held: Dictionary = {}

var _inset_left := 0.0
var _inset_top := 0.0
var _inset_right := 0.0
var _inset_bottom := 0.0

@onready var joystick: JoystickVisual = %Joystick
@onready var dash_button: Button = %DashButton
@onready var pause_button: Button = %PauseButton

func _ready() -> void:
	layer = 5
	# Single source of truth: the drawn radius must match the input math.
	joystick.radius = JOYSTICK_RADIUS
	joystick.knob_radius = KNOB_RADIUS
	dash_button.button_down.connect(_on_dash_down)
	pause_button.button_down.connect(_on_pause_down)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	set_touch_mode(false)

func _process(_delta: float) -> void:
	_update_visibility()
	# Input.action_press only holds for the frame it was called on, so re-assert
	# the move actions every frame while a finger is down. This also covers a
	# stationary hold, which produces no drag events of its own.
	_update_actions()

func _input(event: InputEvent) -> void:
	if not GameState.touch_controls:
		return
	if event is InputEventScreenTouch:
		_on_screen_touch(event)
	elif event is InputEventScreenDrag:
		_on_screen_drag(event)
	elif event is InputEventKey:
		# A real keyboard event means desktop intent: leave touch mode.
		set_touch_mode(false)
	elif (event is InputEventMouseButton or event is InputEventMouseMotion) \
			and not Input.is_emulating_mouse_from_touch():
		# A genuine mouse (not one emulated from a touch) hides the controls.
		set_touch_mode(false)
	elif _touch_mode and enabled and event is InputEventMouseButton \
			and Input.is_emulating_mouse_from_touch():
		# Touch-emulated click (Godot synthesizes mouse events from touches):
		# swallow any that don't land on a button, so a stray touch on a phone
		# never also fires the mouse-click dash. The DASH button is the only
		# touch dash path. A genuine desktop mouse is not emulated and is never
		# swallowed, so its click-dash keeps working.
		var mb := event as InputEventMouseButton
		if not _over_any_button(mb.position):
			get_viewport().set_input_as_handled()

func _on_screen_touch(event: InputEventScreenTouch) -> void:
	set_touch_mode(true)
	if not enabled:
		return
	if event.pressed:
		if _over_any_button(event.position):
			return
		if not _in_joystick_zone(event.position):
			return
		_start_joystick(event.index, event.position)
	else:
		if event.index == _active_finger:
			_stop_joystick()

func _on_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index != _active_finger or not enabled:
		return
	var delta := event.position - _origin
	if delta.length() > JOYSTICK_RADIUS:
		delta = delta.normalized() * JOYSTICK_RADIUS
	_set_stick(delta / JOYSTICK_RADIUS)

func _start_joystick(finger: int, pos: Vector2) -> void:
	_active_finger = finger
	_origin = pos
	_set_stick(Vector2.ZERO)

func _stop_joystick() -> void:
	_active_finger = -1
	_clear_held()
	_set_stick(Vector2.ZERO)

## Store the stick vector, update the visual knob and re-push the actions
## immediately so input feels instant.
func _set_stick(v: Vector2) -> void:
	_vec = v
	joystick.set_stick(_origin, _vec)
	_update_actions()

## Push the current stick vector onto the move_* actions. A dead zone near the
## anchor is remapped so small nudges produce no drift and the stick ramps
## smoothly to full speed.
func _update_actions() -> void:
	# No finger: nothing to do (held actions are cleared on finger-up).
	if _active_finger < 0:
		return
	var av := Vector2.ZERO
	if _vec.length() > DEAD_ZONE:
		var s := clampf((_vec.length() - DEAD_ZONE) / (1.0 - DEAD_ZONE), 0.0, 1.0)
		av = _vec.normalized() * s
	_apply_axis("move_left", "move_right", av.x)
	_apply_axis("move_up", "move_down", av.y)

func _apply_axis(neg: StringName, pos: StringName, value: float) -> void:
	if value > 0.001:
		Input.action_press(pos, value)
		_hold(pos)
		_release_held(neg)
	elif value < -0.001:
		Input.action_press(neg, -value)
		_hold(neg)
		_release_held(pos)
	else:
		_release_held(neg)
		_release_held(pos)

func _hold(action: StringName) -> void:
	_held[action] = true

## Release an action ONLY if this joystick pressed it, so a physical keyboard
## key held at the same time is never dropped.
func _release_held(action: StringName) -> void:
	if _held.has(action):
		_held.erase(action)
		Input.action_release(action)

func _clear_held() -> void:
	for action: StringName in _held.keys():
		Input.action_release(action)
	_held.clear()

func _on_dash_down() -> void:
	if enabled:
		dash_pressed.emit()

func _on_pause_down() -> void:
	if enabled:
		pause_requested.emit()

func set_touch_mode(active: bool) -> void:
	_touch_mode = active
	if not active:
		_stop_joystick()
	_update_visibility()

## game.gd calls this when a menu takes over so the buttons don't float over it.
func set_controls_enabled(active: bool) -> void:
	enabled = active
	if not active:
		_stop_joystick()
	_update_visibility()

func _update_visibility() -> void:
	var visible_now := _touch_mode and enabled and GameState.touch_controls
	dash_button.visible = visible_now
	pause_button.visible = visible_now
	# The joystick only makes sense while a thumb is actually steering it (it
	# appears at the touch point); hide it when no finger is down.
	joystick.visible = visible_now and _active_finger >= 0

func _in_joystick_zone(pos: Vector2) -> bool:
	return pos.x <= get_viewport().get_visible_rect().size.x * JOYSTICK_ZONE_X

func _over_any_button(pos: Vector2) -> bool:
	for btn: Control in [dash_button, pause_button]:
		if btn.visible and btn.get_global_rect().has_point(pos):
			return true
	return false

# --- Safe area --------------------------------------------------------------

## Query the display safe area (notch / home-bar insets) and push the buttons
## in from the physical screen edges. Physical -> logical via the stretch scale.
func _apply_safe_area() -> void:
	var win := get_window()
	var win_px := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	# On desktop/headless the safe area is the whole display (or zero); that
	# yields zero insets once clamped, which is what we want there.
	if safe.size == Vector2i.ZERO:
		safe = Rect2i(Vector2i.ZERO, win_px)
	var css := Vector2(win.content_scale_size)
	if css.x <= 0.0 or css.y <= 0.0 or win_px.x <= 0 or win_px.y <= 0:
		_inset_left = 0.0
		_inset_top = 0.0
		_inset_right = 0.0
		_inset_bottom = 0.0
		_layout_buttons()
		return
	var scale_f := Vector2(win_px) / css
	var safe_logical := Rect2(Vector2(safe.position) / scale_f, Vector2(safe.size) / scale_f)
	var vp := get_viewport().get_visible_rect().size
	_inset_left = maxf(safe_logical.position.x, 0.0)
	_inset_top = maxf(safe_logical.position.y, 0.0)
	_inset_right = maxf(vp.x - (safe_logical.position.x + safe_logical.size.x), 0.0)
	_inset_bottom = maxf(vp.y - (safe_logical.position.y + safe_logical.size.y), 0.0)
	_layout_buttons()

func _layout_buttons() -> void:
	# Dash: bottom-right corner.
	dash_button.offset_left = -BUTTON_SIZE - BUTTON_MARGIN - _inset_right
	dash_button.offset_top = -BUTTON_SIZE - BUTTON_MARGIN - _inset_bottom
	dash_button.offset_right = -BUTTON_MARGIN - _inset_right
	dash_button.offset_bottom = -BUTTON_MARGIN - _inset_bottom
	# Pause: bottom-left corner.
	pause_button.offset_left = BUTTON_MARGIN + _inset_left
	pause_button.offset_top = -BUTTON_SIZE - BUTTON_MARGIN - _inset_bottom
	pause_button.offset_right = BUTTON_MARGIN + _inset_left + BUTTON_SIZE
	pause_button.offset_bottom = -BUTTON_MARGIN - _inset_bottom
