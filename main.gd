extends Control

@onready var turn_label: Label = %TurnLabel
@onready var meters_label: Label = %MetersLabel
@onready var end_turn_button: Button = %EndTurnButton
@export var hand: Array[PolicyCard] = []
@onready var hand_container: HBoxContainer = %HandContainer

func _ready() -> void:
	end_turn_button.pressed.connect(GameState.end_turn)
	GameState.turn_changed.connect(_update_ui)
	GameState.meters_changed.connect(_update_ui)
	_update_ui()
	_build_hand()

func _update_ui() -> void:
	if GameState.is_term_over():
		turn_label.text = "Term over"
		end_turn_button.disabled = true
	else:
		turn_label.text = "Turn %d / %d" % [GameState.turn, GameState.MAX_TURNS]
	meters_label.text = "Budget %d | Affordability %d | Ridership %d | Approval %d" % [
		GameState.budget, GameState.affordability, GameState.ridership, GameState.approval
	]

func _build_hand() -> void:
	for card in hand:
		var button := Button.new()
		button.text = "%s (cost %d)" % [card.card_name, card.cost]
		button.tooltip_text = card.description
		button.pressed.connect(_on_card_pressed.bind(card, button))
		hand_container.add_child(button)
		
func _on_card_pressed(card: PolicyCard, button: Button) -> void:
	if GameState.play_card(card):
		button.disabled = true
