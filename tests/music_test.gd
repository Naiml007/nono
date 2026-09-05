extends Node
## Verifies the Music autoload + chiptune BGM integration end-to-end:
## 1) Music autoload is registered and ready
## 2) All 4 tracks load as loopable AudioStreamWAV
## 3) Music.play() crossfades between tracks (menu -> battle -> boss)
## 4) main_menu.tscn boots cleanly (its _ready calls Music.play("menu"))

var _failures := 0

func _ready() -> void:
	test_music()

func test_music() -> void:
	await get_tree().process_frame

	# --- 1) autoload present ---
	var music := get_node_or_null("/root/Music")
	_check(music != null, "Music autoload is registered")
	if music == null:
		_finish()
		return
	await get_tree().process_frame

	# --- 2) all tracks loaded + looping ---
	_check(music._streams.size() == 4, "all 4 tracks preloaded (%d)" % music._streams.size())
	for key: String in ["menu", "battle", "boss", "gameover"]:
		var s: AudioStreamWAV = music._streams.get(key)
		_check(s is AudioStreamWAV, "track '%s' loads as AudioStreamWAV" % key)
		if s is AudioStreamWAV:
			_check(s.loop_mode == AudioStreamWAV.LOOP_FORWARD, "track '%s' is loop-enabled" % key)
			_check(s.loop_end > 0, "track '%s' has a loop length (%.2fs)" % [key, s.get_length()])

	# --- 3) crossfade switches tracks ---
	music.play("battle")
	await get_tree().process_frame
	_check(music._active == "battle", "play(battle) activates battle")
	var playing: int = 0
	for p: AudioStreamPlayer in music._players:
		if p.playing:
			playing += 1
	_check(playing >= 1, "at least one music player is playing")
	music.play("boss")
	await get_tree().process_frame
	_check(music._active == "boss", "play(boss) crossfades to boss")
	music.play("boss")
	await get_tree().process_frame
	_check(music._active == "boss", "re-playing same track is a no-op")

	# --- 4) main menu boots (proves main_menu.gd compiles with Music.play) ---
	var menu: PackedScene = load("res://scenes/main_menu.tscn")
	_check(menu != null, "main_menu.tscn loads")
	var menu_node := menu.instantiate()
	add_child(menu_node)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(menu_node != null and is_instance_valid(menu_node), "main_menu instantiates and runs")
	_check(music._active == "menu", "menu boot switched music to menu (active=%s)" % music._active)
	menu_node.queue_free()

	_finish()

func _check(ok: bool, what: String) -> void:
	if ok:
		print("PASS: ", what)
	else:
		_failures += 1
		print("FAIL: ", what)

func _finish() -> void:
	print("MUSIC TEST ", "PASSED" if _failures == 0 else "FAILED (%d)" % _failures)
	# Exit cleanly so repeated/CI runs don't accumulate a lingering scene tree.
	get_tree().quit()
