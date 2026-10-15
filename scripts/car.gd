extends CharacterBody3D
## Arcade open-wheel car: bicycle-model steering, speed-dependent aero grip,
## grass penalty, lap/progress tracking. Driven by the player or by the AI.

const Track = preload("res://scripts/track.gd")
const CarModel = preload("res://scripts/car_model.gd")

const WHEELBASE := 3.6
const MAX_ACCEL := 13.0  # m/s^2 at low speed (traction limited)
const TOP_SPEED := 110.0  # theoretical; drag caps it around 335 km/h
const REVERSE_SPEED := 8.0
const GEAR_TOPS := [22.0, 32.0, 42.0, 52.0, 62.0, 72.0, 81.0, 100.0]

var track: Track
var driver_name := ""
var is_player := false
var controls_enabled := false
var ai_skill := 0.95
var ai_line := 0.0  # preferred lateral offset
var braking_assist := false
var steering_mode := 0  # 0 touch/keys, 1 tilt, 2 tilt inverted
var others: Array = []  # other cars, for AI avoidance

# Inputs (0..1, steer -1..1)
var steer := 0.0
var throttle := 0.0
var brake := 0.0

# Telemetry
var speed := 0.0  # forward m/s
var gear := 1
var rpm := 4000.0
var on_grass := false
var wrong_way := false
var skid := 0.0  # 0..1, drives the tyre-squeal sound
var _impact_cooldown := 0.0

# Race tracking
var track_idx := 0
var lap_pos := 0.0  # distance along current lap
var lateral := 0.0
var lap := 0  # 0 = on the grid, 1 = first racing lap
var race_dist := 0.0
var lap_start_time := 0.0
var lap_times: Array[float] = []
var best_lap := INF
var finished := false
var finish_time := 0.0
var clock := 0.0  # game time; stops while paused, unlike wall-clock time
var _stuck_time := 0.0
var _max_lap := 0

signal lap_completed(car, lap_time: float)
signal crossed_finish(car)
signal impact(strength: float)

var model: Node3D


func setup(p_track: Track, color: Color, slot: int) -> void:
	track = p_track
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.0, 5.4)
	shape.shape = box
	shape.position = Vector3(0, 0.5, 0.15)
	add_child(shape)
	model = CarModel.new()
	model.team_color = color
	add_child(model)
	place_on_grid(slot)


func place_on_grid(slot: int) -> void:
	global_transform = track.transform_at(-track.grid_distance(slot), track.grid_lateral(slot))
	velocity = Vector3.ZERO
	track_idx = track.closest_index_global(global_position)
	_update_track_state()
	lap = 0
	race_dist = lap_pos - track.length


func start_lap_timer() -> void:
	lap_start_time = clock


func _physics_process(dt: float) -> void:
	if track == null:
		return
	clock += dt
	if not controls_enabled and not finished:
		# Held on the grid: no creeping, no reversing.
		velocity = Vector3.ZERO
		speed = 0.0
		throttle = 0.0
		_update_gear()
		return
	if finished and is_player:
		_ai_input()  # the car drives itself on the cool-down lap
	elif is_player:
		_player_input(dt)
	else:
		_ai_input()
	_integrate(dt)
	_update_track_state()
	if model:
		model.update_visual(steer, speed, dt)


func _player_input(dt: float) -> void:
	var target := Input.get_axis("steer_left", "steer_right")
	if steering_mode > 0 and absf(target) < 0.01:
		# Godot rotates sensor axes to match the screen, so steering-wheel
		# style rolling shows up on x. Sign differs between devices, hence
		# the "inverted" option in the menu.
		var tilt := Input.get_accelerometer().x / 4.5
		if steering_mode == 2:
			tilt = -tilt
		if absf(tilt) < 0.04:
			tilt = 0.0
		target = clampf(tilt, -1.0, 1.0)
	steer = move_toward(steer, target, dt * 5.0)
	throttle = Input.get_action_strength("accelerate")
	brake = Input.get_action_strength("brake")
	if braking_assist and speed > 15.0:
		var limit := _target_speed_ahead() * 1.04
		if speed > limit:
			throttle = 0.0
			brake = maxf(brake, clampf((speed - limit) / 6.0, 0.3, 1.0))


