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
var braking_assist := 0  # 0 off, 1 low, 2 high
var steering_mode := 0  # 0 arrows, 1 wheel, 2 tilt
var tilt_invert := false
var steer_sensitivity := 1.0
var steer_assist := 0  # 0 off, 1 low, 2 high
var auto_throttle := false
var tilt_neutral := 0.0  # roll angle that counts as "straight"

const TILT_FULL_LOCK := 32.0  # degrees of roll for full lock at sensitivity 1
const STEER_ASSIST_BLEND := [0.0, 0.3, 0.6]
const STEER_ASSIST_EDGE := [0.0, 0.5, 1.0]
const BRAKE_ASSIST_MARGIN := [INF, 1.10, 1.03]  # how far over the safe speed before it brakes
var others: Array = []  # other cars, for AI avoidance

# Inputs (0..1, steer -1..1)
var steer := 0.0
var throttle := 0.0
var brake := 0.0

# Telemetry
var speed := 0.0  # forward m/s
var gear := 1
var rpm := 4000.0
var on_grass := false  # off the track: grass or gravel
var on_gravel := false
# Ground under the car, refreshed every physics tick.
var grade := 0.0  # rise per metre in the direction the car points
var bank := 0.0  # rise per metre toward the car's right
var load_factor := 1.0  # >1 in compressions, <1 over crests
const GRAVEL_GRIP := 0.4
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

# DRS & slipstream
const DRS_DRAG := 0.62  # aero drag multiplier with the flap open
const TOW_RANGE := 30.0  # metres behind another car where the tow works
var drs_from_lap := 2  # race rule; 0 = always allowed (time trial)
var auto_drs := false
var drs_armed := false  # within 1 s at detection, so DRS may open in the zone
var drs_open := false
var tow := 0.0  # 0..1
var _drs_zone := -1

# Tyres. A compound's `life` is the share of the race distance it lasts
# before falling off the cliff, so strategy works the same for 3 or 10 laps.
const COMPOUNDS := [
	{"name": "SOFT", "short": "S", "color": Color(0.95, 0.12, 0.1), "grip": 1.05, "life": 0.55},
	{"name": "MEDIUM", "short": "M", "color": Color(1.0, 0.82, 0.1), "grip": 1.0, "life": 0.8},
	{"name": "HARD", "short": "H", "color": Color(0.95, 0.95, 0.95), "grip": 0.955, "life": 1.15},
]
var compound := 1
var wear := 0.0
var race_laps := 3
var tyre_wear_enabled := true
var compounds_used := {}
var pit_stops := 0
var team := 0
## F1 rule: use two different dry compounds in the race (3+ laps here).
var mandatory_two := false
var penalty := 0.0  # seconds added at the flag
## Time trial: the clock starts at the line (flying lap), and running wide
## past the kerbs invalidates the lap, like qualifying.
var flying_start := false

# ------------------------------------------------------------ realistic handling
# A planar two-axle ("bicycle") vehicle model: slip angles into a Pacejka-
# style tyre curve, load transfer under braking/acceleration, aero downforce,
# power-limited rear-wheel drive and a friction circle per axle, so cars can
# understeer, oversteer, spin the rears or lock the fronts. Tuned so the
# grip envelope matches the arcade model (and the AI) at every speed.
const R_MASS := 800.0  # kg, car + driver
const R_IZ := 1100.0  # yaw inertia, kg m^2
const R_A := 1.95  # CG to front axle, m (46% of the weight on the front)
const R_B := 1.65  # CG to rear axle, m
const R_H := 0.30  # CG height, m
const R_MU := 1.94  # peak tyre friction (soft-ish racing slick)
const R_CLA := 4.95  # downforce coefficient x area
const R_CDA := 1.1  # drag coefficient x area
const R_RHO := 1.2
const R_POWER := 600000.0  # W at the wheels
const R_MAX_DRIVE := 14000.0  # N, clutch/diff limit at very low speed
const R_BRAKE := 52000.0  # N, full pedal
const R_BRAKE_FRONT := 0.56
const TIRE_B_FRONT := 13.0  # cornering stiffness (peak force near 8 deg of slip)
const TIRE_B_REAR := 15.0  # a stiffer, slightly grippier rear keeps the car stable
const TIRE_REAR_GRIP := 1.05
const TIRE_C := 1.45  # shape: how much grip is left once sliding
## Stability control by TC level: body slip angle allowed before it steps in.
const ESC_BETA := [INF, 0.16, 0.09]
## Traction control by level (off / low / high): share of the rear grip
## left over after cornering that the engine may use.
const TC_LIMIT := [INF, 0.98, 0.92]
var realistic := false
var traction_control := 2
var abs_enabled := true
var wheelspin := 0.0  # 0..1, for sound and haptics
var lockup := 0.0
var _vx := 0.0
var _vy := 0.0
var _r := 0.0
var _ax := 0.0
var _ay := 0.0
var _fy_r_prev := 0.0
var _body_pitch := 0.0
var _body_roll := 0.0
var lap_valid := true
var last_lap_valid := true

