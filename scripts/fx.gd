extends Node
## Autoload of "juice" helpers: particle bursts, floating text popups and camera shake.
## Call setup() once per run with the world node and the active Camera2D.

var _world: Node2D
var _camera: Camera2D
var _particle_tex: Texture2D
var _shake_amount := 0.0
var _shake_dur := 0.0
var _shake_left := 0.0

func setup(world: Node2D, camera: Camera2D) -> void:
	_world = world
	_camera = camera
	_particle_tex = load("res://assets/generated/particle_frame_0.png")

func _process(delta: float) -> void:
	if _camera == null:
		return
	if _shake_left > 0.0:
		_shake_left -= delta
		var m: float = _shake_amount * (_shake_left / maxf(_shake_dur, 0.0001))
		_camera.offset = Vector2(randf_range(-m, m), randf_range(-m, m))
		if _shake_left <= 0.0:
			_camera.offset = Vector2.ZERO

func shake(amount: float = 6.0, duration: float = 0.25) -> void:
	_shake_amount = amount
	_shake_dur = duration
	_shake_left = duration

## Spawn a one-shot particle burst at a world position.
func burst(at: Vector2, color: Color, amount: int = 14, speed: float = 240.0, lifetime: float = 0.5, scale: float = 1.0) -> void:
	if _world == null or _particle_tex == null:
		return
	var p := CPUParticles2D.new()
	p.texture = _particle_tex
	p.position = at
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 220.0)
	p.scale_amount_min = scale * 0.5
	p.scale_amount_max = scale
	p.color = color
	p.z_index = 50
	_world.add_child(p)
	var t := get_tree().create_timer(lifetime + 0.4)
	t.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

## Show a floating score/text popup that rises and fades out.
func popup(at: Vector2, text: String, color: Color, size: int = 22) -> void:
	if _world == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 100
	_world.add_child(label)
	label.position = at - label.size * 0.5
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", at.y - 44.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tween.chain().tween_callback(label.queue_free)
