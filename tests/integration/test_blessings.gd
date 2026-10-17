extends TestCase
## The blessings the player gives (the owner and Josh, 2026-10-16; the
## plan's BLESSINGS section): the other hand of the Presence. One at a time
## with the disasters and the one rest after either; the lights in the sky
## come and go, harm nobody, are noticed, written down, and kept with the
## world while they last.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var blessings: BlessingSystem
var disasters: DisasterSystem
var clock: GameClock
var stimuli: Array[Stimulus] = []


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
	blessings = session.blessings
	disasters = session.disasters
	clock = session.clock
	stimuli.clear()
	session.interactions.stimulus_emitted.connect(func(stimulus: Stimulus) -> void: stimuli.append(stimulus))


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _fire() -> Vector2:
	return session.settlement.fire().position2d()


## The clock moves on `minutes`, and both hands with it.
func _pass(minutes: int) -> void:
	clock.tick += minutes
	disasters.advance_to(clock.tick)
	blessings.advance_to(clock.tick)


func test_one_act_a_day_whichever_hand() -> void:
	assert_eq(BlessingSystem.KINDS.size(), 4, "the first cut so far: the lights, the land, the water")
	assert_true(bool(Settings.get_value(&"gameplay/gentle_hands")), "gentle hands are on")
	var iv := session.interactions.bless(BlessingSystem.LIGHTS, _fire())
	assert_true(iv.applied, "asked for and confirmed: not held back by gentle hands (%s)" % iv.rejected)
	assert_eq(iv.severity, Intervention.Severity.MAJOR)
	assert_eq(session.history.count(Intervention.BLESSING, BlessingSystem.LIGHTS), 1, "in the player's history")
	assert_true(blessings.is_active())
	# Neither hand while the other is busy.
	assert_false(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied, "one at a time")
	var curse := session.interactions.disaster(DisasterSystem.ECLIPSE, _fire())
	assert_false(curse.applied, "no disaster while a blessing goes on")
	assert_eq(curse.rejected, &"resting")
	assert_false(disasters.can_start(clock.tick))
	assert_eq(disasters.rest_left(clock.tick), blessings.rest_left(clock.tick), "the one rest, seen from either button")
	_pass(int(BlessingSystem.LASTS[BlessingSystem.LIGHTS]))
	assert_false(blessings.is_active(), "over")
	assert_false(blessings.can_start(clock.tick), "the world rests")
	assert_false(disasters.can_start(clock.tick), "from a disaster too: the one rest")
	assert_eq(blessings.rest_left(clock.tick), BlessingSystem.REST_MINUTES)
	assert_eq(disasters.rest_left(clock.tick), DisasterSystem.REST_MINUTES)
	_pass(BlessingSystem.REST_MINUTES)
	assert_true(blessings.can_start(clock.tick), "a day later, either")
	assert_true(disasters.can_start(clock.tick))
	assert_false(session.interactions.bless(&"plague", _fire()).applied, "no such blessing")
	# And after a disaster, no blessing until the world has rested.
	assert_true(session.interactions.disaster(DisasterSystem.ECLIPSE, _fire()).applied)
	assert_false(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied, "no blessing while a disaster goes on")
	_pass(int(DisasterSystem.LASTS[DisasterSystem.ECLIPSE]))
	assert_false(blessings.can_start(clock.tick), "the rest after a disaster holds the blessings too")
	_pass(DisasterSystem.REST_MINUTES)
	assert_true(blessings.can_start(clock.tick))


func test_the_lights_come_and_go_and_harm_nobody() -> void:
	var living := session.people.size()
	var trees := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled:
			trees += 1
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	assert_eq(blessings.lights_amount(clock.tick), 0.0, "they come")
	_pass(35)
	assert_near(blessings.lights_amount(clock.tick), 1.0, 0.01, "the sky is full of them")
	assert_true(stimuli.any(func(s: Stimulus) -> bool: return s.type == Stimulus.LIGHTS_IN_SKY and s.anomalous and s.large),
		"noticed, everywhere")
	_pass(40)
	assert_eq(blessings.lights_amount(clock.tick), 0.0, "and go")
	assert_false(blessings.is_active())
	assert_eq(session.people.size(), living)
	var after := 0
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled:
			after += 1
	assert_eq(after, trees)
	assert_eq(session.events.of_type(&"lights_in_sky").size(), 1, "written down")


