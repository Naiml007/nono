class_name Player
extends CharacterBody2D
## Robot pilot: 8-direction movement, dash with i-frames, health, shield, magnet.

signal health_changed(current: int, max_hp: int)
signal shield_changed(active: bool)
signal magnet_changed(active: bool)
signal died
signal took_hit

## The play arena is a fixed 1280x720 logical box, even when the window's
## aspect ratio expands the viewport (mobile stretch aspect = expand). The
## player clamps to this box, never to the (possibly larger) viewport.
const ARENA := Vector2(1280, 720)

@export var speed: float = 250.0
@export var dash_speed: float = 820.0
@export var dash_time: float = 0.14
@export var dash_cooldown: float = 1.0
@export var invuln_time: float = 1.4
@export var magnet_radius: float = 250.0

var max_hp: int = 4
var hp: int = 4
var has_shield: bool = false
var magnet_left: float = 0.0
var is_dashing: bool = false

# Persistent buffs granted by wave-clear upgrades.
var speed_mult: float = 1.0
var dash_cd_mult: float = 1.0
var dash_speed_mult: float = 1.0
var magnet_radius_bonus: float = 0.0
var shockwave: bool = false

## Debug-only: while true the player ignores all damage and the dash cooldown
## never blocks. Set exclusively by the Debug autoload (god mode) and false in
## every normal run, so gameplay is byte-identical when debugging is off.
var debug_god: bool = false

var _facing := Vector2.RIGHT
var _dash_dir := Vector2.RIGHT
var _dash_left := 0.0
var _cd_left := 0.0
var _invuln_left := 0.0
var _flash := 0.0
var _hurt_flash := 0.0
var _trail_acc := 0.0
var _dead := false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	health_changed.emit(hp, max_hp)
	shield_changed.emit(false)

func _physics_process(delta: float) -> void:
	if is_dashing:
		_dash_left -= delta
		velocity = _dash_dir * dash_speed * dash_speed_mult
		_trail_acc += delta
		if _trail_acc > 0.02:
			_trail_acc = 0.0
			Fx.burst(global_position, Color(0.4, 0.9, 1.0), 1, 50, 0.35, 0.8)
		if _dash_left <= 0.0:
			is_dashing = false
			velocity = Vector2.ZERO
	else:
		_cd_left = maxf(_cd_left - delta, 0.0)
		# move_left/right/up/down carry arrow keys (always) plus WASD when the
		# WASD-controls setting is enabled (bound/unbound by GameState).
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input != Vector2.ZERO:
			_facing = input
		velocity = input * speed * speed_mult
		if _can_dash() and Input.is_action_just_pressed("dash"):
			_try_dash()
	move_and_slide()
	_clamp_to_screen()
	_tick(delta)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse-click dash is handled here (not as an InputMap action) so clicks on
	# UI buttons never also trigger a dash. Space/Shift dash via the "dash" action.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and GameState.mouse_dash:
		try_dash()

func _can_dash() -> bool:
	return (debug_god or _cd_left <= 0.0) and not is_dashing

## Public dash entry point — the on-screen touch dash button calls this, and
## it shares the exact same implementation as the keyboard (action) and mouse
## (click) paths: there is only one dash code path.
func try_dash() -> void:
	_try_dash()

func _try_dash() -> void:
	if _dead or not _can_dash():
		return
	is_dashing = true
	_dash_dir = _facing.normalized()
	_dash_left = dash_time
	_cd_left = dash_cooldown * dash_cd_mult
	_invuln_left = maxf(_invuln_left, dash_time + 0.05)
	Sfx.play("dash")
	Fx.shake(4.0, 0.15)
	Fx.burst(global_position, Color(0.4, 0.9, 1.0), 10, 200, 0.45, 1.0)
	if shockwave:
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e != null and is_instance_valid(e) and e.global_position.distance_to(global_position) <= 95.0:
				e.die(true)
		for node in get_tree().get_nodes_in_group("boss"):
			var b := node as Boss
			if b != null and is_instance_valid(b) and b.global_position.distance_to(global_position) <= 95.0:
				b.take_damage(3, source_id())
		Fx.burst(global_position, Color(0.5, 0.85, 1.0), 26, 340, 0.5, 1.5)
		Fx.shake(7.0, 0.22)

