extends SceneTree
## The M7 soak (implementation plan, "M7 — Tests & checks"): game years of
## an untouched default world, headless, as fast as it goes — the people
## stay alive, nobody gets stuck, and the world's books stay in order.
##
##   godot --headless --path . -s res://tests/soak/soak_m7.gd -- [--years=10] [--seed=12345] [--quiet] [--watchdog=seconds]
##
## Since M10.2 people are born and die: the soak checks that the band neither
## dies out nor outgrows its roofs, and reports births, deaths, partners and
## generations (the M10 soak is 100 years: --years=100).
##
## Prints a line a season and a summary; exits 0 if every check held, 1 if
## not (2: it did not finish). Saves go to user://soak_tmp (removed after).
##
## (A -s script is compiled before the autoloads exist: everything of the
## game is loaded and reached at run time.)

const WATCHDOG_SECONDS := 1500.0
const ROOT_BASE := "user://soak_tmp"
## (--tag=name: a folder of its own, for two soaks at once.)
var ROOT := ROOT_BASE
## Someone who has not turned to anything new for this many game days is stuck.
const STUCK_DAYS := 2

var _problems: PackedStringArray = []


func _initialize() -> void:
	var watchdog := WATCHDOG_SECONDS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--watchdog="):
			watchdog = maxf(float(argument.get_slice("=", 1)), 60.0)
		elif argument.begins_with("--years="):
			watchdog = maxf(watchdog, float(argument.get_slice("=", 1)) * 40.0)
	create_timer(watchdog).timeout.connect(func() -> void:
		print("SOAK did not finish in %d s" % int(watchdog))
		quit(2))
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var years := 10
	var seed_value := 12345
	var quiet := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--years="):
			years = maxi(int(argument.get_slice("=", 1)), 1)
		elif argument.begins_with("--seed="):
			seed_value = int(argument.get_slice("=", 1))
		elif argument == "--quiet":
			quiet = true
		elif argument.begins_with("--tag="):
			ROOT = ROOT_BASE + "_" + argument.get_slice("=", 1).validate_filename()
	var config: Node = root.get_node("Config")
	var saves: Node = root.get_node("SaveManager")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--knob="):
			var spec := argument.get_slice("=", 1).split(".")
			var value: Variant = str_to_var(argument.get_slice("=", 2))
			(config.get(spec[0]) as Resource).set(spec[1], value)
			print("SOAK knob %s.%s = %s" % [spec[0], spec[1], value])
	root.get_node("Settings").call("use_path", ROOT + "/settings.cfg")
	config.save.save_root = ROOT + "/saves"
	DirAccess.make_dir_recursive_absolute(config.save.save_root)
	var session_script: GDScript = load("res://scripts/simulation/world_session.gd")
	var s: Node = session_script.new()
	root.add_child(s)
	s.create_new(seed_value)
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	var people_at_start: int = s.people.all_people().size()
	var days_per_year: int = config.time.days_per_year()
	var days_per_season: int = config.time.days_per_season
	var minute: float = config.time.real_seconds_per_game_minute
	var frame: float = config.time.max_frame_delta_s
	# When each person last turned to something new.
	var changed: Dictionary = {}
	for person in s.people.all_people():
		changed[person.id] = 0
	var watch := func() -> void:
		s.behavior.activity_changed.connect(func(person_id: int, _activity: StringName) -> void:
			changed[person_id] = s.clock.tick)
	watch.call()
	# (The box unfolds: the world is opened again — its behaviour too. Watched anew, everyone fresh.)
	s.unfolded.connect(func(_old: Rect2i, _new: Rect2i) -> void:
		watch.call()
		for person in s.people.all_people():
			changed[person.id] = s.clock.tick)
	var hungriest := 1.0
	var fewest: int = people_at_start
	var most: int = people_at_start
	var room_for: int = s.households.homes().size() * config.life.home_room
	var least_food_days := INF
	var worst_health := 1.0
	# How long the stores have been low at a stretch (game minutes), and the longest that ever was.
	var low_below: float = config.settlement.shortage_below_days
	var low_for := 0
	var longest_low := 0
	var low_stretches := 0
	var start_tick: int = s.clock.tick
	var fisher_doing := {} # (what the fishers are at, hour by hour: "activity / step" -> hours)
	# Food brought in, by kind (into piles: the stores), and the people in each trade, day by day.
	var brought := {}
	s.piles.stored.connect(func(resource: StringName, amount: int, _pile: int) -> void:
		brought[resource] = int(brought.get(resource, 0)) + amount)
	var trade_days := {}
	var started := Time.get_ticks_msec()
	print("SOAK %d years (%d days) of seed %d: %d people" % [years, years * days_per_year, seed_value, people_at_start])
	for day in years * days_per_year:
		for i in 1440:
			# (The clock takes at most a frame's worth at a time.)
			var seconds := minute
			while seconds > 0.000001:
				var piece := minf(seconds, frame)
				s.clock.advance(piece)
				seconds -= piece
			s.behavior.step(1.0)
			s.pathfinder.serve(1000000)
			s.movement.step(1.0)
			s.unfold_if_due() # (M13.2: the box may unfold)
			if s.nodes.due(s.clock.tick):
				s.nodes.settle(s.clock.tick)
			if i % 60 == 0:
				s.stats.advance_to(s.clock.tick)
				s.knowledge.advance_to(s.clock.tick)
				s.learning.advance_to(s.clock.tick) # (M16: what people know, and what they work out)
				s.technology.advance_to(s.clock.tick)
				s.cultures.advance_to(s.clock.tick) # (M17: traditions, festivals)
				s.faith.advance_to(s.clock.tick)
				s.lexicon.advance_to(s.clock.tick)
				s.anomaly_archive.advance_to(s.clock.tick) # (M18)
				s.science.advance_to(s.clock.tick)
				s.mysteries.advance_to(s.clock.tick)
				s.conflicts.advance_to(s.clock.tick) # (M19)
				s.stories.advance_to(s.clock.tick)
			if i % 10 == 0:
				s.soil.advance_to(s.clock.tick)
				s.boats.advance_to(s.clock.tick) # (FB2: built, worn, mended, torn loose)
				s.fauna.advance_to(s.clock.tick) # (the herds, the fish — and the big predators, PR1)
				s.predators.advance_to(s.clock.tick) # (PR2–PR3: seen, feared, attacks)
				s.parties.advance_to(s.clock.tick) # (PR4: the hunting parties)
				for fisher in s.people.all_people():
					if fisher.occupation_id == &"fisher":
						var steps: Variant = fisher.current_action.get("steps")
						var index := int(fisher.current_action.get("index", 0))
						var step_type := str(steps[index].get("type", "")) if typeof(steps) == TYPE_ARRAY and index < (steps as Array).size() else ""
						var doing := "%s / %s" % [fisher.current_action.get("activity", "-"), step_type]
						if step_type == "boat":
							doing += " " + str(steps[index].get("phase", "?"))
						elif step_type == "walk_to" and index + 1 < (steps as Array).size():
							doing += " (then %s)" % str(steps[index + 1].get("type", ""))
						fisher_doing[doing] = int(fisher_doing.get(doing, 0)) + 1
				var food_days: float = s.settlement.days_of_food()
				least_food_days = minf(least_food_days, food_days)
				if food_days < low_below:
					if low_for == 0:
						low_stretches += 1
					low_for += 10
					longest_low = maxi(longest_low, low_for)
				else:
					low_for = 0
		for worker in s.people.all_people():
			if worker.life_stage(s.clock.tick, config.time.ticks_per_year(), config.people) == PersonData.LifeStage.ADULT:
				trade_days[worker.occupation_id] = int(trade_days.get(worker.occupation_id, 0)) + 1
		# The day's checks.
		var now: int = s.clock.tick
		if day == 0 and absi(now - start_tick - 1440) > 2:
			_problem("a day of the soak was %d game minutes" % (now - start_tick))
		var alive: int = s.people.all_people().size()
		room_for = s.households.homes().size() * config.life.home_room # (homes are built, M12.1)
		fewest = mini(fewest, alive)
		most = maxi(most, alive)
		if alive == 0:
			_problem("day %d: everyone has died" % day)
			break
		if alive > room_for * 2:
			_problem("day %d: %d people (roofs for %d)" % [day, alive, room_for])
		for person in s.people.all_people():
			if not changed.has(person.id):
				changed[person.id] = now # (born since)
			for need: float in person.needs:
				if not is_finite(need) or need < -0.0001 or need > 1.0001:
					_problem("day %d: %s has a need of %s" % [day, person.given_name, need])
			if not is_finite(person.health) or person.health < 0.0 or person.health > 1.0001:
				_problem("day %d: %s has a health of %s" % [day, person.given_name, person.health])
			hungriest = minf(hungriest, person.needs[0])
			worst_health = minf(worst_health, person.health)
			if now - int(changed.get(person.id, 0)) > STUCK_DAYS * 1440:
				_problem("day %d: %s has been at '%s' for %d days" % [day, person.given_name,
					person.current_action.get("activity", ""), (now - int(changed[person.id])) / 1440])
				changed[person.id] = now # (said once)
			if not s.pathfinder.can_stand(person.position) and not person.has_flag(1 << 4) and person.aboard == 0: # (in a boat: FB3)
				var there: Variant = s.props.prop_at(person.position)
				_problem("day %d: %s (#%d, age %d) stands where nobody can stand (%s: %s, water %.2f) at '%s'" % [day,
					person.given_name, person.id, person.age_years(now, config.time.ticks_per_year()), person.position,
					"prop kind %d #%d" % [there.kind, there.id] if there != null else "no prop", s.world.get_water(person.position),
					person.current_action.get("activity", "")])
		# Everyone belongs to a settlement there is, and lives under its roofs (or none yet).
		for person in s.people.all_people():
			var own: Variant = s.settlements.get_settlement(person.settlement_id)
			if own == null:
				_problem("day %d: %s belongs to no settlement (%d)" % [day, person.given_name, person.settlement_id])
			elif person.home_building_id != 0 and not own.start_info().hut_ids.has(person.home_building_id) \
					and not s.migration.travelling(person.id) and s.props.get_prop(person.home_building_id) != null:
				_problem("day %d: %s of %s lives in another settlement's hut" % [day, person.given_name, own.display_name()])
		for resource: StringName in s.settlement.stockpile.amounts():
			if int(s.settlement.stockpile.amounts()[resource]) < 0:
				_problem("day %d: %d %s in store" % [day, s.settlement.stockpile.amounts()[resource], resource])
		for species: StringName in [&"deer", &"rabbit", &"fox"]:
			if s.animals.count(species) <= 0:
				_problem("day %d: no %s left" % [day, species])
		if s.events.size() > config.events.max_events:
			_problem("day %d: the event log holds %d events (%d at most)" % [day, s.events.size(), config.events.max_events])
		if (day + 1) % days_per_year == 0:
			print("SOAK tech year %d  %s  |  %s" % [day / days_per_year + 1, s.technology.debug_text(), s.learning.debug_text()])
		if (day + 1) % days_per_season == 0 and not quiet:
			print("SOAK year %d season %d  people %d  food %.1f days  store: %s  fire %s  events %d  shortage %d  sick %d  hungriest so far %.2f" % [
				day / days_per_year + 1, (day % days_per_year) / days_per_season, alive, s.settlement.days_of_food(),
				s.settlement.stockpile.debug_text(), "lit" if s.settlement.fire_lit() else "OUT", s.events.size(),
				s.events.count_of(&"food_shortage"), s.events.count_of(&"person_hungry_sick"), hungriest])
	var elapsed := Time.get_ticks_msec() - started
	# The books at the end.
	for event in s.events.all_events():
		for cause in event.causes:
			if cause >= event.id:
				_problem("event %d names a later event (%d) as its cause" % [event.id, cause])
	if s.behavior.rescues > 0:
		_problem("%d people had to be moved off ground nobody can stand on" % s.behavior.rescues)
	for person in s.people.all_people():
		for condition: Variant in person.conditions:
			if typeof(condition) == TYPE_DICTIONARY and bool(condition.get("sick", false)) and not bool(condition.get("fed", false)):
				_problem("%s is weak with hunger at the end" % person.given_name)
	# It can be saved and opened again.
	if not saves.save_world(s, &"soak"):
		_problem("the world could not be saved")
	else:
		var loaded: RefCounted = saves.load_world(s.world_id)
		var again: Node = session_script.new()
		root.add_child(again)
		if not loaded.ok or not again.load_from(loaded.world):
			_problem("the saved world could not be opened")
		elif again.people.all_people().size() != s.people.all_people().size() or again.events.size() != s.events.size() \
				or again.archive.size() != s.archive.size():
			_problem("the saved world came back different (%d people, %d events)" % [again.people.all_people().size(), again.events.size()])
		again.queue_free()
	var minutes := years * days_per_year * 1440
	print("SOAK events by kind:")
	var kinds := {}
	for event in s.events.all_events():
		kinds[event.type] = int(kinds.get(event.type, 0)) + event.count
	var names: Array = kinds.keys()
	names.sort()
	for kind: StringName in names:
		print("SOAK   %-22s %d" % [kind, kinds[kind]])
	print("SOAK animals: deer %d  rabbits %d  foxes %d   memories %d   save %d bytes" % [s.animals.count(&"deer"),
		s.animals.count(&"rabbit"), s.animals.count(&"fox"), s.memories.size(), saves.last_save_info.get("bytes", 0)])
	print("SOAK %s" % s.stats.debug_text())
	# Fishing and boats (M19.5).
	var fishers := 0
	var stored_fish := 0
	var boats := PackedStringArray()
	for own in s.settlements.all():
		fishers += own.fisher_count()
		stored_fish += own.stockpile.amount(&"fish")
		for boat in ["raft", "canoe", "nets", "plank_boat", "sail"]:
			if own.knows_how(StringName(boat)) and not boats.has(boat):
				boats.append(boat)
	print("SOAK fishing: %d fishers, %d fish in the stores, %.0f of %.0f in the water, %d landings, knows %s" % [fishers, stored_fish,
		s.fauna.fish, s.fauna.fish_capacity, s.construction.standing(PropData.Kind.LANDING).size(), ", ".join(boats) if not boats.is_empty() else "no boats"])
	# The boats (FB2–FB4): how many, what kinds, how used, how many lost.
	var boat_kinds := {}
	var trips := 0
	var caught := 0
	for boat in s.boats.all_boats():
		boat_kinds[boat.kind] = int(boat_kinds.get(boat.kind, 0)) + 1
		trips += boat.trips
		caught += boat.caught
	# Fish caught (from the waters' own count), year by year, and what the fishers did with their hours.
	var by_year := PackedStringArray()
	for year in range(1, years + 2):
		var in_year := 0
		for own in s.settlements.all():
			in_year += s.fauna.waters.caught(own.id, year)
		by_year.append(str(in_year))
	print("SOAK fish caught by year: %s" % ", ".join(by_year))
	var food_parts := PackedStringArray()
	for resource: StringName in brought:
		var def: ResourceDef = s.resources.get_def(resource)
		if def != null and def.nutrition > 0.0:
			food_parts.append("%s %d (%.0f food)" % [resource, brought[resource], brought[resource] * def.nutrition])
	print("SOAK food brought in: %s" % ", ".join(food_parts))
	var trade_parts := PackedStringArray()
	for trade: StringName in trade_days:
		trade_parts.append("%s %d" % [trade, trade_days[trade]])
	print("SOAK adult worker-days by trade: %s" % ", ".join(trade_parts))
	var farm_parts := PackedStringArray()
	for own in s.settlements.all():
		if own.farming != null:
			own.farming.use_start(own.start_info()) # (one record for all: pointed at each in turn, as the game does)
			farm_parts.append("%s: %d people, %d farmers (wanted %d), %d plots, %d harvests" % [own.display_name(), own.member_count(),
				own.farming.farmer_count(), own.farmers_wanted(), own.farming.plot_count(), own.farming.harvest_count()])
	print("SOAK farming: %s" % "; ".join(farm_parts))
	var fishers_now := 0
	for person in s.people.all_people():
		if person.occupation_id == &"fisher":
			fishers_now += 1
	print("SOAK fishers now %d in %d settlements" % [fishers_now, s.settlements.all().size()])
	var doings: Array = fisher_doing.keys()
	doings.sort_custom(func(x: String, y: String) -> bool: return int(fisher_doing[x]) > int(fisher_doing[y]))
	var top := PackedStringArray()
	for doing: String in doings.slice(0, 12):
		top.append("%s %d h" % [doing, fisher_doing[doing]])
	print("SOAK fishers' hours: %s" % "; ".join(top))
	print("SOAK boats: launched for nothing %d (no water to go to %d, no way %d)" % [s.boats.idle_trips, s.boats.no_water, s.boats.no_way])
	print("SOAK boats: %d %s  trips %d  caught offline %d  built %d  carried off %d  fell apart %d  swamped %d" % [s.boats.size(), str(boat_kinds),
		trips, caught, s.events.count_of(&"boat_built"), s.events.count_of(&"boat_carried_off"),
		s.events.count_of(&"boat_fell_apart"), s.events.count_of(&"boat_swamped")])
	print("SOAK least food in store %.2f days (below %.1f days %d times, for %d minutes at the longest)  hungriest anyone was %.2f  worst health %.2f" % [
		least_food_days, low_below, low_stretches, longest_low, hungriest, worst_health])
	print("SOAK looked up %d  decisions %d" % [s.behavior.skipped + s.behavior.decisions, s.behavior.decisions])
	print("SOAK %s  |  %s" % [s.soil.debug_text(), s.vegetation.debug_text()])
	print("SOAK %s" % s.relationships.debug_text())
	# Lives: how many, how many generations, how old people got.
	var generation := {}
	var deepest := 0
	var everyone: Array = []
	for record in s.archive.all_records():
		everyone.append([record.id, record.parents])
	for person in s.people.all_people():
		everyone.append([person.id, person.parents])
	everyone.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in everyone:
		var depth := 1
		for parent: int in entry[1]:
			depth = maxi(depth, int(generation.get(parent, 1)) + 1)
		generation[entry[0]] = depth
		deepest = maxi(deepest, depth)
	var ages := PackedStringArray()
	var year_ticks: int = config.time.ticks_per_year()
	for record in s.archive.all_records():
		ages.append("%d%s" % [record.age_years(year_ticks), String(record.cause).substr(0, 1)])
	print("SOAK lives: %d people now (%d at the start, %d … %d), %d have died, %d generations  %s" % [
		s.people.all_people().size(), people_at_start, fewest, most, s.archive.size(), deepest, s.lifecycle.counts])
	print("SOAK ages at death: %s" % " ".join(ages))
	var graves: int = s.graves.laid_count()
	var visits := 0
	for person in s.people.all_people():
		if person.activity_log.has("visit_grave"):
			visits += 1
	print("SOAK graves: %d of %d dead laid in %d cemeteries, %d of the living have been to one" % [graves, s.archive.size(),
		s.graves.cemeteries().size(), visits])
	print("SOAK %s" % s.culture.debug_text())
	print("SOAK buildings: huts %d  storehouses %d  woodsheds %d  wells %d  ruins %d  begun %d  built %d  damaged %d  repaired %d  ruined %d  |  %s" % [
		s.construction.standing(PropData.Kind.HUT).size(), s.construction.standing(PropData.Kind.STOREHOUSE).size(),
		s.construction.standing(PropData.Kind.WOODSHED).size(), s.construction.standing(PropData.Kind.WELL).size(), s.construction.standing(PropData.Kind.RUIN).size(),
		s.events.count_of(&"building_begun"), s.events.count_of(&"building_built"), s.events.count_of(&"building_damaged"),
		s.events.count_of(&"building_repaired"), s.events.count_of(&"building_ruined"), s.construction.debug_text()])
	print("SOAK %s  bridges %d" % [s.traffic.debug_text(), s.construction.standing(PropData.Kind.BRIDGE).size()])
	print("SOAK %s  |  %s" % [s.settlements.debug_text(), s.migration.debug_text()])
	var specialties := PackedStringArray()
	for own in s.settlements.all():
		specialties.append("%s: known for %s, knows %s, tools %d (made %d)" % [own.display_name(), own.specialty(), own.knows.keys(),
			own.stockpile.amount(&"tools"), own.tools_made])
	print("SOAK %s  |  %s" % [s.trade.debug_text(), "; ".join(specialties)])
	print("SOAK %s" % s.governance.debug_text())
	print("SOAK %s" % s.learning.debug_text())
	print("SOAK %s" % s.technology.debug_text())
	print("SOAK %s" % s.cultures.debug_text())
	print("SOAK %s" % s.faith.debug_text())
	print("SOAK %s" % s.lexicon.debug_text())
	print("SOAK %s  |  %s  |  %s" % [s.anomaly_archive.debug_text(), s.science.debug_text(), s.mysteries.debug_text()])
	print("SOAK %s  |  %s" % [s.conflicts.debug_text(), s.stories.debug_text()])
	for story: Dictionary in s.stories.stories:
		print("SOAK   story (%d events, score %.1f): %s" % [(story["events"] as Array).size(), float(story["score"]), s.stories.line(story)])
	for e in s.events.of_type(&"knowledge_learned") + s.events.of_type(&"knowledge_spread") + s.events.of_type(&"era_entered") + s.events.of_type(&"knowledge_lost") + s.events.of_type(&"tradition_formed") + s.events.of_type(&"tradition_faded") + s.events.of_type(&"renamed") + s.events.of_type(&"faith_founded") + s.events.of_type(&"schism") + s.events.of_type(&"myth_spread") + s.events.of_type(&"mystery_clue") + s.events.of_type(&"hypothesis") + s.events.of_type(&"box_research"):
		print("SOAK   year %d  %s %s (%s)" % [config.time.year_of(e.tick), e.type, str(e.text_params.get("kind", "")), str(e.text_params.get("place", ""))])
	print("SOAK box: %d x %d tiles, unfolded %d times; regions found %d of %d, the edge %s" % [s.world.bounds.size.x, s.world.bounds.size.y,
		s.unfolder.count, s.knowledge.discovered.size(), s.knowledge.regions.regions.size(), "reached" if s.knowledge.edge_reached else "not reached"])
	for myth: Dictionary in s.culture.myths():
		print("SOAK   myth %s: %s/%s %s, %d believers, formed day %d" % [myth["id"], myth["subject"], myth["agent"], myth["sentiment"],
			int(myth["believers"]), int(myth["formed"]) / 1440])
	var stories := 0
	for person in s.people.all_people():
		for memory in s.memories.of(person):
			if memory.text_key == "MEM_STORY":
				stories += 1
	print("SOAK the living hold %d bedtime stories" % stories)
	var important := PackedStringArray()
	for id: int in s.significance.important_people():
		important.append("%s %.1f" % [s.people.name_of(id), s.significance.points_of(id)])
	print("SOAK important people %d: %s   firsts %d" % [important.size(), ", ".join(important), s.significance.firsts().size()])
	if graves < s.archive.size():
		_problem("%d of %d dead have no grave" % [s.archive.size() - graves, s.archive.size()])
	if years >= 100 and deepest < 4:
		_problem("only %d generations in %d years" % [deepest, years])
	var pairs := PackedStringArray()
	for person in s.people.all_people():
		var known: Dictionary = s.relationships.of(person.id)
		for other_id: int in known:
			if other_id > person.id:
				var record: Relationship = known[other_id]
				pairs.append("%d-%d %+.2f%s" % [person.id, other_id, record.affinity,
					"F" if record.has_kind(Relationship.Kind.FRIEND) else ("R" if record.has_kind(Relationship.Kind.RIVAL) else "")])
	print("SOAK pairs: %s" % " ".join(pairs))
	print("SOAK %s  (stepped back out of rising water %d times)" % [s.hydrology.debug_text().replace("
", "  "), s.behavior.waded_out])
	print("SOAK %d game minutes in %.1f s (%.3f ms a minute)" % [minutes, elapsed / 1000.0, float(elapsed) / minutes])
	s.queue_free()
	await process_frame
	_remove_dir(ROOT)
	if _problems.is_empty():
		print("SOAK PASSED")
		quit(0)
	else:
		print("SOAK FAILED: %d problems" % _problems.size())
		for problem in _problems.slice(0, 40):
			print("SOAK   " + problem)
		quit(1)


func _problem(message: String) -> void:
	_problems.append(message)


## Removes a directory under user:// with everything in it (and nothing else).
func _remove_dir(path: String) -> void:
	if not path.begins_with("user://soak_tmp"):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)
