class_name UpgradePanel
extends Control
## The wave-clear upgrade picker. Runs in PROCESS_MODE_ALWAYS so it still
## receives input while the game tree is paused, and forwards 1/2/3 hotkeys.

signal choice_requested(index: int)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var idx := -1
		match event.physical_keycode:
			KEY_1: idx = 0
			KEY_2: idx = 1
			KEY_3: idx = 2
		if idx >= 0:
			choice_requested.emit(idx)
			get_viewport().set_input_as_handled()
