extends Control
## Top-down car outline: wings and corners coloured by damage
## (green fine, yellow damaged, red broken); a flat tyre blinks.

var front_wing := 0.0
var rear_wing := 0.0
var susp_l := 0.0
var susp_r := 0.0
var puncture := 0  # -1 left, 1 right
var puncture_front := true
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _col(d: float) -> Color:
	if d >= 1.0:
		return Color(0.95, 0.15, 0.1)
	if d >= 0.35:
		return Color(1.0, 0.73, 0.12)
	return Color(0.2, 0.9, 0.35) if d > 0.02 else Color(1, 1, 1, 0.55)


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 4.0
	draw_circle(c, r + 3.0, Color(0.03, 0.03, 0.05, 0.72))
	var u := r / 40.0  # drawing unit
	# Body
	draw_rect(Rect2(c + Vector2(-5, -24) * u, Vector2(10, 46) * u), Color(1, 1, 1, 0.35))
	# Wings
	draw_rect(Rect2(c + Vector2(-17, -31) * u, Vector2(34, 5) * u), _col(front_wing) if front_wing < 1.0 else Color(0.95, 0.15, 0.1, 0.35))
	draw_rect(Rect2(c + Vector2(-12, 24) * u, Vector2(24, 6) * u), _col(rear_wing) if rear_wing < 1.0 else Color(0.95, 0.15, 0.1, 0.35))
	# Wheels, coloured by that side's suspension; a puncture blinks red
	var blink := fmod(_t, 0.6) < 0.3
	for side: float in [-1.0, 1.0]:
		var d := susp_r if side > 0 else susp_l
		for front: bool in [true, false]:
			var col := _col(d)
			if puncture == int(side) and puncture_front == front:
				col = Color(0.95, 0.15, 0.1) if blink else Color(0.95, 0.15, 0.1, 0.25)
			var y := -20.0 if front else 10.0
			draw_rect(Rect2(c + Vector2(side * 13.0 - 3.5, y) * u, Vector2(7, 11) * u), col)
