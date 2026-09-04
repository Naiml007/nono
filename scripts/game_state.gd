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

const SAVE_PATH := "user://nono_save.cfg"
const SETTINGS_PATH := "user://nono_settings.cfg"

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

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("controls", "wasd", wasd_controls)
	cfg.set_value("controls", "mouse_dash", mouse_dash)
	cfg.save(SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	wasd_controls = bool(cfg.get_value("controls", "wasd", true))
	mouse_dash = bool(cfg.get_value("controls", "mouse_dash", true))

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
		best_score = cfg.get_value("meta", "best", 0)