# Pit stops: request with BOX, the car then drives itself through the lane.
var pit_requested := false
var pit_compound := 2
var in_pit := false
var pit_limiter := false
var _pit_state := 0  # 0 driving to box, 1 stopped, 2 done
var _pit_timer := 0.0
var _worn_warned := false
signal pit_event(car, what: String)

signal lap_completed(car, lap_time: float)
signal crossed_finish(car)
signal impact(strength: float)
signal reset

var model: Node3D


func setup(p_track: Track, color: Color, slot: int, accent := Color.WHITE) -> void:
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
	model.accent_color = accent
	add_child(model)
	place_on_grid(slot)


func place_on_grid(slot: int) -> void:
	global_transform = track.transform_at(-track.grid_distance(slot), track.grid_lateral(slot))
	velocity = Vector3.ZERO
	track_idx = track.closest_index_global(global_position)
	_update_track_state()
	lap = 0
	race_dist = lap_pos - track.length


## Put the car `s` metres along the lap (negative = before the line).
func place_at(s: float) -> void:
	global_transform = track.transform_at(s, 0.0)
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
		_r = 0.0
		speed = 0.0
		throttle = 0.0
		_update_gear()
		return
	if in_pit:
		_pit_drive(dt)
	elif finished and is_player:
		_ai_input()  # the car drives itself on the cool-down lap
	elif is_player:
		_player_input(dt)
	else:
		_ai_input()
	_integrate(dt)
	_update_track_state()
	if model:
		model.update_visual(steer, speed, dt)
	_update_body_motion(dt)


func _player_input(dt: float) -> void:
	var target := Input.get_axis("steer_left", "steer_right")
	if steering_mode == 2 and absf(target) < 0.01:
		var deg := rad_to_deg(angle_difference(tilt_neutral, tilt_roll()))
		if absf(deg) < 1.5:
			deg = 0.0  # small deadzone so a steady hand drives straight
		target = clampf(deg * steer_sensitivity / TILT_FULL_LOCK, -1.0, 1.0)
		if tilt_invert:
			target = -target
	if steer_assist > 0 and absf(speed) > 5.0:
		# Like Real Racing's steering assist: blend toward the racing line.
		target = lerpf(target, _ideal_steer(lateral), STEER_ASSIST_BLEND[steer_assist])
		# Edge protection: lean back toward the track as you run out of road.
		var room := track.half_width(track_idx, lateral) - absf(lateral)
		if room < 2.5:
			var push: float = (2.5 - room) / 2.5 * STEER_ASSIST_EDGE[steer_assist]
			target = clampf(target - signf(lateral) * push, -1.0, 1.0)
	# Arrows/keys ramp in; sensitivity makes that ramp quicker or gentler.
	steer = move_toward(steer, target, dt * 5.0 * steer_sensitivity)
	brake = Input.get_action_strength("brake")
	throttle = Input.get_action_strength("accelerate")
	if auto_throttle:
		# Like most mobile racers: the car accelerates by itself, you brake.
		throttle = 0.0 if brake > 0.05 else 1.0
	if braking_assist > 0 and speed > 15.0:
		var limit: float = _target_speed_ahead() * BRAKE_ASSIST_MARGIN[braking_assist] * sqrt(tyre_grip())
		if speed > limit:
			throttle = 0.0
			brake = maxf(brake, clampf((speed - limit) / 6.0, 0.3, 1.0))


