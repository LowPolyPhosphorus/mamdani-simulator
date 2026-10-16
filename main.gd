extends Control

const HAND_SIZE := 5
const EVENT_CHANCE := 0.5
const MAX_DEMANDS := 3
const DEMAND_CHANCE := 0.7
const METERS := ["budget", "affordability", "ridership", "approval"]
const MAP_LAYOUT := {
	"Manhattan": Rect2(150, 8, 120, 170),
	"Bronx": Rect2(285, 8, 175, 92),
	"Queens": Rect2(285, 108, 175, 118),
	"Brooklyn": Rect2(170, 238, 190, 96),
	"Staten Island": Rect2(10, 226, 145, 108),
}

@export var deck: Array[PolicyCard] = []
@export var events: Array[GameEvent] = []
@export var demand_pool: Array[Demand] = []

var turn_label: Label
var budget_label: Label
var net_label: Label
var actions_label: Label
var end_turn_button: Button
var policies_box: VBoxContainer
var demands_box: VBoxContainer
var log_label: Label
var hand_box: HBoxContainer
var event_dialog: ConfirmationDialog
var result_dialog: AcceptDialog

var city_bars := {}
var city_labels := {}
var borough_buttons := {}
var log_lines: Array[String] = []
var current_event: GameEvent
var game_ended := false


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build()
	_build_layout()
	_build_dialogs()
	end_turn_button.pressed.connect(GameState.end_turn)
	GameState.turn_changed.connect(_spawn_demand)
	GameState.turn_changed.connect(_update_ui)
	GameState.meters_changed.connect(_update_ui)
	GameState.turn_changed.connect(_draw_hand)
	GameState.turn_changed.connect(_maybe_trigger_event)
	GameState.meters_changed.connect(_refresh_hand)
	GameState.log_message.connect(_on_log_message)
	_spawn_demand()
	_spawn_demand()
	_update_ui()
	_draw_hand()


# -UI-

func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 12)
	margin.add_child(root_box)

	root_box.add_child(_build_top_bar())

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 12)
	root_box.add_child(middle)
	middle.add_child(_build_left_panel())
	middle.add_child(_build_map_panel())
	middle.add_child(_build_right_panel())

	root_box.add_child(_build_hand_panel())


