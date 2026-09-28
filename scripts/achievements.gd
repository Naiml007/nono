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
	"wave_10": {
		"name": "Marathoner",
		"desc": "Reach wave 10 in a single run.",
	},
	"wave_25": {
		"name": "Veteran",
		"desc": "Reach wave 25 in a single run.",
	},
	"combo_x5": {
		"name": "Combo Machine",
		"desc": "Hit a x5 score multiplier.",
	},
	"coins_100": {
		"name": "Coin Hoarder",
		"desc": "Collect 100 energy cores in one run.",
	},
	"untouchable": {
		"name": "Untouchable",
		"desc": "Clear a wave without taking a hit.",
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
	_unlocked.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var ids: Variant = cfg.get_value("achievements", "unlocked", [])
		if ids is Array:
			for id in ids:
				if ACHIEVEMENTS.has(str(id)):
					_unlocked[str(id)] = true

## Wipe all unlocks and persist the cleared state. Used by "reset progress".
func reset() -> void:
	_unlocked.clear()
	save_unlocked()

func _show_toast(id: String) -> void:
	var meta: Dictionary = ACHIEVEMENTS.get(id, {"name": id, "desc": ""})
	var layer := CanvasLayer.new()
	layer.layer = 200
	get_tree().root.add_child(layer)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"FloatPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "ACHIEVEMENT UNLOCKED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"ToastTitle"
	box.add_child(title)
	var name_label := Label.new()
	name_label.text = str(meta.get("name", id))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.theme_type_variation = &"ToastName"
	box.add_child(name_label)
	var desc_label := Label.new()
	desc_label.text = str(meta.get("desc", ""))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.theme_type_variation = &"ToastDesc"
	box.add_child(desc_label)
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