## Phone roll in the screen plane. Works whether the phone is held upright
## or reclined, as long as it isn't lying flat. Godot already rotates the
## sensor axes to match the landscape screen.
func tilt_roll() -> float:
	var a := Input.get_accelerometer()
	return atan2(a.x, absf(a.y) + 0.001)


func calibrate_tilt() -> void:
	tilt_neutral = tilt_roll()


## Steering that would follow the track at `line` metres off centre.
func _ideal_steer(line: float) -> float:
	var look := clampf(absf(speed) * 0.32, 6.0, 30.0)
	var local := global_transform.affine_inverse() * track.point_at(lap_pos + look, line)
	return clampf(atan2(local.x, -local.z) * 3.0, -1.0, 1.0)


## Slowest planned speed over the next few track points.
func _target_speed_ahead() -> float:
	var n := track.points.size()
	var v := INF
	for o in range(1, 5):
		v = minf(v, track.target_speed[(track_idx + o) % n])
	return v


func _ai_input() -> void:
	var line := ai_line
	# Very simple overtaking/avoidance: pick the other side of a car ahead.
	for o in others:
		if o == self or o.in_pit:
			continue
		var gap: float = o.race_dist - race_dist
		if gap > 0.0 and gap < 22.0 and absf(o.lateral - lateral) < 2.4:
			var hw := track.half_width(track_idx, o.lateral) - 1.5
			line = clampf(o.lateral + (3.2 if o.lateral < 0.0 else -3.2), -hw, hw)
	steer = _ideal_steer(line)
	_ai_strategy()
	var v_target := _target_speed_ahead() * ai_skill * sqrt(tyre_grip())
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
	var tg := tyre_grip()
	var grip_mul := (GRAVEL_GRIP if on_gravel else 0.5 if on_grass else 1.0) * tg * load_factor
	if tyre_wear_enabled and controls_enabled:
		var c: Dictionary = COMPOUNDS[compound]
		var rate: float = 1.0 / (c.life * race_laps * track.length)
		wear += absf(velocity.dot(-global_transform.basis.z)) * dt * rate * (1.0 + 1.2 * skid + (0.5 if on_grass else 0.0))
		if is_player and wear > 0.8 and not _worn_warned:
			_worn_warned = true
			pit_event.emit(self, "worn")
	if realistic:
		_integrate_realistic(dt, tg)
		return

	# Longitudinal
	var accel := 0.0
	if throttle > 0.01 and v_long > -0.5:
		var ratio := clampf(v_long / TOP_SPEED, 0.0, 1.0)
		accel += throttle * MAX_ACCEL * (1.0 - ratio * ratio) * (0.6 if on_grass else 1.0) * minf(tg, 1.0)
	if brake > 0.01:
		if v_long > 0.5:
			accel -= brake * (18.0 + 0.35 * v_long) * (0.5 if on_grass else 1.0) * tg
		elif throttle < 0.01 and v_long > -REVERSE_SPEED:
			accel -= brake * 6.0  # reverse
		elif v_long < -0.5:
			accel += brake * 10.0
	# Aero drag + rolling resistance, plus heavy drag on grass. An open DRS
	# flap and a car ahead's wake both cut the aero part.
	tow = _compute_tow()
	var aero := 0.0004 * (DRS_DRAG if drs_open else 1.0) * (1.0 - 0.45 * tow)
	var drag := 0.25 + aero * v_long * v_long
	if on_gravel:
		# Stones bleed speed fast, but a slow car can still crawl out.
		drag += 0.012 * v_long * v_long + 4.5 * clampf(absf(v_long) / 15.0, 0.15, 1.0)
	elif on_grass:
		drag += 0.004 * v_long * v_long + 2.0
	accel -= signf(v_long) * drag
	accel -= 9.81 * grade / sqrt(1.0 + grade * grade)  # hills
	var new_v := v_long + accel * dt
	if signf(new_v) != signf(v_long) and absf(v_long) > 0.01 and throttle < 0.01 and brake < 0.01:
		new_v = 0.0
	v_long = new_v

	# Steering (bicycle model), clamped by available lateral grip.
	var vabs := absf(v_long)
	var max_angle := lerpf(0.42, 0.05, clampf(vabs / 75.0, 0.0, 1.0))
	var yaw_rate := -v_long * tan(steer * max_angle) / WHEELBASE
	var yaw_cap := grip_accel(vabs) * grip_mul / maxf(vabs, 0.5)
	# Banking holds the car in when it turns toward the low side.
	if absf(bank) > 0.01:
		var helps := bank * yaw_rate > 0.0
		yaw_cap = maxf(yaw_cap + (9.81 if helps else -4.9) * absf(bank) / maxf(vabs, 0.5), 0.0)
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
	v_lat -= 9.81 * bank * dt * 0.3  # slide down a banked slope when slow
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
	speed = velocity.dot(-global_transform.basis.z)
	_update_gear()


