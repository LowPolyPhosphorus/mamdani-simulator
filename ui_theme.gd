class_name UITheme
extends RefCounted

# Grayscale Structural Palette
const BG := Color("#111111")
const PANEL := Color("#1C1C1C")
const CARD := Color("#2A2A2A")
const TEXT := Color("#EAEAEA")
const MUTED := Color("#B8B8B8")
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
	return flat(fill, ACCENT if sel else Color.TRANSPARENT, 3 if sel else 0, 3, 8.0, 0)

static func meter_color(m: String) -> Color:
	return METERS.get(m, TAXI)

static func make_background() -> TextureRect:
	var r := TextureRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return r

static func build() -> Theme:
	return Theme.new()
