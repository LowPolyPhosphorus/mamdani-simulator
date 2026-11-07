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
	
	var logo := _build_logo()
	box.add_child(logo)
	_animate_logo(logo)
	
	if FileAccess.file_exists("user://run.cfg"):
		var cont := Button.new()
		cont.text = "Continue"
		cont.custom_minimum_size = Vector2(0, 52)
		cont.pressed.connect(_continue)
		box.add_child(cont)
	
	var start := Button.new()
	start.text = "Start Term"
	start.custom_minimum_size = Vector2(0, 52)
	start.pressed.connect(_show_difficulty)
	box.add_child(start)
	
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(0, 40)
	settings_btn.pressed.connect(func(): Settings.open(self))
	box.add_child(settings_btn)
	
	var ach := Button.new(); ach.text = "Achievements"; ach.custom_minimum_size = Vector2(0, 40); ach.pressed.connect(_show_achievements); box.add_child(ach); var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var help := Button.new()
	help.text = "How to Play"
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.pressed.connect(_show_help)
	row.add_child(help)
	
	var quit := Button.new()
	quit.text = "Quit"
	quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(get_tree().quit)
	quit.visible = not OS.has_feature("web")
	row.add_child(quit)
	
	var disclaimer := Label.new()
	disclaimer.text = "not affiliated or endorsed by any real person or office."
	disclaimer.modulate = Color(1, 1, 1, 0.6)
	disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(disclaimer)
	_add_star()
	
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

TARGETING
A target card hits the borough you selected fully. The other boroughs only get a share of the effect. Citywide cards hit every borough fully.

POLICIES
Ongoing policies keep helping each turn, but they charge upkeep. If you can't pay it, the policy lapses and approval drops.

TIPS
Fix the weakest borough first, since losing happens on the citywide average. Don't spend all your budget in one turn, because upkeep is due every turn."""

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

const LOGO_WIDTH := 560.0

var sim_rect: TextureRect
var mam_rect: TextureRect

func _logo_piece(path: String) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load(path)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	var tex_size: Vector2 = r.texture.get_size()
	r.size = Vector2(LOGO_WIDTH, LOGO_WIDTH * tex_size.y / tex_size.x)
	return r

func _build_logo() -> Control:
	sim_rect = _logo_piece("res://art/logo1-simulator.png")
	mam_rect = _logo_piece("res://art/logo2-mamdani.png")
	var overlap := mam_rect.size.y * 0.2
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(LOGO_WIDTH, mam_rect.size.y + sim_rect.size.y - overlap)
	mam_rect.position = Vector2(0, 0)
	sim_rect.position = Vector2(0, mam_rect.size.y - overlap)
	holder.add_child(sim_rect)
	holder.add_child(mam_rect)
	return holder

