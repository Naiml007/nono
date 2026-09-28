extends Node
## Verifies the Music autoload + chiptune BGM integration end-to-end:
## 1) Music autoload is registered and ready
## 2) All 4 tracks load as loopable AudioStreamWAV
## 3) Music.play() crossfades between tracks (menu -> battle -> boss)
## 4) main_menu.tscn boots cleanly (its _ready calls Music.play("menu"))
## 5) battle-intensity tiers: tier 1 reuses battle, tiers load/loop via
##    play_battle_tier(), re-visiting an unlocked tier is a no-op
## 6) ChiptuneGenerator caching: committed tier files are preferred, and a
##    missing tier renders at most once per session (no duplicate generation)

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

	# --- 5) battle-intensity tiers ---
	# Tier 1 reuses the committed battle track: no new stream, no render.
	music.play_battle_tier(1)
	await get_tree().process_frame
	_check(music._active == "battle", "play_battle_tier(1) switches to battle (active=%s)" % music._active)
	_check(music._streams.size() == 4, "tier 1 reuses the existing battle stream (no new stream)")
	var render_base: int = ChiptuneGenerator._render_count
	music.play_battle_tier(1)
	await get_tree().process_frame
	_check(music._active == "battle", "re-visiting tier 1 is a no-op")
	_check(ChiptuneGenerator._render_count == render_base, "tier 1 never triggers a render")

	# Tier 2 loads through Music as a loopable stream and crossfades in.
	music.play_battle_tier(2)
	await get_tree().process_frame
	_check(music._active == "battle_tier_2", "play_battle_tier(2) crossfades to battle_tier_2 (active=%s)" % music._active)
	_check(music._streams.size() == 5, "tier 2 stream registered on demand (%d streams)" % music._streams.size())
	var t2: AudioStreamWAV = music._streams.get("battle_tier_2")
	_check(t2 is AudioStreamWAV, "battle_tier_2 loads as AudioStreamWAV")
	if t2 is AudioStreamWAV:
		_check(t2.loop_mode == AudioStreamWAV.LOOP_FORWARD, "battle_tier_2 loop-enabled")
		_check(t2.loop_end > 0, "battle_tier_2 has a loop length (%.2fs)" % t2.get_length())
	# Re-visiting an unlocked tier is a no-op and never re-generates.
	var before_2: int = ChiptuneGenerator._render_count
	music.play_battle_tier(2)
	await get_tree().process_frame
	_check(music._active == "battle_tier_2", "re-visiting tier 2 is a no-op")
	_check(ChiptuneGenerator._render_count == before_2, "re-visiting tier 2 did not re-generate")

	# --- 6) generator caching: committed files are preferred; a missing tier
	#       renders at most once per session.
	var c0: int = ChiptuneGenerator._render_count
	var p2: String = ChiptuneGenerator.ensure_battle_tier(2)
	_check(ChiptuneGenerator._render_count == c0, "committed tier 2 file used, no runtime render")
	_check(ResourceLoader.exists(p2), "tier 2 resolves to a committed/imported file (%s)" % p2)
	# Dedicated probe tier (no committed file) to exercise the runtime fallback
	# deterministically: clear any stale per-run cache/user:// file from an
	# earlier run, then confirm a missing tier renders exactly once per session.
	const PROBE_TIER := 42
	ChiptuneGenerator._rendered_tiers.erase(PROBE_TIER)
	var stale_path := "user://nono_music/battle_tier_%d.wav" % PROBE_TIER
	if FileAccess.file_exists(stale_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(stale_path))
	var c1: int = ChiptuneGenerator._render_count
	var pa: String = ChiptuneGenerator.ensure_battle_tier(PROBE_TIER)
	_check(ChiptuneGenerator._render_count == c1 + 1, "missing tier renders exactly once")
	var pb: String = ChiptuneGenerator.ensure_battle_tier(PROBE_TIER)
	_check(pa == pb, "re-visiting a rendered tier returns the same path")
	_check(ChiptuneGenerator._render_count == c1 + 1, "re-visiting a rendered tier does not re-render")
	var raw: Variant = AudioStreamWAV.load_from_file(pa)
	_check(raw is AudioStreamWAV and raw.get_length() > 0.0,
		"runtime-rendered tier is playable audio (%.2fs)" % (raw.get_length() if raw is AudioStreamWAV else -1.0))

	# --- 7) Task 1: a second play() inside FADE_TIME must not silence the track.
	# The old code left both players stopped because the first crossfade's
	# stop() callback targeted the player that became the new incoming track. ---
	music.play("menu")
	await get_tree().create_timer(0.4).timeout
	music.play("battle")
	await get_tree().create_timer(1.6).timeout
	var audible: int = 0
	var playing_stream := ""
	for p: AudioStreamPlayer in music._players:
		if p.playing and p.volume_db > -60.0:
			audible += 1
			playing_stream = p.stream.resource_path.get_file()
	_check(audible == 1, "rapid double play() leaves exactly one audible player (got %d)" % audible)
	_check(playing_stream == "battle_theme.wav",
		"the surviving track after a rapid double play() is battle (got '%s')" % playing_stream)
	_check(music._active == "battle", "rapid double play() leaves _active consistent (got '%s')" % music._active)

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
