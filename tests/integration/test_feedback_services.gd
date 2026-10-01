extends TestCase
## The Haptics and AudioManager services, and how touches map onto them.

var pulses: Array = [] # [duration_ms, amplitude]
var _real_vibrate: Callable


func before_all() -> void:
	AudioManager.ensure_sounds()


func before_each() -> void:
	Settings.reset_to_defaults()
	_real_vibrate = Haptics.vibrate_action
	pulses.clear()
	Haptics.vibrate_action = func(ms: int, amplitude: float) -> void: pulses.append([ms, amplitude])
	Haptics.reset()
	AudioManager.stop_all()
	AudioManager.sounds_played = 0
	AudioManager.sounds_dropped = 0
	AudioManager.last_sound = &""


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	AudioManager.stop_all()
	AudioManager.stop_ambience()
	Settings.reset_to_defaults()


func _bus_db(bus: StringName) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(bus))


func _bus_muted(bus: StringName) -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index(bus))


# --- haptics ----------------------------------------------------------------------------

func test_three_strengths_use_the_configured_pulses() -> void:
	var cfg := Config.feedback
	assert_true(Haptics.pulse(Haptics.Strength.LIGHT, 1000))
	assert_true(Haptics.pulse(Haptics.Strength.MEDIUM, 2000))
	assert_true(Haptics.pulse(Haptics.Strength.STRONG, 3000))
	assert_eq(pulses, [
		[cfg.haptic_light_ms, cfg.haptic_light_amplitude],
		[cfg.haptic_medium_ms, cfg.haptic_medium_amplitude],
		[cfg.haptic_strong_ms, cfg.haptic_strong_amplitude],
	])
	assert_true(cfg.haptic_light_ms < cfg.haptic_medium_ms and cfg.haptic_medium_ms < cfg.haptic_strong_ms)
	assert_eq(Haptics.pulses_played, 3)


func test_named_shortcuts() -> void:
	Haptics.light()
	assert_eq(pulses.size(), 1)
	assert_eq(pulses[0][0], Config.feedback.haptic_light_ms)
	Haptics.reset()
	Haptics.medium()
	assert_eq(pulses[1][0], Config.feedback.haptic_medium_ms)
	Haptics.reset()
	Haptics.strong()
	assert_eq(pulses[2][0], Config.feedback.haptic_strong_ms)


func test_rapid_pulses_are_rate_limited() -> void:
	var gap := Config.feedback.haptic_min_gap_ms
	assert_true(Haptics.pulse(Haptics.Strength.LIGHT, 1000))
	assert_false(Haptics.pulse(Haptics.Strength.LIGHT, 1000 + gap - 1), "too soon")
	assert_eq(Haptics.pulses_skipped, 1)
	assert_true(Haptics.pulse(Haptics.Strength.LIGHT, 1000 + gap), "after the gap")
	assert_eq(pulses.size(), 2)
	# Twenty taps in a quarter of a second never become a buzz.
	Haptics.reset()
	pulses.clear()
	for i in 20:
		Haptics.pulse(Haptics.Strength.LIGHT, 5000 + i * 12)
	assert_true(pulses.size() <= 240 / gap + 1, "%d pulses" % pulses.size())


func test_a_stronger_pulse_is_never_swallowed() -> void:
	assert_true(Haptics.pulse(Haptics.Strength.LIGHT, 1000))
	assert_true(Haptics.pulse(Haptics.Strength.STRONG, 1005), "a jolt right after a tick still happens")
	assert_false(Haptics.pulse(Haptics.Strength.MEDIUM, 1010), "but not a weaker one after it")
	assert_eq(pulses.size(), 2)


func test_haptics_follow_the_player_setting() -> void:
	Settings.set_value(&"haptics/enabled", false)
	assert_false(Haptics.enabled)
	assert_false(Haptics.strong())
	assert_eq(pulses.size(), 0)
	assert_eq(Haptics.pulses_skipped, 0, "off is not 'dropped'")
	Settings.set_value(&"haptics/enabled", true)
	assert_true(Haptics.light())
	assert_eq(pulses.size(), 1)


# --- audio: buses and volumes ---------------------------------------------------------------

func test_buses_exist_and_feed_the_master() -> void:
	for bus: StringName in [AudioManager.BUS_AMBIENCE, AudioManager.BUS_SFX, AudioManager.BUS_UI]:
		var index := AudioServer.get_bus_index(bus)
		assert_true(index > 0, "%s exists" % bus)
		assert_eq(AudioServer.get_bus_send(index), AudioManager.BUS_MASTER)
	assert_eq(AudioManager.world_voice(0).bus, AudioManager.BUS_SFX)
	assert_eq(AudioManager.ui_voice(0).bus, AudioManager.BUS_UI)
	assert_eq(AudioManager.ambience_player().bus, AudioManager.BUS_AMBIENCE)


