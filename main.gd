extends Control

const HAND_SIZE := 5
const EVENT_CHANCE := 0.5
const METERS := ["budget", "affordability", "ridership", "approval"]

@export var deck: Array[PolicyCard] = []
@export var events: Array[GameEvent] = []

@onready var turn_label: Label = %TurnLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var hand_container: HBoxContainer = %HandContainer
@onready var meters_container: VBoxContainer = %MetersContainer
@onready var event_dialog: ConfirmationDialog = %EventDialog
@onready var result_dialog: AcceptDialog = %ResultDialog

var actions_label := Label.new()
var policies_label := Label.new()
var log_label := Label.new()
var log_lines: Array[String] = []
var current_event: GameEvent
var game_ended := false
var meter_bars := {}


func _ready() -> void:
	_build_info_labels()
	_build_meters()
	end_turn_button.pressed.connect(GameState.end_turn)
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
	_update_ui()
	_draw_hand()


func _build_info_labels() -> void:
	var vbox := meters_container.get_parent()
	for label in [actions_label, policies_label, log_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(label)
	vbox.move_child(actions_label, 1)
	policies_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.modulate = Color(1, 1, 1, 0.7)


func _update_ui() -> void:
	turn_label.text = "Turn %d / %d" % [mini(GameState.turn, GameState.MAX_TURNS), GameState.MAX_TURNS]
	actions_label.text = "Actions left: %d / %d" % [GameState.actions_left, GameState.ACTIONS_PER_TURN]
	_update_policies_label()
	_update_meters()
	if GameState.is_game_over() and not game_ended:
		game_ended = true
		end_turn_button.disabled = true
		result_dialog.title = "Term over"
		result_dialog.dialog_text = GameState.get_ending()
		result_dialog.popup_centered()


func _update_policies_label() -> void:
	if GameState.active_policies.is_empty():
		policies_label.text = "Active policies: none"
		return
	var parts: Array[String] = []
	for policy in GameState.active_policies:
		parts.append("%s (upkeep %d)" % [policy.card_name, policy.upkeep])
	policies_label.text = "Active policies: " + ", ".join(parts)


func _build_meters() -> void:
	for meter in METERS:
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = meter.capitalize()
		name_label.custom_minimum_size.x = 130
		var bar := ProgressBar.new()
		bar.max_value = 100
		bar.value = GameState.get(meter)
		bar.custom_minimum_size = Vector2(300, 26)
		row.add_child(name_label)
		row.add_child(bar)
		meters_container.add_child(row)
		meter_bars[meter] = bar


func _update_meters() -> void:
	for meter in METERS:
		var bar: ProgressBar = meter_bars[meter]
		var target: float = GameState.get(meter)
		if target == bar.value:
			continue
		bar.modulate = Color.LIME_GREEN if target > bar.value else Color.TOMATO
		var tween := create_tween().set_parallel(true)
		tween.tween_property(bar, "value", target, 0.4)
		tween.tween_property(bar, "modulate", Color.WHITE, 0.6)


func _draw_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	var pool := deck.filter(func(c): return not GameState.active_policies.has(c))
	pool.shuffle()
	for card in pool.slice(0, HAND_SIZE):
		_add_card_button(card)
	_refresh_hand()


func _add_card_button(card: PolicyCard) -> void:
	var button := Button.new()
	var label_text := "%s\ncost %d" % [card.card_name, card.cost]
	if card.ongoing:
		label_text += " | upkeep %d" % card.upkeep
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
		button.disabled = button.get_meta("played", false) or not GameState.can_play(card)


func _on_card_pressed(card: PolicyCard, button: Button) -> void:
	if GameState.play_card(card):
		button.set_meta("played", true)
		_refresh_hand()


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
