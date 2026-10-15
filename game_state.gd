extends Node

signal turn_changed
signal meters_changed

const MAX_TURNS := 24

var turn: int = 1
var budget: int = 50
var affordability: int = 50
var ridership: int = 50
var approval: int = 50


func end_turn() -> void:
	turn += 1
	change_meter("budget", 10)
	change_meter("affordability", -3)
	change_meter("ridership", -3)
	change_meter("approval", -2)
	turn_changed.emit()
	


func change_meter(meter: String, amount: int) -> void:
	set(meter, clampi(get(meter) + amount, 0, 100))
	meters_changed.emit()


func is_term_over() -> bool:
	return turn > MAX_TURNS


func play_card(card: PolicyCard) -> bool:
	if budget < card.cost:
		return false
	change_meter("budget", -card.cost)
	change_meter("budget", card.budget_change)
	change_meter("affordability", card.affordability_change)
	change_meter("ridership", card.ridership_change)
	change_meter("approval", card.approval_change)
	return true

func apply_choice(choice: EventChoice) -> void:
	change_meter("budget", choice.budget_change)
	change_meter("affordability", choice.affordability_change)
	change_meter("ridership", choice.ridership_change)
	change_meter("approval", choice.approval_change)


func is_game_over() -> bool:
	return approval <= 0 or is_term_over()


func get_ending() -> String:
	if approval <= 0:
		return "Voted out. Approval hit zero."
	var avg: int = (affordability + ridership + approval) / 3
	if avg >= 70:
		return "Landslide. The city is thriving (average %d)." % avg
	elif avg >= 50:
		return "Re-elected, narrowly (average %d)." % avg
	return "The term ends and voters are unimpressed (average %d)." % avg


func reset() -> void:
	turn = 1
	budget = 50
	affordability = 50
	ridership = 50
	approval = 50
