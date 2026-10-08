extends SceneTree
## A tool (not a test): grows a world for some years, as the soak lives it,
## and saves it into a save folder of its own — never the player's — for the
## screenshot tool (capture_shots.gd) to open.
## Run: --headless -s res://tests/tools/grow_world.gd -- --seed=4242 --years=30 --dir=C:/tmp/wiab_shots


func _init() -> void:
	var seed_value := 4242
	var years := 30
	var dir := "C:/tmp/wiab_shots"
	var like_soak := OS.get_cmdline_user_args().has("--like-soak")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--years="):
			years = int(arg.get_slice("=", 1))
		elif arg.begins_with("--dir="):
			dir = arg.get_slice("=", 1)
	await process_frame
	var config: Variant = root.get_node("Config")
	DirAccess.make_dir_recursive_absolute(dir.path_join("saves"))
	config.save.save_root = dir.path_join("saves")
	root.get_node("Settings").use_path(dir.path_join("settings.cfg"))
	var Session: Variant = load("res://scripts/simulation/world_session.gd")
	var s: Variant = Session.new()
	root.add_child(s)
	s.create_new(seed_value)
	s.set_process(false)
	s.loose_system.set_process(false)
	s.water.set_process(false)
	var minute: float = config.time.real_seconds_per_game_minute
	var frame: float = config.time.max_frame_delta_s
	var days: int = years * config.time.days_per_year()
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
			if like_soak:
				# (Only what the soak steps — to compare: soak_m7.gd.)
				if s.nodes.due(s.clock.tick):
					s.nodes.settle(s.clock.tick)
				if i % 60 == 0:
					for name in ["stats", "knowledge", "learning", "technology", "cultures", "faith", "lexicon", "anomaly_archive", "science", "mysteries", "conflicts", "stories"]:
						s.get(name).advance_to(s.clock.tick)
				if i % 10 == 0:
					for name in ["soil", "boats", "fauna", "predators", "parties", "assemblies", "raids", "wars"]:
						s.get(name).advance_to(s.clock.tick)
			else:
				s.advance_systems()
		if day % config.time.days_per_year() == 0:
			print("GROW year %d: %d people, %d settlements, food %.1f days  %s" % [day / config.time.days_per_year(), s.people.size(), s.settlements.size(),
				s.settlement.days_of_food() if s.settlement != null else 0.0, str(s.lifecycle.counts)])
	var kept: bool = root.get_node("SaveManager").save_world(s, &"grown")
	print("GROW saved %s: %s (%d people)" % [s.world_id, kept, s.people.size()])
	quit()
