extends Control

const GAME_SCENE := "res://main.tscn"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	
	var box := VBoxContainer.new()
	box.add_theme_constant_override("seperation", 16)
	center.add_child(box)
	
	var title := Label.new()
	title.text = "MAMDANI SIMULATOR"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	
	var start := Button.new()
	start.text = "Start Term"
	start.pressed.connect(_on_start_pressed)
	box.add_child(start)
	
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(get_tree().quit)
	box.add_child(quit)
	
	var disclaimer := Label.new()
	disclaimer.text = "not affiliated or endorsed by any real person or office."
	disclaimer.modulate = Color(1, 1, 1, 0.6)
	disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(disclaimer)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