## Called by an enemy when its hitbox touches this player's hurtbox.
func on_enemy_contact(enemy: Enemy) -> void:
	if _dead:
		return
	if enemy is Boss:
		# The boss never dies from contact. A dash is how you damage it (handled
		# in Boss._tick_dash_damage); otherwise it just damages the player.
		if not is_dashing and _invuln_left <= 0.0:
			apply_boss_damage()
		return
	if is_invulnerable():
		enemy.die(true)
		return
	if has_shield:
		has_shield = false
		shield_changed.emit(false)
		_invuln_left = 0.8
		_hurt_flash = 0.18
		Sfx.play("powerup")
		Fx.shake(4.0, 0.15)
		enemy.die(true)
		return
	hp -= 1
	health_changed.emit(hp, max_hp)
	_invuln_left = invuln_time
	_flash = 0.0
	_hurt_flash = 0.22
	took_hit.emit()
	enemy.die(true)
	Fx.shake(10.0, 0.3)
	if hp <= 0:
		_die()

## Player takes damage from the boss or its projectiles. Dash i-frames,
## invulnerability and the shield all block it, and it does not kill the attacker.
func apply_boss_damage() -> void:
	if _dead or is_invulnerable():
		return
	if has_shield:
		has_shield = false
		shield_changed.emit(false)
		_invuln_left = 0.8
		_hurt_flash = 0.18
		Sfx.play("powerup")
		Fx.shake(4.0, 0.15)
		return
	hp -= 1
	health_changed.emit(hp, max_hp)
	_invuln_left = invuln_time
	_hurt_flash = 0.22
	took_hit.emit()
	Fx.shake(10.0, 0.3)
	if hp <= 0:
		_die()

## Identifier used when this player deals damage. In singleplayer this is always
## the same id; in future multiplayer each player gets a distinct one.
func source_id() -> int:
	return multiplayer.get_unique_id()

func _die() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	is_dashing = false
	set_physics_process(false)
	died.emit()

func _tick(delta: float) -> void:
	if magnet_left > 0.0:
		magnet_left -= delta
		if magnet_left <= 0.0:
			magnet_changed.emit(false)
	if _invuln_left > 0.0:
		_invuln_left -= delta
		_flash += delta
	if _hurt_flash > 0.0:
		_hurt_flash -= delta
	var base := Color.WHITE
	if _hurt_flash > 0.0:
		var k: float = clampf(_hurt_flash / 0.2, 0.0, 1.0)
		base = base.lerp(Color(2.0, 0.35, 0.35), k)
	if _invuln_left > 0.0 and int(_flash * 14.0) % 2 == 0:
		base.a = 0.35
	sprite.modulate = base

## Keep the player inside the fixed 1280x720 arena. With stretch aspect=expand
## the viewport can be wider/taller than the arena on mobile, so clamping to
## the viewport rect (the old behaviour) would let the player leave the play
## area into the letterbox-free margin.
func _clamp_to_screen() -> void:
	global_position = Vector2(
		clampf(global_position.x, 0.0, ARENA.x),
		clampf(global_position.y, 0.0, ARENA.y)
	)

func is_invulnerable() -> bool:
	return _invuln_left > 0.0 or is_dashing or debug_god

func heal(amount: int) -> void:
	if _dead:
		return
	hp = mini(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)

func increase_max_hp(amount: int) -> void:
	max_hp += amount
	hp = mini(hp + amount, max_hp)
	health_changed.emit(hp, max_hp)

func effective_magnet_radius() -> float:
	return magnet_radius + magnet_radius_bonus
