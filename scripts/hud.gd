extends CanvasLayer
## Race HUD: position, laps, timing, speed/gear, start lights, minimap,
## pause and results panels. Built in code so it's easy to tweak.

const Minimap = preload("res://scripts/minimap.gd")
const TouchControls = preload("res://scripts/touch_controls.gd")
const Dashboard = preload("res://scripts/ui/dashboard.gd")
const IconButton = preload("res://scripts/ui/icon_button.gd")

signal pause_pressed
signal camera_pressed
signal reset_pressed
signal resume_pressed
signal restart_pressed
signal menu_pressed
signal controls_pressed

var root: Control
var pos_label: Label
var lap_label: Label
var time_label: Label
var last_label: Label
var best_label: Label
var dashboard: Control
var message_label: Label
var lights: Array[Panel] = []
var lights_box: HBoxContainer
var minimap: Control
var touch: Control
var pause_panel: PanelContainer
var results_panel: PanelContainer
var results_list: VBoxContainer

var _message_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = GameState.make_theme()
	add_child(root)

	touch = TouchControls.new()
	root.add_child(touch)

	# Top-left: position and lap
	var tl := _vbox(root)
	_place(tl, Control.PRESET_TOP_LEFT, 20, 14, 20, 14)
	pos_label = _label(tl, "P1/1", 44)
	lap_label = _label(tl, "LAP 0/3", 26)

	# Top-right: timing
	var tr := _vbox(root)
	_place(tr, Control.PRESET_TOP_RIGHT, -20, 14, -20, 14)
	time_label = _label(tr, "0:00.000", 36, HORIZONTAL_ALIGNMENT_RIGHT)
	last_label = _label(tr, "LAST --:--.---", 20, HORIZONTAL_ALIGNMENT_RIGHT)
	best_label = _label(tr, "BEST --:--.---", 20, HORIZONTAL_ALIGNMENT_RIGHT)

	# Top-centre buttons
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	root.add_child(buttons)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(buttons, Control.PRESET_CENTER_TOP, -120, 12, 120, 76)
	for spec in [[IconButton.Icon.PAUSE, pause_pressed], [IconButton.Icon.CAMERA, camera_pressed],
			[IconButton.Icon.RESET, reset_pressed]]:
		var ib := IconButton.new(spec[0])
		ib.pressed.connect(spec[1].emit)
		buttons.add_child(ib)

	# Bottom centre: driver display with shift lights
	dashboard = Dashboard.new()
	root.add_child(dashboard)
	_place(dashboard, Control.PRESET_CENTER_BOTTOM, -125, -162, 125, -12)

	# Messages
	message_label = Label.new()
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_label(message_label, 40)
	root.add_child(message_label)
	_place(message_label, Control.PRESET_CENTER, -400, -150, 400, -90)

	# Start lights: five pairs of reds
	lights_box = HBoxContainer.new()
	lights_box.alignment = BoxContainer.ALIGNMENT_CENTER
	lights_box.add_theme_constant_override("separation", 14)
	lights_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lights_box)
	_place(lights_box, Control.PRESET_CENTER_TOP, -200, 100, 200, 220)
	for i in 5:
		var housing := PanelContainer.new()
		var hs := StyleBoxFlat.new()
		hs.bg_color = Color(0.05, 0.05, 0.05, 0.9)
		hs.set_corner_radius_all(10)
		hs.set_content_margin_all(8)
		housing.add_theme_stylebox_override("panel", hs)
		var col := VBoxContainer.new()
		housing.add_child(col)
		for k in 2:
			var bulb := Panel.new()
			bulb.custom_minimum_size = Vector2(42, 42)
			col.add_child(bulb)
			if k == 1:
				lights.append(bulb)
			_set_bulb(bulb, false)
		lights_box.add_child(housing)
	lights_box.visible = false

	minimap = Minimap.new()
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	_place(minimap, Control.PRESET_TOP_RIGHT, -200, 130, -20, 310)

	_build_pause()
	_build_results()


func set_lights(n_on: int, visible_box: bool) -> void:
	lights_box.visible = visible_box
	for i in lights.size():
		_set_bulb(lights[i], i < n_on)
	# Top row mirrors bottom row.
	for i in lights_box.get_child_count():
		var top: Panel = lights_box.get_child(i).get_child(0).get_child(0)
		_set_bulb(top, i < n_on)


