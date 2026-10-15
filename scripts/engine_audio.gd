extends AudioStreamPlayer
## Procedural engine sound (no audio assets needed). Pitch follows car rpm.

const MIX_RATE := 22050.0

var car: Node
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _lp := 0.0
var _freq := 200.0
var _amp := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.08
	stream = gen
	volume_db = -8.0
	play()
	_playback = get_stream_playback()


func _process(_dt: float) -> void:
	if _playback == null or car == null:
		return
	# V6 four-stroke: 3 combustion pulses per crank revolution.
	var target_freq: float = car.rpm / 60.0 * 3.0 * 0.5
	var target_amp: float = 0.18 + 0.32 * car.throttle
	var frames := _playback.get_frames_available()
	for i in frames:
		_freq += (target_freq - _freq) * 0.002
		_amp += (target_amp - _amp) * 0.001
		_phase = fmod(_phase + _freq / MIX_RATE, 1.0)
		_phase2 = fmod(_phase2 + _freq * 0.5 / MIX_RATE, 1.0)
		var saw := _phase * 2.0 - 1.0
		var sq := 1.0 if _phase2 < 0.5 else -1.0
		var s := saw * 0.6 + sq * 0.25 + randf_range(-0.15, 0.15)
		_lp += (s - _lp) * 0.35
		var v := _lp * _amp
		_playback.push_frame(Vector2(v, v))
