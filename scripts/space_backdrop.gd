class_name SpaceBackdrop
extends CanvasLayer
## Full-viewport space plate with translucent drifting star planes. In gameplay,
## the layers shift by different amounts as the pilot crosses the arena, faking
## camera parallax without changing the fixed arena camera or gameplay positions.

const BACKDROP_TEXTURE: Texture2D = preload("res://assets/generated/menu_nebula_backdrop.png")
const STAR_MATERIAL: ShaderMaterial = preload("res://shaders/menu_bg_material.tres")
const ARENA_CENTER := Vector2(640.0, 360.0)
const ARENA_HALF_SIZE := Vector2(640.0, 360.0)
const PLATE_OVERSCAN := 1.12
const PLATE_PARALLAX_PIXELS := Vector2(24.0, 18.0)
const DISTANT_STAR_PARALLAX_UV := Vector2(0.025, 0.018)
const NEAR_STAR_PARALLAX_UV := Vector2(0.065, 0.048)
const PARALLAX_RESPONSE := 8.0

@onready var base_plate: TextureRect = $Background/BasePlate
@onready var distant_stars: ColorRect = $Background/DistantStars
@onready var near_stars: ColorRect = $Background/NearStars

@export_range(0.0, 1.0, 0.01) var plate_opacity: float = 1.0
@export_range(0.0, 1.0, 0.01) var star_opacity_scale: float = 1.0
@export var parallax_target_path: NodePath = NodePath("../Player")

var _distant_material: ShaderMaterial
var _near_material: ShaderMaterial
var _distant_field_origin: Vector2 = Vector2.ZERO
var _near_field_origin: Vector2 = Vector2(29.0, 17.0)
var _plate_rest_position: Vector2 = Vector2.ZERO
var _plate_parallax_limit: Vector2 = PLATE_PARALLAX_PIXELS
var _parallax_amount: Vector2 = Vector2.ZERO
var _parallax_target: Node2D
var _motion_enabled: bool = true

func _ready() -> void:
	base_plate.texture = BACKDROP_TEXTURE
	base_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	base_plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	base_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base_plate.material = null
	base_plate.modulate.a = plate_opacity
	_parallax_target = get_node_or_null(parallax_target_path) as Node2D

	_configure_star_layers()
	if not get_viewport().size_changed.is_connected(_fit_plate):
		get_viewport().size_changed.connect(_fit_plate)
	_fit_plate()
	if not is_instance_valid(_parallax_target) and get_parent() is Game:
		push_warning("SpaceBackdrop: configured parallax target is missing; camera parallax is disabled")
	if not GameState.settings_changed.is_connected(_apply_motion_preference):
		GameState.settings_changed.connect(_apply_motion_preference)
	_apply_motion_preference()

func _process(delta: float) -> void:
	var target_amount: Vector2 = Vector2.ZERO
	if _motion_enabled and is_instance_valid(_parallax_target):
		var target_offset: Vector2 = _parallax_target.global_position - ARENA_CENTER
		target_amount = Vector2(
			clampf(target_offset.x / ARENA_HALF_SIZE.x, -1.0, 1.0),
			clampf(target_offset.y / ARENA_HALF_SIZE.y, -1.0, 1.0)
		)
	if _motion_enabled:
		var follow_weight: float = 1.0 - exp(-PARALLAX_RESPONSE * delta)
		_parallax_amount = _parallax_amount.lerp(target_amount, follow_weight)
	else:
		_parallax_amount = Vector2.ZERO
	_apply_parallax(_parallax_amount)

