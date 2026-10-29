extends Node3D
## A broken-off part tumbling down the track: simple ballistic motion that
## bounces on the road surface (the track has no ground collider).

const LIFETIME := 40.0

var track: Node
var velocity := Vector3.ZERO
var spin := Vector3.ZERO  # angular velocity, rad/s
var _age := 0.0
var _hint := -1


func _physics_process(dt: float) -> void:
	_age += dt
	if _age > LIFETIME:
		queue_free()
		return
	if velocity.length_squared() < 0.01 and spin.length_squared() < 0.01:
		return  # at rest
	velocity.y -= 9.81 * dt
	velocity *= 1.0 - 0.3 * dt  # air drag
	global_position += velocity * dt
	if spin.length_squared() > 0.0001:
		global_rotate(spin.normalized(), spin.length() * dt)
	var ground := _ground_y()
	if global_position.y < ground + 0.08:
		global_position.y = ground + 0.08
		if velocity.y < -1.0:
			velocity.y = -velocity.y * 0.3
		else:
			velocity.y = 0.0
		velocity.x *= 0.6
		velocity.z *= 0.6
		spin *= 0.55
		if Vector2(velocity.x, velocity.z).length() < 0.4 and absf(velocity.y) < 0.5:
			velocity = Vector3.ZERO
			spin = Vector3.ZERO


func _ground_y() -> float:
	if track == null:
		return 0.0
	var pos := global_position
	_hint = track.closest_index_global(pos) if _hint < 0 else track.closest_index_local(pos, _hint)
	var proj: Vector2 = track.project(pos, _hint)
	return track.ground_height(proj.x, proj.y)
