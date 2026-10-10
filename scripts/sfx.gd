extends Node
## Procedurally generated sound effects (autoload "Sfx"). No audio files needed.

const RATE := 22050
const VOICES := 10

var _sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_sounds["gun"] = _make(0.11, _gun)
	_sounds["rocket"] = _make(0.45, _rocket)
	_sounds["boom"] = _make(1.0, _boom)
	_sounds["hit"] = _make(0.35, _hit)
	_sounds["screech"] = _make(0.45, _screech)
	_sounds["alarm"] = _make(0.35, _alarm)
	_sounds["step"] = _make(0.22, _step)
	_sounds["splat"] = _make(0.3, _splat)
	_sounds["click"] = _make(0.05, _click)
	_sounds["hatch"] = _make(0.9, _hatch)
	_sounds["pickup"] = _make(0.35, _pickup)


func play(name: String, volume_db := 0.0, pitch_jitter := 0.08, pitch := 1.0) -> void:
	if not _sounds.has(name):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _sounds[name]
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	p.play()


# --- Synthesis ------------------------------------------------------------

func _make(duration: float, gen: Callable) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var state := {"lp": 0.0, "lp2": 0.0, "phase": 0.0}
	for i in n:
		var t := float(i) / RATE
		var v: float = gen.call(t, duration, state)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


func _lowpass(state: Dictionary, x: float, k: float) -> float:
	state["lp"] += (x - state["lp"]) * k
	return state["lp"]


func _gun(t: float, d: float, st: Dictionary) -> float:
	var env := exp(-t * 38.0)
	var noise := _lowpass(st, randf_range(-1, 1), 0.35)
	var thump := sin(TAU * 90.0 * t) * exp(-t * 25.0)
	return (noise * 1.4 + thump * 0.8) * env


func _rocket(t: float, d: float, st: Dictionary) -> float:
	var env := minf(t * 20.0, 1.0) * (1.0 - t / d)
	var k := 0.05 + 0.25 * (t / d)
	return _lowpass(st, randf_range(-1, 1), k) * env * 1.6


func _boom(t: float, d: float, st: Dictionary) -> float:
	var env := exp(-t * 4.0)
	var rumble := _lowpass(st, randf_range(-1, 1), 0.06) * 3.0
	var sub := sin(TAU * (55.0 - 25.0 * t) * t) * exp(-t * 6.0)
	return (rumble + sub * 0.9) * env


func _hit(t: float, d: float, st: Dictionary) -> float:
	var env := exp(-t * 12.0)
	var clang := sin(TAU * 410.0 * t) * 0.5 + sin(TAU * 643.0 * t) * 0.35 + sin(TAU * 1170.0 * t) * 0.2
	var crunch := _lowpass(st, randf_range(-1, 1), 0.3) * exp(-t * 30.0)
	return clang * env * 0.8 + crunch


func _screech(t: float, d: float, st: Dictionary) -> float:
	var f := 900.0 - 600.0 * (t / d) + sin(TAU * 30.0 * t) * 120.0
	st["phase"] += f / RATE
	var saw: float = fmod(st["phase"], 1.0) * 2.0 - 1.0
	var env := minf(t * 30.0, 1.0) * (1.0 - t / d)
	return (saw * 0.5 + randf_range(-0.2, 0.2)) * env


func _alarm(t: float, d: float, st: Dictionary) -> float:
	var f := 880.0 if t < d * 0.5 else 660.0
	var sq := 1.0 if sin(TAU * f * t) > 0.0 else -1.0
	return sq * 0.25 * (1.0 - t / d)


func _step(t: float, d: float, st: Dictionary) -> float:
	var env := exp(-t * 18.0)
	var thud := sin(TAU * (70.0 - 40.0 * t) * t)
	var clank := _lowpass(st, randf_range(-1, 1), 0.15) * exp(-t * 40.0)
	return (thud + clank * 0.8) * env


func _splat(t: float, d: float, st: Dictionary) -> float:
	var env := exp(-t * 14.0)
	var wet := _lowpass(st, randf_range(-1, 1), 0.2 + 0.2 * sin(TAU * 40.0 * t))
	return wet * env * 1.8


func _click(t: float, d: float, st: Dictionary) -> float:
	return sin(TAU * 1500.0 * t) * exp(-t * 90.0) * 0.5


func _hatch(t: float, d: float, st: Dictionary) -> float:
	# Pneumatic hiss, then a metal clunk as the hatch locks.
	var hiss := _lowpass(st, randf_range(-1, 1), 0.5) * exp(-t * 3.0) * 0.7
	var tc := t - 0.55
	var clunk := 0.0
	if tc > 0.0:
		clunk = (sin(TAU * 140.0 * tc) + sin(TAU * 333.0 * tc) * 0.5) * exp(-tc * 25.0)
	return hiss + clunk


func _pickup(t: float, d: float, st: Dictionary) -> float:
	var f := 660.0 if t < 0.12 else 990.0
	return sin(TAU * f * t) * 0.4 * (1.0 - t / d)
