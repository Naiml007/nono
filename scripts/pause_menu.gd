class_name PauseMenu
extends Control
## The in-game pause overlay. Runs in PROCESS_MODE_ALWAYS so it keeps receiving
## input while the game tree is paused. Pressing ESC resumes the game.

signal resume_requested

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()
