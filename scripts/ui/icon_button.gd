extends Control
## Round translucent HUD button with a drawn icon (no image assets).

signal pressed

enum Icon { PAUSE, CAMERA, RESET }

var icon := Icon.PAUSE
var _down := false


func _init(p_icon := Icon.PAUSE) -> void:
	icon = p_icon
	custom_minimum_size = Vector2(64, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
		elif _down:
			_down = false
			if Rect2(Vector2.ZERO, size).has_point(event.position):
				pressed.emit()
				if OS.has_feature("mobile"):
					Input.vibrate_handheld(10)
		queue_redraw()
		accept_event()


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	var u := r / 30.0
	draw_circle(c, r, Color(0.04, 0.04, 0.07, 0.75 if _down else 0.5))
	draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.45), 2.0, true)
	var w := Color(1, 1, 1, 0.95)
	match icon:
		Icon.PAUSE:
			draw_rect(Rect2(c + Vector2(-9, -11) * u, Vector2(6, 22) * u), w)
			draw_rect(Rect2(c + Vector2(3, -11) * u, Vector2(6, 22) * u), w)
		Icon.CAMERA:
			draw_rect(Rect2(c + Vector2(-14, -8) * u, Vector2(20, 16) * u), w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(6, -2) * u, c + Vector2(15, -8) * u,
					c + Vector2(15, 8) * u, c + Vector2(6, 2) * u]), w)
			draw_circle(c + Vector2(-4, 0) * u, 4.0 * u, Color(0.04, 0.04, 0.07))
		Icon.RESET:
			draw_arc(c, 11 * u, deg_to_rad(-60), deg_to_rad(230), 24, w, 4.0 * u, true)
			var tip := c + Vector2.from_angle(deg_to_rad(-60)) * 11 * u
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-7, -3) * u, tip + Vector2(5, -7) * u,
					tip + Vector2(3, 6) * u]), w)
