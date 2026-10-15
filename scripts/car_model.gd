extends Node3D
## Visual for a car. Uses res://assets/cars/car.glb if you drop one in,
## otherwise the built-in low-poly F1 car (scripts/lowpoly_car.gd).
## Convention: car faces -Z, origin on the ground between the axles.

## Drop a model at any of these paths and every car uses it. It is fitted
## automatically: longest side laid along the track, scaled to F1 length,
## centred and put on the ground.
const CUSTOM_MODELS := [
	"res://assets/cars/car.glb", "res://assets/cars/car.gltf",
	"res://assets/cars/car.fbx", "res://assets/cars/car.obj",
]
const TARGET_LENGTH := 5.6
## If the car drives backwards, set this to 180.
const CUSTOM_YAW_DEG := 0.0
## Materials whose names contain one of these get the team colour.
const PAINT_HINTS := ["body", "paint", "livery", "chassis", "main"]
const LowpolyCar = preload("res://scripts/lowpoly_car.gd")

var team_color := Color.RED
## Height of the tallest part, used to place the on-board camera.
var top_height := 1.06
var accent_color := Color.WHITE
var _lowpoly: Node3D


func _ready() -> void:
	for path: String in CUSTOM_MODELS:
		if ResourceLoader.exists(path):
			_load_custom(path)
			return
	_build_procedural()


func _load_custom(path: String) -> void:
	var res := load(path)
	var inst: Node3D
	if res is PackedScene:
		inst = res.instantiate()
	elif res is Mesh:  # .obj imports as a bare mesh
		inst = MeshInstance3D.new()
		inst.mesh = res
	else:
		push_warning("Unsupported car model %s, using built-in car" % path)
		_build_procedural()
		return
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(inst)
	# Lay the longest horizontal side along Z (the driving axis).
	var box := _local_aabb(holder)
	var yaw := PI / 2.0 if box.size.x > box.size.z else 0.0
	inst.rotation.y = yaw + deg_to_rad(CUSTOM_YAW_DEG)
	box = _local_aabb(holder)
	var s := TARGET_LENGTH / maxf(box.size.z, 0.001)
	var c := box.get_center()
	holder.scale = Vector3.ONE * s
	holder.position = -Vector3(c.x, box.position.y, c.z) * s
	top_height = box.size.y * s
	_paint(holder)


## Combined bounds of every mesh under `root`, in root's local space.
func _local_aabb(root: Node3D) -> AABB:
	var inv := root.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var b := (inv * mi.global_transform) * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _paint(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i) as BaseMaterial3D
			if m == null:
				continue
			# OBJ imports carry the material name on the surface, glTF on the material.
			var surface := ""
			if mi.mesh is ArrayMesh:
				surface = (mi.mesh as ArrayMesh).surface_get_name(i)
			var name := (m.resource_name + " " + surface + " " + mi.name).to_lower()
			for hint: String in PAINT_HINTS:
				if hint in name:
					var painted: BaseMaterial3D = m.duplicate()
					painted.albedo_color = team_color
					mi.set_surface_override_material(i, painted)
					break


func update_visual(steer: float, speed: float, dt: float) -> void:
	if _lowpoly:
		_lowpoly.update_wheels(steer, speed, dt)


## DRS flap and tyre stripes only exist on the built-in car.
func set_drs(open: bool) -> void:
	if _lowpoly:
		_lowpoly.set_drs(open)


func set_compound(color: Color) -> void:
	if _lowpoly:
		_lowpoly.set_compound(color)


func _build_procedural() -> void:
	_lowpoly = LowpolyCar.new()
	_lowpoly.team_color = team_color
	_lowpoly.accent_color = accent_color
	add_child(_lowpoly)
	top_height = 1.08
