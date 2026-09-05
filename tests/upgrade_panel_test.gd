extends Node
## Headless verification of the wave-clear upgrade panel:
## 1) exactly 3 cards are built from the remaining buff pool
## 2) the tree is paused while choosing and unpaused after
## 3) choosing a card applies the matching buff exactly once
## 4) every card shows a STACK or ONCE PER RUN chip (clarity)

var _failures := 0

func _ready() -> void:
	await get_tree().process_frame
	var game: Node2D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	# Drive straight into the upgrade offer (bypasses the 1s wave timer).
	game._offer_upgrades()
	await get_tree().process_frame
	await get_tree().process_frame

	_check(game.upgrade_panel.visible, "upgrade panel visible while choosing")
	_check(get_tree().paused, "tree paused while choosing")

	var cards: Array = game.upgrade_cards.get_children()
	_check(cards.size() == 3, "exactly 3 upgrade cards offered (got %d)" % cards.size())
	_check(game._current_choices.size() == 3, "3 choices recorded")
	var seen: Dictionary = {}
	var no_dups := true
	for cid: String in game._current_choices:
		if seen.has(cid):
			no_dups = false
		seen[cid] = true
	_check(no_dups, "no duplicate buffs in one offer")

	var all_chipped: bool = true
	for card: Control in cards:
		var has_chip := false
		for child in card.get_children():
			if child is VBoxContainer:
				for sub in child.get_children():
					if sub is Label and ("STACK" in str(sub.text) or "ONCE PER RUN" in str(sub.text)):
						has_chip = true
		if not has_chip:
			all_chipped = false
	_check(all_chipped, "every card shows a STACK or ONCE PER RUN chip")

	# Choose the first card; speed is the representative checkable buff.
	var chosen_id: String = game._current_choices[0]
	var before := 0.0
	var expected := 1.0
	if chosen_id == "speed":
		before = game.player.speed_mult
		expected = before * 1.20

	game._on_upgrade_choice_index(0)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(not game.upgrade_panel.visible, "upgrade panel hidden after choice")
	_check(not get_tree().paused, "tree unpaused after choice")
	if chosen_id == "speed":
		_check(is_equal_approx(game.player.speed_mult, expected),
			"speed buff applied once (%.2f -> %.2f)" % [before, game.player.speed_mult])
	_check(int(game._stack_counts.get(chosen_id, 0)) == 1, "buff registered as stack count 1")

	# Choosing again when already unpaused must be ignored.
	game._on_upgrade_chosen(chosen_id)
	await get_tree().process_frame
	_check(not get_tree().paused and not game.upgrade_panel.visible, "no double-apply when unpaused")

	# An out-of-range hotkey is ignored.
	game._on_upgrade_choice_index(99)
	await get_tree().process_frame
	_check(not get_tree().paused, "out-of-range choice index ignored")

	_summary()
	get_tree().quit()

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS: ", msg)
	else:
		_failures += 1
		print("FAIL: ", msg)

func _summary() -> void:
	print("==== UPGRADE PANEL TEST SUMMARY: failures=%d ====" % _failures)
	get_tree().quit()
