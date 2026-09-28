extends Node
## Autoload that plays looping background music with crossfades.
## NOTE: deliberately NO class_name - the autoload singleton name "Music" is
## the global identifier (same pattern as Sfx/Fx/GameState).
##
## Tracks are the procedurally-synthesized 8-bit chiptune loops in
## res://assets/audio/music. A track is started with Music.play("key"); the
## autoload crossfades from whatever is currently playing, so scene changes
## (menu -> game, retry, game over -> menu) never cut the music abruptly.
##
## Keys: "menu" | "battle" | "boss" | "gameover"

const TRACKS := {
	"menu": "res://assets/audio/music/menu_theme.wav",
	"battle": "res://assets/audio/music/battle_theme.wav",
	"boss": "res://assets/audio/music/boss_theme.wav",
	"gameover": "res://assets/audio/music/game_over.wav",
}

const FADE_TIME := 1.2

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _current_idx := -1   # index of the audible player, -1 = nothing playing
var _active := ""        # key of the track currently fading in / playing
var _fade_tween: Tween   # in-flight crossfade, killed by the next play()/stop()

func _ready() -> void:
	for key: String in TRACKS:
		_streams[key] = _load_track(TRACKS[key])
	_players.append(_make_player())
	_players.append(_make_player())

## Load a wav as a looping AudioStreamWAV. res:// paths go through the normal
## (imported) loader; user:// paths (runtime-synthesized tier fallbacks) are
## read raw via AudioStreamWAV.load_from_file, which needs no import step.
func _load_track(path: String) -> AudioStreamWAV:
	var s: AudioStreamWAV = null
	if path.begins_with("res://"):
		s = load(path) as AudioStreamWAV
	else:
		s = AudioStreamWAV.load_from_file(path)
	if s != null:
		# Enable a seamless whole-file loop (works regardless of how the
		# .wav was imported/compressed).
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s

func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p

## Crossfade to a track. Calling with the already-active key is a no-op, so
## retrying a run (which re-enters the game scene) keeps the music playing.
func play(key: String, fade := FADE_TIME) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null or key == _active:
		return
	# Kill any in-flight crossfade first. A stale tween's stop() callback would
	# otherwise silence the track we are about to fade in, because a second
	# play() within FADE_TIME swaps the two players' roles.
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	var incoming_idx := 0 if _current_idx != 0 else 1
	var outgoing_idx := 1 - incoming_idx
	_active = key
	_current_idx = incoming_idx
	var incoming: AudioStreamPlayer = _players[incoming_idx]
	# Capture the outgoing player in a local so the callback below can never
	# observe an index that a later play() has mutated.
	var outgoing: AudioStreamPlayer = _players[outgoing_idx]
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(incoming, "volume_db", 0.0, fade)
	_fade_tween.tween_property(outgoing, "volume_db", -80.0, fade)
	_fade_tween.chain().tween_callback(func() -> void:
		# Belt-and-braces: only stop it if it is not the active track now.
		if outgoing != _players[_current_idx]:
			outgoing.stop())

## Crossfade to the battle track for `tier` (1..10). Tier 1 is the classic
## battle theme; higher tiers are procedural intensifications that resolve via
## ChiptuneGenerator (a committed res:// file when present, otherwise one
## synthesized per session). Routes through play() so the no-op-if-active guard
## and the shared crossfade/crossfade-pool behavior are identical to battle/boss.
func play_battle_tier(tier: int, fade := FADE_TIME) -> void:
	if tier <= 1:
		play("battle", fade)
		return
	var key := "battle_tier_%d" % tier
	if not _streams.has(key):
		var s := _load_track(ChiptuneGenerator.ensure_battle_tier(tier))
		if s == null:
			return
		_streams[key] = s
	play(key, fade)

## Fade everything out (e.g. before quitting or on a hard mute).
func stop(fade := FADE_TIME) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
	for p: AudioStreamPlayer in _players:
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -80.0, fade)
	_active = ""
	_current_idx = -1
