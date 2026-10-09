extends SceneTree
## A tool (not a test): opens a world grown by grow_world.gd in the game,
## in a window, and saves screenshots of it — the whole box, the settlement,
## people up close, dusk, snow, a storm, and the phone screens (a person's
## card, the menu, the history). Never the player's saves or settings.
## Run (not headless): -s res://tests/tools/capture_shots.gd -- --dir=C:/tmp/wiab_shots
##   --out=C:/.../website/images --size=1920x1080 --set=scenes   (or --set=phone --size=1080x2340)

var _dir := "C:/tmp/wiab_shots"
var _out := ""
var _size := Vector2i(1920, 1080)
var _set := "scenes"
var main: Node
var session: Node
var rig: Node
var ui: CanvasLayer


func _init() -> void:
	_out = ProjectSettings.globalize_path("res://website/images")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="):
			_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--set="):
			_set = arg.get_slice("=", 1)
		elif arg.begins_with("--size="):
			var wh := arg.get_slice("=", 1).split("x")
			_size = Vector2i(int(wh[0]), int(wh[1]))
	await process_frame
	DirAccess.make_dir_recursive_absolute(_out)
	var config: Variant = root.get_node("Config")
	config.save.save_root = _dir.path_join("saves")
	config.interaction.first_opening = false
	root.get_node("Settings").use_path(_dir.path_join("settings.cfg"))
	DisplayServer.window_set_size(_size)
	root.size = _size
	await _frames(5)
	if _set == "menus":
		await _menus()
		quit()
		return
	change_scene_to_file("res://scenes/main/main.tscn")
	await _frames(20)
	main = current_scene
	session = main.get_node("WorldSession")
	rig = main.get_node("WorldView").camera_rig()
	ui = main.get_node("UIRoot")
	# (The time away lived, the opening begun; whatever it put up, closed.)
	for i in 600:
		if main.opening_begun():
			break
		await process_frame
	# (And the glide down that follows the opening, over: the camera is ours.)
	await _frames(420)
	ui.close_all_panels()
	ui.toasts().visible = false # (no old notices over the pictures)
	session.weather.hold(&"clear", session.clock.tick + 24 * 60)
	_at_hour(10.5)
	await _frames(240) # (the rain that was falling, gone)
	print("SHOTS window %s, viewport %s, %d people" % [DisplayServer.window_get_size(), root.get_viewport().get_visible_rect().size, session.people.size()])
	if _set == "scenes":
		await _scenes()
	else:
		await _phone()
	print("SHOTS done")
	quit()


func _scenes() -> void:
	ui.visible = false
	var fire := _fire()
	# The whole box on its table.
	rig.frame_box(false)
	await _shot("box", 90)
	# The settlement, from the side.
	rig.yaw = 35.0
	rig.focus_on(fire, 26.0, false)
	await _shot("settlement")
	rig.focus_on(fire + Vector3(4, 0, 3), 15.0, false)
	await _shot("village")
	# People at their work, up close.
	var someone: Variant = _busy_person()
	if someone != null:
		rig.focus_on(main.get_node("WorldView").people_view().ground_position(someone), 8.0, false)
		await _shot("people")
	# Dusk: the fire, people gathered round it.
	_at_hour(19.6)
	rig.focus_on(fire, 12.0, false)
	await _shot("dusk", 90)
	# Winter: snow on the ground and falling.
	_at_hour(11.0)
	session.weather.hold(&"snow", session.clock.tick + 12 * 60)
	session.weather.snow_cover = 0.95
	rig.yaw = -20.0
	rig.focus_on(fire, 22.0, false)
	await _shot("winter", 120)
	# A storm over the box.
	session.weather.snow_cover = 0.0
	session.weather.hold(&"storm", session.clock.tick + 12 * 60)
	rig.yaw = 10.0
	rig.focus_on(fire, 40.0, false)
	await _shot("storm", 120)


func _phone() -> void:
	var fire := _fire()
	ui.visible = true
	rig.yaw = 25.0
	rig.focus_on(fire, 20.0, false)
	await _shot("phone_world")
	var someone: Variant = _busy_person()
	if someone != null:
		main.select_person(someone.id, 1) # (the card full)
		await _shot("phone_person")
		main.clear_selection()
		ui.close_all_panels()
	var menu: Node = ui.open_menu()
	await _shot("phone_menu", 30)
	menu.open_section("MENU_HISTORY")
	await _shot("phone_menu_history")
	menu.open_section("MENU_PEOPLE")
	await _shot("phone_menu_people")
	menu.open_section("MENU_CIVILIZATION")
	await _shot("phone_menu_civilization")
	var pages: Variant = load("res://scripts/ui/menu/menu_pages.gd")
	for page: Array in [[pages.STORIES, "phone_stories"], [pages.POPULATION, "phone_population"], [pages.TECHNOLOGY, "phone_technology"],
			[&"important", "phone_important"]]:
		ui.close_all_panels()
		menu = ui.open_menu()
		menu.open_page(page[0])
		await _shot(page[1])
	ui.close_all_panels()
	ui.open_history(session)
	await _shot("phone_history")
	ui.close_all_panels()
	ui.open_map()
	await _shot("phone_map")
	ui.close_all_panels()


## The splash screen and the main menu (with this world saved: Continue).
func _menus() -> void:
	change_scene_to_file("res://scenes/main/splash.tscn")
	await _frames(5)
	current_scene.next_action = func() -> void: pass
	await _shot("menu_splash", 70)
	change_scene_to_file("res://scenes/main/title.tscn")
	await _frames(5)
	await _shot("menu_title", 20)
	current_scene.show_page(&"new")
	await _shot("menu_title_new", 10)
	current_scene.show_page(&"root")
	current_scene.choose(current_scene.choices()[0]) # (Continue: the covering screen)
	await _shot("menu_opening", 12)


func _fire() -> Vector3:
	var tile: Vector2i = session.settlement.fire().tile if session.settlement != null and session.settlement.fire() != null \
		else session.start.settlement_tile
	return Vector3(tile.x + 0.5, session.world.get_height(tile) * session.world.height_step, tile.y + 0.5)


## Someone grown, out of doors, at work or on their way, nearest the fire.
func _busy_person() -> Variant:
	var best: Variant = null
	var best_d := INF
	var fire := _fire()
	for person in session.people.all_people():
		if person.has_flag(person.FLAG_INDOORS):
			continue
		var config: Variant = root.get_node("Config")
		if person.life_stage(session.clock.tick, config.time.ticks_per_year(), config.people) != 2: # (grown)
			continue
		var d := Vector2(person.position).distance_to(Vector2(fire.x, fire.z))
		if d > 3.0 and d < best_d:
			best = person
			best_d = d
	return best


## The clock on to `hour` of the day (today, or tomorrow if it is past).
func _at_hour(hour: float) -> void:
	var config: Variant = root.get_node("Config")
	var now: int = session.clock.tick
	var minute: int = config.time.minute_of_day(now)
	var ahead := posmod(roundi(hour * 60.0) - minute, 1440)
	session.clock.tick = now + ahead


func _shot(name: String, settle: int = 60) -> void:
	await _frames(settle)
	var image := root.get_viewport().get_texture().get_image()
	var path := _out.path_join(name + ".png")
	image.save_png(path)
	print("SHOTS %s %s" % [path, image.get_size()])


func _frames(n: int) -> void:
	for i in n:
		await process_frame
