extends Camera3D
## Smooth chase camera with speed-based FOV, plus a cockpit (T-cam) view.

enum Mode { CHASE, FAR_CHASE, COCKPIT }

var target: Node3D
var mode := Mode.CHASE

var _initialized := false


func _ready() -> void:
	top_level = true
	near = 0.1
	far = 3000.0
	current = true


func cycle_mode() -> void:
	mode = ((mode + 1) % Mode.size()) as Mode
	_initialized = false


func _physics_process(dt: float) -> void:
	if target == null:
		return
	var t := target.global_transform
	var fwd := -t.basis.z
	var speed: float = target.get("speed") if target.get("speed") != null else 0.0
	fov = lerpf(fov, 68.0 + clampf(absf(speed) / 90.0, 0.0, 1.0) * 10.0, dt * 3.0)
	match mode:
		Mode.COCKPIT:
			global_transform = Transform3D(t.basis, t * Vector3(0, 1.12, -0.05))
			rotate_object_local(Vector3.RIGHT, deg_to_rad(-3.0))
		_:
			var dist := 6.5 if mode == Mode.CHASE else 11.0
			var height := 2.1 if mode == Mode.CHASE else 3.6
			var desired := t.origin - fwd * dist + Vector3.UP * height
			if not _initialized:
				global_position = desired
				_initialized = true
			# Stiff follow so the car stays framed at 300 km/h.
			# Follow rigidly along the car's motion, smooth only the rest, so
			# the car doesn't shrink into the distance at 300 km/h.
			var vel: Vector3 = target.get("velocity") if target.get("velocity") != null else Vector3.ZERO
			global_position += vel * dt
			global_position = global_position.lerp(desired, clampf(dt * 8.0, 0.0, 1.0))
			look_at(t.origin + fwd * 4.0 + Vector3.UP * 0.9, Vector3.UP)
