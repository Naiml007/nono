extends Node
## Autoload that plays one-shot synthesized SFX from res://assets/audio/sfx.
## Frequent sounds share a pooled polyphonic AudioStreamPlayer (one node per
## sound, many simultaneous voices) so rapid overlaps never churn the tree.
## Rare sounds ("wave", "gameover") still spawn a short-lived player.

const SFX_DIR := "res://assets/audio/sfx"
const NAMES: Array[String] = ["coin", "dash", "explode", "hurt", "powerup", "wave", "gameover"]

## Simultaneous voices for each frequently-played sound. Everything not listed
## here uses the one-shot-node path.
const POLYPHONY := {
	"coin": 12,
	"dash": 4,
	"explode": 8,
	"hurt": 4,
	"powerup": 6,
}

var _streams: Dictionary = {}
var _poly_players: Dictionary = {}   # sound_name -> AudioStreamPlayer (polyphonic)
var _coin_player: AudioStreamPlayer
var _coin_poly: AudioStreamPolyphonic

func _ready() -> void:
	for sound_name in NAMES:
		_streams[sound_name] = load("%s/%s.wav" % [SFX_DIR, sound_name])
	for sound_name: String in POLYPHONY:
		var poly := AudioStreamPolyphonic.new()
		poly.polyphony = int(POLYPHONY[sound_name])
		var player := AudioStreamPlayer.new()
		player.stream = poly
		player.bus = "Sfx"
		add_child(player)
		player.play()
		_poly_players[sound_name] = player
		if sound_name == "coin":
			_coin_poly = poly
			_coin_player = player

func play(sound_name: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound_name)
	if stream == null:
		return
	var poly_player: AudioStreamPlayer = _poly_players.get(sound_name) as AudioStreamPlayer
	if poly_player != null:
		var pb := poly_player.get_stream_playback()
		if pb != null:
			pb.play_stream(stream, 0.0, volume_db, pitch_scale)
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.pitch_scale = pitch_scale
	p.volume_db = volume_db
	p.bus = "Sfx"
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()
