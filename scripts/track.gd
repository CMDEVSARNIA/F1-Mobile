extends Node3D
## Builds a drivable circuit from a real-world centerline CSV
## (TUM racetrack-database format: x_m, y_m, w_tr_right_m, w_tr_left_m).
## Generates road, kerbs, lines, walls (with collision), scenery and an
## AI speed profile. Also offers queries cars use for progress tracking.

const KERB_WIDTH := 1.4
const RUNOFF := 10.0
const WALL_HEIGHT := 1.1
const GRID_CELL := 40.0
## Must match the grip model in car.gd so the AI speed profile is achievable.
const GRIP_BASE := 19.0
const GRIP_AERO := 0.0072
const AI_PLAN_DECEL := 28.0
const FOREST_MODEL := "res://assets/kenney/models/decoration-forest.glb"
const TENTS_MODEL := "res://assets/kenney/models/decoration-tents.glb"
const FOREST_SCALE := 3.0
const PLAN_GRIP_MARGIN := 0.85

var points := PackedVector3Array()
var tangents := PackedVector3Array()
var rights := PackedVector3Array()
var width_left := PackedFloat32Array()
var width_right := PackedFloat32Array()
var cum_dist := PackedFloat32Array()
var curvature := PackedFloat32Array()  # signed, + = right-hand corner
var target_speed := PackedFloat32Array()
var length := 0.0
var bounds := Rect2()
## [{detect, start, end}] in metres along the lap, on the longest straights.
var drs_zones: Array = []

# Pit lane: runs beside the start/finish straight on `pit_side` (+1 right).
const PIT_IN_MAX := 420.0  # furthest before the line the lane may leave the track
const PIT_OUT_MAX := 300.0  # furthest after the line it may rejoin
const PIT_LANE_WIDTH := 8.0
const PIT_SPEED := 22.0  # 80 km/h limiter
const PIT_RAMP := 110.0  # entry/exit blend length (shrinks on short straights)
var pit_ramp := PIT_RAMP
var _gantry_lights: Array[StandardMaterial3D] = []
var pit_box_spacing := 24.0
var pit_side := 1.0
var pit_offset := 20.0  # lane centre distance from the centreline (full section)
var pit_in := 0.0
var pit_len := 0.0

var _grid := {}


func build(csv_path: String) -> bool:
	if not _load_csv(csv_path):
		return false
	_compute_frames()
	_compute_speed_profile()
	_compute_drs_zones()
	_build_grid()
	_compute_pit()
	_build_meshes()
	_build_pit()
	_build_gantry()
	_build_boards()
	_build_drs_markers()
	_build_scenery()
	return true


# ---------------------------------------------------------------- loading