func _integrate_realistic(dt: float, tg: float) -> void:
	tow = _compute_tow()
	var basis := global_transform.basis
	# Body frame: x forward, y to the LEFT, yaw rate positive turning left.
	_vx = velocity.dot(-basis.z)
	_vy = velocity.dot(-basis.x)
	var steps := 3
	var h := dt / steps
	var spin_acc := 0.0
	var lock_acc := 0.0
	var slip_acc := 0.0
	for k in steps:
		var out := _realistic_step(h, tg)
		spin_acc = maxf(spin_acc, out.x)
		lock_acc = maxf(lock_acc, out.y)
		slip_acc = maxf(slip_acc, out.z)
		rotate_y(_r * h)
	wheelspin = move_toward(wheelspin, spin_acc, dt * 6.0)
	lockup = move_toward(lockup, lock_acc, dt * 6.0)
	skid = move_toward(skid, clampf(maxf(slip_acc, maxf(wheelspin, lockup)), 0.0, 1.0), dt * 5.0)
	basis = global_transform.basis
	velocity = -basis.z * _vx - basis.x * _vy
	velocity.y = 0.0
	move_and_slide()
	_impact_cooldown -= dt
	for c in get_slide_collision_count():
		var col := get_slide_collision(c)
		var hit := absf(col.get_normal().dot(-basis.z))
		var strength := hit * absf(_vx)
		if strength > 2.0 and _impact_cooldown <= 0.0:
			impact.emit(strength)
			_impact_cooldown = 0.4
		velocity *= 1.0 - 0.5 * hit * dt * 10.0
		_r *= 1.0 - 0.6 * dt * 10.0  # walls kill rotation
	speed = velocity.dot(-global_transform.basis.z)
	_update_gear()


