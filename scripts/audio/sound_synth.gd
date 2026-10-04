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
const RAIN_SECONDS := 2.5

## Every sound this class can make.
const IDS: Array[StringName] = [
	&"thud", &"plip", &"rustle", &"click", &"knock", &"crackle", &"hum",
	&"chirp", &"chirp_2", &"chirp_3", &"ui_open", &"ui_tap", &"ui_close", &"wind", &"voice", &"crickets",
	&"rain", &"thunder", &"gust", &"chime",
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
	if id == &"wind" or id == &"crickets" or id == &"rain":
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
			# Three quick upward whistles.
			return _finish(_whistles(0.3, [
				[0.0, 0.07, 2700.0, 3600.0], [0.09, 0.07, 2700.0, 3850.0], [0.18, 0.07, 2700.0, 4100.0]]), 0.5)
		&"chirp_2":
			# A falling call and a short answer note.
			return _finish(_whistles(0.26, [[0.0, 0.11, 3900.0, 2900.0], [0.16, 0.06, 3150.0, 3350.0]]), 0.5)
		&"chirp_3":
			# A quick trill.
			return _finish(_whistles(0.24, [
				[0.0, 0.03, 3300.0, 3500.0], [0.045, 0.03, 3900.0, 4000.0], [0.09, 0.03, 3300.0, 3500.0],
				[0.135, 0.03, 3900.0, 4000.0], [0.18, 0.04, 3300.0, 3100.0]]), 0.45)
		&"ui_open":
			return _finish(_blip(620.0, 930.0, 0.07), 0.45)
		&"ui_tap":
			return _finish(_blip(1050.0, 1050.0, 0.035), 0.4)
		&"ui_close":
			return _finish(_blip(880.0, 590.0, 0.07), 0.4)
		&"wind":
			return _wind(rng)
		&"crickets":
			return _crickets(rng)
		&"rain":
			return _rain(rng)
		&"gust":
			return _finish(_gust(rng), 0.6)
		&"thunder":
			return _finish(_thunder(rng), 0.9)
		&"chime":
			return _finish(_chime(), 0.5)
		&"voice":
			# A small "oh!": up, and down again. (Pitched per person when played.)
			return _finish(_whistles(0.24, [[0.0, 0.09, 430.0, 600.0], [0.11, 0.12, 600.0, 390.0]]), 0.55)
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


## Something known again (VS.5): two soft bell notes, a fifth apart, the
## second answering the first.
static func _chime() -> PackedFloat32Array:
	var n := int(1.1 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for note: Array in [[0.0, 784.0], [0.16, 1175.0]]:
		var start := int(float(note[0]) * RATE)
		var hz: float = note[1]
		for i in range(start, n):
			var t := (i - start) / float(RATE)
			var bell := sin(TAU * hz * t) + 0.35 * sin(TAU * hz * 2.76 * t) * exp(-t * 6.0) + 0.2 * sin(TAU * hz * 5.4 * t) * exp(-t * 12.0)
			out[i] += bell * minf(t / 0.004, 1.0) * exp(-t * 4.2)
	return out


## A small bird: a few short whistles. Each note is
## [start seconds, length seconds, from Hz, to Hz]; notes must not overlap.
static func _whistles(seconds: float, notes: Array) -> PackedFloat32Array:
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := i / float(RATE)
		var v := 0.0
		for note: Array in notes:
			var local: float = t - note[0]
			var length: float = note[1]
			if local >= 0.0 and local < length:
				phase += TAU * lerpf(note[2], note[3], local / length) / RATE
				v = sin(phase) * sin(PI * local / length)
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


## A loop of crickets in the night: three of them, each chirping in short
## trills at its own pitch and pace. Every trill fits inside the loop, so it
## has no seam.
static func _crickets(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var seconds := 4.0
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for cricket in 3:
		var pitch := 3900.0 + cricket * 420.0 + rng.randf_range(-60.0, 60.0)
		var period := 0.62 + cricket * 0.21
		var loudness := 0.5 - cricket * 0.12
		var start := rng.randf_range(0.05, 0.3)
		while start + 0.2 < seconds:
			# A trill: three or four quick pulses.
			for pulse in 3 + (cricket % 2):
				var from := int((start + pulse * 0.045) * RATE)
				var length := int(0.028 * RATE)
				for i in length:
					if from + i >= n:
						break
					var f := float(i) / float(length)
					out[from + i] += sin(TAU * pitch * float(i) / RATE) * sin(PI * f) * loudness
			start += period + rng.randf_range(-0.04, 0.04)
	return _finish(out, 0.4)


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


## A loop of steady rain: a soft hiss with drops in it. The end is blended
## into the start so the loop has no seam.
static func _rain(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RAIN_SECONDS * RATE)
	var blend := int(0.25 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n + blend)
	var low := 0.0
	var band := 0.0
	var drop := 0.0
	for i in n + blend:
		var white := rng.randf_range(-1.0, 1.0)
		# The hiss: what is left of noise without its lowest and its sharpest.
		low += (white - low) * 0.25
		band += ((white - low) - band) * 0.55
		# Drops: now and then a tick that dies away at once.
		if rng.randf() < 0.012:
			drop = rng.randf_range(0.4, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		drop *= 0.86
		raw[i] = band * 0.6 + drop * 0.5
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var v := raw[i]
		if i < blend:
			var f := i / float(blend)
			v = raw[i] * f + raw[n + i] * (1.0 - f)
		out[i] = v
	var top := peak(out)
	if top > 0.0:
		for i in n:
			out[i] *= 0.5 / top
	return out


## Thunder: a crack, and a rumble that rolls away.
static func _thunder(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(2.8 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var lower := 0.0
	for i in n:
		var t := i / float(RATE)
		var white := rng.randf_range(-1.0, 1.0)
		low += (white - low) * 0.06
		lower += (low - lower) * 0.12
		# The crack at the start (brighter), then the rumble, swelling twice as it rolls.
		var crack := exp(-t * 14.0)
		var roll := exp(-t * 1.3) * (0.6 + 0.4 * sin(t * 9.0 + 0.7) * sin(t * 2.3))
		out[i] = low * 3.0 * crack + lower * 9.0 * roll
	return out


## A gust of wind: a soft rush that swells and dies away.
static func _gust(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(1.1 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var fast := 0.0
	var slow := 0.0
	for i in n:
		var t := i / float(n)
		var white := rng.randf_range(-1.0, 1.0)
		# (The band between two smoothings — brighter in the middle of the gust.)
		fast += (white - fast) * lerpf(0.18, 0.45, sin(PI * t))
		slow += (white - slow) * 0.05
		out[i] = (fast - slow) * pow(sin(PI * t), 1.5)
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
