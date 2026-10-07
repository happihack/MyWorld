extends SceneTree
## M21.1 — the scale harness: how the game holds up as worlds grow. A world of
## a given size, a given number of people spread over a given number of
## settlements (optionally lived for years first, the offline way), then the
## running game at a given speed with every part of the frame timed
## (WorldSession.profiling), and the costs that grow with the world: memory,
## the save (size, time), loading, a day lived offline.
##
## Options: --tiles=N (64 … 512)  --people=N  --settlements=N  --seed=N
##          --age_years=N (lived offline first)  --hours=N (game hours timed)
##          --speed=0…3 (default 3)  --tag=name  --watchdog=seconds
##
##   godot --headless --path . -s res://tests/soak/scale_bench.gd -- --tiles=256 --people=500 --settlements=5
##
## Prints one "SCALE" block; the numbers are the PC's (the phone: judge by
## FPS — see the debug overlay's profile line).

const DT := 1.0 / 60.0

var _spawn_us := 0
var _spawns := 0
var _opts := {"tiles": "128", "people": "100", "settlements": "1", "seed": "21", "age_years": "0", "hours": "6",
	"speed": "3", "tag": "scale", "watchdog": "7200"}


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			_opts[argument.substr(2, argument.find("=") - 2)] = argument.get_slice("=", 1)
	create_timer(float(_opts["watchdog"])).timeout.connect(func() -> void:
		print("SCALE watchdog: did not finish")
		quit(2))
	_run()


