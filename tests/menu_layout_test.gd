extends Node
## Regression checks for shared menu composition, responsive fitting, overlay access, and motion preference.

var _failures: int = 0
var _failed_checks: Array[String] = []
var _started: bool = false
var _finished: bool = false

signal _test_finished

func _ready() -> void:
	if get_tree().current_scene == self:
		call_deferred("_start_scene_test")

func _start_scene_test() -> void:
	if _started:
		return
	_started = true
	_run_menu_layout()

func test_menu_composition_and_hud_layout() -> void:
	if not _started:
		_started = true
		_run_menu_layout()
	if not _finished:
		await _test_finished
	assert(_failures == 0, "Menu layout regression checks found %d failure(s): %s" % [_failures, ", ".join(_failed_checks)])

func _run_menu_layout() -> void:
	await get_tree().process_frame
	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn") as PackedScene
	var menu: MainMenu = menu_scene.instantiate() as MainMenu
	add_child(menu)
	await get_tree().process_frame
	_check(menu.play_button.has_focus(), "Play is keyboard/gamepad focused on menu entry")
	var initial_viewport: Vector2 = get_viewport().get_visible_rect().size
	var initial_is_narrow: bool = initial_viewport.x / maxf(initial_viewport.y, 1.0) < 1.55
	var initial_is_compact_landscape: bool = initial_viewport.x <= 760.0 or initial_viewport.y <= 440.0
	_check(not menu.get_node("SpaceBackdrop/Background").has_node("HeroFrame"),
		"the shared space backdrop does not include a separate HeroFrame node")
	_check(not menu.has_node("RobotHero"),
		"no second robot hero is drawn above the shared artwork")
	var menu_backdrop: SpaceBackdrop = menu.get_node("SpaceBackdrop") as SpaceBackdrop
	_check(not menu_backdrop.is_processing(),
		"menu backdrop skips camera parallax when no gameplay target is configured")
	_check(menu.get_node("Center/Panel/VBox/BestLabel").visible,
		"best-score readout remains part of the primary menu")
	_check(menu.controls_hint.visible == (not initial_is_narrow and (not initial_is_compact_landscape or initial_viewport.x > 900.0)),
		"control hint visibility follows the compact/portrait responsive mode")
	var menu_panel: Control = menu.get_node("Center/Panel") as Control
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_check(menu_panel.get_global_rect().position.x >= 0.0 and menu_panel.get_global_rect().end.x <= viewport_size.x,
		"menu panel fits inside the current viewport")
	menu._open_settings()
	await get_tree().process_frame
	_check(menu.settings_overlay.visible, "settings overlay remains reachable")
	_check(menu.get_node("SettingsOverlay/SettingsCenter/SettingsPanel/SettingsVBox/ReduceMotionToggle") != null,
		"reduce-motion preference remains available in settings")
	_check(menu.back_button.has_focus(), "settings opening moves focus into the overlay")
	menu._close_settings()
	menu._open_achievements()
	await get_tree().process_frame
	_check(menu.achievements_overlay.visible, "achievement overlay remains reachable")
	_check(menu.achievements_list.get_child_count() == Achievements.total_count(),
		"achievement overlay displays every achievement row")
	_check(menu.achievements_back.has_focus(), "achievement opening moves focus to its back action")
	menu.queue_free()
	await get_tree().process_frame
	await _run_hud_layout_checks()
	print("==== MENU LAYOUT TEST SUMMARY: failures=%d ====" % _failures)
	_finished = true
	_test_finished.emit()
	if get_tree().current_scene == self:
		get_tree().quit()

