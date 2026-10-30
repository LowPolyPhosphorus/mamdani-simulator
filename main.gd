extends Control

const HAND_SIZE := 5
const LOW_THRESHOLD := 30
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
var issues_box: VBoxContainer
var log_label: Label
var hand_box: HBoxContainer
var event_dialog: ConfirmationDialog
var result_dialog: AcceptDialog
var tip_panel: PanelContainer
var tip_label: Label
var event_overlay: Control
var borough_map: Control
var summary_overlay: Control
var cards_enacted := 0

var city_bars := {}
var city_labels := {}
var attitude_bars := {}
var attitude_labels := {}
var lobby_buttons := {}
var borough_buttons := {}
var log_lines: Array[String] = []
var current_event: GameEvent
var game_ended := false
var auto_target := false


func _ready() -> void:
	for child in get_children():
		child.queue_free()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build()
	_build_layout()
	_build_dialogs()
	end_turn_button.pressed.connect(GameState.end_turn)
	GameState.turn_changed.connect(_apply_auto_target)
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
	_show_intro()


# -UI-

func _build_layout() -> void:
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

	var needy_button := Button.new()
	needy_button.text = "Auto-target neediest"
	needy_button.toggle_mode = true
	needy_button.custom_minimum_size = Vector2(190, 40)
	needy_button.toggled.connect(_on_auto_target_toggled)
	row.add_child(needy_button)
	
	end_turn_button = Button.new()
	end_turn_button.text = "End Turn"
	end_turn_button.custom_minimum_size = Vector2(140, 40)
	row.add_child(end_turn_button)
	return panel


func _build_left_panel() -> Control:
	var box := _make_panel("Citywide", 290)
	for meter in METERS:
		_add_city_row(box, meter)
	box.add_child(_label("GATEKEEPERS", 12, UITheme.MUTED))
	for body in GameState.GATEKEEPERS:
		_add_attitude_row(box, body)
	box.add_child(_label("ACTIVE POLICIES", 12, UITheme.MUTED))
	policies_box = VBoxContainer.new()
	policies_box.add_theme_constant_override("separation", 6)
	box.add_child(_scroll_wrap(policies_box))
	return box.get_parent()

func _on_auto_target_toggled(pressed: bool) -> void:
	auto_target = pressed
	if pressed:
		_target_neediest()

func _target_neediest() -> void:
	GameState.target_borough = GameState.neediest_borough()
	_update_boroughs()

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

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_N:
		_target_neediest()

