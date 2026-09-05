extends Node
## Headless verification of save/settings robustness:
## 1) settings save/load round-trips (incl. new volume/fullscreen keys)
## 2) missing + corrupted settings files fall back to defaults, never crash
## 3) achievements unlock and persist across a simulated reload
## 4) reset_progress() wipes best score + achievements but keeps settings
## User files are snapshotted first and restored before quitting.

var _failures := 0
var _backup: Dictionary = {}

const SAVE_PATH := "user://nono_save.cfg"
const SETTINGS_PATH := "user://nono_settings.cfg"

func _ready() -> void:
	_backup = UserFilesHelper.snapshot()
	await get_tree().process_frame

	# --- Settings round trip ---
	GameState.set_master_volume(0.42)
	GameState.set_music_volume(0.35)
	GameState.set_sfx_volume(0.61)
	GameState.set_wasd_controls(false)
	GameState.set_mouse_dash(false)
	GameState.set_fullscreen(false)
	GameState.save_settings()

	# Dirty every field, then reload from disk.
	GameState.master_volume = 9.9
	GameState.music_volume = 9.9
	GameState.sfx_volume = 9.9
	GameState.wasd_controls = true
	GameState.mouse_dash = true
	GameState.fullscreen = true
	GameState.load_settings()

	_check(is_equal_approx(GameState.master_volume, 0.42), "master volume round-trips")
	_check(is_equal_approx(GameState.music_volume, 0.35), "music volume round-trips")
	_check(is_equal_approx(GameState.sfx_volume, 0.61), "sfx volume round-trips")
	_check(GameState.wasd_controls == false, "wasd control round-trips")
	_check(GameState.mouse_dash == false, "mouse-dash control round-trips")
	_check(GameState.fullscreen == false, "fullscreen round-trips")

	# --- Missing settings file: defaults, no crash (simulate a fresh boot:
	# dirty the in-memory fields, then boot with no file on disk) ---
	GameState.wasd_controls = false
	GameState.mouse_dash = false
	GameState.master_volume = 9.9
	GameState.fullscreen = true
	_remove(SETTINGS_PATH)
	GameState.load_settings()
	_check(GameState.wasd_controls == true, "missing settings file -> default wasd on")
	_check(is_equal_approx(GameState.master_volume, 1.0), "missing settings file -> default volume 1.0")
	_check(GameState.fullscreen == false, "missing settings file -> default fullscreen off")

	# --- Corrupted settings file (wrong types stored) ---
	var bad := ConfigFile.new()
	bad.set_value("controls", "wasd", "false")      # string, not bool
	bad.set_value("controls", "mouse_dash", 0)      # int 0 -> false
	bad.set_value("audio", "music", "garbage")      # unparseable string
	bad.set_value("audio", "master", "0.8")         # valid numeric string
	bad.set_value("display", "fullscreen", "yes")   # truthy string
	bad.save(SETTINGS_PATH)
	GameState.load_settings()
	_check(GameState.wasd_controls == false, "string 'false' coerced to false (not true)")
	_check(GameState.mouse_dash == false, "int 0 coerced to false")
	_check(is_equal_approx(GameState.music_volume, 1.0), "garbage volume falls back to default 1.0")
	_check(is_equal_approx(GameState.master_volume, 0.8), "numeric string volume parsed")
	_check(GameState.fullscreen == true, "string 'yes' coerced to true")

	# --- Missing best-score file (fresh boot: stale in-memory value first) ---
	GameState.best_score = 9999
	_remove(SAVE_PATH)
	GameState.load_best()
	_check(GameState.best_score == 0, "missing save file loads best=0")

	# --- Achievements: unlock, persist across reload, idempotent re-unlock ---
	GameState.reset_progress()  # start from a clean slate
	_check(Achievements.unlocked_count() == 0, "reset_progress clears achievements")
	_check(Achievements.unlock("wave_10"), "unlock returns true for a brand-new unlock")
	Achievements._unlocked.clear()
	Achievements.load_unlocked()
	_check(Achievements.is_unlocked("wave_10"), "achievement persists across reload")
	_check(not Achievements.unlock("wave_10"), "re-unlocking an earned achievement is a no-op")

	# --- Corrupted achievement file: only known ids load ---
	Achievements._unlocked.clear()
	var bad_ach := ConfigFile.new()
	bad_ach.set_value("achievements", "unlocked", ["wave_10", "not_a_real_achievement"])
	bad_ach.save(Achievements.SAVE_PATH)
	Achievements.load_unlocked()
	_check(Achievements.is_unlocked("wave_10") and not Achievements.is_unlocked("not_a_real_achievement"),
		"unknown achievement ids from a corrupted file are ignored")

	# --- reset_progress wipes score + achievements, keeps settings ---
	GameState.best_score = 12345
	GameState.reset_progress()
	_check(GameState.best_score == 0, "reset_progress zeroes best score")
	_check(Achievements.unlocked_count() == 0, "reset_progress wipes achievements")
	_check(GameState.wasd_controls == false, "reset_progress keeps settings intact")

	UserFilesHelper.restore(_backup)
	_summary()
	get_tree().quit()

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== PROGRESS PERSISTENCE TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