func _load_csv(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open track %s" % path)
		return false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var p := line.split(",")
		if p.size() < 4:
			continue
		# CSV y (north) -> Godot -Z so the layout is not mirrored from above.
		points.append(Vector3(p[0].to_float(), 0.0, -p[1].to_float()))
		width_right.append(p[2].to_float())
		width_left.append(p[3].to_float())
	return points.size() > 10


func _compute_frames() -> void:
	var n := points.size()
	tangents.resize(n)
	rights.resize(n)
	cum_dist.resize(n)
	curvature.resize(n)
	var d := 0.0
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for i in n:
		var prev := points[(i - 1 + n) % n]
		var next := points[(i + 1) % n]
		var t := (next - prev).normalized()
		tangents[i] = t
		rights[i] = t.cross(Vector3.UP).normalized()
		cum_dist[i] = d
		d += points[i].distance_to(next)
		mn = Vector2(minf(mn.x, points[i].x), minf(mn.y, points[i].z))
		mx = Vector2(maxf(mx.x, points[i].x), maxf(mx.y, points[i].z))
	length = d
	bounds = Rect2(mn, mx - mn)
	# Curvature from the circumcircle of points k apart (smooths noise).
	var k := 2
	for i in n:
		var a := points[(i - k + n) % n]
		var b := points[i]
		var c := points[(i + k) % n]
		var ab := b - a
		var bc := c - b
		var cross := ab.x * bc.z - ab.z * bc.x  # >0 when turning right (Godot -Z fwd)
		var la := ab.length()
		var lb := bc.length()
		var lc := (c - a).length()
		var denom := la * lb * lc
		curvature[i] = 0.0 if denom < 0.001 else 2.0 * cross / denom


func _compute_speed_profile() -> void:
	var n := points.size()
	target_speed.resize(n)
	for i in n:
		var r := 1.0 / maxf(absf(curvature[i]), 0.00001)
		# v^2 = (GRIP_BASE + GRIP_AERO * v^2) * r, planned with a margin so
		# the AI (and braking assist) can still steer through transitions.
		var m := PLAN_GRIP_MARGIN
		var denom := 1.0 - GRIP_AERO * m * r
		target_speed[i] = 100.0 if denom <= 0.0 else minf(100.0, sqrt(GRIP_BASE * m * r / denom))
	# Backward pass so the AI brakes before corners. Two laps for wrap-around.
	for pass_i in 2:
		for j in range(n - 1, -1, -1):
			var nxt := (j + 1) % n
			var ds := points[j].distance_to(points[nxt])
			var v_lim := sqrt(target_speed[nxt] * target_speed[nxt] + 2.0 * AI_PLAN_DECEL * ds)
			target_speed[j] = minf(target_speed[j], v_lim)


## Like the real thing: zones on the longest straights, activation a little
## after the straight begins, detection 200 m before that.
func _compute_drs_zones() -> void:
	var n := points.size()
	var straight := PackedByteArray()
	straight.resize(n)
	var first_bend := -1
	for i in n:
		straight[i] = 1 if absf(curvature[i]) < 1.0 / 450.0 else 0
		if first_bend == -1 and not straight[i]:
			first_bend = i
	if first_bend == -1:
		return
	var runs := []
	var i := 0
	while i < n:
		var idx := (first_bend + i) % n
		if straight[idx]:
			var start := idx
			var count := 0
			while count < n and straight[(start + count) % n]:
				count += 1
			var s0 := cum_dist[start]
			var s1 := cum_dist[(start + count - 1) % n]
			var run_len := fposmod(s1 - s0, length)
			if run_len > 500.0:
				runs.append([run_len, s0, s1])
			i += count
		else:
			i += 1
	runs.sort_custom(func(a, b): return a[0] > b[0])
	for r in runs.slice(0, 2):
		var start := fposmod(r[1] + 70.0, length)
		drs_zones.append({
			"detect": fposmod(start - 200.0, length),
			"start": start,
			"end": fposmod(r[2] - 40.0, length),
		})


func _build_drs_markers() -> void:
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(0.95, 0.95, 0.95)
	var post := StandardMaterial3D.new()
	post.albedo_color = Color(0.2, 0.2, 0.22)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.95, 0.95, 0.95)
	for z: Dictionary in drs_zones:
		for spec in [[z.detect, "DRS\nDETECTION", 0.06], [z.start, "DRS", 0.2]]:
			var i := index_at_distance(spec[0])
			# Line across the track
			var line := MeshInstance3D.new()
			var lb := BoxMesh.new()
			lb.size = Vector3(width_left[i] + width_right[i], 0.02, 0.35)
			line.mesh = lb
			line.material_override = line_mat
			var c := points[i] + rights[i] * (width_right[i] - width_left[i]) / 2.0
			line.transform = Transform3D(Basis.looking_at(tangents[i], Vector3.UP), c + Vector3(0, _road_y(i) + 0.012, 0))
			add_child(line)
			# Board on a post beside the track, facing oncoming cars
			var side := 1.0 if not is_near_track(points[i] + rights[i] * (width_right[i] + 5.0), 0.0) else -1.0
			var at := points[i] + rights[i] * side * ((width_right[i] if side > 0 else width_left[i]) + KERB_WIDTH + 2.5)
			# Text reads from +Z: face oncoming cars by pointing -Z down the track.
			var basis := Basis.looking_at(tangents[i], Vector3.UP)
			var p := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.12, 2.2, 0.12)
			p.mesh = pm
			p.material_override = post
			p.position = at + Vector3(0, 1.1, 0)
			add_child(p)
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(2.0, 1.1, 0.08)
			b.mesh = bm
			b.material_override = board
			b.transform = Transform3D(basis, at + Vector3(0, 2.4, 0))
			add_child(b)
			var label := Label3D.new()
			label.text = spec[1]
			label.font_size = 96
			label.pixel_size = 0.006 if spec[1] == "DRS" else 0.0045
			label.modulate = Color(0.05, 0.05, 0.05)
			label.outline_size = 0
			label.transform = Transform3D(basis, at + Vector3(0, 2.4, 0) - tangents[i] * 0.06)
			add_child(label)


func in_drs_zone(s: float) -> int:
	for k in drs_zones.size():
		if _in_range(s, drs_zones[k].start, drs_zones[k].end):
			return k
	return -1


static func _in_range(x: float, a: float, b: float) -> bool:
	return (x >= a and x <= b) if a <= b else (x >= a or x <= b)


## True if travelling from `a` to `b` along the lap passed point `p`.
static func crossed(a: float, b: float, p: float) -> bool:
	if b >= a:
		return a < p and p <= b
	return p > a or p <= b


# ---------------------------------------------------------------- pit lane

