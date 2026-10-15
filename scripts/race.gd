extends Node3D
## Sets up a session: track, environment, grid, camera, HUD. Runs the start
## lights, positions, lap counting and results for three modes:
##   race        quick race with the menu's laps/opponents
##   season      a championship round (full grid, points, standings)
##   time_trial  flying laps alone with a ghost of your best and a delta

const Track = preload("res://scripts/track.gd")
const Car = preload("res://scripts/car.gd")
const ChaseCamera = preload("res://scripts/chase_camera.gd")
const Hud = preload("res://scripts/hud.gd")
const CarAudio = preload("res://scripts/car_audio.gd")
const ControlsPanel = preload("res://scripts/ui/controls_panel.gd")
const CarModel = preload("res://scripts/car_model.gd")
const GHOST_STRIDE := 5  # floats per ghost sample: t, lap_pos, x, z, yaw

enum State { COUNTDOWN, RACING, FINISHED }

var track: Track
var cars: Array = []
var player: Car
var camera: ChaseCamera
var hud: Hud
var state := State.COUNTDOWN
var laps := 3
var track_info: Dictionary

var _countdown := 0.0
var _lights_out_at := 0.0
var _finish_order: Array = []
var _results_timer := -1.0
var _race_start := 0.0
var mode := "race"
var time_trial := false
var _awarded := {}
# Time trial ghost
var _ghost_data := PackedFloat32Array()
var _rec := PackedFloat32Array()
var _ghost: Node3D
var _rec_tick := 0
var _was_valid := true


func _ready() -> void:
	GameState.stop_music(1.2)
	mode = GameState.mode
	if mode == "season" and (not GameState.season_active() or GameState.season_complete()):
		mode = "race"
	time_trial = mode == "time_trial"
	track_info = GameState.current_track()
	laps = 0 if time_trial else GameState.settings.laps
	_build_environment()

	track = Track.new()
	add_child(track)
	if not track.build(track_info.file):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	var opponents: int = GameState.settings.opponents
	if mode == "season":
		opponents = GameState.DRIVERS.size() - 1
	elif time_trial:
		opponents = 0
	_spawn_cars(opponents)
	if time_trial:
		_setup_time_trial()

	camera = ChaseCamera.new()
	camera.target = player
	camera.mode = GameState.settings.camera
	add_child(camera)


	hud = Hud.new()
	add_child(hud)
	hud.touch.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_apply_controls()
	hud.controls_pressed.connect(_open_controls)
	hud.box_selected.connect(_on_box)
	hud.pits_enabled = laps >= 2
	hud.session_mode = mode
	hud.minimap.setup(track, cars, player)
	hud.pause_pressed.connect(_toggle_pause)
	hud.resume_pressed.connect(_toggle_pause)
	hud.camera_pressed.connect(_cycle_camera)
	hud.reset_pressed.connect(func(): player.reset_to_track())
	hud.restart_pressed.connect(_restart)
	hud.menu_pressed.connect(_to_menu)

	# 5 lights one per second, then a random hold before lights out.
	_countdown = 0.0
	_lights_out_at = 5.0 + randf_range(0.4, 1.8)
	if time_trial:
		_lights_out_at = 1.0
		hud.show_message("%s  -  TIME TRIAL" % track_info.name.to_upper(), 2.5)
	elif mode == "season":
		hud.show_message("ROUND %d  -  %s  -  %d LAPS" % [GameState.season.round + 1,
				track_info.name.to_upper(), laps], 3.0)
	else:
		hud.show_message("%s  -  %d LAPS" % [track_info.name.to_upper(), laps], 3.0)


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.47, 0.8)
	sky_mat.sky_horizon_color = Color(0.68, 0.78, 0.9)
	sky_mat.ground_horizon_color = Color(0.68, 0.78, 0.9)
	sky_mat.ground_bottom_color = Color(0.3, 0.35, 0.3)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