## One sub-step. Returns (wheelspin, lockup, tyre slide) amounts.
func _realistic_step(h: float, tg: float) -> Vector3:
	var L := R_A + R_B
	var v := absf(_vx)
	var grip := R_MU * tg * (GRAVEL_GRIP if on_gravel else 0.5 if on_grass else 1.0)
	var down := 0.5 * R_RHO * R_CLA * _vx * _vx
	var transfer := R_MASS * _ax * R_H / L  # braking (ax < 0) loads the front
	# Compressions press the tyres into the road, crests unload them.
	var fz_f := maxf((R_MASS * 9.81 * R_B / L + down * 0.45) * load_factor - transfer, 200.0)
	var fz_r := maxf((R_MASS * 9.81 * R_A / L + down * 0.55) * load_factor + transfer, 200.0)
	var cap_f := grip * fz_f
	var cap_r := grip * fz_r * TIRE_REAR_GRIP

	# Front wheel angle. Lock shrinks with speed so a touch input never asks
	# for absurd slip angles at 300 km/h, like a speed-sensitive rack.
	var dmax := clampf(0.38 - v * 0.0045, 0.065, 0.38)
	var delta := -steer * dmax
	# Slip-angle limiter: full lock asks the fronts for (a bit past) their
	# peak grip, never more, the way a good driver feels the wheel. Keeps
	# digital touch steering from scrubbing the fronts and snapping the rear.
	if v > 4.0:
		var peak := tan(PI / (2.0 * TIRE_C)) / TIRE_B_FRONT
		var path := atan2(_vy + R_A * _r, v)
		delta = clampf(delta, path - 1.25 * peak, path + 1.25 * peak)

	# Longitudinal demand per axle (rear-wheel drive)
	var fx_f := 0.0
	var fx_r := 0.0
	if throttle > 0.01 and _vx > -0.5:
		fx_r += throttle * minf(R_POWER / maxf(v, 4.0), R_MAX_DRIVE) * (0.6 if on_grass else 1.0)
	if brake > 0.01:
		if _vx > 0.5:
			fx_f -= brake * R_BRAKE * R_BRAKE_FRONT
			fx_r -= brake * R_BRAKE * (1.0 - R_BRAKE_FRONT)
		elif throttle < 0.01 and _vx > -REVERSE_SPEED:
			fx_r -= brake * 4000.0  # reverse gear
	# Driver aids. TC works on the friction circle: only the grip the rear
	# isn't already using to corner is available for drive.
	if fx_r > 0.0 and traction_control > 0:
		var room := sqrt(maxf(cap_r * cap_r - _fy_r_prev * _fy_r_prev, 0.0))
		fx_r = minf(fx_r, TC_LIMIT[traction_control] * room)
	if abs_enabled:
		fx_f = maxf(fx_f, -0.96 * cap_f)
		fx_r = maxf(fx_r, -0.96 * cap_r)
	# Friction circle: past the limit the axle slides (wheelspin or lock-up)
	# and keeps only a little lateral grip.
	var spin := 0.0
	var lock := 0.0
	var lat_f := sqrt(maxf(cap_f * cap_f - fx_f * fx_f, 0.0))
	var lat_r := sqrt(maxf(cap_r * cap_r - fx_r * fx_r, 0.0))
	if absf(fx_f) > cap_f:
		lock = 1.0
		fx_f = signf(fx_f) * cap_f * 0.85
		lat_f = cap_f * 0.3
	if absf(fx_r) > cap_r:
		if fx_r > 0.0:
			spin = clampf(fx_r / cap_r - 1.0 + 0.5, 0.0, 1.0)
		else:
			lock = 1.0
		fx_r = signf(fx_r) * cap_r * 0.85
		lat_r = cap_r * 0.3

	# Slip angles and tyre forces (low speed floor keeps them finite)
	var vxs := maxf(v, 3.0)
	var dir := 1.0 if _vx >= -0.5 else -1.0
	var alpha_f := atan2(_vy + R_A * _r, vxs) - delta * dir
	var alpha_r := atan2(_vy - R_B * _r, vxs)
	var fy_f := -lat_f * sin(TIRE_C * atan(TIRE_B_FRONT * alpha_f))
	var fy_r := -lat_r * sin(TIRE_C * atan(TIRE_B_REAR * alpha_r))
	_fy_r_prev = fy_r

	# Resistances: aero drag (cut by DRS and tow), rolling, grass
	var aero := 0.5 * R_RHO * R_CDA * (DRS_DRAG if drs_open else 1.0) * (1.0 - 0.45 * tow)
	var resist := aero * _vx * absf(_vx) + 200.0 * signf(_vx)
	if on_gravel:
		resist += R_MASS * (0.012 * _vx * absf(_vx) + 4.5 * clampf(_vx / 15.0, -1.0, 1.0))
	elif on_grass:
		resist += R_MASS * (0.004 * _vx * absf(_vx) + 2.0 * signf(_vx))
	# Gravity along the slope, and across it on banking (y is to the left).
	resist += R_MASS * 9.81 * grade / sqrt(1.0 + grade * grade)
	var g_lat := R_MASS * 9.81 * bank / sqrt(1.0 + bank * bank)

	var cd := cos(delta)
	var sd := sin(delta)
	var fx := fx_r + fx_f * cd - fy_f * sd - resist
	var fy := fx_f * sd + fy_f * cd + fy_r + g_lat
	var mz := R_A * (fx_f * sd + fy_f * cd) - R_B * fy_r
	var ax := fx / R_MASS + _vy * _r
	var ay := fy / R_MASS - _vx * _r
	var prev_vx := _vx
	_vx += ax * h
	_vy += ay * h
	_r += mz / R_IZ * h
	# Don't let the brakes drive the car backwards through zero.
	if brake > 0.01 and throttle < 0.01 and prev_vx > 0.0 and _vx < 0.0:
		_vx = 0.0
	if throttle < 0.01 and brake < 0.01 and absf(_vx) < 0.3:
		_vx = 0.0
	_ax = lerpf(_ax, fx / R_MASS, 0.25)
	_ay = lerpf(_ay, fy / R_MASS, 0.25)
	# Below walking pace slip angles are meaningless: blend to rolling motion.
	var k := clampf((v - 2.0) / 4.0, 0.0, 1.0)
	if k < 1.0:
		_r = lerpf(_vx * tan(delta) / L, _r, k)
		_vy = lerpf(0.0, _vy, k)
	# Stability control: when the car slides past the allowed body slip
	# angle, yaw it back toward where it's travelling (like brake-based ESC).
	if v > 6.0 and traction_control > 0:
		var beta := atan2(_vy, v)
		var excess: float = absf(beta) - ESC_BETA[traction_control]
		if excess > 0.0:
			_r += signf(beta) * excess * 14.0 * h * v / 20.0
	var slide := maxf(absf(alpha_f), absf(alpha_r)) / 0.12 - 0.7
	return Vector3(spin, lock, slide)


