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
	turn_changed.emit()
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