func _configure_star_layers() -> void:
	_distant_material = STAR_MATERIAL.duplicate() as ShaderMaterial
	_distant_material.set_shader_parameter("star_density", 0.0015)
	_distant_material.set_shader_parameter("star_opacity", 0.14 * star_opacity_scale)
	_distant_material.set_shader_parameter("star_drift", 0.0025)
	_distant_material.set_shader_parameter("star_scale", 1.0)
	_distant_material.set_shader_parameter("field_offset", _distant_field_origin)
	_distant_material.set_shader_parameter("parallax_uv_offset", Vector2.ZERO)
	_distant_material.set_shader_parameter("horizontal_expand", 1.0)
	_distant_material.set_shader_parameter("horizontal_offset", 0.0)
	distant_stars.material = _distant_material
	distant_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	distant_stars.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_near_material = STAR_MATERIAL.duplicate() as ShaderMaterial
	_near_material.set_shader_parameter("star_density", 0.0008)
	_near_material.set_shader_parameter("star_opacity", 0.22 * star_opacity_scale)
	_near_material.set_shader_parameter("star_drift", 0.005)
	_near_material.set_shader_parameter("star_scale", 1.55)
	_near_material.set_shader_parameter("field_offset", _near_field_origin)
	_near_material.set_shader_parameter("parallax_uv_offset", Vector2.ZERO)
	_near_material.set_shader_parameter("horizontal_expand", 1.0)
	_near_material.set_shader_parameter("horizontal_offset", 0.0)
	near_stars.material = _near_material
	near_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	near_stars.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _fit_plate() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var texture_size: Vector2 = BACKDROP_TEXTURE.get_size()
	var scale_factor: float = maxf(viewport_size.x / texture_size.x, viewport_size.y / texture_size.y)
	var rendered_size: Vector2 = texture_size * scale_factor * PLATE_OVERSCAN
	base_plate.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_plate_rest_position = (viewport_size - rendered_size) * 0.5
	base_plate.size = rendered_size
	base_plate.scale = Vector2.ONE
	var crop_fraction: float = maxf(0.0, (rendered_size.x - viewport_size.x) / rendered_size.x)
	_plate_parallax_limit = Vector2(
		maxf((rendered_size.x - viewport_size.x) * 0.5, 0.0),
		maxf((rendered_size.y - viewport_size.y) * 0.5, 0.0)
	)
	var horizontal_expand: float = viewport_size.x / rendered_size.x
	var horizontal_offset: float = 0.0 if rendered_size.x <= viewport_size.x else crop_fraction * 0.5
	for star_layer: ColorRect in [distant_stars, near_stars]:
		var star_material: ShaderMaterial = star_layer.material as ShaderMaterial
		star_material.set_shader_parameter("horizontal_crop", crop_fraction)
		star_material.set_shader_parameter("horizontal_expand", horizontal_expand)
		star_material.set_shader_parameter("horizontal_offset", horizontal_offset)
		star_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 0)
		star_layer.position = _plate_rest_position
		star_layer.size = rendered_size
	_apply_parallax(_parallax_amount)

func _apply_parallax(amount: Vector2) -> void:
	var plate_offset: Vector2 = Vector2(
		minf(PLATE_PARALLAX_PIXELS.x, _plate_parallax_limit.x),
		minf(PLATE_PARALLAX_PIXELS.y, _plate_parallax_limit.y)
	)
	base_plate.position = _plate_rest_position - amount * plate_offset
	_distant_material.set_shader_parameter(
		"field_offset", _distant_field_origin
	)
	_distant_material.set_shader_parameter("parallax_uv_offset", amount * DISTANT_STAR_PARALLAX_UV)
	distant_stars.position = _plate_rest_position - amount * Vector2(8.0, 6.0)
	_near_material.set_shader_parameter(
		"field_offset", _near_field_origin
	)
	_near_material.set_shader_parameter("parallax_uv_offset", amount * NEAR_STAR_PARALLAX_UV)
	near_stars.position = _plate_rest_position - amount * Vector2(20.0, 14.0)

func _apply_motion_preference() -> void:
	_motion_enabled = not GameState.reduce_motion
	var motion_scale: float = 1.0 if _motion_enabled else 0.0
	for star_layer: ColorRect in [distant_stars, near_stars]:
		var star_material: ShaderMaterial = star_layer.material as ShaderMaterial
		star_material.set_shader_parameter("motion_scale", motion_scale)
	if not _motion_enabled:
		_parallax_amount = Vector2.ZERO
		_apply_parallax(_parallax_amount)
	set_process(_motion_enabled and is_instance_valid(_parallax_target))
