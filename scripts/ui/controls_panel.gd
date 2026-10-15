extends Control
## Full-screen "Controls & assists" overlay, shared by the main menu and the
## pause menu. Each row cycles through preset values with big ‹ › buttons.
## Changes are written to GameState.settings and saved on close.

signal closed
signal recalibrate_requested

const DOTS := ["●○○○○", "●●○○○", "●●●○○", "●●●●○", "●●●●●"]

## key, label, values, display names
const OPTIONS := [
	["steering", "Steering", [0, 1, 2], ["Arrows", "Wheel (drag)", "Tilt"]],
	["steer_sensitivity", "Sensitivity", [0.6, 0.8, 1.0, 1.25, 1.5], DOTS],
	["tilt_invert", "Tilt direction", [false, true], ["Normal", "Inverted"]],
	["steer_assist", "Steering assist", [0, 1, 2], ["Off", "Low", "High"]],
	["auto_throttle", "Throttle", [true, false], ["Auto", "Manual (Pro)"]],
	["braking_assist", "Braking assist", [0, 1, 2], ["Off", "Low", "High"]],
	["control_size", "Button size", [0.85, 1.0, 1.2], ["Small", "Medium", "Large"]],
	["control_opacity", "Button opacity", [0.4, 0.75, 1.0], ["Low", "Medium", "High"]],
	["mirrored", "Layout", [false, true], ["Steer left", "Steer right"]],
	["auto_drs", "DRS", [false, true], ["Tap to open", "Automatic"]],
	["haptics", "Vibration", [true, false], ["On", "Off"]],
	["music", "Menu music", [true, false], ["On", "Off"]],
]

var in_race := false
var _value_labels := {}


func _ready() -> void:
	# Anchors alone don't resize a node already in the tree; set offsets too.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "CONTROLS & ASSISTS"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for opt in OPTIONS:
		grid.add_child(_row(opt))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 20)
	box.add_child(footer)
	if in_race:
		var cal := _button("RECALIBRATE TILT", 24)
		cal.custom_minimum_size = Vector2(300, 60)
		cal.pressed.connect(recalibrate_requested.emit)
		footer.add_child(cal)
	var done := _button("DONE", 26)
	done.custom_minimum_size = Vector2(220, 60)
	GameState.style_primary(done)
	done.pressed.connect(_close)
	footer.add_child(done)

	var hint := Label.new()
	hint.text = "Tilt straightens itself at lights out: hold the phone how you'll race."
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_refresh()


func _row(opt: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name := Label.new()
	name.text = opt[1]
	name.custom_minimum_size = Vector2(190, 0)
	name.add_theme_font_size_override("font_size", 21)
	name.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	row.add_child(name)
	var prev := _button("‹", 30)
	prev.pressed.connect(_step.bind(opt, -1))
	row.add_child(prev)
	var value := Label.new()
	value.custom_minimum_size = Vector2(170, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 22)
	row.add_child(value)
	_value_labels[opt[0]] = value
	var next := _button("›", 30)
	next.pressed.connect(_step.bind(opt, 1))
	row.add_child(next)
	return row


func _button(text: String, font_size: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(56, 52)
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _step(opt: Array, dir: int) -> void:
	var values: Array = opt[2]
	var idx := _index_of(values, GameState.settings[opt[0]])
	GameState.settings[opt[0]] = values[wrapi(idx + dir, 0, values.size())]
	if OS.has_feature("mobile") and GameState.settings.haptics:
		Input.vibrate_handheld(8)
	_refresh()


## Index of the stored value, tolerant of float rounding in saved configs.
func _index_of(values: Array, v) -> int:
	for i in values.size():
		if typeof(values[i]) == TYPE_FLOAT and typeof(v) in [TYPE_FLOAT, TYPE_INT]:
			if absf(values[i] - v) < 0.01:
				return i
		elif values[i] == v:
			return i
	return 0


func _refresh() -> void:
	var tilt: bool = GameState.settings.steering == 2
	for opt in OPTIONS:
		var label: Label = _value_labels[opt[0]]
		label.text = opt[3][_index_of(opt[2], GameState.settings[opt[0]])]
		# Grey out what doesn't apply to the current steering mode.
		var applies: bool = not (opt[0] == "tilt_invert" and not tilt)
		label.get_parent().modulate.a = 1.0 if applies else 0.4


func _close() -> void:
	GameState.save()
	closed.emit()
	queue_free()
