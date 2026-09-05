class_name MainMenu
extends Control
## Game-themed main menu: animated space backdrop, Play/Settings/Achievements/
## Quit, a settings panel that toggles WASD movement and mouse-click dash, and
## an achievements panel listing every unlock. ESC opens/closes the overlays.

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var achievements_button: Button = %AchievementsButton
@onready var quit_button: Button = %QuitButton
@onready var best_label: Label = %BestLabel
@onready var controls_hint: Label = %ControlsHint
@onready var settings_overlay: Control = %SettingsOverlay
@onready var wasd_toggle: CheckButton = %WasdToggle
@onready var mouse_dash_toggle: CheckButton = %MouseDashToggle
@onready var back_button: Button = %BackButton
@onready var title_logo: TextureRect = %Logo
@onready var robot: TextureRect = %Robot
@onready var achievements_overlay: Control = %AchievementsOverlay
@onready var achievements_title: Label = %AchievementsTitle
@onready var achievements_list: VBoxContainer = %AchievementsList
@onready var achievements_back: Button = %AchievementsBack

func _ready() -> void:
	# Set initial toggle state before connecting so ready-time signal fires are no-ops.
	wasd_toggle.button_pressed = GameState.wasd_controls
	mouse_dash_toggle.button_pressed = GameState.mouse_dash

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_open_settings)
	achievements_button.pressed.connect(_open_achievements)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_close_settings)
	achievements_back.pressed.connect(_close_achievements)
	wasd_toggle.toggled.connect(_on_wasd_toggled)
	mouse_dash_toggle.toggled.connect(_on_mouse_dash_toggled)

	best_label.text = "BEST SCORE: %d" % GameState.best_score
	_update_controls_hint()
	_animate_title()
	_animate_robot()
	Music.play("menu")

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if settings_overlay.visible:
		_close_settings()
	elif achievements_overlay.visible:
		_close_achievements()

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

# --- Achievements -----------------------------------------------------------

func _open_achievements() -> void:
	_populate_achievements()
	achievements_overlay.visible = true
	achievements_back.grab_focus()

func _close_achievements() -> void:
	achievements_overlay.visible = false
	achievements_button.grab_focus()

## Rebuild the achievement list from the autoload so locked/unlocked state is
## always current when the panel opens.
func _populate_achievements() -> void:
	for child in achievements_list.get_children():
		achievements_list.remove_child(child)
		child.free()
	var all: Array[Dictionary] = Achievements.get_all()
	achievements_title.text = "ACHIEVEMENTS   %d / %d" % [Achievements.unlocked_count(), Achievements.total_count()]
	for entry in all:
		achievements_list.add_child(_build_achievement_row(entry))

func _build_achievement_row(entry: Dictionary) -> Control:
	var unlocked: bool = bool(entry.get("unlocked", false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0, 52)

	# Status icon: gold star for unlocked, dim lock-slot for locked.
	var icon := Label.new()
	icon.text = "\u2605" if unlocked else "\u25cb"
	icon.add_theme_font_size_override("font_size", 28)
	icon.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3) if unlocked else Color(0.35, 0.38, 0.45))
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	var name_label := Label.new()
	name_label.text = str(entry.get("name", ""))
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1) if unlocked else Color(0.55, 0.6, 0.7))
	text_box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = str(entry.get("desc", ""))
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88) if unlocked else Color(0.45, 0.5, 0.6))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(desc_label)
	row.add_child(text_box)

	var state := Label.new()
	state.text = "UNLOCKED" if unlocked else "LOCKED"
	state.add_theme_font_size_override("font_size", 12)
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3) if unlocked else Color(0.4, 0.45, 0.55))
	row.add_child(state)
	return row

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
