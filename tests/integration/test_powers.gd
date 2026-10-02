extends TestCase
## The player's powers over weather and water (M9.5, bible §23.2): rain,
## wind and carving as interventions — what they do to the world, what the
## people may notice of them, the history — and when each power shows itself.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const V17_FIXTURE := "res://tests/fixtures/saves/v17_world.sav"
const V17_ID := "w1790975871_fde1ea1f"
const DAY := 1440

var session: WorldSession
var acts: InteractionManager
var world: WorldData
var weather: WeatherSystem
var river: Hydrology
var clock: GameClock
var config: ToolsConfig
var stimuli: Array[Stimulus] = []
var _knobs: Array = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	session.behavior.enabled = false
	acts = session.interactions
	world = session.world
	weather = session.weather
	river = session.hydrology
	clock = session.clock
	config = Config.tools
	river.enabled = false # (the river moves only by what the player does here)
	weather.hold(&"clear", clock.tick + 1000 * DAY)
	stimuli.clear()
	acts.stimulus_emitted.connect(func(stimulus: Stimulus) -> void: stimuli.append(stimulus))


func after_each() -> void:
	_knobs.reverse()
	for knob: Array in _knobs:
		(knob[0] as Resource).set(knob[1], knob[2])
	_knobs.clear()
	session.queue_free()
	await wait_frames(1)


func _knob(resource: Resource, knob: StringName, value: Variant) -> void:
	_knobs.append([resource, knob, resource.get(knob)])
	resource.set(knob, value)


## Open grass on the valley floor near the settlement, with nothing standing
## within `clear` tiles of it and no water under a cloud over it.
func _open_ground(clear: int = 1, dry_within: float = 0.0) -> Vector2i:
	var home := session.start.settlement_tile
	for ring in range(4, 16):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var tile := home + Vector2i(dx, dy)
				if not world.is_in_bounds(tile) or world.get_height(tile) != world.get_height(home):
					continue
				var fine := true
				for y in range(-clear, clear + 1):
					for x in range(-clear, clear + 1):
						var near := tile + Vector2i(x, y)
						if world.get_terrain(near) != ChunkData.Terrain.GRASS or world.get_water(near) > 0.0 or session.props.has_prop_at(near):
							fine = false
				if fine and dry_within > 0.0:
					for y in range(-ceili(dry_within), ceili(dry_within) + 1):
						for x in range(-ceili(dry_within), ceili(dry_within) + 1):
							if world.get_water(tile + Vector2i(x, y)) > 0.0:
								fine = false
				if fine:
					return tile
	return Vector2i(-999, -999)


func _middle(tile: Vector2i) -> Vector2:
	return Vector2(tile) + Vector2(0.5, 0.5)


func _moisture(tile: Vector2i) -> int:
	return world.chunk_at_tile(tile).moisture[world.index_at_tile(tile)]


func _set_moisture(tile: Vector2i, value: int) -> void:
	world.chunk_at_tile(tile).moisture[world.index_at_tile(tile)] = value


