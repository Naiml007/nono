class_name ChiptuneGenerator
extends RefCounted
## One-shot tool that synthesizes original 8-bit / chiptune background music
## tracks as 16-bit mono WAV files into res://assets/audio/music/.
##
## Usage (run once from the editor or a headless script):
##   ChiptuneGenerator.generate_all()
##
## Tracks are rendered with classic NES-style voices:
##   square  (50% duty)  - lead melody
##   square25 (25% duty) - bouncy arpeggios
##   triangle            - bass
##   noise / kick        - percussion
## No samples or external audio are used - everything is synthesized.

const SR := 22050                      # Sample rate. Lower rate = chunkier, more "8-bit".
const OUT_DIR := "res://assets/audio/music"

# --- Procedural battle-intensity tiers ---------------------------------------
# Waves 1-49 are bucketed every BATTLE_TIER_SIZE waves into BATTLE_TIER_COUNT
# tiers. Tier 1 is bit-identical to the classic battle_theme (it reuses that
# committed file); higher tiers add deterministic layers (extra voices, denser
# percussion), raise BPM toward the boss theme's tempo, and shift key up
# late-run. Each tier is generated at most once per session.
const BATTLE_TIER_COUNT := 10
const BATTLE_TIER_SIZE := 5
const BATTLE_TIER_BPM := [144.0, 150.0, 154.0, 158.0, 162.0, 166.0, 168.0, 168.0, 168.0, 168.0]
const BATTLE_TIER_KEY := [0, 0, 0, 0, 0, 0, 1, 1, 2, 3]

## tiers already resolved this session (tier -> path); prevents duplicate renders.
static var _rendered_tiers: Dictionary = {}
## how many tracks were actually synthesized this session (test hook).
static var _render_count := 0

# --- Pitch ------------------------------------------------------------------

static func midi_to_hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

# --- Single-voice synthesis --------------------------------------------------

## Render one note into a buffer with a tiny attack and a short release so
## successive notes blend instead of clicking.
static func _synth_note(freq: float, dur: float, wave: String, attack: float, release: float) -> PackedFloat32Array:
	var n := maxi(1, int(dur * SR))
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var inc := freq / SR
	for i in n:
		phase = fmod(phase + inc, 1.0)
		var s := 0.0
		match wave:
			"square": s = 1.0 if phase < 0.5 else -1.0
			"square25": s = 1.0 if phase < 0.25 else -1.0
			"triangle": s = 4.0 * absf(phase - 0.5) - 1.0
			"saw": s = 2.0 * phase - 1.0
			_: s = sin(TAU * phase)
		var t := float(i) / SR
		var env := 1.0
		if t < attack:
			env = t / maxf(attack, 0.0001)
		var rt := dur - t
		if rt < release:
			env = minf(env, rt / maxf(release, 0.0001))
		out[i] = s * env
	return out

