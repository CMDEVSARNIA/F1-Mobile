extends Control
## Touch driving controls, modelled on what shipped mobile racers do
## (GRID Autosport, Real Racing, Codemasters' F1 mobile games):
##   steering  ARROWS - two big chevron buttons, left thumb
##             WHEEL  - drag anywhere in the left zone; analog, with a wheel
##                      graphic that appears under your thumb
##             TILT   - nothing on screen, the phone is the wheel
##   pedals    right thumb; with auto-throttle only a big brake pedal shows
## Every finger is tracked on its own, so steering and pedals work together.

enum Steer { ARROWS, WHEEL, TILT }

const ACCENT := Color(0.88, 0.02, 0.0)
const GAS_COLOR := Color(0.15, 0.85, 0.35)
const BRAKE_COLOR := Color(0.95, 0.18, 0.15)
const WHEEL_TRAVEL := 130.0  # px of drag for full lock (at 720p)

var steer_mode := Steer.ARROWS
var auto_throttle := true
var haptics := true

var _touches := {}  # finger index -> {zone, start, pos}
var _u := 1.0  # UI scale relative to 720p
var _steer := 0.0
var _wheel_center := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _size() -> Vector2:
	return get_viewport_rect().size if size == Vector2.ZERO else size


# ------------------------------------------------------------ layout

func _arrow_centers() -> Array[Vector2]:
	var s := _size()
	return [Vector2(120 * _u, s.y - 130 * _u), Vector2(310 * _u, s.y - 130 * _u)]


func _pedal_rects() -> Dictionary:
	var s := _size()
	var u := _u
	var out := {}
	if auto_throttle:
		out["brake"] = Rect2(s.x - 210 * u, s.y - 270 * u, 180 * u, 240 * u)
	else:
		out["throttle"] = Rect2(s.x - 160 * u, s.y - 290 * u, 130 * u, 260 * u)
		out["brake"] = Rect2(s.x - 330 * u, s.y - 230 * u, 150 * u, 200 * u)
	return out


## Generous hit areas: thumbs land roughly, never exactly.
func _zone_at(p: Vector2) -> String:
	var s := _size()
	if p.y < s.y * 0.38:
		return ""
	var pedals := _pedal_rects()
	if auto_throttle:
		if p.x > s.x * 0.62:
			return "brake"
	else:
		if p.x > pedals.throttle.position.x - 10 * _u:
			return "throttle"
		if p.x > s.x * 0.58:
			return "brake"
	match steer_mode:
		Steer.ARROWS:
			if p.x < 215 * _u:
				return "left"
			if p.x < 430 * _u:
				return "right"
		Steer.WHEEL:
			if p.x < s.x * 0.45:
				return "wheel"
	return ""


# ------------------------------------------------------------ input

func _input(event: InputEvent) -> void:
	if not visible:
		return
	_u = _size().y / 720.0
	if event is InputEventScreenTouch:
		if event.pressed:
			var z := _zone_at(event.position)
			_touches[event.index] = {"zone": z, "start": event.position, "pos": event.position}
			if z != "":
				_buzz(10)
			if z == "wheel":
				_wheel_center = event.position
		else:
			_touches.erase(event.index)
		_apply()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var t: Dictionary = _touches[event.index]
		t.pos = event.position
		# Arrows and pedals follow the finger; the wheel stays latched.
		if t.zone != "wheel":
			var z := _zone_at(event.position)
			if z != t.zone and z != "":
				_buzz(8)
			t.zone = z
		_apply()


func release_all() -> void:
	_touches.clear()
	_apply()


func _apply() -> void:
	var active := {}
	_steer = 0.0
	for idx in _touches:
		var t: Dictionary = _touches[idx]
		if t.zone == "wheel":
			_steer = clampf((t.pos.x - t.start.x) / (WHEEL_TRAVEL * _u), -1.0, 1.0)
		elif t.zone != "":
			active[t.zone] = true
	if active.has("left"):
		_steer -= 1.0
	if active.has("right"):
		_steer += 1.0
	_steer = clampf(_steer, -1.0, 1.0)
	_set_action("steer_left", maxf(-_steer, 0.0))
	_set_action("steer_right", maxf(_steer, 0.0))
	_set_action("brake", 1.0 if active.has("brake") else 0.0)
	_set_action("accelerate", 1.0 if active.has("throttle") else 0.0)
	queue_redraw()


func _set_action(action: String, strength: float) -> void:
	if strength > 0.01:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _buzz(ms: int) -> void:
	if haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


# ------------------------------------------------------------ drawing

