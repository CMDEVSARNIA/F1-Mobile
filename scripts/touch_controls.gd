extends Control
## Multi-touch driving zones. Each finger is tracked independently so you
## can steer and accelerate at the same time (Godot's Button can't).

var show_steering := true

var _touches := {}  # finger index -> zone name
var _zones := {}  # zone name -> Rect2
const ACTIONS := {
	"left": "steer_left", "right": "steer_right",
	"brake": "brake", "throttle": "accelerate",
}
const LABELS := {"left": "<", "right": ">", "brake": "BRAKE", "throttle": "GAS"}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Zones are recomputed from the current size so rotation/resizing and
## late layout never leave them stale.
func _layout() -> void:
	var s := get_viewport_rect().size if size == Vector2.ZERO else size
	var h := s.y * 0.42
	var y := s.y - h - 16.0
	var w := s.x * 0.16
	_zones.clear()
	if show_steering:
		_zones["left"] = Rect2(16, y, w, h)
		_zones["right"] = Rect2(32 + w, y, w, h)
	_zones["brake"] = Rect2(s.x - 2.0 * w - 32, y + h * 0.3, w, h * 0.7)
	_zones["throttle"] = Rect2(s.x - w - 16, y, w, h)


func _zone_at(p: Vector2) -> String:
	_layout()
	for z in _zones:
		if _zones[z].grow(12.0).has_point(p):
			return z
	return ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = _zone_at(event.position)
		else:
			_touches.erase(event.index)
		_apply()
	elif event is InputEventScreenDrag:
		_touches[event.index] = _zone_at(event.position)
		_apply()


func release_all() -> void:
	_touches.clear()
	_apply()


func _apply() -> void:
	var active := {}
	for idx in _touches:
		if _touches[idx] != "":
			active[_touches[idx]] = true
	for z in ACTIONS:
		if active.has(z):
			Input.action_press(ACTIONS[z])
		else:
			Input.action_release(ACTIONS[z])
	queue_redraw()


func _draw() -> void:
	_layout()
	var active := {}
	for idx in _touches:
		active[_touches[idx]] = true
	var font := get_theme_default_font()
	for z in _zones:
		var r: Rect2 = _zones[z]
		var col := Color(1, 1, 1, 0.28 if active.has(z) else 0.12)
		if z == "throttle":
			col = Color(0.2, 0.9, 0.3, 0.4 if active.has(z) else 0.18)
		elif z == "brake":
			col = Color(0.95, 0.2, 0.2, 0.4 if active.has(z) else 0.18)
		draw_rect(r, col)
		draw_rect(r, Color(1, 1, 1, 0.35), false, 2.0)
		var label: String = LABELS[z]
		var fs := 34 if label.length() == 1 else 22
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, r.get_center() + Vector2(-ts.x / 2.0, ts.y / 4.0), label,
				HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1, 1, 1, 0.8))
