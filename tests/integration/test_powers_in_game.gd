extends TestCase
## The rain, wind and water tools in the main scene, driven by real touch
## events (M9.5): what a finger does with each, what is seen and heard, the
## tool bar as powers show themselves, and the trail of the observing eye.

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig
var router: InputRouter
var tools: ToolManager
var fx: ToolFx
var pulses: Array = []
var _real_vibrate: Callable


func before_each() -> void:
	AudioManager.ensure_sounds()
	_real_vibrate = Haptics.vibrate_action
	pulses.clear()
	Haptics.vibrate_action = func(ms: int, _amplitude: float) -> void: pulses.append(ms)
	Haptics.reset()
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	router = main.get_node("InputRouter")
	tools = main.get_node("Tools")
	rig = view.camera_rig()
	rig.set_process(false)
	fx = view.tool_fx()
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.behavior.enabled = false
	session.clock.set_speed(0)
	session.hydrology.enabled = false
	session.weather.hold(&"clear", session.clock.tick + 1_000_000)


func after_each() -> void:
	Haptics.vibrate_action = _real_vibrate
	AudioManager.set_made_rain(0.0)
	if get_tree().current_scene != null:
		get_tree().unload_current_scene()
	await wait_frames(2)


func _look_at(xz: Vector2, distance: float = 14.0) -> void:
	rig.focus_on(Vector3(xz.x, 0, xz.y), distance, false)
	for i in 120:
		rig.advance(1.0 / 60.0)


func _ground_screen(xz: Vector2) -> Vector2:
	var tile := WorldCoords.world2d_to_tile(xz)
	return rig.world_to_screen(Vector3(xz.x, session.world.get_height(tile) * session.world.height_step, xz.y))


