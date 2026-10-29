extends Node3D
## Visual for a car. Uses res://assets/cars/car.glb if you drop one in,
## otherwise the built-in low-poly F1 car (scripts/lowpoly_car.gd).
## Convention: car faces -Z, origin on the ground between the axles.

## Drop a model at any of these paths and every car uses it. It is fitted
## automatically: longest side laid along the track, scaled to F1 length,
## centred and put on the ground.
const CUSTOM_MODELS := [
	"res://assets/cars/local/car.fbx", "res://assets/cars/local/car.glb",
	"res://assets/cars/car.glb", "res://assets/cars/car.gltf",
	"res://assets/cars/car.fbx", "res://assets/cars/car.obj",
]
const TARGET_LENGTH := 5.6
## If the car drives backwards, set this to 180.
const CUSTOM_YAW_DEG := 0.0
## Materials whose names contain one of these get the team colour.
const PAINT_HINTS := ["body", "paint", "livery", "chassis", "main"]
const LowpolyCar = preload("res://scripts/lowpoly_car.gd")
## Nodes named like this are wheels (spun and steered); front ones are the
## pair furthest forward.
const WHEEL_NAME := "^(wheel|tyre|tire)[_.\\-]?\\d*$"
## Node that opens for DRS (rear-wing top element).
const FLAP_NAMES := ["drs", "flap", "spoiler_002"]
## Wing parts, baked separately so damage can bend or knock them off.
const FRONT_WING_NAMES := ["front_wing", "frontwing", "front_spoiler"]
const REAR_WING_NAMES := ["rear_wing", "rearwing", "spoiler"]
## Texture-atlas models (one shared material) are recoloured by this shader:
## near-white paint becomes the team colour, the red stripes the accent.
const LIVERY_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : filter_linear_mipmap, repeat_enable;
uniform vec3 paint = vec3(1.0, 0.0, 0.0);
uniform vec3 accent = vec3(1.0);
uniform bool repaint = true;
void fragment() {
	vec3 c = texture(atlas, UV).rgb;  // sRGB, compared as authored
	float mx = max(c.r, max(c.g, c.b));
	float sat = (mx - min(c.r, min(c.g, c.b))) / max(mx, 0.001);
	vec3 o = c;
	if (repaint) {
		float white = smoothstep(0.62, 0.72, mx) * (1.0 - smoothstep(0.08, 0.16, sat));
		float red = step(0.3, c.r) * step(c.g * 2.5, c.r) * step(c.b * 2.5, c.r);
		o = mix(o, paint * clamp(mx / 0.8, 0.0, 1.1), white);
		o = mix(o, accent * clamp(mx / 0.53, 0.0, 1.1), red);
	}
	ALBEDO = pow(o, vec3(2.2));
	ROUGHNESS = 0.42;
	METALLIC = 0.15;
}
"""
static var _shader: Shader
## Baked model per path: body mesh, wheels and flap, shared by every car.
static var _baked := {}

var team_color := Color.RED
## Height of the tallest part, used to place the on-board camera.
var top_height := 1.06
var accent_color := Color.WHITE
var _lowpoly: Node3D
var _wheels: Array = []  # [{node, base, center, front}]
var _flap: Dictionary = {}  # {node, base, pivot}
var _spin := 0.0
var _steer_vis := 0.0
var _drs_amt := 0.0
var _drs_open := false
var _wheel_radius := 0.36
var _parts := {}  # "front_wing"/"rear_wing" -> {node, base, pivot}
var _susp := {"susp_l": 0.0, "susp_r": 0.0}
var _twist := 0.0
var _smoke: CPUParticles3D
static var _bits_mesh: Mesh
static var _bits_mat: Material


func _ready() -> void:
	_twist = randf_range(-1.0, 1.0)
	for path: String in CUSTOM_MODELS:
		if ResourceLoader.exists(path):
			_load_custom(path)
			return
	_build_procedural()


func _load_custom(path: String) -> void:
	if not _baked.has(path):
		_baked[path] = _bake(path)
	var bake: Dictionary = _baked[path]
	if bake.is_empty():
		_load_custom_plain(path)
		return
	var mat: Material = bake.mat0
	if bake.atlas != null:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = LIVERY_SHADER
		var sm := ShaderMaterial.new()
		sm.shader = _shader
		sm.set_shader_parameter("atlas", bake.atlas)
		sm.set_shader_parameter("paint", Vector3(team_color.r, team_color.g, team_color.b))
		sm.set_shader_parameter("accent", Vector3(accent_color.r, accent_color.g, accent_color.b))
		mat = sm
		if not bake.has("plain_mat"):
			var plain: ShaderMaterial = sm.duplicate()
			plain.set_shader_parameter("repaint", false)
			bake["plain_mat"] = plain
	var body := MeshInstance3D.new()
	body.mesh = bake.body
	body.material_override = mat
	add_child(body)
	for w: Dictionary in bake.wheels:
		var mi := MeshInstance3D.new()
		mi.mesh = w.mesh
		mi.material_override = bake.get("plain_mat", mat)
		mi.transform = w.base
		add_child(mi)
		_wheels.append({"node": mi, "base": w.base, "center": w.center, "front": w.front})
	if not bake.flap.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = bake.flap.mesh
		mi.material_override = mat
		mi.transform = bake.flap.base
		add_child(mi)
		_flap = {"node": mi, "base": bake.flap.base, "pivot": bake.flap.pivot}
	for part: String in ["front_wing", "rear_wing"]:
		var g: Dictionary = bake[part]
		if g.is_empty():
			continue
		var wmi := MeshInstance3D.new()
		wmi.mesh = g.mesh
		wmi.material_override = mat
		add_child(wmi)
		_parts[part] = {"node": wmi, "base": Transform3D.IDENTITY, "pivot": g.pivot}
	top_height = bake.top
	_wheel_radius = bake.radius


## Loads a model once, fits it (longest side along Z, F1 length, on the
## ground) and bakes everything that doesn't move into a single mesh.
## Returns {} when the model has no recognisable wheels.
static func _bake(path: String) -> Dictionary:
	var res := load(path)
	if not res is PackedScene:
		return {}
	var root := Node3D.new()
	var inst: Node3D = res.instantiate()
	root.add_child(inst)
	var re := RegEx.create_from_string("(?i)" + WHEEL_NAME)
	var parts: Array[MeshInstance3D] = []
	var wheel_parts: Array[MeshInstance3D] = []
	var flap_part: MeshInstance3D = null
	var front_parts: Array[MeshInstance3D] = []
	var rear_parts: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var nm := String(mi.name).to_lower()
		if re.search(nm):
			wheel_parts.append(mi)
		elif flap_part == null and FLAP_NAMES.any(func(h: String) -> bool: return h in nm):
			flap_part = mi
		elif FRONT_WING_NAMES.any(func(h: String) -> bool: return h in nm):
			front_parts.append(mi)
		elif REAR_WING_NAMES.any(func(h: String) -> bool: return h in nm):
			rear_parts.append(mi)
		else:
			parts.append(mi)
	if wheel_parts.size() < 4:
		root.free()
		return {}
	# Transforms relative to `root`, computed by hand (nothing is in the tree).
	var rel := func(n: Node3D) -> Transform3D:
		var t := Transform3D.IDENTITY
		var cur: Node = n
		while cur != root:
			t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		return t
	var all: Array[MeshInstance3D] = parts + wheel_parts + front_parts + rear_parts
	if flap_part:
		all.append(flap_part)
	var box := AABB()
	for k in all.size():
		var b: AABB = rel.call(all[k]) * all[k].get_aabb()
		box = b if k == 0 else box.merge(b)
	var fit := Transform3D.IDENTITY
	if box.size.x > box.size.z:
		fit = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3.ZERO)
	fit = Transform3D(Basis(Vector3.UP, deg_to_rad(CUSTOM_YAW_DEG)), Vector3.ZERO) * fit
	box = fit * box
	var s := TARGET_LENGTH / maxf(box.size.z, 0.001)
	var c := box.get_center()
	fit = Transform3D(Basis().scaled(Vector3.ONE * s), -Vector3(c.x, box.position.y, c.z) * s) * fit
	var atlas: Texture2D = null
	var mat0: Material = null
	var st := SurfaceTool.new()
	for mi in parts:
		var t: Transform3D = fit * rel.call(mi)
		for i in mi.mesh.get_surface_count():
			st.append_from(mi.mesh, i, t)
			var m := mi.get_active_material(i)
			if mat0 == null:
				mat0 = m
			if atlas == null and m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture:
				atlas = (m as BaseMaterial3D).albedo_texture
	var out := {"body": st.commit(), "atlas": atlas, "mat0": mat0, "wheels": [], "flap": {},
			"front_wing": _bake_group(front_parts, fit, rel, true),
			"rear_wing": _bake_group(rear_parts, fit, rel, false),
			"top": box.size.y * s}
	var zs: Array[float] = []
	for mi in wheel_parts:
		var t: Transform3D = fit * rel.call(mi)
		zs.append((t * mi.get_aabb().get_center()).z)
	var sorted_z := zs.duplicate()
	sorted_z.sort()
	var front_limit: float = (sorted_z[1] + sorted_z[2]) / 2.0
	var radius := 0.0
	for k in wheel_parts.size():
		var mi := wheel_parts[k]
		var t: Transform3D = fit * rel.call(mi)
		var wb := t * mi.get_aabb()
		radius = maxf(radius, wb.size.y / 2.0)
		out.wheels.append({"mesh": mi.mesh, "base": t, "center": wb.get_center(), "front": zs[k] < front_limit})
	out["radius"] = radius
	if flap_part:
		var t: Transform3D = fit * rel.call(flap_part)
		var fb := t * flap_part.get_aabb()
		# Hinge on the leading edge, like a real DRS flap.
		out.flap = {"mesh": flap_part.mesh, "base": t,
				"pivot": Vector3(fb.get_center().x, fb.get_center().y, fb.position.z)}
	root.free()
	return out


## One mesh for a wing assembly plus the point it hinges on when bent
## (where it meets the nose, or the bottom of the rear wing).
static func _bake_group(group: Array[MeshInstance3D], fit: Transform3D, rel: Callable, front: bool) -> Dictionary:
	if group.is_empty():
		return {}
	var st := SurfaceTool.new()
	var box := AABB()
	for k in group.size():
		var mi := group[k]
		var t: Transform3D = fit * rel.call(mi)
		for i in mi.mesh.get_surface_count():
			st.append_from(mi.mesh, i, t)
		var b := t * mi.get_aabb()
		box = b if k == 0 else box.merge(b)
	var c := box.get_center()
	var pivot := Vector3(c.x, c.y, box.end.z) if front else Vector3(c.x, box.position.y, c.z)
	return {"mesh": st.commit(), "pivot": pivot}


## Fallback for models without separate wheels: auto-fit and paint by name.
func _load_custom_plain(path: String) -> void:
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
		return
	if _wheels.is_empty():
		return
	_spin = fposmod(_spin - speed / _wheel_radius * dt, TAU)
	_steer_vis = lerpf(_steer_vis, steer * 0.38, clampf(dt * 12.0, 0.0, 1.0))
	for w: Dictionary in _wheels:
		var ctr: Vector3 = w.center
		var r := Basis(Vector3.RIGHT, _spin)
		if w.front:
			r = Basis(Vector3.UP, -_steer_vis) * r
		# Bent suspension: the wheel leans over.
		var bent: float = _susp.susp_r if ctr.x > 0.0 else _susp.susp_l
		if bent > 0.0:
			r = Basis(Vector3.BACK, signf(ctr.x) * bent * 0.3) * r
		w.node.transform = Transform3D(r, ctr - r * ctr) * w.base
	if not _flap.is_empty() and _flap.node.visible:
		_drs_amt = move_toward(_drs_amt, 1.0 if _drs_open else 0.0, dt * 5.0)
		var pv: Vector3 = _flap.pivot
		var fr := Basis(Vector3.RIGHT, -0.45 * _drs_amt)
		_flap.node.transform = Transform3D(fr, pv - fr * pv) * _flap.base


## Tyre stripes only exist on the built-in car.
func set_drs(open: bool) -> void:
	_drs_open = open
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
	_parts["front_wing"] = {"node": _lowpoly.front_wing, "base": Transform3D.IDENTITY, "pivot": Vector3(0, 0.15, -2.45)}
	_parts["rear_wing"] = {"node": _lowpoly.rear_wing, "base": Transform3D.IDENTITY, "pivot": Vector3(0, 0.4, 2.3)}


# ------------------------------------------------------------ damage

## Bend a part by `amount` (0..1): wings droop and twist, wheels lean.
func set_part_damage(part: String, amount: float) -> void:
	if _susp.has(part):
		_susp[part] = amount
		return
	if not _parts.has(part):
		return
	var p: Dictionary = _parts[part]
	var front := part == "front_wing"
	var r := Basis(Vector3.RIGHT, (-0.3 if front else 0.3) * amount) \
			* Basis(Vector3.UP, 0.12 * amount * _twist) * Basis(Vector3.BACK, 0.15 * amount * _twist)
	var pv: Vector3 = p.pivot
	p.node.transform = Transform3D(r, pv - r * pv) * p.base


## Knock a part off: hides it and returns a copy (transform = its world
## transform) for the caller to send tumbling down the track.
func detach_part(part: String) -> Node3D:
	if not _parts.has(part) or not _parts[part].node.visible:
		return null
	var node: Node3D = _parts[part].node
	var copy: Node3D = node.duplicate()
	copy.transform = node.global_transform
	node.visible = false
	if part == "rear_wing" and not _flap.is_empty():
		_flap.node.visible = false
	return copy


## Fresh part fitted in the pits.
func repair_part(part: String) -> void:
	if not _parts.has(part):
		return
	var p: Dictionary = _parts[part]
	p.node.visible = true
	p.node.transform = p.base
	if part == "rear_wing" and not _flap.is_empty():
		_flap.node.visible = true


## A spray of carbon bits where the car hit something.
func debris_burst(at: Vector3, vel: Vector3) -> void:
	if _bits_mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.02, 0.06)
		_bits_mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.08, 0.08, 0.09)
		m.roughness = 0.4
		_bits_mat = m
	var p := CPUParticles3D.new()
	p.mesh = _bits_mesh
	p.material_override = _bits_mat
	p.amount = 16
	p.lifetime = 1.3
	p.one_shot = true
	p.explosiveness = 0.9
	p.direction = (vel.normalized() + Vector3.UP).normalized() if vel.length() > 0.1 else Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var scene := get_tree().current_scene
	scene.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


## Grey smoke from the back of a broken car.
func smoke(on: bool) -> void:
	if on and _smoke == null:
		_smoke = CPUParticles3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		_smoke.mesh = q
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		_smoke.material_override = m
		_smoke.amount = 28
		_smoke.lifetime = 2.6
		_smoke.position = Vector3(0, 0.7, 2.0)
		_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_smoke.emission_sphere_radius = 0.3
		_smoke.direction = Vector3.UP
		_smoke.spread = 25.0
		_smoke.gravity = Vector3(0, 0.8, 0)
		_smoke.initial_velocity_min = 1.0
		_smoke.initial_velocity_max = 2.5
		_smoke.scale_amount_min = 1.2
		_smoke.scale_amount_max = 2.6
		var grow := Curve.new()
		grow.add_point(Vector2(0, 0.4))
		grow.add_point(Vector2(1, 1.6))
		_smoke.scale_amount_curve = grow
		var fade := Gradient.new()
		fade.set_color(0, Color(0.35, 0.35, 0.36, 0.7))
		fade.set_color(1, Color(0.55, 0.55, 0.56, 0.0))
		_smoke.color_ramp = fade
		add_child(_smoke)
	if _smoke:
		_smoke.emitting = on
