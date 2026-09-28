extends Node
## Autoload of "juice" helpers: particle bursts, floating text popups and camera shake.
## Call setup() once per run with the world node and the active Camera2D.
##
## Bursts and popups are pooled: nodes are configured once and reused instead of
## allocated/freed per effect. A pooled node stays a child of the world but is
## inert (not emitting / modulate.a == 0) while parked, so it neither accumulates
## draw calls nor churns the SceneTree during play.

var _world: Node2D
var _camera: Camera2D
var _particle_tex: Texture2D
var _shake_amount := 0.0
var _shake_dur := 0.0
var _shake_left := 0.0
## Hit-stop (brief time freeze) runs on real time so it doesn't freeze itself.
var _hitstop_until := 0

const POPUP_WIDTH := 240.0
const MAX_PARTICLE_POOL := 64
const MAX_POPUP_POOL := 32

var _particle_pool: Array[CPUParticles2D] = []
var _popup_pool: Array[Label] = []

func _ready() -> void:
	# Hit-stop restoration runs in _process, which must fire even while the
	# SceneTree is paused. Without ALWAYS a hitstop that overlaps a pause (e.g.
	# the upgrade offer) would leave Engine.time_scale == 0 forever.
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup(world: Node2D, camera: Camera2D) -> void:
	_world = world
	_camera = camera
	_particle_tex = load("res://assets/generated/particle_frame_0.png")
	# A fresh setup means a new run/scene; any pooled nodes belong to the old
	# world, so drop the pools and rebuild against the new one.
	_particle_pool.clear()
	_popup_pool.clear()

func _process(delta: float) -> void:
	# Hit-stop is managed before the camera guard so it works even if setup()
	# hasn't run. Engine.time_scale freezes gameplay; we restore on real time.
	if _hitstop_until > 0:
		if Time.get_ticks_msec() >= _hitstop_until:
			_hitstop_until = 0
			Engine.time_scale = 1.0
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

## Freeze the whole game for a short moment (weighty hits). Nested calls extend
## the freeze rather than cut it short. Restores time_scale on real elapsed time.
func hitstop(duration: float) -> void:
	var until := Time.get_ticks_msec() + maxi(1, int(duration * 1000.0))
	_hitstop_until = maxi(_hitstop_until, until)
	Engine.time_scale = 0.0

## Spawn a one-shot particle burst at a world position.
func burst(at: Vector2, color: Color, amount: int = 14, speed: float = 240.0, lifetime: float = 0.5, scale: float = 1.0) -> void:
	if _world == null or _particle_tex == null:
		return
	var p := _acquire_particle()
	p.texture = _particle_tex
	p.position = at
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, 220.0)
	p.scale_amount_min = scale * 0.5
	p.scale_amount_max = scale
	p.color = color
	p.z_index = 50
	p.emitting = true
	p.restart()
	# One-shot bursts return to the pool via the particle system's `finished`
	# signal (emitted once all particles die). CONNECT_ONE_SHOT leaves no stale
	# connection behind for the recycled node.
	p.finished.connect(_recycle_particles.bind(p), CONNECT_ONE_SHOT)

## Show a floating score/text popup that rises and fades out.
func popup(at: Vector2, text: String, color: Color, size: int = 22) -> void:
	if _world == null:
		return
	var label := _acquire_popup()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.modulate = Color(1, 1, 1, 1)
	label.z_index = 100
	# A Label parented straight to a Node2D is not laid out until the next
	# frame, so centring on label.size would use (0, 0). Use an explicit width
	# and centre the text inside it instead — no frame of latency.
	label.size = Vector2(POPUP_WIDTH, label.get_minimum_size().y)
	label.position = at - label.size * 0.5
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", at.y - 44.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.15)
	tween.chain().tween_callback(_recycle_popup.bind(label))

# --- Pooling -----------------------------------------------------------------

func _acquire_particle() -> CPUParticles2D:
	while not _particle_pool.is_empty():
		var pooled: CPUParticles2D = _particle_pool.pop_back()
		if is_instance_valid(pooled):
			return pooled
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.z_index = 50
	_world.add_child(p)
	return p

func _recycle_particles(p: CPUParticles2D) -> void:
	if not is_instance_valid(p):
		return
	p.emitting = false
	if _particle_pool.size() < MAX_PARTICLE_POOL:
		_particle_pool.append(p)
	else:
		p.queue_free()

func _acquire_popup() -> Label:
	while not _popup_pool.is_empty():
		var pooled: Label = _popup_pool.pop_back()
		if is_instance_valid(pooled):
			return pooled
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_index = 100
	_world.add_child(l)
	return l

func _recycle_popup(label: Label) -> void:
	if not is_instance_valid(label):
		return
	label.modulate.a = 0.0
	if _popup_pool.size() < MAX_POPUP_POOL:
		_popup_pool.append(label)
	else:
		label.queue_free()
