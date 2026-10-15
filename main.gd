extends Control

const HAND_SIZE := 5
const EVENT_CHANCE := 0.5
const MAX_DEMANDS := 3
const DEMAND_CHANCE := 0.7
const METERS := ["budget", "affordability", "ridership", "approval"]

@export var deck: Array[PolicyCard] = []
@export var events: Array[GameEvent] = []
@export var demand_pool: Array[Demand] = []

@onready var turn_label: Label = %TurnLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var hand_container: HBoxContainer = %HandContainer
@onready var meters_container: VBoxContainer = %MetersContainer
@onready var event_dialog: ConfirmationDialog = %EventDialog
@onready var result_dialog: AcceptDialog = %ResultDialog

var actions_label := Label.new()
var policies_label := Label.new()
var demands_label := Label.new()
var log_label := Label.new()
var target_picker := OptionButton.new()
var log_lines: Array[String] = []
var current_event: GameEvent
var game_ended := false
var meter_bars := {}
var borough_bars := {}


func _ready() -> void:
	_build_meters()
	_build_borough_grid()
	_build_info_labels()
	_build_target_picker()
	end_turn_button.pressed.connect(GameState.end_turn)
	GameState.turn_changed.connect(_spawn_demand)
	GameState.turn_changed.connect(_update_ui)
	GameState.meters_changed.connect(_update_ui)
	GameState.turn_changed.connect(_draw_hand)
	GameState.turn_changed.connect(_maybe_trigger_event)
	GameState.meters_changed.connect(_refresh_hand)
	GameState.log_message.connect(_on_log_message)
	event_dialog.confirmed.connect(_on_event_choice.bind(true))
	event_dialog.canceled.connect(_on_event_choice.bind(false))
	result_dialog.confirmed.connect(_restart)
	result_dialog.canceled.connect(_restart)
	_spawn_demand()
	_spawn_demand()
	_update_ui()
	_draw_hand()


# -UI=

