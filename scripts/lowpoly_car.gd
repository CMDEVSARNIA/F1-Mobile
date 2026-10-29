extends Node3D
## Clean low-poly modern F1 car, modelled in code from lofted cross-sections
## and flat-shaded. ~1.5k triangles. Faces -Z, origin on the ground between
## the axles, about 5.6 m long like the real thing.
##
## Exposes: team_color / accent_color, set_drs(open), set_compound(color),
## update_wheels(steer, speed, dt).

const WHEEL_R := 0.36
const FRONT_AXLE := -1.6
const REAR_AXLE := 1.95

var team_color := Color(0.85, 0.05, 0.05)
var accent_color := Color.WHITE

var _paint: StandardMaterial3D
var _accent: StandardMaterial3D
var _carbon: StandardMaterial3D
var _dark: StandardMaterial3D
var _stripe: StandardMaterial3D
var _drs_flap: Node3D
var _drs_target := 0.0
var _front_pivots: Array[Node3D] = []
## Wing assemblies, kept as their own nodes so damage can bend or remove them.
var front_wing: Node3D
var rear_wing: Node3D
var _spinners: Array[Node3D] = []
var _spin := 0.0


func _ready() -> void:
	_paint = _mat(team_color, 0.4, 0.3)
	_accent = _mat(accent_color, 0.3, 0.35)
	_carbon = _mat(Color(0.07, 0.07, 0.08), 0.25, 0.5)
	_dark = _mat(Color(0.02, 0.02, 0.025), 0.0, 0.8)
	_stripe = _mat(Color(1.0, 0.85, 0.1), 0.0, 0.6)
	_build_body()
	_build_sidepods()
	_build_floor()
	_build_front_wing()
	_build_rear_wing()
	_build_cockpit()
	_build_suspension()
	_build_wheels()


func set_drs(open: bool) -> void:
	_drs_target = deg_to_rad(-38.0) if open else 0.0


func set_compound(color: Color) -> void:
	_stripe.albedo_color = color


func update_wheels(steer: float, speed: float, dt: float) -> void:
	_spin = fmod(_spin + speed / WHEEL_R * dt, TAU)
	for s in _spinners:
		s.rotation.x = -_spin
	for p in _front_pivots:
		p.rotation.y = -steer * 0.35
	if _drs_flap:
		_drs_flap.rotation.x = lerpf(_drs_flap.rotation.x, _drs_target, clampf(dt * 10.0, 0.0, 1.0))


# ------------------------------------------------------------ parts

func _build_body() -> void:
	# Nose, survival cell, engine cover and gearbox as one loft.
	# [z, width, height, centre y, squareness]
	var spec := [
		[-2.66, 0.10, 0.08, 0.19, 2.2],
		[-2.35, 0.20, 0.13, 0.23, 2.4],
		[-1.85, 0.32, 0.21, 0.30, 2.6],
		[-1.25, 0.46, 0.31, 0.37, 3.0],
		[-0.70, 0.66, 0.44, 0.43, 3.2],
		[-0.20, 0.80, 0.52, 0.46, 3.4],
		[0.35, 0.80, 0.56, 0.48, 3.4],
		[0.55, 0.66, 0.88, 0.63, 3.0],  # airbox behind the driver's head
		[1.05, 0.56, 0.70, 0.56, 3.0],
		[1.65, 0.34, 0.44, 0.45, 2.8],
		[2.15, 0.22, 0.24, 0.36, 2.6],
	]
	var rings: Array = []
	for r in spec:
		rings.append(_ring_xy(Vector3(0, r[3], r[0]), r[1], r[2], 12, r[4]))
	_add(_loft(rings, true, true), _paint)
	# Airbox intake (dark mouth above the helmet)
	_add(_box_mesh(Vector3(0.26, 0.2, 0.04), Vector3(0, 0.92, 0.36)), _dark)
	# Shark fin along the engine cover
	var fin := [
		Vector3(0, 0.98, 0.58), Vector3(0, 0.98, 1.0), Vector3(0, 0.62, 2.05), Vector3(0, 0.55, 2.05),
		Vector3(0, 0.80, 0.58),
	]
	_add(_slab(fin, 0.025), _paint)
	# Accent stripe down the nose
	_add(_box_mesh(Vector3(0.12, 0.012, 1.3), Vector3(0, 0.425, -1.75), Vector3(deg_to_rad(-7), 0, 0)), _accent)
	# Rain light
	_add(_box_mesh(Vector3(0.12, 0.06, 0.02), Vector3(0, 0.3, 2.28)), _mat(Color(1, 0.1, 0.05), 0, 0.4, 2.0))


