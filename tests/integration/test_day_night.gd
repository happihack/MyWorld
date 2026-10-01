extends TestCase
## Day and night (M6.2): what the light is at each hour, and that the world
## on screen follows the clock — sun, moon, air, windows, fire, and sounds.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const ViewScript := preload("res://scripts/rendering/world_view.gd")

var config: DayNightConfig
var session: WorldSession
var view: WorldView
var cycle: DayNight


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	config = Config.day_night
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	view = ViewScript.new()
	add_child(view)
	view.show_world(session.world, session.props, session.start, session.loose)
	view.show_people(session.people, session.clock, session.occupations)
	cycle = view.day_night()


func after_each() -> void:
	AudioManager.stop_ambience()
	view.queue_free()
	session.queue_free()
	await wait_frames(1)


func _at(hour: float) -> DayNight.State:
	return DayNight.state_at(hour, config)


func _set_hour(hour: float) -> void:
	session.clock.tick = posmod(roundi((hour - Config.time.start_hour) * 60.0), 1440)
	cycle.refresh()


# --- the light at an hour -------------------------------------------------------------------------

func test_the_config_is_sound() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	assert_true(ResourceLoader.exists("res://data/configuration/day_night.tres"))
	var broken := DayNightConfig.new()
	broken.sunrise_hour = 12.0
	broken.sunset_hour = 12.0
	assert_true(broken.validate().size() >= 1)
	# Gradients given in the resource are used instead of the built-in ones.
	var own := Gradient.new()
	own.colors = PackedColorArray([Color.RED, Color.RED])
	var custom := DayNightConfig.new()
	custom.ambient_color = own
	assert_eq(DayNight.state_at(12.0, custom).ambient_color, Color.RED)
	assert_ne(DayNight.state_at(12.0, DayNightConfig.new()).ambient_color, Color.RED)


func test_night_and_day_turn_into_each_other() -> void:
	assert_eq(DayNight.night_at(12.0, config), 0.0, "noon is day")
	assert_eq(DayNight.night_at(1.0, config), 1.0, "one in the morning is night")
	assert_eq(DayNight.night_at(25.0, config), 1.0, "hours wrap")
	assert_near(DayNight.night_at(config.sunrise_hour, config), 0.5, 0.001, "half and half as the sun comes up")
	assert_near(DayNight.night_at(config.sunset_hour, config), 0.5, 0.001)
	# Smoothly: never a jump from one quarter of an hour to the next.
	var last := DayNight.night_at(0.0, config)
	var hour := 0.0
	while hour <= 24.0:
		var night := DayNight.night_at(hour, config)
		assert_true(night >= 0.0 and night <= 1.0)
		assert_true(absf(night - last) < 0.3, "at %.2f" % hour)
		last = night
		hour += 0.25
	# It is dark when people sleep and light when they are up.
	assert_true(DayNight.night_at(SleepStep.NIGHT_FROM + 1.0, config) > 0.9, "night has fallen an hour after bedtime")
	assert_true(DayNight.night_at(8.0, config) < 0.05, "broad day at eight")
	assert_true(DayNight.night_at(18.0, config) < 0.05, "and at six in the evening")


