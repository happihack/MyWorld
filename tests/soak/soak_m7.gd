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
	s.behavior.activity_changed.connect(func(person_id: int, _activity: StringName) -> void:
		changed[person_id] = s.clock.tick)
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
			if s.nodes.due(s.clock.tick):
				s.nodes.settle(s.clock.tick)
			if i % 60 == 0:
				s.stats.advance_to(s.clock.tick)
			if i % 10 == 0:
				s.soil.advance_to(s.clock.tick)
				var food_days: float = s.settlement.days_of_food()
				least_food_days = minf(least_food_days, food_days)
				if food_days < low_below:
					if low_for == 0:
						low_stretches += 1
					low_for += 10
					longest_low = maxi(longest_low, low_for)
				else:
					low_for = 0
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
			if not s.pathfinder.can_stand(person.position) and not person.has_flag(1 << 4):
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
	var graves: int = s.graves.all_graves().size()
	var visits := 0
	for person in s.people.all_people():
		if person.activity_log.has("visit_grave"):
			visits += 1
	print("SOAK graves %d (of %d dead), %d of the living have been to one" % [graves, s.archive.size(), visits])
	print("SOAK %s" % s.culture.debug_text())
	print("SOAK buildings: huts %d  storehouses %d  wells %d  ruins %d  begun %d  built %d  damaged %d  repaired %d  ruined %d  |  %s" % [
		s.construction.standing(PropData.Kind.HUT).size(), s.construction.standing(PropData.Kind.STOREHOUSE).size(),
		s.construction.standing(PropData.Kind.WELL).size(), s.construction.standing(PropData.Kind.RUIN).size(),
		s.events.count_of(&"building_begun"), s.events.count_of(&"building_built"), s.events.count_of(&"building_damaged"),
		s.events.count_of(&"building_repaired"), s.events.count_of(&"building_ruined"), s.construction.debug_text()])
	print("SOAK %s  bridges %d" % [s.traffic.debug_text(), s.construction.standing(PropData.Kind.BRIDGE).size()])
	print("SOAK %s  |  %s" % [s.settlements.debug_text(), s.migration.debug_text()])
	var specialties := PackedStringArray()
	for own in s.settlements.all():
		specialties.append("%s: known for %s, knows %s, tools %d (made %d)" % [own.display_name(), own.specialty(), own.knows.keys(),
			own.stockpile.amount(&"tools"), own.tools_made])
	print("SOAK %s  |  %s" % [s.trade.debug_text(), "; ".join(specialties)])
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