func _make_bar(value: float, min_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = value
	bar.custom_minimum_size = min_size
	return bar


func _build_meters() -> void:
	for meter in METERS:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = meter.capitalize()
		name_label.custom_minimum_size.x = 130
		var bar := _make_bar(GameState.get_value(meter), Vector2(300, 22))
		row.add_child(name_label)
		row.add_child(bar)
		meters_container.add_child(row)
		meter_bars[meter] = bar


func _build_borough_grid() -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for header in ["", "Affordability", "Ridership", "Approval"]:
		var h := Label.new()
		h.text = header
		grid.add_child(h)
	for b in GameState.BOROUGHS:
		var name_label := Label.new()
		name_label.text = b
		grid.add_child(name_label)
		for stat in GameState.STATS:
			var bar := _make_bar(GameState.get_value(stat, b), Vector2(110, 18))
			grid.add_child(bar)
			borough_bars["%s/%s" % [b, stat]] = bar
	var vbox := meters_container.get_parent()
	vbox.add_child(grid)
	vbox.move_child(grid, meters_container.get_index() + 1)


func _build_info_labels() -> void:
	var vbox := meters_container.get_parent()
	for label in [actions_label, policies_label, demands_label, log_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(label)
	vbox.move_child(actions_label, 1)
	policies_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.modulate = Color(1, 1, 1, 0.7)


func _build_target_picker() -> void:
	var vbox := meters_container.get_parent()
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := Label.new()
	label.text = "Target borough:"
	for b in GameState.BOROUGHS:
		target_picker.add_item(b)
	target_picker.item_selected.connect(_on_target_selected)
	row.add_child(label)
	row.add_child(target_picker)
	vbox.add_child(row)
	vbox.move_child(row, hand_container.get_index())


# -UI updates-

func _update_ui() -> void:
	turn_label.text = "Turn %d / %d" % [mini(GameState.turn, GameState.MAX_TURNS), GameState.MAX_TURNS]
	actions_label.text = "Actions left: %d / %d" % [GameState.actions_left, GameState.ACTIONS_PER_TURN]
	_update_policies_label()
	_update_demands_label()
	_update_meters()
	if GameState.is_game_over() and not game_ended:
		game_ended = true
		end_turn_button.disabled = true
		result_dialog.title = "Term over"
		result_dialog.dialog_text = GameState.get_ending()
		result_dialog.popup_centered()


func _tween_bar(bar: ProgressBar, target: float) -> void:
	if target == bar.value:
		return
	bar.modulate = Color.LIME_GREEN if target > bar.value else Color.TOMATO
	var tween := create_tween().set_parallel(true)
	tween.tween_property(bar, "value", target, 0.4)
	tween.tween_property(bar, "modulate", Color.WHITE, 0.6)


func _update_meters() -> void:
	for meter in METERS:
		_tween_bar(meter_bars[meter], GameState.get_value(meter))
	for key in borough_bars:
		var parts: PackedStringArray = key.split("/")
		_tween_bar(borough_bars[key], GameState.get_value(parts[1], parts[0]))


func _update_policies_label() -> void:
	if GameState.active_policies.is_empty():
		policies_label.text = "Active policies: none"
		return
	var parts: Array[String] = []
	var total_upkeep := 0
	for entry in GameState.active_policies:
		var card: PolicyCard = entry["card"]
		var where: String = "citywide" if entry["borough"] == "" else entry["borough"]
		parts.append("%s [%s]" % [card.card_name, where])
		total_upkeep += card.upkeep
	policies_label.text = "Upkeep %d/turn (base income +%d)\nActive: %s" % [
		total_upkeep, GameState.BASE_INCOME, ", ".join(parts)
	]


func _update_demands_label() -> void:
	if GameState.active_demands.is_empty():
		demands_label.text = "Demands: none"
		return
	var lines: Array[String] = ["Demands:"]
	for entry in GameState.active_demands:
		var d: Demand = entry["demand"]
		var where := "" if entry["borough"] == "" else " (%s)" % entry["borough"]
		lines.append("%s%s: %s %d+ (%d turns left)" % [d.group_name, where, d.meter, d.threshold, entry["turns_left"]])
	demands_label.text = "\n".join(lines)


# -Demands-

func _demand_active(demand: Demand, borough: String) -> bool:
	for entry in GameState.active_demands:
		if entry["demand"] == demand and entry["borough"] == borough:
			return true
	return false


func _spawn_demand() -> void:
	if GameState.active_demands.size() >= MAX_DEMANDS or GameState.is_game_over():
		return
	if randf() > DEMAND_CHANCE:
		return
	var options: Array = []
	for demand in demand_pool:
		if demand.meter == "budget":
			if not _demand_active(demand, "") and GameState.budget < demand.threshold:
				options.append([demand, ""])
		else:
			for b in GameState.BOROUGHS:
				if not _demand_active(demand, b) and GameState.get_value(demand.meter, b) < demand.threshold:
					options.append([demand, b])
	if options.is_empty():
		return
	var pick: Array = options.pick_random()
	GameState.add_demand(pick[0], pick[1])


# -Hand-

func _on_target_selected(index: int) -> void:
	GameState.target_borough = GameState.BOROUGHS[index]
	_refresh_hand()


func _draw_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	var pool := deck.filter(func(c): return not (c.citywide and c.ongoing and GameState.is_active(c, "")))
	pool.shuffle()
	for card in pool.slice(0, HAND_SIZE):
		_add_card_button(card)
	_refresh_hand()


func _add_card_button(card: PolicyCard) -> void:
	var button := Button.new()
	var label_text := "%s\ncost %d" % [card.card_name, card.cost]
	if card.ongoing:
		label_text += " | upkeep %d" % card.upkeep
	label_text += "\ncitywide" if card.citywide else "\ntargeted"
	button.text = label_text
	button.tooltip_text = card.description
	button.set_meta("card", card)
	button.pressed.connect(_on_card_pressed.bind(card, button))
	hand_container.add_child(button)


func _refresh_hand() -> void:
	for button in hand_container.get_children():
		if button.is_queued_for_deletion():
			continue
		var card: PolicyCard = button.get_meta("card")
		button.disabled = button.get_meta("played", false) or not GameState.can_play(card, GameState.target_borough)


func _on_card_pressed(card: PolicyCard, button: Button) -> void:
	if GameState.play_card(card, GameState.target_borough):
		button.set_meta("played", true)
		_refresh_hand()


# -Log, events, restart-

func _on_log_message(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 4:
		log_lines.pop_front()
	log_label.text = "\n".join(log_lines)


func _maybe_trigger_event() -> void:
	if events.is_empty() or GameState.is_game_over() or randf() > EVENT_CHANCE:
		return
	current_event = events.pick_random()
	event_dialog.title = current_event.title
	event_dialog.dialog_text = current_event.description
	event_dialog.ok_button_text = current_event.choice_a.choice_text
	event_dialog.cancel_button_text = current_event.choice_b.choice_text
	event_dialog.popup_centered()


func _on_event_choice(chose_a: bool) -> void:
	GameState.apply_choice(current_event.choice_a if chose_a else current_event.choice_b)


func _restart() -> void:
	GameState.reset()
	get_tree().reload_current_scene()
