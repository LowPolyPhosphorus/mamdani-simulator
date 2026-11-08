extends Node

signal turn_changed
signal meters_changed
signal log_message(text: String)

const MAX_TURNS := 24
const HEALTHY := 60
const GATE_WEAK_MARGIN := 15
const ATTITUDE_DRIFT := 1
const LOBBY_COST := 5
const LOBBY_GAIN := 8
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
const GATEKEEPERS := ["MTA", "Council", "Albany"]
# Rough placeholder starting values. Change them freely.
const START := {
	"Bronx": {"affordability": 42, "ridership": 52, "approval": 50},
	"Brooklyn": {"affordability": 46, "ridership": 56, "approval": 50},
	"Manhattan": {"affordability": 38, "ridership": 62, "approval": 50},
	"Queens": {"affordability": 50, "ridership": 48, "approval": 50},
	"Staten Island": {"affordability": 55, "ridership": 34, "approval": 46},
}
const PRESETS := {
	"easy": {
		"actions": 3, "income": 12, "drift_aff": 1, "drift_rid": 1, "drift_app": 0,
		"spillover": 0.6, "lose_approval": 10, "lapse_penalty": 4,
		"event_chance": 0.35, "demand_chance": 0.5, "max_demands": 2, "issue_chance": 0.2, "max_issues": 2,
		"health_drift": 0.0,
	},
	"normal": {
		"actions": 2, "income": 10, "drift_aff": 2, "drift_rid": 2, "drift_app": 1,
		"spillover": 0.4, "lose_approval": 15, "lapse_penalty": 8,
		"event_chance": 0.5, "demand_chance": 0.7, "max_demands": 3, "issue_chance": 0.4, "max_issues": 3,
		"health_drift": 0.5,
	},
	"hard": {
		"actions": 2, "income": 8, "drift_aff": 3, "drift_rid": 2, "drift_app": 1,
		"spillover": 0.3, "lose_approval": 20, "lapse_penalty": 10,
		"event_chance": 0.6, "demand_chance": 0.8, "max_demands": 4, "issue_chance": 0.5, "max_issues": 4,
		"health_drift": 1.0,
	},
}

var difficulty: String = "normal"
var intro_shown := false
var pending_load := false
var demands_met := 0
var demands_failed := 0
var issues_fixed := 0
var peak_approval := 0
var approval_history: Array[int] = []
var cfg: Dictionary = PRESETS["normal"]

func set_difficulty(d: String) -> void:
	difficulty = d
	cfg = PRESETS[d]
	intro_shown = false

var turn: int = 1
var budget: int = 50
var actions_left: int = cfg["actions"]
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


func _drift(stat: String, borough: String = "") -> int:
	var amount: int
	match stat:
		"affordability":
			amount = -cfg["drift_aff"]
		"ridership":
			amount = mini(0, -cfg["drift_rid"] + (1 if has_advisor("transit") else 0))
		_:
			amount = mini(0, -cfg["drift_rid"] + (1 if has_advisor("press") else 0))
	if borough != "" and get_value(stat, borough) >= HEALTHY:
		amount = int(amount * cfg["health_drift"])
	return amount - (1 if has_mod("winter") else 0)

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
	actions_left = actions_per_turn()
	target_borough = BOROUGHS[0]
	stats = START.duplicate(true)
	active_policies.clear()
	active_demands.clear()
	attitudes = {"MTA": 50, "Council": 50, "Albany": 40}
	active_issues.clear(); demands_met = 0; demands_failed = 0; issues_fixed = 0; peak_approval = approval
	banned_borough = ""
	approval_history = [approval]
	advisors.clear()
	cooldowns.clear()
	loyalty.clear()
	scandals = 0


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
# others get cfg["spillover"] of it. An empty borough means every borough gets it all.
func _change(meter: String, amount: int, borough: String = "") -> void:
	if meter == "budget":
		budget = clampi(budget + amount, 0, budget_cap())
		return
	for b in BOROUGHS:
		var share := 1.0
		if borough != "" and b != borough:
			share = spillover()
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
	if mood >= gate_threshold_for(card):
		return "pass"
	if mood >= gate_threshold_for(card) - GATE_WEAK_MARGIN:
		return "weak"
	return "blocked"


