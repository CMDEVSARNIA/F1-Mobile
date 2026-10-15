extends Node
## Global settings, track list, persistent best laps and the input map.

const SETTINGS_PATH := "user://settings.cfg"

## Centerlines come from the TUM racetrack-database (LGPL-3.0), see tracks/.
## Listed in calendar order; the last four are classic venues.
const TRACKS := [
	{"id": "melbourne", "name": "Albert Park", "country": "Australia", "file": "res://tracks/melbourne.csv"},
	{"id": "shanghai", "name": "Shanghai", "country": "China", "file": "res://tracks/shanghai.csv"},
	{"id": "suzuka", "name": "Suzuka", "country": "Japan", "file": "res://tracks/suzuka.csv"},
	{"id": "sakhir", "name": "Sakhir", "country": "Bahrain", "file": "res://tracks/sakhir.csv"},
	{"id": "catalunya", "name": "Barcelona-Catalunya", "country": "Spain", "file": "res://tracks/catalunya.csv"},
	{"id": "montreal", "name": "Gilles Villeneuve", "country": "Canada", "file": "res://tracks/montreal.csv"},
	{"id": "spielberg", "name": "Red Bull Ring", "country": "Austria", "file": "res://tracks/spielberg.csv"},
	{"id": "silverstone", "name": "Silverstone", "country": "Great Britain", "file": "res://tracks/silverstone.csv"},
	{"id": "spa", "name": "Spa-Francorchamps", "country": "Belgium", "file": "res://tracks/spa.csv"},
	{"id": "budapest", "name": "Hungaroring", "country": "Hungary", "file": "res://tracks/budapest.csv"},
	{"id": "zandvoort", "name": "Zandvoort", "country": "Netherlands", "file": "res://tracks/zandvoort.csv"},
	{"id": "monza", "name": "Monza", "country": "Italy", "file": "res://tracks/monza.csv"},
	{"id": "austin", "name": "Circuit of the Americas", "country": "USA", "file": "res://tracks/austin.csv"},
	{"id": "mexicocity", "name": "Hermanos Rodriguez", "country": "Mexico", "file": "res://tracks/mexicocity.csv"},
	{"id": "saopaulo", "name": "Interlagos", "country": "Brazil", "file": "res://tracks/saopaulo.csv"},
	{"id": "yasmarina", "name": "Yas Marina", "country": "Abu Dhabi", "file": "res://tracks/yasmarina.csv"},
	{"id": "sepang", "name": "Sepang", "country": "Malaysia (classic)", "file": "res://tracks/sepang.csv"},
	{"id": "hockenheim", "name": "Hockenheim", "country": "Germany (classic)", "file": "res://tracks/hockenheim.csv"},
	{"id": "nuerburgring", "name": "Nurburgring GP", "country": "Germany (classic)", "file": "res://tracks/nuerburgring.csv"},
	{"id": "sochi", "name": "Sochi", "country": "Russia (classic)", "file": "res://tracks/sochi.csv"},
]

const LAP_OPTIONS := [1, 3, 5, 10]
const OPPONENT_OPTIONS := [0, 3, 5, 9]

## Fictional grid. Colors are loosely "team-like" without any branding.
const DRIVERS := [
	{"name": "YOU", "color": Color(0.9, 0.05, 0.05), "accent": Color(1, 1, 1)},
	{"name": "VERSANO", "color": Color(0.05, 0.1, 0.45), "accent": Color(0.9, 0.1, 0.15)},
	{"name": "HALLORAN", "color": Color(0.0, 0.62, 0.6), "accent": Color(0.08, 0.08, 0.09)},
	{"name": "OKAFOR", "color": Color(1.0, 0.5, 0.0), "accent": Color(0.25, 0.65, 1.0)},
	{"name": "LINDQVIST", "color": Color(0.0, 0.35, 0.2), "accent": Color(0.8, 1.0, 0.3)},
	{"name": "MORAES", "color": Color(0.95, 0.95, 0.95), "accent": Color(0.85, 0.1, 0.1)},
	{"name": "TAKEDA", "color": Color(0.15, 0.35, 0.95), "accent": Color(1, 1, 1)},
	{"name": "DUBOIS", "color": Color(0.95, 0.4, 0.7), "accent": Color(0.2, 0.4, 0.95)},
	{"name": "KOWALSKI", "color": Color(0.35, 0.35, 0.38), "accent": Color(0.9, 0.15, 0.1)},
	{"name": "ARMSTRONG", "color": Color(0.55, 0.85, 0.1), "accent": Color(0.06, 0.06, 0.07)},
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
	"auto_drs": false,
	"start_compound": 1,
	"music": true,
	"camera": 0,
}

var best_laps := {}  # track id -> seconds
var tt_best := {}  # track id -> seconds, time trial only (has a ghost)