func _build_sidepods() -> void:
	for sx: float in [-1.0, 1.0]:
		var spec := [
			[-0.48, 0.44, 0.34, 0.38],
			[0.05, 0.50, 0.38, 0.37],
			[0.75, 0.40, 0.30, 0.32],
			[1.45, 0.18, 0.16, 0.24],
		]
		var rings: Array = []
		for r in spec:
			# Undercut: pods are wider at the top, so shift the centre outward.
			rings.append(_ring_xy(Vector3(0.6 * sx, r[3], r[0]), r[1], r[2], 10, 2.6))
		_add(_loft(rings, false, true), _paint)
		# Dark inlet face
		var inlet: PackedVector3Array = rings[0]
		_add(_cap(inlet, true), _dark)
		# Mirror on a stalk
		_add(_tube([Vector3(0.36 * sx, 0.62, -0.55), Vector3(0.52 * sx, 0.76, -0.62)], 0.012, 4), _carbon)
		_add(_box_mesh(Vector3(0.16, 0.07, 0.04), Vector3(0.56 * sx, 0.78, -0.63)), _paint)


func _build_floor() -> void:
	var outline := PackedVector2Array([
		Vector2(-0.36, -1.05), Vector2(0.36, -1.05), Vector2(0.72, -0.5), Vector2(0.78, 1.0),
		Vector2(0.55, 1.8), Vector2(-0.55, 1.8), Vector2(-0.78, 1.0), Vector2(-0.72, -0.5),
	])
	_add(_extrude_xz(outline, 0.05, 0.11), _carbon)
	# Diffuser ramp
	var dif := [
		[Vector3(-0.5, 0.06, 1.8), Vector3(0.5, 0.06, 1.8)],
		[Vector3(-0.5, 0.26, 2.3), Vector3(0.5, 0.26, 2.3)],
	]
	_add(_plate(dif[0][0], dif[0][1], dif[1][1], dif[1][0], 0.02), _carbon)


func _build_front_wing() -> void:
	front_wing = Node3D.new()
	add_child(front_wing)
	# Three elements, rising and steepening toward the back.
	var elems := [
		[-2.92, 0.085, 0.36, -4.0, 1.96, _carbon],
		[-2.66, 0.15, 0.20, -20.0, 1.84, _accent],
		[-2.53, 0.215, 0.15, -34.0, 1.70, _paint],
	]
	for e in elems:
		_add(_wing(Vector3(0, e[1], e[0]), e[2], e[3], e[4]), e[5], front_wing)
	for sx: float in [-1.0, 1.0]:
		var ep := [Vector3(0.98 * sx, 0.04, -3.12), Vector3(0.98 * sx, 0.04, -2.42),
				Vector3(0.98 * sx, 0.3, -2.42), Vector3(0.98 * sx, 0.26, -2.9)]
		_add(_slab(ep, 0.02), _paint, front_wing)
		# Nose pylons
		_add(_tube([Vector3(0.09 * sx, 0.2, -2.45), Vector3(0.2 * sx, 0.1, -2.8)], 0.018, 4), _carbon, front_wing)


func _build_rear_wing() -> void:
	rear_wing = Node3D.new()
	add_child(rear_wing)
	# Main plane
	_add(_wing(Vector3(0, 0.88, 2.34), 0.34, -10.0, 1.0), _carbon, rear_wing)
	# DRS flap, pivoting about its leading edge
	_drs_flap = Node3D.new()
	_drs_flap.position = Vector3(0, 0.95, 2.18)
	rear_wing.add_child(_drs_flap)
	var flap := MeshInstance3D.new()
	flap.mesh = _wing(Vector3(0, 0.03, 0.12), 0.24, -32.0, 0.98)
	flap.material_override = _accent
	_drs_flap.add_child(flap)
	# Beam wing low down
	_add(_wing(Vector3(0, 0.44, 2.3), 0.18, -12.0, 0.72), _carbon)
	for sx: float in [-1.0, 1.0]:
		var ep := [Vector3(0.51 * sx, 0.38, 2.0), Vector3(0.51 * sx, 0.38, 2.62),
				Vector3(0.51 * sx, 1.08, 2.62), Vector3(0.51 * sx, 1.08, 2.08)]
		_add(_slab(ep, 0.025), _paint, rear_wing)
	# Swan-neck pylon
	_add(_tube([Vector3(0, 0.38, 2.2), Vector3(0, 0.7, 2.3), Vector3(0, 0.86, 2.28)], 0.03, 4), _carbon, rear_wing)


