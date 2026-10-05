extends TestCase
## M17.1: what makes a settlement's people theirs — a profile, traditions
## from what they live through again and again (the player's doing among it),
## holidays kept at dusk by the fire, a ritual when a drought begins, and
## their own look (roofs, colours).

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var cultures: CultureSystem


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	cultures = session.cultures


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


## Everyone of the first settlement lives through `subject` (taken as
## `interpretation`, from the player's act `act`) on each of `days`.
func _live_through(subject: StringName, interpretation: StringName, days: Array, act: int) -> void:
	for day: int in days:
		var tick := day * TimeConfig.MINUTES_PER_DAY + 60
		for person in session.settlement.members():
			var memory := Memory.new()
			memory.subject = subject
			memory.interpretation = interpretation
			memory.source = Memory.Source.WITNESSED
			memory.tick = tick
			memory.first_tick = tick
			memory.importance = 0.8
			memory.intensity = 0.8
			memory.intervention_id = act
			memory.emotions = PackedFloat32Array([0.1, 0.6, 0.0, 0.7, 0.2])
			session.memories.remember(person, memory)


func test_the_profile() -> void:
	var own := session.settlement
	var profile := cultures.profile_of(own)
	for value: String in ["innovation", "collectivism", "piety"]:
		assert_true(float(profile[value]) >= -1.0 and float(profile[value]) <= 1.0, value)
	assert_eq(profile["architecture"], 0, "the band's way")
	assert_eq(profile["palette"], 0)
	# Those who take everything for a god's doing are pious.
	for person in own.members():
		var beliefs := Interpretation.beliefs_of(person)
		beliefs.fill(0.0)
		beliefs[ReactionTable.INTERPRETATIONS.find(ReactionTable.DEITY)] = 1.0
		person.beliefs = beliefs
	profile = cultures.profile_of(own)
	assert_near(profile["piety"], 1.0, 0.001)
	assert_eq(profile["presence"], ReactionTable.DEITY)
	# Another settlement has its own look (the same for a world, every time).
	var other := Settlement.new()
	other.id = 7
	session.settlements.add(other)
	var looks := {}
	for id in range(2, 40):
		other.id = id
		looks["%d/%d" % [cultures.architecture_of(other), cultures.palette_of(other)]] = true
	assert_true(looks.size() > 3, "settlements look different")
	assert_eq(cultures.architecture_of(other), cultures.architecture_of(other))
	session.settlements.remove(other)
	var meshes := PropMeshLibrary.new()
	for style in CultureSystem.ARCHITECTURES:
		assert_not_null(meshes.template_for(PropData.Kind.HUT, style), "roof %d" % style)


func test_tradition_from_repetition() -> void:
	var own := session.settlement
	# Rain out of a clear sky, the player's doing, taken for a god's: on days
	# of two seasons. Not yet: too few days.
	_live_through(Stimulus.RAIN_FROM_CLEAR_SKY, ReactionTable.DEITY, [1, 2], 42)
	session.culture.settle(3 * TimeConfig.MINUTES_PER_DAY)
	cultures.look_for_traditions(3 * TimeConfig.MINUTES_PER_DAY)
	assert_true(cultures.traditions_of(own.id).is_empty(), "twice is not a tradition")
	_live_through(Stimulus.RAIN_FROM_CLEAR_SKY, ReactionTable.DEITY, [3, 7, 8], 42)
	var now := 9 * TimeConfig.MINUTES_PER_DAY
	session.culture.settle(now)
	cultures.look_for_traditions(now)
	var formed := cultures.traditions_of(own.id)
	assert_eq(formed.size(), 1)
	var dance := formed[0]
	assert_eq(dance["name"], "TRADITION_RAIN_DANCE")
	assert_eq(dance["when"], "drought")
	assert_true(dance["player"], "it goes back to the player")
	assert_eq(dance["intervention"], 42, "to this act of the player's")
	var told := session.events.of_type(&"tradition_formed")
	assert_eq(told.size(), 1)
	assert_eq(EventText.text(told[0], session.people),
		"%s has begun to keep the rain dance — it began with something nobody could explain" % own.display_name())
	# Once only.
	cultures.look_for_traditions(now + 60)
	assert_eq(cultures.traditions_of(own.id).size(), 1)
	# A drought begins: they dance for rain that evening — at the fire.
	session.clock.tick = now + 10 * 60 # (16:00)
	cultures.on_condition(WeatherSystem.DROUGHT, true, session.clock.tick)
	assert_true(cultures.festival_now(own.id, session.clock.tick).is_empty(), "at dusk, not before")
	session.clock.tick = now + 12 * 60 + 30
	assert_false(cultures.festival_now(own.id, session.clock.tick).is_empty())
	var person: PersonData = own.members()[0]
	var ctx := session.behavior.ctx
	assert_true(Planner.can(&"festival", person, ctx))
	var steps := Planner.plan(&"celebrate", person, ctx)
	assert_eq(steps.size(), 3, "to the fire, to dance")
	assert_eq(int(steps[1]["pose"]), PersonData.Pose.JUMP)
	# Saved.
	var again := CultureSystem.new()
	again.from_dict(bytes_to_var(var_to_bytes(cultures.to_dict())))
	assert_eq(again.traditions.size(), 1)
	assert_eq(again.traditions[0]["intervention"], 42)