func _compute_pit() -> void:
	# Fit the lane to the straight around the line: walk out from the line
	# while the track stays (nearly) straight.
	var back := 0.0
	while back < PIT_IN_MAX and absf(curvature[index_at_distance(-back - 10.0)]) < 1.0 / 320.0:
		back += 10.0
	var fwd := 0.0
	while fwd < PIT_OUT_MAX and absf(curvature[index_at_distance(fwd + 10.0)]) < 1.0 / 320.0:
		fwd += 10.0
	back = maxf(back - 20.0, 200.0)
	fwd = maxf(fwd - 20.0, 150.0)
	pit_in = fposmod(-back, length)
	pit_len = back + fwd
	pit_ramp = clampf(pit_len * 0.18, 70.0, PIT_RAMP)
	var drivers: Array = Engine.get_main_loop().root.get_node("/root/GameState").DRIVERS
	pit_box_spacing = clampf((pit_len - 2.0 * pit_ramp - 60.0) / drivers.size(), 14.0, 24.0)
	# Lane goes on whichever side of the straight has room, clear of the rest
	# of the circuit. Offset clears the widest point of the straight.
	var max_w := {1.0: 0.0, -1.0: 0.0}
	for k in 30:
		var i := index_at_distance(pit_in + pit_len * k / 29.0)
		max_w[1.0] = maxf(max_w[1.0], width_right[i])
		max_w[-1.0] = maxf(max_w[-1.0], width_left[i])
	var best_side := 1.0
	var best_clash := INF
	for side: float in [1.0, -1.0]:
		var clash := 0
		for k in 30:
			var s := pit_in + pit_len * k / 29.0
			var i := index_at_distance(s)
			# Far enough out that only *other* parts of the circuit can be near.
			var probe: Vector3 = points[i] + rights[i] * side * (max_w[side] + 34.0)
			if is_near_track(probe, 6.0):
				clash += 1
		if clash < best_clash:
			best_clash = clash
			best_side = side
	pit_side = best_side
	pit_offset = max_w[pit_side] + KERB_WIDTH + 12.0


## Distance travelled into the pit lane for lap position `s` (may be < 0 or
## > pit_len when outside it).
func pit_progress(s: float) -> float:
	var d := fposmod(s - pit_in, length)
	return d - length if d > length * 0.5 else d


## Signed lateral offset of the pit lane centre at pit progress `d`.
func pit_lateral(d: float) -> float:
	var i := index_at_distance(pit_in + d)
	var edge := (width_right[i] if pit_side > 0 else width_left[i]) - 1.5
	var t := 1.0
	if d < pit_ramp:
		t = smoothstep(0.0, pit_ramp, d)
	elif d > pit_len - pit_ramp:
		t = 1.0 - smoothstep(pit_len - pit_ramp, pit_len, d)
	return lerpf(edge, pit_offset, t) * pit_side


func pit_box(team: int) -> float:
	return pit_ramp + 40.0 + team * pit_box_spacing


func in_pit_limiter(d: float) -> bool:
	return d > pit_ramp * 0.6 and d < pit_len - pit_ramp * 0.6


func on_pit_surface(s: float, lateral: float) -> bool:
	var d := pit_progress(s)
	if d < 0.0 or d > pit_len or signf(lateral) != pit_side:
		return false
	return absf(lateral - pit_lateral(d)) < PIT_LANE_WIDTH * 0.75


func _in_pit_complex(p: Vector3) -> bool:
	var i := closest_index_global(p)
	var proj := project(p, i)
	var d := pit_progress(proj.x)
	return d > -60.0 and d < pit_len + 60.0 and signf(proj.y) == pit_side \
			and absf(proj.y) < pit_offset + 45.0