func _drift_attitudes() -> void:
	for body in GATEKEEPERS:
		attitudes[body] = move_toward(attitudes[body], 50, ATTITUDE_DRIFT)


func can_lobby() -> bool:
	return actions_left > 0 and budget >= LOBBY_COST and not is_game_over() and not has_mod("no_lobby")


func lobby(body: String) -> void:
	if not can_lobby():
		return
	actions_left -= 1
	_change("budget", -LOBBY_COST)
	change_attitude(body, lobby_gain(body))
	log_message.emit("Lobbied the %s (+%d attitude)." % [body, lobby_gain(body)])
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
		active_policies.append({"card": card, "borough": scope, "age": 0})
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
	if active_issues.size() >= cfg["max_issues"] or randf() > cfg["issue_chance"]:
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
			active_issues.erase(entry); issues_fixed += 1
			log_message.emit("Fixed %s in %s." % [entry["name"], entry["borough"]])

func neediest_borough() -> String:
	var worst := ""
	var worst_score := 999.0
	for b in stats.keys().filter(func(k): return k != banned_borough):
		var s: float = (stats[b]["affordability"] + stats[b]["ridership"] + stats[b]["approval"]) / 3.0
		if s < worst_score:
			worst_score = s
			worst = b
	return worst

func end_turn() -> void:
	turn += 1
	actions_left = actions_per_turn()
	_change("budget", income())
	for b in BOROUGHS:
		for stat in STATS:
			stats[b][stat] = clampi(stats[b][stat] + _drift(stat, b), 0, 100)
	_drift_attitudes()
	_run_ongoing_policies()
	_resolve_demands()
	_run_issues()
	_spawn_issue()
	_run_loyalty()
	_tick_cooldowns()
	_end_turn_mods()
	approval_history.append(approval)
	peak_approval = maxi(peak_approval, approval); turn_changed.emit()


func _run_ongoing_policies() -> void:
	for entry in active_policies.duplicate():
		var card: PolicyCard = entry["card"]
		var borough: String = entry["borough"]
		if card.upkeep > 0 and budget < card.upkeep:
			active_policies.erase(entry)
			_change("approval", -cfg["lapse_penalty"], borough)
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
			_change("approval", demand_reward(demand), borough)
			log_message.emit("%s%s are happy (+%d approval)." % [demand.group_name, where, demand_reward(demand)])
		elif entry["turns_left"] <= 0:
			active_demands.erase(entry)
			_change("approval", -demand_penalty(demand), borough)
			log_message.emit("%s%s feel ignored (-%d approval)." % [demand.group_name, where, demand_penalty(demand)])


func is_term_over() -> bool:
	return turn > MAX_TURNS


func is_game_over() -> bool:
	return approval <= lose_threshold() or is_term_over()


func boroughs_carried() -> int:
	var count := 0
	for b in BOROUGHS:
		if stats[b]["approval"] >= 50:
			count += 1
	return count


func get_ending() -> String:
	if approval <= lose_threshold():
		return "Voted out. Citywide approval collapsed."
	var avg: int = roundi((affordability + ridership + approval) / 3.0)
	var carried := "You carried %d of %d boroughs." % [boroughs_carried(), BOROUGHS.size()]
	if avg >= 70:
		return "Landslide. The city is thriving (average %d). %s" % [avg, carried]
	elif avg >= 50:
		return "Re-elected, narrowly (average %d). %s" % [avg, carried]
	return "The term ends and voters are unimpressed (average %d). %s" % [avg, carried]