## Driver indices into GameState.DRIVERS, pole first. Quick race: you start
## at the back. Season: grid follows the championship, you behind any tie.
func _grid_order(opponents: int) -> Array:
	var ids := range(1, opponents + 1)
	if mode == "season":
		var pts: Dictionary = GameState.season.points
		ids.append(0)
		ids.sort_custom(func(a, b):
			var pa: int = pts.get(GameState.DRIVERS[a].name, 0)
			var pb: int = pts.get(GameState.DRIVERS[b].name, 0)
			if pa != pb:
				return pa > pb
			return (a if a > 0 else 99) < (b if b > 0 else 99))
		return ids
	ids.append(0)
	return ids


func _spawn_cars(opponents: int) -> void:
	var order := _grid_order(opponents)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for slot in order.size():
		var idx: int = order[slot]
		var car := Car.new()
		add_child(car)
		var is_player := idx == 0
		var d: Dictionary = GameState.DRIVERS[idx]
		car.setup(track, d.color, slot, d.get("accent", Color.WHITE))
		car.driver_name = d.name
		car.is_player = is_player
		car.lap_completed.connect(_on_lap_completed)
		car.crossed_finish.connect(_on_crossed_finish)
		car.team = idx
		car.race_laps = laps
		car.tyre_wear_enabled = laps >= 2
		car.mandatory_two = laps >= 3
		if is_player:
			player = car
			car.set_compound(GameState.settings.start_compound)
			car.pit_event.connect(_on_pit_event)
		else:
			# Strategy mix like a real grid: mostly mediums, some softs/hards.
			var roll := rng.randf()
			car.set_compound(0 if roll < 0.3 else (1 if roll < 0.8 else 2))
			# Each driver has a pace of their own, plus a little day-to-day form.
			car.ai_skill = clampf(0.975 - (idx - 1) * 0.005 + rng.randf_range(-0.006, 0.006), 0.9, 0.99)
			car.ai_line = rng.randf_range(-1.5, 1.5)
		var audio := CarAudio.new()
		audio.car = car
		audio.positional = not is_player
		car.add_child(audio)
		cars.append(car)
	for c in cars:
		c.others = cars


func _physics_process(dt: float) -> void:
	match state:
		State.COUNTDOWN:
			_countdown += dt
			var lit := clampi(int(_countdown), 0, 5)
			hud.set_lights(lit, not time_trial)
			track.set_gantry_lights(0 if time_trial else lit)
			if _countdown >= _lights_out_at:
				_go()
		State.RACING, State.FINISHED:
			pass
	_update_hud()
	if time_trial:
		_time_trial_tick()
	if _results_timer > 0.0:
		_results_timer -= dt
		if _results_timer <= 0.0:
			_show_results()


## Push the current control settings into the player car and touch layout.
func _apply_controls() -> void:
	var s := GameState.settings
	player.steering_mode = s.steering
	player.tilt_invert = s.tilt_invert
	player.steer_sensitivity = s.steer_sensitivity
	player.steer_assist = s.steer_assist
	player.auto_throttle = s.auto_throttle
	player.braking_assist = s.braking_assist
	player.auto_drs = s.auto_drs
	player.realistic = s.handling == 1
	player.traction_control = s.traction_control
	player.abs_enabled = s.abs
	var t := hud.touch
	t.steer_mode = s.steering
	t.auto_throttle = s.auto_throttle
	t.haptics = s.haptics
	t.size_mult = s.control_size
	t.wheel_sensitivity = s.steer_sensitivity
	t.mirrored = s.mirrored
	t.self_modulate = Color(1, 1, 1, s.control_opacity)
	t.release_all()


func _open_controls() -> void:
	var panel := ControlsPanel.new()
	panel.in_race = true
	panel.recalibrate_requested.connect(func():
		player.calibrate_tilt()
		hud.show_message("TILT CALIBRATED", 1.5))
	panel.closed.connect(func():
		_apply_controls()
		hud.pause_panel.visible = true)
	hud.pause_panel.visible = false
	hud.root.add_child(panel)


func _go() -> void:
	state = State.RACING
	hud.set_lights(0, false)
	track.set_gantry_lights(0)
	hud.show_message("GO!", 1.2)
	_race_start = player.clock
	# However the phone is held at lights out counts as "straight".
	player.calibrate_tilt()
	for c in cars:
		c.controls_enabled = true
		c.start_lap_timer()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
	elif event.is_action_pressed("camera"):
		_cycle_camera()
	elif event.is_action_pressed("reset_car") and state != State.COUNTDOWN:
		player.reset_to_track()