func test_kept_with_the_world_while_it_lasts() -> void:
	var before := SaveManager.save_world(session, &"test")
	assert_true(before)
	var pristine := SaveManager.last_save_info["bytes"] as int
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	_pass(10)
	assert_true(SaveManager.save_world(session, &"test"))
	assert_true(SaveManager.last_save_info["bytes"] > pristine, "a blessing going on is saved")
	var loaded := SaveManager.load_world(session.world_id)
	assert_true(loaded.ok, loaded.error)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.blessings.kind, BlessingSystem.LIGHTS, "still going on")
	assert_eq(again.blessings.until, blessings.until)
	assert_false(again.disasters.can_start(again.clock.tick), "and the disasters know it")
	again.clock.tick = blessings.until
	again.blessings.advance_to(again.clock.tick)
	assert_false(again.blessings.is_active())
	assert_eq(again.disasters.rest_until, blessings.until + BlessingSystem.REST_MINUTES, "the one rest, kept by the disasters")
	# Once over, the save carries nothing of it.
	assert_true(SaveManager.save_world(again, &"test"))
	var state: Dictionary = again.to_dict()["world_state"]
	assert_false(state.has("blessings"), "nothing to save of a blessing that is over")
	again.queue_free()


func test_it_goes_on_while_away() -> void:
	assert_true(session.interactions.bless(BlessingSystem.LIGHTS, _fire()).applied)
	var until := blessings.until
	# The session's own step brings it up to the clock (as it does while the game runs).
	clock.tick = until + 5
	session.advance_systems()
	assert_false(blessings.is_active(), "over, by the clock")
	assert_eq(disasters.rest_until, until + BlessingSystem.REST_MINUTES)


# --- the land and the water (step 2) ---------------------------------------------------------------

func _bush_near(where: Vector2, within: float, beyond: float = 0.0) -> PropData:
	var best: PropData = null
	for prop in session.props.of_kind(PropData.Kind.BUSH):
		if prop.kind != PropData.Kind.BUSH:
			continue
		var d := prop.position2d().distance_to(where)
		if d <= within and d > beyond and (best == null or d < best.position2d().distance_to(where)):
			best = prop
	return best


func _fertility(tile: Vector2i) -> int:
	var chunk := session.world.chunk_at_tile(tile)
	return int(chunk.fertility[session.world.index_at_tile(tile)]) if chunk != null else 0


func test_the_bounty_fills_the_bushes_and_they_grow_back_faster_for_a_season() -> void:
	var fire := _fire()
	var near := _bush_near(fire, BlessingSystem.REACH)
	var far := _bush_near(fire, 60.0, BlessingSystem.REACH + 2.0)
	assert_not_null(near, "a bush within reach of the fire")
	assert_not_null(far, "and one beyond it")
	var nodes := session.nodes
	var full := nodes.capacity(near)
	assert_eq(nodes.take(near.id, 3, clock.tick), 3, "picked")
	assert_eq(nodes.take(far.id, 3, clock.tick), 3)
	assert_eq(nodes.left(near), full - 3)
	assert_true(session.interactions.bless(BlessingSystem.BOUNTY, fire).applied)
	assert_eq(nodes.left(near), full, "filled as it was made")
	assert_eq(nodes.left(far), nodes.capacity(far) - 3, "beyond reach: as it was")
	assert_eq(session.vegetation.bounty_at(near.tile), VegetationSystem.BOUNTY_REGROW, "grows back faster under the bounty")
	assert_eq(session.vegetation.bounty_at(far.tile), 1.0, "not elsewhere")
	# Twice as fast (a bush grows all its berries back in two days).
	assert_eq(nodes.take(near.id, 3, clock.tick), 3)
	clock.tick += roundi(2.0 * Config.time.MINUTES_PER_DAY / full / VegetationSystem.BOUNTY_REGROW) + 10
	nodes.settle(clock.tick)
	assert_eq(nodes.left(near), full - 2, "a berry back already under the bounty")
	assert_eq(nodes.left(far), nodes.capacity(far) - 3, "none yet beyond it")
	assert_eq(session.events.of_type(&"bounty_of_bushes").size(), 1, "written down")
	# A season later: as before.
	clock.tick += Config.time.days_per_season * Config.time.MINUTES_PER_DAY
	assert_eq(session.vegetation.bounty_at(near.tile), 1.0, "the season over")
	# Kept with the world while it lasts.
	clock.tick -= Config.time.days_per_season * Config.time.MINUTES_PER_DAY
	assert_true(session.vegetation.to_dict().has("bounty"))
	var again := VegetationSystem.new()
	again.from_dict(session.vegetation.to_dict())
	assert_eq(again.to_dict()["bounty"], session.vegetation.to_dict()["bounty"])


