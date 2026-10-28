extends Control
## Main menu: mode tabs (Quick race / Season / Time trial), circuit list or
## season calendar on the left, mode settings and start on the right.
## Built in code, sized for thumbs.

const LOGO := preload("res://assets/ui/logo.png")
const MODES := [["race", "QUICK RACE"], ["season", "SEASON"], ["time_trial", "TIME TRIAL"]]
const TYRES := ["Soft", "Medium", "Hard"]
const SEASON_NAMES := {"short": "Short (5 rounds)", "medium": "Medium (10 rounds)", "full": "Full (16 rounds)"}

var _tabs: Array[Button] = []
var _left: VBoxContainer
var _right: VBoxContainer
var _scroll: ScrollContainer
var _track_buttons: Array[Button] = []
var _season_length := "short"
var _confirm_reset := false


func _ready() -> void:
	theme = GameState.make_theme()
	var bg := ColorRect.new()
	bg.color = GameState.BRAND_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Red over gold pinstripes, as across the top of the logo.
	for spec in [[GameState.BRAND_RED, 0, 5], [GameState.BRAND_GOLD, 7, 10]]:
		var stripe := ColorRect.new()
		stripe.color = spec[0]
		stripe.set_anchors_preset(Control.PRESET_TOP_WIDE)
		stripe.offset_top = spec[1]
		stripe.offset_bottom = spec[2]
		add_child(stripe)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)

	# Header: title + mode tabs
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	page.add_child(header)
	var title := TextureRect.new()
	title.texture = LOGO
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	title.custom_minimum_size = Vector2(0, 92)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	for m in MODES:
		var t := _button(header, m[1], _set_mode.bind(m[0]))
		t.toggle_mode = true
		t.custom_minimum_size = Vector2(190, 58)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.add_theme_font_size_override("font_size", 21)
		_tabs.append(t)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 36)
	page.add_child(body)
	_left = VBoxContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.add_theme_constant_override("separation", 10)
	body.add_child(_left)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(420, 0)
	_right.add_theme_constant_override("separation", 10)
	body.add_child(_right)

	if GameState.season_active():
		_season_length = GameState.season.length
	_rebuild()
	GameState.play_menu_music()


func _set_mode(m: String) -> void:
	GameState.mode = m
	_confirm_reset = false
	GameState.save()
	_rebuild()


func _rebuild() -> void:
	for i in MODES.size():
		_tabs[i].button_pressed = MODES[i][0] == GameState.mode
	for c in _left.get_children() + _right.get_children():
		c.queue_free()
	_track_buttons.clear()
	match GameState.mode:
		"season":
			_build_season()
		"time_trial":
			_build_track_list(true)
			_build_time_trial()
		_:
			_build_track_list(false)
			_build_quick_race()


# ------------------------------------------------------------ left: circuits

