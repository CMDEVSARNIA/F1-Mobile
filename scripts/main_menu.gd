extends Control
## Track select + race settings. Built in code, sized for thumbs.

var _track_buttons: Array[Button] = []
var _laps_btn: Button
var _opp_btn: Button
var _steer_btn: Button
var _assist_btn: Button
var _info: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var stripe := ColorRect.new()
	stripe.color = Color(0.88, 0.02, 0.0)
	stripe.set_anchors_preset(Control.PRESET_TOP_WIDE)
	stripe.offset_bottom = 8
	add_child(stripe)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 40)
	margin.add_child(root)

	# Left column: title + tracks
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	root.add_child(left)
	var title := _label(left, "F1 MOBILE", 56)
	title.add_theme_color_override("font_color", Color.WHITE)
	_label(left, "SELECT CIRCUIT", 20).add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	for i in GameState.TRACKS.size():
		var b := _button(left, "", _select_track.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		_track_buttons.append(b)
		_refresh_track_label(i)

	# Right column: settings + start
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 12)
	root.add_child(right)
	_label(right, "RACE SETTINGS", 20).add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_laps_btn = _button(right, "", _cycle_laps)
	_opp_btn = _button(right, "", _cycle_opponents)
	_steer_btn = _button(right, "", _cycle_steering)
	_assist_btn = _button(right, "", _toggle_assist)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	_info = _label(right, "", 16)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.text = "Keyboard: WASD/arrows, C camera, R reset, Esc pause.\nTrack data: TUM racetrack-database (LGPL-3.0)."
	_info.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	var start := _button(right, "START RACE", _start)
	start.custom_minimum_size.y = 84
	start.add_theme_font_size_override("font_size", 34)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.88, 0.02, 0.0)
	sb.set_corner_radius_all(10)
	start.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(1.0, 0.2, 0.15)
	start.add_theme_stylebox_override("hover", sbh)
	start.add_theme_stylebox_override("pressed", sbh)

	_refresh()


func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _refresh_track_label(i: int) -> void:
	var t: Dictionary = GameState.TRACKS[i]
	var best := GameState.format_time(GameState.best_laps.get(t.id, 0.0))
	_track_buttons[i].text = "  %s  -  %s        best %s" % [t.name, t.country, best]


func _refresh() -> void:
	var s := GameState.settings
	for i in _track_buttons.size():
		_track_buttons[i].button_pressed = i == s.track
	_laps_btn.text = "Laps: %d" % s.laps
	_opp_btn.text = "Opponents: %d" % s.opponents
	_steer_btn.text = "Steering: " + ["Touch buttons", "Tilt", "Tilt (inverted)"][s.steering]
	_assist_btn.text = "Braking assist: " + ("ON" if s.braking_assist else "OFF")


func _select_track(i: int) -> void:
	GameState.settings.track = i
	_refresh()


func _cycle(options: Array, current) -> Variant:
	var idx := options.find(current)
	return options[(idx + 1) % options.size()]


func _cycle_laps() -> void:
	GameState.settings.laps = _cycle(GameState.LAP_OPTIONS, GameState.settings.laps)
	_refresh()


func _cycle_opponents() -> void:
	GameState.settings.opponents = _cycle(GameState.OPPONENT_OPTIONS, GameState.settings.opponents)
	_refresh()


func _cycle_steering() -> void:
	GameState.settings.steering = (GameState.settings.steering + 1) % 3
	_refresh()


func _toggle_assist() -> void:
	GameState.settings.braking_assist = not GameState.settings.braking_assist
	_refresh()


func _start() -> void:
	GameState.save()
	get_tree().change_scene_to_file("res://scenes/race.tscn")
