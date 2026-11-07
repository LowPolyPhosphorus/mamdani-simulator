extends Node

const PATH := "user://settings.cfg"

var volume := 1.0
var muted := false
var fullscreen := false
var overlay: Control


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	volume = cfg.get_value("audio", "volume", 1.0)
	muted = cfg.get_value("audio", "muted", false)
	fullscreen = cfg.get_value("video", "fullscreen", false)
	apply()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, muted)
	if not OS.has_feature("web"):
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(PATH)


func open(parent: Node) -> void:
	if overlay != null:
		return
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 200
	parent.add_child(overlay)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

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
	heading.text = "Settings"
	heading.add_theme_font_size_override("font_size", 28)
	v.add_child(heading)

	var vol_label := Label.new()
	vol_label.text = "Volume: %d%%" % roundi(volume * 100)
	v.add_child(vol_label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volume
	slider.custom_minimum_size = Vector2(320, 24)
	slider.value_changed.connect(func(val: float):
		volume = val
		vol_label.text = "Volume: %d%%" % roundi(val * 100)
		apply())
	v.add_child(slider)

	var mute := CheckButton.new()
	mute.text = "Mute"
	mute.button_pressed = muted
	mute.toggled.connect(func(on: bool):
		muted = on
		apply())
	v.add_child(mute)

	if not OS.has_feature("web"):
		var fs := CheckButton.new()
		fs.text = "Fullscreen"
		fs.button_pressed = fullscreen
		fs.toggled.connect(func(on: bool):
			fullscreen = on
			apply())
		v.add_child(fs)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(close)
	v.add_child(back)


func close() -> void:
	if overlay == null:
		return
	save()
	overlay.queue_free()
	overlay = null


func _unhandled_key_input(event: InputEvent) -> void:
	if overlay != null and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
