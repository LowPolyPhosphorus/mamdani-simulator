extends Node

signal turn_changed
signal meters_changed
signal log_message(text: String)

const MAX_TURNS := 24
const ACTIONS_PER_TURN := 2
const BASE_INCOME := 10
const LAPSE_APPROVAL_PENALTY := 8

var turn: int = 1
var budget: int = 50
var affordability: int = 50
var ridership: int = 50
var approval: int = 50
var actions_left: int = ACTIONS_PER_TURN
var active_policies: Array[PolicyCard] = []
var active_demands: Array[Dictionary] = []


func _apply(meter: String, amount: int) -> void:
	set(meter, clampi(get(meter) + amount, 0, 100))


func change_meter(meter: String, amount: int) -> void:
	_apply(meter, amount)
	meters_changed.emit()


func can_play(card: PolicyCard) -> bool:
	if actions_left <= 0 or budget < card.cost:
		return false
	if card.ongoing and active_policies.has(card):
		return false
	return true


func play_card(card: PolicyCard) -> bool:
	if not can_play(card):
		return false
	actions_left -= 1
	if card.ongoing:
		active_policies.append(card)
	_apply("budget", -card.cost + card.budget_change)
	_apply("affordability", card.affordability_change)
	_apply("ridership", card.ridership_change)
	_apply("approval", card.approval_change)
	log_message.emit("Enacted: %s" % card.card_name)
	meters_changed.emit()
	return true


func apply_choice(choice: EventChoice) -> void:
	_apply("budget", choice.budget_change)
	_apply("affordability", choice.affordability_change)
	_apply("ridership", choice.ridership_change)
	_apply("approval", choice.approval_change)
	meters_changed.emit()


func add_demand(demand: Demand) -> void:
	active_demands.append({"demand": demand, "turns_left": demand.turns_to_meet})
	log_message.emit("New demand: %s want %s at %d+ within %d turns." % [
		demand.group_name, demand.meter, demand.threshold, demand.turns_to_meet
	])


func end_turn() -> void:
	turn += 1
	actions_left = ACTIONS_PER_TURN
	_apply("budget", BASE_INCOME)
	_apply("affordability", -3)
	_apply("ridership", -3)
	_apply("approval", -2)
	_run_ongoing_policies()
	_resolve_demands()
	turn_changed.emit()


func _run_ongoing_policies() -> void:
	for policy in active_policies.duplicate():
		if policy.upkeep > 0 and budget < policy.upkeep:
			active_policies.erase(policy)
			_apply("approval", -LAPSE_APPROVAL_PENALTY)
			log_message.emit("Couldn't fund %s. It lapsed and approval fell." % policy.card_name)
			continue
		_apply("budget", -policy.upkeep)
		_apply("affordability", policy.per_turn_affordability)
		_apply("ridership", policy.per_turn_ridership)
		_apply("approval", policy.per_turn_approval)


func _resolve_demands() -> void:
	for entry in active_demands.duplicate():
		var demand: Demand = entry["demand"]
		entry["turns_left"] -= 1
		if get(demand.meter) >= demand.threshold:
			active_demands.erase(entry)
			_apply("approval", demand.reward)
			log_message.emit("%s are happy (+%d approval)." % [demand.group_name, demand.reward])
		elif entry["turns_left"] <= 0:
			active_demands.erase(entry)
			_apply("approval", -demand.penalty)
			log_message.emit("%s feel ignored (-%d approval)." % [demand.group_name, demand.penalty])


func is_term_over() -> bool:
	return turn > MAX_TURNS


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
	actions_left = ACTIONS_PER_TURN
	active_policies.clear()
	active_demands.clear()
