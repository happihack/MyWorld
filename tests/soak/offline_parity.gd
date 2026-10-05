extends SceneTree
## M20 check: the same world lived for a while twice — once in real time (as
## the soak does), once away (OfflineSimulator, day-steps) — and the two
## compared: people, births, deaths, food and wood in store, buildings,
## discoveries; and how long the offline run took.
##
##   godot --headless --path . -s res://tests/soak/offline_parity.gd -- --days=24 --seed=12345

const ROOT := "user://offline_parity"


func _initialize() -> void:
	create_timer(3000.0).timeout.connect(func() -> void:
		print("PARITY watchdog")
		quit(2))
	_run()


func _session(seed_value: int) -> Node:
	var s: Node = load("res://scripts/simulation/world_session.gd").new()
	root.add_child(s)
	s.create_new(seed_value)
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	return s


func _numbers(s: Node, label: String, events_before: int) -> Dictionary:
	var people: int = s.people.all_people().size()
	var food := 0.0
	var wood := 0
	var buildings := 0
	for own in s.settlements.all():
		food += own.stockpile.food()
		wood += own.stockpile.amount(&"wood")
	for kind in [PropData.Kind.HUT, PropData.Kind.STOREHOUSE, PropData.Kind.WELL, PropData.Kind.WORKSHOP]:
		buildings += s.construction.standing(kind).size()
	var count := func(type: StringName) -> int: return s.events.count_of(type)
	var out := {"people": people, "settlements": s.settlements.size(), "born": count.call(&"person_born"), "died": count.call(&"person_died"),
		"food": food, "wood": wood, "buildings": buildings, "discoveries": count.call(&"knowledge_learned"),
		"hungry": count.call(&"person_hungry_sick"), "fishers": 0}
	for own in s.settlements.all():
		out["fishers"] += own.fisher_count()
	print("PARITY %-9s people %3d  settlements %d  born %2d  died %2d  hungry-sick %3d  food %6.1f  wood %4d  buildings %2d  discoveries %d" % [
		label, people, out["settlements"], out["born"], out["died"], out["hungry"], food, wood, buildings, out["discoveries"]])
	return out


func _run() -> void:
	await process_frame
	await process_frame
	var days := 24
	var seed_value := 12345
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--days="):
			days = int(argument.get_slice("=", 1))
		elif argument.begins_with("--seed="):
			seed_value = int(argument.get_slice("=", 1))
	var config: Node = root.get_node("Config")
	root.get_node("Settings").call("use_path", ROOT + "/settings.cfg")
	config.save.save_root = ROOT + "/saves"
	DirAccess.make_dir_recursive_absolute(config.save.save_root)
	print("PARITY %d days of seed %d" % [days, seed_value])
	# Away.
	var away := _session(seed_value)
	var began := Time.get_ticks_msec()
	# (Loaded now, not named: a -s script is compiled before the autoloads it would need exist.)
	var simulator: GDScript = load("res://scripts/simulation/offline_simulator.gd")
	var summary: Dictionary = simulator.new(away).run(days * 1440)
	var ms := Time.get_ticks_msec() - began
	_numbers(away, "offline", 0)
	print("PARITY offline took %d ms (%.1f ms a day); told: %s  hook: %s" % [ms, float(ms) / maxf(days, 1), str(summary["counts"]),
		str((summary["hook"] as Dictionary).get("text", "-"))])
	away.queue_free()
	await process_frame
	# Watched.
	var s := _session(seed_value)
	var minute: float = config.time.real_seconds_per_game_minute
	var frame: float = config.time.max_frame_delta_s
	began = Time.get_ticks_msec()
	for day in days:
		for i in 1440:
			var seconds := minute
			while seconds > 0.000001:
				var piece := minf(seconds, frame)
				s.clock.advance(piece)
				seconds -= piece
			s.behavior.step(1.0)
			s.pathfinder.serve(1000000)
			s.movement.step(1.0)
			s.unfold_if_due()
			if i % 10 == 0:
				s.advance_systems()
	_numbers(s, "real-time", 0)
	print("PARITY real-time took %d ms" % (Time.get_ticks_msec() - began))
	quit(0)