func _add_attitude_row(parent: Node, body: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var name_label := _label(body, 15)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value_label := _label("", 15)
	head.add_child(name_label)
	head.add_child(value_label)
	var lobby_button := Button.new()
	lobby_button.text = "Lobby"
	lobby_button.tooltip_text = "Costs 1 action and %d budget. Raises their attitude by %d." % [GameState.LOBBY_COST, GameState.LOBBY_GAIN]
	lobby_button.pressed.connect(func(): GameState.lobby(body))
	head.add_child(lobby_button)
	lobby_buttons[body] = lobby_button
	row.add_child(head)
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	row.add_child(bar)
	parent.add_child(row)
	attitude_bars[body] = bar
	attitude_labels[body] = value_label


func _update_attitudes() -> void:
	for body in GameState.GATEKEEPERS:
		var value: int = GameState.attitudes[body]
		attitude_bars[body].value = value
		attitude_labels[body].text = str(value)
		lobby_buttons[body].disabled = not GameState.can_lobby()


func _build_map_panel() -> Control:
	var box := _make_panel("Boroughs (click one to target it)")
	box.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	borough_map = load("res://borough_map.gd").new()
	borough_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	borough_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(borough_map)
	borough_map.clip_contents = true
	box.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	borough_map.picked.connect(_on_map_picked)
	var hint := _label("Targeted cards hit the selected borough fully. The others get %d%%." % roundi(GameState.cfg["spillover"] * 100), 12, UITheme.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	return box.get_parent()


func _wrapped(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _build_right_panel() -> Control:
	var box := _make_panel("Demands", 330)
	demands_box = VBoxContainer.new()
	demands_box.add_theme_constant_override("separation", 8)
	box.add_child(_scroll_wrap(demands_box))
	box.add_child(_label("BOROUGH ISSUES", 12, UITheme.MUTED))
	issues_box = VBoxContainer.new()
	issues_box.add_theme_constant_override("separation", 6)
	box.add_child(_scroll_wrap(issues_box))
	box.add_child(_label("LOG", 12, UITheme.MUTED))
	log_label = _label("", 13, UITheme.MUTED)
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_add_log_scroll(box)
	return box.get_parent()


func _build_hand_panel() -> Control:
	var box := _make_panel("Your hand")
	hand_box = HBoxContainer.new()
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.add_theme_constant_override("separation", 10)
	box.add_child(hand_box); box.get_parent().custom_minimum_size.y = 340
	return box.get_parent()


func _build_dialogs() -> void:
	event_dialog = ConfirmationDialog.new()
	event_dialog.borderless = true
	event_dialog.dialog_close_on_escape = false
	event_dialog.confirmed.connect(_on_event_choice.bind(true))
	event_dialog.canceled.connect(_on_event_choice.bind(false))
	add_child(event_dialog)
	result_dialog = AcceptDialog.new()
	result_dialog.confirmed.connect(_restart)
	result_dialog.canceled.connect(_restart)
	add_child(result_dialog)
	tip_panel = PanelContainer.new()
	tip_panel.theme_type_variation = "CardPanel"
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	tip_panel.z_index = 100
	tip_label = Label.new()
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(300, 0)
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_child(tip_label)
	add_child(tip_panel)


# -UI updates-

func _update_ui() -> void:
	turn_label.text = "TURN %d / %d" % [mini(GameState.turn, GameState.MAX_TURNS), GameState.MAX_TURNS]
	budget_label.text = "Budget %d" % GameState.budget
	var net: int = GameState.cfg["income"] - _total_upkeep()
	net_label.text = "Net %s / turn" % _signed_num(net)
	net_label.add_theme_color_override("font_color", UITheme.GOOD if net >= 0 else UITheme.BAD)
	actions_label.text = "Actions %d / %d" % [GameState.actions_left, GameState.cfg["actions"]]
	_update_city()
	_update_attitudes()
	_update_boroughs()
	_update_policies()
	_update_demands()
	_update_issues()
	if GameState.is_game_over() and not game_ended:
		game_ended = true
		end_turn_button.disabled = true
		_show_summary()


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


func _update_policies() -> void:
	_clear(policies_box)
	if GameState.active_policies.is_empty():
		_add_wrapped(policies_box, _label("None yet. Ongoing cards you enact show up here.", 13, UITheme.MUTED))
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
		_add_wrapped(policies_box, label)


func _update_demands() -> void:
	_clear(demands_box)
	if GameState.active_demands.is_empty():
		_add_wrapped(demands_box,_label("No demands right now.", 13, UITheme.MUTED))
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
		_add_wrapped(demands_box,label)


func _update_issues() -> void:
	_clear(issues_box)
	if GameState.active_issues.is_empty():
		_add_wrapped(issues_box, _label("No issues right now.", 13, UITheme.MUTED))
		return
	for entry in GameState.active_issues:
		var urgent: bool = entry["age"] >= GameState.ISSUE_ESCALATE_TURNS - 1
		var label := _label("%s | %s\n%s -%d/turn (%d turns old)" % [
			entry["borough"], entry["name"], entry["meter"].capitalize(), GameState.ISSUE_DRAIN, entry["age"]
		], 14, UITheme.BAD if urgent else UITheme.TEXT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_add_wrapped(issues_box, label)


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _scroll_wrap(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


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
	if card.synergy_with != "":
		lines.append("Synergy: %s (+%d approval)" % [card.synergy_with, card.synergy_bonus])
	if lines.is_empty():
		return "[color=#8b95ad]No direct effect[/color]"
	return "\n".join(lines)


func _add_card(card: PolicyCard) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(225, 280)
	panel.tooltip_text = card.description
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_set_tooltip_deep(panel, _card_tooltip(card))

	var title := _label(card.card_name, 16, UITheme.ACCENT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; title.custom_minimum_size.y = 44
	box.add_child(title)

	var cost_text := "Cost %d" % card.cost
	if card.ongoing:
		cost_text += "  |  Ongoing"
	box.add_child(_label(cost_text, 14))

	var tag := _label("", 12, UITheme.MUTED)
	box.add_child(tag)

	var gate := _label("", 12, UITheme.MUTED)
	gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; gate.custom_minimum_size.y = 32
	box.add_child(gate)

	var fx := RichTextLabel.new()
	fx.bbcode_enabled = true
	fx.fit_content = false; fx.custom_minimum_size = Vector2(0, 80); fx.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	panel.set_meta("gate", gate)
	hand_box.add_child(panel)


func _refresh_hand() -> void:
	for panel in hand_box.get_children():
		var card: PolicyCard = panel.get_meta("card")
		var tag: Label = panel.get_meta("tag")
		var button: Button = panel.get_meta("button")
		var gate: Label = panel.get_meta("gate")
		if card.gatekeeper == "None":
			gate.text = " "
		else:
			gate.visible = true
			var mood: int = GameState.attitudes[card.gatekeeper]
			var status := GameState.gate_status(card)
			var note := "ready"
			var col := UITheme.GOOD
			if status == "weak":
				note = "half effect"
				col = UITheme.MID_FILL
			elif status == "blocked":
				note = "will be blocked"
				col = UITheme.BAD
			gate.text = "Needs %s %d+ (now %d): %s" % [card.gatekeeper, card.gate_threshold, mood, note]
			gate.add_theme_color_override("font_color", col)
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
		cards_enacted += 1
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
	_show_event_popup()


func _on_event_choice(chose_a: bool) -> void:
	var where := "" if current_event.borough == "Any" else current_event.borough
	GameState.apply_choice(current_event.choice_a if chose_a else current_event.choice_b, where)


func _restart() -> void:
	GameState.reset()
	get_tree().reload_current_scene()

func _apply_auto_target() -> void:
	if auto_target:
		GameState.target_borough = GameState.neediest_borough()
		_update_boroughs()

func _show_intro() -> void:
	if GameState.intro_shown:
		return
	GameState.intro_shown = true
	var d := AcceptDialog.new()
	d.title = "Your first turn"
	d.dialog_text = "1. Click a borough on the map to target it. The tags show where trouble is. \n2. Play cards from your hand at the bottom. Each costs budget and one action. \n3. Click End Turn when you're done. \n\nTip: switch on Auto-target neediest in the top bar to have the game pick the weakest borough for you."
	d.ok_button_text = "Let's go"
	add_child(d)
	d.popup_centered(Vector2i(520, 0))

func _card_tooltip(card: PolicyCard) -> String:
	var lines: Array[String] = []
	if card.citywide:
		lines.append("Citywide: hits every borough at full strength.")
	else:
		lines.append("Targeted: hits the selected borough fully. The other boroughs get a smaller share.")
	if card.ongoing:
		lines.append("Ongoing: keeps helping every turn after you play it.")
		if card.upkeep > 0:
			lines.append("Brings in %d budget every turn." % -card.upkeep)
	else:
		lines.append("One-time: the effect happens once, right away.")
	if card.gatekeeper != "None":
		lines.append("Needs approval from %s. If their mood is too low, the card is blocked or only half as effective." % card.gatekeeper)
	return "\n".join(lines)

func _set_tooltip_deep(node: Node, text: String) -> void:
	if node is Control:
		node.tooltip_text = text
	for child in node.get_children():
		_set_tooltip_deep(child, text)

func _process(_delta: float) -> void:
	if tip_panel == null:
		return
	if event_overlay != null or summary_overlay != null:
		tip_panel.visible = false
		return
	var mouse := get_global_mouse_position()
	var text := ""
	for panel in hand_box.get_children():
		if panel is Control and panel.get_global_rect().has_point(mouse):
			text = panel.get_meta("tip", "")
			break
	if text == "" and borough_map != null and borough_map.hover != "":
		text = _borough_info(borough_map.hover)
	if text == "":
		tip_panel.visible = false
		return
	tip_label.text = text
	tip_panel.visible = true
	tip_panel.reset_size()
	var pos := mouse + Vector2(16, 16)
	var limit := get_viewport_rect().size - tip_panel.size
	pos.x = minf(pos.x, limit.x)
	pos.y = minf(pos.y, limit.y)
	tip_panel.global_position = pos

func _choice_preview(c: EventChoice) -> String:
	var names := {
		"budget_change": "Budget",
		"affordability_change": "Afford",
		"ridership_change": "Ride",
		"approval_change": "Approval",
	}
	var parts: Array[String] = []
	for key in names:
		var v = c.get(key)
		if v != null and int(v) != 0:
			parts.append("%s %+d" % [names[key], int(v)])
	return ", ".join(parts)

func _show_event_popup() -> void:
	if event_overlay != null:
		return
	event_overlay = Control.new()
	event_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(event_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.08, 0.05, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	event_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	event_overlay.add_child(center)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.92)
	box.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var heading := Label.new()
	heading.text = current_event.title if current_event.borough == "Any" else "%s: %s" % [current_event.borough, current_event.title]
	heading.theme_type_variation = "HeaderLabel"
	heading.add_theme_font_size_override("font_size", 26)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.custom_minimum_size = Vector2(460, 0)
	v.add_child(heading)

	var body := Label.new()
	body.text = current_event.description
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(460, 0)
	v.add_child(body)

	var choices := [current_event.choice_a, current_event.choice_b]
	for i in choices.size():
		var c: EventChoice = choices[i]
		var b := Button.new()
		b.text = c.choice_text + "\n" + _choice_preview(c)
		b.custom_minimum_size = Vector2(460, 64)
		b.pressed.connect(_pick_event.bind(i == 0))
		v.add_child(b)

func _pick_event(chose_a: bool) -> void:
	if event_overlay != null:
		event_overlay.queue_free()
		event_overlay = null
	_on_event_choice(chose_a)

func _on_map_picked(b: String) -> void:
	_on_borough_pressed(b)

func _update_boroughs() -> void:
	var approvals := {}
	for b in GameState.BOROUGHS:
		approvals[b] = GameState.get_value("approval", b)
	borough_map.update_state(approvals, GameState.target_borough)

func _borough_info(b: String) -> String:
	var aff: int = GameState.get_value("affordability", b)
	var rid: int = GameState.get_value("ridership", b)
	var app: int = GameState.get_value("approval", b)
	var lines: Array[String] = [b.to_upper(), "Affordability %d" % aff, "Ridership %d" % rid, "Approval %d" % app]
	var low: Array[String] = []
	if aff < LOW_THRESHOLD:
		low.append("Afford")
	if rid < LOW_THRESHOLD:
		low.append("Ride")
	if app < LOW_THRESHOLD:
		low.append("Approval")
	if not low.is_empty():
		lines.append("LOW: " + ", ".join(low))
	var n := 0
	for entry in GameState.active_demands:
		if entry["borough"] == b:
			n += 1
	if n > 0:
		lines.append("! %d demand%s" % [n, "" if n== 1 else "s"])
	for issue in GameState.active_issues:
		if issue["borough"] == b:
			lines.append("Issue: " + str(issue["name"]))
	return "\n".join(lines)

func _show_summary() -> void:
	if summary_overlay != null:
		return
	summary_overlay = Control.new()
	summary_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(summary_overlay)
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary_overlay.add_child(dim)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	summary_overlay.add_child(center)
	
	var panel := PanelContainer.new()
	center.add_child(panel)
	
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	
	v.add_child(_label("Term over", 30, UITheme.ACCENT))
	
	var ending := _label(GameState.get_ending(), 15)
	ending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ending.custom_minimum_size = Vector2(560, 0)
	ending.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	v.add_child(ending)
	
	v.add_child(HSeparator.new())
	
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	v.add_child(cols)
	
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_maximum_size = Vector2(260, 0)
	cols.add_child(left)
	
	left.add_child(_label("CITYWIDE", 12, UITheme.MUTED))
	for meter in METERS:
		var value := GameState.get_value(meter)
		_summary_row(left, meter.capitalize(), str(value), _score_color(value))
	
	left.add_child(_label("RUN", 12, UITheme.MUTED))
	_summary_row(left, "Turns served", "%d / %d" % [mini(GameState.turn, GameState.MAX_TURNS), GameState.MAX_TURNS])
	_summary_row(left, "Cards enacted", str(cards_enacted))
	
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(260, 0)
	cols.add_child(right)
	
	right.add_child(_label("BOROUGH APPROVAL", 12, UITheme.MUTED))
	for b in GameState.BOROUGHS:
		var approval: int = GameState.get_value("approval", b)
		_summary_row(right, b, str(approval), _score_color(approval))
	
	right.add_child(_label("GATEKEEPERS", 12, UITheme.MUTED))
	for body in GameState.GATEKEEPERS:
		var mood: int = GameState.attitudes[body]
		_summary_row(right, body, str(mood), _score_color(mood))
	
	v.add_child(HSeparator.new())
	
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	v.add_child(buttons)
	
	var again := Button.new()
	again.text = "Play again"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.custom_minimum_size = Vector2(0, 48)
	again.pressed.connect(_restart)
	buttons.add_child(again)

	var menu := Button.new()
	again.text = "Main menu"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	again.custom_minimum_size = Vector2(0, 48)
	again.pressed.connect(_restart)
	buttons.add_child(menu)


func _summary_row(parent: Node, name: String, value: String, col: Color = UITheme.TEXT) -> void:
	var row := HBoxContainer.new()
	var n := _label(name, 15)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(n)
	row.add_child(_label(value, 15, col))
	parent.add_child(row)


func _score_color(value: int) -> Color:
	if value < LOW_THRESHOLD:
		return UITheme.BAD
	if value >= 60:
		return UITheme.GOOD
	return UITheme.TEXT


func _to_title() -> void:
	GameState.reset()
	get_tree().change_scene_to_file("res://title.tscn")


func _add_wrapped(parent: Node, label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)

func _add_log_scroll(parent: Node) -> void:
	var log_scroll := _scroll_wrap(log_label)
	log_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	log_scroll.custom_minimum_size = Vector2(0, 110)
	parent.add_child(log_scroll)
