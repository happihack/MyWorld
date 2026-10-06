extends SceneTree
## Profiles the game loop: what each part of a frame costs, to find the
## bottlenecks (the owner, 2026-10-06).
##
## Two modes:
##   --mode=sim   (headless) the simulation alone, every system timed apart:
##                the clock and people's turns, the paths, walking, each
##                system brought up to the clock, the water, loose objects.
##   --mode=game  (in a window) the running game: every node's _process
##                timed apart (the view, the HUD, the effects …), and the
##                frame's render time, draw calls, objects.
##
## Options: --frames=N (default 1800: 30 s at 60 fps)  --speed=0…3 (default 3,
## the fastest)  --seed=N  --extra_people=N  --save_root=PATH --world=ID (an
## existing world, e.g. a phone backup)  --tag=name  --warm=N (frames run
## first and not counted; default 120).
##
##   godot --headless --path . -s res://tests/soak/profile_loop.gd -- --mode=sim --speed=3
##   godot --resolution 540x960 --path . -s res://tests/soak/profile_loop.gd -- --mode=game --speed=3
##
## (Times are the PC's; on the phone everything costs several times more —
## judge the share of each, and the frame against 16.7 ms.)

const DT := 1.0 / 60.0

var _opts := {"mode": "sim", "frames": "1800", "speed": "3", "seed": "12345", "extra_people": "0", "save_root": "",
	"world": "", "tag": "profile", "warm": "120"}
var _samples: Dictionary = {} # name -> PackedInt32Array of µs per frame
var _last_frame := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			_opts[argument.substr(2, argument.find("=") - 2)] = argument.get_slice("=", 1)
	create_timer(3600.0).timeout.connect(func() -> void:
		print("PROFILE did not finish")
		quit(2))
	_run()


func _wait(frames: int) -> void:
	for i in frames:
		await process_frame


func _note(name: String, usec: int) -> void:
	# (A packed array is a value: taken out, added to, put back.)
	var values: PackedInt32Array = _samples.get(name, PackedInt32Array())
	values.append(usec)
	_samples[name] = values


func _run() -> void:
	await process_frame
	await process_frame
	var config: Node = root.get_node("Config")
	var settings: Node = root.get_node("Settings")
	settings.call("use_path", "user://shot_tmp_%s/settings.cfg" % _opts["tag"])
	settings.call("set_value", &"accessibility/reduced_motion", true)
	if String(_opts["save_root"]) != "":
		config.save.save_root = String(_opts["save_root"])
	elif String(_opts["mode"]) == "game":
		config.save.save_root = "user://shot_tmp_%s/saves" % _opts["tag"]
		DirAccess.make_dir_recursive_absolute(config.save.save_root)
	if String(_opts["mode"]) == "game":
		await _profile_game(config)
	else:
		await _profile_sim(config)
	quit(0)


# --- the simulation alone ---------------------------------------------------------------------------