func _build_pit() -> void:
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.3, 0.3, 0.32)
	asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.cull_mode = BaseMaterial3D.CULL_DISABLED
	var steps := int(pit_len / 4.0)
	var lane_l := PackedVector3Array()
	var lane_r := PackedVector3Array()
	var line_l := PackedVector3Array()
	var line_r := PackedVector3Array()
	for k in steps + 1:
		var d := pit_len * k / steps
		var p := point_at(pit_in + d, pit_lateral(d))
		var i := index_at_distance(pit_in + d)
		var r := rights[i] * pit_side
		var y := Vector3(0, _road_y(i) + 0.004, 0)
		lane_l.append(p - r * PIT_LANE_WIDTH / 2.0 + y)
		lane_r.append(p + r * PIT_LANE_WIDTH / 2.0 + y)
		# Painted line on the garage side marks the fast lane
		line_l.append(p + r * 0.8 + y + Vector3(0, 0.006, 0))
		line_r.append(p + r * 1.0 + y + Vector3(0, 0.006, 0))
	_add_mesh(_open_ribbon(lane_l, lane_r, Color.WHITE), asphalt)
	_add_mesh(_open_ribbon(line_l, line_r, Color(0.95, 0.95, 0.95)), vc)

	# Pit wall between track and lane, and the garage block behind the lane.
	var faces := PackedVector3Array()
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall_off := (pit_offset - PIT_LANE_WIDTH / 2.0 - 1.0)
	var garage_off := pit_offset + PIT_LANE_WIDTH / 2.0 + 0.5
	for spec in [[wall_off, pit_ramp - 10.0, pit_len - pit_ramp + 10.0, 1.1, Color(0.85, 0.85, 0.88)],
			[garage_off, pit_ramp, pit_len - pit_ramp, 1.2, Color(0.5, 0.5, 0.55)]]:
		var segs := int((spec[2] - spec[1]) / 6.0)
		for k in segs:
			var d0: float = spec[1] + (spec[2] - spec[1]) * k / segs
			var d1: float = spec[1] + (spec[2] - spec[1]) * (k + 1) / segs
			var a := point_at(pit_in + d0, spec[0] * pit_side)
			var b := point_at(pit_in + d1, spec[0] * pit_side)
			var up := Vector3(0, spec[3], 0)
			wall.set_color(spec[4] if k % 2 == 0 else Color(0.85, 0.1, 0.1))
			for v in [a, b, b + up, a, b + up, a + up]:
				wall.add_vertex(v)
			faces.append_array([a, b, b + up, a, b + up, a + up])
	wall.generate_normals()
	_add_mesh(wall.commit(), vc)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	add_child(body)

	# Garages: one per team, coloured door frames, under a long roof.
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.86, 0.86, 0.9)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.1)
	var drivers: Array = Engine.get_main_loop().root.get_node("/root/GameState").DRIVERS
	for team in drivers.size():
		var d := pit_box(team)
		if d > pit_len - pit_ramp:
			break
		var i := index_at_distance(pit_in + d)
		var basis := Basis.looking_at(tangents[i], Vector3.UP)
		var front := point_at(pit_in + d, (garage_off + 0.6) * pit_side)
		var out := rights[i] * pit_side
		var g := MeshInstance3D.new()
		var gb := BoxMesh.new()
		gb.size = Vector3(14.0, 7.0, pit_box_spacing - 1.0)
		g.mesh = gb
		g.material_override = shell
		g.transform = Transform3D(basis, front + out * 7.0 + Vector3(0, 3.5, 0))
		add_child(g)
		var door := MeshInstance3D.new()
		var db := BoxMesh.new()
		db.size = Vector3(0.2, 4.5, pit_box_spacing - 6.0)
		door.mesh = db
		door.material_override = dark
		door.transform = Transform3D(basis, front + out * 0.05 + Vector3(0, 2.25, 0))
		add_child(door)
		var band := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.3, 1.2, pit_box_spacing - 1.0)
		band.mesh = bb
		var team_mat := StandardMaterial3D.new()
		team_mat.albedo_color = drivers[team].color
		band.material_override = team_mat
		band.transform = Transform3D(basis, front + out * 0.1 + Vector3(0, 5.6, 0))
		add_child(band)
		# Box marking on the lane
		var mark := MeshInstance3D.new()
		var mb := BoxMesh.new()
		mb.size = Vector3(3.0, 0.02, 6.0)
		mark.mesh = mb
		mark.material_override = team_mat
		mark.transform = Transform3D(basis, point_at(pit_in + d, pit_lateral(d) + pit_side * 1.8) + Vector3(0, _road_y(i) + 0.012, 0))
		add_child(mark)


# ---------------------------------------------------------------- dressing

## Start gantry across the line; its five lights follow the start sequence.
func _build_gantry() -> void:
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.22, 0.22, 0.25)
	var basis := Basis.looking_at(tangents[0], Vector3.UP)
	var r := rights[0]
	var y := Vector3(0, _road_y(0), 0)
	var left := points[0] - r * (width_left[0] + 2.5) + y
	var right := points[0] + r * (width_right[0] + 2.5) + y
	for p: Vector3 in [left, right]:
		_box(Vector3(0.7, 7.6, 0.7), p + Vector3(0, 3.8, 0), basis, grey)
	var mid := (left + right) / 2.0
	_box(Vector3(left.distance_to(right) + 0.7, 0.9, 0.9), mid + Vector3(0, 7.2, 0), basis, grey)
	var housing := StandardMaterial3D.new()
	housing.albedo_color = Color(0.05, 0.05, 0.06)
	for k in 5:
		var c := mid + r * (k - 2) * 1.1 + Vector3(0, 6.0, 0) - tangents[0] * 0.5
		_box(Vector3(0.9, 1.8, 0.35), c, basis, housing)
		var lamp := StandardMaterial3D.new()
		lamp.albedo_color = Color(0.2, 0.02, 0.02)
		lamp.emission_enabled = true
		lamp.emission = Color(1.0, 0.05, 0.03)
		lamp.emission_energy_multiplier = 0.0
		_gantry_lights.append(lamp)
		for dy: float in [-0.4, 0.4]:
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.28
			sm.height = 0.56
			sm.radial_segments = 10
			sm.rings = 5
			bulb.mesh = sm
			bulb.material_override = lamp
			bulb.position = c + Vector3(0, dy, 0) - tangents[0] * 0.2
			add_child(bulb)


