extends Node
## Autoload singleton that carries run state across scenes and persists the best score.

signal score_changed(new_score: int)
signal best_changed(new_best: int)

var score: int = 0
var best_score: int = 0
var kills: int = 0
var wave: int = 0

const SAVE_PATH := "user://nono_save.cfg"

func _ready() -> void:
	load_best()

## Reset the run's score / stats. Called when a new game starts.
func reset_run() -> void:
	score = 0
	kills = 0
	wave = 0
	score_changed.emit(score)

## Add points and track the best score.
func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)
	if score > best_score:
		best_score = score
		best_changed.emit(best_score)

func register_kill() -> void:
	kills += 1

func save_best() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "best", best_score)
	cfg.save(SAVE_PATH)

func load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best_score = cfg.get_value("meta", "best", 0)