func _build_track_list(time_trial: bool) -> void:
	_heading(_left, "SELECT CIRCUIT")
	_scroll = _scroller(_left)
	var list: VBoxContainer = _scroll.get_child(0)
	for i in GameState.TRACKS.size():
		var t: Dictionary = GameState.TRACKS[i]
		var best: float = (GameState.tt_best if time_trial else GameState.best_laps).get(t.id, 0.0)
		var b := _button(list, "  %s  ·  %s      %s" % [t.name, t.country, GameState.format_time(best)],
				_select_track.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = i == GameState.settings.track
		_track_buttons.append(b)
	_scroll_to(_track_buttons[clampi(GameState.settings.track, 0, _track_buttons.size() - 1)])


func _select_track(i: int) -> void:
	GameState.settings.track = i
	for k in _track_buttons.size():
		_track_buttons[k].button_pressed = k == i
	if GameState.mode == "time_trial":
		_rebuild()  # refresh the best-lap panel


# ------------------------------------------------------------ right: modes

func _build_quick_race() -> void:
	_heading(_right, "RACE SETTINGS")
	_button(_right, "Laps: %d" % GameState.settings.laps, _cycle_setting.bind("laps", GameState.LAP_OPTIONS))
	_button(_right, "Opponents: %d" % GameState.settings.opponents,
			_cycle_setting.bind("opponents", GameState.OPPONENT_OPTIONS))
	_button(_right, "Starting tyres: %s" % TYRES[GameState.settings.start_compound],
			_cycle_setting.bind("start_compound", [0, 1, 2]))
	_controls_button()
	_spacer(_right)
	_hint(_right, "Keyboard: WASD/arrows, E DRS, C camera, R reset, Esc pause.\nTrack data: TUM racetrack-database (LGPL-3.0).")
	_start_button("START RACE", _start)


func _build_time_trial() -> void:
	_heading(_right, "TIME TRIAL")
	var t := GameState.current_track()
	var best: float = GameState.tt_best.get(t.id, 0.0)
	_info_panel(_right, [
		[t.name.to_upper(), 26, Color.WHITE],
		["Best lap  " + GameState.format_time(best), 24, Color(0.3, 1.0, 0.45) if best > 0.0 else Color(0.7, 0.7, 0.75)],
		["Ghost of your best lap: " + ("saved" if best > 0.0 else "set a valid lap to create one"), 18, Color(0.7, 0.7, 0.75)],
		["Soft tyres, DRS in every zone, no wear. Leaving the track invalidates the lap.", 18, Color(0.7, 0.7, 0.75)],
	])
	_controls_button()
	_spacer(_right)
	_start_button("START TIME TRIAL", _start)


func _build_season() -> void:
	var active := GameState.season_active()
	var complete := GameState.season_complete()
	# Left: calendar with results
	_heading(_left, "CALENDAR" if active else "SEASON")
	_scroll = _scroller(_left)
	var list: VBoxContainer = _scroll.get_child(0)
	var calendar: Array = GameState.season.calendar if active else GameState.SEASON_LENGTHS[_season_length]
	var next_button: Button
	for r in calendar.size():
		var t: Dictionary = GameState.TRACKS[GameState.track_index(calendar[r])]
		var status := ""
		if active and r < GameState.season.round:
			status = "winner  " + GameState.season.winners[r]
		elif active and r == GameState.season.round:
			status = "NEXT"
		var b := _button(list, "  R%d   %s      %s" % [r + 1, t.name, status], func(): pass)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = active and r == GameState.season.round
		if b.button_pressed:
			next_button = b
	if next_button:
		_scroll_to(next_button)

	# Right: standings + start
	if not active or complete:
		_heading(_right, "SEASON COMPLETE" if complete else "NEW SEASON")
		if complete:
			var st := GameState.season_standings()
			var you := _you_position(st)
			_info_panel(_right, [
				["CHAMPION  " + st[0][0], 28, GameState.BRAND_GOLD],
				["You finished P%d with %d points" % [you + 1, st[you][1]], 20, Color.WHITE],
			])
		_button(_right, "Length: " + SEASON_NAMES[_season_length], _cycle_season_length)
		_button(_right, "Laps per race: %d" % GameState.settings.laps, _cycle_setting.bind("laps", GameState.LAP_OPTIONS))
		_controls_button()
		_spacer(_right)
		_hint(_right, "Full 10-car grid, F1 points 25-18-15-12-10-8-6-4-2-1. The grid lines up in championship order.")
		_start_button("START SEASON", _start_season)
		return

	var round_no: int = GameState.season.round + 1
	_heading(_right, "ROUND %d OF %d" % [round_no, calendar.size()])
	var rows := []
	var st := GameState.season_standings()
	var you := _you_position(st)
	for i in mini(5, st.size()):
		rows.append(["%d.  %-10s  %d" % [i + 1, st[i][0], st[i][1]], 20, GameState.BRAND_GOLD if i == you else Color.WHITE])
	if you >= 5:
		rows.append(["%d.  %-10s  %d" % [you + 1, st[you][0], st[you][1]], 20, GameState.BRAND_GOLD])
	_info_panel(_right, rows)
	_button(_right, "Laps: %d   ·   Tyres: %s" % [GameState.settings.laps, TYRES[GameState.settings.start_compound]],
			_cycle_setting.bind("start_compound", [0, 1, 2]))
	_controls_button()
	_spacer(_right)
	var reset := _button(_right, "Tap twice to abandon season" if _confirm_reset else "Abandon season", _abandon_season)
	reset.custom_minimum_size.y = 44
	reset.add_theme_font_size_override("font_size", 18)
	var t: Dictionary = GameState.current_track()
	_start_button("START ROUND %d  ·  %s" % [round_no, t.name.to_upper()], _start)


func _you_position(standings: Array) -> int:
	for i in standings.size():
		if standings[i][0] == GameState.DRIVERS[0].name:
			return i
	return 0


func _cycle_setting(key: String, options: Array) -> void:
	var idx := options.find(GameState.settings[key])
	GameState.settings[key] = options[(idx + 1) % options.size()]
	_rebuild()


func _cycle_season_length() -> void:
	var keys := SEASON_NAMES.keys()
	_season_length = keys[(keys.find(_season_length) + 1) % keys.size()]
	_rebuild()


func _start_season() -> void:
	GameState.season_start(_season_length)
	_start()


func _abandon_season() -> void:
	if not _confirm_reset:
		_confirm_reset = true
		_rebuild()
		return
	GameState.season = {}
	GameState.save()
	_confirm_reset = false
	_rebuild()


func _open_controls() -> void:
	var panel := preload("res://scripts/ui/controls_panel.gd").new()
	panel.closed.connect(func():
		_rebuild()
		GameState.play_menu_music())
	add_child(panel)


func _start() -> void:
	GameState.save()
	# Building the circuit takes a moment on a phone: show the logo meanwhile.
	var cover := ColorRect.new()
	cover.color = Color.BLACK
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(cover)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	logo.offset_left = -360
	logo.offset_right = 360
	logo.offset_top = -170
	logo.offset_bottom = 100
	cover.add_child(logo)
	var info := Label.new()
	info.text = "LOADING  %s" % GameState.current_track().name.to_upper()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 22)
	info.add_theme_color_override("font_color", GameState.BRAND_GOLD)
	info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	info.offset_left = -400
	info.offset_right = 400
	info.offset_top = -90
	info.offset_bottom = -50
	cover.add_child(info)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/race.tscn")