func test_volume_settings_drive_the_buses() -> void:
	assert_near(_bus_db(AudioManager.BUS_SFX), 0.0, 0.01)
	Settings.set_value(&"audio/sfx", 0.5)
	assert_near(_bus_db(AudioManager.BUS_SFX), -6.02, 0.05, "half volume")
	assert_near(_bus_db(AudioManager.BUS_UI), 0.0, 0.01, "other buses untouched")
	Settings.set_value(&"audio/ambience", 0.0)
	assert_true(_bus_muted(AudioManager.BUS_AMBIENCE), "zero is silent")
	Settings.set_value(&"audio/ambience", 0.25)
	assert_false(_bus_muted(AudioManager.BUS_AMBIENCE))
	Settings.set_value(&"audio/master", 0.1)
	assert_near(_bus_db(AudioManager.BUS_MASTER), -20.0, 0.05)


func test_mute_setting_silences_everything_and_comes_back() -> void:
	Settings.set_value(&"audio/muted", true)
	assert_true(_bus_muted(AudioManager.BUS_MASTER))
	Settings.set_value(&"audio/muted", false)
	assert_false(_bus_muted(AudioManager.BUS_MASTER))
	assert_near(AudioManager.slider_to_db(1.0), 0.0, 0.001)
	assert_true(AudioManager.slider_to_db(0.0) < -60.0)


# --- audio: sounds and voices -----------------------------------------------------------------

func test_placeholder_sounds_are_ready() -> void:
	assert_true(AudioManager.is_ready())
	for id in SoundSynth.IDS:
		assert_true(AudioManager.has_sound(id), String(id))
	assert_eq(AudioManager.world_voice_count(), Config.feedback.world_voices)
	assert_eq(AudioManager.ui_voice_count(), Config.feedback.ui_voices)


func test_world_sound_plays_where_it_happened() -> void:
	assert_true(AudioManager.play_at(&"thud", Vector3(3, 1, -4), -5.0, 1.0, false))
	var voice := AudioManager.world_voice(0)
	assert_eq(voice.position, Vector3(3, 1, -4))
	assert_true(voice.stream == AudioManager.sound(&"thud"))
	assert_near(voice.volume_db, -5.0, 0.001)
	assert_near(voice.pitch_scale, 1.0, 0.001)
	assert_eq(AudioManager.last_sound, &"thud")
	assert_eq(AudioManager.sounds_played, 1)
	assert_eq(AudioManager.active_voices(), 1)
	# Quieter the further the camera is; never louder than recorded.
	assert_eq(voice.attenuation_model, AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE)
	assert_near(voice.unit_size, Config.feedback.full_volume_distance, 0.001)
	assert_near(voice.max_db, 0.0, 0.001)


func test_each_sound_gets_its_own_voice_until_the_pool_is_full() -> void:
	var voices := AudioManager.world_voice_count()
	for i in voices:
		AudioManager.play_at(&"hum", Vector3(i, 0, 0)) # long enough to overlap
		await wait_real_ms(3) # so "playing longest" has an order
	assert_eq(AudioManager.active_voices(), voices)
	for i in voices:
		assert_near(AudioManager.world_voice(i).position.x, float(i), 0.001)
	# One more: the voice that has been playing longest is reused.
	AudioManager.play_at(&"hum", Vector3(99, 0, 0))
	assert_near(AudioManager.world_voice(0).position.x, 99.0, 0.001)
	assert_near(AudioManager.world_voice(1).position.x, 1.0, 0.001)
	assert_eq(AudioManager.active_voices(), voices, "never more than the pool")


func test_a_finished_voice_is_reused_first() -> void:
	AudioManager.play_at(&"ui_tap", Vector3(1, 0, 0)) # 35 ms
	AudioManager.play_at(&"hum", Vector3(2, 0, 0))
	await wait_real_ms(120)
	assert_eq(AudioManager.active_voices(), 1, "the tick is over, the hum is not")
	AudioManager.play_at(&"thud", Vector3(3, 0, 0))
	assert_near(AudioManager.world_voice(0).position.x, 3.0, 0.001, "took the finished voice")
	assert_near(AudioManager.world_voice(1).position.x, 2.0, 0.001)