const ACH_PATH := "user://achievements.cfg"
const ACHIEVEMENTS := [
	["survivor", "Survivor", "Finish all 24 turns without being voted out."],
	["landslide", "Landslide", "Finish with an average score of 70 or more"],
	["every_borough", "Every Borough", "Carry all 5 boroughs"],
	["hard_won", "Hard Hat", "Finish a term on Hard"],
	["penny", "Penny Pincher", "Finish with 60 or more budget"],
	["minimalist", "Minimalist", "Finish a term enacting 20 cards or fewer."],
	["promises", "Promise Keeper", "Meet 8 demands in one term."],
	["fixer", "Fixer", "Fix 10 issues in one term."],
	["wonk", "Policy Wonk", "Enact 36 cards in one term."],
	["beloved", "Beloved", "Reach 85 citywide approval."], 
	["underdog", "Underdog", "Finish a term with a challenge modifier on."], 
	["mod_no_lobby", "Above Board", "Finish a term with No Lobbying on."], 
	["mod_albany", "Albany Who?", "Finish a term with Albany Hates You on."], 
	["mod_broke", "Shoestring", "Finish a term with Shoestring Budget on."], 
	["mod_winter", "Winter Survivor", "Finish a term with Rough Winter on."], 
	["mod_short", "One and Done", "Finish a term with One Action Only on."],
	["mod_council", "Council Whisperer", "Finish a term with Hostile Council on."],
	["mod_crisis", "Crisis Manager", "Finish a term with Constant Crisis on."],
	["mod_austerity", "Tight Belt", "Finish a term with Austerity on."],
	["mod_glass_jaw", "Iron Chin", "Finish a term with Glass Jaw on."],
	["mod_tunnel", "Eyes on the prize", "Finish a term with Tunnel Vision on."],
	["mod_skeleton", "Small Hand", "Finish a term with Skeleton Crew on."],
	["mod_demanding", "Hard to Please", "Finish a term with Demanding Public on."],
	["mod_expiring", "Beat the Clock", "Finish a term with Expiring Policies on."],
	["mod_pride", "Spread the Love", "Finish a term with Borough Pride on."],
	["mod_midterms", "Midterm Master", "Finish a term with Midterms on."],
	["cabinet_full", "Full Cabinet", "Have2 advisors at the end of a term."],
	["loyal", "Loyal Friends", "Finish a term with every advisors abover 60 loyalty."],
	["scandal", "Scandal Sheet", "Lose an advisor to a scandal."],
]


func _earned(cards: int) -> Array:
	var ids: Array = []
	var survived: bool = is_term_over() and approval > lose_threshold()
	var avg: int = roundi((affordability + ridership + approval) / 3.0)
	if survived:
		ids.append("survivor"); ids.append_array(["underdog"] if not modifiers.is_empty() else []); ids.append_array(modifiers.map(func(m): return "mod_" + m))
		if avg >= 70:
			ids.append("landslide")
		if boroughs_carried() == BOROUGHS.size():
			ids.append("every_borough")
		if difficulty == "hard":
			ids.append("hard_won")
		if budget >= 60:
			ids.append("penny")
		if cards <= 20:
			ids.append("minimalist")
		if advisors.size() >= 2:
			ids.append("cabinet_full")
		if not advisors.is_empty() and advisors.all(func(a): return int(loyalty.get(a, 0)) > 60):
			ids.append("loyal")
	if scandals >= 1:
		ids.append("scandal")
	if demands_met >= 8:
		ids.append("promises")
	if issues_fixed >= 10:
		ids.append("fixer")
	if cards >= 36:
		ids.append("wonk")
	if maxi(peak_approval, approval) >= 85:
		ids.append("beloved")
	return ids


func check_achievements(cards: int) -> Array:
	var  save := ConfigFile.new()
	save.load(ACH_PATH)
	var fresh: Array = []
	for id in _earned(cards):
		if not save.get_value("unlocked", id, false):
			save.set_value("unlocked", id, true)
			fresh.append(id)
	if not fresh.is_empty():
		save.save(ACH_PATH)
	return fresh


func is_unlocked(id: String) -> bool:
	var save := ConfigFile.new()
	if save.load(ACH_PATH) != OK:
		return false
	return save.get_value("unlocked", id, false)


var modifiers: Array = []

const MODIFIERS := [
	["no_lobby", "No Lobbying", "You can't lobby gatekeepers."],
	["albany", "Albany Hates You", "Lobbying Albany is only half as effective."],
	["broke", "Shoestring Budget", "Your budget can never go above 50."],
	["winter", "Rough Winter", "Every stat drifts down 1 extra point per turn."],
	["short", "One Action Short", "One fewer action each turn (min 1)."],
	["council", "Hostile Council", "Council's approval thresholds are 10 higher."],
	["crisis", "Constant Crisis", "An event happens every turn."],
	["austerity", "Austerity", "Your income is 3 lower each turn."],
	["glass_jaw", "Glass Jaw", "You're voted out at 30 approval or below."],
	["tunnel", "Tunnel Vision", "Cards only affect the borough you target."],
	["skeleton", "Skeleton Crew", "You only draw 3 cards each turn."],
	["demanding", "Demanding Public", "Demand rewards are halved and penalties doubled."],
	["expiring", "Expiring Policies", "Ongoing policies expire after 6 turns."],
	["pride", "Borough Pride", "You can't target the same borough two turns in a row."],
	["midterms", "Midterms", "After turn 12, approval under 50 costs you 12 approval everywhere."],
]


