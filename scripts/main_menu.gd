class_name MainMenu
extends Control
## Game-themed main menu: animated space backdrop, Play/Settings/Quit, and a
## settings panel that toggles WASD movement and mouse-click dash. ESC opens or
## closes the settings panel.

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var best_label: Label = %BestLabel
@onready var controls_hint: Label = %ControlsHint
@onready var settings_overlay: Control = %SettingsOverlay
@onready var wasd_toggle: CheckButton = %WasdToggle
@onready var mouse_dash_toggle: CheckButton = %MouseDashToggle
@onready var back_button: Button = %BackButton
@onready var title_logo: TextureRect = %Logo
@onready var robot: TextureRect = %Robot

func _ready() -> void:
	# Set initial toggle state before connecting so ready-time signal fires are no-ops.
	wasd_toggle.button_pressed = GameState.wasd_controls
	mouse_dash_toggle.button_pressed = GameState.mouse_dash

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_open_settings)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_close_settings)
	wasd_toggle.toggled.connect(_on_wasd_toggled)
	mouse_dash_toggle.toggled.connect(_on_mouse_dash_toggled)

	best_label.text = "BEST SCORE: %d" % GameState.best_score
	_update_controls_hint()
	_animate_title()
	_animate_robot()
	Music.play("menu")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and settings_overlay.visible:
		get_viewport().set_input_as_handled()
		_close_settings()

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

# --- Settings --------------------------------------------------------------

func _open_settings() -> void:
	settings_overlay.visible = true
	back_button.grab_focus()

func _close_settings() -> void:
	settings_overlay.visible = false
	settings_button.grab_focus()

func _on_wasd_toggled(value: bool) -> void:
	GameState.set_wasd_controls(value)
	_update_controls_hint()

func _on_mouse_dash_toggled(value: bool) -> void:
	GameState.set_mouse_dash(value)
	_update_controls_hint()

func _update_controls_hint() -> void:
	var move := "WASD / Arrows" if GameState.wasd_controls else "Arrows"
	var dash := "Space / Shift"
	if GameState.mouse_dash:
		dash += " / Click"
	controls_hint.text = "%s to move   ·   %s to dash" % [move, dash]

# --- Decoration -------------------------------------------------------------

func _animate_title() -> void:
	_set_pivot.call_deferred(title_logo)
	var tw := title_logo.create_tween().set_loops()
	tw.tween_property(title_logo, "scale", Vector2(1.03, 1.03), 1.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(title_logo, "scale", Vector2.ONE, 1.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _animate_robot() -> void:
	_set_pivot.call_deferred(robot)
	var tw := robot.create_tween().set_loops()
	tw.tween_property(robot, "scale", Vector2(1.07, 1.07), 1.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(robot, "scale", Vector2.ONE, 1.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_pivot(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
