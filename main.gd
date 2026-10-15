extends Control

const HAND_SIZE := 3
const EVENT_CHANCE := 0.5

@export var deck: Array[PolicyCard] = []
@export var events: Array[GameEvent] = []

@onready var turn_label: Label = %TurnLabel
@onready var meters_label: Label = %MetersLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var hand_container: HBoxContainer = %HandContainer
@onready var event_dialog: ConfirmationDialog = %EventDialog
@onready var result_dialog: AcceptDialog = %ResultDialog

var current_event: GameEvent
var game_ended := false

func _ready() -> void:
	end_turn_button.pressed.connect(GameState.end_turn)
	GameState.turn_changed.connect(_update_ui)
	GameState.meters_changed.connect(_update_ui)
	GameState.turn_changed.connect(_draw_hand)
	GameState.turn_changed.connect(_maybe_trigger_event)
	event_dialog.confirmed.connect(_on_event_choice.bind(true))
	event_dialog.canceled.connect(_on_event_choice.bind(false))
	_update_ui()
	_draw_hand()
	result_dialog.confirmed.connect(_restart)
	result_dialog.canceled.connect(_restart)


func _update_ui() -> void:
	turn_label.text = "Turn %d / %d" % [mini(GameState.turn, GameState.MAX_TURNS), GameState.MAX_TURNS]
	meters_label.text = "Budget %d | Affordality %d | Ridership %d  | Approval %d" % [
		GameState.budget, GameState.affordability, GameState.ridership, GameState.approval
		]
	if GameState.is_game_over() and not game_ended:
		game_ended = true
		end_turn_button.disabled = true
		result_dialog.title = "Term over"
		result_dialog.dialog_text = GameState.get_ending()
		result_dialog.popup_center()


func _draw_hand() -> void:
	for child in hand_container.get_children():
		child.queue_free()
	var pool := deck.duplicate()
	pool.shuffle()
	for card in pool.slice(0, HAND_SIZE):
		_add_card_button(card)


func _add_card_button(card: PolicyCard) -> void:
	var button := Button.new()
	button.text = "%s (cost %d)" % [card.card_name, card.cost]
	button.tooltip_text = card.description
	button.pressed.connect(_on_card_pressed.bind(card, button))
	hand_container.add_child(button)


func _on_card_pressed(card: PolicyCard, button: Button) -> void:
	if GameState.play_card(card):
		button.disabled = true


func _maybe_trigger_event() -> void:
	if events.is_empty() or GameState.is_term_over() or randf() > EVENT_CHANCE:
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
