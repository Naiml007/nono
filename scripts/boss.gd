class_name Boss
extends Enemy
## Wave 50 boss: a big armored drone with two telegraphed attacks (a charge
## dash and a radial bolt burst). It never dies on contact — the player has to
## dash through it to damage it. Every source of damage is tracked so the game
## can award the "Let Me Solo Her" achievement only to a lone attacker.

signal boss_died(boss: Boss)
signal health_changed(current: int, max_hp: int)

const BOLT_SCENE := preload("res://scenes/boss_bolt.tscn")

enum State { CHASE, TELEGRAPH_CHARGE, TELEGRAPH_BURST, CHARGE }

@export var max_hp: int = 35
@export var chase_speed: float = 82.0
@export var charge_speed: float = 560.0
@export var burst_count: int = 8
@export var bolt_speed: float = 190.0
@export var telegraph_time: float = 0.65
@export var charge_time: float = 0.42

var hp: int = 35
var state := State.CHASE

var _state_left := 0.0
var _attack_cd := 1.2
var _flash := 0.0
var _dash_hit_cd := 0.0
var _charge_dir := Vector2.RIGHT
var _telegraph_tint := Color.WHITE
var _damage_sources: Dictionary = {}

func _ready() -> void:
	super._ready()
	hp = max_hp
	health_changed.emit(hp, max_hp)
	sprite.scale = Vector2.ONE
	sprite.modulate = Color.WHITE

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta * wobble_freq
	if _flash > 0.0:
		_flash -= delta
	_update_visuals()
	_tick_dash_damage(delta)
	if _player == null or not is_instance_valid(_player):
		velocity = Vector2.ZERO
		move_and_slide()
		return
	match state:
		State.CHASE:
			_physics_chase(delta)
		State.TELEGRAPH_CHARGE, State.TELEGRAPH_BURST:
			_state_left -= delta
			velocity = Vector2.ZERO
			move_and_slide()
			if _state_left <= 0.0:
				if state == State.TELEGRAPH_CHARGE:
					_start_charge()
				else:
					_fire_burst()
		State.CHARGE:
			velocity = _charge_dir * charge_speed
			move_and_slide()
			sprite.rotation = _charge_dir.angle()
			_state_left -= delta
			if _state_left <= 0.0:
				_finish_attack()

func _physics_chase(delta: float) -> void:
	_attack_cd -= delta
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	if dist > 0.01:
		var dir := to_player / dist
		var perp := Vector2(-dir.y, dir.x)
		velocity = dir * chase_speed + perp * sin(_t) * 22.0
	move_and_slide()
	if velocity.length() > 10.0:
		sprite.rotation = velocity.angle()
	if _attack_cd <= 0.0:
		_pick_attack()

func _pick_attack() -> void:
	sprite.rotation = 0.0
	if randf() < 0.55:
		state = State.TELEGRAPH_CHARGE
		_state_left = telegraph_time
		_telegraph_tint = Color(1.7, 0.35, 0.3)
	else:
		state = State.TELEGRAPH_BURST
		_state_left = telegraph_time + 0.25
		_telegraph_tint = Color(1.7, 1.25, 0.3)
	sprite.scale = Vector2(1.28, 1.28)
	_update_visuals()

func _start_charge() -> void:
	state = State.CHARGE
	_state_left = charge_time
	_charge_dir = (_player.global_position - global_position).normalized()
	if _charge_dir == Vector2.ZERO:
		_charge_dir = Vector2.RIGHT
	_telegraph_tint = Color.WHITE
	sprite.scale = Vector2.ONE
	sprite.rotation = 0.0
	_update_visuals()
	Fx.burst(global_position, Color(1.0, 0.4, 0.25), 12, 220, 0.4, 0.8)

func _fire_burst() -> void:
	_finish_attack()
	var base_angle := (_player.global_position - global_position).angle()
	for i in burst_count:
		var bolt: BossBolt = BOLT_SCENE.instantiate()
		var ang := base_angle + i * TAU / float(burst_count)
		bolt.global_position = global_position
		get_parent().add_child(bolt)
		bolt.launch(Vector2(cos(ang), sin(ang)) * bolt_speed)
	Fx.burst(global_position, Color(1.0, 0.85, 0.35), 16, 260, 0.4, 0.9)
	Sfx.play("powerup", 0.8)

func _finish_attack() -> void:
	state = State.CHASE
	_attack_cd = randf_range(1.5, 2.5)
	sprite.scale = Vector2.ONE
	_telegraph_tint = Color.WHITE
	sprite.rotation = 0.0
	_update_visuals()

## Player dash-through damage (area overlap can miss a fast dash, so check
## proximity every frame while the player is dashing).
func _tick_dash_damage(delta: float) -> void:
	_dash_hit_cd = maxf(_dash_hit_cd - delta, 0.0)
	if _dash_hit_cd > 0.0 or _player == null or not _player.is_dashing:
		return
	if global_position.distance_to(_player.global_position) < 78.0:
		take_damage(1, _player.source_id())
		_dash_hit_cd = 0.35
		Fx.burst(global_position, Color(1.0, 0.6, 0.3), 10, 240, 0.35, 0.9)
		# Weightier beat than a regular kill: small hit-stop + screen shake.
		Fx.hitstop(0.08)
		Fx.shake(5.0, 0.18)

func take_damage(amount: int, source_id: int) -> void:
	if _dead:
		return
	_damage_sources[source_id] = int(_damage_sources.get(source_id, 0)) + amount
	hp -= amount
	_flash = 0.16
	health_changed.emit(hp, max_hp)
	if hp <= 0:
		die(true)

func die(_scored: bool) -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	set_physics_process(false)
	Fx.burst(global_position, Color(1.0, 0.5, 0.2), 48, 540, 1.1, 1.7)
	Fx.shake(14.0, 0.5)
	Fx.hitstop(0.3)
	Sfx.play("explode", 0.7, -2.0)
	boss_died.emit(self)
	queue_free()

## Returns the attacker id if exactly one source dealt damage this fight,
## otherwise -1 (used for the solo achievement).
func solo_attacker_id() -> int:
	if _damage_sources.size() == 1:
		return int(_damage_sources.keys()[0])
	return -1

func _update_visuals() -> void:
	var tint := _telegraph_tint
	if _flash > 0.0:
		tint = Color(
			minf(tint.r + 0.8, 2.5),
			minf(tint.g + 0.3, 2.5),
			minf(tint.b + 0.3, 2.5))
	sprite.modulate = tint
