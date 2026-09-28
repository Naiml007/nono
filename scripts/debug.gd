extends CanvasLayer
## Developer tooling (autoload `Debug`): jump straight to any wave — including
## the wave-50 boss — skip/kill waves, god mode, and a live overlay that shows
## FPS, node/draw counts and, critically, the camera's visible world rect next
## to the arena rect so the "player leaves the map" class of bug is visible
## while testing.
##
## This is completely inert in a release build: every entry point no-ops unless
## OS.is_debug_build() (see [member available]) AND the developer has switched
## the tool on (see [member active], toggled with the `debug_toggle` action,
## F1). The debug input actions are registered at runtime by GameState
## (AGENTS.md gotcha #5 — input actions live in code, never project.godot).

const OVERLAY_LAYER := 90
const OVERLAY_WIDTH := 512.0

## True only in a debug build; a release export reports false and the whole
## tool stays a no-op.
var available: bool = OS.is_debug_build()
## Master switch, defaults off. F1 toggles it; while off the overlay is hidden
## and every action method returns immediately.
var active: bool = false
## God mode: the player ignores damage and the dash cooldown never blocks.
var god: bool = false

var _game: Game = null
var _panel: PanelContainer = null
var _label: Label = null

func _ready() -> void:
	layer = OVERLAY_LAYER
	# Keep the overlay ticking while the game is paused (upgrade offer / ESC).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()

func _process(_delta: float) -> void:
	if not _is_live():
		return
	_label.text = _overlay_text()

func _unhandled_input(event: InputEvent) -> void:
	# Gate 1: never in a release build.
	if not available:
		return
	if event.is_action_pressed("debug_toggle"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	# Gate 2: the explicit developer toggle must be on.
	if not active:
		return
	if event.is_action_pressed("debug_boss"):
		goto_boss()
	elif event.is_action_pressed("debug_skip"):
		skip_wave()
	elif event.is_action_pressed("debug_clear"):
		kill_all_enemies()
	elif event.is_action_pressed("debug_god"):
		set_god(not god)
	elif event.is_action_pressed("debug_reset"):
		reset_run()
	else:
		return
	get_viewport().set_input_as_handled()

# --- Lifecycle (called by Game) --------------------------------------------

## Game calls this from _ready so the tool can act on the live run. Single
## registration point: nothing else in the game reaches into Debug.
func register(game: Game) -> void:
	_game = game
	if _game != null and is_instance_valid(_game.player):
		_game.player.debug_god = god
	set_active(active)

func unregister(game: Game) -> void:
	if _game == game:
		_game = null
	if _panel != null:
		_panel.visible = false

# --- Public API ------------------------------------------------------------

func toggle() -> void:
	if not available:
		return
	set_active(not active)

func set_active(value: bool) -> void:
	active = available and value
	if _panel != null:
		_panel.visible = active and _is_live()

func is_overlay_visible() -> bool:
	return _panel != null and _panel.visible

## Jump straight to wave [param n]. Wave 50 routes through the normal boss path
## (banner, boss spawn, health bar, boss music, boss-cam priority) because it
## reuses Game._start_wave.
func goto_wave(n: int) -> void:
	if not _can_act():
		return
	_game.debug_goto_wave(n)

## One-key boss jump: drops straight into the wave-50 fight.
func goto_boss() -> void:
	goto_wave(Game.BOSS_WAVE)

func skip_wave() -> void:
	if not _can_act():
		return
	_game.debug_skip_wave()

func kill_all_enemies() -> void:
	if not _can_act():
		return
	_game.debug_kill_all_enemies()

func reset_run() -> void:
	if not _can_act():
		return
	_game.debug_reset_run()

func set_god(value: bool) -> void:
	if not available:
		return
	god = value
	if _game != null and is_instance_valid(_game) and is_instance_valid(_game.player):
		_game.player.debug_god = value

func _can_act() -> bool:
	return _is_live()

func _is_live() -> bool:
	return available and active and _game != null and is_instance_valid(_game)

# --- Overlay ----------------------------------------------------------------

func _build_overlay() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DebugOverlay"
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.offset_left = -OVERLAY_WIDTH
	_panel.offset_right = -8.0
	_panel.offset_top = 8.0
	_panel.theme_type_variation = &"DebugPanel"
	_label = Label.new()
	_label.theme_type_variation = &"DebugInfo"
	_panel.add_child(_label)
	add_child(_panel)

func _overlay_text() -> String:
	var cam: Camera2D = _game.camera
	var arena: Rect2 = _game.arena_rect()
	var rect: Rect2 = camera_view_rect(cam)
	var live_enemies := get_tree().get_nodes_in_group("enemies").size() \
			+ get_tree().get_nodes_in_group("boss").size()
	return "\n".join([
		"DEBUG  F1 hide  F2 boss  F3 skip  F4 clear  F5 god:%s  F6 reset" % ("on" if god else "off"),
		"FPS %d   wave %d   enemies %d   nodes %d   draws %d" % [
			Engine.get_frames_per_second(), GameState.wave, live_enemies,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))],
		"view (%.0f,%.0f)-(%.0f,%.0f)" % [rect.position.x, rect.position.y, rect.end.x, rect.end.y],
		"arena (%.0f,%.0f)-(%.0f,%.0f)   inside=%s" % [
			arena.position.x, arena.position.y, arena.end.x, arena.end.y, arena.encloses(rect)],
	])

## The world rect the camera currently shows, derived from its effective zoom
## and clamped screen center. Kept public so tests assert against the same math.
func camera_view_rect(cam: Camera2D) -> Rect2:
	var half: Vector2 = get_viewport().get_visible_rect().size / (cam.zoom * 2.0)
	return Rect2(cam.get_screen_center_position() - half, half * 2.0)