func test_the_sun_climbs_and_sets_and_the_moon_takes_over() -> void:
	var noon := _at((config.sunrise_hour + config.sunset_hour) * 0.5)
	var morning := _at(config.sunrise_hour + 1.0)
	var evening := _at(config.sunset_hour - 1.0)
	assert_false(noon.is_moon)
	assert_near(-noon.light_rotation.x, config.noon_elevation_degrees, 0.01, "highest at noon")
	assert_true(-morning.light_rotation.x < -noon.light_rotation.x and -evening.light_rotation.x < -noon.light_rotation.x)
	assert_true(-morning.light_rotation.x >= config.lowest_elevation_degrees, "never grazing: shadows stay within reason")
	assert_true(morning.light_rotation.y > noon.light_rotation.y and noon.light_rotation.y > evening.light_rotation.y, "it crosses the sky")
	assert_near(noon.light_energy, config.sun_energy, 0.001)
	assert_true(morning.light_energy < noon.light_energy and morning.light_energy > config.sun_energy * 0.5, "strong soon after it is up")
	# Warm at both ends of the day, near white at noon.
	assert_true(morning.light_color.b < noon.light_color.b - 0.15 and evening.light_color.b < noon.light_color.b - 0.15)
	assert_true(noon.light_color.r > 0.95 and noon.light_color.b > 0.8)
	# At the horizon the light is nothing — so sun and moon can change places unseen.
	assert_near(_at(config.sunrise_hour).light_energy, 0.0, 0.001)
	assert_near(_at(config.sunset_hour).light_energy, 0.0, 0.001)
	assert_near(_at(config.sunset_hour + 0.01).light_energy, 0.0, 0.01)
	# The night: the moon, paler and cooler, with softer shadows.
	var midnight := _at(1.0)
	assert_true(midnight.is_moon)
	assert_true(midnight.light_energy > 0.2 and midnight.light_energy < noon.light_energy * 0.4, "enough to see by, far less than the sun")
	assert_true(midnight.light_color.b > midnight.light_color.r, "cool")
	assert_true(midnight.shadow_opacity < noon.shadow_opacity)
	assert_true(-midnight.light_rotation.x >= config.lowest_elevation_degrees)
	# The whole day round: the light never goes out for more than the twilight, and is always sane.
	var hour := 0.0
	var dark_quarters := 0
	while hour < 24.0:
		var s := _at(hour)
		assert_true(s.light_energy >= 0.0 and s.light_energy <= config.sun_energy + 0.001)
		assert_true(s.ambient_energy > 0.3, "never pitch black (%.2f)" % hour)
		assert_true(-s.light_rotation.x >= config.lowest_elevation_degrees - 0.01 and -s.light_rotation.x <= 89.0)
		if s.light_energy < 0.05:
			dark_quarters += 1
		hour += 0.25
	assert_true(dark_quarters <= 8, "the sky is without a light for two hours a day at most (%d quarters)" % dark_quarters)


func test_the_air_and_the_backdrop_follow_the_hour() -> void:
	var noon := _at(13.0)
	var night := _at(1.0)
	var dawn := _at(config.sunrise_hour)
	var dusk := _at(config.sunset_hour)
	assert_true(night.ambient_color.b > night.ambient_color.r + 0.25, "the night is blue")
	assert_true(dawn.ambient_color.r > noon.ambient_color.r and dusk.ambient_color.r > noon.ambient_color.r, "dawn and dusk are warm")
	assert_near(noon.ambient_energy, config.ambient_energy_day, 0.001)
	assert_near(night.ambient_energy, config.ambient_energy_night, 0.001)
	assert_true(night.background.get_luminance() < noon.background.get_luminance() * 0.6, "the room goes dark")
	assert_eq(noon.table_light, 1.0)
	assert_near(night.table_light, config.table_night_light, 0.001)
	assert_near(night.cloud_shadows, config.cloud_shadows_at_night, 0.001)
	assert_eq(noon.cloud_shadows, 1.0)
	# The night is darker than the day, taken all in all — and still to be seen by.
	var day_light := noon.light_energy + noon.ambient_energy
	var night_light := night.light_energy + night.ambient_energy
	assert_true(night_light < day_light * 0.6)
	assert_true(night_light > day_light * 0.3, "people and huts can still be made out")


func test_windows_and_fire_belong_to_the_dark() -> void:
	assert_eq(_at(12.0).window_light, 0.0, "no lights by day")
	assert_true(_at(config.sunset_hour + 1.0).window_light > 0.9, "lit in the evening")
	assert_near(_at(config.lights_out_hour + 1.0).window_light, config.late_window_light, 0.01, "low once the village is in bed")
	assert_near(_at(3.0).window_light, config.late_window_light, 0.01)
	assert_true(_at(config.sunrise_hour + 1.5).window_light < 0.05, "out by morning")
	assert_true(_at(config.sunset_hour - 2.0).window_light < 0.01)
	assert_near(_at(12.0).fire_energy, config.fire_energy_day, 0.001)
	assert_near(_at(1.0).fire_energy, config.fire_energy_night, 0.001)
	assert_true(config.fire_energy_night > config.fire_energy_day * 3.0, "the fire is the light of the night")


# --- the world on screen --------------------------------------------------------------------------