func _make_panel(title: String, min_width: int = 0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = min_width
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	if title != "":
		box.add_child(_label(title.to_upper(), 12, UITheme.MUTED))
	return box


func _label(content: String, font_size: int = 15, col: Color = UITheme.TEXT) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", col)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _build_top_bar() -> Control:
	var panel := PanelContainer.new()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	panel.add_child(row)

	turn_label = _label("", 22, UITheme.ACCENT)
	budget_label = _label("", 18)
	net_label = _label("", 15)
	actions_label = _label("", 18)
	row.add_child(turn_label)
	row.add_child(budget_label)
	row.add_child(net_label)
	row.add_child(actions_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	end_turn_button = Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.custom_minimum_size = Vector2(140, 40)
	row.add_child(end_turn_button)
	return panel


func _build_left_panel() -> Control:
	var box := _make_panel("Citywide", 290)
	for meter in METERS:
		_add_city_row(box, meter)
	box.add_child(_label("ACTIVE POLICIES", 12, UITheme.MUTED))
	policies_box = VBoxContainer.new()
	policies_box.add_theme_constant_override("separation", 6)
	box.add_child(policies_box)
	return box.get_parent()


func _add_city_row(parent: Node, meter: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var name_label := _label(meter.capitalize(), 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := _label("", 15)
	head.add_child(name_label)
	head.add_child(value_label)
	row.add_child(head)
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = GameState.get_value(meter)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	row.add_child(bar)
	parent.add_child(row)
	city_bars[meter] = bar
	city_labels[meter] = value_label


func _build_map_panel() -> Control:
	var box := _make_panel("Boroughs (click one to target it)")
	box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(center)
	var map := Control.new()
	map.custom_minimum_size = Vector2(470, 340)
	center.add_child(map)
	for b in GameState.BOROUGHS:
		var rect: Rect2 = MAP_LAYOUT[b]
		var button := Button.new()
		button.position = rect.position
		button.size = rect.size
		button.clip_text = true
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_on_borough_pressed.bind(b))
		map.add_child(button)
		borough_buttons[b] = button
	var hint := _label("Targeted cards hit the selected borough fully. The others get %d%%." % roundi(GameState.SPILLOVER * 100), 12, UITheme.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	return box.get_parent()


func _build_right_panel() -> Control:
	var box := _make_panel("Demands", 330)
	demands_box = VBoxContainer.new()
	demands_box.add_theme_constant_override("separation", 8)
	box.add_child(demands_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	box.add_child(_label("LOG", 12, UITheme.MUTED))
	log_label = _label("", 13, UITheme.MUTED)
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(log_label)
	return box.get_parent()


func _build_hand_panel() -> Control:
	var box := _make_panel("Your hand")
	hand_box = HBoxContainer.new()
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.add_theme_constant_override("separation", 10)
	box.add_child(hand_box)
	return box.get_parent()


func _build_dialogs() -> void:
	event_dialog = ConfirmationDialog.new()
	event_dialog.confirmed.connect(_on_event_choice.bind(true))
	event_dialog.canceled.connect(_on_event_choice.bind(false))
	add_child(event_dialog)
	result_dialog = AcceptDialog.new()
	result_dialog.confirmed.connect(_restart)
	result_dialog.canceled.connect(_restart)
	add_child(result_dialog)


# -UI updates-

func _update_ui() -> void:
	turn_label.text = "TURN %d / %d" % [mini(GameState.turn, GameState.MAX_TURNS), GameState.MAX_TURNS]
	budget_label.text = "Budget %d" % GameState.budget
	var net := GameState.BASE_INCOME - _total_upkeep()
	net_label.text = "Net %s / turn" % _signed_num(net)
	net_label.add_theme_color_override("font_color", UITheme.GOOD if net >= 0 else UITheme.BAD)
	actions_label.text = "Actions %d / %d" % [GameState.actions_left, GameState.ACTIONS_PER_TURN]
	_update_city()
	_update_boroughs()
	_update_policies()
	_update_demands()
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


func _update_city() -> void:
	for meter in METERS:
		var value := GameState.get_value(meter)
		city_labels[meter].text = str(value)
		_tween_bar(city_bars[meter], value)


func _update_boroughs() -> void:
	var demand_counts := {}
	for entry in GameState.active_demands:
		var key: String = entry["borough"]
		demand_counts[key] = demand_counts.get(key, 0) + 1
	for b in GameState.BOROUGHS:
		var button: Button = borough_buttons[b]
		var approval := GameState.get_value("approval", b)
		var label_text := "%s\nAfford %d  Ride %d\nApproval %d" % [
			b, GameState.get_value("affordability", b), GameState.get_value("ridership", b), approval
		]
		var n: int = demand_counts.get(b, 0)
		if n > 0:
			label_text += "\n! %d demand%s" % [n, "" if n == 1 else "s"]
		button.text = label_text
		var base := UITheme.heat(approval)
		var selected: bool = b == GameState.target_borough
		var border := UITheme.ACCENT if selected else Color(0, 0, 0, 0)
		var width := 4 if selected else 0
		for state in ["normal", "hover", "pressed", "disabled"]:
			var fill := base.lightened(0.12) if state == "hover" else base
			button.add_theme_stylebox_override(state, UITheme.flat(fill, border, width, 10))


func _update_policies() -> void:
	_clear(policies_box)
	if GameState.active_policies.is_empty():
		policies_box.add_child(_label("None yet. Ongoing cards you enact show up here.", 13, UITheme.MUTED))
		return
	for entry in GameState.active_policies:
		var card: PolicyCard = entry["card"]
		var where: String = "Citywide" if entry["borough"] == "" else entry["borough"]
		var money := ""
		if card.upkeep >= 0:
			money = "upkeep %d" % card.upkeep
		else:
			money = "income +%d" % -card.upkeep
		var label := _label("%s\n%s | %s" % [card.card_name, where, money], 14)
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		policies_box.add_child(label)


func _update_demands() -> void:
	_clear(demands_box)
	if GameState.active_demands.is_empty():
		demands_box.add_child(_label("No demands right now.", 13, UITheme.MUTED))
		return
	for entry in GameState.active_demands:
		var d: Demand = entry["demand"]
		var borough: String = entry["borough"]
		var now := GameState.get_value(d.meter, borough)
		var where := "citywide" if borough == "" else borough
		var urgent: bool = entry["turns_left"] <= 1
		var label := _label("%s | %s\n%s %d -> %d+   (%d turns left)" % [
			d.group_name, where, d.meter.capitalize(), now, d.threshold, entry["turns_left"]
		], 14, UITheme.BAD if urgent else UITheme.TEXT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		demands_box.add_child(label)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _signed_num(n: int) -> String:
	return ("+" if n > 0 else "") + str(n)


func _total_upkeep() -> int:
	var total := 0
	for entry in GameState.active_policies:
		var card: PolicyCard = entry["card"]
		total += card.upkeep
	return total


func _on_borough_pressed(borough: String) -> void:
	GameState.target_borough = borough
	_update_boroughs()
	_refresh_hand()


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

func _draw_hand() -> void:
	_clear(hand_box)
	var pool := deck.filter(func(c): return not (c.citywide and c.ongoing and GameState.is_active(c, "")))
	pool.shuffle()
	for card in pool.slice(0, HAND_SIZE):
		_add_card(card)
	_refresh_hand()


func _effect_parts(pairs: Array) -> String:
	var parts: Array[String] = []
	for pair in pairs:
		var value: int = pair[1]
		if value == 0:
			continue
		var col := "#6fdc8c" if value > 0 else "#ff6b6b"
		parts.append("[color=%s]%s %s[/color]" % [col, _signed_num(value), pair[0]])
	return ", ".join(parts)


func _effects_bbcode(card: PolicyCard) -> String:
	var lines: Array[String] = []
	var now := _effect_parts([
		["Budget", card.budget_change], ["Afford", card.affordability_change],
		["Ridership", card.ridership_change], ["Approval", card.approval_change],
	])
	if now != "":
		lines.append(now)
	if card.ongoing:
		var per := _effect_parts([
			["Afford", card.per_turn_affordability], ["Ridership", card.per_turn_ridership],
			["Approval", card.per_turn_approval], ["Budget", -card.upkeep],
		])
		lines.append("[color=#8b95ad]Each turn:[/color] " + per)
	if lines.is_empty():
		return "[color=#8b95ad]No direct effect[/color]"
	return "\n".join(lines)


func _add_card(card: PolicyCard) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(205, 0)
	panel.tooltip_text = card.description
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var title := _label(card.card_name, 16, UITheme.ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var cost_text := "Cost %d" % card.cost
	if card.ongoing:
		cost_text += "  |  Ongoing"
	box.add_child(_label(cost_text, 14))

	var tag := _label("", 12, UITheme.MUTED)
	box.add_child(tag)

	var fx := RichTextLabel.new()
	fx.bbcode_enabled = true
	fx.fit_content = true
	fx.scroll_active = false
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.text = _effects_bbcode(card)
	box.add_child(fx)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var button := Button.new()
	button.text = "Enact"
	button.pressed.connect(_on_card_pressed.bind(card, panel))
	box.add_child(button)

	panel.set_meta("card", card)
	panel.set_meta("tag", tag)
	panel.set_meta("button", button)
	hand_box.add_child(panel)


func _refresh_hand() -> void:
	for panel in hand_box.get_children():
		var card: PolicyCard = panel.get_meta("card")
		var tag: Label = panel.get_meta("tag")
		var button: Button = panel.get_meta("button")
		var played: bool = panel.get_meta("played", false)
		tag.text = "CITYWIDE" if card.citywide else "TARGET: " + GameState.target_borough.to_upper()
		button.disabled = played or not GameState.can_play(card, GameState.target_borough)
		if played:
			button.text = "Enacted"
		elif GameState.budget < card.cost:
			button.text = "Need %d budget" % card.cost
		else:
			button.text = "Enact"
		panel.modulate = Color(1, 1, 1, 0.55) if button.disabled else Color.WHITE


func _on_card_pressed(card: PolicyCard, panel: PanelContainer) -> void:
	if GameState.play_card(card, GameState.target_borough):
		panel.set_meta("played", true)
		_refresh_hand()


# -Log, events, restart-

func _on_log_message(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 6:
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