func test_rain_wets_the_land_and_is_one_act() -> void:
	assert_eq(config.validate().size(), 0, str(config.validate()))
	assert_eq(Config.problems.size(), 0, str(Config.problems))
	var tile := _open_ground(1, config.rain_radius + 1.0)
	assert_true(world.is_in_bounds(tile))
	var at := _middle(tile)
	var far := tile + Vector2i(ceili(config.rain_radius) + 2, 0)
	_set_moisture(tile, 100)
	_set_moisture(tile + Vector2i(2, 0), 100)
	var far_before := _moisture(far)
	var level := river.level
	# The cloud forms: nothing has fallen yet, nothing is in the history — but it is seen.
	assert_true(acts.sky_is_clear())
	var begun := acts.rain(at, 0.0, Intervention.PHASE_BEGIN)
	assert_true(begun.applied)
	assert_false(begun.recorded)
	assert_eq(begun.subject, &"rain")
	assert_eq(session.history.total(), 0)
	assert_eq(stimuli.size(), 1)
	assert_eq(stimuli[0].type, Stimulus.RAIN_FROM_CLEAR_SKY)
	assert_true(stimuli[0].anomalous and stimuli[0].large and stimuli[0].weatherlike, "rain out of a clear sky is uncanny")
	assert_eq(stimuli[0].position, at)
	assert_eq(_moisture(tile), 100)
	# It rains: the soil under the cloud takes it, pulse by pulse; the soil beyond does not.
	var fallen := 0.0
	for n in 10:
		var more := acts.rain(at, 0.3, Intervention.PHASE_MORE)
		assert_true(more.applied and not more.recorded)
		fallen += 0.3
	var gained := _moisture(tile) - 100
	assert_true(absi(gained - roundi(fallen * config.rain_moisture_per_unit)) <= 1, "%d gained" % gained)
	assert_eq(_moisture(tile + Vector2i(2, 0)), _moisture(tile))
	assert_eq(_moisture(far), far_before)
	assert_true(world.chunk_at_tile(tile).modified)
	assert_eq(stimuli.size(), 1, "not noticed anew with every drop")
	assert_eq(session.history.total(), 0)
	# What falls on land runs off into the river (a little).
	assert_near(river.level, level + fallen * config.rain_river_rise * config.rain_runoff_share, 0.00001)
	# The finger lifts: one act in the history, a gentle one.
	var ended := acts.rain(at, fallen, Intervention.PHASE_END)
	assert_true(ended.applied and ended.recorded)
	assert_eq(ended.severity, Intervention.Severity.GENTLE)
	assert_eq(session.history.count(Intervention.MAKE_RAIN), 1)
	assert_eq(session.history.count(Intervention.MAKE_RAIN, &"rain"), 1)
	assert_near(session.history.total_of(&"rain_made"), fallen, 0.0001)
	assert_eq(stimuli.size(), 1, "a little rain is not noticed twice")
	assert_eq(HistoryText.text(session.history.entries()[-1]), "made it rain for the first time")
	# A great deal of it is no longer gentle — and is noticed again, more strongly.
	acts.rain(at, 0.0, Intervention.PHASE_BEGIN)
	var much := acts.rain(at, config.rain_moderate_units * 2.0, Intervention.PHASE_END)
	assert_eq(much.severity, Intervention.Severity.MODERATE)
	assert_eq(stimuli.size(), 3)
	assert_true(stimuli[2].intensity > stimuli[1].intensity)
	assert_eq(session.history.count(Intervention.MAKE_RAIN), 2)
	# A cloud that came and went with nothing fallen is nothing.
	acts.rain(at, 0.0, Intervention.PHASE_BEGIN)
	var nothing := acts.rain(at, 0.0, Intervention.PHASE_END)
	assert_false(nothing.applied)
	assert_eq(nothing.rejected, &"nothing_fell")
	assert_eq(session.history.count(Intervention.MAKE_RAIN), 2)
	# Outside the box there is no ground to rain on.
	assert_eq(acts.rain(Vector2(9999.0, 0.0), 1.0, Intervention.PHASE_BEGIN).rejected, &"no_ground")
	# Soil cannot be wetter than soaked.
	_set_moisture(tile, 250)
	acts.rain(at, 5.0, Intervention.PHASE_MORE)
	assert_eq(_moisture(tile), 255)


func test_rain_under_clouds_is_only_rain() -> void:
	var at := _middle(_open_ground())
	weather.hold(&"cloudy", clock.tick + 1000 * DAY)
	assert_false(acts.sky_is_clear())
	acts.rain(at, 0.0, Intervention.PHASE_BEGIN)
	assert_eq(stimuli.size(), 1)
	assert_eq(stimuli[0].type, Stimulus.RAIN_FELL)
	assert_false(stimuli[0].anomalous, "rain from a grey sky is the weather")
	assert_true(stimuli[0].weatherlike)
	assert_true(stimuli[0].intensity < Config.reactions.stimuli[Stimulus.RAIN_FROM_CLEAR_SKY][0])
	# What the sky was like when it began holds for the whole of it.
	weather.hold(&"clear", clock.tick + 1000 * DAY)
	var ended := acts.rain(at, config.rain_moderate_units * 2.0, Intervention.PHASE_END)
	assert_eq(stimuli[-1].type, Stimulus.RAIN_FELL)
	assert_false(ended.params["clear_sky"])
	# Every kind has its words.
	for type: StringName in [Stimulus.RAIN_FROM_CLEAR_SKY, Stimulus.RAIN_FELL, Stimulus.SOURCELESS_WIND, Stimulus.GROUND_CARVED]:
		assert_true(Stimulus.TYPES.has(type))
		assert_true(Config.reactions.stimuli.has(type))
		for prefix: String in ["DAY_AT_", "MEM_", "MEMWHAT_"]:
			var key := prefix + String(type).to_upper()
			assert_ne(TranslationServer.translate(key), StringName(key), key)
	for type: StringName in [Intervention.MAKE_RAIN, Intervention.MAKE_WIND, Intervention.CARVE]:
		for prefix: String in ["HIST_", "HIST_FIRST_"]:
			var key := prefix + String(type).to_upper()
			assert_ne(TranslationServer.translate(key), StringName(key), key)


