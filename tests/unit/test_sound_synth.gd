extends TestCase
## SoundSynth: the generated placeholder sounds.


## Sign changes per second: a rough measure of how bright a sound is.
func _crossings_per_second(samples: PackedFloat32Array, rate: int, from: int = 0, to: int = -1) -> float:
	var end := samples.size() if to < 0 else to
	var count := 0
	for i in range(from + 1, end):
		if (samples[i] >= 0.0) != (samples[i - 1] >= 0.0):
			count += 1
	return count / (float(end - from) / rate)


func test_every_sound_is_made_and_sane() -> void:
	for id in SoundSynth.IDS:
		var samples := SoundSynth.samples_for(id)
		assert_true(samples.size() > 200, "%s has samples" % id)
		var top := SoundSynth.peak(samples)
		assert_true(top > 0.2 and top <= 1.0, "%s peak %.2f" % [id, top])
		var finite := true
		for v in samples:
			if not is_finite(v):
				finite = false
				break
		assert_true(finite, "%s has only finite samples" % id)
		if id != &"wind" and id != &"crickets": # (those two are loops)
			assert_true(SoundSynth.seconds_of(samples) <= 1.6, "%s is short" % id)
			assert_near(samples[0], 0.0, 0.02, "%s starts silent (no click)" % id)
			assert_near(samples[samples.size() - 1], 0.0, 0.02, "%s ends silent (no click)" % id)


func test_sounds_are_deterministic() -> void:
	for id: StringName in [&"thud", &"rustle", &"crackle", &"wind"]:
		assert_true(SoundSynth.samples_for(id) == SoundSynth.samples_for(id), "%s is the same every time" % id)
	assert_false(SoundSynth.samples_for(&"thud") == SoundSynth.samples_for(&"knock"))


func test_unknown_sound() -> void:
	assert_eq(SoundSynth.samples_for(&"trumpet").size(), 0)
	assert_null(SoundSynth.make(&"trumpet"))


func test_stream_format() -> void:
	var samples := SoundSynth.samples_for(&"plip")
	var stream := SoundSynth.make(&"plip")
	assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(stream.mix_rate, SoundSynth.RATE)
	assert_false(stream.stereo)
	assert_eq(stream.data.size(), samples.size() * 2)
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED)
	assert_near(stream.get_length(), SoundSynth.seconds_of(samples), 0.001)
	# Samples survive the conversion (within 16-bit precision) and are clamped.
	assert_near(stream.data.decode_s16(200 * 2) / 32767.0, samples[200], 0.0001)
	var loud := SoundSynth.to_stream(PackedFloat32Array([2.0, -2.0]), 8000)
	assert_eq(loud.data.decode_s16(0), 32767)
	assert_eq(loud.data.decode_s16(2), -32767)


func test_sounds_have_the_right_character() -> void:
	var rate := SoundSynth.RATE
	var thud := _crossings_per_second(SoundSynth.samples_for(&"thud"), rate)
	var click := _crossings_per_second(SoundSynth.samples_for(&"click"), rate)
	var rustle := _crossings_per_second(SoundSynth.samples_for(&"rustle"), rate)
	var hum := _crossings_per_second(SoundSynth.samples_for(&"hum"), rate)
	assert_true(thud < 1500.0, "a thud is low (%.0f)" % thud)
	assert_true(hum < 1200.0, "a hum is low (%.0f)" % hum)
	assert_true(hum > 300.0, "but not below what a phone speaker can play (%.0f)" % hum)
	assert_true(click > 3000.0, "a click is bright (%.0f)" % click)
	assert_true(rustle > 5000.0, "leaves hiss (%.0f)" % rustle)
	# A drop of water slides upward in pitch.
	var plip := SoundSynth.samples_for(&"plip")
	var early := _crossings_per_second(plip, rate, 0, plip.size() / 5)
	var late := _crossings_per_second(plip, rate, plip.size() / 2, plip.size())
	assert_true(late > early * 1.3, "plip rises (%.0f -> %.0f)" % [early, late])
	# Two knocks: loud, quiet in between, loud again.
	var knock := SoundSynth.samples_for(&"knock")
	var gap := SoundSynth.peak(knock.slice(int(0.08 * rate), int(0.11 * rate)))
	var second := SoundSynth.peak(knock.slice(int(0.115 * rate), int(0.14 * rate)))
	assert_true(second > gap * 3.0, "the second knock stands out (%.2f vs %.2f)" % [second, gap])


func test_wind_loops_without_a_seam() -> void:
	var samples := SoundSynth.samples_for(&"wind")
	assert_near(SoundSynth.seconds_of(samples, SoundSynth.WIND_RATE), SoundSynth.WIND_SECONDS, 0.01)
	var stream := SoundSynth.make(&"wind")
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(stream.loop_end, samples.size())
	assert_eq(stream.mix_rate, SoundSynth.WIND_RATE)
	# The jump from the last sample back to the first is no bigger than the
	# steps between neighbouring samples elsewhere.
	var biggest_step := 0.0
	for i in range(1, samples.size()):
		biggest_step = maxf(biggest_step, absf(samples[i] - samples[i - 1]))
	var seam := absf(samples[0] - samples[samples.size() - 1])
	assert_true(seam <= biggest_step, "seam %.4f vs largest step %.4f" % [seam, biggest_step])
	var brightness := _crossings_per_second(samples, SoundSynth.WIND_RATE)
	assert_true(brightness > 500.0 and brightness < 2600.0, "a mid-range whoosh: no rumble, no hiss (%.0f)" % brightness)
	assert_true(SoundSynth.peak(samples) <= 0.51)


func test_make_all() -> void:
	var all := SoundSynth.make_all()
	assert_eq(all.size(), SoundSynth.IDS.size())
	for id in SoundSynth.IDS:
		assert_true(all[id] is AudioStreamWAV, String(id))
