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
@onready var touch_toggle: CheckButton = %TouchToggle
@onready var master_slider: HSlider = %MasterVolumeSlider
@onready var music_slider: HSlider = %MusicVolumeSlider
@onready var sfx_slider: HSlider = %SfxVolumeSlider
@onready var master_value: Label = %MasterVolumeValue
@onready var music_value: Label = %MusicVolumeValue
@onready var sfx_value: Label = %SfxVolumeValue
@onready var fullscreen_toggle: CheckButton = %FullscreenToggle
@onready var reset_button: Button = %ResetProgressButton
@onready var reset_confirm: ConfirmationDialog = %ResetConfirm
@onready var back_button: Button = %BackButton
@onready var title_logo: TextureRect = %Logo
@onready var reduce_motion_toggle: CheckButton = %ReduceMotionToggle
@onready var achievements_overlay: Control = %AchievementsOverlay
@onready var achievements_title: Label = %AchievementsTitle
@onready var achievements_list: VBoxContainer = %AchievementsList
@onready var achievements_back: Button = %AchievementsBack

func _ready() -> void:
	# Set initial toggle state before connecting so ready-time signal fires are no-ops.
	play_button.focus_mode = Control.FOCUS_ALL
	play_button.grab_focus()
	_set_responsive_layout()
	get_viewport().size_changed.connect(_set_responsive_layout)
	wasd_toggle.button_pressed = GameState.wasd_controls
	mouse_dash_toggle.button_pressed = GameState.mouse_dash
	touch_toggle.button_pressed = GameState.touch_controls
	reduce_motion_toggle.button_pressed = GameState.reduce_motion
	fullscreen_toggle.button_pressed = GameState.fullscreen
	master_slider.value = GameState.master_volume
	music_slider.value = GameState.music_volume
	sfx_slider.value = GameState.sfx_volume
	master_value.text = "%d%%" % roundi(GameState.master_volume * 100)
	music_value.text = "%d%%" % roundi(GameState.music_volume * 100)
	sfx_value.text = "%d%%" % roundi(GameState.sfx_volume * 100)

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_open_settings)
	achievements_button.pressed.connect(_open_achievements)
	quit_button.pressed.connect(_on_quit_pressed)
	back_button.pressed.connect(_close_settings)
	achievements_back.pressed.connect(_close_achievements)
	wasd_toggle.toggled.connect(_on_wasd_toggled)
	mouse_dash_toggle.toggled.connect(_on_mouse_dash_toggled)
	touch_toggle.toggled.connect(_on_touch_toggled)
	reduce_motion_toggle.toggled.connect(_on_reduce_motion_toggled)
	master_slider.value_changed.connect(_on_master_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	reset_confirm.confirmed.connect(_on_reset_confirmed)

	best_label.text = "BEST SCORE: %d" % GameState.best_score
	_update_controls_hint()
	_animate_title()
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

func _set_responsive_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var compact_landscape: bool = viewport_size.x <= 760.0 or viewport_size.y <= 440.0
	var narrow_layout: bool = viewport_size.x / maxf(viewport_size.y, 1.0) < 1.55
	var menu_center: CenterContainer = $Center
	var menu_panel: PanelContainer = $Center/Panel
	var menu_box: VBoxContainer = $Center/Panel/VBox
	var short_view: bool = viewport_size.y < 620.0
	var button_width: float = clampf(viewport_size.x * (0.62 if compact_landscape else 0.40), 220.0, 420.0)
	var button_height: float = 36.0 if short_view else (44.0 if compact_landscape else 48.0)
	var spacing: int = 4 if short_view else 8
	menu_panel.custom_minimum_size = Vector2(button_width + 32.0, 0.0)
	menu_box.add_theme_constant_override("separation", spacing)
	for menu_button: Button in [play_button, settings_button, achievements_button, quit_button]:
		menu_button.custom_minimum_size = Vector2(button_width, button_height)
	var logo: TextureRect = title_logo
	logo.custom_minimum_size = Vector2(minf(button_width, 360.0), 64.0 if short_view else (96.0 if compact_landscape else 120.0))
	$Center/Panel/VBox/Spacer.custom_minimum_size.y = 0.0 if short_view else 12.0
	if narrow_layout:
		menu_center.anchor_left = 0.025
		menu_center.anchor_right = 0.975
		menu_center.anchor_top = 0.015
		menu_center.anchor_bottom = 0.985
	else:
		menu_center.anchor_left = 0.025 if compact_landscape else 0.04
		menu_center.anchor_right = 0.52 if compact_landscape else 0.49
		menu_center.anchor_top = 0.015 if compact_landscape else 0.035
		menu_center.anchor_bottom = 0.985 if compact_landscape else 0.965
	var compact_settings: bool = viewport_size.y < 620.0 or viewport_size.x < 1000.0
	var settings_box: VBoxContainer = $SettingsOverlay/SettingsCenter/SettingsPanel/SettingsVBox
	var settings_panel: PanelContainer = $SettingsOverlay/SettingsCenter/SettingsPanel
	var settings_center: CenterContainer = $SettingsOverlay/SettingsCenter
	settings_box.add_theme_constant_override("separation", 8 if compact_settings else 16)
	settings_panel.custom_minimum_size.x = minf(420.0, maxf(viewport_size.x - 32.0, 320.0))
	settings_center.offset_left = 12.0 if compact_settings else 0.0
	settings_center.offset_top = 8.0 if compact_settings else 0.0
	settings_center.offset_right = -12.0 if compact_settings else 0.0
	settings_center.offset_bottom = -8.0 if compact_settings else 0.0
	var achievement_panel: PanelContainer = $AchievementsOverlay/AchievementsCenter/AchievementsPanel
	var achievement_scroll: ScrollContainer = $AchievementsOverlay/AchievementsCenter/AchievementsPanel/AchievementsVBox/AchievementsScroll
	achievement_panel.custom_minimum_size.x = minf(600.0, maxf(viewport_size.x - 32.0, 288.0))
	achievement_scroll.custom_minimum_size = Vector2(minf(540.0, maxf(viewport_size.x - 96.0, 224.0)), minf(360.0, maxf(viewport_size.y - 190.0, 180.0)))
	var hint: Label = controls_hint
	hint.visible = not narrow_layout and (not compact_landscape or viewport_size.x > 900.0)
	hint.position = Vector2(viewport_size.x * 0.51 - 310.0, viewport_size.y - 34.0)
	best_label.visible = true
	$SettingsOverlay/SettingsDim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$AchievementsOverlay/AchievementsDim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$SettingsOverlay/SettingsDim.color.a = 0.72
	$AchievementsOverlay/AchievementsDim.color.a = 0.72

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

func _on_touch_toggled(value: bool) -> void:
	GameState.set_touch_controls(value)
	_update_controls_hint()

func _on_reduce_motion_toggled(value: bool) -> void:
	GameState.set_reduce_motion(value)

func _on_master_volume_changed(value: float) -> void:
	GameState.set_master_volume(value)
	master_value.text = "%d%%" % roundi(value * 100)

func _on_music_volume_changed(value: float) -> void:
	GameState.set_music_volume(value)
	music_value.text = "%d%%" % roundi(value * 100)

func _on_sfx_volume_changed(value: float) -> void:
	GameState.set_sfx_volume(value)
	sfx_value.text = "%d%%" % roundi(value * 100)

func _on_fullscreen_toggled(value: bool) -> void:
	GameState.set_fullscreen(value)

func _on_reset_pressed() -> void:
	reset_confirm.popup_centered()

func _on_reset_confirmed() -> void:
	GameState.reset_progress()
	best_label.text = "BEST SCORE: %d" % GameState.best_score

func _update_controls_hint() -> void:
	var move := "WASD / Arrows" if GameState.wasd_controls else "Arrows"
	var dash := "Space / Shift"
	if GameState.mouse_dash:
		dash += " / Click"
	if GameState.touch_controls:
		dash += " / Touch"
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
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size = Vector2(0, 52)
	# Locked rows dim as a whole (modulate) instead of carrying per-label colour
	# overrides, so every colour token stays in the shared theme.
	if not unlocked:
		row.modulate = Color(1, 1, 1, 0.55)

	# Status icon: gold star for unlocked, dim lock-slot for locked.
	var icon := Label.new()
	icon.text = "\u2605" if unlocked else "\u25cb"
	icon.theme_type_variation = &"AchIcon"
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 4)
	var name_label := Label.new()
	name_label.text = str(entry.get("name", ""))
	name_label.theme_type_variation = &"AchName"
	text_box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = str(entry.get("desc", ""))
	desc_label.theme_type_variation = &"AchDesc"
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(desc_label)
	row.add_child(text_box)

	var state := Label.new()
	state.text = "UNLOCKED" if unlocked else "LOCKED"
	state.theme_type_variation = &"AchState"
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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

func _set_pivot(node: Control) -> void:
	node.pivot_offset = node.size * 0.5
