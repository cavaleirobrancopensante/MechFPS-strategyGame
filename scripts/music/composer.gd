extends RefCounted
## Composes one song from a short description and synthesises it into a
## loopable 16-bit sound. No audio files: drums, bass, pads, arpeggios and
## the lead melody are all generated here.
##
## Rendering is split into small pieces so it can run a little each frame
## (or all at once on a background thread): call prepare(), then call
## work(deadline_usec) until it returns true, then take `stream`.

const RATE := 22050
const BARS := 16
const STEPS := 16  ## sixteenth notes per bar

const SCALES := {
	"minor": [0, 2, 3, 5, 7, 8, 10],
	"major": [0, 2, 4, 5, 7, 9, 11],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
	"harmonic": [0, 2, 3, 5, 7, 8, 11],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
}

## k = kick, s = snare, h = closed hat, o = open hat (steps in a bar).
const DRUMS := {
	"four": {"k": [0, 4, 8, 12], "s": [4, 12], "h": [0, 4, 8, 12], "o": [2, 6, 10, 14]},
	"rock": {"k": [0, 7, 8, 10], "s": [4, 12], "h": [0, 2, 4, 6, 8, 10, 12, 14], "o": []},
	"break": {"k": [0, 10], "s": [4, 7, 12, 15], "h": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], "o": []},
	"halftime": {"k": [0, 6, 11], "s": [8], "h": [0, 2, 4, 6, 8, 10, 12, 14], "o": []},
	"dnb": {"k": [0, 10], "s": [4, 12], "h": [0, 2, 3, 4, 6, 8, 10, 11, 12, 14], "o": [6]},
	"march": {"k": [0, 8], "s": [4, 12, 14, 15], "h": [0, 4, 8, 12], "o": []},
	"shuffle": {"k": [0, 7, 8], "s": [4, 12], "h": [0, 3, 4, 7, 8, 11, 12, 15], "o": []},
	"disco": {"k": [0, 4, 8, 12], "s": [4, 12], "h": [0, 1, 4, 5, 8, 9, 12, 13], "o": [2, 6, 10, 14]},
}

## One-bar rhythms for melodies: [step, length].
const RHYTHMS := [
	[[0, 3], [3, 3], [6, 2], [8, 4], [12, 4]],
	[[0, 2], [2, 2], [4, 4], [8, 2], [10, 2], [12, 4]],
	[[0, 4], [4, 2], [6, 2], [8, 6], [14, 2]],
	[[0, 1], [2, 1], [3, 3], [6, 2], [8, 2], [10, 6]],
	[[0, 6], [6, 2], [8, 3], [11, 5]],
	[[2, 2], [4, 2], [6, 2], [8, 4], [12, 2], [14, 2]],
	[[0, 2], [3, 1], [4, 2], [7, 1], [8, 4], [12, 2], [14, 2]],
	[[0, 8], [8, 2], [10, 2], [12, 4]],
	[[0, 3], [3, 1], [4, 3], [7, 1], [8, 3], [11, 1], [12, 4]],
	[[0, 2], [2, 2], [4, 2], [6, 2], [8, 8]],
]

enum Wave { SQUARE, PULSE, SAW, TRIANGLE, BELL, SINE }

var stream: AudioStreamWAV
var progress := 0.0

var _def: Dictionary
var _rng := RandomNumberGenerator.new()
var _scale: Array
var _step_n := 0.0
var _n := 0
var _tail := 0
var _mix := PackedFloat32Array()
var _lead := PackedFloat32Array()
var _events: Array = []
var _ev_i := 0
var _stage := 0
var _cursor := 0
var _drum := {}


func prepare(def: Dictionary) -> void:
	_def = def
	_rng.seed = int(def.get("seed", 1))
	_scale = SCALES[def.get("scale", "minor")]
	var bpm: float = def.get("bpm", 120.0)
	_step_n = 60.0 / bpm / 4.0 * RATE
	_n = int(BARS * STEPS * _step_n)
	_tail = int(RATE * 2.0)
	_mix.resize(_n + _tail)
	_mix.fill(0.0)
	_lead.resize(_n + _tail)
	_lead.fill(0.0)
	_build_tables()
	_build_drum_samples()
	_compose()
	_ev_i = 0
	_stage = 0
	_cursor = 0