func test_rain_saves_a_dry_field_and_raises_the_river() -> void:
	# A crop in soil that has dried out, wilting.
	var farming := session.farming
	var plot: Vector2i = farming.next_plot()
	var crop := farming.sow(plot, clock.tick)
	assert_not_null(crop)
	_set_moisture(plot, Config.farming.wilt_below - 30)
	assert_near(Farming.moisture_factor(_moisture(plot)), 0.0, 0.001, "nothing grows in it")
	# Ten seconds of rain over it.
	acts.rain(_middle(plot), 0.0, Intervention.PHASE_BEGIN)
	for n in 20:
		acts.rain(_middle(plot), config.rain_units_per_second * config.rain_pulse_seconds, Intervention.PHASE_MORE)
	assert_true(_moisture(plot) > Config.farming.wilt_below, "%d" % _moisture(plot))
	assert_true(Farming.moisture_factor(_moisture(plot)) > 0.0, "it grows again")
	# Rain on the river itself raises it far more than rain on land — a long rain floods.
	var bed := river.bed()[river.bed().size() / 2]
	var before := river.level
	acts.rain(_middle(bed), 0.0, Intervention.PHASE_BEGIN)
	acts.rain(_middle(bed), 10.0, Intervention.PHASE_MORE)
	var rise := river.level - before
	assert_true(rise > 10.0 * config.rain_river_rise * 0.6, "%.4f" % rise)
	assert_true(rise <= 10.0 * config.rain_river_rise + 0.00001)
	var surface := river.surface()
	acts.rain(_middle(bed), 10.0, Intervention.PHASE_END)
	assert_true(river.surface() > surface, "when it ends the river's tiles have it")
	for n in 60:
		acts.rain(_middle(bed), 10.0, Intervention.PHASE_MORE)
	assert_near(river.level, Config.hydrology.highest, 0.0001, "the box is not filled")
	acts.rain(_middle(bed), 600.0, Intervention.PHASE_END)
	assert_true(river.flooded, "rain without end is a flood")


