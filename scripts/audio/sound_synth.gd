class_name SoundSynth
extends RefCounted
## Placeholder sounds made from math (bible §29): small, soft, and tuned for a
## phone speaker (little energy below 150 Hz, where it cannot be heard anyway).
## They exist so the feedback loop can be built and tuned before real audio is
## recorded; a file in res://assets/audio/sfx/<id>.wav (or .ogg) replaces the
## generated sound of the same id (see AudioManager).
##
## Pure and deterministic: the same id always gives the same samples. Safe to
## run on a worker thread.

const RATE := 22050
## The wind is all low frequencies, so a low rate is enough (and quick to make).
const WIND_RATE := 11025
const WIND_SECONDS := 3.0

## Every sound this class can make.
const IDS: Array[StringName] = [
	&"thud", &"plip", &"rustle", &"click", &"knock", &"crackle", &"hum",
	&"chirp", &"ui_open", &"ui_tap", &"ui_close", &"wind",
]


## All sounds, as id -> AudioStreamWAV.
static func make_all() -> Dictionary:
	var out := {}
	for id in IDS:
		out[id] = make(id)
	return out


## One sound, or null for an unknown id.
static func make(id: StringName) -> AudioStreamWAV:
	var samples := samples_for(id)
	if samples.is_empty():
		return null
	var rate := WIND_RATE if id == &"wind" else RATE
	var stream := to_stream(samples, rate)
	if id == &"wind":
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


## Raw samples (-1..1) of a sound; empty for an unknown id.
static func samples_for(id: StringName) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(id)) # each sound has its own fixed noise
	match id:
		&"thud":
			return _finish(_thud(rng), 0.85)
		&"plip":
			return _finish(_plip(), 0.7)
		&"rustle":
			return _finish(_rustle(rng), 0.6)
		&"click":
			return _finish(_click(rng), 0.7)
		&"knock":
			return _finish(_knock(rng), 0.85)
		&"crackle":
			return _finish(_crackle(rng), 0.6)
		&"hum":
			return _finish(_hum(), 0.6)
		&"chirp":
			return _finish(_chirp(), 0.5)
		&"ui_open":
			return _finish(_blip(620.0, 930.0, 0.07), 0.45)
		&"ui_tap":
			return _finish(_blip(1050.0, 1050.0, 0.035), 0.4)
		&"ui_close":
			return _finish(_blip(880.0, 590.0, 0.07), 0.4)
		&"wind":
			return _wind(rng)
	return PackedFloat32Array()