## White-noise burst with an exponential decay - used for hats and snares.
static func _noise_burst(dur: float, decay: float, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var n := maxi(1, int(dur * SR))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		out[i] = rng.randf_range(-1.0, 1.0) * exp(-t * decay)
	return out

## Kick drum: sine with a fast pitch drop (classic 8-bit "thump").
static func _kick(dur: float) -> PackedFloat32Array:
	var n := maxi(1, int(dur * SR))
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / SR
		var f := lerpf(170.0, 44.0, minf(t / dur, 1.0))
		phase += f / SR
		out[i] = sin(TAU * phase) * exp(-t * 9.0)
	return out

# --- Sequencing helpers ------------------------------------------------------

## Convert a list of [step, midi, length_in_steps] into [start_sec, dur_sec, hz].
static func _to_notes(seq: Array, step_dur: float) -> Array:
	var out: Array = []
	for e in seq:
		out.append([e[0] * step_dur, e[2] * step_dur, midi_to_hz(float(e[1]))])
	return out

## Offset a list of per-bar [step, midi, len] patterns into one long sequence.
## Each bar is assumed to be 16 steps.
static func _bars(patterns: Array) -> Array:
	var out: Array = []
	for i in patterns.size():
		for note: Array in patterns[i]:
			out.append([int(note[0]) + 16 * i, int(note[1]), int(note[2])])
	return out

## Root + fifth 8th-note bass pattern for one bar (root, fifth, octave, fifth).
static func _bass_root5(root: int) -> Array:
	var pat: Array = []
	for s in [0, 2, 4, 6, 8, 10, 12, 14]:
		var note := root
		if s % 4 == 2:
			note = root + 12
		elif s % 4 == 3:
			note = root + 7
		pat.append([s, note, 2])
	return pat

## Driving 8th-note root/octave bass for one bar.
static func _bass_oct(root: int) -> Array:
	var pat: Array = []
	for s in [0, 2, 4, 6, 8, 10, 12, 14]:
		pat.append([s, root + (12 if s % 4 == 1 else 0), 2])
	return pat

## 16th-note broken chord (a,b,c,d repeated) for one bar.
static func _arp_chord(a: int, b: int, c: int, d: int) -> Array:
	var pat: Array = []
	for i in 4:
		pat.append([i * 4 + 0, a, 1])
		pat.append([i * 4 + 1, b, 1])
		pat.append([i * 4 + 2, c, 1])
		pat.append([i * 4 + 3, d, 1])
	return pat

# --- Mixing / rendering -------------------------------------------------------

static func _mix_into(master: PackedFloat32Array, voice: PackedFloat32Array) -> void:
	for i in mini(master.size(), voice.size()):
		master[i] += voice[i]

## Place a burst (kick/hat/snare) at start_sec with a volume.
static func _place(master: PackedFloat32Array, burst: PackedFloat32Array, start_sec: float, vol: float) -> void:
	var i0 := int(start_sec * SR)
	for i in burst.size():
		var idx := i0 + i
		if idx >= 0 and idx < master.size():
			master[idx] += burst[i] * vol

## Render one voice's note list into its own buffer.
static func _render_notes(seq: Array, total_sec: float, wave: String, vol: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(total_sec * SR))
	for n in seq:
		var tone := _synth_note(n[2], n[1], wave, 0.004, 0.06)
		var i0 := int(n[0] * SR)
		for i in tone.size():
			var idx := i0 + i
			if idx >= 0 and idx < buf.size():
				buf[idx] += tone[i] * vol
	return buf

## Render percussion (per-bar step patterns expanded across all bars).
static func _render_drums(master: PackedFloat32Array, drums: Dictionary, bars: int, step_dur: float) -> void:
	var kick_burst := _kick(0.14)
	var hat_burst := _noise_burst(0.05, 70.0, 999)
	var snare_burst := _noise_burst(0.12, 45.0, 4242)
	var kick_steps: Array = drums.get("kick", [])
	var hat_steps: Array = drums.get("hat", [])
	var snare_steps: Array = drums.get("snare", [])
	var open_steps: Array = drums.get("open", [])
	var crash_steps: Array = drums.get("crash", [])
	var open_burst := _noise_burst(0.12, 30.0, 5005)
	var crash_burst := _noise_burst(0.4, 20.0, 31337)
	for b in bars:
		for s: int in kick_steps:
			_place(master, kick_burst, (16 * b + s) * step_dur, 0.9)
		for s: int in hat_steps:
			_place(master, hat_burst, (16 * b + s) * step_dur, 0.28)
		for s: int in snare_steps:
			_place(master, snare_burst, (16 * b + s) * step_dur, 0.5)
		for s: int in open_steps:
			_place(master, open_burst, (16 * b + s) * step_dur, 0.25)
	for s: int in crash_steps:
		_place(master, crash_burst, s * step_dur, 0.5)

## Peak-normalize and add tiny edge fades so the loop point doesn't click.
static func _finish(buf: PackedFloat32Array) -> void:
	var peak := 0.0
	for i in buf.size():
		var a := absf(buf[i])
		if a > peak:
			peak = a
	if peak > 0.0001:
		var g := 0.9 / peak
		for i in buf.size():
			buf[i] *= g
	var f := int(0.02 * SR)
	for i in mini(f, buf.size()):
		var e := float(i) / maxf(float(f), 1.0)
		buf[i] *= e
		buf[buf.size() - 1 - i] *= e

## Render a whole song dictionary and write it to OUT_DIR/<name>.wav, or to
## `path` when given (e.g. the user:// runtime fallback for a missing tier).
static func _render_song(song: Dictionary, path := "") -> void:
	var bpm: float = song["bpm"]
	var bars: int = int(song["bars"])
	var step_dur: float = 60.0 / bpm / 4.0
	var total_sec: float = bars * 16.0 * step_dur
	var master := PackedFloat32Array()
	master.resize(int(total_sec * SR))
	for v: Dictionary in song["voices"]:
		var seq := _to_notes(v["seq"], step_dur)
		var voice := _render_notes(seq, total_sec, v["wave"], v["vol"])
		_mix_into(master, voice)
	if song.has("drums"):
		_render_drums(master, song["drums"], bars, step_dur)
	_finish(master)
	if path.is_empty():
		path = "%s/%s.wav" % [OUT_DIR, song["name"]]
	_write_wav(path, master)
	print("Wrote %s (%.2fs)" % [path.get_file(), total_sec])

# --- WAV output ---------------------------------------------------------------

static func _write_wav(path: String, buf: PackedFloat32Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write %s" % path)
		return
	var data_size := buf.size() * 2
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data_size)
	f.store_buffer("WAVE".to_ascii_buffer())
	f.store_buffer("fmt ".to_ascii_buffer())
	f.store_32(16)          # fmt chunk size
	f.store_16(1)           # PCM
	f.store_16(1)           # mono
	f.store_32(SR)
	f.store_32(SR * 2)      # byte rate
	f.store_16(2)           # block align
	f.store_16(16)          # bits per sample
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data_size)
	for i in buf.size():
		var v := clampi(int(buf[i] * 32767.0), -32768, 32767)
		f.store_16(v & 0xFFFF)
	f.close()

