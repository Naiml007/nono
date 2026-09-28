class_name BossBolt
extends Area2D
## Projectile fired by the boss's radial burst. Travels in a straight line and
## damages the player on contact, then despawns.

var _dir := Vector2.ZERO
var _speed := 0.0
var _life := 3.0
var _spin := 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func launch(velocity_vec: Vector2) -> void:
	_dir = velocity_vec.normalized()
	_speed = velocity_vec.length()
	rotation = _dir.angle()

func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	global_position += _dir * _speed * delta
	_spin += delta * 14.0
	sprite.rotation = _spin

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player_hurtbox"):
		var p := area.get_parent()
		# Only despawn when the hit actually landed (damage or shield absorb).
		# An invulnerable player must let the bolt pass through: Area2D only
		# reports entry once, so freeing here would let the player delete the
		# boss's entire radial burst for free during their i-frames.
		if p is Player and p.apply_boss_damage():
			queue_free()