func _update_body_motion(dt: float) -> void:
	# Visual pitch and roll from the car's accelerations (weight transfer).
	var ax := _ax
	var ay := _ay
	if not realistic:
		ax = 0.0
		ay = 0.0
	_body_pitch = lerpf(_body_pitch, clampf(ax / 9.81 * 0.012, -0.05, 0.05), clampf(dt * 8.0, 0.0, 1.0))
	_body_roll = lerpf(_body_roll, clampf(-ay / 9.81 * 0.008, -0.05, 0.05), clampf(dt * 8.0, 0.0, 1.0))
	if model:
		# The body follows the road: nose up uphill, rolled on banking.
		model.rotation = Vector3(_body_pitch + atan(grade), 0.0, _body_roll + atan(bank))


## Sit the car on the road and read the slope, banking and vertical
## curvature under it for the physics.
func _follow_ground() -> void:
	global_position.y = track.ground_height(lap_pos, lateral)
	var heading := (-global_transform.basis.z).dot(track.tangents[track_idx])
	var on_road := absf(lateral) <= track.half_width(track_idx, lateral) + Track.KERB_WIDTH
	grade = track.slope_at(lap_pos) * heading
	bank = track.camber_at(lap_pos) * heading if on_road else 0.0
	var v := absf(speed)
	load_factor = clampf(1.0 + v * v * track.vcurv_at(lap_pos) / 9.81, 0.4, 2.0)


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
	_update_pit(prev_pos)
	_update_drs(prev_pos)
	var hw := track.half_width(track_idx, lateral)
	var surface := track.surface_at(track_idx, lateral)
	on_grass = surface != 0 and not track.on_pit_surface(lap_pos, lateral)
	on_gravel = on_grass and surface == 2
	_follow_ground()
	if on_grass and lap >= 1:
		lap_valid = false
	wrong_way = absf(speed) > 5.0 and (-global_transform.basis.z).dot(track.tangents[track_idx]) < -0.3
	if absf(lateral) > hw + Track.KERB_WIDTH + Track.RUNOFF + 25.0:
		reset_to_track()


func drs_available() -> bool:
	return drs_armed and _drs_zone != -1 and not drs_open


## 0 = nothing, 1 = can open now, 2 = open. For the HUD.
func drs_state() -> int:
	return 2 if drs_open else (1 if drs_available() else 0)