## Slowest planned speed over the next few track points.
func _target_speed_ahead() -> float:
	var n := track.points.size()
	var v := INF
	for o in range(1, 5):
		v = minf(v, track.target_speed[(track_idx + o) % n])
	return v


func _ai_input() -> void:
	var look := clampf(absf(speed) * 0.32, 6.0, 30.0)
	var line := ai_line
	# Very simple overtaking/avoidance: pick the other side of a car ahead.
	for o in others:
		if o == self:
			continue
		var gap: float = o.race_dist - race_dist
		if gap > 0.0 and gap < 22.0 and absf(o.lateral - lateral) < 2.4:
			var hw := track.half_width(track_idx, o.lateral) - 1.5
			line = clampf(o.lateral + (3.2 if o.lateral < 0.0 else -3.2), -hw, hw)
	var target := track.point_at(lap_pos + look, line)
	var local := global_transform.affine_inverse() * target
	var angle := atan2(local.x, -local.z)
	steer = clampf(angle * 3.0, -1.0, 1.0)
	var v_target := _target_speed_ahead() * ai_skill
	if on_grass:
		v_target = minf(v_target, 25.0)
	if speed < v_target - 1.0:
		throttle = 1.0
		brake = 0.0
	elif speed > v_target + 1.5:
		throttle = 0.0
		brake = clampf((speed - v_target) / 8.0, 0.25, 1.0)
	else:
		throttle = 0.5
		brake = 0.0
	# Lift when running out of road on corner exit instead of going off.
	var room := track.half_width(track_idx, lateral) - absf(lateral)
	if room < 1.0 and absf(steer) > 0.3:
		throttle = minf(throttle, 0.3)
	# Recover when stuck against a wall.
	if controls_enabled and absf(speed) < 2.0:
		_stuck_time += get_physics_process_delta_time()
		if _stuck_time > 2.5:
			reset_to_track()
	else:
		_stuck_time = 0.0


func grip_accel(v: float) -> float:
	return Track.GRIP_BASE + Track.GRIP_AERO * v * v


func _integrate(dt: float) -> void:
	var basis := global_transform.basis
	var fwd := -basis.z
	var right := basis.x
	var v_long := velocity.dot(fwd)
	var v_lat := velocity.dot(right)
	var grip_mul := 0.5 if on_grass else 1.0

	# Longitudinal
	var accel := 0.0
	if throttle > 0.01 and v_long > -0.5:
		var ratio := clampf(v_long / TOP_SPEED, 0.0, 1.0)
		accel += throttle * MAX_ACCEL * (1.0 - ratio * ratio) * (0.6 if on_grass else 1.0)
	if brake > 0.01:
		if v_long > 0.5:
			accel -= brake * (18.0 + 0.35 * v_long) * (0.5 if on_grass else 1.0)
		elif throttle < 0.01 and v_long > -REVERSE_SPEED:
			accel -= brake * 6.0  # reverse
		elif v_long < -0.5:
			accel += brake * 10.0
	# Aero drag + rolling resistance, plus heavy drag on grass.
	var drag := 0.25 + 0.0004 * v_long * v_long
	if on_grass:
		drag += 0.004 * v_long * v_long + 2.0
	accel -= signf(v_long) * drag
	var new_v := v_long + accel * dt
	if signf(new_v) != signf(v_long) and absf(v_long) > 0.01 and throttle < 0.01 and brake < 0.01:
		new_v = 0.0
	v_long = new_v

	# Steering (bicycle model), clamped by available lateral grip.
	var vabs := absf(v_long)
	var max_angle := lerpf(0.42, 0.05, clampf(vabs / 75.0, 0.0, 1.0))
	var yaw_rate := -v_long * tan(steer * max_angle) / WHEELBASE
	var yaw_cap := grip_accel(vabs) * grip_mul / maxf(vabs, 0.5)
	# Tyres squeal when asked for more than the grip gives, or under hard braking.
	var over := absf(yaw_rate) / yaw_cap - 1.0
	var target_skid := clampf(over * 2.0, 0.0, 1.0) if vabs > 12.0 and not on_grass else 0.0
	if brake > 0.7 and v_long > 25.0 and not on_grass:
		target_skid = maxf(target_skid, 0.5)
	skid = move_toward(skid, target_skid, dt * 4.0)
	yaw_rate = clampf(yaw_rate, -yaw_cap, yaw_cap)
	rotate_y(yaw_rate * dt)

	basis = global_transform.basis
	fwd = -basis.z
	right = basis.x
	v_lat *= exp(-dt * 10.0 * grip_mul)
	velocity = fwd * v_long + right * v_lat
	velocity.y = 0.0
	move_and_slide()
	# Scrub speed on wall hits so contact hurts.
	_impact_cooldown -= dt
	for c in get_slide_collision_count():
		var col := get_slide_collision(c)
		var hit := absf(col.get_normal().dot(fwd))
		var strength := hit * absf(v_long)
		if strength > 2.0 and _impact_cooldown <= 0.0:
			impact.emit(strength)
			_impact_cooldown = 0.4
		velocity *= 1.0 - 0.5 * hit * dt * 10.0
	global_position.y = 0.0
	speed = velocity.dot(-global_transform.basis.z)
	_update_gear()