func test_firsts_become_festivals_kept_each_year() -> void:
	var own := session.settlement
	session.events.record(&"first_farm", {"settlement": own.id})
	cultures.look_for_traditions(session.clock.tick)
	var harvest := cultures.tradition_of(own.id, &"first_farm")
	assert_false(harvest.is_empty())
	assert_false(harvest["player"], "nature's doing, and theirs")
	var day: int = harvest["day"]
	assert_eq(day, Config.time.days_per_season * 2 + 1, "the first day of autumn")
	# Its day, at dusk: the festival (told), for three hours.
	var dusk := (day - 1) * TimeConfig.MINUTES_PER_DAY + roundi((18.5 - Config.time.start_hour) * 60.0)
	cultures.advance_to(dusk - 1440)
	cultures.advance_to(dusk)
	assert_false(cultures.festival_now(own.id, dusk).is_empty())
	assert_true(cultures.festival_now(own.id, dusk + 4 * 60).is_empty(), "over by night")
	var told := session.events.of_type(&"festival")
	assert_eq(told.size(), 1)
	assert_eq(EventText.text(told[0], session.people), "The harvest festival begins at dusk in %s" % own.display_name())
	assert_eq(int(harvest["kept"]), 1)
	# A year on, again.
	var next := dusk + Config.time.ticks_per_year()
	cultures.advance_to(next - 60)
	cultures.advance_to(next)
	assert_eq(int(harvest["kept"]), 2)


func test_a_tradition_fades_when_its_root_is_forgotten() -> void:
	var own := session.settlement
	_live_through(Stimulus.TOUCH, ReactionTable.SPIRIT, [1, 2, 3, 7, 8], 9)
	var now := 9 * TimeConfig.MINUTES_PER_DAY
	session.culture.settle(now)
	cultures.look_for_traditions(now)
	assert_false(cultures.tradition_of(own.id, Stimulus.TOUCH).is_empty(), "the Blessing of the Young")
	# Nobody remembers it any more (they have died, it has faded)…
	for person in own.members():
		for memory in session.memories.about(person, Stimulus.TOUCH):
			session.memories.forget(person, memory.id)
	var later := now + 30 * TimeConfig.MINUTES_PER_DAY
	for i in 40:
		session.culture.settle(later + i * TimeConfig.MINUTES_PER_DAY)
	cultures.look_for_traditions(later)
	assert_false(cultures.tradition_of(own.id, Stimulus.TOUCH).is_empty(), "not at once")
	cultures.look_for_traditions(later + (CultureSystem.FADES_AFTER_YEARS + 1) * Config.time.ticks_per_year())
	assert_true(cultures.tradition_of(own.id, Stimulus.TOUCH).is_empty(), "years later, gone")
	assert_eq(session.events.of_type(&"tradition_faded").size(), 1)


func test_homes_are_roofed_their_settlements_way() -> void:
	var calls: Array = []
	session.construction.style_of = func(id: int) -> int:
		calls.append(id)
		return 2
	var own := session.settlement
	var fire := own.fire().tile
	var tile := Vector2i(-1000, -1000)
	for r in range(3, 9):
		for dx in [r, -r]:
			var t := fire + Vector2i(dx, r)
			if tile == Vector2i(-1000, -1000) and session.props.prop_at(t) == null and session.world.get_water(t) <= 0.0:
				tile = t
	var project := session.construction.start(&"hut", tile, session.clock.tick, 0, own.id)
	assert_false(project.is_empty())
	session.construction._finish(project, session.clock.tick)
	var hut := session.props.prop_at(tile)
	assert_not_null(hut)
	assert_eq(hut.kind, PropData.Kind.HUT)
	assert_eq(hut.variant, 2, "hide roofs")
	assert_eq(calls, [own.id])


func test_everyone_comes_to_the_festival() -> void:
	var own := session.settlement
	session.events.record(&"first_farm", {"settlement": own.id})
	cultures.look_for_traditions(session.clock.tick)
	var day: int = cultures.tradition_of(own.id, &"first_farm")["day"]
	var dusk := (day - 1) * TimeConfig.MINUTES_PER_DAY + roundi((18.0 - Config.time.start_hour) * 60.0)
	session.clock.tick = dusk - 10
	cultures.advance_to(dusk - TimeConfig.MINUTES_PER_DAY)
	var behavior := session.behavior
	var most := 0
	for minute in 90:
		var seconds := 1.0 * Config.time.real_seconds_per_game_minute
		while seconds > 0.000001:
			var piece := minf(seconds, Config.time.max_frame_delta_s)
			session.clock.advance(piece)
			seconds -= piece
		cultures.advance_to(session.clock.tick)
		behavior.step(1.0)
		session.pathfinder.serve(1_000_000)
		session.movement.step(1.0)
		var at := own.members().filter(func(p: PersonData) -> bool: return BehaviorSystem.activity_of(p) == &"celebrate").size()
		most = maxi(most, at)
	assert_true(most * 2 >= own.member_count(), "most of them come (%d of %d)" % [most, own.member_count()])