func test_rich_soil_lies_on_the_land_within_reach_and_fades() -> void:
	var fire := _fire()
	var middle := WorldCoords.world2d_to_tile(fire)
	var before: Dictionary = {}
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var tile := middle + Vector2i(dx, dy)
			if session.world.is_in_bounds(tile):
				before[tile] = _fertility(tile)
	var far := middle + Vector2i(0, 12)
	assert_true(session.interactions.bless(BlessingSystem.SOIL, fire).applied)
	var risen: Array[Vector2i] = []
	for tile: Vector2i in before:
		if _fertility(tile) > int(before[tile]):
			risen.append(tile)
			assert_true(Vector2(tile - middle).length() <= BlessingSystem.REACH, "%s within reach" % tile)
	assert_true(risen.size() >= 20, "%d tiles richer" % risen.size())
	assert_eq(_fertility(far), before[far], "beyond reach: as it was")
	var one := risen[0]
	assert_true(Farming.fertility_factor(_fertility(one)) > Farming.fertility_factor(before[one]), "heavier at harvest")
	assert_true(session.soil.silted >= risen.size())
	assert_eq(session.events.of_type(&"rich_soil").size(), 1)
	# It fades as silt does: a year on, the land is about as it was.
	session.soil.settle_all(clock.tick)
	for i in 40:
		clock.tick += 4 * Config.time.MINUTES_PER_DAY
		session.soil.settle_all(clock.tick)
	assert_true(_fertility(one) <= int(before[one]) + 4, "faded (%d, was %d)" % [_fertility(one), before[one]])


func test_teeming_waters_fill_the_river_and_bring_a_run() -> void:
	var waters := session.fauna.waters
	var fire := _fire()
	var middle := WorldCoords.world2d_to_tile(fire)
	var cells := waters.cells_near(middle, BlessingSystem.REACH)
	assert_false(cells.is_empty(), "water within reach of the fire")
	var at := FishWaters.middle_of(cells[0][0])
	var holds := waters.capacity_at(at)
	waters.set_stock(at, 1.0)
	assert_true(waters.stock_at(at) < holds, "fished down")
	assert_true(session.interactions.bless(BlessingSystem.WATERS, fire).applied)
	assert_true(waters.stock_at(at) >= holds - 0.01, "filled to what it holds")
	var run := waters.run_cell()
	assert_ne(run, Vector2i.MAX, "a run")
	assert_true(Vector2(FishWaters.middle_of(run) - middle).length() <= BlessingSystem.REACH, "within reach")
	assert_near(waters.stock_at(FishWaters.middle_of(run)), waters.capacity_at(FishWaters.middle_of(run)) * FishWaters.RUN_SHARE, 0.01, "thick with fish")
	assert_eq(session.events.of_type(&"teeming_waters").size(), 1)
	# It lasts its days, as a run does.
	clock.tick += (FishWaters.RUN_DAYS + 1) * Config.time.MINUTES_PER_DAY
	waters.advance_day(clock.tick, RandomNumberGenerator.new())
	assert_eq(waters.run_cell(), Vector2i.MAX, "over after its days")