func _run() -> void:
	await process_frame
	await process_frame
	var config: Node = root.get_node("Config")
	var saves: Node = root.get_node("SaveManager")
	root.get_node("Settings").call("use_path", "user://scale_tmp_%s/settings.cfg" % _opts["tag"])
	config.save.save_root = "user://scale_tmp_%s/saves" % _opts["tag"]
	DirAccess.make_dir_recursive_absolute(config.save.save_root)
	var tiles := int(_opts["tiles"])
	var memory_before := OS.get_static_memory_usage()
	# --- the world ---
	var t := Time.get_ticks_usec()
	var session: Node = load("res://scripts/simulation/world_session.gd").new()
	root.add_child(session)
	session.create_new(int(_opts["seed"]), tiles)
	var made_ms := (Time.get_ticks_usec() - t) / 1000.0
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	t = Time.get_ticks_usec()
	var placed := _populate(session, int(_opts["people"]), int(_opts["settlements"]))
	var populate_ms := (Time.get_ticks_usec() - t) / 1000.0
	print("SCALE world %d² seed %s: made in %.0f ms; %d people in %d settlements (placed in %.0f ms)" % [
		tiles, _opts["seed"], made_ms, session.people.size(), session.settlements.size(), populate_ms])
	print("SCALE an arrival (spawn_person) costs %.1f ms on average" % (_spawn_us / 1000.0 / maxi(_spawns, 1)))
	if placed < int(_opts["people"]):
		print("SCALE note: only %d of %d people could be placed" % [placed, int(_opts["people"])])
	# --- lived for years first (the offline way: a day at a time) ---
	var age_years := int(_opts["age_years"])
	if age_years > 0:
		t = Time.get_ticks_usec()
		var offline = load("res://scripts/simulation/offline_simulator.gd").new(session)
		var year_minutes: int = config.time.ticks_per_year()
		for year in age_years:
			offline.run(year_minutes)
			if year % 10 == 9 or year == age_years - 1:
				print("SCALE aged %d years (%.0f s): %d people, %d settlements, %d events, %d dead" % [year + 1,
					(Time.get_ticks_usec() - t) / 1e6, session.people.size(), session.settlements.size(),
					session.events.size(), session.archive.all_records().size()])
	if age_years > 0:
		var causes := {}
		for record in session.archive.all_records():
			causes[record.cause] = int(causes.get(record.cause, 0)) + 1
		var types := {}
		for event in session.events.all_events():
			types[event.type] = int(types.get(event.type, 0)) + 1
		var top: Array = types.keys()
		top.sort_custom(func(x, y) -> bool: return types[x] > types[y])
		var listing := PackedStringArray()
		for kind in top.slice(0, 16):
			listing.append("%s %d" % [kind, types[kind]])
		print("SCALE deaths by cause: ", causes)
		print("SCALE events: ", ", ".join(listing))
	# --- a day lived offline: what it costs now ---
	var offline_probe = load("res://scripts/simulation/offline_simulator.gd").new(session)
	t = Time.get_ticks_usec()
	offline_probe.run(2 * 1440)
	var offline_day_ms := (Time.get_ticks_usec() - t) / 2000.0
	# --- the running game, every part timed ---
	session.clock.set_speed(int(_opts["speed"]))
	session.profiling = true
	session.profile.clear()
	session.is_active = true
	var frame_us := PackedInt32Array()
	var loose_us := 0
	var water_us := 0
	var start_tick: int = session.clock.tick
	var hours := float(_opts["hours"])
	var wall := Time.get_ticks_usec()
	var guard := 0
	while session.clock.tick - start_tick < hours * 60.0 and guard < 2_000_000:
		guard += 1
		var f := Time.get_ticks_usec()
		session._process(DT)
		var w := Time.get_ticks_usec()
		session.water._process(DT)
		var l := Time.get_ticks_usec()
		session.loose_system.step(DT)
		var e := Time.get_ticks_usec()
		water_us += l - w
		loose_us += e - l
		frame_us.append(e - f)
		if e - f > 200000:
			var heavy := PackedStringArray()
			for part in session.profile:
				var entry: Array = session.profile[part]
				if entry.size() > 3 and int(entry[3]) > 20000:
					heavy.append("%s %.0f" % [part, int(entry[3]) / 1000.0])
			print("SCALE slow frame %.0f ms at %s: %s (water %.0f, loose %.0f)" % [(e - f) / 1000.0,
				session.clock.format_date(), ", ".join(heavy), (l - w) / 1000.0, (e - l) / 1000.0])
	if frame_us.is_empty():
		frame_us.append(0) # (nothing timed: --hours=0)
	var wall_s := (Time.get_ticks_usec() - wall) / 1e6
	var game_hours: float = (session.clock.tick - start_tick) / 60.0
	var sorted := frame_us.duplicate()
	sorted.sort()
	var total := 0
	for v in frame_us:
		total += v
	var n := maxi(frame_us.size(), 1)
	print("SCALE running: %.1f game hours in %d frames (%.1f s): sim %.1f ms a game hour; frame mean %.2f ms, p95 %.2f, p99 %.2f, max %.1f; frames over 16 ms: %d" % [
		game_hours, frame_us.size(), wall_s, total / 1000.0 / maxf(game_hours, 0.01), total / 1000.0 / n,
		sorted[int(n * 0.95)] / 1000.0 if n > 1 else 0.0, sorted[int(n * 0.99)] / 1000.0 if n > 1 else 0.0,
		sorted[-1] / 1000.0 if n > 0 else 0.0, _count_over(frame_us, 16000)])
	var sim: Object = session.simulation
	print("SCALE people: deferred turns %d (of %d lived)" % [sim.deferred_total, sim.get("lived_total") if sim.get("lived_total") != null else -1])
	var parts: Array = session.profile.keys()
	parts.sort_custom(func(a, b) -> bool: return float(session.profile[a][0]) > float(session.profile[b][0]))
	var lines := PackedStringArray()
	for name in parts.slice(0, 12):
		var entry: Array = session.profile[name]
		lines.append("%s %.3f/%.1f" % [name, float(entry[0]) / 1000.0, maxi(int(entry[1]), int(entry[2])) / 1000.0])
	lines.append("water %.3f" % (water_us / 1000.0 / n))
	lines.append("loose %.3f" % (loose_us / 1000.0 / n))
	print("SCALE parts (avg/worst ms a frame): ", "  ".join(lines))
	# --- memory, the save, loading ---
	var memory_mb := (OS.get_static_memory_usage() - memory_before) / 1048576.0
	t = Time.get_ticks_usec()
	var saved: bool = saves.save_world(session, &"manual")
	var save_ms := (Time.get_ticks_usec() - t) / 1000.0
	var path: String = config.save.save_root.path_join(String(session.world_id)).path_join("world.sav")
	var size := FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
	t = Time.get_ticks_usec()
	var loaded = saves.load_world(session.world_id)
	var load_ms := (Time.get_ticks_usec() - t) / 1000.0
	var again: Node = load("res://scripts/simulation/world_session.gd").new()
	root.add_child(again)
	t = Time.get_ticks_usec()
	var rebuilt: bool = loaded.ok and again.load_from(loaded.world)
	var rebuild_ms := (Time.get_ticks_usec() - t) / 1000.0
	print("SCALE memory +%.0f MB; save %s %.0f KB in %.0f ms; read %.0f ms, world rebuilt %s in %.0f ms; a day lived offline %.0f ms" % [
		memory_mb, "ok" if saved else "FAILED", size / 1024.0, save_ms, load_ms, "ok" if rebuilt else "FAILED", rebuild_ms,
		offline_day_ms])
	print("SCALE done %s" % _opts["tag"])
	quit(0)


