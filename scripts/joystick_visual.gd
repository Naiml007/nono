class_name JoystickVisual
extends Control
## Draws the virtual joystick overlay: a base ring at the thumb anchor plus a
## knob that follows the stick vector. Driven by TouchControls.

var origin := Vector2.ZERO
var vector := Vector2.ZERO
var radius := 70.0
var knob_radius := 30.0
var base_color := Color(0.45, 0.85, 1.0, 0.30)
var ring_color := Color(0.75, 0.95, 1.0, 0.55)
var knob_color := Color(0.78, 0.97, 1.0, 0.80)
var knob_ring_color := Color(0.95, 1.0, 1.0, 0.9)

func set_stick(o: Vector2, v: Vector2) -> void:
	origin = o
	vector = v
	queue_redraw()

func _draw() -> void:
	draw_circle(origin, radius, base_color)
	draw_arc(origin, radius, 0.0, TAU, 48, ring_color, 3.0)
	var knob_pos := origin + vector * radius
	draw_circle(knob_pos, knob_radius, knob_color)
	draw_arc(knob_pos, knob_radius, 0.0, TAU, 32, knob_ring_color, 2.0)