# ------------------------------------------------------------ widgets

func _label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _heading(parent: Control, text: String) -> void:
	_label(parent, text, 20).add_theme_color_override("font_color", GameState.BRAND_GOLD)


func _hint(parent: Control, text: String) -> void:
	var l := _label(parent, text, 16)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))


func _spacer(parent: Control) -> void:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(s)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.add_theme_font_size_override("font_size", 23)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _start_button(text: String, cb: Callable) -> void:
	var b := _button(_right, text, cb)
	b.custom_minimum_size.y = 80
	b.add_theme_font_size_override("font_size", 28 if text.length() < 20 else 22)
	GameState.style_primary(b)


func _controls_button() -> void:
	var s := GameState.settings
	var assists := ["off", "low", "high"]
	var b := _button(_right, "CONTROLS & ASSISTS  ›\n%s  ·  %s  ·  %s gas  ·  TC %s" % [
			["Arrows", "Wheel", "Tilt"][clampi(s.steering, 0, 2)],
			"Realistic" if s.handling == 1 else "Arcade",
			"Auto" if s.auto_throttle else "Manual", assists[clampi(s.traction_control, 0, 2)]], _open_controls)
	b.custom_minimum_size.y = 80
	b.add_theme_font_size_override("font_size", 20)


## Dark card with lines of [text, size, colour].
func _info_panel(parent: Control, lines: Array) -> void:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.095, 0.1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(16)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	for line in lines:
		var l := _label(v, line[0], line[1])
		l.add_theme_color_override("font_color", line[2])
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(p)


## Touch-friendly scrolling list (the deadzone lets a thumb drag the list
## without pressing the button it started on).
func _scroller(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 14
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	return scroll


func _scroll_to(c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(c) and is_instance_valid(_scroll):
		_scroll.ensure_control_visible(c)