func test_a_gust_blows_light_things_along() -> void:
	var tile := _open_ground(3)
	var from := _middle(tile) + Vector2(-3.0, 0.0)
	var to := from + Vector2(2.0, 0.0)
	var loose := session.loose
	# A pebble and a fruit in its way, a pebble beside its way, a pebble behind it, a boulder in its way.
	var in_way := acts._spawn(LooseObject.Kind.PEBBLE, from + Vector2(3.0, 0.3), 0.0, 100)
	var fruit := acts._spawn(LooseObject.Kind.FRUIT, from + Vector2(5.0, -0.5), 0.0, 100)
	var beside := acts._spawn(LooseObject.Kind.PEBBLE, from + Vector2(3.0, config.wind_width + 1.0), 0.0, 100)
	var behind := acts._spawn(LooseObject.Kind.PEBBLE, from + Vector2(-2.0, 0.0), 0.0, 100)
	var boulder := acts._spawn(LooseObject.Kind.BOULDER, from + Vector2(4.0, 0.0), 0.0, 100)
	for object: LooseObject in [in_way, fruit, beside, behind, boulder]:
		object.state = LooseObject.State.RESTING
		loose.touch(object.id)
	var gust := acts.gust(from, to, 1.0)
	assert_true(gust.applied and gust.recorded)
	assert_eq(gust.subject, &"wind")
	assert_eq(gust.severity, Intervention.Severity.MODERATE)
	assert_eq(gust.params["direction"], Vector2.RIGHT)
	assert_eq(gust.params["pushed"], 2)
	assert_true(in_way.velocity.x > config.wind_push * 0.8 and absf(in_way.velocity.z) < 0.001, str(in_way.velocity))
	assert_ne(in_way.state, LooseObject.State.RESTING)
	assert_true(fruit.velocity.x > in_way.velocity.x, "the lighter, the faster")
	assert_eq(beside.velocity, Vector3.ZERO)
	assert_eq(behind.velocity, Vector3.ZERO)
	assert_eq(boulder.velocity, Vector3.ZERO, "a boulder does not move for a gust")
	assert_near(Vector2(gust.position.x, gust.position.z).distance_to(from + Vector2.RIGHT * config.wind_reach * 0.5), 0.0, 0.001)
	# They come to rest further along.
	var was := in_way.position
	for n in 200:
		session.loose_system.step(1.0 / 30.0)
	assert_true(in_way.position.x > was.x + 0.5, "%s -> %s" % [was, in_way.position])
	assert_eq(in_way.state, LooseObject.State.RESTING)
	# It is in the history, and it was felt: a gust from nowhere.
	assert_eq(session.history.count(Intervention.MAKE_WIND, &"wind"), 1)
	assert_eq(HistoryText.text(session.history.entries()[-1]), "sent a gust of wind for the first time")
	assert_eq(stimuli.size(), 1)
	assert_eq(stimuli[0].type, Stimulus.SOURCELESS_WIND)
	assert_true(stimuli[0].anomalous and stimuli[0].weatherlike)
	# A weaker gust: slower things, a fainter stimulus.
	in_way.velocity = Vector3.ZERO
	in_way.position = from + Vector2(3.0, 0.3)
	loose.touch(in_way.id)
	var weak := acts.gust(from, to, 0.4)
	assert_true(in_way.velocity.x > 0.0 and in_way.velocity.x < config.wind_push * 0.5)
	assert_true(stimuli[1].intensity < stimuli[0].intensity)
	assert_near(weak.magnitude, 0.4, 0.0001)
	# While the weather's wind blows hard, a gust is nothing strange.
	weather.wind_speed = 0.8
	assert_true(acts.gust(from, to, 1.0).params["ordinary"])
	assert_false(stimuli[-1].anomalous)
	weather.wind_speed = 0.1
	# No direction, no gust.
	var none := acts.gust(from, from, 1.0)
	assert_false(none.applied)
	assert_eq(none.rejected, &"no_direction")
	assert_eq(session.history.count(Intervention.MAKE_WIND), 3)


func test_a_gust_frightens_the_animals() -> void:
	var animal := session.animals.all_animals()[0]
	var from := animal.position + Vector2(-4.0, 0.0)
	acts.gust(from, from + Vector2(2.0, 0.0), 1.0)
	assert_eq(animal.state, AnimalData.State.FLEE)


func test_carving_a_channel() -> void:
	var tile := _open_ground(2)
	var height := world.get_height(tile)
	var changed: Array = []
	world.ground_changed.connect(func(where: Vector2i) -> void: changed.append(where))
	# What can be carved: open ground — not water, not rock, not where something stands, not outside.
	assert_true(acts.can_carve(tile))
	assert_false(acts.can_carve(river.bed()[0]))
	assert_false(acts.can_carve(Vector2i(9999, 0)))
	var tree: PropData = null
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE:
			tree = prop
			break
	assert_false(acts.can_carve(tree.tile), "not under a tree")
	assert_false(acts.can_carve(session.start.settlement_tile), "not under the fire")
	var rock := Vector2i(-999, -999)
	for chunk in world.loaded_chunks():
		for i in chunk.terrain.size():
			if chunk.terrain[i] == ChunkData.Terrain.ROCK and rock.x == -999:
				@warning_ignore("integer_division")
				rock = WorldCoords.chunk_origin(chunk.coord, world.chunk_size) + Vector2i(i % world.chunk_size, i / world.chunk_size)
	if rock.x != -999 and not session.props.has_prop_at(rock):
		assert_false(acts.can_carve(rock), "not through rock")
	# The first tile of a stroke: a level lower, bare earth — seen, not yet history.
	var first := acts.carve(tile, Intervention.PHASE_BEGIN)
	assert_true(first.applied)
	assert_false(first.recorded)
	assert_eq(first.subject, &"ground")
	assert_eq(first.severity, Intervention.Severity.MODERATE)
	assert_eq(world.get_height(tile), height - 1)
	assert_eq(world.get_terrain(tile), ChunkData.Terrain.DIRT)
	assert_true(changed.has(tile))
	assert_eq(stimuli.size(), 1)
	assert_eq(stimuli[0].type, Stimulus.GROUND_CARVED)
	assert_true(stimuli[0].anomalous)
	assert_eq(session.history.total(), 0)
	# The next tiles: no new stimulus.
	assert_true(acts.carve(tile + Vector2i(1, 0), Intervention.PHASE_MORE).applied)
	assert_true(acts.carve(tile + Vector2i(2, 0), Intervention.PHASE_MORE).applied)
	assert_eq(stimuli.size(), 1)
	# A channel is shallow: the same tile does not go deeper.
	var again := acts.carve(tile, Intervention.PHASE_MORE)
	assert_false(again.applied)
	assert_eq(again.rejected, &"cannot_carve")
	assert_eq(world.get_height(tile), height - 1)
	# The stroke ends: one act, with how much was carved.
	var ended := acts.carve(tile + Vector2i(2, 0), Intervention.PHASE_END, &"water", 3)
	assert_true(ended.applied and ended.recorded)
	assert_eq(session.history.count(Intervention.CARVE, &"ground"), 1)
	assert_near(session.history.total_of(&"tiles_carved"), 3.0, 0.0001)
	assert_eq(HistoryText.text(session.history.entries()[-1]), "carved a channel for the first time")
	assert_eq(stimuli.size(), 1)
	assert_eq(acts.carve(tile, Intervention.PHASE_END, &"water", 0).rejected, &"nothing_carved")
	# The paths know the new ground (a step down is still walked).
	session.pathfinder.refresh_dirty()
	assert_true(session.pathfinder.can_stand(tile))
	# It is a change of the ground like any other: kept in the save.
	assert_true(world.chunk_at_tile(tile).modified)


