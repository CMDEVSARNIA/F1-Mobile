extends Control
## Track map with car dots, north-up.

var track: Node
var cars: Array = []
var player: Node

var _raw := PackedVector2Array()


func setup(p_track: Node, p_cars: Array, p_player: Node) -> void:
	track = p_track
	cars = p_cars
	player = p_player
	_raw.clear()
	for i in range(0, track.points.size(), 3):
		var p: Vector3 = track.points[i]
		_raw.append(Vector2(p.x, p.z))
	_raw.append(_raw[0])


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if track == null:
		return
	var b: Rect2 = track.bounds
	var sc := minf(size.x / b.size.x, size.y / b.size.y) * 0.9
	var xf := Transform2D(0.0, Vector2(sc, sc), 0.0, size / 2.0 - b.get_center() * sc)
	var poly := xf * _raw
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	draw_polyline(poly, Color(0, 0, 0, 0.8), 6.0, true)
	draw_polyline(poly, Color(0.9, 0.9, 0.9), 3.0, true)
	draw_circle(poly[0], 4.0, Color.WHITE)
	for c in cars:
		if c == player:
			continue
		draw_circle(xf * _flat(c.global_position), 4.0, c.model.team_color)
	if player:
		var pp := xf * _flat(player.global_position)
		draw_circle(pp, 6.5, Color.BLACK)
		draw_circle(pp, 5.0, Color(1, 0.85, 0.1))


func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
