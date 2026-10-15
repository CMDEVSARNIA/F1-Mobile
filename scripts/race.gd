extends Node3D
## Sets up a race: track, environment, grid, camera, HUD. Runs the start
## lights, positions, lap counting and results.

const Track = preload("res://scripts/track.gd")
const Car = preload("res://scripts/car.gd")
const ChaseCamera = preload("res://scripts/chase_camera.gd")
const Hud = preload("res://scripts/hud.gd")
const CarAudio = preload("res://scripts/car_audio.gd")

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


func _ready() -> void:
	track_info = GameState.current_track()
	laps = GameState.settings.laps
	_build_environment()

	track = Track.new()
	add_child(track)
	if not track.build(track_info.file):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return

	_spawn_cars(GameState.settings.opponents)

	camera = ChaseCamera.new()
	camera.target = player
	camera.mode = GameState.settings.camera
	add_child(camera)


	hud = Hud.new()
	add_child(hud)
	hud.touch.steer_mode = mini(GameState.settings.steering, 2)
	hud.touch.auto_throttle = GameState.settings.auto_throttle
	hud.touch.haptics = GameState.settings.haptics
	hud.touch.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
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


func _spawn_cars(opponents: int) -> void:
	var n := 1 + opponents
	# Player starts at the back half of the grid for a bit of a fight.
	var player_slot := n - 1 if opponents > 0 else 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ai_i := 1
	for slot in n:
		var car := Car.new()
		add_child(car)
		var is_player := slot == player_slot
		var d: Dictionary = GameState.DRIVERS[0] if is_player else GameState.DRIVERS[ai_i]
		car.setup(track, d.color, slot)
		car.driver_name = d.name
		car.is_player = is_player
		car.lap_completed.connect(_on_lap_completed)
		car.crossed_finish.connect(_on_crossed_finish)
		if is_player:
			player = car
			car.braking_assist = GameState.settings.braking_assist
			car.steering_mode = GameState.settings.steering
			car.auto_throttle = GameState.settings.auto_throttle
		else:
			# Front of the grid is a touch quicker, like a real grid.
			car.ai_skill = clampf(0.97 - slot * 0.006 + rng.randf_range(-0.01, 0.01), 0.88, 0.99)
			car.ai_line = rng.randf_range(-1.5, 1.5)
			ai_i += 1
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
			hud.set_lights(lit, true)
			if _countdown >= _lights_out_at:
				_go()
		State.RACING, State.FINISHED:
			pass
	_update_hud()
	if _results_timer > 0.0:
		_results_timer -= dt
		if _results_timer <= 0.0:
			_show_results()


func _go() -> void:
	state = State.RACING
	hud.set_lights(0, false)
	hud.show_message("GO!", 1.2)
	_race_start = player.clock
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


func _on_lap_completed(car: Car, lap_time: float) -> void:
	if car != player:
		return
	var best := GameState.record_lap(track_info.id, lap_time)
	var txt := "LAP  " + GameState.format_time(lap_time)
	if best:
		txt += "\nPERSONAL BEST!"
	hud.show_message(txt, 2.5)


func _on_crossed_finish(car: Car) -> void:
	if car.finished or car.lap <= laps:
		return
	car.finished = true
	car.finish_time = car.clock
	_finish_order.append(car)
	if car == player:
		state = State.FINISHED
		var pos := _finish_order.size()
		hud.show_message("CHEQUERED FLAG  -  P%d" % pos, 4.0)
		_results_timer = 4.0


func _show_results() -> void:
	var rows := []
	var order := _standings()
	var leader: Car = order[0]
	var leader_time := leader.finish_time
	var now := player.clock
	for i in order.size():
		var c: Car = order[i]
		var t := ""
		if i == 0:
			t = GameState.format_time(leader_time - _race_start)
		elif c.finished:
			t = "+%.3f" % (c.finish_time - leader_time)
		elif c.lap < laps:
			var down := laps - c.lap
			t = "+%d LAP%s" % [down, "S" if down > 1 else ""]
		else:
			# Still on the final lap: estimate the gap from average pace.
			var avg := maxf(c.race_dist / maxf(now - _race_start, 1.0), 20.0)
			var remaining := laps * track.length - c.race_dist
			t = "+%.1f" % (now - leader_time + remaining / avg)
		rows.append({"pos": i + 1, "name": c.driver_name, "time": t,
				"best": GameState.format_time(c.best_lap), "is_player": c == player})
	hud.show_results(rows)
