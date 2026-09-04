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

func _ready() -> void:
	for key: String in TRACKS:
		var s := load(TRACKS[key]) as AudioStreamWAV
		if s != null:
			# Enable a seamless whole-file loop (works regardless of how the
			# .wav was imported/compressed).
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		_streams[key] = s
	_players.append(_make_player())
	_players.append(_make_player())

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
	var incoming_idx := 0 if _current_idx != 0 else 1
	var outgoing_idx := 1 - incoming_idx
	_active = key
	_current_idx = incoming_idx
	var incoming: AudioStreamPlayer = _players[incoming_idx]
	var outgoing: AudioStreamPlayer = _players[outgoing_idx]
	incoming.stream = stream
	incoming.volume_db = -80.0
	incoming.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(incoming, "volume_db", 0.0, fade)
	tw.tween_property(outgoing, "volume_db", -80.0, fade)
	tw.chain().tween_callback(func() -> void:
		outgoing.stop())

## Fade everything out (e.g. before quitting or on a hard mute).
func stop(fade := FADE_TIME) -> void:
	for p: AudioStreamPlayer in _players:
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -80.0, fade)
	_active = ""
	_current_idx = -1