# --- The four tracks -----------------------------------------------------------

static func _song_menu() -> void:
	# 112 BPM, C major. Intro: C, Am. Loop: C, Am, F, G. Calm, spacey, hopeful.
	var bass := _bars([
		_bass_root5(36), _bass_root5(33),                     # intro
		_bass_root5(36), _bass_root5(33), _bass_root5(29), _bass_root5(31),
	])
	var arp := _bars([
		_arp_chord(60, 64, 67, 72), _arp_chord(57, 60, 64, 69),
		_arp_chord(60, 64, 67, 72), _arp_chord(57, 60, 64, 69),
		_arp_chord(53, 57, 60, 65), _arp_chord(55, 59, 62, 67),
	])
	var melody := _bars([
		[], [],
		[[0, 76, 2], [2, 79, 2], [4, 84, 2], [6, 79, 2], [8, 76, 2], [10, 79, 2], [12, 81, 2], [14, 79, 2]],
		[[0, 76, 2], [2, 81, 2], [4, 84, 2], [6, 81, 2], [8, 76, 2], [10, 81, 2], [12, 83, 2], [14, 81, 2]],
		[[0, 77, 2], [2, 81, 2], [4, 84, 2], [6, 81, 2], [8, 77, 2], [10, 81, 2], [12, 79, 2], [14, 81, 2]],
		[[0, 74, 2], [2, 79, 2], [4, 83, 2], [6, 86, 2], [8, 83, 2], [10, 79, 2], [12, 81, 2], [14, 83, 2]],
	])
	var song := {
		"name": "menu_theme", "bpm": 112.0, "bars": 6,
		"voices": [
			{"wave": "triangle", "vol": 0.40, "seq": bass},
			{"wave": "square25", "vol": 0.14, "seq": arp},
			{"wave": "square", "vol": 0.21, "seq": melody},
		],
		"drums": {"kick": [0, 8], "snare": [], "hat": [2, 4, 6, 10, 12, 14]},
	}
	_render_song(song)

static func _song_battle() -> void:
	# 144 BPM, A minor. Am - F - C - G. Driving chase music for the waves.
	# Tier 1 must stay bit-identical to the classic theme, so it delegates to
	# the shared parameterized builder - "same song, more intense" by construction.
	# It renders to the classic battle_theme.wav (tier 1 never gets its own file).
	_render_song(_build_battle(1), battle_tier_path(1))

