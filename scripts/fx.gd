extends Node
## Presentation-only pooled VFX facade. Call setup() for each game world and active camera.
## Particle budget 24, line/ring 16, sprite 48, popup 32 and viewport overlay 4; real-time ticking survives pause/hit-stop.
##
## Bursts and popups are pooled: nodes are configured once and reused instead of
## allocated/freed per effect. A pooled node stays a child of the world but is
## inert (not emitting / modulate.a == 0) while parked, so it neither accumulates
## draw calls nor churns the SceneTree during play.

var _world: Node2D
var _camera: Camera2D
var _particle_tex: Texture2D
var _shake_amount: float = 0.0
var _shake_dur: float = 0.0
var _shake_left: float = 0.0
## Combined time effect state uses real milliseconds so it never freezes itself.
var _time_effect_until: int = 0
var _time_effect_scale: float = 1.0
var _camera_base_zoom: Vector2 = Vector2.ONE
var _zoom_until: int = 0
var _zoom_amount: float = 0.0
var _zoom_duration_ms: int = 0
var _vignette_rect: ColorRect

const POPUP_WIDTH := 240.0
const MAX_PARTICLE_POOL := 24
const MAX_POPUP_POOL := 32
const MAX_LINE_POOL := 16
const MAX_SPRITE_POOL := 48
const MAX_SCREEN_POOL := 4
const ARENA_RECT := Rect2(0.0, 0.0, 1280.0, 720.0)

var _particle_pool: Array[CPUParticles2D] = []
var _particle_allocated: int = 0
var _active_particles: Array[Dictionary] = []
var _popup_pool: Array[Label] = []
var _active_popups: Array[Dictionary] = []
var _line_pool: Array[Line2D] = []
var _active_lines: Array[Dictionary] = []
var _ring_unit_points: PackedVector2Array = []
var _sprite_pool: Array[Sprite2D] = []
var _active_sprites: Array[Dictionary] = []
var _screen_pool: Array[ColorRect] = []
var _active_screens: Array[Dictionary] = []
var _screen_allocated: int = 0
var _sprite_allocated: int = 0
var _screen_layer: CanvasLayer
var _additive_material: CanvasItemMaterial
var _active_slowmo: bool = false
var _popup_font_material: CanvasItemMaterial

func _ready() -> void:
	# Hit-stop restoration runs in _process, which must fire even while the
	# SceneTree is paused. Without ALWAYS a hitstop that overlaps a pause (e.g.
	# the upgrade offer) would leave Engine.time_scale == 0 forever.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ring_unit_points.resize(33)
	for i: int in _ring_unit_points.size():
		var angle: float = TAU * float(i) / 32.0
		_ring_unit_points[i] = Vector2(cos(angle), sin(angle))

func setup(world: Node2D, camera: Camera2D) -> void:
	var had_previous_world: bool = _world != null and _world != world
	if world == null or had_previous_world:
		_discard_world_pools()
	_world = world
	_camera = camera
	_particle_tex = load("res://assets/generated/particle_frame_0.png") if world != null else null
	# A fresh setup clears active bookkeeping even when the world is unchanged.
	_active_particles.clear()
	_active_lines.clear()
	_active_sprites.clear()
	_active_popups.clear()
	_active_screens.clear()
	_screen_layer = null
	_vignette_rect = null
	_shake_amount = 0.0
	_shake_dur = 0.0
	_shake_left = 0.0
	_zoom_until = 0
	_zoom_amount = 0.0
	_zoom_duration_ms = 0
	_camera_base_zoom = camera.zoom if camera != null else Vector2.ONE
	# A fresh game run must never inherit a prior scene's partial time scale.
	_time_effect_until = 0
	_time_effect_scale = 1.0
	Engine.time_scale = 1.0
	_active_slowmo = false

func _discard_world_pools() -> void:
	_particle_pool.clear()
	_particle_allocated = 0
	_active_particles.clear()
	_popup_pool.clear()
	_active_popups.clear()
	_line_pool.clear()
	_active_lines.clear()
	_sprite_pool.clear()
	_sprite_allocated = 0
	_active_sprites.clear()
	_screen_pool.clear()
	_screen_allocated = 0
	_active_screens.clear()
	_screen_layer = null
	_vignette_rect = null
	_additive_material = null
	_popup_font_material = null