## 16-bit mono stream from samples in -1..1.
static func to_stream(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = bytes
	return stream


static func seconds_of(samples: PackedFloat32Array, rate: int = RATE) -> float:
	return samples.size() / float(rate)


static func peak(samples: PackedFloat32Array) -> float:
	var top := 0.0
	for v in samples:
		top = maxf(top, absf(v))
	return top


# --- the sounds -------------------------------------------------------------------------

## A soft, low knock on earth: a falling tone with a puff of dull noise.
static func _thud(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.17 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var low := 0.0
	for i in n:
		var t := i / float(RATE)
		phase += TAU * lerpf(330.0, 185.0, minf(t / 0.08, 1.0)) / RATE
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.2 # dull noise
		# The overtone is what a small speaker actually reproduces.
		out[i] = (sin(phase) + 0.4 * sin(phase * 2.0)) * exp(-t / 0.045) + low * 1.4 * exp(-t / 0.02)
	return out


## A drop falling into water: a quick tone sliding upward.
static func _plip() -> PackedFloat32Array:
	var n := int(0.15 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / float(RATE)
		var rise := 1.0 - exp(-t / 0.03)
		phase += TAU * lerpf(520.0, 1450.0, rise) / RATE
		out[i] = sin(phase) * exp(-t / 0.04) * minf(t / 0.004, 1.0)
	return out


## Leaves: bright noise in a few overlapping gusts.
static func _rustle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var starts: Array[float] = [0.0, 0.09, 0.2, 0.31]
	var low := 0.0
	var bright := 0.0
	for i in n:
		var t := i / float(RATE)
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.35
		bright += ((white - low) - bright) * 0.45 # the hiss, with its harsh top taken off
		var envelope := 0.0
		for j in starts.size():
			var local := t - starts[j]
			if local >= 0.0:
				envelope += (1.0 - j * 0.18) * minf(local / 0.012, 1.0) * exp(-local / 0.055)
		out[i] = bright * envelope
	return out


## Stone on stone: a very short, bright tick.
static func _click(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.06 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := i / float(RATE)
		var ring := sin(TAU * 2150.0 * t) + 0.6 * sin(TAU * 3300.0 * t)
		out[i] = ring * exp(-t / 0.007) + rng.randf_range(-1.0, 1.0) * exp(-t / 0.0015)
	return out


## Knuckles on wood: two hollow knocks.
static func _knock(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.24 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var starts: Array[float] = [0.0, 0.115]
	for i in n:
		var t := i / float(RATE)
		var v := 0.0
		for j in starts.size():
			var local := t - starts[j]
			if local >= 0.0:
				var body := sin(TAU * 415.0 * local) + 0.5 * sin(TAU * 820.0 * local)
				v += (1.0 - j * 0.25) * (body * exp(-local / 0.02) + rng.randf_range(-1.0, 1.0) * 0.5 * exp(-local / 0.003))
		out[i] = v
	return out


## A stirred fire: a soft whoosh with a handful of pops.
static func _crackle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(0.36 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var pops: Array[int] = []
	for i in 9:
		pops.append(rng.randi_range(0, int(n * 0.75)))
	var low := 0.0
	for i in n:
		var t := i / float(RATE)
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.2
		out[i] = low * 0.5 * minf(t / 0.03, 1.0) * exp(-t / 0.14)
	for start in pops:
		var strength := rng.randf_range(0.4, 1.0)
		var pop := 0.0
		for k in int(0.012 * RATE):
			if start + k >= n:
				break
			pop += (rng.randf_range(-1.0, 1.0) - pop) * 0.5
			out[start + k] += pop * 1.6 * strength * exp(-k / (0.0025 * RATE))
	return out


## The old stones answer: a low chord that swells and fades.
static func _hum() -> PackedFloat32Array:
	var n := int(1.5 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := i / float(RATE)
		var wobble := 1.0 + 0.004 * sin(TAU * 4.5 * t)
		var chord := sin(TAU * 262.0 * wobble * t) + 0.6 * sin(TAU * 392.0 * wobble * t) + 0.35 * sin(TAU * 523.0 * t)
		var envelope := minf(t / 0.3, 1.0) * minf((1.5 - t) / 0.9, 1.0)
		out[i] = chord * envelope
	return out


## A small bird: three quick upward whistles.
static func _chirp() -> PackedFloat32Array:
	var n := int(0.3 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var starts: Array[float] = [0.0, 0.09, 0.18]
	var phase := 0.0
	for i in n:
		var t := i / float(RATE)
		var v := 0.0
		for j in starts.size():
			var local := t - starts[j]
			if local >= 0.0 and local < 0.07:
				phase += TAU * lerpf(2700.0, 3600.0 + j * 250.0, local / 0.07) / RATE
				v = sin(phase) * sin(PI * local / 0.07)
		out[i] = v
	return out


## A short tone sliding from one pitch to another (UI ticks).
static func _blip(from_hz: float, to_hz: float, seconds: float) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var f := i / float(n)
		phase += TAU * lerpf(from_hz, to_hz, f) / RATE
		out[i] = sin(phase) * sin(PI * f)
	return out


## A loop of soft, slowly breathing wind. The end is blended into the start so
## the loop has no seam.
static func _wind(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(WIND_SECONDS * WIND_RATE)
	var blend := int(0.4 * WIND_RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + blend)
	var fast := 0.0
	var slow := 0.0
	var smooth := 0.0
	for i in n + blend:
		var white := rng.randf_range(-1.0, 1.0)
		fast += (white - fast) * 0.4
		slow += (white - slow) * 0.1
		# What lies between the two: a soft "hhh" — no rumble (which a phone
		# cannot play) and no hiss.
		smooth += ((fast - slow) - smooth) * 0.4
		raw[i] = smooth
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := raw[i]
		if i < blend:
			var f := i / float(blend)
			v = raw[i] * f + raw[n + i] * (1.0 - f)
		# Breathing that repeats exactly once (and twice) per loop.
		var t := i / float(n)
		out[i] = v * (0.72 + 0.2 * sin(TAU * t) + 0.08 * sin(TAU * 2.0 * t + 1.3))
	var top := peak(out)
	if top > 0.0:
		for i in n:
			out[i] *= 0.5 / top
	return out


## Scales to `level` and fades the first and last milliseconds so nothing clicks.
static func _finish(samples: PackedFloat32Array, level: float) -> PackedFloat32Array:
	var top := peak(samples)
	if top <= 0.0:
		return samples
	var n := samples.size()
	var fade_in := mini(int(0.0003 * RATE), n / 2) # short: a click keeps its attack
	var fade_out := mini(int(0.012 * RATE), n / 2)
	for i in n:
		var gain := level / top
		if i < fade_in:
			gain *= i / float(fade_in)
		if i >= n - fade_out:
			gain *= (n - 1 - i) / float(fade_out)
		samples[i] *= gain
	return samples
