extends Node
## Autoload that plays one-shot synthesized SFX from res://assets/audio/sfx.
## Each play() spawns a short-lived AudioStreamPlayer so sounds can overlap.

const SFX_DIR := "res://assets/audio/sfx"
const NAMES: Array[String] = ["coin", "dash", "explode", "hurt", "powerup", "wave", "gameover"]

var _streams: Dictionary = {}
var _coin_player: AudioStreamPlayer
var _coin_poly: AudioStreamPolyphonic

func _ready() -> void:
	for sound_name in NAMES:
		_streams[sound_name] = load("%s/%s.wav" % [SFX_DIR, sound_name])
	_coin_poly = AudioStreamPolyphonic.new()
	_coin_poly.polyphony = 12
	_coin_player = AudioStreamPlayer.new()
	_coin_player.stream = _coin_poly
	_coin_player.bus = "Sfx"
	add_child(_coin_player)
	_coin_player.play()

func play(sound_name: String, pitch_scale: float = 1.0, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound_name)
	if stream == null:
		return
	if sound_name == "coin":
		var pb := _coin_player.get_stream_playback()
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