func set_gantry_lights(n: int) -> void:
	for k in _gantry_lights.size():
		var on := k < n
		_gantry_lights[k].albedo_color = Color(1.0, 0.1, 0.05) if on else Color(0.2, 0.02, 0.02)
		_gantry_lights[k].emission_energy_multiplier = 1.2 if on else 0.0


## Our own trackside boards along the start straight.
func _build_boards() -> void:
	var board := StandardMaterial3D.new()
	board.albedo_color = Color(0.88, 0.02, 0.0)
	for s: float in [-120.0, -60.0, 60.0, 120.0, 180.0]:
		var i := index_at_distance(s)
		var side := -pit_side
		var w := (width_right[i] if side > 0 else width_left[i]) + KERB_WIDTH + RUNOFF + 0.4
		var p := points[i] + rights[i] * side * w + Vector3(0, 1.9, 0)
		if is_near_track(p, KERB_WIDTH + 2.0):
			continue
		# Label3D text reads from its +Z side, so -Z points away from the track.
		var basis := Basis.looking_at(rights[i] * side, Vector3.UP)
		_box(Vector3(9.0, 1.6, 0.15), p, basis, board)
		var label := Label3D.new()
		label.text = "FORMULA FORCE"
		label.font_size = 96
		label.pixel_size = 0.009
		label.outline_size = 0
		label.modulate = Color.WHITE
		label.transform = Transform3D(basis, p - rights[i] * side * 0.1)
		add_child(label)