## Spreads `count` people over `settlements` settlements: the first is the
## world's own; the others are founded where a migrating band would settle,
## as far from each other as the land allows. Returns how many were placed.
func _populate(session: Node, count: int, settlements: int) -> int:
	var homes: Array = [session.settlement]
	var taken: Array[Vector2i] = [session.start.settlement_tile]
	var migration: Object = session.migration
	for i in settlements - 1:
		# (Candidates on a coarse grid, the farthest from every other fire
		# first; the first a band would settle at is taken — scoring every
		# third tile of a 512 world took minutes a settlement.)
		var candidates: Array = []
		var bounds: Rect2i = session.world.bounds
		for y in range(bounds.position.y + 8, bounds.end.y - 8, 16):
			for x in range(bounds.position.x + 8, bounds.end.x - 8, 16):
				var tile := Vector2i(x, y)
				var apart := INF
				for other in taken:
					apart = minf(apart, Vector2(tile - other).length())
				if apart >= 14.0:
					candidates.append([apart, tile])
		candidates.sort_custom(func(a, b) -> bool: return a[0] > b[0])
		var best: Variant = null
		var tries := 0
		for entry in candidates:
			tries += 1
			if tries > 60:
				break
			for dy in range(-4, 5, 2):
				for dx in range(-4, 5, 2):
					var tile: Vector2i = entry[1] + Vector2i(dx, dy)
					if best == null and migration.site_score(tile, session.settlement) != null:
						best = tile
			if best != null:
				break
		if best == null:
			break
		var leader: PersonData = session.spawn_person(best)
		if leader == null:
			break
		var journey := {"members": [leader.id], "leader": leader.id, "to": best, "goods": {"wood": 20, "berries": 30},
			"households": [], "from": session.settlement.id, "started": session.clock.tick}
		migration.journeys.append(journey)
		var own: Object = migration.found(journey, session.clock.tick)
		if own == null:
			continue
		homes.append(own)
		taken.append(best)
	var placed: int = session.people.size()
	var i := 0
	while placed < count and i < count * 4:
		var own: Object = homes[i % homes.size()]
		i += 1
		var fire: Variant = own.fire()
		if fire == null:
			continue
		var stage := PersonData.LifeStage.ADULT if i % 4 != 0 else PersonData.LifeStage.CHILD
		var spawn_t := Time.get_ticks_usec()
		var person: PersonData = session.spawn_person(fire.tile + Vector2i(i % 9 - 4, (i / 9) % 9 - 4), stage)
		_spawn_us += Time.get_ticks_usec() - spawn_t
		_spawns += 1
		if person == null:
			continue
		person.settlement_id = own.id
		placed += 1
	session.households.ensure_records(session.clock.tick)
	return session.people.size()


static func _count_over(values: PackedInt32Array, limit: int) -> int:
	var c := 0
	for v in values:
		if v > limit:
			c += 1
	return c