func _draw() -> void:
	_u = _size().y / 720.0
	var active := {}
	var wheel_touch := false
	for idx in _touches:
		active[_touches[idx].zone] = true
		if _touches[idx].zone == "wheel":
			wheel_touch = true
	var font := get_theme_default_font()

	match steer_mode:
		Steer.ARROWS:
			var c := _arrow_centers()
			_draw_arrow(c[0], -1.0, active.has("left"))
			_draw_arrow(c[1], 1.0, active.has("right"))
		Steer.WHEEL:
			var s := _size()
			var center := _wheel_center if wheel_touch else Vector2(210 * _u, s.y - 190 * _u)
			_draw_wheel(center, wheel_touch)

	var pedals := _pedal_rects()
	for name: String in pedals:
		var col := GAS_COLOR if name == "throttle" else BRAKE_COLOR
		_draw_pedal(pedals[name], col, "GAS" if name == "throttle" else "BRAKE", active.has(name), font)


func _panel_box(fill: Color, border: Color, radius: float, width: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(int(width))
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	return sb


func _draw_arrow(c: Vector2, dir: float, on: bool) -> void:
	var r := (80.0 if not on else 74.0) * _u
	draw_circle(c, r, Color(0.04, 0.04, 0.07, 0.62 if on else 0.42))
	draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.9 if on else 0.4), 3.0 * _u, true)
	if on:
		draw_arc(c, r - 6 * _u, 0, TAU, 48, Color(ACCENT, 0.85), 5.0 * _u, true)
	# Chevron, drawn as a thick stroke
	var w := 18.0 * _u
	var h := 30.0 * _u
	var back := c + Vector2(-dir * w * 0.5, 0)
	var pts := PackedVector2Array([back + Vector2(0, -h), c + Vector2(dir * w, 0), back + Vector2(0, h)])
	draw_polyline(pts, Color(1, 1, 1, 1.0 if on else 0.85), 13.0 * _u, true)
	for p in pts:
		draw_circle(p, 6.5 * _u, Color(1, 1, 1, 1.0 if on else 0.85))


func _draw_wheel(c: Vector2, on: bool) -> void:
	var r := 105.0 * _u
	var a := alpha_for(on)
	var rot := _steer * deg_to_rad(110.0)
	# Grip ring
	draw_circle(c, r, Color(0.04, 0.04, 0.07, 0.25 * a))
	draw_arc(c, r, 0, TAU, 64, Color(0.08, 0.08, 0.1, 0.8 * a), 22.0 * _u, true)
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.35 * a), 2.0 * _u, true)
	# Spokes and hub
	for ang: float in [PI / 2.0, PI * 7.0 / 6.0, -PI / 6.0]:
		var d := Vector2.from_angle(ang + rot)
		draw_line(c + d * 22 * _u, c + d * (r - 8 * _u), Color(0.75, 0.75, 0.8, 0.8 * a), 10.0 * _u, true)
	draw_circle(c, 26 * _u, Color(0.1, 0.1, 0.12, 0.9 * a))
	draw_circle(c, 9 * _u, Color(ACCENT, a))
	# Top-dead-centre marker, like a real racing wheel
	var top := Vector2.from_angle(-PI / 2.0 + rot)
	draw_line(c + top * (r - 11 * _u), c + top * (r + 11 * _u), Color(ACCENT, a), 9.0 * _u, true)
	if not on:
		var font := get_theme_default_font()
		var txt := "DRAG TO STEER"
		var fs := int(16 * _u)
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-ts.x / 2.0, r + 36 * _u), txt, HORIZONTAL_ALIGNMENT_CENTER,
				-1, fs, Color(1, 1, 1, 0.55))


func alpha_for(on: bool) -> float:
	return 1.0 if on else 0.6


func _draw_pedal(r: Rect2, col: Color, label: String, on: bool, font: Font) -> void:
	# Pressed pedals sink a little, like a real pedal under your foot.
	if on:
		r = r.grow(-6 * _u)
	var fill := Color(col.darkened(0.55), 0.75 if on else 0.42)
	var border := Color(col, 0.95 if on else 0.6)
	_panel_box(fill, border, 18 * _u, 3 * _u).draw(get_canvas_item(), r)
	# Grip ribs
	var ribs := 6
	for i in ribs:
		var y := r.position.y + r.size.y * (0.18 + 0.1 * i)
		draw_line(Vector2(r.position.x + r.size.x * 0.2, y), Vector2(r.end.x - r.size.x * 0.2, y),
				Color(1, 1, 1, 0.35 if on else 0.18), 5.0 * _u, true)
	var fs := int(22 * _u)
	var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, Vector2(r.get_center().x - ts.x / 2.0, r.end.y - 18 * _u), label,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 1.0 if on else 0.8))