func _build_cockpit() -> void:
	# Opening rim and helmet
	_add(_box_mesh(Vector3(0.5, 0.05, 0.78), Vector3(0, 0.735, -0.28)), _dark)
	var helmet := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.15
	sph.height = 0.3
	sph.radial_segments = 10
	sph.rings = 6
	helmet.mesh = sph
	helmet.material_override = _mat(accent_color.lerp(Color(1, 0.85, 0.1), 0.5), 0.2, 0.25)
	helmet.position = Vector3(0, 0.8, -0.12)
	add_child(helmet)
	# Halo: horseshoe tube plus centre pillar
	var pts := []
	for i in 13:
		var a := lerpf(deg_to_rad(-105), deg_to_rad(105), i / 12.0)
		pts.append(Vector3(sin(a) * 0.31, 0.88 + 0.04 * cos(a), -0.12 - cos(a) * 0.42))
	pts.push_front(Vector3(-0.33, 0.74, 0.05))
	pts.append(Vector3(0.33, 0.74, 0.05))
	_add(_tube(pts, 0.03, 6), _carbon)
	_add(_tube([Vector3(0, 0.92, -0.54), Vector3(0, 0.68, -0.72)], 0.03, 6), _carbon)


func _build_suspension() -> void:
	for axle: float in [FRONT_AXLE, REAR_AXLE]:
		for sx: float in [-1.0, 1.0]:
			var hub := Vector3(0.78 * sx, WHEEL_R, axle)
			for dz: float in [-0.22, 0.22]:
				_add(_tube([Vector3(0.24 * sx, 0.46, axle + dz), hub + Vector3(0, 0.12, 0)], 0.016, 4), _carbon)
				_add(_tube([Vector3(0.24 * sx, 0.24, axle + dz), hub - Vector3(0, 0.1, 0)], 0.016, 4), _carbon)


func _build_wheels() -> void:
	var rim_mat := _mat(Color(0.12, 0.12, 0.13), 0.7, 0.35)
	for spec in [[-0.86, FRONT_AXLE, 0.38, true], [0.86, FRONT_AXLE, 0.38, true],
			[-0.84, REAR_AXLE, 0.44, false], [0.84, REAR_AXLE, 0.44, false]]:
		var pivot := Node3D.new()
		pivot.position = Vector3(spec[0], WHEEL_R, spec[1])
		add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var w: float = spec[2]
		spin.add_child(_cyl(WHEEL_R, w, 18, _dark))
		# Compound-coloured sidewall stripes on both faces
		for side: float in [-1.0, 1.0]:
			var ring := _cyl(WHEEL_R * 0.84, 0.012, 18, _stripe)
			ring.position.x = side * (w / 2.0 + 0.002)
			spin.add_child(ring)
			var hub := _cyl(WHEEL_R * 0.66, 0.02, 12, rim_mat)
			hub.position.x = side * (w / 2.0 + 0.008)
			spin.add_child(hub)
		# Spoke bar so rotation reads at speed
		var bar := MeshInstance3D.new()
		bar.mesh = _box_mesh(Vector3(w + 0.03, WHEEL_R * 1.1, 0.07), Vector3.ZERO)
		bar.material_override = rim_mat
		spin.add_child(bar)
		_spinners.append(spin)
		if spec[3]:
			_front_pivots.append(pivot)


# ------------------------------------------------------------ geometry