func work(deadline_usec: int) -> bool:
	## Renders until the deadline. Returns true once the song is finished.
	while Time.get_ticks_usec() < deadline_usec:
		match _stage:
			0:
				if _ev_i >= _events.size():
					_stage = 1
					_cursor = 0
					continue
				_render_event(_events[_ev_i])
				_ev_i += 1
				progress = 0.85 * _ev_i / maxf(1.0, _events.size())
			1:
				# Echo on the lead, then fold the tail over the start so the loop is seamless.
				var d := int(_step_n * 3.0)
				var end := mini(_cursor + 20000, _n + _tail)
				for i in range(maxi(_cursor, d), end):
					_lead[i] += _lead[i - d] * 0.32
				_cursor = end
				if _cursor >= _n + _tail:
					for i in _tail:
						_mix[i] += _mix[_n + i] + _lead[_n + i]
					_stage = 2
					_cursor = 0
			2:
				_finish_chunk()
				if _stage == 3:
					return true
			3:
				return true
	return false


# =============================================================================
# Composition: turns the song description into note events
# =============================================================================

func _deg_semi(deg: int) -> int:
	return _scale[posmod(deg, 7)] + 12 * floori(deg / 7.0)


func _chord_degs(root_deg: int) -> Array:
	return [root_deg, root_deg + 2, root_deg + 4]


func _step_sample(step: float) -> int:
	var swing: float = _def.get("swing", 0.0)
	var s := step * _step_n
	if int(step) % 2 == 1:
		s += swing * _step_n
	return int(s)


func _note(step: float, len_steps: float, midi: int, inst: String, vol: float) -> void:
	_events.append([_step_sample(step), int(len_steps * _step_n), 440.0 * pow(2.0, (midi - 69) / 12.0), inst, vol])


func _compose() -> void:
	_events.clear()
	var prog: Array = _def.get("prog", [0, 5, 3, 4])
	var key: int = _def.get("key", 45)
	var drums: Dictionary = DRUMS[_def.get("drums", "four")]
	var bass_style: String = _def.get("bass", "octave")
	var pad_vol: float = _def.get("pad", 0.5)

	for bar in BARS:
		var b0 := bar * STEPS
		var chord_deg: int = prog[bar % prog.size()]
		var root := key + _deg_semi(chord_deg)
		var fifth := key + _deg_semi(chord_deg + 4)
		var third := key + _deg_semi(chord_deg + 2)

		# Drums, with a fill at the end of the loop and crashes on section starts.
		var fill := bar == BARS - 1
		for st: int in drums["k"]:
			_events.append([_step_sample(b0 + st), 0, 0.0, "kick", 0.9])
		for st: int in drums["s"]:
			if not (fill and st >= 12):
				_events.append([_step_sample(b0 + st), 0, 0.0, "snare", 0.55 if st % 4 == 0 else 0.25])
		if fill:
			for st in range(12, 16):
				_events.append([_step_sample(b0 + st), 0, 0.0, "snare", 0.3 + 0.08 * (st - 12)])
		for st: int in drums["h"]:
			if not drums["o"].has(st):
				_events.append([_step_sample(b0 + st), 0, 0.0, "hat", 0.22 if st % 2 == 0 else 0.14])
		for st: int in drums["o"]:
			_events.append([_step_sample(b0 + st), 0, 0.0, "ohat", 0.2])
		if bar == 0 or bar == 4 or bar == 12:
			_events.append([_step_sample(b0), 0, 0.0, "crash", 0.35])

		# Bass line
		match bass_style:
			"octave":
				for i in 8:
					_note(b0 + i * 2, 1.7, root + (12 if i % 2 == 1 else 0), "bass", 0.42)
			"pulse":
				for i in 8:
					_note(b0 + i * 2, 1.6, root, "bass", 0.42)
			"sync":
				for st in [0, 3, 6, 8, 11, 14]:
					_note(b0 + st, 2.0, fifth - 12 if st == 11 else root, "bass", 0.45)
			"walk":
				var next_root := key + _deg_semi(prog[(bar + 1) % prog.size()])
				var notes := [root, third, fifth, next_root - 1 if next_root > root else next_root + 1]
				for i in 4:
					_note(b0 + i * 4, 3.5, notes[i], "bass", 0.45)
			_:  # "long"
				_note(b0, 7.5, root, "bass", 0.45)
				_note(b0 + 8, 4.0, root, "bass", 0.4)
				_note(b0 + 12, 4.0, fifth - 12, "bass", 0.38)

		# Soft pad holding the chord
		if pad_vol > 0.0:
			for d in _chord_degs(chord_deg):
				_note(b0, 16.0, key + 12 + _deg_semi(d), "pad", 0.05 * pad_vol)

		# Arpeggio
		if _def.get("arp", false):
			var tones := [key + 24 + _deg_semi(chord_deg), key + 24 + _deg_semi(chord_deg + 2), key + 24 + _deg_semi(chord_deg + 4), key + 36 + _deg_semi(chord_deg)]
			var arp_vol := 0.09 if bar < 4 else 0.05
			for st in 16:
				_note(b0 + st, 0.9, tones[[0, 1, 2, 3, 2, 1][st % 6]], "arp", arp_vol)

	_compose_melody(prog, key)