## Shared battle builder. Tier 1 reproduces the classic battle_theme exactly;
## higher tiers add deterministic layers (extra voices, denser percussion), raise
## BPM toward the boss theme's 168, and shift key up late-run. The base motif
## (bass octaves, 16th arpeggio, lead melody) is never replaced - only thickened.
static func _build_battle(tier: int) -> Dictionary:
	var t := clampi(tier, 1, BATTLE_TIER_COUNT)
	var k: int = _tier_key_shift(t)
	var bpm: float = _tier_bpm(t)
	var l2 := t >= 2   # melody octave-up shimmer
	var l3 := t >= 3   # snare on all 4 beats + open-hat downbeat accent
	var l4 := t >= 4   # melody octave-down fullness
	var l5 := t >= 5   # sustained root+5th block-chord pad
	var l6 := t >= 6   # double-time kick (8ths)
	var l8 := t >= 8   # driving root/5th/octave bass
	var l9 := t >= 9   # crash accent on bars 1 & 3

	var bass: Array
	if l8:
		bass = _bars([
			_bass_drive(33 + k), _bass_drive(29 + k), _bass_drive(36 + k), _bass_drive(31 + k),
		])
	else:
		bass = _bars([
			_bass_oct(33 + k), _bass_oct(29 + k), _bass_oct(36 + k), _bass_oct(31 + k),
		])
	var arp := _bars([
		_arp_chord(57 + k, 64 + k, 69 + k, 64 + k), _arp_chord(53 + k, 60 + k, 65 + k, 60 + k),
		_arp_chord(60 + k, 67 + k, 72 + k, 67 + k), _arp_chord(55 + k, 62 + k, 67 + k, 62 + k),
	])
	var melody := _bars([
		[[0, 81 + k, 1], [1, 84 + k, 1], [2, 81 + k, 1], [4, 79 + k, 2], [8, 76 + k, 2], [10, 79 + k, 1], [12, 81 + k, 2]],
		[[0, 77 + k, 2], [2, 81 + k, 2], [4, 84 + k, 2], [8, 81 + k, 2], [10, 79 + k, 1], [12, 77 + k, 1], [14, 74 + k, 2]],
		[[0, 76 + k, 2], [2, 72 + k, 1], [4, 76 + k, 2], [8, 79 + k, 1], [9, 81 + k, 1], [10, 84 + k, 2], [12, 81 + k, 1], [14, 79 + k, 1]],
		[[0, 79 + k, 2], [2, 74 + k, 1], [4, 79 + k, 1], [5, 83 + k, 1], [8, 86 + k, 2], [10, 83 + k, 2], [12, 81 + k, 1], [13, 83 + k, 1], [14, 84 + k, 2]],
	])
	var voices: Array = [
		{"wave": "triangle", "vol": 0.50, "seq": bass},
		{"wave": "square25", "vol": 0.16, "seq": arp},
		{"wave": "square", "vol": 0.22, "seq": melody},
	]
	if l2:
		voices.append({"wave": "square", "vol": 0.09, "seq": _transpose(melody, 12)})
	if l4:
		voices.append({"wave": "square", "vol": 0.10, "seq": _transpose(melody, -12)})
	if l5:
		voices.append({"wave": "square25", "vol": 0.10, "seq": _bars([
			_block_chords(45 + k), _block_chords(41 + k), _block_chords(48 + k), _block_chords(43 + k),
		])})
	var drums := {
		"kick": [0, 2, 4, 6, 8, 10, 12, 14] if l6 else [0, 4, 8, 12],
		"snare": [0, 4, 8, 12] if l3 else [4, 12],
		"hat": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
	}
	if l3:
		drums["open"] = [0]
	if l9:
		drums["crash"] = [0, 32]   # downbeats of bars 1 & 3
	return {
		"name": "battle_tier_%d" % t, "bpm": bpm, "bars": 4,
		"voices": voices, "drums": drums,
	}

static func _tier_bpm(tier: int) -> float:
	return BATTLE_TIER_BPM[clampi(tier - 1, 0, BATTLE_TIER_COUNT - 1)]

static func _tier_key_shift(tier: int) -> int:
	return BATTLE_TIER_KEY[clampi(tier - 1, 0, BATTLE_TIER_COUNT - 1)]

## Transpose a flat [step, midi, len] sequence by `shift` semitones.
static func _transpose(seq: Array, shift: int) -> Array:
	var out: Array = []
	for e: Array in seq:
		out.append([e[0], int(e[1]) + shift, e[2]])
	return out

## Driving root / fifth / octave / fifth 8th-note bass for one bar.
static func _bass_drive(root: int) -> Array:
	var pat: Array = []
	for i in 8:
		pat.append([i * 2, root + [0, 7, 12, 7][i % 4], 2])
	return pat

## Sustained root + fifth quarter-note block chord (2 notes at once) for one bar.
static func _block_chords(root: int) -> Array:
	var pat: Array = []
	for s in [0, 8]:
		pat.append([s, root, 4])
		pat.append([s, root + 7, 4])
	return pat