const ABILITIES := {
	"hawk": ["Audit", "+15 budget.", 4],
	"organizer": ["Rally", "+6 approval in the targeted borough.", 3],
	"transit": ["Emergency Service", "+8 ridership in the targeted borough.", 3],
	"fixer": ["Rapid Repair", "Fixes the oldest issue.", 4],
	"whisperer": ["Backroom Deal", "+10 attitude with all gatekeepers.", 5],
	"press": ["Press Conference", "+4 approval citywide.", 4],
	"lobbyist": ["Free Lobby", "+8 attitude with your lowest gatekeeper.", 3],
	"strategist": ["Extra Push", "+1 action this turn.", 5],
}

var cooldowns := {}

const LOYALTY_START := 70
const LOYALTY_DECAY := 3
const LOYALTY_USE_GAIN := 10
const LOYALTY_WEAK := 30
const LOYALTY_RISK := 40
const SCANDAL_CHANCE := 0.25
const SCANDAL_PENALTY := 6

var loyalty := {}
var scandals := 0

const ADVISORS := [
	["hawk", "Budget Hawk", "+2 income every turn."],
	["organizer", "Community Organizer", "Demand rewards are 50% bigger."],
	["transit", "Transit Chief", "Ridership drifts down 1 less per turn."],
	["fixer", "City Fixer", "Issues drain 1 less per turn."],
	["whisperer", "Gatekeeper Whisperer", "All gatekeeper thresholds are 5 lower."],
	["press", "Press Secretary", "Approval drifts down 1 less per turn."],
	["lobbyist", "Veteran Lobbyist", "Lobbying raises attitude by 4 more."],
	["strategist", "Chief Strategist", "+1 action on every 3rd turn."],
]

var advisors: Array = []


func has_advisor(id: String) -> bool:
	return advisors.has(id) and int(loyalty.get(id, LOYALTY_START)) >= LOYALTY_WEAK


func advisor_text(id: String) -> String:
	for a in ADVISORS:
		if a[0] == id:
			return "%s: %s" % [a[1], a[2]]
	return id


func issue_drain() -> int:
	return ISSUE_DRAIN - (1 if has_advisor("fixer") else 0)


func has_mod(id: String) -> bool:
	return modifiers.has(id)


func actions_per_turn() -> int:
	var n: int = 1 if has_mod("short") else int(cfg["actions"])
	if has_advisor("strategist") and turn % 3 == 0:
		n += 1
	return n


func budget_cap() -> int:
	return 50 if has_mod("broke") else 100


func lobby_gain(body: String) -> int:
	var g := LOBBY_GAIN + (4 if has_advisor("lobbyist") else 0)
	if body == "Albany" and has_mod("albany"):
		return roundi(g * 0.5)
	return g


const EXPIRY_TURNS := 6
const MIDTERM_TURN := 12
const MIDTERM_PENALTY := 12

var banned_borough := ""


func gate_threshold_for(card: PolicyCard) -> int:
	var t: int = card.get("gate_threshold")
	if card.gatekeeper == "Council" and has_mod("council"):
		t += 10
	if has_advisor("whisperer"):
		t -= 5
	return t


func income() -> int:
	return int(cfg.get("income")) - (3 if has_mod("austerity") else 0) + (2 if has_advisor("hawk") else 0)


func lose_threshold() -> int:
	var t: int = cfg.get("lose_approval")
	return maxi(t, 30) if has_mod("glass_jaw") else t


func spillover() -> float:
	return 0.0 if has_mod("tunnel") else float(cfg.get("spillover"))


func demand_reward(d: Demand) -> int:
	var r: int = d.reward
	if has_advisor("organizer"):
		r = roundi(r * 1.5)
	return maxi(1, roundi(r * 0.5)) if has_mod("demanding") else r