func gap_ahead_seconds() -> float:
	var best := INF
	for o in others:
		if o == self:
			continue
		var d: float = o.race_dist - race_dist
		if d > 0.0 and d < best:
			best = d
	return best / maxf(absf(speed), 20.0)


func _update_drs(prev_pos: float) -> void:
	if in_pit:
		drs_open = false
		drs_armed = false
		return
	for z: Dictionary in track.drs_zones:
		if Track.crossed(prev_pos, lap_pos, z.detect):
			drs_armed = lap >= drs_from_lap and (drs_from_lap == 0 or gap_ahead_seconds() < 1.0)
	var zone := track.in_drs_zone(lap_pos)
	if zone == -1 and _drs_zone != -1:
		drs_armed = false  # each activation is used up at the end of its zone
	_drs_zone = zone
	if zone == -1 or brake > 0.1:
		if drs_open:
			drs_armed = false
		drs_open = false
	elif drs_available() and (not is_player or auto_drs or Input.is_action_just_pressed("drs")):
		drs_open = true
	if model:
		model.set_drs(drs_open)


# ------------------------------------------------------------ tyres & pits

func tyre_grip() -> float:
	var c: Dictionary = COMPOUNDS[compound]
	var g: float = c.grip * (1.0 - 0.06 * minf(wear, 1.0))
	if wear > 0.8:
		g -= 0.28 * clampf((wear - 0.8) / 0.25, 0.0, 1.2)  # the cliff
	return g


func set_compound(c: int) -> void:
	compound = c
	wear = 0.0
	_worn_warned = false
	compounds_used[c] = true
	if model:
		model.set_compound(COMPOUNDS[c].color)


func request_pit(c: int) -> void:
	pit_requested = true
	pit_compound = c


func cancel_pit() -> void:
	if not in_pit:
		pit_requested = false


func _update_pit(prev_pos: float) -> void:
	if not in_pit and pit_requested and controls_enabled and not finished \
			and Track.crossed(prev_pos, lap_pos, track.pit_in):
		in_pit = true
		_pit_state = 0
		pit_event.emit(self, "enter")
	if in_pit:
		var d := track.pit_progress(lap_pos)
		pit_limiter = track.in_pit_limiter(d)
		if d > track.pit_len - 4.0 or d < -60.0:
			in_pit = false
			pit_limiter = false
			pit_requested = false
			pit_event.emit(self, "exit")


func _pit_drive(dt: float) -> void:
	var d := track.pit_progress(lap_pos)
	# Stalled against something in the lane: put the car back on the lane line.
	if _pit_state != 1 and absf(speed) < 1.0:
		_stuck_time += dt
		if _stuck_time > 2.0:
			_stuck_time = 0.0
			var s := lap_pos + 4.0
			var p := track.point_at(s, _pit_line(d + 4.0))
			var ahead := track.point_at(s + 3.0, _pit_line(d + 7.0))
			global_transform = Transform3D(Basis.IDENTITY, p).looking_at(ahead, Vector3.UP)
			velocity = Vector3.ZERO
			_r = 0.0
	else:
		_stuck_time = 0.0
	var look := clampf(absf(speed) * 0.4, 6.0, 20.0)
	var aim := track.point_at(lap_pos + look, _pit_line(d + look))
	var local := global_transform.affine_inverse() * aim
	steer = clampf(atan2(local.x, -local.z) * 3.0, -1.0, 1.0)
	# Brake down to the limiter before it starts, then hold it.
	var limiter_start := track.pit_ramp * 0.6
	var v_target := sqrt(Track.PIT_SPEED * Track.PIT_SPEED + 2.0 * 14.0 * maxf(limiter_start - d, 0.0))
	if track.in_pit_limiter(d):
		v_target = Track.PIT_SPEED
	elif d < track.pit_ramp:
		# The entry can start inside one of the circuit's corners (Spa's Bus Stop).
		v_target = minf(v_target, _target_speed_ahead())
	if _pit_state < 2:
		var to_box := track.pit_box(team) - d
		v_target = minf(v_target, sqrt(2.0 * 5.0 * maxf(to_box, 0.0)) + 0.3)
		if _pit_state == 0 and (to_box < 0.6 or (to_box < 3.0 and absf(speed) < 1.0)):
			_pit_state = 1
			_pit_timer = 2.3 + randf_range(0.0, 0.7)
			pit_event.emit(self, "stop")
		if _pit_state == 1:
			velocity = Vector3.ZERO
			_r = 0.0
			throttle = 0.0
			brake = 1.0
			_pit_timer -= dt
			if _pit_timer <= 0.0:
				set_compound(pit_compound)
				pit_stops += 1
				_pit_state = 2
				pit_event.emit(self, "done")
			return
	if speed < v_target - 0.5:
		throttle = 1.0 if v_target - speed > 3.0 else 0.4
		brake = 0.0
	elif speed > v_target + 0.5:
		throttle = 0.0
		brake = clampf((speed - v_target) / 6.0, 0.2, 1.0)
	else:
		throttle = 0.25
		brake = 0.0


