class_name PowerUp
extends Area2D
## Collectible power-up dropped by enemies. type picks the effect + sprite.

enum Type { MAGNET, SHIELD, HEART }

signal collected(power: PowerUp)

const TEX_MAGNET := preload("res://assets/generated/powerup_magnet_frame_0.png")
const TEX_SHIELD := preload("res://assets/generated/powerup_shield_frame_0.png")
const TEX_HEART := preload("res://assets/generated/powerup_heart_frame_0.png")

@export var type: Type = Type.MAGNET

var _t := 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	match type:
		Type.MAGNET:
			sprite.texture = TEX_MAGNET
			modulate = Color(0.5, 0.9, 1.0)
		Type.SHIELD:
			sprite.texture = TEX_SHIELD
			modulate = Color(0.5, 1.0, 0.85)
		Type.HEART:
			sprite.texture = TEX_HEART
			modulate = Color(1.0, 0.5, 0.6)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_t += delta
	var s := 1.0 + sin(_t * 5.0) * 0.08
	sprite.scale = Vector2(s, s)
	rotation = sin(_t * 3.0) * 0.12

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		collected.emit(self)
		queue_free()