func _compose_melody(prog: Array, key: int) -> void:
	## Catchy structure: groove (no melody) → phrase A → phrase A again with
	## a resolved ending → phrase B higher up, then the loop starts over.
	var lead_key := key + 24
	var phrase_a := _make_phrase(prog, 0, 7)
	var phrase_b := _make_phrase(prog, 0, 10)
	var inst: String = _def.get("lead", "square")
	_place_phrase(phrase_a, 4, lead_key, inst, false)
	_place_phrase(phrase_a, 8, lead_key, inst, true)
	_place_phrase(phrase_b, 12, lead_key, inst, true)


func _make_phrase(prog: Array, first_bar: int, center: int) -> Array:
	## Two bars of motif, then the same motif moved to follow the chords.
	var r1: Array = RHYTHMS[_rng.randi_range(0, RHYTHMS.size() - 1)]
	var r2: Array = RHYTHMS[_rng.randi_range(0, RHYTHMS.size() - 1)]
	var cur := center + _rng.randi_range(-2, 2)
	var motif: Array = []  # [bar_offset, step, len, deg]
	for bi in 2:
		var rhythm: Array = r1 if bi == 0 else r2
		var chord_deg: int = prog[(first_bar + bi) % prog.size()]
		for n: Array in rhythm:
			var st: int = n[0]
			if st % 4 == 0:
				# Strong beats land on a chord tone near the last note.
				var best := cur
				var best_d := 99
				for base in _chord_degs(chord_deg):
					for octv in [-7, 0, 7, 14]:
						var cand: int = base + octv
						var dd: int = absi(cand - cur) + _rng.randi_range(0, 1)
						if dd < best_d:
							best_d = dd
							best = cand
				cur = best
			else:
				cur += [-1, 1, -2, 2, 1, -1, 0][_rng.randi_range(0, 6)]
			cur = clampi(cur, center - 5, center + 6)
			motif.append([bi, st, n[1], cur])
	var shift: int = prog[(first_bar + 2) % prog.size()] - prog[first_bar % prog.size()]
	var phrase := motif.duplicate(true)
	for m: Array in motif:
		phrase.append([m[0] + 2, m[1], m[2], clampi(m[3] + shift, center - 6, center + 8)])
	return phrase


