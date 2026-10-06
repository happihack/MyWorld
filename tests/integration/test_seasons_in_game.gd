extends TestCase
## The seasons on screen and in the ears (M9.2): what grows changes colour,
## trees stand bare and leaves fall, snow lies and the water freezes over,
## and in the cold the birds and the crickets are quiet.

const DAY := 1440

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var fx: WeatherFx
var weather: WeatherSystem
var seasons: SeasonsConfig
var days := 6
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
	session.set_process(false) # (the test says what time it is)
	fx = view.weather_fx()
	fx.set_process(false)
	weather = session.weather
	seasons = Config.seasons
	days = Config.time.days_per_season
	view.day_night().forced_hour = 12.0


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)
	Settings.reset_to_defaults()


## Sets the clock to the middle of a season (0 spring … 3 winter) — or, if
## an hour is given, to that hour of the day in the middle of it — and
## shows it at once.
func _season(index: int, hour: float = -1.0) -> void:
	var middle := roundi((index + 0.5) * days * DAY - Config.time.start_hour * 60.0)
	if hour >= 0.0:
		middle += roundi(hour * 60.0) - Config.time.minute_of_day(middle)
	session.clock.tick = middle
	fx.snap()


func test_what_grows_changes_with_the_year() -> void:
	assert_eq(seasons.validate().size(), 0, str(seasons.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	var props := view.prop_material()
	var ground := view.terrain_material()
	# Summer: as it was drawn.
	_season(Seasons.SUMMER)
	assert_near(fx.season, 1.5, 0.01)
	assert_near(props.get_shader_parameter(&"season_strength"), 0.0, 0.01)
	assert_near(props.get_shader_parameter(&"bare"), 0.0, 0.01)
	assert_near(ground.get_shader_parameter(&"season_strength"), 0.0, 0.01)
	assert_near(fx.leaf_fall, 0.0, 0.01)
	assert_false(fx.leaves_node().visible)
	# Autumn: the leaves turn, some trees thin, and leaves are in the air.
	_season(Seasons.AUTUMN)
	assert_near(props.get_shader_parameter(&"season_strength"), seasons.foliage_strength[Seasons.AUTUMN], 0.01)
	assert_true((props.get_shader_parameter(&"season_tint") as Color).is_equal_approx(seasons.foliage[Seasons.AUTUMN]))
	assert_true((props.get_shader_parameter(&"season_tint_other") as Color).is_equal_approx(seasons.foliage_other[Seasons.AUTUMN]))
	assert_near(props.get_shader_parameter(&"bare"), seasons.bare[Seasons.AUTUMN], 0.01)
	assert_true((ground.get_shader_parameter(&"season_ground") as Color).is_equal_approx(seasons.ground[Seasons.AUTUMN]))
	assert_near(fx.leaf_fall, seasons.leaf_fall[Seasons.AUTUMN], 0.01)
	var leaves := fx.leaves_node()
	assert_true(leaves.visible, "leaves in the air")
	var falling := leaves.material_override as ShaderMaterial
	assert_eq(falling.get_shader_parameter(&"tint"), seasons.leaf_color)
	assert_true(float(falling.get_shader_parameter(&"amount")) > 0.0)
	assert_true(float(falling.get_shader_parameter(&"fall_speed")) < Config.weather_fx.snow_speed + 1.0, "they drift down")
	assert_eq(leaves.multimesh.instance_count, fx.drop_count())
	# (Not for those who asked for less motion.)
	fx.reduced_motion = true
	fx.advance(0.0)
	assert_false(leaves.visible)
	fx.reduced_motion = false
	# Winter: the trees are bare, the grass is pale.
	_season(Seasons.WINTER)
	assert_near(props.get_shader_parameter(&"bare"), seasons.bare[Seasons.WINTER], 0.01)
	assert_true(float(props.get_shader_parameter(&"bare")) > 0.7)
	assert_near(ground.get_shader_parameter(&"season_strength"), seasons.ground_strength[Seasons.WINTER], 0.01)
	assert_true(fx.leaf_fall < 0.1)
	# Spring: the fresh green, and nearly everything in leaf again.
	_season(Seasons.SPRING)
	assert_true((props.get_shader_parameter(&"season_tint") as Color).is_equal_approx(seasons.foliage[Seasons.SPRING]))
	assert_true(float(props.get_shader_parameter(&"bare")) < 0.2)
	# Between two seasons it is between the two: nothing jumps when a season turns.
	session.clock.tick = roundi(2.0 * days * DAY - Config.time.start_hour * 60.0) - 1
	fx.snap()
	var before: float = props.get_shader_parameter(&"season_strength")
	session.clock.tick += 2
	fx.advance(0.0)
	assert_near(props.get_shader_parameter(&"season_strength"), before, 0.01)
	assert_near(before, (seasons.foliage_strength[Seasons.SUMMER] + seasons.foliage_strength[Seasons.AUTUMN]) * 0.5, 0.01)
	assert_true(fx.debug_text().contains("season "))


func test_snow_lies_and_the_water_freezes_over() -> void:
	var props := view.prop_material()
	var ground := view.terrain_material()
	var water := view.water_material()
	_season(Seasons.WINTER)
	assert_near(ground.get_shader_parameter(&"snow"), 0.0, 0.001)
	assert_near(water.get_shader_parameter(&"frozen"), 0.0, 0.001)
	# Snow has fallen and the frost is in the ground: shown at once in a world just opened.
	weather.snow_cover = 0.8
	weather.frost = 1.0
	weather.frozen = true
	fx.snap()
	assert_near(fx.snow, 0.8, 0.001)
	assert_near(ground.get_shader_parameter(&"snow"), 0.8, 0.001)
	assert_near(props.get_shader_parameter(&"snow"), 0.8, 0.001)
	assert_eq(ground.get_shader_parameter(&"snow_color"), seasons.snow_color)
	assert_near(water.get_shader_parameter(&"frozen"), 1.0, 0.001)
	assert_eq(water.get_shader_parameter(&"ice_color"), seasons.ice_color)
	var depth: float = water.get_shader_parameter(&"ice_depth")
	assert_true(depth > 0.0 and depth <= 1.0, "only the shallows freeze over (%.2f)" % depth)
	# It thaws: the white goes little by little, not from one frame to the next.
	weather.snow_cover = 0.0
	weather.frost = 0.0
	weather.frozen = false
	fx.advance(1.0 / 30.0)
	assert_true(fx.snow > 0.7 and fx.snow < 0.8, "%.3f" % fx.snow)
	assert_true(fx.ice > 0.9 and fx.ice < 1.0, "%.3f" % fx.ice)
	for i in 30 * 30:
		fx.advance(1.0 / 30.0)
	assert_near(fx.snow, 0.0, 0.001)
	assert_near(ground.get_shader_parameter(&"snow"), 0.0, 0.001)
	assert_near(water.get_shader_parameter(&"frozen"), 0.0, 0.001)


func test_the_cold_is_quiet() -> void:
	var ambient := view.ambient()
	# A summer's noon: the birds sing.
	weather.hold(&"clear", session.clock.tick + 1000 * DAY)
	_season(Seasons.SUMMER, 13.0)
	assert_true(weather.temperature() > seasons.birds_full)
	assert_near(ambient.bird_song(), 1.0, 0.001)
	# A winter's night: no bird, no cricket.
	_season(Seasons.WINTER, 3.0)
	assert_true(weather.temperature() < seasons.birds_from, "%.1f" % weather.temperature())
	assert_near(ambient.bird_song(), 0.0, 0.001)
	ambient.set_night(0.0, 12.0)
	assert_near(ambient.chirp_rate(), 0.0, 0.001, "nothing chirps, even by day")
	assert_near(ambient._crickets, 0.0, 0.001, "no cricket in the cold")
	ambient.set_warmth(seasons.crickets_full + 1.0)
	ambient.set_night(0.0, 12.0)
	assert_true(ambient.chirp_rate() > 0.0)
	assert_near(ambient._crickets, 1.0, 0.001)
	# No crickets in autumn and winter, however warm (the owner, 2026-10-06).
	for season: int in [Seasons.AUTUMN, Seasons.WINTER]:
		ambient.set_warmth(seasons.crickets_full + 5.0, season)
		assert_eq(ambient._crickets, 0.0, "none in season %d" % season)
	for season: int in [Seasons.SPRING, Seasons.SUMMER]:
		ambient.set_warmth(seasons.crickets_full + 5.0, season)
		assert_near(ambient._crickets, 1.0, 0.001, "a warm night in season %d" % season)
	# In between: some of the song.
	ambient.set_warmth((seasons.birds_from + seasons.birds_full) * 0.5)
	assert_true(ambient.bird_song() > 0.2 and ambient.bird_song() < 0.8)


func test_what_is_a_leaf() -> void:
	var library := PropMeshLibrary.new()
	# A broadleaf tree: its crown is shed, its trunk is not a leaf.
	var tree := library.template_for(PropData.Kind.TREE, 0)
	var shed := 0
	var wood := 0
	for i in tree.vertices.size():
		if is_equal_approx(tree.leaf_of(i), PropMeshLibrary.LEAF_SHED):
			shed += 1
		elif tree.leaf_of(i) == 0.0:
			wood += 1
	assert_true(shed > 0 and wood > 0, "%d leaf, %d wood" % [shed, wood])
	assert_eq(shed + wood, tree.vertices.size())
	# A conifer keeps its needles (they only pale a little); a rock is no leaf at all.
	var conifer := library.template_for(PropData.Kind.TREE, PropData.TREE_CONIFER_FIRST_VARIANT)
	var needles := 0
	for i in conifer.vertices.size():
		assert_true(conifer.leaf_of(i) <= PropMeshLibrary.LEAF_EVERGREEN + 0.001)
		if conifer.leaf_of(i) > 0.0:
			needles += 1
	assert_true(needles > 0)
	var rock := library.template_for(PropData.Kind.ROCK, 0)
	for i in rock.vertices.size():
		assert_eq(rock.leaf_of(i), 0.0)
	var bush := library.template_for(PropData.Kind.BUSH, 0)
	assert_near(bush.leaf_of(0), PropMeshLibrary.LEAF_TURNS, 0.001, "a bush turns, and keeps its leaves")
	# The meshes carry it to the shader (in the second texture coordinate).
	var carried := 0
	for chunk_view: ChunkView in view._chunk_views.values():
		var mesh := chunk_view.props_mesh()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		for uv in uvs:
			if uv.y > 0.9:
				carried += 1
		if carried > 0:
			break
	assert_true(carried > 0, "leaves in the meshes of the world")