func _process(delta: float) -> void:
	# Real-time effects keep progressing through hit-stop and tree pause.
	if _world != null and not is_instance_valid(_world):
		_world = null
		_camera = null
		_discard_world_pools()
	var now: int = Time.get_ticks_msec()
	if _time_effect_until > 0 and now >= _time_effect_until:
		_time_effect_until = 0
		_time_effect_scale = 1.0
		Engine.time_scale = 1.0
		_active_slowmo = false
	_tick_real_time_effects(now)
	if _camera != null:
		if _shake_left > 0.0:
			var elapsed: float = 1.0 - (_shake_left / maxf(_shake_dur, 0.0001))
			_shake_left = maxf(_shake_left - delta, 0.0)
			var trauma: float = _shake_amount * pow(1.0 - elapsed, 2.0)
			_camera.offset = Vector2(randf_range(-trauma, trauma), randf_range(-trauma, trauma))
			if _shake_left <= 0.0:
				_camera.offset = Vector2.ZERO
		if _zoom_until > now:
			var remaining: float = float(_zoom_until - now) / float(maxi(_zoom_duration_ms, 1))
			_set_camera_zoom_punch(clampf(remaining, 0.0, 1.0))
		elif _zoom_until != 0:
			_zoom_until = 0
			_zoom_amount = 0.0
			_zoom_duration_ms = 0
			_camera.zoom = _camera_base_zoom
	if _vignette_rect != null and is_instance_valid(_vignette_rect):
		var pulse: float = 0.5 + 0.5 * sin(float(now) * 0.0022)
		_vignette_rect.color.a = 0.10 + pulse * 0.08

## `shake(amount, duration)` adds camera offset trauma; the strongest amount and longest duration are retained.
## `hitstop(duration)` freezes gameplay; `slowmo(scale, duration)` limits scale to [0.05, 1]. Both stack on real-time deadlines.
## `ring(at, color, radius, width, duration)` / `aim_line(from, to, color, duration)` share 16 Line2D slots.
## `spark(at, dir, color, count, speed, lifetime, spread)` and `debris(at, color, count, speed, lifetime)` share the 24 CPUParticles2D cap.
## `afterimage(texture, at, angle, scale, tint, life)` and `flash(at, color, strength, duration)` share the 48 Sprite2D slots.
## `screen_flash(color, strength, duration)` / `vignette(enabled)` share four viewport ColorRects.
## `zoom_punch(amount, duration)` preserves player/boss camera zoom ratio and clamps to arena floor; setup() owns lifecycle/reset.
## Add trauma to the current camera shake; the strongest request and longest duration win.
func shake(amount: float = 6.0, duration: float = 0.25) -> void:
	if duration <= 0.0:
		return
	_shake_amount = maxf(_shake_amount, amount)
	_shake_dur = maxf(_shake_dur, duration)
	_shake_left = maxf(_shake_left, duration)

## Freeze the whole game briefly. Nested hitstop/slowmo extends lifetime and keeps the strongest freeze.
func hitstop(duration: float) -> void:
	_set_time_effect(0.0, duration)

## Partially slow gameplay for a real-time duration; nested requests never shorten an active effect.
func slowmo(scale: float = 0.35, duration: float = 0.2) -> void:
	_set_time_effect(clampf(scale, 0.05, 1.0), duration)