func show_message(text: String, seconds := 2.0) -> void:
	message_label.text = text
	_message_timer = seconds


func update_telemetry(car, position: int, total: int, laps: int, now: float, racing: bool) -> void:
	pos_label.text = "P%d/%d" % [position, total]
	lap_label.text = "LAP %d/%d" % [clampi(car.lap, 1, laps) if racing or car.lap > 0 else 0, laps]
	var lap_t: float = now - car.lap_start_time if racing else 0.0
	time_label.text = GameState.format_time(lap_t) if racing else "0:00.000"
	last_label.text = "LAST " + GameState.format_time(car.lap_times[-1] if car.lap_times.size() else 0.0)
	best_label.text = "BEST " + GameState.format_time(car.best_lap)
	dashboard.speed_kmh = int(absf(car.speed) * 3.6)
	dashboard.gear_text = "R" if car.speed < -0.5 else ("N" if absf(car.speed) < 0.5 and car.throttle < 0.05 else str(car.gear))
	dashboard.rpm = car.rpm
	dashboard.throttle = car.throttle
	dashboard.brake = car.brake
	dashboard.drs_state = car.drs_state()
	dashboard.tow = car.tow
	touch.drs_state = car.drs_state()


func _process(dt: float) -> void:
	if _message_timer > 0.0:
		_message_timer -= dt
		if _message_timer <= 0.0:
			message_label.text = ""


func show_pause(on: bool) -> void:
	pause_panel.visible = on
	touch.release_all()


func show_results(rows: Array) -> void:
	for c in results_list.get_children():
		c.queue_free()
	for r in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 24)
		var a := _label(line, "%2d" % r.pos, 24)
		a.custom_minimum_size = Vector2(40, 0)
		var b := _label(line, r.name, 24)
		b.custom_minimum_size = Vector2(200, 0)
		if r.is_player:
			b.add_theme_color_override("font_color", Color(1, 0.85, 0.1))
		var c := _label(line, r.time, 24)
		c.custom_minimum_size = Vector2(150, 0)
		_label(line, "best " + r.best, 20)
		results_list.add_child(line)
	results_panel.visible = true
	touch.visible = false
	touch.release_all()


# ------------------------------------------------------------ helpers

func _build_pause() -> void:
	pause_panel = _panel()
	var box: VBoxContainer = pause_panel.get_child(0)
	_label(box, "PAUSED", 40, HORIZONTAL_ALIGNMENT_CENTER)
	GameState.style_primary(_button(box, "RESUME", resume_pressed.emit))
	_button(box, "CONTROLS", controls_pressed.emit)
	_button(box, "RESTART", restart_pressed.emit)
	_button(box, "MAIN MENU", menu_pressed.emit)
	pause_panel.visible = false


func _build_results() -> void:
	results_panel = _panel()
	var box: VBoxContainer = results_panel.get_child(0)
	_label(box, "RESULTS", 40, HORIZONTAL_ALIGNMENT_CENTER)
	results_list = VBoxContainer.new()
	box.add_child(results_list)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	GameState.style_primary(_button(row, "RACE AGAIN", restart_pressed.emit))
	_button(row, "MAIN MENU", menu_pressed.emit)
	results_panel.visible = false


func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.09, 0.92)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(28)
	sb.border_color = Color(0.88, 0.02, 0.0)
	sb.border_width_top = 6
	p.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	p.add_child(box)
	root.add_child(p)
	return p


func _vbox(parent: Control) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


## Anchor `c` to `preset` and set explicit offsets from those anchors.
func _place(c: Control, preset: int, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	if preset == Control.PRESET_TOP_RIGHT:
		c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	elif preset == Control.PRESET_TOP_LEFT:
		c.grow_horizontal = Control.GROW_DIRECTION_END
	if preset == Control.PRESET_CENTER_BOTTOM:
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _label(parent: Control, text: String, font_size: int,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	_style_label(l, font_size)
	parent.add_child(l)
	return l


func _style_label(l: Label, font_size: int) -> void:
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(240, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _set_bulb(bulb: Panel, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.05, 0.05) if on else Color(0.18, 0.02, 0.02)
	sb.set_corner_radius_all(21)
	bulb.add_theme_stylebox_override("panel", sb)
