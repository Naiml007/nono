class_name MainMenu
extends Control
## Main menu: title + Play/Quit buttons wired to scene switching.

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton
@onready var best_label: Label = %BestLabel

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	best_label.text = "Best score: %d" % GameState.best_score

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
