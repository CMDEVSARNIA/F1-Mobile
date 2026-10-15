extends Control
## Compound letter in its colour, ringed by remaining tyre life.

var compound_short := "M"
var compound_color := Color(1.0, 0.82, 0.1)
var life := 1.0  # 1 = new, 0 = at the cliff
var enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 4.0
	draw_circle(c, r + 3.0, Color(0.03, 0.03, 0.05, 0.72))
	draw_arc(c, r - 4.0, 0, TAU, 40, Color(1, 1, 1, 0.12), 6.0, true)
	if enabled:
		var col := Color(0.2, 0.9, 0.35).lerp(Color(0.95, 0.15, 0.1), 1.0 - clampf(life, 0.0, 1.0))
		draw_arc(c, r - 4.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(life, 0.0, 1.0), 40, col, 6.0, true)
	draw_arc(c, r - 13.0, 0, TAU, 32, compound_color, 3.0, true)
	var font := get_theme_default_font()
	var fs := int(r * 0.9)
	var ts := font.get_string_size(compound_short, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	draw_string(font, c + Vector2(-ts.x / 2.0, ts.y * 0.32), compound_short, HORIZONTAL_ALIGNMENT_CENTER,
			-1, fs, compound_color)
