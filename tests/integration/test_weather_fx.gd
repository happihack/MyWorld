extends TestCase
## The weather on screen and in the ears (M9.1): rain and snow in the box,
## the light under clouds, fog, lightning and thunder, wind in the trees,
## wet ground, and the weather line of the HUD.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var fx: WeatherFx
var weather: WeatherSystem
var config: WeatherFxConfig
var _real_vibrate: Callable


func before_each() -> void:
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	Haptics.vibrate_action = func(_ms: int, _amplitude: float) -> void: pass
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.behavior.enabled = false
	session.clock.set_speed(0)
	fx = view.weather_fx()
	fx.set_process(false) # (the test says when time passes for the sky)
	weather = session.weather
	config = Config.weather_fx
	view.day_night().forced_hour = 12.0


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)
	Settings.reset_to_defaults()


## Holds the weather at a kind and shows it at once.
func _sky(kind: StringName) -> void:
	weather.hold(kind, session.clock.tick + 100_000)
	fx.snap()
	view.day_night().refresh()


func _seconds(seconds: float) -> void:
	for i in ceili(seconds * 30.0):
		fx.advance(1.0 / 30.0)
	view.day_night().refresh()


func test_rain_and_snow_fall_in_the_box() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	var rain := fx.rain_node()
	var material := fx.rain_material()
	_sky(&"clear")
	assert_false(rain.visible, "a clear sky: nothing falls, nothing is drawn")
	assert_near(fx.falling, 0.0, 0.001)
	# Rain: a third of the drops; heavy rain most; a storm all of them.
	assert_eq(fx.drop_count(), config.drops_for(GraphicsQuality.current()))
	assert_eq(rain.multimesh.instance_count, fx.drop_count())
	_sky(&"rain")
	assert_true(rain.visible)
	assert_near(fx.falling, 1.0 / config.full_precipitation, 0.001)
	assert_near(material.get_shader_parameter(&"amount"), fx.falling, 0.001)
	assert_near(material.get_shader_parameter(&"snow"), 0.0, 0.001)
	assert_near(material.get_shader_parameter(&"fall_speed"), config.rain_speed, 0.001)
	_sky(&"heavy_rain")
	assert_near(fx.falling, 2.5 / config.full_precipitation, 0.001)
	_sky(&"storm")
	assert_near(fx.falling, 1.0, 0.001)
	# It falls around what the camera looks at, inside the box, from its top to its floor.
	var rig := view.camera_rig()
	assert_near((material.get_shader_parameter(&"area_center") as Vector2).x, rig.pivot().x, 0.01)
	assert_near((material.get_shader_parameter(&"area_center") as Vector2).y, rig.pivot().z, 0.01)
	var side: float = material.get_shader_parameter(&"area_size")
	assert_true(side >= config.area_min and side <= config.area_max)
	assert_eq(material.get_shader_parameter(&"box_min"), Vector2(session.world.bounds.position))
	assert_eq(material.get_shader_parameter(&"box_max"), Vector2(session.world.bounds.end))
	assert_true(float(material.get_shader_parameter(&"top")) > float(material.get_shader_parameter(&"bottom")) + 4.0)
	# Looked at from closer, the square is smaller (as many drops in less room).
	rig.focus_on(rig.pivot(), 12.0, false)
	fx.advance(0.0)
	assert_true(float(material.get_shader_parameter(&"area_size")) <= side)
	# The wind carries it.
	weather.wind_speed = 0.8
	weather.wind_degrees = 90.0
	fx.snap()
	var carried: Vector2 = material.get_shader_parameter(&"wind")
	assert_near(carried.y, 0.8 * config.wind_carry, 0.01)
	assert_near(carried.x, 0.0, 0.01)
	# Snow: flakes, slow, white.
	_sky(&"snow")
	assert_true(fx.snowing and rain.visible)
	assert_near(material.get_shader_parameter(&"snow"), 1.0, 0.001)
	assert_near(material.get_shader_parameter(&"fall_speed"), config.snow_speed, 0.001)
	assert_eq(material.get_shader_parameter(&"tint"), config.snow_color)
	assert_true(fx.falling > 0.5, "a snowfall is a sky full of flakes")
	# Fewer drops on a weaker device.
	Settings.set_value(GraphicsQuality.SETTING, "low")
	assert_eq(fx.drop_count(), config.drops[0])
	Settings.set_value(GraphicsQuality.SETTING, "high")
	assert_eq(fx.drop_count(), config.drops[2])
	assert_true(fx.debug_text().begins_with("sky: "))


