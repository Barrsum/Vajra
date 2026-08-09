extends Node
## Procedural sound. Every clip is synthesised into an AudioStreamWAV at startup,
## so the project ships no audio files and every sound is a number you can tune
## exactly like damage or hit-stop.
##
## Autoloaded as `Sfx`.

const RATE := 22050
const VOICES := 14        ## positional players in the pool
const UI_VOICES := 4

var _bank: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _cursor := 0
var _ui_cursor := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_bank()

	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 40.0
		p.unit_size = 6.0
		add_child(p)
		_pool.append(p)

	for i in UI_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_ui_pool.append(p)


# --- playback ---------------------------------------------------------------

## Positional. `pitch_jitter` keeps repeated hits from sounding machine-gunned.
func play_at(name: StringName, pos: Vector3, volume_db := 0.0, pitch_jitter := 0.12) -> void:
	if not _bank.has(name):
		return
	var p := _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	p.stream = _bank[name]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play(name: StringName, volume_db := 0.0, pitch_jitter := 0.1) -> void:
	if not _bank.has(name):
		return
	var p := _ui_pool[_ui_cursor]
	_ui_cursor = (_ui_cursor + 1) % _ui_pool.size()
	p.stream = _bank[name]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	p.play()


# --- synthesis --------------------------------------------------------------

func _build_bank() -> void:
	_bank[&"swing_light"] = _swing(0.22, 2600.0, 700.0, 0.26)
	_bank[&"swing_heavy"] = _swing(0.34, 1500.0, 320.0, 0.32)
	_bank[&"impact_light"] = _impact(0.30, 190.0, 0.75)
	_bank[&"impact_heavy"] = _impact(0.55, 110.0, 1.0)
	_bank[&"finisher"] = _boom(0.85, 130.0)
	_bank[&"hurt"] = _hurt()
	_bank[&"dodge"] = _whoosh(0.28)
	_bank[&"footstep"] = _footstep()
	_bank[&"land"] = _impact(0.34, 130.0, 0.6)
	_bank[&"roar"] = _roar()
	_bank[&"death"] = _death()


func _stream(s: PackedFloat32Array) -> AudioStreamWAV:
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	st.data = bytes
	return st


func _n(seconds: float) -> int:
	return int(seconds * RATE)


## Exponential decay envelope with a short attack, so nothing clicks on.
func _env(i: int, total: int, attack := 0.004, curve := 5.0) -> float:
	var t := float(i) / RATE
	var a := minf(1.0, t / attack)
	var d := exp(-curve * float(i) / float(total))
	return a * d


## Air moving. Noise through a lowpass whose cutoff sweeps down.
func _swing(dur: float, f_start: float, f_end: float, amp: float) -> AudioStreamWAV:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var p := float(i) / n
		var cutoff: float = lerpf(f_start, f_end, p * p)
		var a: float = clampf(cutoff / (RATE * 0.5), 0.01, 0.99)
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		# Bell-shaped envelope — a swing swells and fades, it doesn't just decay.
		out[i] = y * amp * sin(p * PI) * 2.0
	return _stream(out)


## Something solid meeting something solid. Pitched-down sine gives it mass,
## a filtered noise crack on top makes it read as a strike rather than a thud.
func _impact(dur: float, f0: float, amp: float) -> AudioStreamWAV:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var y := 0.0
	for i in n:
		var p := float(i) / n
		var f: float = f0 * pow(0.32, p)
		phase += TAU * f / RATE
		var body := sin(phase) * _env(i, n, 0.002, 5.5)

		var a: float = clampf(lerpf(4200.0, 350.0, p * 3.0) / (RATE * 0.5), 0.01, 0.99)
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		var crack := y * _env(i, n, 0.001, 26.0) * 0.55

		out[i] = tanh((body + crack) * amp * 1.4)
	return _stream(out)


func _boom(dur: float, f0: float) -> AudioStreamWAV:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var y := 0.0
	for i in n:
		var p := float(i) / n
		var f: float = f0 * pow(0.22, p)
		phase += TAU * f / RATE
		var a: float = clampf(lerpf(2200.0, 180.0, p) / (RATE * 0.5), 0.01, 0.99)
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = tanh((sin(phase) * 1.1 + y * 0.6) * _env(i, n, 0.004, 3.2))
	return _stream(out)


func _hurt() -> AudioStreamWAV:
	var n := _n(0.26)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var p := float(i) / n
		var f: float = lerpf(160.0, 62.0, p)
		phase += TAU * f / RATE
		out[i] = signf(sin(phase)) * _env(i, n, 0.003, 6.0) * 0.42
	return _stream(out)


func _whoosh(dur: float) -> AudioStreamWAV:
	var n := _n(dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var p := float(i) / n
		# Cutoff rises then falls — the doppler-ish shape of something passing.
		var c: float = 700.0 + sin(p * PI) * 2400.0
		var a: float = clampf(c / (RATE * 0.5), 0.01, 0.99)
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * sin(p * PI) * 0.5
	return _stream(out)


func _footstep() -> AudioStreamWAV:
	var n := _n(0.10)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		y += 0.06 * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * _env(i, n, 0.001, 16.0) * 2.2
	return _stream(out)


## Detuned saws pitched down. Reads as large and not human.
func _roar() -> AudioStreamWAV:
	var n := _n(0.95)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := [0.0, 0.0, 0.0]
	var detune := [1.0, 1.006, 0.993]
	var y := 0.0
	for i in n:
		var p := float(i) / n
		var f: float = lerpf(140.0, 70.0, p) * (1.0 + sin(p * 34.0) * 0.03)
		var v := 0.0
		for k in 3:
			ph[k] += TAU * f * float(detune[k]) / RATE
			# Saw from phase, cheap and rough on purpose.
			v += fposmod(ph[k], TAU) / TAU * 2.0 - 1.0
		v /= 3.0
		var a: float = clampf(lerpf(900.0, 380.0, p) / (RATE * 0.5), 0.01, 0.99)
		y += a * (v - y)
		out[i] = tanh(y * 2.2) * _env(i, n, 0.05, 2.4) * 0.6
	return _stream(out)


func _death() -> AudioStreamWAV:
	var n := _n(0.75)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var y := 0.0
	for i in n:
		var p := float(i) / n
		var f: float = lerpf(300.0, 45.0, p * p)
		ph += TAU * f / RATE
		var saw := fposmod(ph, TAU) / TAU * 2.0 - 1.0
		var a: float = clampf(lerpf(2400.0, 200.0, p) / (RATE * 0.5), 0.01, 0.99)
		y += a * (saw - y)
		out[i] = tanh(y * 1.8) * _env(i, n, 0.01, 3.0) * 0.55
	return _stream(out)
