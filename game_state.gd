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
const GATE_WEAK_MARGIN := 15
const ATTITUDE_DRIFT := 1
const LOBBY_COST := 5
const LOBBY_GAIN := 8
const ISSUE_CHANCE := 0.4
const MAX_ISSUES := 3
const ISSUE_DRAIN := 3
const ISSUE_ESCALATE_TURNS := 3
const ISSUE_PENALTY := 6
const ISSUES := [
	{"name": "Overcrowded buses", "meter": "ridership"},
	{"name": "Eviction wave", "meter": "affordability"},
	{"name": "Food desert", "meter": "affordability"},
	{"name": "Service complaints", "meter": "approval"},
]
const BOROUGHS := ["Bronx", "Brooklyn", "Manhattan", "Queens", "Staten Island"]
const STATS := ["affordability", "ridership", "approval"]
const DRIFT := {"affordability": -2, "ridership": -2, "approval": -1}
const GATEKEEPERS := ["MTA", "Council", "Albany"]
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
var active_issues: Array[Dictionary] = []
var attitudes := {"MTA": 50, "Council": 50, "Albany": 40}

var affordability: int:
	get:
		return city_average("affordability")

var ridership: int:
	get:
		return city_average("ridership")

var approval: int:
	get:
		return city_average("approval")


func change_attitude(body: String, amount: int) -> void:
	if not attitudes.has(body):
		return
	attitudes[body] = clampi(attitudes[body] + amount, 0, 100)
	meters_changed.emit()


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
	attitudes = {"MTA": 50, "Council": 50, "Albany": 40}
	active_issues.clear()


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


func gate_status(card: PolicyCard) -> String:
	if card.gatekeeper == "None":
		return "pass"
	var mood: int = attitudes[card.gatekeeper]
	if mood >= card.gate_threshold:
		return "pass"
	if mood >= card.gate_threshold - GATE_WEAK_MARGIN:
		return "weak"
	return "blocked"


func _drift_attitudes() -> void:
	for body in GATEKEEPERS:
		attitudes[body] = move_toward(attitudes[body], 50, ATTITUDE_DRIFT)


func can_lobby() -> bool:
	return actions_left > 0 and budget >= LOBBY_COST and not is_game_over()


func lobby(body: String) -> void:
	if not can_lobby():
		return
	actions_left -= 1
	_change("budget", -LOBBY_COST)
	change_attitude(body, LOBBY_GAIN)
	log_message.emit("Lobbied the %s (+%d attitude)." % [body, LOBBY_GAIN])
	meters_changed.emit()


func has_active_named(card_name: String, scope: String) -> bool:
	for entry in active_policies:
		if entry["card"].card_name != card_name:
			continue
		if scope == "" or entry["borough"] == "" or entry["borough"] == scope:
			return true
	return false


func play_card(card: PolicyCard, borough: String) -> bool:
	if not can_play(card, borough):
		return false
	var scope := _scope(card, borough)
	var where := "citywide" if scope == "" else "in " + scope
	var status := gate_status(card)
	actions_left -= 1

	if status == "blocked":
		change_attitude(card.gatekeeper, -2)
		log_message.emit("%s blocked %s. The action was wasted." % [card.gatekeeper, card.card_name])
		meters_changed.emit()
		return true

	var mult := 0.5 if status == "weak" else 1.0
	if card.ongoing:
		active_policies.append({"card": card, "borough": scope})
	_change("budget", -card.cost + card.budget_change)
	_change("affordability", roundi(card.affordability_change * mult), scope)
	_change("ridership", roundi(card.ridership_change * mult), scope)
	_change("approval", roundi(card.approval_change * mult), scope)
	_fix_issues(card, scope)
	if card.synergy_with != "" and has_active_named(card.synergy_with, scope):
		_change("approval", card.synergy_bonus, scope)
		log_message.emit("Synergy with %s: +%d approval." % [card.synergy_with, card.synergy_bonus])
	if card.gatekeeper != "None":
		change_attitude(card.gatekeeper, card.attitude_change)
	if status == "weak":
		log_message.emit("%s grudgingly passed %s %s. Only half the effect." % [card.gatekeeper, card.card_name, where])
	else:
		log_message.emit("Enacted %s %s." % [card.card_name, where])
	meters_changed.emit()
	return true


func apply_choice(choice: EventChoice, borough: String = "") -> void:
	_change("budget", choice.budget_change)
	_change("affordability", choice.affordability_change, borough)
	_change("ridership", choice.ridership_change, borough)
	_change("approval", choice.approval_change, borough)
	meters_changed.emit()


func add_demand(demand: Demand, borough: String) -> void:
	active_demands.append({"demand": demand, "turns_left": demand.turns_to_meet, "borough": borough})
	var where := "" if borough == "" else " in " + borough
	log_message.emit("%s%s want %s at %d+ within %d turns." % [
		demand.group_name, where, demand.meter, demand.threshold, demand.turns_to_meet
	])


func _spawn_issue() -> void:
	if active_issues.size() >= MAX_ISSUES or randf() > ISSUE_CHANCE:
		return
	var b: String = BOROUGHS.pick_random()
	var template: Dictionary = ISSUES.pick_random()
	for entry in active_issues:
		if entry["borough"] == b and entry["name"] == template["name"]:
			return
	active_issues.append({"name": template["name"], "meter": template["meter"], "borough": b, "age": 0})
	log_message.emit("New issue in %s: %s." % [b, template["name"]])


func _run_issues() -> void:
	for entry in active_issues:
		var b: String = entry["borough"]
		var m: String = entry["meter"]
		entry["age"] += 1
		stats[b][m] = clampi(stats[b][m] - ISSUE_DRAIN, 0, 100)
		if entry ["age"] == ISSUE_ESCALATE_TURNS:
			stats[b]["approval"] = clampi(stats[b]["approval"] - ISSUE_PENALTY, 0, 100)
			log_message.emit("%s is angry about %s (-%d approval)." % [b, entry["name"], ISSUE_PENALTY])

func _fix_issues(card: PolicyCard, scope: String) -> void:
	for entry in active_issues.duplicate():
		if scope != "" and entry["borough"] != scope:
			continue
		var gain: int = card.get(entry["meter"] + "_change")
		if gain > 0:
			active_issues.erase(entry)
			log_message.emit("Fixed %s in %s." % [entry["name"], entry["borough"]])


func end_turn() -> void:
	turn += 1
	actions_left = ACTIONS_PER_TURN
	_change("budget", BASE_INCOME)
	for stat in STATS:
		_change(stat, DRIFT[stat])
	_drift_attitudes()
	_run_ongoing_policies()
	_resolve_demands()
	_run_issues()
	_spawn_issue()
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
