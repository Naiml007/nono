extends Node
## Autoload singleton that carries run state across scenes and persists the best score.

signal score_changed(new_score: int)
signal best_changed(new_best: int)
signal settings_changed

var score: int = 0
var best_score: int = 0
var kills: int = 0
var wave: int = 0

## Control settings (persisted to user://nono_settings.cfg).
var wasd_controls: bool = true
var mouse_dash: bool = true
## On-screen touch controls (virtual joystick + dash/pause buttons). Defaults
## on: they only appear when a touch happens and auto-hide on keyboard/mouse.
var touch_controls: bool = true
## Audio + display settings (persisted in the same file).
var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var fullscreen: bool = false

const SAVE_PATH := "user://nono_save.cfg"
const SETTINGS_PATH := "user://nono_settings.cfg"
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "Sfx"

## Arrow keys always map to movement; WASD is added on top when enabled.
const ARROW_KEYS := {
	"move_left": KEY_LEFT,
	"move_right": KEY_RIGHT,
	"move_up": KEY_UP,
	"move_down": KEY_DOWN,
}
const WASD_KEYS := {
	"move_left": KEY_A,
	"move_right": KEY_D,
	"move_up": KEY_W,
	"move_down": KEY_S,
}

func _ready() -> void:
	# Window title is set at runtime so we never rename the project (that would
	# move the user:// data folder and lose saves).
	DisplayServer.window_set_title("NONO - Endless Space Survival")
	load_best()
	load_settings()
	_setup_input_actions()

# --- Settings --------------------------------------------------------------

func set_wasd_controls(value: bool) -> void:
	if wasd_controls == value:
		return
	wasd_controls = value
	_apply_wasd_binding()
	save_settings()
	settings_changed.emit()

func set_mouse_dash(value: bool) -> void:
	if mouse_dash == value:
		return
	mouse_dash = value
	save_settings()
	settings_changed.emit()

func set_touch_controls(value: bool) -> void:
	if touch_controls == value:
		return
	touch_controls = value
	save_settings()
	settings_changed.emit()

func set_master_volume(value: float) -> void:
	if is_equal_approx(master_volume, value):
		return
	master_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_music_volume(value: float) -> void:
	if is_equal_approx(music_volume, value):
		return
	music_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_sfx_volume(value: float) -> void:
	if is_equal_approx(sfx_volume, value):
		return
	sfx_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_fullscreen(value: bool) -> void:
	if fullscreen == value:
		return
	fullscreen = value
	apply_display()
	save_settings()
	settings_changed.emit()

## Push the stored volumes onto the audio buses (0 -> -80 dB / effectively muted).
func apply_audio() -> void:
	_apply_bus_volume(BUS_MASTER, master_volume)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_apply_bus_volume(BUS_SFX, sfx_volume)

func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, -80.0 if linear <= 0.0 else linear_to_db(clampf(linear, 0.0001, 1.0)))

## Apply the fullscreen setting to the window (no-op under the headless server).
func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "wasd", wasd_controls)
	cfg.set_value("controls", "mouse_dash", mouse_dash)
	cfg.set_value("controls", "touch", touch_controls)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)

## Read settings back. Every value is type-sanitized and falls back to defaults,
## so a missing or corrupted user://nono_settings.cfg can never break startup.
## A missing file resets to defaults rather than trusting whatever in-memory
## values happen to be there (covers mid-session deletes and re-loads too).
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		wasd_controls = true
		mouse_dash = true
		touch_controls = true
		master_volume = 1.0
		music_volume = 1.0
		sfx_volume = 1.0
		fullscreen = false
		_apply_wasd_binding()
		apply_audio()
		apply_display()
		return
	wasd_controls = _coerce_bool(cfg.get_value("controls", "wasd", true), true)
	mouse_dash = _coerce_bool(cfg.get_value("controls", "mouse_dash", true), true)
	touch_controls = _coerce_bool(cfg.get_value("controls", "touch", true), true)
	master_volume = _coerce_volume(cfg.get_value("audio", "master", 1.0), 1.0)
	music_volume = _coerce_volume(cfg.get_value("audio", "music", 1.0), 1.0)
	sfx_volume = _coerce_volume(cfg.get_value("audio", "sfx", 1.0), 1.0)
	fullscreen = _coerce_bool(cfg.get_value("display", "fullscreen", false), false)
	_apply_wasd_binding()
	apply_audio()
	apply_display()

## bool coercion that never trusts the stored type (a corrupted string like
## "false" must not become true).
func _coerce_bool(value: Variant, default: bool) -> bool:
	match typeof(value):
		TYPE_BOOL: return value
		TYPE_INT: return value != 0
		TYPE_FLOAT: return value != 0.0
		TYPE_STRING:
			var s := (value as String).to_lower().strip_edges()
			if s in ["true", "1", "yes", "on"]:
				return true
			if s in ["false", "0", "no", "off"]:
				return false
	return default

func _coerce_volume(value: Variant, default: float) -> float:
	match typeof(value):
		TYPE_FLOAT, TYPE_INT:
			return clampf(float(value), 0.0, 1.0)
		TYPE_STRING:
			if (value as String).is_valid_float():
				return clampf((value as String).to_float(), 0.0, 1.0)
	return default

## Wipe best score + achievements (preferences/settings are kept). Used by the
## in-game "reset progress" option and for support/debugging.
func reset_progress() -> void:
	best_score = 0
	save_best()
	best_changed.emit(best_score)
	var ach := get_node_or_null("/root/Achievements")
	if ach != null and ach.has_method("reset"):
		ach.reset()

# --- Input actions ----------------------------------------------------------

func _setup_input_actions() -> void:
	for action: String in ARROW_KEYS:
		_bind_key(action, ARROW_KEYS[action])
	# Dash: Space + Shift are always bound.
	_bind_key("dash", KEY_SPACE)
	_bind_key("dash", KEY_SHIFT)
	# Pause menu: Escape.
	_bind_key("pause", KEY_ESCAPE)
	_apply_wasd_binding()

## Add/remove the WASD key bindings based on the current setting.
func _apply_wasd_binding() -> void:
	for action: String in WASD_KEYS:
		_unbind_key(action, WASD_KEYS[action])
	if wasd_controls:
		for action: String in WASD_KEYS:
			_bind_key(action, WASD_KEYS[action])

func _bind_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	for existing: InputEvent in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	InputMap.action_add_event(action, ev)

func _unbind_key(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		return
	for existing: InputEvent in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == keycode:
			InputMap.action_erase_event(action, existing)

## Reset the run's score / stats. Called when a new game starts.
func reset_run() -> void:
	score = 0
	kills = 0
	wave = 0
	score_changed.emit(score)

## Add points and track the best score.
func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)
	if score > best_score:
		best_score = score
		best_changed.emit(best_score)

func register_kill() -> void:
	kills += 1

func save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "best", best_score)
	cfg.save(SAVE_PATH)

func load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = maxi(0, int(cfg.get_value("meta", "best", 0)))
	else:
		best_score = 0