func test_a_channel_from_the_river_fills_with_its_water() -> void:
	# From the bank inland, across the valley floor.
	var bank := Vector2i(-999, -999)
	var inland := Vector2i.ZERO
	for bed in river.bed():
		for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
			var sand := bed + side
			var first := sand + side
			if bank.x != -999 or world.get_terrain(sand) != ChunkData.Terrain.SAND or world.get_water(sand) <= 0.0:
				continue
			var fine := true
			for n in 3:
				fine = fine and acts.can_carve(first + side * n) and world.get_height(first + side * n) == world.get_height(sand) + 1
			if fine:
				bank = first
				inland = side
	assert_true(world.is_in_bounds(bank), "open valley floor beside the bank")
	var tiles: Array[Vector2i] = [bank, bank + inland, bank + inland * 2]
	var body := river.body_size()
	for n in tiles.size():
		assert_near(world.get_water(tiles[n]), 0.0, 0.0001)
		assert_true(acts.carve(tiles[n], Intervention.PHASE_BEGIN if n == 0 else Intervention.PHASE_MORE).applied)
	acts.carve(tiles[-1], Intervention.PHASE_END, &"water", tiles.size())
	# The river follows the channel.
	assert_eq(river.body_size(), body + 3)
	for tile in tiles:
		assert_true(river.is_river(tile))
		assert_near(world.get_water(tile) + world.get_height(tile) * world.height_step, river.surface(), 0.001)
	assert_near(world.get_water(tiles[-1]), 0.16, 0.01, "as deep as the bank")
	assert_false(acts.can_carve(tiles[0]), "water is not carved")
	# It can be waded, and the land beside it is by the water now.
	session.pathfinder.refresh_dirty()
	assert_true(session.pathfinder.can_stand(tiles[1]))
	assert_true(session.pathfinder.speed_factor(tiles[1]) < 0.9)


