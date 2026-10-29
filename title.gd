extends Control

const GAME_SCENE := "res://main.tscn"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	
	var title := Label.new()
	title.text = "MAMDANI SIMULATOR"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	
	for o in [["Easy", "easy"], ["Normal", "normal"], ["Hard", "hard"]]:
		var b := Button.new()
		b.text = "Start Term: " + o[0]
		b.pressed.connect(_start.bind(o[1]))
		box.add_child(b)
	
	var help := Button.new()
	help.text = "How to Play"
	help.pressed.connect(_show_help)
	box.add_child(help)
	
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)
	
	var disclaimer := Label.new()
	disclaimer.text = "not affiliated or endorsed by any real person or office."
	disclaimer.modulate = Color(1, 1, 1, 0.6)
	disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(disclaimer)
	
func _start(d: String) -> void:
	GameState.set_difficulty(d)
	GameState.reset()
	get_tree().change_scene_to_file(GAME_SCENE)

const HOW_TO_PLAY := """GOAL
Get through 24 turns with citywide approval staying healthy. Higher approval at the end of the game means a better result.

EACH TURN
1. Pick a borough to target (click it, or use Auto-target neediest).
2. Play cards from your hand. Each one costs budget and one action.
3. Click End Turn when you're out of actions or budget.

TARGETTING
A target card hits the borough you selected fully. The other boroughs only get a share of the effect. Citywide cards hit every borough fully.

POLICIES
Ongoing policies keep helping each turn, but they charge upkeep. If you cant pay it, the policy lapses and approval drops.

TIPS
Fix the weakest borough first, sincing losing happens on the citywide average. Don't spend all your budget in one turn, buecause upkeep is due every turn."""

var help_overlay: Control

func _show_help() -> void:
	if help_overlay != null:
		return
	help_overlay = Control.new()
	help_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(help_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_overlay.add_child(dim)
	
	var center:= CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	help_overlay.add_child(center)
	
	var panel := PanelContainer.new()
	center.add_child(panel)
	
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	
	var heading := Label.new()
	heading.text = "How to Play"
	heading.add_theme_font_size_override("font_size", 28)
	v.add_child(heading)
	
	var body := Label.new()
	body.text = HOW_TO_PLAY
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(520, 0)
	v.add_child(body)
	
	var close := Button.new()
	close.text = "Got it"
	close.pressed.connect(_close_help)
	v.add_child(close)

func _close_help() -> void:
	help_overlay.queue_free()
	help_overlay = null
