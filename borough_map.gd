extends Control

signal picked(borough: String)
signal hovered(borough: String)

const SHEET_PATH := "res://art/boroughs.png"
const CELL := 700
const SHEET_ORDER := ["Brooklyn", "Manhattan", "Queens", "Staten Island", "Bronx"]
const LABEL_INDEX := 5
const DRAW_ORDER := ["Staten Island", "Bronx", "Manhattan", "Brooklyn", "Queens"]
const DIM := 0.55
const BRIGHT := 1.1
const HOVER_BOOST := 0.18
const SELECT_BOOST := 0.3
const SHADER_CODE := """
shader_type canvas_item;
uniform float brightness = 1.0;
void fragment() {
	COLOR.rgb *= brightness;
}
"""

var rects := {}
var masks := {}
var label_rect: TextureRect
var approvals := {}
var target := ""
var hover := ""
var _scale := 1.0
var _origin := Vector2.ZERO
var content := Rect2i(0, 0, CELL, CELL)

func _ready() -> void:
	custom_minimum_size = Vector2(420, 420)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet: Texture2D = load(SHEET_PATH)
	var sheet_img := sheet.get_image()
	var shader := Shader.new()
	shader.code = SHADER_CODE
	for b in DRAW_ORDER:
		var idx: int = SHEET_ORDER.find(b)
		var r := _make_layer(sheet, idx)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		r.material = mat
		add_child(r)
		rects[b] = r
		masks[b] = sheet_img.get_region(Rect2i(idx * CELL, 0, CELL, CELL))
	label_rect = _make_layer(sheet, LABEL_INDEX)
	add_child(label_rect)
	var used := Rect2i()
	var first := true
	var imgs: Array = masks.values()
	imgs.append(sheet_img.get_region(Rect2i(LABEL_INDEX * CELL, 0, CELL, CELL)))
	for img in imgs:
		var r: Rect2i = img.get_used_rect()
		if r.size == Vector2i.ZERO:
			continue
		used = r if first else used.merge(r)
		first = false
	if not first:
		content = used
	resized.connect(_layout)
	_layout()
	_refresh()

func _make_layer(sheet: Texture2D, idx: int) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = sheet
	at.region = Rect2(idx * CELL, 0, CELL, CELL)
	at.filter_clip = true
	var r := TextureRect.new()
	r.texture = at
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return r

func _layout() -> void:
	var c := Vector2(content.size)
	_scale = minf(size.x / c.x, size.y / c.y)
	_origin = (size - c * _scale) / 2.0 - Vector2(content.position) * _scale
	var side := CELL * _scale
	for r in rects.values() + [label_rect]:
		r.position = _origin
		r.size = Vector2(side, side)

func _borough_at(p: Vector2) -> String:
	if _scale <= 0.0:
		return ""
	var local := (p - _origin) / _scale
	var x := int(local.x)
	var y := int(local.y)
	if x < 0 or y < 0 or x >= CELL or y >= CELL:
		return ""
	# Check the top layer first so Queens wins over Brooklyn where they overlap.
	for i in range(DRAW_ORDER.size() - 1, -1, -1):
		var b: String = DRAW_ORDER[i]
		if masks[b].get_pixel(x, y).a > 0.3:
			return b
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var b := _borough_at(event.position)
		if b != hover:
			hover = b
			hovered.emit(b)
			_refresh()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := _borough_at(event.position)
		if c != "":
			picked.emit(c)

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and hover != "":
		hover = ""
		hovered.emit("")
		_refresh()

func update_state(new_approvals: Dictionary, new_target: String) -> void:
	approvals = new_approvals
	target = new_target
	_refresh()

func _refresh() -> void:
	for b in rects:
		var a: float = approvals.get(b, 50)
		var v := lerpf(DIM, BRIGHT, clampf(a / 100.0, 0.0, 1.0))
		if b == hover:
			v += HOVER_BOOST
		if b == target:
			v += SELECT_BOOST
		rects[b].material.set_shader_parameter("brightness", v)
