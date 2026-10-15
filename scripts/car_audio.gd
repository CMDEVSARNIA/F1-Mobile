extends Node3D
## Engine, tyre-skid and impact sounds for one car (Kenney CC0 samples).
## The player's car is non-positional; AI cars are 3D so you hear them pass.

const ENGINE := preload("res://assets/kenney/audio/engine.ogg")
const SKID := preload("res://assets/kenney/audio/skid.ogg")
const IMPACT := preload("res://assets/kenney/audio/impact.ogg")

var car: Node
var positional := false

var _engine: Node
var _skid: Node
var _impact: Node


func _ready() -> void:
	_engine = _make(ENGINE, -6.0 if positional else -4.0)
	_skid = _make(SKID, -10.0)
	_impact = _make(IMPACT, -4.0)
	_engine.play()
	car.impact.connect(_on_impact)


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

	if car.skid > 0.2:
		if not _skid.playing:
			_skid.play()
		_skid.volume_db = linear_to_db(clampf(car.skid, 0.0, 1.0)) - 8.0
		_skid.pitch_scale = clampf(0.8 + absf(car.speed) / 120.0, 0.8, 1.4)
	elif _skid.playing:
		_skid.stop()


func _on_impact(strength: float) -> void:
	_impact.volume_db = clampf(remap(strength, 2.0, 30.0, -18.0, 0.0), -18.0, 0.0)
	_impact.play()
