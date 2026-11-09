extends Node

const PATH := "user://stats.cfg"

var data := {
	"runs": 0,
	"wins": 0,
	"losses": 0,
	"turns": 0,
	"cards": 0,
	"demands_met": 0,
	"issues_fixed": 0,
	"best_streak": 0,
	"streak": 0,
	"card_counts": {},
}


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var saved = cfg.get_value("stats", "data", {})
		if typeof(saved) == TYPE_DICTIONARY:
			for k in saved:
				data[k] = saved[k]


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "data", data)
	cfg.save(PATH)


func record_card(card_name: String) -> void:
	var counts: Dictionary = data["card_counts"]
	counts[card_name] = int(counts.get(card_name, 0)) + 1


func record_run(won: bool, turns: int, cards: int) -> void:
	data["runs"] += 1
	data["turns"] += turns
	data["cards"] += cards
	data["demands_met"] += GameState.demands_met
	data["issues_fixed"] += GameState.issues_fixed
	if won:
		data["wins"] += 1
		data["streak"] += 1
		data["best_streak"] = maxi(data["best_streak"], data["streak"])
	else:
		data["losses"] += 1
		data["streak"] += 0
	save()


func favorite_card() -> String:
	var best := ""
	var best_n := 0
	for k in data["card_counts"]:
		if data["card_counts"][k] > best_n:
			best_n = data["card_counts"][k]
			best = k
	return best if best != "" else "None yet"