func _touch(pos: Vector2, pressed: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = pos
	t.pressed = pressed
	get_tree().root.push_input(t, true)


func _move(from: Vector2, to: Vector2, steps: int = 8) -> void:
	for i in range(1, steps + 1):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from.lerp(to, i / float(steps))
		d.relative = (to - from) / steps
		get_tree().root.push_input(d, true)


## Open grass on the valley floor near the settlement with nothing standing
## within two tiles of it (and no water within `dry` tiles).
func _open_ground(dry: int = 2) -> Vector2i:
	var world := session.world
	var home := session.start.settlement_tile
	for ring in range(4, 16):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var tile := home + Vector2i(dx, dy)
				if not world.is_in_bounds(tile) or world.get_height(tile) != world.get_height(home):
					continue
				var fine := true
				for y in range(-dry, dry + 1):
					for x in range(-dry, dry + 1):
						var near := tile + Vector2i(x, y)
						if not world.is_in_bounds(near) or world.get_water(near) > 0.0:
							fine = false
						elif absi(x) <= 2 and absi(y) <= 2 and (world.get_terrain(near) != ChunkData.Terrain.GRASS
								or session.props.has_prop_at(near) or world.get_height(near) != world.get_height(home)):
							fine = false
				if fine:
					return tile
	return Vector2i(-999, -999)


func _middle(tile: Vector2i) -> Vector2:
	return Vector2(tile) + Vector2(0.5, 0.5)


func _moisture(tile: Vector2i) -> int:
	return session.world.chunk_at_tile(tile).moisture[session.world.index_at_tile(tile)]


func test_the_tool_bar_grows_with_the_players_powers() -> void:
	var bar := ui.tool_bar()
	# What a player has at first: the hand and the eye. (A debug build has everything.)
	assert_true(tools.show_all, "this is a debug build")
	tools.show_all = false
	tools.refresh()
	assert_eq(bar.tool_ids(), [HandTool.ID, ObserveTool.ID, CallTool.ID])
	assert_false(tools.has_tool(RainTool.ID))
	assert_true(tools.select(ObserveTool.ID))
	# It rains for the first time: the rain tool is there, glowing, and the player is told.
	NotificationManager.clear()
	session.weather.hold(&"rain", session.clock.tick + 1_000_000)
	assert_true(session.powers.is_known(ToolReveals.RAIN))
	assert_eq(bar.tool_ids(), [HandTool.ID, ObserveTool.ID, RainTool.ID, CallTool.ID])
	var button := bar.button(RainTool.ID)
	assert_not_null(button)
	assert_true(button.is_glowing())
	assert_false(bar.button(HandTool.ID).is_glowing())
	assert_eq(button.tooltip_text, "Rain")
	assert_eq(tools.current_id(), ObserveTool.ID, "the tool in hand stays in hand")
	assert_true(bar.button(ObserveTool.ID).selected)
	await wait_frames(3)
	assert_true(ui.toasts().texts().has(UIText.tool_revealed(ToolReveals.RAIN)), str(ui.toasts().texts()))
	assert_true(pulses.size() >= 1)
	await wait_frames(1)
	assert_near(bar.get_global_rect().get_center().x, get_tree().root.get_visible_rect().size.x * 0.5, 1.0, "still centred")
	# The glow goes.
	button.glow(0.05)
	await wait_real_ms(150)
	assert_false(button.is_glowing())
	# A storm: wind. The water touched: water. In the bar's order.
	session.weather.hold(&"storm", session.clock.tick + 1_000_000)
	session.powers.reveal(ToolReveals.WATER, session.clock.tick)
	assert_eq(bar.tool_ids(), [HandTool.ID, ObserveTool.ID, RainTool.ID, WindTool.ID, WaterTool.ID, CallTool.ID])
	assert_true(bar.button(WaterTool.ID).is_glowing())
	for id: StringName in [RainTool.ID, WindTool.ID, WaterTool.ID]:
		assert_true(tools.select(id))
		assert_true(bar.button(id).selected)
		assert_true(router.is_over_ui(bar.button(id).get_global_rect().get_center()))
	# The water tool's button shows how full the bucket is.
	session.water.carried = WaterTool.BUCKET * 0.5
	await wait_frames(2)
	assert_near(bar.button(WaterTool.ID).fill, 0.5, 0.001)
	assert_true(bar.button(RainTool.ID).fill < 0.0)


func test_a_resting_finger_makes_rain() -> void:
	assert_true(tools.select(RainTool.ID))
	var rain := tools.current() as RainTool
	var tile := _open_ground(4)
	assert_true(session.world.is_in_bounds(tile))
	_look_at(_middle(tile))
	var at := _ground_screen(_middle(tile))
	var pivot := rig.pivot()
	var before := _moisture(tile)
	var stimuli: Array = []
	session.interactions.stimulus_emitted.connect(func(s: Stimulus) -> void: stimuli.append(s.type))
	# A finger rests on the land: a cloud forms over it, and it rains.
	_touch(at, true)
	assert_false(rain.is_raining(), "not at once")
	await wait_real_ms(Config.interaction.grab_hold_ms + 150)
	assert_true(rain.is_raining())
	assert_true(tools.is_busy())
	assert_true(rain.cloud_at().distance_to(_middle(tile)) < 0.6, str(rain.cloud_at()))
	assert_true(fx.is_raining() and fx.cloud_node().visible and fx.rain_node().visible)
	assert_true(fx.cloud_position().y > session.world.get_height(tile) * session.world.height_step + 2.0, "it hangs over the land")
	assert_eq(stimuli, [Stimulus.RAIN_FROM_CLEAR_SKY])
	assert_eq(pulses.size(), 1)
	# It goes on raining for as long as the finger stays: the soil under the cloud gets wet.
	await wait_real_ms(1400)
	assert_true(rain.fallen() > 0.5, "%.2f units" % rain.fallen())
	assert_true(_moisture(tile) > before + 3, "%d -> %d" % [before, _moisture(tile)])
	assert_near(fx.formed(), 1.0, 0.001)
	assert_true(float(fx.rain_material().get_shader_parameter(&"amount")) > 0.4)
	assert_near((fx.rain_material().get_shader_parameter(&"area_center") as Vector2).distance_to(rain.cloud_at()), 0.0, 0.01)
	assert_true(AudioManager.rain_ambience_player().playing, "it is heard")
	assert_eq(ui.panel_count(), 0, "no menu opens under a raining finger")
	assert_eq(session.history.total(), 0, "not history until it ends")
	# The finger moves: the cloud follows, and the view stays.
	var along := _middle(tile) + Vector2(2.0, 0.0)
	_move(at, _ground_screen(along))
	await wait_real_ms(600)
	assert_true(rain.cloud_at().distance_to(along) < 0.6, str(rain.cloud_at()))
	assert_eq(rig.pivot(), pivot)
	# It lifts: the rain stops, the cloud goes, and it is one act of the player's.
	_touch(_ground_screen(along), false)
	assert_false(rain.is_raining())
	assert_false(fx.is_raining())
	assert_eq(session.history.count(Intervention.MAKE_RAIN), 1)
	assert_near(session.history.total_of(&"rain_made"), rain.fallen(), 0.0001)
	await wait_real_ms(700)
	assert_false(fx.cloud_node().visible)
	assert_false(AudioManager.rain_ambience_player().playing)
	assert_false(rig.is_flinging())
	# A quick drag is still a look around; a tap is nothing.
	_touch(at, true)
	_move(at, at + Vector2(260, 0))
	_touch(at + Vector2(260, 0), false)
	assert_false(rain.is_raining())
	assert_true(rig.pivot().distance_to(pivot) > 0.5, "the view moved")
	assert_eq(session.history.count(Intervention.MAKE_RAIN), 1)
	# Choosing another tool while it rains ends the rain.
	_look_at(_middle(tile))
	_touch(_ground_screen(_middle(tile)), true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 400)
	assert_true(rain.is_raining())
	tools.select(HandTool.ID)
	assert_false(rain.is_raining())
	_touch(_ground_screen(_middle(tile)), false)


func test_a_swipe_is_a_gust() -> void:
	assert_true(tools.select(WindTool.ID))
	var wind := tools.current() as WindTool
	var tile := _open_ground()
	_look_at(_middle(tile))
	var from := _middle(tile) + Vector2(-3.0, 0.0)
	var to := _middle(tile) + Vector2(1.0, 0.0)
	var pebble := session.interactions._spawn(LooseObject.Kind.PEBBLE, _middle(tile) + Vector2(0.5, 0.3), 0.0, 100)
	pebble.state = LooseObject.State.RESTING
	session.loose.touch(pebble.id)
	var was := pebble.position
	var pivot := rig.pivot()
	var sky := view.weather_fx()
	sky.set_process(false)
	var calm := sky.blowing().length()
	# A quick swipe across the land.
	_touch(_ground_screen(from), true)
	_move(_ground_screen(from), _ground_screen(to), 4)
	_touch(_ground_screen(to), false)
	var gust := wind.last_gust
	assert_not_null(gust)
	assert_true(gust.applied)
	assert_true((gust.params["direction"] as Vector2).dot(Vector2.RIGHT) > 0.95, str(gust.params["direction"]))
	assert_true(gust.magnitude >= Config.tools.wind_least and gust.magnitude <= 1.0)
	assert_eq(session.history.count(Intervention.MAKE_WIND), 1)
	assert_eq(rig.pivot(), pivot, "with the wind tool a swipe does not move the view")
	assert_false(rig.is_flinging())
	# It is seen, heard and felt: dust along its way, the trees bend, a rush of air, a pulse.
	assert_eq(fx.gusts, 1)
	assert_true(view.effects().burst_count(WorldEffects.Burst.DUST) >= 1)
	sky.advance(0.4)
	assert_true(sky.blowing().length() > calm + 0.2, "%.2f against %.2f" % [sky.blowing().length(), calm])
	assert_eq(AudioManager.last_sound, &"gust")
	assert_true(pulses.size() >= 1)
	# The pebble in its way is blown along.
	session.clock.set_speed(1)
	await wait_real_ms(900)
	assert_true(pebble.position.x > was.x + 0.3, "%s -> %s" % [was, pebble.position])
	# The gust dies away.
	sky.advance(Config.tools.wind_gust_seconds + 0.1)
	assert_near(sky.blowing().length(), sky.wind.length(), 0.001)
	# A touch that hardly moves is no gust.
	wind.last_gust = null
	var here := _ground_screen(_middle(tile))
	_touch(here, true)
	_move(here, here + Vector2(30, 0), 2)
	_touch(here + Vector2(30, 0), false)
	assert_true(wind.last_gust == null or not wind.last_gust.applied)
	assert_eq(session.history.count(Intervention.MAKE_WIND), 1)


func test_a_held_finger_drawn_across_the_land_carves_a_channel() -> void:
	assert_true(tools.select(WaterTool.ID))
	var water := tools.current() as WaterTool
	var tile := _open_ground()
	_look_at(_middle(tile), 11.0)
	var world := session.world
	var height := world.get_height(tile)
	var from := _ground_screen(_middle(tile))
	var to := _ground_screen(_middle(tile + Vector2i(2, 0)))
	var pivot := rig.pivot()
	# Rest the finger, then draw it across three tiles.
	_touch(from, true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 150)
	assert_eq(world.get_height(tile), height, "resting alone carves nothing")
	_move(from, to, 12)
	assert_true(water.is_busy())
	assert_eq(water.carved(), 3)
	for n in 3:
		assert_eq(world.get_height(tile + Vector2i(n, 0)), height - 1, "tile %d" % n)
		assert_eq(world.get_terrain(tile + Vector2i(n, 0)), ChunkData.Terrain.DIRT)
	assert_eq(world.get_height(tile + Vector2i(3, 0)), height)
	assert_eq(rig.pivot(), pivot, "the view does not pan while carving")
	assert_eq(session.history.total(), 0)
	assert_true(view.effects().burst_count(WorldEffects.Burst.DUST) >= 3, "earth flies")
	_touch(to, false)
	assert_false(water.is_busy())
	assert_eq(session.history.count(Intervention.CARVE, &"ground"), 1)
	assert_near(session.history.total_of(&"tiles_carved"), 3.0, 0.0001)
	# The ground is drawn anew (changed ground is redrawn by itself).
	var chunk := world.chunk_at_tile(tile)
	assert_true(chunk.is_dirty(ChunkData.DIRTY_MESH))
	await wait_frames(3)
	assert_false(chunk.is_dirty(ChunkData.DIRTY_MESH), "the chunk was rebuilt")
	# A rested finger that lifts without moving is still a tap (it pours, it does not dig).
	session.water.carried = 1.0
	var spot := _ground_screen(_middle(tile + Vector2i(0, 2)))
	_touch(spot, true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 120)
	_touch(spot, false)
	await wait_real_ms(Config.interaction.double_tap_ms + 80)
	assert_eq(world.get_height(tile + Vector2i(0, 2)), height)
	assert_true(session.water.carried < 1.0, "it poured")
	assert_eq(session.history.count(Intervention.CARVE), 1)
	# A quick drag is still a look around.
	_touch(from, true)
	_move(from, from + Vector2(260, 0))
	_touch(from + Vector2(260, 0), false)
	assert_true(rig.pivot().distance_to(pivot) > 0.5)
	assert_eq(session.history.count(Intervention.CARVE), 1)


func test_a_finger_drawn_through_water_leaves_ripples() -> void:
	assert_true(tools.select(WaterTool.ID))
	var bed := session.hydrology.bed()
	var tile := bed[bed.size() / 2]
	_look_at(_middle(tile), 11.0)
	var world := session.world
	var surface := Vector3(tile.x + 0.5, world.get_height(tile) * world.height_step + world.get_water(tile), tile.y + 0.5)
	var from := rig.world_to_screen(surface)
	var to := rig.world_to_screen(surface + Vector3(0.0, 0.0, 3.0))
	var volume := session.water.total_volume()
	_touch(from, true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 150)
	_move(from, to, 12)
	assert_true(view.effects().active_ring_count() >= 2, "%d rings" % view.effects().active_ring_count())
	_touch(to, false)
	assert_near(session.water.total_volume(), volume, 0.0001, "nothing was scooped, nothing dug")
	assert_eq(session.history.total(), 0)


func test_the_observing_eye_leaves_a_trail_of_tiles() -> void:
	assert_true(tools.select(ObserveTool.ID))
	var eye := tools.current() as ObserveTool
	var tile := _open_ground()
	_look_at(_middle(tile), 11.0)
	var from := _ground_screen(_middle(tile))
	var to := _ground_screen(_middle(tile + Vector2i(3, 0)))
	var pivot := rig.pivot()
	_touch(from, true)
	await wait_real_ms(Config.interaction.grab_hold_ms + 150)
	_move(from, to, 16)
	await wait_frames(2)
	assert_true(eye.trail_tiles >= 3, "%d tiles" % eye.trail_tiles)
	var card := ui.top_panel() as InspectCard
	assert_not_null(card)
	assert_eq(ui.panel_count(), 1, "one card, telling of one tile after the other")
	assert_eq(card.subtitle_text(), "tile %d, %d" % [tile.x + 3, tile.y])
	assert_true(card.rows().has("Moisture"))
	assert_eq(rig.pivot(), pivot, "the view stays while the eye wanders")
	assert_true(view.effects().active_ring_count() >= 1)
	_touch(to, false)
	assert_false(eye.is_busy())
	assert_eq(session.history.total(), 0, "looking is not touching")
	assert_eq(ui.panel_count(), 1, "the card stays")
	# A quick drag is still a look around.
	_touch(from, true)
	_move(from, from + Vector2(260, 0))
	_touch(from + Vector2(260, 0), false)
	assert_true(rig.pivot().distance_to(pivot) > 0.5)


func test_ground_the_river_takes_is_drawn_anew() -> void:
	# (The bank erosion of M9.3 changed the ground and nothing redrew it.)
	var river := session.hydrology
	river.enabled = true
	Config.hydrology.erosion_chance = 1.0
	var taken: Array = []
	river.eroded.connect(func(tile: Vector2i) -> void: taken.append(tile))
	river.level = 0.3
	river.step(session.clock.tick, 0.0)
	Config.hydrology.erosion_chance = 0.25
	assert_eq(taken.size(), 1)
	var chunk := session.world.chunk_at_tile(taken[0])
	await wait_frames(3)
	assert_false(chunk.is_dirty(ChunkData.DIRTY_MESH))
	assert_false(chunk.is_dirty(ChunkData.DIRTY_WATER))