func test_pitch_varies_a_little_per_play() -> void:
	var spread := Config.feedback.pitch_variation
	var seen := {}
	for i in 12:
		AudioManager.stop_all()
		AudioManager.play_at(&"click", Vector3.ZERO)
		var pitch := AudioManager.world_voice(0).pitch_scale
		assert_true(pitch >= 1.0 - spread - 0.0001 and pitch <= 1.0 + spread + 0.0001, "pitch %.3f" % pitch)
		seen[snappedf(pitch, 0.0001)] = true
	assert_true(seen.size() > 3, "not the same every time")
	AudioManager.stop_all()
	AudioManager.play_at(&"click", Vector3.ZERO, 0.0, 1.3)
	assert_near(AudioManager.world_voice(0).pitch_scale, 1.3, 1.3 * spread + 0.0001, "around the asked pitch")


func test_ui_sounds_use_their_own_voices() -> void:
	assert_true(AudioManager.play_ui(&"ui_tap"))
	var voice := AudioManager.ui_voice(0)
	assert_true(voice.stream == AudioManager.sound(&"ui_tap"))
	assert_near(voice.volume_db, Config.feedback.ui_volume_db, 0.001, "UI sounds are quiet")
	for i in AudioManager.ui_voice_count() + 2:
		AudioManager.play_ui(&"ui_open")
	assert_true(AudioManager.active_voices() <= AudioManager.ui_voice_count())


func test_unknown_sound_is_dropped_quietly() -> void:
	assert_false(AudioManager.play_at(&"trumpet", Vector3.ZERO))
	assert_false(AudioManager.play_ui(&"trumpet"))
	assert_eq(AudioManager.sounds_dropped, 2)
	assert_eq(AudioManager.sounds_played, 0)


func test_a_sound_can_be_replaced() -> void:
	var original := AudioManager.sound(&"plip")
	var other := SoundSynth.make(&"click")
	AudioManager.set_sound(&"plip", other)
	AudioManager.play_at(&"plip", Vector3.ZERO)
	assert_true(AudioManager.world_voice(0).stream == other)
	AudioManager.set_sound(&"plip", original)
	assert_false(AudioManager.is_from_file(&"plip"), "placeholders are generated, not files")