func _set_time_effect(scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var was_active: bool = _time_effect_until > Time.get_ticks_msec()
	var until: int = Time.get_ticks_msec() + maxi(1, int(duration * 1000.0))
	_time_effect_until = maxi(_time_effect_until, until)
	_time_effect_scale = minf(_time_effect_scale, scale) if was_active else scale
	Engine.time_scale = _time_effect_scale
	_active_slowmo = _time_effect_scale > 0.0 and _time_effect_scale < 1.0

## Draw an expanding, fading circle; rings and aim lines share a capped Line2D pool.
func ring(at: Vector2, color: Color, radius: float = 36.0, width: float = 3.0, duration: float = 0.22) -> Line2D:
	return _line_effect(at, at + Vector2.RIGHT * maxf(radius, 1.0), color, duration, true, width, radius)

## Emit a narrow directional particle cone centered on `dir`.
func spark(at: Vector2, dir: Vector2, color: Color, count: int = 10, speed: float = 260.0, lifetime: float = 0.25, spread: float = 25.0) -> CPUParticles2D:
	return _particle_effect(at, color, count, speed, lifetime, 0.8, dir, spread, false)

## Emit spinning, damped particles which shrink to nothing over their lifetime.
func debris(at: Vector2, color: Color, count: int = 8, speed: float = 220.0, lifetime: float = 0.45) -> CPUParticles2D:
	var p: CPUParticles2D = _particle_effect(at, color, count, speed, lifetime, 1.0, Vector2.UP, 180.0, true)
	return p

## Leave a tinted, fading copy of a sprite; uses the shared sprite pool.
func afterimage(texture: Texture2D, at: Vector2, angle: float = 0.0, sprite_scale: Vector2 = Vector2.ONE, tint: Color = Color(0.4, 0.9, 1.0, 0.5), life: float = 0.16) -> Sprite2D:
	if _world == null or not is_instance_valid(_world) or texture == null:
		return null
	var ghost: Sprite2D = _acquire_sprite()
	if ghost == null:
		return null
	ghost.texture = texture
	ghost.global_position = at
	ghost.rotation = angle
	ghost.scale = sprite_scale
	ghost.modulate = tint
	ghost.visible = true
	ghost.z_index = 45
	_active_sprites.append({"node": ghost, "start": Time.get_ticks_msec(), "duration": maxf(life, 0.01), "alpha": tint.a})
	return ghost

## Add a brief local glow pop using a pooled additive sprite.
func flash(at: Vector2, color: Color, strength: float = 1.0, duration: float = 0.08) -> Sprite2D:
	if _world == null or _particle_tex == null:
		return null
	var glow: Sprite2D = _acquire_sprite()
	if glow == null:
		return null
	glow.texture = _particle_tex
	glow.global_position = at
	glow.scale = Vector2.ONE * maxf(strength, 0.1) * 2.5
	glow.modulate = Color(color.r, color.g, color.b, 0.85)
	glow.material = _additive()
	glow.visible = true
	glow.z_index = 60
	_active_sprites.append({"node": glow, "start": Time.get_ticks_msec(), "duration": maxf(duration, 0.01), "alpha": glow.modulate.a})
	return glow

## Tint the whole viewport briefly on a CanvasLayer above the world and below touch controls.
func screen_flash(color: Color, strength: float = 0.3, duration: float = 0.18) -> ColorRect:
	var overlay: ColorRect = _acquire_screen()
	if overlay == null:
		return null
	overlay.color = Color(color.r, color.g, color.b, clampf(strength, 0.0, 0.35))
	overlay.visible = true
	_active_screens.append({"node": overlay, "start": Time.get_ticks_msec(), "duration": maxf(duration, 0.01), "alpha": overlay.color.a})
	return overlay

## Enable a subtle screen-edge warning vignette; disable it when HP recovers.
func vignette(enabled: bool) -> void:
	if not enabled:
		if _vignette_rect != null and is_instance_valid(_vignette_rect):
			_vignette_rect.visible = false
		return
	if _vignette_rect == null or not is_instance_valid(_vignette_rect):
		_vignette_rect = _acquire_screen()
	if _vignette_rect != null:
		var was_active: bool = _active_screens.any(func(effect: Dictionary) -> bool: return effect.get("node") == _vignette_rect)
		if not was_active and _active_screens.size() >= MAX_SCREEN_POOL:
			return
		_vignette_rect.color = Color(0.9, 0.2, 0.15, 0.12)
		_vignette_rect.visible = true

## Draw a telegraph line that grows from `from` to `to`, then fades out.
func aim_line(from: Vector2, to: Vector2, color: Color, duration: float = 0.65) -> Line2D:
	return _line_effect(from, to, color, duration, false, 3.0, 0.0)

## Add a brief camera zoom punch without crossing the game's arena zoom floor.
func zoom_punch(amount: float = 0.04, duration: float = 0.18) -> void:
	if _camera == null or duration <= 0.0:
		return
	_camera_base_zoom = _camera.zoom
	_zoom_amount = clampf(amount, 0.0, 0.08)
	_zoom_duration_ms = maxi(1, int(duration * 1000.0))
	_zoom_until = Time.get_ticks_msec() + _zoom_duration_ms

func _set_camera_zoom_punch(weight: float) -> void:
	if _camera == null:
		return
	var floor_zoom: float = 1.0
	if _world != null:
		floor_zoom = maxf(float(_world.get("_camera_floor")), 1.0)
	var factor: float = 1.0 + _zoom_amount * weight
	var target: Vector2 = _camera_base_zoom * factor
	var boss_camera: bool = _world != null and _world.get("boss_cam") == _camera
	var minimum: float = floor_zoom * (1.2 if boss_camera else 1.0)
	_camera.zoom = Vector2(maxf(target.x, minimum), maxf(target.y, minimum))

func _tick_real_time_effects(now: int) -> void:
	if _world == null:
		return
	for i: int in range(_active_particles.size() - 1, -1, -1):
		var particle_effect: Dictionary = _active_particles[i]
		var particle_ref: Variant = particle_effect["node"]
		if not is_instance_valid(particle_ref):
			_particle_allocated = maxi(_particle_allocated - 1, 0)
			_active_particles.remove_at(i)
			continue
		var particle: CPUParticles2D = particle_ref as CPUParticles2D
		if now >= int(particle_effect["until"]) + 100:
			particle.emitting = false
			_recycle_particles(particle)
			_active_particles.remove_at(i)
	for i: int in range(_active_lines.size() - 1, -1, -1):
		var effect: Dictionary = _active_lines[i]
		var node_ref: Variant = effect["node"]
		if not is_instance_valid(node_ref):
			_active_lines.remove_at(i)
			continue
		var node: Line2D = node_ref as Line2D
		var t: float = clampf(float(now - int(effect["start"])) / (float(effect["duration"]) * 1000.0), 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - t, 2.0)
		if bool(effect["ring"]):
			var ring_radius: float = float(effect["radius"]) * eased
			for n: int in _ring_unit_points.size():
				node.set_point_position(n, _ring_unit_points[n] * ring_radius)
			node.width = maxf(float(effect["width"]) * (1.0 - t), 0.1)
		else:
			var start: Vector2 = effect["from"]
			var end: Vector2 = effect["to"]
			node.set_point_position(0, start)
			node.set_point_position(1, start.lerp(end, eased))
		node.modulate.a = 1.0 - t
		if not bool(effect["ring"]):
			node.default_color.a = 1.0 - t
		if t >= 1.0:
			_recycle_line(node)
			_active_lines.remove_at(i)
	for i: int in range(_active_sprites.size() - 1, -1, -1):
		var effect: Dictionary = _active_sprites[i]
		var node_ref: Variant = effect["node"]
		if not is_instance_valid(node_ref):
			_sprite_allocated = maxi(_sprite_allocated - 1, 0)
			_active_sprites.remove_at(i)
			continue
		var node: Sprite2D = node_ref as Sprite2D
		var t: float = clampf(float(now - int(effect["start"])) / (float(effect["duration"]) * 1000.0), 0.0, 1.0)
		node.modulate.a = float(effect["alpha"]) * (1.0 - t)
		if effect.has("popup"):
			var origin: Vector2 = effect["origin"]
			var end: Vector2 = effect["end"]
			node.position = origin.lerp(end, 1.0 - pow(1.0 - t, 2.0))
		if t >= 1.0:
			_recycle_sprite(node)
			_active_sprites.remove_at(i)
	for i: int in range(_active_popups.size() - 1, -1, -1):
		var popup_effect: Dictionary = _active_popups[i]
		var popup_ref: Variant = popup_effect["node"]
		if not is_instance_valid(popup_ref):
			_active_popups.remove_at(i)
			continue
		var popup_label: Label = popup_ref as Label
		var popup_t: float = clampf(float(now - int(popup_effect["start"])) / 700.0, 0.0, 1.0)
		popup_label.modulate.a = 1.0 if popup_t < 0.15 else clampf(1.0 - (popup_t - 0.15) / 0.85, 0.0, 1.0)
		var popup_origin: Vector2 = popup_effect["origin"]
		popup_label.position = popup_origin + Vector2(0.0, -44.0 * (1.0 - pow(1.0 - popup_t, 2.0)))
		if popup_t >= 1.0:
			popup_label.modulate.a = 0.0
			popup_label.material = null
			if _popup_pool.size() < MAX_POPUP_POOL:
				_popup_pool.append(popup_label)
			_active_popups.remove_at(i)
	for i: int in range(_active_screens.size() - 1, -1, -1):
		var effect: Dictionary = _active_screens[i]
		var node_ref: Variant = effect["node"]
		if not is_instance_valid(node_ref):
			_screen_allocated = maxi(_screen_allocated - 1, 0)
			_active_screens.remove_at(i)
			continue
		var node: ColorRect = node_ref as ColorRect
		var t: float = clampf(float(now - int(effect["start"])) / (float(effect["duration"]) * 1000.0), 0.0, 1.0)
		node.color.a = float(effect["alpha"]) * (1.0 - t)
		if t >= 1.0:
			node.visible = false
			_active_screens.remove_at(i)
			if _screen_pool.size() < MAX_SCREEN_POOL and not _screen_pool.has(node):
				_screen_pool.append(node)

func _line_effect(from: Vector2, to: Vector2, color: Color, duration: float, is_ring: bool, width: float, radius: float) -> Line2D:
	if _world == null or not is_instance_valid(_world) or _active_lines.size() >= MAX_LINE_POOL:
		return null
	if not is_ring:
		for i: int in range(_active_lines.size() - 1, -1, -1):
			var old_effect: Dictionary = _active_lines[i]
			if not bool(old_effect["ring"]):
				var old_line: Line2D = old_effect["node"]
				_recycle_line(old_line)
				_active_lines.remove_at(i)
				break
	var line: Line2D = _acquire_line()
	if line == null:
		return null
	line.clear_points()
	if is_ring:
		line.points = _ring_unit_points
	else:
		line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	line.default_color = color
	line.modulate = Color.WHITE
	line.position = from if is_ring else Vector2.ZERO
	line.width = width
	line.visible = true
	line.z_index = 55
	_active_lines.append({"node": line, "start": Time.get_ticks_msec(), "duration": maxf(duration, 0.01), "ring": is_ring, "width": width, "radius": radius, "from": from, "to": to})
	return line

func _particle_effect(at: Vector2, color: Color, amount: int, speed: float, lifetime: float, scale: float, direction: Vector2, spread: float, spinning: bool) -> CPUParticles2D:
	if _world == null or not is_instance_valid(_world) or _particle_tex == null or _active_particles.size() >= MAX_PARTICLE_POOL:
		return null
	var p: CPUParticles2D = _acquire_particle()
	if p == null:
		return null
	p.texture = _particle_tex
	p.position = _clamp_effect_position(at)
	p.amount = maxi(amount, 1)
	p.lifetime = maxf(lifetime, 0.05)
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP
	p.spread = spread
	p.initial_velocity_min = speed * (0.4 if not spinning else 0.5)
	p.initial_velocity_max = speed
	p.gravity = Vector2(0.0, 90.0 if spinning else 220.0)
	p.scale_amount_min = scale * 0.45
	p.scale_amount_max = scale
	p.angular_velocity_min = -420.0 if spinning else 0.0
	p.angular_velocity_max = 420.0 if spinning else 0.0
	p.damping_min = 160.0 if spinning else 0.0
	p.damping_max = 280.0 if spinning else 0.0
	p.color = color
	p.z_index = 50
	p.direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.UP
	p.emitting = true
	p.restart()
	_active_particles.append({"node": p, "until": Time.get_ticks_msec() + int(p.lifetime * 1000.0)})
	return p

func _clamp_effect_position(at: Vector2) -> Vector2:
	return Vector2(clampf(at.x, 8.0, ARENA_RECT.size.x - 8.0), clampf(at.y, 8.0, ARENA_RECT.size.y - 8.0))

func _additive() -> CanvasItemMaterial:
	if _additive_material == null or not is_instance_valid(_additive_material):
		_additive_material = CanvasItemMaterial.new()
		_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material

func _ensure_screen_layer() -> CanvasLayer:
	if _screen_layer == null or not is_instance_valid(_screen_layer):
		_screen_layer = CanvasLayer.new()
		_screen_layer.layer = 4
		if _world != null:
			_world.add_child(_screen_layer)
	return _screen_layer

func _acquire_screen() -> ColorRect:
	while not _screen_pool.is_empty():
		var pooled_ref: Variant = _screen_pool.pop_back()
		if is_instance_valid(pooled_ref):
			var pooled: ColorRect = pooled_ref as ColorRect
			pooled.visible = true
			return pooled
		_screen_allocated = maxi(_screen_allocated - 1, 0)
	if _screen_allocated >= MAX_SCREEN_POOL:
		return null
	if _active_screens.size() >= MAX_SCREEN_POOL:
		return null
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.visible = false
	_ensure_screen_layer().add_child(rect)
	_screen_allocated += 1
	return rect

func _acquire_line() -> Line2D:
	while not _line_pool.is_empty():
		var pooled_ref: Variant = _line_pool.pop_back()
		if is_instance_valid(pooled_ref):
			return pooled_ref as Line2D
	if _active_lines.size() >= MAX_LINE_POOL:
		return null
	if _line_pool.size() + _active_lines.size() >= MAX_LINE_POOL:
		return null
	var line: Line2D = Line2D.new()
	line.closed = false
	line.antialiased = true
	_world.add_child(line)
	return line

func _acquire_sprite() -> Sprite2D:
	while not _sprite_pool.is_empty():
		var pooled_ref: Variant = _sprite_pool.pop_back()
		if is_instance_valid(pooled_ref):
			var pooled: Sprite2D = pooled_ref as Sprite2D
			pooled.visible = true
			return pooled
		_sprite_allocated = maxi(_sprite_allocated - 1, 0)
	if _sprite_allocated >= MAX_SPRITE_POOL:
		return null
	var sprite: Sprite2D = Sprite2D.new()
	_world.add_child(sprite)
	_sprite_allocated += 1
	return sprite

## Spawn a one-shot omnidirectional particle burst (legacy API retained).
func burst(at: Vector2, color: Color, amount: int = 14, speed: float = 240.0, lifetime: float = 0.5, scale: float = 1.0) -> void:
	_particle_effect(at, color, amount, speed, lifetime, scale, Vector2.UP, 180.0, false)

## Show a floating score/text popup that rises and fades out.
func popup(at: Vector2, text: String, color: Color, size: int = 22) -> void:
	if _world == null:
		return
	var label: Label = _acquire_popup()
	if label == null or _active_popups.size() >= MAX_POPUP_POOL:
		return
	label.text = text
	label.theme_type_variation = &"FloatPopup" if size >= 28 else &"PopupSmall"
	label.add_theme_color_override("font_color", color)
	label.modulate = Color.WHITE
	label.material = _popup_font_material
	label.z_index = 100
	label.size = Vector2(POPUP_WIDTH, label.get_minimum_size().y)
	label.position = _clamp_effect_position(at) - label.size * 0.5
	_active_popups.append({"node": label, "start": Time.get_ticks_msec(), "origin": label.position})

# --- Pooling -----------------------------------------------------------------

func _acquire_particle() -> CPUParticles2D:
	while not _particle_pool.is_empty():
		var pooled_ref: Variant = _particle_pool.pop_back()
		if is_instance_valid(pooled_ref):
			var pooled: CPUParticles2D = pooled_ref as CPUParticles2D
			pooled.modulate.a = 1.0
			return pooled
		_particle_allocated = maxi(_particle_allocated - 1, 0)
	if _particle_allocated >= MAX_PARTICLE_POOL:
		return null
	var particle: CPUParticles2D = CPUParticles2D.new()
	particle.one_shot = true
	particle.z_index = 50
	_world.add_child(particle)
	_particle_allocated += 1
	return particle

func _recycle_particles(p: CPUParticles2D) -> void:
	if not is_instance_valid(p):
		return
	p.emitting = false
	p.modulate.a = 0.0
	if not _particle_pool.has(p) and _particle_pool.size() < MAX_PARTICLE_POOL:
		_particle_pool.append(p)
	elif not _particle_pool.has(p):
		_particle_allocated = maxi(_particle_allocated - 1, 0)
		p.queue_free()

func _acquire_popup() -> Label:
	while not _popup_pool.is_empty():
		var pooled_ref: Variant = _popup_pool.pop_back()
		if is_instance_valid(pooled_ref):
			return pooled_ref as Label
	if _popup_pool.size() + _active_popups.size() >= MAX_POPUP_POOL:
		return null
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate.a = 0.0
	label.z_index = 100
	_world.add_child(label)
	return label

func _recycle_popup(label: Label) -> void:
	if not is_instance_valid(label):
		return
	label.modulate.a = 0.0
	if not _popup_pool.has(label) and _popup_pool.size() < MAX_POPUP_POOL:
		_popup_pool.append(label)

func _recycle_line(line: Line2D) -> void:
	if not is_instance_valid(line):
		return
	line.clear_points()
	line.modulate.a = 0.0
	line.visible = false
	if _line_pool.size() < MAX_LINE_POOL:
		_line_pool.append(line)

func _recycle_sprite(sprite: Sprite2D) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.modulate.a = 0.0
	sprite.visible = false
	sprite.material = null
	if _sprite_pool.size() < MAX_SPRITE_POOL:
		_sprite_pool.append(sprite)
