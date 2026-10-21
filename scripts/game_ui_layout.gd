class_name GameUILayout
extends RefCounted
## Shared, deterministic placement for the gameplay HUD at the design and expanded viewport sizes.

const COMPACT_WIDTH: float = 1024.0
const COMPACT_HEIGHT: float = 600.0
const MAX_BOSS_BAR_WIDTH: float = 520.0
const MIN_INLINE_BOSS_BAR_WIDTH: float = 180.0
const BOSS_BAR_HEIGHT: float = 56.0
const TINY_WIDTH: float = 600.0

static func apply(hud: CanvasLayer, viewport_size: Vector2) -> void:
	if hud == null or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var compact: bool = viewport_size.x <= COMPACT_WIDTH or viewport_size.y <= COMPACT_HEIGHT
	var tiny: bool = viewport_size.x <= TINY_WIDTH
	var edge_margin: float = 8.0 if tiny else (12.0 if compact else 16.0)
	var health_height: float = 76.0
	var score_panel_height: float = 68.0
	var menu_width: float = minf(80.0 if tiny else (104.0 if compact else 134.0), maxf(viewport_size.x - edge_margin * 2.0, 1.0))
	var menu_left: float = viewport_size.x - edge_margin - menu_width
	if tiny:
		menu_left = maxf(viewport_size.x * 0.5 + 12.0, menu_left)
	var health_width: float = minf(278.0 if not compact else 230.0, maxf(viewport_size.x - edge_margin * 2.0, 1.0))
	var desired_readout_width: float = minf(228.0 if compact else 284.0, viewport_size.x * (0.48 if tiny else 0.30))
	var panel: Control = hud.get_node("HUDPanel") as Control
	var health_panel: Control = hud.get_node("HeartsBacking") as Control
	var hearts: HBoxContainer = hud.get_node("Hearts") as HBoxContainer
	var shield_icon: Control = hud.get_node("ShieldIcon") as Control
	var magnet_icon: Control = hud.get_node("MagnetIcon") as Control
	var score_label: Control = hud.get_node("ScoreLabel") as Control
	var wave_label: Control = hud.get_node("WaveLabel") as Control
	var menu_button: Control = hud.get_node("MenuButton") as Control
	var boss_bar: Control = hud.get_node("BossBar") as Control

	health_panel.position = Vector2(edge_margin, edge_margin)
	health_panel.size = Vector2(health_width, health_height)
	var icon_size: float = 24.0 if tiny else (26.0 if compact else 36.0)
	var indicator_lane: float = icon_size * 2.0 + 16.0
	var heart_count: int = hearts.get_child_count()
	var heart_content_width: float = maxf(health_width - indicator_lane - 24.0, 1.0)
	var heart_icon_size: float = minf(22.0 if compact else 26.0, heart_content_width / maxf(float(heart_count), 1.0))
	var heart_gap: float = minf(5.0 if compact else 8.0, maxf((heart_content_width - heart_count * heart_icon_size) / maxf(float(heart_count - 1), 1.0), 0.0))
	var heart_total_width: float = float(heart_count) * heart_icon_size + float(maxi(heart_count - 1, 0)) * heart_gap
	hearts.position = Vector2(edge_margin + 10.0, edge_margin + (16.0 if compact else 20.0))
	hearts.size = Vector2(minf(heart_total_width, heart_content_width), 30.0)
	hearts.add_theme_constant_override("separation", int(roundf(heart_gap)))
	for heart: Control in hearts.get_children():
		heart.custom_minimum_size = Vector2(heart_icon_size, heart_icon_size)
		heart.size = heart.custom_minimum_size
	shield_icon.position = Vector2(edge_margin + health_width - icon_size * 2.0 - 16.0, edge_margin + 10.0)
	magnet_icon.position = Vector2(edge_margin + health_width - icon_size - 8.0, edge_margin + 10.0)
	shield_icon.size = Vector2(icon_size, icon_size)
	magnet_icon.size = Vector2(icon_size, icon_size)

	menu_button.anchor_left = 1.0
	menu_button.anchor_right = 1.0
	menu_button.anchor_top = 0.0
	menu_button.anchor_bottom = 0.0
	menu_button.offset_left = -edge_margin - menu_width
	menu_button.offset_right = -edge_margin
	menu_button.offset_top = edge_margin
	menu_button.offset_bottom = edge_margin + (34.0 if compact else 38.0)
	if tiny:
		var menu_left_from_center: float = menu_left - viewport_size.x
		menu_button.offset_left = menu_left_from_center
		menu_button.offset_right = menu_left_from_center + menu_width

	if tiny:
		var readout_top: float = edge_margin + health_height + 4.0
		var compact_score_left: float = edge_margin + 8.0
		var compact_score_right: float = viewport_size.x - edge_margin - 8.0
		panel.position = Vector2(edge_margin, readout_top)
		panel.size = Vector2(viewport_size.x - edge_margin * 2.0, score_panel_height)
		score_label.anchor_left = 0.0
		score_label.anchor_right = 0.0
		wave_label.anchor_left = 0.0
		wave_label.anchor_right = 0.0
		score_label.offset_left = compact_score_left
		score_label.offset_right = compact_score_right
		score_label.offset_top = readout_top + 2.0
		score_label.offset_bottom = score_label.offset_top + 30.0
		wave_label.offset_left = compact_score_left
		wave_label.offset_right = compact_score_right
		wave_label.offset_top = score_label.offset_bottom + 2.0
		wave_label.offset_bottom = wave_label.offset_top + 22.0
		var tiny_boss_width: float = minf(MAX_BOSS_BAR_WIDTH, maxf(viewport_size.x - edge_margin * 2.0, 1.0))
		var tiny_boss_left: float = (viewport_size.x - tiny_boss_width) * 0.5
		boss_bar.anchor_left = 0.0
		boss_bar.anchor_right = 0.0
		boss_bar.anchor_top = 0.0
		boss_bar.anchor_bottom = 0.0
		boss_bar.offset_left = tiny_boss_left
		boss_bar.offset_right = tiny_boss_left + tiny_boss_width
		boss_bar.offset_top = readout_top + score_panel_height + 8.0
		boss_bar.offset_bottom = boss_bar.offset_top + BOSS_BAR_HEIGHT
		return

	var left_gutter: float = edge_margin + health_width + 12.0
	var standard_menu_left: float = viewport_size.x - edge_margin - menu_width
	var score_right: float = standard_menu_left - 12.0
	var available_readout_width: float = maxf(score_right - left_gutter - 12.0, 0.0)
	var readout_width: float = minf(desired_readout_width, available_readout_width)
	var score_left: float = score_right - readout_width
	panel.position = Vector2(score_left - 8.0, edge_margin - 4.0)
	panel.size = Vector2(readout_width + 16.0, score_panel_height)
	var score_anchor_left: float = score_left - viewport_size.x
	var score_anchor_right: float = score_right - viewport_size.x
	score_label.anchor_left = 1.0
	score_label.anchor_right = 1.0
	score_label.anchor_top = 0.0
	score_label.anchor_bottom = 0.0
	score_label.offset_left = score_anchor_left
	score_label.offset_right = score_anchor_right
	score_label.offset_top = edge_margin + (2.0 if compact else 4.0)
	score_label.offset_bottom = score_label.offset_top + (32.0 if compact else 38.0)
	wave_label.anchor_left = 1.0
	wave_label.anchor_right = 1.0
	wave_label.anchor_top = 0.0
	wave_label.anchor_bottom = 0.0
	wave_label.offset_left = score_anchor_left
	wave_label.offset_right = score_anchor_right
	wave_label.offset_top = score_label.offset_bottom + 2.0
	wave_label.offset_bottom = wave_label.offset_top + 24.0

	var boss_left: float = edge_margin + health_width + 24.0
	var boss_right: float = score_left - 12.0
	var inline_boss_space: float = maxf(boss_right - boss_left, 0.0)
	boss_bar.anchor_left = 0.0
	boss_bar.anchor_right = 0.0
	boss_bar.anchor_top = 0.0
	boss_bar.anchor_bottom = 0.0
	if inline_boss_space >= MIN_INLINE_BOSS_BAR_WIDTH:
		var boss_width: float = minf(inline_boss_space, MAX_BOSS_BAR_WIDTH)
		var boss_position: float = boss_left + (inline_boss_space - boss_width) * 0.5
		boss_bar.offset_left = boss_position
		boss_bar.offset_right = boss_position + boss_width
		boss_bar.offset_top = 10.0
	else:
		var fallback_width: float = minf(MAX_BOSS_BAR_WIDTH, maxf(viewport_size.x - edge_margin * 2.0, 1.0))
		var fallback_left: float = (viewport_size.x - fallback_width) * 0.5
		boss_bar.offset_left = fallback_left
		boss_bar.offset_right = fallback_left + fallback_width
		boss_bar.offset_top = edge_margin + health_height + 12.0
	boss_bar.offset_bottom = boss_bar.offset_top + BOSS_BAR_HEIGHT