func test_ambience_loop() -> void:
	assert_false(AudioManager.is_ambience_wanted())
	AudioManager.start_ambience()
	var player := AudioManager.ambience_player()
	assert_true(AudioManager.is_ambience_wanted())
	assert_true(player.stream == AudioManager.sound(AudioManager.WIND))
	assert_eq((player.stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_near(player.volume_db, Config.feedback.wind_volume_db, 0.001, "wind stays in the background")
	assert_true(player.playing)
	AudioManager.stop_ambience()
	assert_false(player.playing)
	assert_false(AudioManager.is_ambience_wanted())


func test_debug_text() -> void:
	AudioManager.play_at(&"thud", Vector3.ZERO)
	assert_has(AudioManager.debug_text(), "1 played")
	assert_has(AudioManager.debug_text(), "voices")


# --- touches ------------------------------------------------------------------------------

func test_every_tap_effect_has_a_sound_and_a_pulse() -> void:
	var effects := [
		InteractionResponse.DUST, InteractionResponse.RIPPLE, InteractionResponse.TREE_SHAKE,
		InteractionResponse.BUSH_RUSTLE, InteractionResponse.ROCK_WOBBLE, InteractionResponse.BUILDING_KNOCK,
		InteractionResponse.FIRE_FLARE, InteractionResponse.RUIN_HUM,
		InteractionResponse.LOG_KNOCK, InteractionResponse.NUDGE, InteractionResponse.TREE_UPROOT,
	]
	for effect: StringName in effects:
		var sound := TouchFeedback.sound_for(effect)
		assert_true(AudioManager.has_sound(sound), "%s -> '%s'" % [effect, sound])
		var r := InteractionResponse.new()
		r.effect = effect
		r.position = Vector3(5, 2, 5)
		var played := AudioManager.sounds_played
		var felt := pulses.size()
		Haptics.reset()
		TouchFeedback.play(r)
		assert_eq(AudioManager.sounds_played, played + 1, String(effect))
		assert_eq(AudioManager.last_sound, sound)
		assert_eq(pulses.size(), felt + 1, "%s is felt" % effect)
	assert_eq(TouchFeedback.sound_for(&"nothing"), &"")


func test_a_knock_is_felt_more_than_a_tap_on_grass() -> void:
	var r := InteractionResponse.new()
	r.effect = InteractionResponse.DUST
	TouchFeedback.play(r)
	Haptics.reset()
	r.effect = InteractionResponse.BUILDING_KNOCK
	TouchFeedback.play(r)
	assert_true(pulses[1][0] > pulses[0][0])


func test_heavy_things_sound_lower_and_are_felt_more() -> void:
	var spread := Config.feedback.pitch_variation
	var r := InteractionResponse.new()
	r.effect = InteractionResponse.ROCK_WOBBLE
	TouchFeedback.play(r) # an ordinary rock
	var rock_pitch := AudioManager.world_voice(0).pitch_scale
	assert_near(rock_pitch, 1.0, spread + 0.001)
	assert_eq(pulses[0][0], Config.feedback.haptic_light_ms)
	Haptics.reset()
	AudioManager.stop_all()
	r.strength = 0.27 # a boulder
	TouchFeedback.play(r)
	assert_near(AudioManager.world_voice(0).pitch_scale, 0.635, 0.635 * spread + 0.001, "lower")
	assert_eq(pulses[1][0], Config.feedback.haptic_medium_ms, "and felt more")
	Haptics.reset()
	AudioManager.stop_all()
	r.strength = 1.8 # a pebble
	TouchFeedback.play(r)
	assert_true(AudioManager.world_voice(0).pitch_scale > 1.25, "higher")


func test_landings_are_heard_and_felt_by_weight_and_speed() -> void:
	var spread := Config.feedback.pitch_variation
	TouchFeedback.landed(Vector3(2, 1, 3), 1.0, 5.0, false) # a rock from carrying height
	assert_eq(AudioManager.last_sound, &"thud")
	var rock_voice := AudioManager.world_voice(0)
	assert_eq(rock_voice.position, Vector3(2, 1, 3))
	var rock_volume := rock_voice.volume_db
	assert_near(rock_voice.pitch_scale, 1.0, spread + 0.001)
	assert_eq(pulses[0][0], Config.feedback.haptic_light_ms)
	Haptics.reset()
	AudioManager.stop_all()
	TouchFeedback.landed(Vector3.ZERO, 0.27, 5.0, false) # a boulder
	assert_true(AudioManager.world_voice(0).volume_db > rock_volume, "a stronger thud")
	assert_true(AudioManager.world_voice(0).pitch_scale < 0.75, "and a lower one")
	assert_eq(pulses[1][0], Config.feedback.haptic_medium_ms)
	Haptics.reset()
	AudioManager.stop_all()
	TouchFeedback.landed(Vector3.ZERO, 1.0, 1.0, false) # set down gently
	assert_true(AudioManager.world_voice(0).volume_db < rock_volume - 4.0, "a soft landing is quiet")
	AudioManager.stop_all()
	TouchFeedback.landed(Vector3.ZERO, 1.0, 5.0, true)
	assert_eq(AudioManager.last_sound, &"plip", "water")


func test_bumps_click_louder_when_harder() -> void:
	TouchFeedback.bumped(Vector3(1, 2, 3), 1.0, 1.0)
	assert_eq(AudioManager.last_sound, &"click")
	var soft := AudioManager.world_voice(0).volume_db
	assert_eq(AudioManager.world_voice(0).position, Vector3(1, 2, 3))
	AudioManager.stop_all()
	TouchFeedback.bumped(Vector3.ZERO, 1.0, 6.0)
	assert_true(AudioManager.world_voice(0).volume_db > soft + 4.0)
	assert_eq(pulses.size(), 0, "bumps are heard, not felt")


func test_sound_comes_from_the_touched_place() -> void:
	var r := InteractionResponse.new()
	r.effect = InteractionResponse.RIPPLE
	r.position = Vector3(-7, 1.3, 12)
	TouchFeedback.play(r)
	assert_eq(AudioManager.world_voice(0).position, Vector3(-7, 1.3, 12))
	assert_eq(AudioManager.last_sound, &"plip")


func test_long_press_gives_a_ui_tick_not_a_world_sound() -> void:
	var r := InteractionResponse.new()
	r.effect = InteractionResponse.INSPECT
	TouchFeedback.play(r)
	assert_eq(AudioManager.last_sound, &"ui_open")
	assert_true(AudioManager.ui_voice(0).stream == AudioManager.sound(&"ui_open"))
	assert_eq(pulses.size(), 1)
	assert_eq(pulses[0][0], Config.feedback.haptic_light_ms, "a light tick")
	TouchFeedback.play(null)
	assert_eq(AudioManager.sounds_played, 1)


func test_feedback_config_is_valid() -> void:
	assert_eq(FeedbackConfig.new().validate().size(), 0)
	var bad := FeedbackConfig.new()
	bad.haptic_light_ms = 100
	bad.chirp_min_seconds = 250.0
	assert_eq(bad.validate().size(), 2)