## Where in the lane to drive: the fast lane by the pit wall, pulling over
## into our own box for the stop so cars behind can pass.
func _pit_line(d: float) -> float:
	var base := track.pit_lateral(d)
	var full := clampf((d - track.pit_ramp) / 20.0, 0.0, 1.0) \
			* clampf((track.pit_len - track.pit_ramp - d) / 20.0, 0.0, 1.0)
	var box := track.pit_box(team)
	var into := 0.0
	if _pit_state < 2:
		into = clampf(1.0 - (box - d - 3.0) / 15.0, 0.0, 1.0)
	else:
		into = clampf(1.0 - (d - box) / 15.0, 0.0, 1.0)
	return base + track.pit_side * full * lerpf(-1.6, 2.2, into)


## AI: pit when the tyres won't make the flag, onto the softest compound
## that will.
func _ai_strategy() -> void:
	if pit_requested or in_pit or not tyre_wear_enabled or finished:
		return
	var remaining := race_laps - (lap - 1) - lap_pos / track.length
	if remaining < 0.35:
		return
	var life_left: float = (1.0 - wear) * COMPOUNDS[compound].life * race_laps
	var owes_compound := mandatory_two and compounds_used.size() < 2 and remaining < race_laps * 0.55
	if not owes_compound and (life_left > remaining or wear < 0.7):
		return
	var choice := 2
	for c in [0, 1, 2]:
		if c != compound and COMPOUNDS[c].life * race_laps >= remaining * 1.05:
			choice = c
			break
	request_pit(choice)


func _compute_tow() -> float:
	if absf(speed) < 30.0:
		return 0.0
	var best := 0.0
	for o in others:
		if o == self:
			continue
		var d: float = o.race_dist - race_dist
		if d > 3.0 and d < TOW_RANGE and absf(o.lateral - lateral) < 2.2:
			best = maxf(best, 1.0 - d / TOW_RANGE)
	return best


func _on_cross_line() -> void:
	lap += 1
	if lap <= _max_lap:
		return  # re-crossing after reversing or a reset
	_max_lap = lap
	last_lap_valid = lap_valid
	lap_valid = true
	if lap <= 1:
		if flying_start:
			lap_start_time = clock
		return
	var t := clock - lap_start_time
	lap_start_time = clock
	if not finished:
		lap_times.append(t)
		best_lap = minf(best_lap, t)
		lap_completed.emit(self, t)
	crossed_finish.emit(self)


func reset_to_track() -> void:
	reset.emit()
	_stuck_time = 0.0
	if in_pit:
		in_pit = false
		pit_limiter = false
		pit_requested = false
	var s := lap_pos - 15.0
	global_transform = track.transform_at(s, 0.0)
	velocity = Vector3.ZERO
	_r = 0.0
	_ax = 0.0
	speed = 0.0
	track_idx = track.closest_index_local(global_position, track_idx, 30)
	var proj := track.project(global_position, track_idx)
	# Don't let a reset count as crossing the line.
	if lap_pos < track.length * 0.25 and proj.x > track.length * 0.75:
		lap -= 1
	lap_pos = proj.x
	lateral = proj.y
