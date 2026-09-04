class_name Enemy
extends CharacterBody2D
## Hostile chaser drone. Homes toward the player with a sine wobble.
## Touching the player's hurtbox damages the player (and destroys this drone);
## if the player is dashing or invulnerable the drone is destroyed harmlessly.

signal died(enemy: Enemy)

@export var speed: float = 100.0
@export var wobble_amp: float = 34.0
@export var wobble_freq: float = 2.4

var _player: Player
var _t := 0.0
var _dead := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var hitbox: Area2D = $HitBox

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_t = randf() * TAU
	_player = get_tree().get_first_node_in_group("player")
	hitbox.area_entered.connect(_on_hitbox_area_entered)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _player == null or not is_instance_valid(_player):
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_t += delta * wobble_freq
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > 0.01:
		var dir := to_player / dist
		var perp := Vector2(-dir.y, dir.x)
		velocity = dir * speed + perp * sin(_t) * wobble_amp
	move_and_slide()
	if velocity.length() > 10.0:
		sprite.rotation = velocity.angle()

func _on_hitbox_area_entered(area: Area2D) -> void:
	if _dead:
		return
	if area.is_in_group("player_hurtbox"):
		var p := area.get_parent()
		if p is Player:
			p.on_enemy_contact(self)

## Destroy this drone. `scored` awards points (player caused the kill).
func die(scored: bool) -> void:
	if _dead:
		return
	_dead = true
	if scored:
		GameState.add_score(10)
		GameState.register_kill()
		Fx.popup(global_position, "+10", Color(1.0, 0.62, 0.24), 20)
	Fx.burst(global_position, Color(1.0, 0.42, 0.2), 18, 320, 0.55, 1.2)
	Sfx.play("explode", randf_range(0.85, 1.15))
	died.emit(self)
	queue_free()