func _profile_sim(config: Node) -> void:
	var session: Node = load("res://scripts/simulation/world_session.gd").new()
	root.add_child(session)
	if String(_opts["world"]) != "":
		var loaded = root.get_node("SaveManager").call("load_world", String(_opts["world"]))
		if not loaded.ok or not session.load_from(loaded.world):
			print("PROFILE could not open world ", _opts["world"], ": ", loaded.error)
			return
	else:
		session.create_new(int(_opts["seed"]))
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	_add_people(session)
	session.clock.set_speed(int(_opts["speed"]))
	var systems: Array = []
	for name in ["knowledge", "learning", "technology", "cultures", "faith", "lexicon", "anomaly_archive", "science",
			"mysteries", "conflicts", "stories", "weather", "disasters", "soil", "relationships:settle", "lifecycle", "culture",
			"construction", "traffic", "migration", "trade", "governance", "fauna", "stats"]:
		var parts: PackedStringArray = name.split(":")
		systems.append([parts[0], session.get(parts[0]), parts[1] if parts.size() > 1 else "advance_to"])
	var started_tick: int = session.clock.tick
	var deferred := 0
	var warm := int(_opts["warm"])
	var frames := int(_opts["frames"])
	for frame in warm + frames:
		var counting := frame >= warm
		var whole := Time.get_ticks_usec()
		var t := Time.get_ticks_usec()
		session.simulation.advance(DT)
		var sim_usec := Time.get_ticks_usec() - t
		if counting:
			_note("people: turns (think, plan, act)", session.simulation.last_live_usec)
			_note("people: paths found", session.simulation.last_paths_usec)
			_note("people: walking", session.simulation.last_move_usec)
			_note("clock + scheduling (rest of the sim step)", maxi(sim_usec - session.simulation.last_live_usec
				- session.simulation.last_paths_usec - session.simulation.last_move_usec, 0))
			deferred += session.simulation.last_deferred
		var tick: int = session.clock.tick
		for system: Array in systems:
			t = Time.get_ticks_usec()
			(system[1] as Object).call(system[2], tick)
			if counting:
				_note("system: " + String(system[0]), Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		if session.nodes.due(tick):
			session.nodes.settle(tick)
		if counting:
			_note("system: resource nodes (regrowth)", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		session.settlements.step(tick)
		if counting:
			_note("system: settlements (stores, jobs, planner)", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		session.call("_look_for_powers")
		if counting:
			_note("system: powers (look for)", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		session.water._process(DT)
		if counting:
			_note("water (flowing)", Time.get_ticks_usec() - t)
		t = Time.get_ticks_usec()
		session.loose_system.step(DT)
		if counting:
			_note("loose objects (falling, rolling)", Time.get_ticks_usec() - t)
			_note("FRAME (all of the above)", Time.get_ticks_usec() - whole)
	var days := float(session.clock.tick - started_tick) / 1440.0
	print("PROFILE sim  world=%s  people=%d  props=%d  loose=%d  settlements=%d  speed=%s  frames=%d  game days=%.1f  people deferred (out of AI time) %d" % [
		_opts["world"] if String(_opts["world"]) != "" else "new %s" % _opts["seed"], session.people.size(), session.props.size(),
		session.loose.size(), session.settlements.all().size(), _opts["speed"], frames, days, deferred])
	_report(frames)
	session.queue_free()
	await _wait(2)


func _add_people(session: Node) -> void:
	var extra := int(_opts["extra_people"])
	if extra <= 0:
		return
	var fire: Vector2i = session.start.settlement_tile
	for i in extra:
		session.spawn_person(fire + Vector2i(i % 7 - 3, i / 7 % 7 - 3))


# --- the running game --------------------------------------------------------------------------------

func _profile_game(config: Node) -> void:
	change_scene_to_file("res://scenes/main/main.tscn")
	await _wait(240)
	var main: Node = current_scene
	var session: Node = main.get_node("WorldSession")
	var ui: Node = main.get_node("UIRoot")
	ui.hints().set_process(false)
	for child in ui.get_children():
		if child.has_method("dismiss"):
			pass
	ui.close_all_panels()
	_add_people(session)
	session.clock.set_speed(int(_opts["speed"]))
	var viewport_rid: RID = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
	# Every node that runs each frame is run by us instead, timed.
	var timed: Array = []
	var warm := int(_opts["warm"])
	var frames := int(_opts["frames"])
	for frame in warm + frames:
		var counting := frame >= warm
		_take_over(root, timed)
		var whole := Time.get_ticks_usec()
		for i in range(timed.size() - 1, -1, -1):
			if not is_instance_valid(timed[i]):
				timed.remove_at(i) # (freed: a panel closed)
		for entry in timed:
			var node := entry as Node
			if not node.is_inside_tree():
				continue
			var t := Time.get_ticks_usec()
			node.call("_process", root.get_process_delta_time())
			if counting:
				_note(_label(node), Time.get_ticks_usec() - t)
		if counting:
			_note("SCRIPTS (all _process above)", Time.get_ticks_usec() - whole)
		var before := Time.get_ticks_usec()
		await process_frame
		if counting:
			_note("frame interval (real, whole frame)", Time.get_ticks_usec() - _last_frame if _last_frame > 0 else 0)
			_note("engine: physics time (Performance)", int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0))
			_note("nodes in the tree", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			_note("waiting for the next frame (not ours)", Time.get_ticks_usec() - before)
		_last_frame = Time.get_ticks_usec()
		if counting:
			_note("render: CPU (whole frame)", int(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) * 1000.0))
			_note("render: GPU (whole frame)", int(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid) * 1000.0))
			_note("engine: process time (Performance)", int(Performance.get_monitor(Performance.TIME_PROCESS) * 1_000_000.0))
			_note("draw calls", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			_note("objects drawn", int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	print("PROFILE game  people=%d  props=%d  loose=%d  speed=%s  frames=%d  fps(engine)=%.0f  nodes timed=%d" % [
		session.people.size(), session.props.size(), session.loose.size(), _opts["speed"], frames,
		Performance.get_monitor(Performance.TIME_FPS), timed.size()])
	_report(frames)


## Turns off the frame processing of every scripted node that processes (it
## is called by us, timed, instead); new ones are found every frame.
func _take_over(node: Node, timed: Array) -> void:
	if node.get_script() != null and node.is_processing() and node.has_method("_process"):
		node.set_process(false)
		if not timed.has(node):
			timed.append(node)
	for child in node.get_children():
		_take_over(child, timed)


func _label(node: Node) -> String:
	var script: Script = node.get_script()
	var cls := script.get_global_name() if script != null else &""
	return "%s (%s)" % [String(cls) if cls != &"" else node.get_class(), node.name]


# --- the table -------------------------------------------------------------------------------------

func _report(frames: int) -> void:
	var rows: Array = []
	for name: String in _samples:
		var values: PackedInt32Array = _samples[name]
		var sorted := values.duplicate()
		sorted.sort()
		var total := 0
		for v in values:
			total += v
		rows.append([name, total / maxf(values.size(), 1.0), sorted[int(sorted.size() * 0.95)] if sorted.size() > 0 else 0,
			sorted[-1] if sorted.size() > 0 else 0, total])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[4]) > float(b[4]))
	print("PROFILE %-58s %10s %10s %10s" % ["(µs per frame; counts for draw calls / objects)", "mean", "p95", "max"])
	for row: Array in rows:
		print("PROFILE %-58s %10.1f %10d %10d" % [row[0], row[1], row[2], row[3]])