func test_powers_show_themselves() -> void:
	var powers := session.powers
	var shown: Array = []
	powers.revealed.connect(func(id: StringName) -> void: shown.append(id))
	assert_eq(powers.known(), [] as Array[StringName], "none at first")
	assert_false(powers.is_known(ToolReveals.RAIN))
	assert_eq(powers.since(ToolReveals.RAIN), -1)
	# The first rain: the idea of rain.
	weather.hold(&"cloudy", clock.tick + 1000 * DAY)
	assert_eq(shown, [])
	clock.tick += 60
	weather.hold(&"rain", clock.tick + 1000 * DAY)
	assert_eq(shown, [ToolReveals.RAIN])
	assert_eq(powers.since(ToolReveals.RAIN), clock.tick)
	# The first storm: wind. (Neither twice.)
	weather.hold(&"storm", clock.tick + 1000 * DAY)
	weather.hold(&"rain", clock.tick + 1000 * DAY)
	weather.hold(&"storm", clock.tick + 1000 * DAY)
	assert_eq(shown, [ToolReveals.RAIN, ToolReveals.WIND])
	# The water touched three times: the water tool.
	var bed := river.bed()[0]
	var target := Picker.Result.new()
	target.kind = Picker.Kind.WATER
	target.tile = bed
	target.position = Vector3(bed.x + 0.5, river.surface(), bed.y + 0.5)
	for n in config.water_touches - 1:
		acts.tap(target)
	assert_false(powers.is_known(ToolReveals.WATER))
	acts.tap(target)
	assert_eq(shown, [ToolReveals.RAIN, ToolReveals.WIND, ToolReveals.WATER])
	assert_eq(powers.known(), ToolReveals.ALL)
	# Only powers there are.
	assert_false(powers.reveal(&"lightning", clock.tick))
	# Kept with the world.
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	var told: Array = []
	again.powers.revealed.connect(func(id: StringName) -> void: told.append(id))
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.powers.known(), ToolReveals.ALL)
	assert_eq(again.powers.since(ToolReveals.RAIN), powers.since(ToolReveals.RAIN))
	assert_eq(told, [], "nothing is shown anew on opening")
	again.queue_free()
	# A world from before powers were kept finds those it has earned — quietly.
	var older: Dictionary = loaded.world.duplicate(true)
	(older["world_state"] as Dictionary).erase("powers")
	var old: WorldSession = SessionScript.new()
	add_child(old)
	told.clear()
	old.powers.revealed.connect(func(id: StringName) -> void: told.append(id))
	assert_true(old.load_from(older))
	old.set_process(false)
	assert_true(old.powers.is_known(ToolReveals.WATER), "the water was touched three times")
	assert_true(old.powers.is_known(ToolReveals.WIND), "a storm is in its chronicle")
	assert_true(old.powers.is_known(ToolReveals.RAIN))
	assert_eq(told, [])
	old.queue_free()
	# Nonsense in a save does no harm.
	powers.from_dict({"known": {"rain": "soon", "lightning": 3, "wind": 7}})
	assert_eq(powers.known(), [ToolReveals.WIND] as Array[StringName])
	powers.from_dict({"known": 4})
	assert_eq(powers.known(), [] as Array[StringName])


func test_a_dry_crop_gives_the_idea_of_rain() -> void:
	var powers := session.powers
	var farming := session.farming
	var crop := farming.sow(farming.next_plot(), clock.tick)
	crop.variant = Farming.Stage.GROWING
	crop.growth = 500
	session.is_active = true
	session._look_for_powers()
	assert_false(powers.is_known(ToolReveals.RAIN), "a healthy crop gives no such idea")
	crop.vigor = Config.farming.looks_dry_below - 50
	assert_true(Farming.looks_dry(crop))
	session._look_for_powers()
	assert_false(powers.is_known(ToolReveals.RAIN), "looked at once an hour")
	clock.tick += 60
	session._look_for_powers()
	assert_true(powers.is_known(ToolReveals.RAIN))


func test_version_17_save_gets_its_powers() -> void:
	var dir := SaveManager.world_dir(V17_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	write_bytes(dir.path_join("world.sav"), FileAccess.get_file_as_bytes(V17_FIXTURE))
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], 17)
	var loaded := SaveManager.load_world(V17_ID)
	assert_true(loaded.ok, loaded.error)
	assert_eq(loaded.world["world_state"]["powers"], {})
	var s: WorldSession = SessionScript.new()
	add_child(s)
	assert_true(s.load_from(loaded.world))
	s.set_process(false)
	assert_eq(s.people.size(), 8)
	assert_eq(s.powers.known(), [] as Array[StringName], "a morning's world has earned none yet")
	# Saved again: the current version, the old file kept.
	assert_true(SaveManager.save_world(s, &"test"))
	assert_true(SaveManager.SAVE_VERSION >= 18)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav")).header["save_version"], SaveManager.SAVE_VERSION)
	assert_eq(SaveContainer.read_header(dir.path_join("world.sav.bak1")).header["save_version"], 17)
	s.queue_free()
	# The step itself.
	assert_eq(SaveMigrations._v17_to_v18({"world": {"world_state": {}}})["world"]["world_state"], {})
	assert_eq(SaveMigrations._v17_to_v18({"world": {"world_state": {"people": {}}}})["world"]["world_state"]["powers"], {})
	var kept: Dictionary = SaveMigrations._v17_to_v18({"world": {"world_state": {"powers": {"known": {"rain": 5}}}}})
	assert_eq(kept["world"]["world_state"]["powers"], {"known": {"rain": 5}})