func _place_phrase(phrase: Array, bar: int, lead_key: int, inst: String, resolve: bool) -> void:
	var last := phrase.size() - 1
	for i in phrase.size():
		var m: Array = phrase[i]
		var deg: int = m[3]
		var length: float = m[2]
		if resolve and i == last:
			# End on the home note so the phrase feels finished.
			deg = 7 * int(round(deg / 7.0))
			length = maxf(length, 4.0)
		_note((bar + m[0]) * STEPS + m[1], length * 0.92, lead_key + _deg_semi(deg), inst, 0.16)


# =============================================================================
# Synthesis
# =============================================================================

func _build_drum_samples() -> void:
	_drum.clear()
	var kick := PackedFloat32Array()
	kick.resize(int(RATE * 0.3))
	var ph := 0.0
	for i in kick.size():
		var t := float(i) / RATE
		ph += (45.0 + 110.0 * exp(-t * 28.0)) / RATE
		kick[i] = sin(TAU * ph) * exp(-t * 9.0) + (_rng.randf_range(-0.3, 0.3) * exp(-t * 200.0))
	_drum["kick"] = kick
	var snare := PackedFloat32Array()
	snare.resize(int(RATE * 0.22))
	var lp := 0.0
	for i in snare.size():
		var t := float(i) / RATE
		lp += (_rng.randf_range(-1, 1) - lp) * 0.6
		snare[i] = lp * exp(-t * 18.0) * 0.8 + sin(TAU * 185.0 * t) * exp(-t * 30.0) * 0.5
	_drum["snare"] = snare
	for name in ["hat", "ohat", "crash"]:
		var dur: float = {"hat": 0.05, "ohat": 0.25, "crash": 1.4}[name]
		var dec: float = {"hat": 90.0, "ohat": 12.0, "crash": 2.8}[name]
		var buf := PackedFloat32Array()
		buf.resize(int(RATE * dur))
		var prev := 0.0
		for i in buf.size():
			var nz := _rng.randf_range(-1, 1)
			buf[i] = (nz - prev) * 0.5 * exp(-float(i) / RATE * dec)
			prev = nz
		_drum[name] = buf


func _render_event(ev: Array) -> void:
	var start: int = ev[0]
	var inst: String = ev[3]
	var vol: float = ev[4]
	if _drum.has(inst):
		var smp: PackedFloat32Array = _drum[inst]
		var end := mini(smp.size(), _n + _tail - start)
		for i in end:
			_mix[start + i] += smp[i] * vol
		return
	var length: int = ev[1]
	var freq: float = ev[2]
	match inst:
		"bass":
			_tone(_mix, start, length, freq, Wave.SAW, vol, 0.004, 0.02, 0.35, 0.18)
		"pad":
			_tone(_mix, start, length, freq, Wave.SAW, vol * 1.2, 0.25, 0.4, 0.0, 0.07)
		"arp":
			_tone(_mix, start, length, freq, Wave.PULSE, vol, 0.002, 0.05, 6.0, 0.5)
		_:
			var wave := Wave.SQUARE
			var decay := 0.8
			match inst:
				"pulse": wave = Wave.PULSE
				"saw": wave = Wave.SAW
				"triangle": wave = Wave.TRIANGLE
				"bell":
					wave = Wave.BELL
					decay = 3.0
				"sine": wave = Wave.SINE
			_tone(_lead, start, length, freq, wave, vol, 0.008, 0.05, decay, 0.45)


func _tone(buf: PackedFloat32Array, start: int, length: int, freq: float, wave: int, vol: float, attack: float, release: float, decay: float, bright: float) -> void:
	## One note: wavetable oscillator → simple low-pass → envelope, added into
	## buf. Split into attack / hold / release so the inner loops stay simple.
	var a := mini(maxi(1, int(attack * RATE)), length)
	var r := maxi(1, int(release * RATE))
	var total := mini(length + r, _n + _tail - start)
	if total <= 0:
		return
	var st := {"ph": 0.0, "lp": 0.0, "dec": 1.0, "mod": 0.0}
	var inc := freq / RATE
	var k := clampf(bright, 0.01, 1.0)
	var dmul := exp(-decay / RATE) if decay > 0.0 else 1.0
	_seg(buf, start, 0, mini(a, total), 0, a, wave, inc, k, dmul, vol, st)
	_seg(buf, start, mini(a, total), mini(length, total), 1, 0, wave, inc, k, dmul, vol, st)
	_seg(buf, start, mini(length, total), total, 2, r, wave, inc, k, dmul, vol, st, length)


