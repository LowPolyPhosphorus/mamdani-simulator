extends Node

signal turn_changed
signal meters_changed
signal log_message(text: String)

const MAX_TURNS := 24
const ACTIONS_PER_TURN := 2
const BASE_INCOME := 10
const LAPSE_APPROVAL_PENALTY := 8
const SPILLOVER := 0.4
const LOSE_APPROVAL := 15
const BOROUGHS := ["Bronx", "Brooklyn", "Manhattan", "Queens", "Staten Island"]
const STATS := ["affordability", "ridership", "approval"]
const DRIFT := {"affordability": -2, "ridership": -2, "approval": -1}
# Rough placeholder starting values. Change them freely.
const START := {
	"Bronx": {"affordability": 42, "ridership": 52, "approval": 50},
	"Brooklyn": {"affordability": 46, "ridership": 56, "approval": 50},
	"Manhattan": {"affordability": 38, "ridership": 62, "approval": 50},
	"Queens": {"affordability": 50, "ridership": 48, "approval": 50},
	"Staten Island": {"affordability": 55, "ridership": 34, "approval": 46},
}

var turn: int = 1
var budget: int = 50
var actions_left: int = ACTIONS_PER_TURN
var target_borough: String = "Bronx"
var stats := {}
var active_policies: Array[Dictionary] = []
var active_demands: Array[Dictionary] = []

var affordability: int:
	get:
		return city_average("affordability")

var ridership: int:
	get:
		return city_average("ridership")

var approval: int:
	get:
		return city_average("approval")


func _ready() -> void:
	reset()


func reset() -> void:
	turn = 1
	budget = 50
	actions_left = ACTIONS_PER_TURN
	target_borough = BOROUGHS[0]
	stats = START.duplicate(true)
	active_policies.clear()
	active_demands.clear()


func city_average(stat: String) -> int:
	var total := 0
	for b in BOROUGHS:
		total += stats[b][stat]
	return roundi(total / float(BOROUGHS.size()))


func get_value(meter: String, borough: String = "") -> int:
	if meter == "budget":
		return budget
	if borough == "":
		return city_average(meter)
	return stats[borough][meter]


# The one place meters change. A named borough gets the full amount and the
# others get SPILLOVER of it. An empty borough means every borough gets it all.
func _change(meter: String, amount: int, borough: String = "") -> void:
	if meter == "budget":
		budget = clampi(budget + amount, 0, 100)
		return
	for b in BOROUGHS:
		var share := 1.0
		if borough != "" and b != borough:
			share = SPILLOVER
		stats[b][meter] = clampi(stats[b][meter] + roundi(amount * share), 0, 100)


func change_meter(meter: String, amount: int, borough: String = "") -> void:
	_change(meter, amount, borough)
	meters_changed.emit()


func _scope(card: PolicyCard, borough: String) -> String:
	return "" if card.citywide else borough


func is_active(card: PolicyCard, borough: String) -> bool:
	for entry in active_policies:
		if entry["card"] == card and entry["borough"] == borough:
			return true
	return false


func can_play(card: PolicyCard, borough: String) -> bool:
	if actions_left <= 0 or budget < card.cost:
		return false
	if card.ongoing and is_active(card, _scope(card, borough)):
		return false
	return true


func play_card(card: PolicyCard, borough: String) -> bool:
	if not can_play(card, borough):
		return false
	var scope := _scope(card, borough)
	actions_left -= 1
	if card.ongoing:
		active_policies.append({"card": card, "borough": scope})
	_change("budget", -card.cost + card.budget_change)
	_change("affordability", card.affordability_change, scope)
	_change("ridership", card.ridership_change, scope)
	_change("approval", card.approval_change, scope)
	var where := "citywide" if scope == "" else "in " + scope
	log_message.emit("Enacted %s %s." % [card.card_name, where])
	meters_changed.emit()
	return true


func apply_choice(choice: EventChoice) -> void:
	_change("budget", choice.budget_change)
	_change("affordability", choice.affordability_change)
	_change("ridership", choice.ridership_change)
	_change("approval", choice.approval_change)
	meters_changed.emit()


func add_demand(demand: Demand, borough: String) -> void:
	active_demands.append({"demand": demand, "turns_left": demand.turns_to_meet, "borough": borough})
	var where := "" if borough == "" else " in " + borough
	log_message.emit("%s%s want %s at %d+ within %d turns." % [
		demand.group_name, where, demand.meter, demand.threshold, demand.turns_to_meet
	])


func end_turn() -> void:
	turn += 1
	actions_left = ACTIONS_PER_TURN
	_change("budget", BASE_INCOME)
	for stat in STATS:
		_change(stat, DRIFT[stat])
	_run_ongoing_policies()
	_resolve_demands()
	turn_changed.emit()


func _run_ongoing_policies() -> void:
	for entry in active_policies.duplicate():
		var card: PolicyCard = entry["card"]
		var borough: String = entry["borough"]
		if card.upkeep > 0 and budget < card.upkeep:
			active_policies.erase(entry)
			_change("approval", -LAPSE_APPROVAL_PENALTY, borough)
			log_message.emit("Couldn't fund %s. It lapsed and approval fell." % card.card_name)
			continue
		_change("budget", -card.upkeep)
		_change("affordability", card.per_turn_affordability, borough)
		_change("ridership", card.per_turn_ridership, borough)
		_change("approval", card.per_turn_approval, borough)


func _resolve_demands() -> void:
	for entry in active_demands.duplicate():
		var demand: Demand = entry["demand"]
		var borough: String = entry["borough"]
		var where := "" if borough == "" else " in " + borough
		entry["turns_left"] -= 1
		if get_value(demand.meter, borough) >= demand.threshold:
			active_demands.erase(entry)
			_change("approval", demand.reward, borough)
			log_message.emit("%s%s are happy (+%d approval)." % [demand.group_name, where, demand.reward])
		elif entry["turns_left"] <= 0:
			active_demands.erase(entry)
			_change("approval", -demand.penalty, borough)
			log_message.emit("%s%s feel ignored (-%d approval)." % [demand.group_name, where, demand.penalty])


func is_term_over() -> bool:
	return turn > MAX_TURNS


func is_game_over() -> bool:
	return approval <= LOSE_APPROVAL or is_term_over()


func boroughs_carried() -> int:
	var count := 0
	for b in BOROUGHS:
		if stats[b]["approval"] >= 50:
			count += 1
	return count


func get_ending() -> String:
	if approval <= LOSE_APPROVAL:
		return "Voted out. Citywide approval collapsed."
	var avg: int = roundi((affordability + ridership + approval) / 3.0)
	var carried := "You carried %d of %d boroughs." % [boroughs_carried(), BOROUGHS.size()]
	if avg >= 70:
		return "Landslide. The city is thriving (average %d). %s" % [avg, carried]
	elif avg >= 50:
		return "Re-elected, narrowly (average %d). %s" % [avg, carried]
	return "The term ends and voters are unimpressed (average %d). %s" % [avg, carried]