func _mat(c: Color, metallic := 0.0, rough := 0.5, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


func _add(mesh: Mesh, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	(parent if parent else self).add_child(mi)
	return mi


## Superellipse ring in the XY plane at `c` (higher `p` = boxier).
func _ring_xy(c: Vector3, w: float, h: float, n: int, p: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var t := TAU * i / n + PI / n
		var cx := cos(t)
		var sy := sin(t)
		var x := signf(cx) * pow(absf(cx), 2.0 / p) * w / 2.0
		var y := signf(sy) * pow(absf(sy), 2.0 / p) * h / 2.0
		out.append(c + Vector3(x, y, 0))
	return out


## Skins consecutive rings (same vertex count) with flat-shaded quads.
func _loft(rings: Array, cap_start: bool, cap_end: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for k in rings.size() - 1:
		var a: PackedVector3Array = rings[k]
		var b: PackedVector3Array = rings[k + 1]
		var n := a.size()
		for i in n:
			var j := (i + 1) % n
			_tri(st, a[i], b[i], b[j])
			_tri(st, a[i], b[j], a[j])
	if cap_start:
		_fan(st, rings[0], true)
	if cap_end:
		_fan(st, rings[-1], false)
	st.generate_normals()
	return st.commit()


func _cap(ring: PackedVector3Array, flip: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	_fan(st, ring, flip)
	st.generate_normals()
	return st.commit()


func _fan(st: SurfaceTool, ring: PackedVector3Array, flip: bool) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	for i in ring.size():
		var j := (i + 1) % ring.size()
		if flip:
			_tri(st, c, ring[j], ring[i])
		else:
			_tri(st, c, ring[i], ring[j])


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Wing element: a thin cambered airfoil extruded across the car.
func _wing(c: Vector3, chord: float, pitch_deg: float, span: float) -> ArrayMesh:
	var prof := [Vector2(0, 0), Vector2(0.25, 0.022), Vector2(0.6, 0.02), Vector2(1.0, 0.0),
			Vector2(0.6, -0.006), Vector2(0.25, -0.01)]
	var rot := deg_to_rad(pitch_deg)
	var rings: Array = []
	for sx: float in [-span / 2.0, span / 2.0]:
		var ring := PackedVector3Array()
		for p: Vector2 in prof:
			var v := Vector2(p.x * chord, p.y * chord * 2.2).rotated(rot)
			ring.append(c + Vector3(sx, v.y, v.x))
		rings.append(ring)
	return _loft(rings, true, true)


## Flat plate of `thickness` through a planar outline (fins, endplates).
func _slab(pts: Array, thickness: float) -> ArrayMesh:
	var n := ((pts[1] - pts[0]) as Vector3).cross(pts[2] - pts[1]).normalized()
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	for p: Vector3 in pts:
		a.append(p - n * thickness / 2.0)
		b.append(p + n * thickness / 2.0)
	return _loft([a, b], true, true)


func _plate(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> ArrayMesh:
	return _slab([p0, p1, p2, p3], t)


## Vertical extrusion of an XZ outline between heights y0 and y1.
func _extrude_xz(outline: PackedVector2Array, y0: float, y1: float) -> ArrayMesh:
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	for p in outline:
		lo.append(Vector3(p.x, y0, p.y))
		hi.append(Vector3(p.x, y1, p.y))
	return _loft([lo, hi], true, true)


## Polygonal tube along a path.
func _tube(path: Array, r: float, sides: int) -> ArrayMesh:
	var rings: Array = []
	for i in path.size():
		var p: Vector3 = path[i]
		var t: Vector3 = ((path[mini(i + 1, path.size() - 1)] as Vector3) - (path[maxi(i - 1, 0)] as Vector3)).normalized()
		var up := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u := t.cross(up).normalized()
		var v := t.cross(u).normalized()
		var ring := PackedVector3Array()
		for k in sides:
			var a := TAU * k / sides
			ring.append(p + (u * cos(a) + v * sin(a)) * r)
		rings.append(ring)
	return _loft(rings, true, true)


func _box_mesh(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> ArrayMesh:
	var b := BoxMesh.new()
	b.size = size
	var st := SurfaceTool.new()
	st.append_from(b, 0, Transform3D(Basis.from_euler(rot), pos))
	return st.commit()


## Cylinder along X, centred on the parent's origin.
func _cyl(r: float, w: float, n: int, mat: Material) -> MeshInstance3D:
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	for i in n:
		var t := TAU * i / n
		a.append(Vector3(-w / 2.0, sin(t) * r, cos(t) * r))
		b.append(Vector3(w / 2.0, sin(t) * r, cos(t) * r))
	var mi := MeshInstance3D.new()
	mi.mesh = _loft([a, b], true, true)
	mi.material_override = mat
	return mi