func demand_penalty(d: Demand) -> int:
	var p: int = d.penalty
	return p * 2 if has_mod("demanding") else p


func _end_turn_mods() -> void:
	if has_mod("pride"):
		banned_borough = target_borough
		target_borough = neediest_borough()
	else:
		banned_borough = ""
	if has_mod("expiring"):
		for entry in active_policies.duplicate():
			entry["age"] = int(entry.get("age", 0)) + 1
			if entry["age"] >= EXPIRY_TURNS:
				active_policies.erase(entry)
				log_message.emit("%s expired." % entry["card"].card_name)
	if has_mod("midterms"):
		if turn == MIDTERM_TURN - 1:
			log_message.emit("Midterms come after turn %d. Keep citywide approval at 50 or higher." % MIDTERM_TURN)
		elif turn == MIDTERM_TURN + 1:
			if approval < 50:
				_change("approval", -MIDTERM_PENALTY)
				log_message.emit("Midterms: voters are unhappy. -%d approval everywhere." % MIDTERM_PENALTY)
			else:
				log_message.emit("Midterms: you held on. No penalty.")


const UNLOCK_ALL := false 

const MOD_UNLOCKS := {
	"winter": "survivor",
	"crisis": "survivor",
	"tunnel": "survivor",
	"albany": "every_borough",
	"council": "promises",
	"demanding": "underdog",
	"expiring": "underdog",
	"pride": "underdog",
	"glass_jaw": "hard_won",
	"midterms": "landslide",
}


func mod_unlocked(id: String) -> bool:
	if UNLOCK_ALL or not MOD_UNLOCKS.has(id):
		return true
	return is_unlocked(MOD_UNLOCKS[id])


func achievement_text(id: String) -> String:
	for a in ACHIEVEMENTS:
		if a[0] == id:
			return "%s: %s" % [a[1], a[2]]
	return id


func _tick_cooldowns() -> void:
	for id in cooldowns.keys():
		cooldowns[id] = maxi(0, int(cooldowns[id]) - 1)


func can_use_ability(id: String) -> bool:
	return has_advisor(id) and int(cooldowns.get(id, 0)) <= 0 and not is_game_over()


func use_ability(id: String) -> bool:
	if not can_use_ability(id):
		return false
	match id:
		"hawk":
			_change("budget", 15)
		"organizer":
			_change("approval", 6, target_borough)
		"transit":
			_change("ridership", 8, target_borough)
		"fixer":
			if active_issues.is_empty():
				log_message.emit("No issues to fix.")
				return false
			var issue: Dictionary = active_issues[0]
			active_issues.remove_at(0)
			issues_fixed += 1
			log_message.emit("Fixed %s in %s." % [issue["name"], issue["borough"]])
		"whisperer":
			for body in GATEKEEPERS:
				change_attitude(body, 10)
		"press":
			_change("approval", 4)
		"lobbyist":
			var lowest: String = GATEKEEPERS[0]
			for body in GATEKEEPERS:
				if attitudes[body] < attitudes[lowest]:
					lowest = body
			change_attitude(lowest, 8)
		"strategist":
			actions_left += 1
	loyalty[id] = mini(100, int(loyalty.get(id, LOYALTY_START)) + LOYALTY_USE_GAIN)
	cooldowns[id] = ABILITIES[id][2]
	log_message.emit("%s used %s." % [advisor_text(id).split(":")[0], ABILITIES[id][0]])
	meters_changed.emit()
	return true


func hire_advisor(id: String) -> void:
	advisors.append(id)
	loyalty[id] = LOYALTY_START


func _run_loyalty() -> void:
	for id in advisors.duplicate():
		loyalty[id] = clampi(int(loyalty.get(id, LOYALTY_START)) - LOYALTY_DECAY, 0, 100)
		if loyalty[id] < LOYALTY_RISK and randf() < SCANDAL_CHANCE:
			var nm: String = advisor_text(id).split(":")[0]
			advisors.erase(id)
			scandals += 1
			loyalty.erase(id)
			cooldowns.erase(id)
			_change("approval", -SCANDAL_PENALTY)
			log_message.emit("Scandal! %s resigned (-%d approval)." % [nm, SCANDAL_PENALTY])