func test_the_sky_changes_it_does_not_switch() -> void:
	_sky(&"clear")
	weather.hold(&"storm", session.clock.tick + 100_000)
	fx.advance(1.0 / 30.0)
	assert_true(fx.falling > 0.0 and fx.falling < 0.1, "a thirtieth of a second later: hardly begun (%.3f)" % fx.falling)
	assert_true(fx.cover < 0.2)
	_seconds(config.transition_seconds * 0.5)
	assert_true(fx.falling > 0.3 and fx.falling < 0.7, "%.2f half way" % fx.falling)
	_seconds(config.transition_seconds)
	assert_near(fx.falling, 1.0, 0.001)
	assert_near(fx.cover, 1.0, 0.001)
	# The ground gets wet in the rain, and dries slowly after it.
	_seconds(config.wetting_seconds)
	assert_near(fx.wetness, 1.0, 0.001)
	var terrain := view.terrain_material()
	assert_near(terrain.get_shader_parameter(&"wetness"), config.wet_ground, 0.001)
	weather.hold(&"clear", session.clock.tick + 100_000)
	_seconds(config.transition_seconds + 1.0)
	assert_near(fx.falling, 0.0, 0.001)
	assert_false(fx.rain_node().visible)
	assert_true(fx.wetness > 0.5, "still wet (%.2f)" % fx.wetness)
	_seconds(config.drying_seconds)
	assert_near(fx.wetness, 0.0, 0.001)
	assert_near(terrain.get_shader_parameter(&"wetness"), 0.0, 0.001)
	# Rain does not turn white in mid-air: it stops, and then it snows.
	_sky(&"heavy_rain")
	weather.hold(&"snow", session.clock.tick + 100_000)
	fx.advance(0.2)
	assert_false(fx.snowing)
	assert_true(fx.falling < 2.5 / config.full_precipitation)
	_seconds(config.transition_seconds * 2.0)
	assert_true(fx.snowing)
	assert_true(fx.falling > 0.5)
	assert_true(fx.wetness < 0.9, "snow does not wet the ground: it is drying (%.2f)" % fx.wetness)
	# Faster when the world runs faster.
	_sky(&"clear")
	session.clock.set_speed(GameClock.SPEED_VERY_FAST)
	weather.hold(&"cloudy", session.clock.tick + 100_000)
	_seconds(config.transition_seconds / 8.0)
	assert_near(fx.cover, Config.climate.value_for(Config.climate.cloud_cover, &"cloudy"), 0.001)
	session.clock.set_speed(0)


func test_the_light_under_the_weather() -> void:
	var lighting := view.lighting()
	_sky(&"clear")
	var clear := lighting.sun().light_energy
	var clear_shadows := lighting.sun().shadow_opacity
	assert_false(lighting.environment().fog_enabled)
	# Cloud: dimmer, greyer, paler shadows.
	_sky(&"cloudy")
	var cloudy := lighting.sun().light_energy
	assert_true(cloudy < clear * 0.85 and cloudy > clear * 0.4, "%.2f under cloud, %.2f in the clear" % [cloudy, clear])
	_sky(&"heavy_rain")
	assert_near(lighting.sun().light_energy, clear / lerpf(1.0, config.overcast_light, 0.08) * config.overcast_light, 0.03)
	assert_true(lighting.sun().shadow_opacity < clear_shadows * 0.5)
	assert_near(view.day_night().cover(), 1.0, 0.001)
	# The rule itself: nothing under a clear sky; a flash is brighter than day.
	var plain := DayNight.state_at(12.0, Config.day_night)
	var same := DayNight.under_weather(DayNight.state_at(12.0, Config.day_night), 0.0, 0.0, config)
	assert_eq([same.light_energy, same.ambient_energy, same.shadow_opacity], [plain.light_energy, plain.ambient_energy, plain.shadow_opacity])
	var covered := DayNight.under_weather(DayNight.state_at(12.0, Config.day_night), 1.0, 0.0, config)
	assert_near(covered.light_energy, plain.light_energy * config.overcast_light, 0.001)
	assert_true(covered.ambient_energy < plain.ambient_energy and covered.ambient_energy > plain.ambient_energy * 0.7)
	assert_true(covered.cloud_shadows < plain.cloud_shadows, "a closed sky throws no patches of shade")
	assert_true(DayNight.under_weather(DayNight.state_at(12.0, Config.day_night), 0.5, 0.0, config).cloud_shadows > plain.cloud_shadows,
		"broken cloud throws more")
	var lit := DayNight.under_weather(DayNight.state_at(12.0, Config.day_night), 1.0, 1.0, config)
	assert_true(lit.light_energy > plain.light_energy)
	# At night the weather has little light to take.
	var night := DayNight.under_weather(DayNight.state_at(1.0, Config.day_night), 1.0, 0.0, config)
	assert_true(night.light_energy <= DayNight.state_at(1.0, Config.day_night).light_energy)
	# Fog: it hides the same share of what is looked at from near and from far.
	_sky(&"fog")
	assert_true(lighting.environment().fog_enabled)
	var rig := view.camera_rig()
	assert_near(lighting.fog_haze_at(rig.distance()), config.fog_haze, 0.01)
	rig.focus_on(rig.pivot(), 14.0, false)
	fx.advance(0.0)
	assert_near(lighting.fog_haze_at(14.0), config.fog_haze, 0.01)
	_sky(&"rain")
	assert_true(lighting.fog_haze_at(rig.distance()) < config.fog_haze * 0.3, "rain is a little hazy")
	_sky(&"clear")
	assert_false(lighting.environment().fog_enabled)