func _seg(buf: PackedFloat32Array, start: int, i0: int, i1: int, mode: int, span: int, wave: int, inc: float, k: float, dmul: float, vol: float, st: Dictionary, rel_from := 0) -> void:
	## mode 0 = attack ramp, 1 = hold, 2 = release fade.
	if i1 <= i0:
		return
	var ph: float = st["ph"]
	var lp: float = st["lp"]
	var dec: float = st["dec"]
	if wave == Wave.BELL:
		var mph: float = st["mod"]
		for i in range(i0, i1):
			ph += inc
			if ph >= 1.0:
				ph -= 1.0
			mph += inc * 3.5
			if mph >= 1.0:
				mph -= 1.0
			var x := sin(TAU * ph + 1.6 * dec * sin(TAU * mph))
			var env := dec
			if mode == 0:
				env *= float(i) / span
			elif mode == 2:
				env *= 1.0 - float(i - rel_from) / span
			dec *= dmul
			buf[start + i] += x * env * vol
		st["mod"] = mph
	else:
		var table: PackedFloat32Array = _tables[wave]
		if mode == 1:
			for i in range(i0, i1):
				ph += inc
				if ph >= 1.0:
					ph -= 1.0
				lp += (table[int(ph * 256.0)] - lp) * k
				buf[start + i] += lp * dec * vol
				dec *= dmul
		else:
			for i in range(i0, i1):
				ph += inc
				if ph >= 1.0:
					ph -= 1.0
				lp += (table[int(ph * 256.0)] - lp) * k
				var env := dec * (float(i) / span if mode == 0 else 1.0 - float(i - rel_from) / span)
				buf[start + i] += lp * env * vol
				dec *= dmul
	st["ph"] = ph
	st["lp"] = lp
	st["dec"] = dec


func _build_tables() -> void:
	_tables.clear()
	for wave in [Wave.SQUARE, Wave.PULSE, Wave.SAW, Wave.TRIANGLE, Wave.BELL, Wave.SINE]:
		var t := PackedFloat32Array()
		t.resize(257)
		for i in 257:
			var ph := float(i % 256) / 256.0
			match wave:
				Wave.SQUARE: t[i] = 1.0 if ph < 0.5 else -1.0
				Wave.PULSE: t[i] = 1.0 if ph < 0.25 else -1.0
				Wave.SAW: t[i] = ph * 2.0 - 1.0
				Wave.TRIANGLE: t[i] = 4.0 * absf(ph - 0.5) - 1.0
				_: t[i] = sin(TAU * ph)
		_tables[wave] = t


var _tables := {}


func _finish_chunk() -> void:
	## Soft-clip and convert to 16-bit, a slice at a time.
	if _cursor == 0:
		_bytes = PackedByteArray()
		_bytes.resize(_n * 2)
	var end := mini(_cursor + 30000, _n)
	for i in range(_cursor, end):
		var x := (_mix[i] + _lead[i]) * 0.9
		x = x * (27.0 + x * x) / (27.0 + 9.0 * x * x)
		_bytes.encode_s16(i * 2, int(clampf(x, -1.0, 1.0) * 30000.0))
	_cursor = end
	progress = 0.9 + 0.1 * float(_cursor) / _n
	if _cursor >= _n:
		stream = AudioStreamWAV.new()
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.mix_rate = RATE
		stream.stereo = false
		stream.data = _bytes
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = _n
		_mix = PackedFloat32Array()
		_lead = PackedFloat32Array()
		_bytes = PackedByteArray()
		_stage = 3


var _bytes := PackedByteArray()