func _notification(what: int) -> void:
	# Auto-pause when the app is backgrounded on Android.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not get_tree().paused and state == State.RACING and hud:
			_toggle_pause()


func _toggle_pause() -> void:
	if state == State.FINISHED and _results_timer < 0.0:
		return
	var p := not get_tree().paused
	get_tree().paused = p
	hud.show_pause(p)


func _cycle_camera() -> void:
	camera.cycle_mode()
	GameState.settings.camera = camera.mode
	GameState.save()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _standings() -> Array:
	var order := _finish_order.duplicate()
	order.sort_custom(func(a, b): return a.finish_time + a.penalty < b.finish_time + b.penalty)
	var running := cars.filter(func(c): return not c.finished)
	running.sort_custom(func(a, b): return a.race_dist > b.race_dist)
	order.append_array(running)
	return order


func _update_hud() -> void:
	var now := player.clock
	var order := _standings()
	hud.update_telemetry(player, order.find(player) + 1, cars.size(), laps, now, state != State.COUNTDOWN)
	if player.wrong_way and state == State.RACING:
		hud.show_message("WRONG WAY", 0.3)


func _on_pit_event(car: Car, what: String) -> void:
	var c: Dictionary = Car.COMPOUNDS[car.pit_compound]
	match what:
		"worn":
			hud.show_message("TYRES ARE GONE - BOX!", 2.5)
		"enter":
			hud.show_message("PIT LANE - LIMITER ON", 2.0)
		"stop":
			hud.show_message("FITTING %s" % c.name, 2.5)
		"done":
			hud.show_message("GO GO GO!  %s ON" % c.name, 1.5)


## From the HUD's BOX button: -1 cancels, otherwise the compound to fit.
func _on_box(compound: int) -> void:
	if compound < 0:
		player.cancel_pit()
		hud.show_message("BOX CANCELLED", 1.2)
	else:
		player.request_pit(compound)
		hud.show_message("BOX THIS LAP - %s" % Car.COMPOUNDS[compound].name, 2.0)


func _on_lap_completed(car: Car, lap_time: float) -> void:
	if car != player:
		return
	if time_trial:
		_time_trial_lap(lap_time)
		return
	var best := GameState.record_lap(track_info.id, lap_time)
	var txt := "LAP  " + GameState.format_time(lap_time)
	if best:
		txt += "\nPERSONAL BEST!"
	hud.show_message(txt, 2.5)


func _on_crossed_finish(car: Car) -> void:
	if time_trial or car.finished or car.lap <= laps:
		return
	car.finished = true
	car.finish_time = car.clock
	if car.mandatory_two and car.compounds_used.size() < 2:
		car.penalty = 10.0
		if car == player:
			hud.show_message("+10s PENALTY - ONE TYRE COMPOUND", 3.0)
	_finish_order.append(car)
	if car == player:
		state = State.FINISHED
		var pos := _standings().find(player) + 1
		hud.show_message("CHEQUERED FLAG  -  P%d" % pos, 4.0)
		_results_timer = 4.0


func _show_results() -> void:
	var rows := []
	var order := _standings()
	var leader: Car = order[0]
	var leader_time := leader.finish_time + leader.penalty
	var now := player.clock
	for i in order.size():
		var c: Car = order[i]
		var t := ""
		if i == 0:
			t = GameState.format_time(leader_time - _race_start)
		elif c.finished:
			t = "+%.3f" % (c.finish_time + c.penalty - leader_time)
		elif c.lap < laps:
			var down := laps - c.lap
			t = "+%d LAP%s" % [down, "S" if down > 1 else ""]
		else:
			# Still on the final lap: estimate the gap from average pace.
			var avg := maxf(c.race_dist / maxf(now - _race_start, 1.0), 20.0)
			var remaining := laps * track.length - c.race_dist
			t = "+%.1f" % (now - leader_time + remaining / avg)
		if c.penalty > 0.0:
			t += "  (+%ds pen)" % int(c.penalty)
		rows.append({"pos": i + 1, "name": c.driver_name, "time": t, "stops": c.pit_stops,
				"best": GameState.format_time(c.best_lap), "is_player": c == player})
	if mode == "season" and _awarded.is_empty():
		var gained := GameState.season_award(order.map(func(c): return c.driver_name))
		_awarded = gained
		for r in rows:
			r["pts"] = gained.get(r.name, 0)
	hud.show_results(rows, mode == "season")