func test_lightning_and_thunder() -> void:
	_sky(&"storm")
	assert_true(fx.is_storming())
	var played := AudioManager.sounds_played
	fx.strike()
	assert_eq(fx.flashes, 1)
	fx.advance(0.02)
	assert_near(fx.flash, 1.0, 0.001, "a flash")
	view.day_night().refresh()
	var bright := view.lighting().sun().light_energy
	_seconds(0.6)
	assert_near(fx.flash, 0.0, 0.001, "and it is over")
	assert_true(view.lighting().sun().light_energy < bright)
	# The thunder comes after it.
	_seconds(config.thunder_max_seconds)
	assert_eq(fx.thunders, 1)
	assert_true(AudioManager.sounds_played > played)
	assert_true(SoundSynth.THUNDER_IDS.has(AudioManager.last_sound), "one of the thunders: %s" % AudioManager.last_sound)
	assert_true(AudioManager.has_sound(&"thunder") and AudioManager.has_sound(&"rain"))
	# Each thunder is heard on a phone (owner: none was): most of it above 150 Hz.
	for id in SoundSynth.THUNDER_IDS:
		var samples := SoundSynth.samples_for(id)
		var keep := float(SoundSynth.RATE) / (float(SoundSynth.RATE) + TAU * 150.0)
		var high := 0.0
		var last := 0.0
		var heard := 0.0
		var all := 0.0
		for x in samples:
			high = keep * (high + x - last)
			last = x
			heard += high * high
			all += x * x
		assert_true(heard / all > 0.6, "%s: %.2f of it a phone can play" % [id, heard / all])
	# In a storm they come by themselves, every few seconds.
	_seconds(config.lightning_max_seconds * 2.0 + 1.0)
	assert_true(fx.flashes >= 3, "%d flashes" % fx.flashes)
	# Not when the storm is over.
	_sky(&"rain")
	var before := fx.flashes
	_seconds(config.lightning_max_seconds * 2.0)
	assert_eq(fx.flashes, before)
	# Reduced motion: no flashing light — the thunder is still heard.
	Settings.set_value(&"accessibility/reduced_motion", true)
	assert_true(fx.reduced_motion)
	var thunders := fx.thunders
	fx.strike()
	fx.advance(0.02)
	assert_near(fx.flash, 0.0, 0.001)
	_seconds(config.thunder_max_seconds + 0.1)
	assert_eq(fx.thunders, thunders + 1)


func test_wind_and_sound_and_words() -> void:
	var props := view.prop_material()
	_sky(&"clear")
	weather.wind_speed = 0.0
	fx.snap()
	var calm: float = props.get_shader_parameter(&"sway_amplitude")
	weather.wind_speed = 1.0
	weather.wind_degrees = 0.0
	fx.snap()
	var stormy: float = props.get_shader_parameter(&"sway_amplitude")
	assert_near(stormy / calm, config.sway_storm / config.sway_calm, 0.01, "the trees sway with the wind")
	assert_near((props.get_shader_parameter(&"wind_direction") as Vector2).x, 1.0, 0.001)
	# Holding a kind of weather gives it its wind.
	weather.hold(&"fog", session.clock.tick + 100_000)
	assert_true(weather.wind_speed <= 0.1)
	weather.hold(&"storm", session.clock.tick + 100_000)
	assert_true(weather.wind_speed >= 0.75)
	# The sound of it: rain is heard while it rains, the wind is louder when it blows.
	AudioManager.start_ambience()
	_sky(&"clear")
	weather.wind_speed = 0.0
	fx.snap()
	assert_false(AudioManager.rain_ambience_player().playing)
	var quiet := AudioManager.ambience_player().volume_db
	_sky(&"heavy_rain")
	assert_true(AudioManager.rain_ambience_player().playing)
	var heavy := AudioManager.rain_ambience_player().volume_db
	_sky(&"rain")
	assert_true(AudioManager.rain_ambience_player().volume_db < heavy)
	weather.wind_speed = 1.0
	fx.snap()
	assert_near(quiet, AudioManager.SILENT_DB, 0.01, "still air: no wind heard")
	assert_near(AudioManager.ambience_player().volume_db, Config.feedback.wind_volume_db + config.wind_gain_db, 0.01, "a gale: heard")
	_sky(&"snow")
	assert_false(AudioManager.rain_ambience_player().playing, "snow falls without a sound")
	# The weather line under the clock.
	_sky(&"heavy_rain")
	ui.speed_control().refresh()
	assert_eq(ui.speed_control().weather_text(), "Heavy rain · %s" % UIText.temperature_text(weather.temperature()))
	# The debug overlay says how the sky stands.
	var overlay: DebugOverlay = main.get_node("DebugOverlay")
	if not overlay.is_shown():
		overlay.toggle()
	await wait_frames(2)
	overlay.refresh()
	var text := (overlay.get_node("%OverlayLabel") as Label).text
	assert_true(text.contains("weather: heavy_rain") and text.contains("sky: cover"))
	# The world closed: the rain is not heard on.
	get_tree().unload_current_scene()
	await wait_frames(2)
	assert_false(AudioManager.rain_ambience_player().playing)