func _run_hud_layout_checks() -> void:
	var packed_game: PackedScene = load("res://scenes/game.tscn") as PackedScene
	var probe_game: Game = packed_game.instantiate() as Game
	add_child(probe_game)
	await get_tree().process_frame
	var hud: CanvasLayer = probe_game.get_node("HUD") as CanvasLayer
	for size: Vector2 in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(960.0, 540.0), Vector2(800.0, 450.0), Vector2(480.0, 270.0)]:
		GameUILayout.apply(hud, size)
		await get_tree().process_frame
		var hearts: Rect2 = _rect_for_viewport(hud.get_node("HeartsBacking") as Control, size)
		var menu_button: Rect2 = _rect_for_viewport(hud.get_node("MenuButton") as Control, size)
		var score: Rect2 = _rect_for_viewport(hud.get_node("ScoreLabel") as Control, size)
		var wave: Rect2 = _rect_for_viewport(hud.get_node("WaveLabel") as Control, size)
		var score_panel: Rect2 = _rect_for_viewport(hud.get_node("HUDPanel") as Control, size)
		_check(_inside_viewport(hearts, size), "health panel remains inside HUD viewport %s" % size)
		_check(_inside_viewport(score_panel, size), "score panel remains inside HUD viewport %s" % size)
		var health_backing_rect: Rect2 = _rect_for_viewport(hud.get_node("HeartsBacking") as Control, size)
		_check(_inside_viewport(health_backing_rect, size), "health backing remains inside HUD viewport %s" % size)
		_check(_inside_viewport(menu_button, size), "menu button remains inside HUD viewport %s" % size)
		_check(not health_backing_rect.intersects(menu_button),
			"health and menu do not overlap %s" % size)
		_check(health_backing_rect.end.x <= menu_button.position.x - 12.0,
			"health and menu keep a 12px top-row gap %s" % size)
		_check(not menu_button.intersects(score) and not menu_button.intersects(wave),
			"HUD menu button does not overlap score/wave readouts %s" % size)
		if size.x <= GameUILayout.TINY_WIDTH:
			_check(score_panel.position.y >= menu_button.end.y + 12.0,
				"tiny score panel is stacked below the menu with a 12px gap %s" % size)
		else:
			_check(score.end.x <= menu_button.position.x - 12.0,
				"score readout keeps a 12px gap before the menu button %s" % size)
		_check(not hearts.intersects(score_panel),
			"health and readout panels remain separate %s" % size)
		var boss_bar: Control = hud.get_node("BossBar") as Control
		var boss_rect: Rect2 = _rect_for_viewport(boss_bar, size)
		var expected_boss_width: float = maxf(boss_rect.size.x, 0.0)
		_check(_inside_viewport(boss_rect, size), "boss bar remains inside HUD viewport %s" % size)
		_check(expected_boss_width <= GameUILayout.MAX_BOSS_BAR_WIDTH,
			"boss bar width remains capped in viewport %s" % size)
		_check(not boss_rect.intersects(hearts) and not boss_rect.intersects(score_panel) and not boss_rect.intersects(menu_button) and not boss_rect.intersects(score) and not boss_rect.intersects(wave),
			"boss bar stays clear of HUD clusters %s" % size)
		if size == Vector2(1280.0, 720.0):
			probe_game.debug_goto_wave(50)
			await get_tree().process_frame
			var boss_bar_live: Control = hud.get_node("BossBar") as Control
			_check(boss_bar_live.visible, "boss-wave trigger still displays the boss health bar")
			_check(_inside_viewport(boss_bar_live.get_global_rect(), size), "live boss health bar fits the HUD viewport")
			probe_game.debug_reset_run()
			await get_tree().process_frame
	probe_game.free()
	await get_tree().process_frame
	Fx.setup(null, null)
	await get_tree().process_frame

func _rect_for_viewport(control: Control, viewport_size: Vector2) -> Rect2:
	var old_size: Vector2 = get_viewport().get_visible_rect().size
	if is_equal_approx(old_size.x, viewport_size.x) and is_equal_approx(old_size.y, viewport_size.y):
		return control.get_global_rect()
	var global_position: Vector2 = control.global_position
	var relative_position: Vector2 = global_position - Vector2(old_size.x if control.anchor_left == 1.0 else 0.0, old_size.y if control.anchor_top == 1.0 else 0.0)
	var resolved_position: Vector2 = relative_position + Vector2(viewport_size.x if control.anchor_left == 1.0 else 0.0, viewport_size.y if control.anchor_top == 1.0 else 0.0)
	var resolved_size: Vector2 = control.size
	if control.anchor_right != control.anchor_left:
		resolved_size.x = viewport_size.x * (control.anchor_right - control.anchor_left) + control.offset_right - control.offset_left
	if control.anchor_bottom != control.anchor_top:
		resolved_size.y = viewport_size.y * (control.anchor_bottom - control.anchor_top) + control.offset_bottom - control.offset_top
	return Rect2(resolved_position, resolved_size)

func _inside_viewport(rect: Rect2, viewport_size: Vector2) -> bool:
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 \
		and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: ", message)
	else:
		_failures += 1
		_failed_checks.append(message)
		print("FAIL: ", message)