static func _song_boss() -> void:
	# 168 BPM, A minor with a tense pedal bass. Am - F - G - E(maj).
	# Relentless 16th bass + chromatic arpeggio + stabbing lead = boss tension.
	var bass := _bars([
		_arp_chord(33, 45, 33, 45), _arp_chord(29, 41, 29, 41),
		_arp_chord(31, 43, 31, 43), _arp_chord(28, 40, 28, 40),
	])
	var arp := _bars([
		_arp_chord(57, 60, 64, 69), _arp_chord(53, 57, 60, 65),
		_arp_chord(55, 59, 62, 67), _arp_chord(52, 56, 59, 64),
	])
	var melody := _bars([
		[[0, 81, 1], [1, 84, 1], [2, 88, 2], [4, 84, 1], [5, 81, 1], [6, 84, 1], [8, 81, 2], [12, 84, 1], [13, 88, 1], [14, 91, 1], [15, 88, 1]],
		[[0, 84, 1], [1, 81, 1], [2, 77, 2], [4, 81, 1], [5, 84, 1], [6, 81, 1], [8, 77, 2], [12, 84, 1], [13, 81, 1], [14, 77, 1], [15, 81, 1]],
		[[0, 83, 1], [1, 79, 1], [2, 74, 2], [4, 79, 1], [5, 83, 1], [6, 86, 1], [8, 83, 2], [12, 86, 1], [13, 83, 1], [14, 79, 1], [15, 83, 1]],
		[[0, 88, 1], [1, 84, 1], [2, 80, 2], [4, 84, 1], [5, 88, 1], [6, 92, 1], [8, 88, 2], [12, 92, 1], [13, 88, 1], [14, 84, 1], [15, 80, 1]],
	])
	var song := {
		"name": "boss_theme", "bpm": 168.0, "bars": 4,
		"voices": [
			{"wave": "triangle", "vol": 0.50, "seq": bass},
			{"wave": "square25", "vol": 0.18, "seq": arp},
			{"wave": "square", "vol": 0.24, "seq": melody},
		],
		"drums": {"kick": [0, 4, 8, 12], "snare": [4, 12], "hat": [0, 2, 4, 6, 8, 10, 12, 14]},
	}
	_render_song(song)

static func _song_game_over() -> void:
	# 70 BPM, A minor. Sparse, descending lament. No drums.
	var bass := _bars([
		_bass_root5(33), _bass_root5(31), _bass_root5(29), _bass_root5(28),
	])
	var arp := _bars([
		_arp_chord(57, 60, 64, 69), _arp_chord(55, 59, 62, 67),
		_arp_chord(53, 57, 60, 65), _arp_chord(52, 56, 59, 64),
	])
	var melody := _bars([
		[[0, 76, 4], [4, 72, 4], [8, 69, 4], [12, 64, 4]],
		[[0, 67, 4], [4, 64, 4], [8, 62, 4], [12, 59, 4]],
		[[0, 65, 4], [4, 60, 4], [8, 57, 4], [12, 53, 4]],
		[[0, 64, 6], [6, 59, 6], [12, 55, 4]],
	])
	var song := {
		"name": "game_over", "bpm": 70.0, "bars": 4,
		"voices": [
			{"wave": "triangle", "vol": 0.40, "seq": bass},
			{"wave": "square25", "vol": 0.13, "seq": arp},
			{"wave": "square", "vol": 0.20, "seq": melody},
		],
	}
	_render_song(song)

# --- Battle tier file resolution --------------------------------------------

## File base name for a battle tier. Tier 1 intentionally reuses the committed
## battle_theme.wav - it is the classic track, no extra copy is ever written.
static func battle_tier_name(tier: int) -> String:
	return "battle_theme" if tier <= 1 else "battle_tier_%d" % tier

## res:// path a tier's committed wav would live at.
static func battle_tier_path(tier: int) -> String:
	return "%s/%s.wav" % [OUT_DIR, battle_tier_name(tier)]

## Resolve the wav to play for a battle tier. Order of preference:
##   1. committed + imported res:// file (ResourceLoader.exists) - the shipped path;
##   2. a tier already generated this session (per-run cache - never regenerated);
##   3. synthesize once into user:// (writable, no import needed) as a fallback.
static func ensure_battle_tier(tier: int) -> String:
	if tier < 1:
		tier = 1
	if _rendered_tiers.has(tier):
		return _rendered_tiers[tier]
	var res_path := battle_tier_path(tier)
	if ResourceLoader.exists(res_path):
		_rendered_tiers[tier] = res_path
		return res_path
	var user_path := "user://nono_music/battle_tier_%d.wav" % tier
	if not FileAccess.file_exists(user_path):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://nono_music"))
		_render_song(_build_battle(tier), user_path)
		_render_count += 1
	_rendered_tiers[tier] = user_path
	return user_path

## Render a tier's committed file into OUT_DIR (used by generate_all).
static func _render_battle_tier_file(tier: int) -> void:
	if tier <= 1:
		return   # tier 1 IS battle_theme.wav - never write a duplicate
	_render_song(_build_battle(tier), battle_tier_path(tier))

static func generate_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_song_menu()
	_song_battle()
	for tier in range(2, BATTLE_TIER_COUNT + 1):
		_render_battle_tier_file(tier)
	_song_boss()
	_song_game_over()
	print("All chiptune tracks generated.")