func _box(size: Vector3, pos: Vector3, basis: Basis, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	add_child(mi)
	return mi


## Like _ribbon but not closed into a loop.
func _open_ribbon(left: PackedVector3Array, right: PackedVector3Array, color: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(color)
	for k in left.size() - 1:
		for v in [left[k], right[k], right[k + 1], left[k], right[k + 1], left[k + 1]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


func _build_grid() -> void:
	for i in points.size():
		var key := _cell(points[i])
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_grid[key].append(i)


func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))


# ---------------------------------------------------------------- queries

func half_width(i: int, lateral: float) -> float:
	return width_right[i] if lateral >= 0.0 else width_left[i]


## Nearest centerline index searching only around `hint`. Using a local
## window keeps cars on the correct branch where the track crosses itself.
func closest_index_local(pos: Vector3, hint: int, window: int = 12) -> int:
	var n := points.size()
	var best := hint
	var best_d := INF
	for o in range(-window, window + 1):
		var i := (hint + o + n) % n
		var dd := _flat_dist_sq(points[i], pos)
		if dd < best_d:
			best_d = dd
			best = i
	return best


func closest_index_global(pos: Vector3) -> int:
	var c := _cell(pos)
	var best := -1
	var best_d := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				var dd := _flat_dist_sq(points[i], pos)
				if dd < best_d:
					best_d = dd
					best = i
	if best == -1:
		for i in points.size():
			var dd := _flat_dist_sq(points[i], pos)
			if dd < best_d:
				best_d = dd
				best = i
	return best


## Returns Vector2(distance along lap, lateral offset; + = right of center).
func project(pos: Vector3, i: int) -> Vector2:
	var rel := pos - points[i]
	rel.y = 0.0
	var s := fposmod(cum_dist[i] + rel.dot(tangents[i]), length)
	return Vector2(s, rel.dot(rights[i]))


func index_at_distance(s: float) -> int:
	s = fposmod(s, length)
	var lo := 0
	var hi := cum_dist.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum_dist[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return lo


## World position at distance `s` along the lap, shifted `lateral` metres right.
func point_at(s: float, lateral: float = 0.0) -> Vector3:
	s = fposmod(s, length)
	var i := index_at_distance(s)
	var j := (i + 1) % points.size()
	var seg_end := length if j == 0 else cum_dist[j]
	var t := 0.0
	if seg_end - cum_dist[i] > 0.001:
		t = (s - cum_dist[i]) / (seg_end - cum_dist[i])
	var p := points[i].lerp(points[j], t)
	var r := rights[i].lerp(rights[j], t).normalized()
	return p + r * lateral


func transform_at(s: float, lateral: float = 0.0) -> Transform3D:
	var p := point_at(s, lateral)
	var ahead := point_at(s + 3.0, lateral)
	return Transform3D(Basis.IDENTITY, p).looking_at(ahead, Vector3.UP)


func _flat_dist_sq(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return dx * dx + dz * dz


## True if `pos` lies within `margin` of any part of the track surface.
func is_near_track(pos: Vector3, margin: float) -> bool:
	var c := _cell(pos)
	var reach := ceili((margin + 20.0) / GRID_CELL)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if not _grid.has(key):
				continue
			for i in _grid[key]:
				var w := maxf(width_left[i], width_right[i]) + margin
				if _flat_dist_sq(points[i], pos) < w * w:
					return true
	return false


# ---------------------------------------------------------------- meshes

func _road_y(i: int) -> float:
	# A tiny climb over the lap means crossing sections (Suzuka) never z-fight.
	return 0.02 + 0.04 * float(i) / points.size()


func _build_meshes() -> void:
	var n := points.size()
	var road_l := PackedVector3Array()
	var road_r := PackedVector3Array()
	for i in n:
		var y := Vector3(0, _road_y(i), 0)
		road_l.append(points[i] - rights[i] * width_left[i] + y)
		road_r.append(points[i] + rights[i] * width_right[i] + y)

	# Asphalt
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color(0.26, 0.26, 0.28)
	asphalt.albedo_texture = _noise_texture(0.08, 0.7, 1.0)
	asphalt.uv1_scale = Vector3(0.12, 0.12, 1)
	asphalt.roughness = 0.92
	asphalt.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_mesh(_ribbon(road_l, road_r, Color.WHITE, [], true), asphalt)

	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.roughness = 0.8
	vc.cull_mode = BaseMaterial3D.CULL_DISABLED

	# White edge lines
	var lift := Vector3(0, 0.006, 0)
	var line_in_l := PackedVector3Array()
	var line_in_r := PackedVector3Array()
	var line_out_l := PackedVector3Array()
	var line_out_r := PackedVector3Array()
	for i in n:
		line_out_l.append(road_l[i] + lift)
		line_in_l.append(road_l[i] + rights[i] * 0.35 + lift)
		line_in_r.append(road_r[i] - rights[i] * 0.35 + lift)
		line_out_r.append(road_r[i] + lift)
	_add_mesh(_ribbon(line_out_l, line_in_l, Color(0.95, 0.95, 0.95)), vc)
	_add_mesh(_ribbon(line_in_r, line_out_r, Color(0.95, 0.95, 0.95)), vc)

	# Kerbs on corners: inside and outside, alternating red / white.
	var kerb_mask := PackedByteArray()
	kerb_mask.resize(n)
	for i in n:
		kerb_mask[i] = 1 if absf(curvature[i]) > 1.0 / 220.0 else 0
	# Grow the mask a little so kerbs run through corner entry/exit.
	var grown := kerb_mask.duplicate()
	for i in n:
		if kerb_mask[i]:
			for o in range(-3, 4):
				grown[(i + o + n) % n] = 1
	var kerb_lift := Vector3(0, 0.012, 0)
	var kl_in := PackedVector3Array()
	var kl_out := PackedVector3Array()
	var kr_in := PackedVector3Array()
	var kr_out := PackedVector3Array()
	for i in n:
		kl_in.append(road_l[i] + kerb_lift)
		kl_out.append(road_l[i] - rights[i] * KERB_WIDTH + kerb_lift)
		kr_in.append(road_r[i] + kerb_lift)
		kr_out.append(road_r[i] + rights[i] * KERB_WIDTH + kerb_lift)
	var kerb_cols := [Color(0.8, 0.04, 0.04), Color(0.95, 0.95, 0.95)]
	_add_mesh(_ribbon(kl_out, kl_in, Color.WHITE, grown, false, kerb_cols, 5), vc)
	_add_mesh(_ribbon(kr_in, kr_out, Color.WHITE, grown, false, kerb_cols, 5), vc)

	# Start / finish: checkered strip across the track at index 0.
	_build_start_line(vc)

	# Walls, dropped wherever they would cut across another part of the track.
	_build_walls(vc)

	# Ground
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	var size := bounds.size + Vector2(1600, 1600)
	plane.size = size
	ground.mesh = plane
	ground.position = Vector3(bounds.get_center().x, 0.0, bounds.get_center().y)
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.2, 0.38, 0.12)
	grass.albedo_texture = _noise_texture(0.03, 0.55, 1.0)
	grass.uv1_scale = Vector3(size.x / 30.0, size.y / 30.0, 1)
	grass.roughness = 1.0
	ground.material_override = grass
	add_child(ground)


func _build_start_line(mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := points[0]
	var r := rights[0]
	var t := tangents[0]
	var y := Vector3(0, _road_y(0) + 0.01, 0)
	var cols := 14
	var rows := 2
	var w := width_left[0] + width_right[0]
	var cell_w := w / cols
	var cell_l := 0.9
	for cx in cols:
		for cz in rows:
			st.set_color(Color.WHITE if (cx + cz) % 2 == 0 else Color(0.05, 0.05, 0.05))
			var o := p - r * width_left[0] + r * (cx * cell_w) + t * (cz * cell_l) + y
			var a := o
			var b := o + r * cell_w
			var c := o + r * cell_w + t * cell_l
			var d := o + t * cell_l
			for v in [a, b, c, a, c, d]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	_add_mesh(st.commit(), mat)

	# Grid slot markings behind the line.
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.set_color(Color(0.95, 0.95, 0.95))
	for slot in 20:
		var gt := transform_at(-grid_distance(slot), grid_lateral(slot))
		var gp := gt.origin + Vector3(0, 0.05, 0)
		var gr := gt.basis.x
		var gf := -gt.basis.z
		var front := gp + gf * 3.0
		var a := front - gr * 1.1
		var b := front + gr * 1.1
		var c := b + gf * 0.3
		var d := a + gf * 0.3
		for v in [a, b, c, a, c, d]:
			st2.set_normal(Vector3.UP)
			st2.add_vertex(v)
	_add_mesh(st2.commit(), mat)


func grid_distance(slot: int) -> float:
	return 10.0 + slot * 8.0


func grid_lateral(slot: int) -> float:
	return -2.8 if slot % 2 == 0 else 2.8


func _build_walls(mat: Material) -> void:
	var n := points.size()
	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		var base := PackedVector3Array()
		var ok := PackedByteArray()
		base.resize(n)
		ok.resize(n)
		for i in n:
			var w := (width_right[i] if side > 0 else width_left[i]) + KERB_WIDTH + RUNOFF
			var wp := points[i] + rights[i] * w * side
			base[i] = wp
			ok[i] = 0 if is_near_track(wp, KERB_WIDTH + 3.0) else 1
			if side == pit_side and pit_progress(cum_dist[i]) >= -30.0 and pit_progress(cum_dist[i]) <= pit_len + 30.0:
				ok[i] = 0  # the pit lane runs here instead
		for i in n:
			var j := (i + 1) % n
			if not ok[i] or not ok[j]:
				continue
			var a := base[i]
			var b := base[j]
			if a.distance_to(b) > 25.0:
				continue
			var up := Vector3(0, WALL_HEIGHT, 0)
			var col := Color(0.82, 0.82, 0.85) if (i / 2) % 2 == 0 else Color(0.15, 0.3, 0.75)
			st.set_color(col)
			var n_out := rights[i] * side
			for v in [a, b, b + up, a, b + up, a + up]:
				st.set_normal(-n_out)
				st.add_vertex(v)
			faces.append_array([a, b, b + up, a, b + up, a + up])
	_add_mesh(st.commit(), mat)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.backface_collision = true
	concave.set_faces(faces)
	shape.shape = concave
	body.add_child(shape)
	add_child(body)


## Builds a quad strip between two edge polylines. `mask` (optional) selects
## segments. `alt_colors` alternates per segment (used for kerbs).
func _ribbon(left: PackedVector3Array, right: PackedVector3Array, color: Color,
		mask: PackedByteArray = PackedByteArray(), with_uv := false, alt_colors := [],
		subdiv := 1) -> ArrayMesh:
	var n := left.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	for i in n:
		if not mask.is_empty() and not mask[i]:
			continue
		var j := (i + 1) % n
		var d0 := cum_dist[i]
		var d1 := length if j == 0 else cum_dist[j]
		for sub in subdiv:
			var t0 := float(sub) / subdiv
			var t1 := float(sub + 1) / subdiv
			var c: Color = color if alt_colors.is_empty() else alt_colors[(i * subdiv + sub) % alt_colors.size()]
			var l0 := left[i].lerp(left[j], t0)
			var l1 := left[i].lerp(left[j], t1)
			var r0 := right[i].lerp(right[j], t0)
			var r1 := right[i].lerp(right[j], t1)
			var v0 := lerpf(d0, d1, t0)
			var v1 := lerpf(d0, d1, t1)
			var w0 := l0.distance_to(r0)
			var w1 := l1.distance_to(r1)
			var quad := [l0, r0, r1, l0, r1, l1]
			var quv := [Vector2(0, v0), Vector2(w0, v0), Vector2(w1, v1), Vector2(0, v0), Vector2(w1, v1), Vector2(0, v1)]
			for k in 6:
				verts.append(quad[k])
				normals.append(Vector3.UP)
				colors.append(c)
				uvs.append(quv[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	if with_uv:
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	if verts.size() > 0:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## First mesh found in an imported glTF scene.
func _glb_mesh(path: String) -> Mesh:
	var scene: PackedScene = load(path)
	var root := scene.instantiate()
	var mi := root.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = mi[0].mesh if mi.size() > 0 else null
	root.free()
	return mesh


## Copy of a mesh's first material with its colour multiplied by `tint`.
func _tinted(mesh: Mesh, tint: Color) -> Material:
	var src := mesh.surface_get_material(0) as BaseMaterial3D
	var m: BaseMaterial3D = src.duplicate() if src else StandardMaterial3D.new()
	m.albedo_color = m.albedo_color * tint
	m.roughness = 1.0
	return m


func _noise_texture(freq: float, lo: float, hi: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = freq
	noise.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(lo, lo, lo))
	ramp.set_color(1, Color(hi, hi, hi))
	tex.color_ramp = ramp
	return tex


# ---------------------------------------------------------------- scenery

func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(length)

	# Forest: Kenney CC0 tiles (10 m square, ~2k tris) scaled up and batched
	# into one MultiMesh per map chunk, so off-screen chunks get culled and
	# distant ones drop out via visibility range.
	var forest := _glb_mesh(FOREST_MODEL)
	# Kenney's palette is bright teal; pull it toward natural, darker greens.
	var forest_mat := _tinted(forest, Color(0.55, 0.62, 0.38))
	var tile := 10.0 * FOREST_SCALE
	var chunks := {}
	var area := bounds.grow(300.0)
	var gx := area.position.x
	while gx < area.end.x:
		var gz := area.position.y
		while gz < area.end.y:
			var p := Vector3(gx + rng.randf_range(-4, 4), 0.0, gz + rng.randf_range(-4, 4))
			gz += tile
			# Sparse clumps rather than a carpet, and well clear of the barriers.
			if rng.randf() > 0.45 or is_near_track(p, KERB_WIDTH + RUNOFF + tile * 0.75) or _in_pit_complex(p):
				continue
			var b := Basis(Vector3.UP, rng.randi_range(0, 3) * PI / 2.0) \
					* Basis().scaled(Vector3.ONE * FOREST_SCALE * rng.randf_range(0.85, 1.15))
			var key := Vector2i(floori(p.x / 400.0), floori(p.z / 400.0))
			if not chunks.has(key):
				chunks[key] = []
			chunks[key].append(Transform3D(b, p))
		gx += tile
	for key in chunks:
		var xforms: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = forest
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 1100.0
		mmi.material_override = forest_mat
		add_child(mmi)

	# Paddock / fan-zone tents near the start, on whichever side is free.
	var tents := _glb_mesh(TENTS_MODEL)
	var tents_mat := _tinted(tents, Color(0.75, 0.8, 0.7))
	for s_at: float in [-260.0, -200.0, 120.0, 180.0, 240.0]:
		var i := index_at_distance(s_at)
		for side: float in [-1.0, 1.0]:
			var off := (width_right[i] if side > 0 else width_left[i]) + KERB_WIDTH + RUNOFF + 22.0
			var p := points[i] + rights[i] * off * side
			if is_near_track(p, KERB_WIDTH + RUNOFF + 12.0) or _in_pit_complex(p):
				continue
			var mi := MeshInstance3D.new()
			mi.mesh = tents
			mi.material_override = tents_mat
			mi.transform = Transform3D(Basis.looking_at(tangents[i], Vector3.UP).scaled(Vector3.ONE * 2.2), p)
			add_child(mi)
			break

	# Tiered grandstands along the start straight, wherever there's room.
	var stand_mat := StandardMaterial3D.new()
	stand_mat.albedo_color = Color(0.6, 0.6, 0.65)
	var crowd_mat := StandardMaterial3D.new()
	crowd_mat.albedo_texture = _noise_texture(0.9, 0.2, 1.0)
	crowd_mat.albedo_color = Color(0.9, 0.75, 0.6)
	crowd_mat.uv1_scale = Vector3(6, 1, 1)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.8, 0.08, 0.06)
	for s_at: float in [-150.0, -80.0, -10.0, 60.0]:
		var i := index_at_distance(s_at)
		for side: float in [-pit_side]:
			var off := (width_right[i] if side > 0 else width_left[i]) + KERB_WIDTH + RUNOFF + 6.0
			var base := points[i] + rights[i] * off * side
			if is_near_track(base + rights[i] * side * 12.0, KERB_WIDTH + RUNOFF + 1.0) \
					or is_near_track(base, KERB_WIDTH + RUNOFF - 2.0):
				continue
			var basis := Basis.looking_at(tangents[i], Vector3.UP)
			for tier in 5:
				var h := 1.2 + tier * 1.4
				var step := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(2.4, h, 60)
				step.mesh = box
				step.material_override = crowd_mat if tier % 2 == 0 else stand_mat
				step.transform = Transform3D(basis, base + rights[i] * side * (tier * 2.4) + Vector3(0, h / 2.0, 0))
				add_child(step)
			var roof := MeshInstance3D.new()
			var rbox := BoxMesh.new()
			rbox.size = Vector3(14, 0.4, 62)
			roof.mesh = rbox
			roof.material_override = roof_mat
			roof.transform = Transform3D(basis, base + rights[i] * side * 5.0 + Vector3(0, 10.5, 0))
			add_child(roof)
			break
