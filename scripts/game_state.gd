extends Node
## Global settings, track list, persistent best laps and the input map.

const SETTINGS_PATH := "user://settings.cfg"

## Centerlines come from the TUM racetrack-database (LGPL-3.0), see tracks/.
const TRACKS := [
	{"id": "monza", "name": "Monza", "country": "Italy", "file": "res://tracks/monza.csv"},
	{"id": "silverstone", "name": "Silverstone", "country": "Great Britain", "file": "res://tracks/silverstone.csv"},
	{"id": "spa", "name": "Spa-Francorchamps", "country": "Belgium", "file": "res://tracks/spa.csv"},
	{"id": "suzuka", "name": "Suzuka", "country": "Japan", "file": "res://tracks/suzuka.csv"},
]

const LAP_OPTIONS := [1, 3, 5, 10]
const OPPONENT_OPTIONS := [0, 3, 5, 9]

## Fictional grid. Colors are loosely "team-like" without any branding.
const DRIVERS := [
	{"name": "YOU", "color": Color(0.9, 0.05, 0.05)},
	{"name": "VERSANO", "color": Color(0.05, 0.1, 0.45)},
	{"name": "HALLORAN", "color": Color(0.0, 0.62, 0.6)},
	{"name": "OKAFOR", "color": Color(1.0, 0.5, 0.0)},
	{"name": "LINDQVIST", "color": Color(0.0, 0.35, 0.2)},
	{"name": "MORAES", "color": Color(0.95, 0.95, 0.95)},
	{"name": "TAKEDA", "color": Color(0.15, 0.35, 0.95)},
	{"name": "DUBOIS", "color": Color(0.95, 0.4, 0.7)},
	{"name": "KOWALSKI", "color": Color(0.35, 0.35, 0.38)},
	{"name": "ARMSTRONG", "color": Color(0.55, 0.85, 0.1)},
]

var settings := {
	"track": 0,
	"laps": 3,
	"opponents": 5,
	"steering": 0,  # 0 arrows, 1 wheel (drag), 2 tilt
	"tilt_invert": false,
	"steer_sensitivity": 1.0,
	"steer_assist": 0,  # 0 off, 1 low, 2 high
	"auto_throttle": true,
	"braking_assist": 2,  # 0 off, 1 low, 2 high
	"control_size": 1.0,
	"control_opacity": 0.75,
	"mirrored": false,
	"haptics": true,
	"camera": 0,
}

var best_laps := {}  # track id -> seconds


func _ready() -> void:
	_setup_input()
	_load()


func current_track() -> Dictionary:
	return TRACKS[clampi(settings.track, 0, TRACKS.size() - 1)]


func record_lap(track_id: String, seconds: float) -> bool:
	if not best_laps.has(track_id) or seconds < best_laps[track_id]:
		best_laps[track_id] = seconds
		save()
		return true
	return false


func save() -> void:
	var cfg := ConfigFile.new()
	for key in settings:
		cfg.set_value("settings", key, settings[key])
	for key in best_laps:
		cfg.set_value("best_laps", key, best_laps[key])
	cfg.save(SETTINGS_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for key in settings:
		settings[key] = cfg.get_value("settings", key, settings[key])
	# Older saves: steering 3 meant "tilt inverted", braking assist was a bool.
	if settings.steering == 3:
		settings.steering = 2
		settings.tilt_invert = true
	if settings.braking_assist is bool:
		settings.braking_assist = 2 if settings.braking_assist else 0
	if cfg.has_section("best_laps"):
		for key in cfg.get_section_keys("best_laps"):
			best_laps[key] = cfg.get_value("best_laps", key)


## Shared look for menus and HUD panels: dark glassy buttons, red accent.
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24
	var normal := _box(Color(0.12, 0.12, 0.16, 0.92), Color(1, 1, 1, 0.08), 2)
	var hover := _box(Color(0.17, 0.17, 0.22, 0.95), Color(1, 1, 1, 0.18), 2)
	var pressed := _box(Color(0.22, 0.05, 0.05, 0.95), Color(0.88, 0.02, 0.0), 2)
	pressed.border_width_left = 8
	for st in [normal, hover, pressed]:
		st.content_margin_left = 22
		st.content_margin_right = 22
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("hover_pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.92, 0.92, 0.95))
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	var panel := _box(Color(0.05, 0.05, 0.08, 0.94), Color(0.88, 0.02, 0.0), 0)
	panel.border_width_top = 6
	panel.set_content_margin_all(28)
	t.set_stylebox("panel", "PanelContainer", panel)
	return t


## Big red call-to-action button style (START RACE, RACE AGAIN).
static func style_primary(b: Button) -> void:
	b.add_theme_stylebox_override("normal", _box(Color(0.88, 0.02, 0.0), Color(1, 1, 1, 0.15), 2))
	b.add_theme_stylebox_override("hover", _box(Color(1.0, 0.18, 0.12), Color(1, 1, 1, 0.3), 2))
	b.add_theme_stylebox_override("pressed", _box(Color(0.7, 0.0, 0.0), Color(1, 1, 1, 0.3), 2))


static func _box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(12)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.anti_aliasing = true
	return sb


static func format_time(seconds: float) -> String:
	if seconds <= 0.0 or is_inf(seconds):
		return "--:--.---"
	var m := int(seconds / 60.0)
	var s := seconds - m * 60.0
	return "%d:%06.3f" % [m, s]


func _setup_input() -> void:
	var bindings := {
		"accelerate": [KEY_W, KEY_UP],
		"brake": [KEY_S, KEY_DOWN, KEY_SPACE],
		"steer_left": [KEY_A, KEY_LEFT],
		"steer_right": [KEY_D, KEY_RIGHT],
		"camera": [KEY_C],
		"reset_car": [KEY_R],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	# Gamepad support comes almost for free.
	var pad := {
		"accelerate": JOY_AXIS_TRIGGER_RIGHT,
		"brake": JOY_AXIS_TRIGGER_LEFT,
	}
	for action in pad:
		var ev := InputEventJoypadMotion.new()
		ev.axis = pad[action]
		ev.axis_value = 1.0
		InputMap.action_add_event(action, ev)
	for pair in [["steer_left", -1.0], ["steer_right", 1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_LEFT_X
		ev.axis_value = pair[1]
		InputMap.action_add_event(pair[0], ev)