func _animate_logo(_holder: Control) -> void:
	var sim_home := sim_rect.position
	var mam_home := mam_rect.position
	sim_rect.position.x = get_viewport_rect().size.x + 200.0
	mam_rect.position.y = mam_home.y - 80.0
	mam_rect.modulate.a = 0.0
	
	var t := create_tween()
	t.tween_property(sim_rect, "position:x", sim_home.x, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(mam_rect, "modulate:a", 1.0, 0.3)
	t.parallel().tween_property(mam_rect, "position:y", mam_home.y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
func _float_mamdani(home_y: float) -> void:
	var f := create_tween().set_loops()
	f.tween_property(mam_rect, "position:y", home_y - 10.0, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	f.tween_property(mam_rect, "position:y", home_y, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _add_star() -> void:
	var star := TextureRect.new()
	star.texture = load("res://art/super-cool-game.png")
	star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.size = Vector2(160, 160)
	star.pivot_offset = star.size / 2.0
	add_child(star)
	star.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE, 24)
	star.rotation_degrees = -8.0
	var r := create_tween().set_loops()
	r.tween_property(star, "rotation_degrees", 8.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	r.tween_property(star, "rotation_degrees", -8.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

const DIFFICULTIES := [
	["Easy", "easy", "3 actions a turn, more income, fewer issues."],
	["Normal", "normal", "The intended challenge."],
	["Hard", "hard", "Tight budget, more issues, harsher drift."],
]

var diff_overlay: Control

func _show_difficulty() -> void:
	if diff_overlay != null:
		return
	diff_overlay = Control.new()
	diff_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(diff_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	diff_overlay.add_child(dim)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	diff_overlay.add_child(center)
	
	var panel := PanelContainer.new()
	center.add_child(panel)
	
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	
	var heading := Label.new()
	heading.text = "Choose a difficulty"
	heading.add_theme_font_size_override("font_size", 28)
	v.add_child(heading)
	
	for d in DIFFICULTIES:
		var b := Button.new()
		b.text = d[0] + "\n" + d[2] + _best_text(d[1])
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(460, 90)
		b.pressed.connect(_start.bind(d[1]))
		v.add_child(b)
	
	_add_mod_toggles(v); var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_close_difficulty)
	v.add_child(back)

func _close_difficulty() -> void:
	diff_overlay.queue_free()
	diff_overlay = null

func _continue() -> void:
	var save := ConfigFile.new()
	if save.load("user://run.cfg") != OK:
		return
	var data = save.get_value("run", "data", {})
	GameState.pending_load = true
	GameState.modifiers = data.get("modifiers", [])
	_start(str(data.get("difficulty", "normal")))

func _best_text(key: String) -> String:
	var save := ConfigFile.new()
	if save.load("user://best.cfg") != OK:
		return ""
	var best: int =save.get_value("best", key, -1)
	return "" if best < 0 else "\nBest approval: %d" % best


var ach_overlay: Control

func _show_achievements() -> void:
	if ach_overlay != null:
		return
	ach_overlay = Control.new()
	ach_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ach_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ach_overlay.add_child(dim)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ach_overlay.add_child(center)
	
	var panel := PanelContainer.new()
	center.add_child(panel)
	
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" +side, 24)
	panel.add_child(margin)
	
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	
	var heading := Label.new()
	heading.add_theme_font_size_override("font_size", 28)
	v.add_child(heading)
	
	var count := 0
	for a in GameState.ACHIEVEMENTS:
		var got: bool = GameState.is_unlocked(a[0])
		if got:
			count += 1
		var item := Label.new()
		item.text = "%s %s\n%s" % ["[x]" if got else "[ ]", a[1], a[2]]
		item.custom_minimum_size = Vector2(440, 0)
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.modulate = Color(1, 1, 1, 1.0 if got else 0.5)
		v.add_child(item)
	heading.text = "Achievements (%d / %d)" % [count, GameState.ACHIEVEMENTS.size()]

	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(_close_achievements)
	v.add_child(close)

func _close_achievements() -> void:
	ach_overlay.queue_free()
	ach_overlay = null

func _add_mod_toggles(parent: Node) -> void:
	var open := 0
	for m in GameState.MODIFIERS:
		if GameState.mod_unlocked(m[0]):
			open += 1
	
	var head := Label.new()
	head.text = "Challenge modifiers (%d / %d unlocked)" % [open, GameState.MODIFIERS.size()]
	head.add_theme_font_size_override("font_size", 16)
	parent.add_child(head)
	
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(490, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	
	for m in GameState.MODIFIERS:
		var b := Button.new()
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(460, 56)
		if GameState.mod_unlocked(m[0]):
			b.button_pressed = GameState.modifiers.has(m[0])
			_style_mod_button(b, m, b.button_pressed)
			b.toggled.connect(_on_mod_toggled.bind(m[0], b, m))
		else:
			GameState.modifiers.erase(m[0])
			b.disabled = true
			b.custom_minimum_size.y = 72
			b.text = "[locked] %s\nUnlock: %s" % [m[1], GameState.achievement_text(GameState.MOD_UNLOCKS[m[0]])]
		list.add_child(b)


func _style_mod_button(b: Button, m: Array, on: bool) -> void:
	b.text = "%s %s \n%s" % ["[x]" if on else "[ ]", m[1], m[2]]
	b.modulate = Color(0.65, 1.0, 0.65) if on else Color.WHITE


func _on_mod_toggled(on: bool, id: String, b: Button, m: Array) -> void:
	if on and not GameState.modifiers.has(id):
		GameState.modifiers.append(id)
	elif not on:
		GameState.modifiers.erase(id)
	_style_mod_button(b, m, on)
