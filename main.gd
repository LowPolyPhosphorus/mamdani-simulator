extends Control

const MAX_TURNS := 24

var turn: int = 1

@onready var turn_label: Label = %TurnLabel
@onready var end_turn_button: Button = %EndTurnButton


func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	_update_ui()


func _on_end_turn_pressed() -> void:
	turn += 1
	_update_ui()


func _update_ui() -> void:
	if turn > MAX_TURNS:
		turn_label.text = "Term over"
		end_turn_button.disabled = true
	else:
		turn_label.text = "Turn %d / %d" % [turn, MAX_TURNS]
