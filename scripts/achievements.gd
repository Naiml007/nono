extends Node
## Autoload achievement tracker. Unlocks persist to user:// and every new unlock
## shows a toast banner. Currently one achievement: "Let Me Solo Her".

signal achievement_unlocked(id: String)

const SAVE_PATH := "user://nono_achievements.cfg"
const ACHIEVEMENTS := {
	"let_me_solo_her": {
		"name": "Let Me Solo Her",
		"desc": "Defeat the Wave 50 boss without help.",
	},
}

var _unlocked: Dictionary = {}

func _ready() -> void:
	load_unlocked()

## Returns true if this was a brand-new unlock (false if already earned).
func unlock(id: String) -> bool:
	if _unlocked.has(id):
		return false
	_unlocked[id] = true
	save_unlocked()
	achievement_unlocked.emit(id)
	_show_toast(id)
	return true

func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)

## Returns every defined achievement with its display info and unlock state,
## for UI listing (main menu achievements panel).
func get_all() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id in ACHIEVEMENTS:
		var meta: Dictionary = ACHIEVEMENTS[id]
		list.append({
			"id": id,
			"name": str(meta.get("name", id)),
			"desc": str(meta.get("desc", "")),
			"unlocked": is_unlocked(id),
		})
	return list

func unlocked_count() -> int:
	return _unlocked.size()

func total_count() -> int:
	return ACHIEVEMENTS.size()

func save_unlocked() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("achievements", "unlocked", _unlocked.keys())
	cfg.save(SAVE_PATH)

func load_unlocked() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var ids: Array = cfg.get_value("achievements", "unlocked", [])
		for id in ids:
			_unlocked[str(id)] = true

func _show_toast(id: String) -> void:
	var meta: Dictionary = ACHIEVEMENTS.get(id, {"name": id, "desc": ""})
	var layer := CanvasLayer.new()
	layer.layer = 200
	get_tree().root.add_child(layer)
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "ACHIEVEMENT UNLOCKED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	box.add_child(title)
	var name_label := Label.new()
	name_label.text = str(meta.get("name", id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = str(meta.get("desc", ""))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	box.add_child(desc_label)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.12, 0.96)
	style.border_color = Color(1.0, 0.8, 0.25, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 44.0
	style.content_margin_right = 44.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	panel.modulate.a = 0.0
	panel.reset_size()
	await get_tree().process_frame
	panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	panel.position = Vector2((vp.x - panel.size.x) * 0.5, -panel.size.y - 8.0)
	Sfx.play("powerup")
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(panel, "position:y", 24.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(4.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)