func _update_gear() -> void:
	var v := absf(speed)
	gear = GEAR_TOPS.size()
	for g in GEAR_TOPS.size():
		if v < GEAR_TOPS[g]:
			gear = g + 1
			break
	var lo: float = 0.0 if gear == 1 else GEAR_TOPS[gear - 2]
	var hi: float = GEAR_TOPS[gear - 1]
	var t := clampf((v - lo) / (hi - lo), 0.0, 1.0)
	var base := 4000.0 if gear == 1 else 8500.0
	rpm = lerpf(base, 12000.0, t) if throttle > 0.05 or v > 3.0 else 4000.0


func _update_track_state() -> void:
	track_idx = track.closest_index_local(global_position, track_idx)
	var prev_pos := lap_pos
	var proj := track.project(global_position, track_idx)
	lap_pos = proj.x
	lateral = proj.y
	var L := track.length
	if prev_pos > L * 0.75 and lap_pos < L * 0.25:
		_on_cross_line()
	elif prev_pos < L * 0.25 and lap_pos > L * 0.75 and lap > 0:
		lap -= 1  # reversed back over the line
	race_dist = (lap - 1) * L + lap_pos
	var hw := track.half_width(track_idx, lateral)
	on_grass = absf(lateral) > hw + Track.KERB_WIDTH * 0.8
	wrong_way = absf(speed) > 5.0 and (-global_transform.basis.z).dot(track.tangents[track_idx]) < -0.3
	if absf(lateral) > hw + Track.KERB_WIDTH + Track.RUNOFF + 25.0:
		reset_to_track()


func _on_cross_line() -> void:
	lap += 1
	if lap <= _max_lap:
		return  # re-crossing after reversing or a reset
	_max_lap = lap
	if lap <= 1:
		return
	var t := clock - lap_start_time
	lap_start_time = clock
	if not finished:
		lap_times.append(t)
		best_lap = minf(best_lap, t)
		lap_completed.emit(self, t)
	crossed_finish.emit(self)


func reset_to_track() -> void:
	_stuck_time = 0.0
	var s := lap_pos - 15.0
	global_transform = track.transform_at(s, 0.0)
	velocity = Vector3.ZERO
	speed = 0.0
	track_idx = track.closest_index_local(global_position, track_idx, 30)
	var proj := track.project(global_position, track_idx)
	# Don't let a reset count as crossing the line.
	if lap_pos < track.length * 0.25 and proj.x > track.length * 0.75:
		lap -= 1
	lap_pos = proj.x
	lateral = proj.y