func test_the_light_follows_the_clock() -> void:
	var lighting := view.lighting()
	_set_hour(12.5)
	var noon := DayNight.state_at(session.clock.hour(), config)
	assert_near(lighting.sun().light_energy, noon.light_energy, 0.001)
	assert_eq(lighting.sun().light_color, noon.light_color)
	assert_near(lighting.sun().rotation_degrees.x, noon.light_rotation.x, 0.01)
	assert_eq(lighting.environment().ambient_light_color, noon.ambient_color)
	assert_eq(lighting.environment().background_color, noon.background)
	assert_eq(lighting.table_material().get_shader_parameter(&"daylight"), 1.0)
	assert_eq(cycle.night(), 0.0)
	var prop_material := lighting.get_parent().get("_prop_material") as ShaderMaterial
	assert_eq(prop_material.get_shader_parameter(&"night_glow"), 0.0)
	assert_near(float(prop_material.get_shader_parameter(&"cloud_strength")), Config.terrain_palette.cloud_shadow_strength, 0.001)
	# Night falls.
	_set_hour(1.0)
	var night := cycle.state()
	assert_true(night.is_moon)
	assert_eq(cycle.night(), 1.0)
	assert_near(lighting.sun().light_energy, config.moon_energy, 0.01)
	assert_eq(lighting.sun().light_color, config.moon_color)
	assert_near(lighting.sun().shadow_opacity, config.moon_shadow_opacity, 0.001)
	assert_true(lighting.environment().ambient_light_color.b > lighting.environment().ambient_light_color.r)
	assert_near(float(lighting.table_material().get_shader_parameter(&"daylight")), config.table_night_light, 0.001)
	assert_eq(lighting.table_material().get_shader_parameter(&"background_color"), night.background)
	assert_near(float(prop_material.get_shader_parameter(&"night_glow")), config.late_window_light, 0.01)
	assert_true(float(prop_material.get_shader_parameter(&"flame_glow")) > 2.0, "flames shine in the dark")
	assert_near(float(prop_material.get_shader_parameter(&"cloud_strength")),
		Config.terrain_palette.cloud_shadow_strength * config.cloud_shadows_at_night, 0.001)
	assert_near(float(view.people_view().body_material().get_shader_parameter(&"cloud_strength")),
		Config.terrain_palette.cloud_shadow_strength * config.cloud_shadows_at_night, 0.001, "people stand under the same sky")
	# It moves with the clock by itself, a little at a time.
	_set_hour(20.0)
	var before := lighting.sun().light_energy
	session.clock.tick += 20
	await wait_frames(2)
	assert_ne(lighting.sun().light_energy, before, "twenty minutes on, the light has changed")
	# Without a clock (or held by a test) it is what it is told.
	cycle.forced_hour = 12.0
	cycle.refresh()
	assert_eq(cycle.night(), 0.0)
	cycle.forced_hour = -1.0
	cycle.bind(null)
	assert_eq(cycle.hour(), 12.0, "no clock: a fixed noon")


func test_the_campfire_lights_the_night() -> void:
	var fire := cycle.fire_light()
	var campfire := session.props.get_prop(session.start.campfire_id)
	assert_true(fire.visible, "there is a fire")
	assert_true(Vector2(fire.position.x, fire.position.z).distance_to(campfire.position2d()) < 0.01, "over the campfire")
	assert_true(fire.position.y > session.world.get_height(campfire.tile) * session.world.height_step)
	assert_false(fire.shadow_enabled, "cheap: no shadows of its own")
	_set_hour(12.0)
	await wait_frames(2)
	var by_day := fire.light_energy
	_set_hour(0.5)
	var energies := PackedFloat32Array()
	for i in 12:
		await wait_frames(1)
		energies.append(fire.light_energy)
	var least := 100.0
	var most := 0.0
	for energy in energies:
		least = minf(least, energy)
		most = maxf(most, energy)
	assert_true(least > by_day * 3.0, "far brighter by night (%.2f against %.2f)" % [least, by_day])
	assert_true(most > least, "and never steady: it flickers")
	assert_true(most <= config.fire_energy_night * (1.0 + config.fire_flicker) + 0.001)
	assert_near(fire.omni_range, config.fire_range, 0.001)
	# A world without a fire has no fire light.
	cycle.set_fire(Vector3.ZERO, false)
	assert_false(fire.visible)