## Which game mode the menu is on: "race", "season" or "time_trial".
var mode := "race"

const POINTS := [25, 18, 15, 12, 10, 8, 6, 4, 2, 1]
const SEASON_LENGTHS := {
	"short": ["melbourne", "suzuka", "silverstone", "spa", "monza"],
	"medium": ["melbourne", "shanghai", "suzuka", "catalunya", "montreal", "silverstone",
			"spa", "monza", "austin", "saopaulo"],
	"full": ["melbourne", "shanghai", "suzuka", "sakhir", "catalunya", "montreal", "spielberg",
			"silverstone", "spa", "budapest", "zandvoort", "monza", "austin", "mexicocity",
			"saopaulo", "yasmarina"],
}
var season := {}


const MENU_MUSIC := "res://assets/music/menu_theme.ogg"
const MUSIC_DB := -8.0

var _music: AudioStreamPlayer
var _music_tween: Tween


func _ready() -> void:
	_setup_input()
	_load()
	# Lives on this autoload so the menu theme carries on across menu screens.
	_music = AudioStreamPlayer.new()
	_music.stream = load(MENU_MUSIC)
	_music.volume_db = -60.0
	add_child(_music)


func play_menu_music() -> void:
	if not settings.music:
		stop_music(0.3)
		return
	if not _music.playing:
		_music.play()
	_fade_music(MUSIC_DB, 1.5)


func stop_music(seconds := 1.0) -> void:
	if _music.playing:
		_fade_music(-60.0, seconds, true)


func _fade_music(db: float, seconds: float, stop_after := false) -> void:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", db, seconds)
	if stop_after:
		_music_tween.tween_callback(_music.stop)


func current_track() -> Dictionary:
	if mode == "season" and season_active() and not season_complete():
		return TRACKS[track_index(season.calendar[season.round])]
	return TRACKS[clampi(settings.track, 0, TRACKS.size() - 1)]


func track_index(id: String) -> int:
	for i in TRACKS.size():
		if TRACKS[i].id == id:
			return i
	return 0


# ------------------------------------------------------------ season

func season_active() -> bool:
	return not season.is_empty()


func season_complete() -> bool:
	return season_active() and season.round >= season.calendar.size()


func season_start(length: String) -> void:
	var pts := {}
	for d in DRIVERS:
		pts[d.name] = 0
	season = {"length": length, "calendar": SEASON_LENGTHS[length].duplicate(), "round": 0,
			"points": pts, "winners": []}
	save()


## `order` is driver names in finishing order. Returns points scored by each.
func season_award(order: Array) -> Dictionary:
	var gained := {}
	for i in order.size():
		var p: int = POINTS[i] if i < POINTS.size() else 0
		season.points[order[i]] = season.points.get(order[i], 0) + p
		gained[order[i]] = p
	season.winners.append(order[0])
	season.round += 1
	save()
	return gained


## [[name, points], ...] best first; ties keep driver order.
func season_standings() -> Array:
	var rows := []
	for d in DRIVERS:
		rows.append([d.name, season.points.get(d.name, 0) if season_active() else 0])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows


# ------------------------------------------------------------ ghosts

func ghost_path(track_id: String) -> String:
	return "user://ghost_%s.bin" % track_id


func save_ghost(track_id: String, seconds: float, samples: PackedFloat32Array) -> void:
	tt_best[track_id] = seconds
	var f := FileAccess.open(ghost_path(track_id), FileAccess.WRITE)
	if f:
		f.store_var(samples)
	save()


func load_ghost(track_id: String) -> PackedFloat32Array:
	if not tt_best.has(track_id) or not FileAccess.file_exists(ghost_path(track_id)):
		return PackedFloat32Array()
	var f := FileAccess.open(ghost_path(track_id), FileAccess.READ)
	var v = f.get_var() if f else null
	return v if v is PackedFloat32Array else PackedFloat32Array()


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
	for key in tt_best:
		cfg.set_value("tt_best", key, tt_best[key])
	cfg.set_value("state", "mode", mode)
	cfg.set_value("state", "season", season)
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
	if cfg.has_section("tt_best"):
		for key in cfg.get_section_keys("tt_best"):
			tt_best[key] = cfg.get_value("tt_best", key)
	mode = cfg.get_value("state", "mode", mode)
	season = cfg.get_value("state", "season", {})
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
		"drs": [KEY_E, KEY_SHIFT],
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
	var drs_pad := InputEventJoypadButton.new()
	drs_pad.button_index = JOY_BUTTON_A
	InputMap.action_add_event("drs", drs_pad)
	for pair in [["steer_left", -1.0], ["steer_right", 1.0]]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_LEFT_X
		ev.axis_value = pair[1]
		InputMap.action_add_event(pair[0], ev)
