extends Control
## Bottom-centre driver display: F1 steering-wheel shift lights
## (green, red, blue), gear, speed, and throttle/brake bars.

const LEDS := 15
const LED_COLORS := [Color(0.15, 0.95, 0.3), Color(1.0, 0.15, 0.1), Color(0.25, 0.45, 1.0)]

var gear_text := "N"
var speed_kmh := 0
var rpm := 4000.0
var throttle := 0.0
var brake := 0.0
var _flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_flash += dt
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var u := size.y / 150.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.03, 0.05, 0.72)
	bg.set_corner_radius_all(int(22 * u))
	bg.border_color = Color(1, 1, 1, 0.12)
	bg.set_border_width_all(int(2 * u))
	bg.anti_aliasing = true
	bg.draw(get_canvas_item(), r)

	# Shift lights: fill from the outside in, all flash blue at the limiter.
	var t := clampf((rpm - 8000.0) / 3800.0, 0.0, 1.0)
	var lit := int(round(t * LEDS))
	var limiter := rpm > 11800.0 and fmod(_flash, 0.16) < 0.08
	var gap := (size.x - 40 * u) / LEDS
	for i in LEDS:
		var c := Vector2(20 * u + gap * (i + 0.5), 18 * u)
		var col: Color = LED_COLORS[mini(i / 5, 2)]
		var on := i < lit
		if limiter:
			col = LED_COLORS[2]
			on = true
		draw_circle(c, 6.5 * u, col if on else Color(col.darkened(0.8), 0.6))

	var font := get_theme_default_font()
	# Gear, big and central
	var gs := int(64 * u)
	var gsz := font.get_string_size(gear_text, HORIZONTAL_ALIGNMENT_CENTER, -1, gs)
	draw_string(font, Vector2(size.x / 2.0 - gsz.x / 2.0, 92 * u), gear_text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, gs, Color.WHITE)
	# Speed under it
	var sp := "%d" % speed_kmh
	var ss := int(30 * u)
	var ssz := font.get_string_size(sp, HORIZONTAL_ALIGNMENT_CENTER, -1, ss)
	draw_string(font, Vector2(size.x / 2.0 - ssz.x / 2.0, 128 * u), sp,
			HORIZONTAL_ALIGNMENT_CENTER, -1, ss, Color(1, 1, 1, 0.9))
	var unit := "KM/H"
	var us := int(13 * u)
	draw_string(font, Vector2(size.x / 2.0 + ssz.x / 2.0 + 6 * u, 128 * u), unit,
			HORIZONTAL_ALIGNMENT_LEFT, -1, us, Color(1, 1, 1, 0.55))

	# Pedal bars at the sides
	_bar(Rect2(18 * u, 38 * u, 12 * u, 96 * u), brake, Color(0.95, 0.2, 0.15))
	_bar(Rect2(size.x - 30 * u, 38 * u, 12 * u, 96 * u), throttle, Color(0.15, 0.9, 0.35))


func _bar(r: Rect2, v: float, col: Color) -> void:
	draw_rect(r, Color(1, 1, 1, 0.1))
	var h := r.size.y * clampf(v, 0.0, 1.0)
	draw_rect(Rect2(r.position.x, r.end.y - h, r.size.x, h), col)
