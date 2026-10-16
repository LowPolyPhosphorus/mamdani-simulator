class_name UITheme
extends RefCounted

# Grayscale Structural Palette
const BG := Color("#111111")
const PANEL := Color("#1C1C1C")
const CARD := Color("#2A2A2A")
const TEXT := Color("#EAEAEA")
const MUTED := Color("#777777")
const OUTLINE := Color("#080808")
const EDGE := Color("#3E3E3E")

const ACCENT := Color("#FFFFFF")
const TAXI := Color("#CCCCCC")
const SUBWAY_GREEN := Color("#AAAAAA")
const SUBWAY_BLUE := Color("#888888")

# Functional Status Colors
const GOOD := Color("#2ECC71")
const BAD := Color("#E74C3C")
const GOOD_FILL := Color("#27AE60")
const BAD_FILL := Color("#C0392B")
const MID_FILL := Color("#F39C12")
const FLASH_UP := Color("#2ECC71")
const FLASH_DOWN := Color("#E74C3C")

const METERS := { "budget": Color("#CCCCCC"), "affordability": Color("#AAAAAA"), "ridership": Color("#999999"), "approval": GOOD }
const FONTS := ["res://fonts/Fredoka.ttf", "res://fonts/Nunito.ttf"]

static func flat(bg: Color, border := Color.TRANSPARENT, bw := 0, r := 3, m := 10.0, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw); s.set_corner_radius_all(r); s.set_content_margin_all(m)
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.6); s.shadow_offset = Vector2(0, shadow); s.shadow_size = 2
	return s

static func heat(val: float) -> Color:
	var t := clampf(val / 100.0, 0.0, 1.0)
	return BAD_FILL.lerp(MID_FILL, t * 2.0) if t < 0.5 else MID_FILL.lerp(GOOD_FILL, (t - 0.5) * 2.0)

static func tile(fill: Color, sel: bool) -> StyleBoxFlat:
	return flat(fill, ACCENT if sel else OUTLINE, 3 if sel else 2, 2, 8.0, 3)

static func meter_color(m: String) -> Color:
	return METERS.get(m, TAXI)

static func make_background() -> TextureRect:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("#0D0D0D"), Color("#161616"), Color("#0A0A0A")])
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g; t.width = 32; t.height = 32; t.fill_to = Vector2(0, 1)
	
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Changed from scale to prevent aggressive edge-cropping on window resizes:
	r.stretch_mode = TextureRect.STRETCH_SCALE 
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r

static func _load_font() -> Font:
	for p in FONTS:
		if ResourceLoader.exists(p): return load(p) as Font
	return null

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 15

	var body := _load_font()
	var base: Font = body if body else ThemeDB.fallback_font
	if body: t.default_font = body
	
	var head := FontVariation.new()
	head.base_font = base; head.variation_embolden = 0.6
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", head)

	for type in ["Label", "RichTextLabel", "TooltipLabel"]:
		t.set_color("font_color" if type != "RichTextLabel" else "default_color", type, TEXT)

	# Panels
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, EDGE, 2, 4, 12.0, 2))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", flat(CARD, EDGE, 2, 2, 10.0, 2))

	# Button Factory Helper
	var apply_btn := func(type: String, bg: Color, fg: Color):
		t.set_stylebox("normal", type, flat(bg, OUTLINE, 2, 3, 10.0, 3))
		t.set_stylebox("hover", type, flat(bg.lightened(0.1), OUTLINE, 2, 3, 10.0, 3))
		t.set_stylebox("pressed", type, flat(bg.darkened(0.15), OUTLINE, 2, 3, 10.0, 0))
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			t.set_color(c, type, fg)

	apply_btn.call("Button", Color("#333333"), TEXT)
	t.set_stylebox("disabled", "Button", flat(Color("#1E1E1E"), EDGE, 2, 3, 10.0, 0))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_disabled_color", "Button", MUTED)

	t.set_type_variation("PrimaryButton", "Button")
	apply_btn.call("PrimaryButton", Color("#555555"), Color.WHITE)

	# Progress Bars & Dialogs
	t.set_stylebox("background", "ProgressBar", flat(Color("#111111"), EDGE, 1, 2, 0.0))
	t.set_stylebox("fill", "ProgressBar", flat(Color("#CCCCCC"), Color.TRANSPARENT, 0, 2, 0.0))
	t.set_stylebox("panel", "TooltipPanel", flat(PANEL, OUTLINE, 2, 2, 6.0))
	t.set_stylebox("panel", "AcceptDialog", flat(PANEL, OUTLINE, 2, 4, 12.0, 0))

	return t