# ------------------------------------------------------------ time trial

func _setup_time_trial() -> void:
	player.place_at(-260.0)
	player.flying_start = true
	player.drs_from_lap = 0
	player.tyre_wear_enabled = false
	player.set_compound(0)
	_ghost_data = GameState.load_ghost(track_info.id)
	_ghost = CarModel.new()
	_ghost.team_color = Color(0.4, 0.85, 1.0)
	_ghost.accent_color = Color.WHITE
	add_child(_ghost)
	for mi: MeshInstance3D in _ghost.find_children("*", "MeshInstance3D", true, false):
		mi.transparency = 0.6
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false


func _time_trial_tick() -> void:
	if player.lap < 1:
		return
	var t := player.clock - player.lap_start_time
	# Record ~20 samples a second of the lap in progress.
	_rec_tick += 1
	if _rec_tick % 3 == 0:
		var xf := player.global_transform
		_rec.append_array([t, player.lap_pos, xf.origin.x, xf.origin.z, player.rotation.y])
	if _was_valid and not player.lap_valid:
		hud.show_message("TRACK LIMITS - LAP INVALID", 2.0)
	_was_valid = player.lap_valid
	# Ghost replays the best lap at the same lap time.
	var n := _ghost_data.size() / GHOST_STRIDE
	if n > 1 and t <= _ghost_data[(n - 1) * GHOST_STRIDE]:
		var i := _ghost_index(t, 0)
		var a := i * GHOST_STRIDE
		var b := mini(i + 1, n - 1) * GHOST_STRIDE
		var span := _ghost_data[b] - _ghost_data[a]
		var f := 0.0 if span <= 0.0 else clampf((t - _ghost_data[a]) / span, 0.0, 1.0)
		_ghost.visible = true
		_ghost.position = Vector3(lerpf(_ghost_data[a + 2], _ghost_data[b + 2], f), 0.0,
				lerpf(_ghost_data[a + 3], _ghost_data[b + 3], f))
		_ghost.rotation.y = lerp_angle(_ghost_data[a + 4], _ghost_data[b + 4], f)
		# Delta: our lap time minus the ghost's time at the same point of the lap.
		var j := _ghost_index(player.lap_pos, 1)
		var pa := j * GHOST_STRIDE
		var pb := mini(j + 1, n - 1) * GHOST_STRIDE
		var ds := _ghost_data[pb + 1] - _ghost_data[pa + 1]
		var g := 0.0 if ds <= 0.0 else clampf((player.lap_pos - _ghost_data[pa + 1]) / ds, 0.0, 1.0)
		hud.set_delta(t - lerpf(_ghost_data[pa], _ghost_data[pb], g))
	else:
		_ghost.visible = false
		hud.set_delta(NAN)


## Last sample whose field `k` (0 = time, 1 = lap distance) is <= v.
func _ghost_index(v: float, k: int) -> int:
	var lo := 0
	var hi := _ghost_data.size() / GHOST_STRIDE - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if _ghost_data[mid * GHOST_STRIDE + k] <= v:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _time_trial_lap(lap_time: float) -> void:
	var samples := _rec
	_rec = PackedFloat32Array()
	_was_valid = true
	if not player.last_lap_valid:
		hud.show_message("LAP " + GameState.format_time(lap_time) + "\nINVALID", 2.5)
		return
	GameState.record_lap(track_info.id, lap_time)
	var prev: float = GameState.tt_best.get(track_info.id, INF)
	var txt := "LAP  " + GameState.format_time(lap_time)
	if lap_time < prev:
		GameState.save_ghost(track_info.id, lap_time, samples)
		_ghost_data = samples
		txt += "\nNEW BEST - GHOST SAVED" if prev < INF else "\nGHOST SAVED"
	else:
		txt += "\n+%.3f" % (lap_time - prev)
	hud.show_message(txt, 2.5)
