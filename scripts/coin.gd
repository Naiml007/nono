class_name Coin
extends Area2D
## A pickup energy core. Emits [signal collected] when the player touches it.

signal collected(coin: Coin)

var _t := 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("coins")
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_t += delta
	var s := 1.0 + sin(_t * 6.0) * 0.1
	sprite.scale = Vector2(s, s)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		collected.emit(self)
		queue_free()
