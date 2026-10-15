extends Node3D
## Visual for a car. Uses res://assets/cars/car.glb if you drop one in,
## otherwise builds a low-poly open-wheel car from primitives.
## Convention: car faces -Z, origin on the ground between the axles.

const CUSTOM_MODEL := "res://assets/cars/car.glb"
## Tweak these to fit whatever model you download.
const CUSTOM_SCALE := 1.0
const CUSTOM_YAW_DEG := 0.0
const CUSTOM_OFFSET := Vector3.ZERO
const WHEEL_RADIUS := 0.36

var team_color := Color.RED
var _front_wheels: Array[Node3D] = []
var _all_wheels: Array[Node3D] = []
var _spin := 0.0


func _ready() -> void:
	if ResourceLoader.exists(CUSTOM_MODEL):
		var scene: PackedScene = load(CUSTOM_MODEL)
		var inst := scene.instantiate() as Node3D
		inst.scale = Vector3.ONE * CUSTOM_SCALE
		inst.rotation_degrees.y = CUSTOM_YAW_DEG
		inst.position = CUSTOM_OFFSET
		add_child(inst)
		return
	_build_procedural()


func update_visual(steer: float, speed: float, dt: float) -> void:
	_spin = fmod(_spin + speed / WHEEL_RADIUS * dt, TAU)
	for w in _all_wheels:
		w.get_child(0).rotation.x = -_spin
	for w in _front_wheels:
		w.rotation.y = -steer * 0.35


func _mat(color: Color, metallic := 0.0, roughness := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _build_procedural() -> void:
	var paint := _mat(team_color, 0.35, 0.3)
	var carbon := _mat(Color(0.06, 0.06, 0.07), 0.2, 0.55)
	var accent := _mat(team_color.lightened(0.35), 0.35, 0.3)

	# Floor / plank
	_box(Vector3(1.5, 0.05, 3.6), Vector3(0, 0.07, 0.35), carbon)
	# Monocoque / survival cell
	_box(Vector3(0.75, 0.42, 2.2), Vector3(0, 0.36, -0.05), paint)
	# Nose cone: cylinder tipped forward and squashed
	var nose := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.3
	cyl.height = 1.7
	cyl.radial_segments = 12
	nose.mesh = cyl
	nose.material_override = paint
	nose.rotation_degrees = Vector3(-93, 0, 0)
	nose.scale = Vector3(1.0, 1.0, 0.65)
	nose.position = Vector3(0, 0.3, -1.95)
	add_child(nose)
	# Front wing: main plane, flap, endplates
	_box(Vector3(1.95, 0.035, 0.42), Vector3(0, 0.1, -2.75), carbon)
	_box(Vector3(1.8, 0.03, 0.2), Vector3(0, 0.17, -2.62), accent, Vector3(deg_to_rad(-18), 0, 0))
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.03, 0.26, 0.55), Vector3(0.97 * sx, 0.18, -2.72), carbon)
	# Sidepods (tapered look from two boxes)
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.5, 0.4, 1.2), Vector3(0.6 * sx, 0.3, 0.05), paint)
		_box(Vector3(0.38, 0.28, 0.9), Vector3(0.5 * sx, 0.26, 1.05), paint)
		# Inlet
		_box(Vector3(0.42, 0.22, 0.02), Vector3(0.62 * sx, 0.36, -0.56), carbon)
	# Engine cover and fin
	_box(Vector3(0.55, 0.5, 1.5), Vector3(0, 0.5, 1.0), paint)
	_box(Vector3(0.04, 0.35, 1.3), Vector3(0, 0.88, 1.25), paint)
	# Airbox over the driver's head
	_box(Vector3(0.32, 0.38, 0.55), Vector3(0, 0.85, 0.35), carbon)
	# Driver helmet
	var helmet := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.15
	sph.height = 0.3
	helmet.mesh = sph
	helmet.material_override = _mat(Color(1.0, 0.85, 0.1), 0.1, 0.25)
	helmet.position = Vector3(0, 0.7, -0.15)
	add_child(helmet)
	# Halo: torus ring + centre pillar
	var halo := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.3
	tor.outer_radius = 0.35
	tor.rings = 16
	tor.ring_segments = 6
	halo.mesh = tor
	halo.material_override = carbon
	halo.position = Vector3(0, 0.84, -0.12)
	halo.scale = Vector3(1.0, 1.0, 1.35)
	add_child(halo)
	_box(Vector3(0.05, 0.3, 0.05), Vector3(0, 0.7, -0.6), carbon, Vector3(deg_to_rad(-25), 0, 0))
	# Rear wing: two elements, endplates, pylon
	_box(Vector3(1.0, 0.04, 0.38), Vector3(0, 0.92, 2.3), carbon)
	_box(Vector3(1.0, 0.03, 0.22), Vector3(0, 1.04, 2.2), accent, Vector3(deg_to_rad(20), 0, 0))
	for sx in [-1.0, 1.0]:
		_box(Vector3(0.03, 0.55, 0.65), Vector3(0.51 * sx, 0.8, 2.25), paint)
	_box(Vector3(0.06, 0.45, 0.12), Vector3(0, 0.62, 2.1), carbon)
	# Diffuser hint
	_box(Vector3(1.0, 0.2, 0.25), Vector3(0, 0.15, 2.3), carbon, Vector3(deg_to_rad(20), 0, 0))
	# Suspension arms (just thin boxes)
	for wz in [-1.6, 1.9]:
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.6, 0.03, 0.06), Vector3(0.6 * sx, 0.38, wz), carbon)

	# Wheels
	var tyre := _mat(Color(0.08, 0.08, 0.08), 0.0, 0.85)
	var rim := _mat(Color(0.75, 0.75, 0.78), 0.8, 0.3)
	for spec in [[-0.86, -1.6, 0.36, true], [0.86, -1.6, 0.36, true], [-0.84, 1.9, 0.44, false], [0.84, 1.9, 0.44, false]]:
		var pivot := Node3D.new()
		pivot.position = Vector3(spec[0], WHEEL_RADIUS, spec[1])
		add_child(pivot)
		var spin := Node3D.new()
		pivot.add_child(spin)
		var wheel := MeshInstance3D.new()
		var wc := CylinderMesh.new()
		wc.top_radius = WHEEL_RADIUS
		wc.bottom_radius = WHEEL_RADIUS
		wc.height = spec[2]
		wc.radial_segments = 16
		wheel.mesh = wc
		wheel.material_override = tyre
		wheel.rotation_degrees.z = 90
		spin.add_child(wheel)
		# Rim face + a spoke bar so rotation is visible
		var rim_mi := MeshInstance3D.new()
		var rc := CylinderMesh.new()
		rc.top_radius = WHEEL_RADIUS * 0.62
		rc.bottom_radius = WHEEL_RADIUS * 0.62
		rc.height = spec[2] + 0.01
		rc.radial_segments = 12
		rim_mi.mesh = rc
		rim_mi.material_override = rim
		rim_mi.rotation_degrees.z = 90
		spin.add_child(rim_mi)
		var spoke := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(spec[2] + 0.02, WHEEL_RADIUS * 1.1, 0.06)
		spoke.mesh = sb
		spoke.material_override = tyre
		spin.add_child(spoke)
		_all_wheels.append(pivot)
		if spec[3]:
			_front_wheels.append(pivot)
