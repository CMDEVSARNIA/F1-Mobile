extends Node3D
## Engine, tyre-skid and impact sounds for one car (Kenney CC0 samples),
## plus gravel, heavy-crash and stall effects (assets/sfx).
## The player's car is non-positional; AI cars are 3D so you hear them pass.

const ENGINE := preload("res://assets/kenney/audio/engine.ogg")
const SKID := preload("res://assets/kenney/audio/skid.ogg")
const IMPACT := preload("res://assets/kenney/audio/impact.ogg")
const IMPACT_HEAVY := preload("res://assets/sfx/collision-heavy.ogg")
const GRAVEL := preload("res://assets/sfx/gravel-loop.ogg")
const STALL := preload("res://assets/sfx/engine-stall.ogg")
const HEAVY_HIT := 14.0  # impact strength (m/s into the wall) for the big crunch

var car: Node
var positional := false

var _engine: Node
var _skid: Node
var _impact: Node
var _impact_heavy: Node
var _gravel: Node
var _stall: Node
var _buzz_timer := 0.0


func _ready() -> void:
	_engine = _make(ENGINE, -6.0 if positional else -4.0)
	_skid = _make(SKID, -10.0)
	_impact = _make(IMPACT, -4.0)
	_impact_heavy = _make(IMPACT_HEAVY, -2.0)
	_gravel = _make(GRAVEL, -40.0)
	_stall = _make(STALL, -4.0)
	_engine.play()
	car.impact.connect(_on_impact)
	car.reset.connect(_on_reset)


func _make(stream: AudioStream, db: float) -> Node:
	var p: Node
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 12.0
		p3.max_distance = 160.0
		p3.panning_strength = 0.6
		p = p3
	else:
		p = AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _process(dt: float) -> void:
	if car == null:
		return
	# Sample is a mid-rev engine; stretch it up toward a V6 hybrid scream.
	var pitch := remap(car.rpm, 4000.0, 12000.0, 0.65, 2.3)
	_engine.pitch_scale = lerpf(_engine.pitch_scale, maxf(pitch, 0.5), clampf(dt * 10.0, 0.0, 1.0))
	var base := -6.0 if positional else -4.0
	var vol: float = base - 9.0 * (1.0 - car.throttle)
	_engine.volume_db = lerpf(_engine.volume_db, vol, clampf(dt * 6.0, 0.0, 1.0))

	# Feel the tyres let go: short pulses on wheelspin or lock-up.
	_buzz_timer -= dt
	if not positional and _buzz_timer <= 0.0 and (car.wheelspin > 0.5 or car.lockup > 0.5) \
			and GameState.settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(18)
		_buzz_timer = 0.15
	# Stones rattling under the floor in a gravel trap.
	var crunch := clampf(absf(car.speed) / 25.0, 0.0, 1.0) if car.on_gravel else 0.0
	if crunch > 0.02:
		if not _gravel.playing:
			_gravel.play()
		_gravel.volume_db = linear_to_db(crunch) - (6.0 if positional else 3.0)
		_gravel.pitch_scale = 0.85 + crunch * 0.3
	elif _gravel.playing:
		_gravel.stop()
	if car.skid > 0.2:
		if not _skid.playing:
			_skid.play()
		_skid.volume_db = linear_to_db(clampf(car.skid, 0.0, 1.0)) - 8.0
		_skid.pitch_scale = clampf(0.8 + absf(car.speed) / 120.0, 0.8, 1.4)
	elif _skid.playing:
		_skid.stop()


func _on_impact(strength: float) -> void:
	if not positional and GameState.settings.haptics and OS.has_feature("mobile"):
		Input.vibrate_handheld(int(clampf(strength * 3.0, 20.0, 90.0)))
	if strength >= HEAVY_HIT:
		_impact_heavy.volume_db = clampf(remap(strength, HEAVY_HIT, 45.0, -6.0, 0.0), -6.0, 0.0)
		_impact_heavy.play()
		return
	_impact.volume_db = clampf(remap(strength, 2.0, 30.0, -18.0, 0.0), -18.0, 0.0)
	_impact.play()


## Car put back on track: the engine cuts out and refires.
func _on_reset() -> void:
	if not positional:
		_stall.play()