func test_huts_have_openings_that_glow_and_the_fire_a_flame() -> void:
	var library := PropMeshLibrary.new()
	var hut := library.template_for(PropData.Kind.HUT, 0)
	var glowing := 0
	for i in hut.vertices.size():
		assert_true(hut.glow_of(i) == 0.0 or hut.glow_of(i) == 1.0)
		if hut.glow_of(i) == 1.0:
			glowing += 1
	assert_eq(glowing, 2 * 36, "a doorway and a window (two boxes)")
	assert_eq(hut.glow_of(0), 0.0, "walls do not glow")
	var fire := library.template_for(PropData.Kind.CAMPFIRE, 0)
	var burning := 0
	for i in fire.vertices.size():
		if fire.glow_of(i) == 2.0:
			burning += 1
	assert_true(burning >= 9, "the flame")
	assert_eq(fire.glow_of(0), 0.0, "stones do not burn")
	var tree := library.template_for(PropData.Kind.TREE, 0)
	assert_eq(tree.glow.size(), 0, "nothing on a tree glows")
	assert_eq(tree.glow_of(5), 0.0)
	# The marks reach the mesh (as UV.x), prop by prop.
	var coord := WorldCoords.tile_to_chunk(session.start.settlement_tile, session.world.chunk_size)
	var buffers := PropMesher.build_buffers(session.world, session.props, coord, library)
	assert_eq(buffers.uvs.size(), buffers.vertices.size())
	var marks := {}
	for uv in buffers.uvs:
		marks[uv.x] = int(marks.get(uv.x, 0)) + 1
	assert_true(marks.has(0.0) and marks.has(1.0) and marks.has(2.0), str(marks.keys()))
	var mesh := PropMesher.build_mesh(session.world, session.props, coord, library)
	assert_eq((mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size(), buffers.vertices.size())


# --- sounds ---------------------------------------------------------------------------------------

func test_crickets_come_with_the_dark() -> void:
	assert_true(AudioManager.has_sound(&"crickets"))
	var stream := AudioManager.sound(&"crickets") as AudioStreamWAV
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "a loop")
	var samples := SoundSynth.samples_for(&"crickets")
	assert_true(SoundSynth.seconds_of(samples) >= 3.0)
	assert_true(SoundSynth.peak(samples) > 0.2 and SoundSynth.peak(samples) <= 1.0)
	assert_true(absf(samples[0]) < 0.05 and absf(samples[samples.size() - 1]) < 0.05, "no click where the loop joins")
	AudioManager.start_ambience()
	var player := AudioManager.night_ambience_player()
	AudioManager.set_night(0.0)
	assert_false(player.playing, "silent by day")
	AudioManager.set_night(1.0)
	assert_true(player.playing)
	assert_near(player.volume_db, Config.feedback.crickets_volume_db, 0.01)
	assert_eq(player.bus, AudioManager.BUS_AMBIENCE, "under the ambience slider")
	AudioManager.set_night(0.25)
	assert_true(player.playing)
	assert_true(player.volume_db < Config.feedback.crickets_volume_db - 6.0, "quiet at dusk")
	AudioManager.set_night(0.0)
	assert_false(player.playing)
	# No ambience wanted (the game is in the background): no crickets either.
	AudioManager.set_night(1.0)
	AudioManager.stop_ambience()
	assert_false(player.playing)
	AudioManager.set_night(1.0)
	assert_false(player.playing)


func test_birds_roost_at_night_and_sing_at_dawn() -> void:
	var ambient := view.ambient()
	ambient.set_process(false)
	AudioManager.start_ambience()
	ambient.set_night(0.0, 13.0)
	assert_eq(ambient.chirp_rate(), 1.0, "an ordinary afternoon")
	assert_true((ambient.get("_birds") as Node3D).visible)
	ambient.set_night(DayNight.night_at(config.sunrise_hour + 0.75, config), config.sunrise_hour + 0.75)
	assert_true(ambient.chirp_rate() > 2.0, "the dawn chorus (%.2f)" % ambient.chirp_rate())
	ambient.set_night(1.0, 1.0)
	assert_eq(ambient.chirp_rate(), 0.0, "no birdsong at night")
	assert_false((ambient.get("_birds") as Node3D).visible, "the flock has gone to roost")
	assert_true(AudioManager.night_ambience_player().playing, "the crickets are told too")
	# At night nothing chirps, however long one waits; the fire crackles.
	AudioManager.last_sound = &""
	var until := ambient.seconds_until_chirp()
	for i in 200:
		ambient._process(0.5)
	assert_eq(ambient.seconds_until_chirp(), until, "the birds' clock stands still")
	assert_eq(AudioManager.last_sound, &"crackle")
	# By day the fire is not heard over the birds.
	ambient.set_night(0.0, 13.0)
	AudioManager.last_sound = &""
	var crackle_in := ambient.seconds_until_crackle()
	ambient._process(0.1)
	assert_eq(ambient.seconds_until_crackle(), crackle_in)
	# The running view tells the ambient life the hour.
	ambient.set_process(true)
	_set_hour(1.0)
	await wait_frames(2)
	assert_eq(ambient.night(), 1.0)
	_set_hour(12.0)
	await wait_frames(2)
	assert_eq(ambient.night(), 0.0)
