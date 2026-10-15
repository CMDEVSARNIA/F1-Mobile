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
	"steering": 0,  # 0 touch, 1 tilt, 2 tilt inverted
	"braking_assist": true,
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
	if cfg.has_section("best_laps"):
		for key in cfg.get_section_keys("best_laps"):
			best_laps[key] = cfg.get_value("best_laps", key)


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
