class_name WorldView
extends Node3D
## Everything visible of the world (bible §31.3): the box frame, chunk views
## (terrain, water, props), ambient life and lighting. Entities and weather
## effects join in later milestones. Views only read world state; they never
## own or change it. The CameraRig is the player's view into the box.

## Headroom between the highest possible terrain and the top of the box.
const BOX_HEADROOM := 2.6

var _world: WorldData
var _props: PropRegistry
var _prop_library: PropMeshLibrary
var _prop_material: ShaderMaterial
var _props_dirty: Dictionary = {} # chunk coord -> true
var _ambient: AmbientLife
var _chunks: Node3D
var _chunk_views: Dictionary = {} # Vector2i -> ChunkView (only those in sight: M13.1)
## Which chunks have views: what the camera sees, built on worker threads.
var _streamer := ChunkStreamer.new()
var _has_fire := false
var _animals_view: AnimalsView
var _terrain_material: ShaderMaterial
var _frame: BoxFrame
var _lighting: WorldLighting
var _day_night: DayNight
var _weather_fx: WeatherFx
var _tool_fx: ToolFx
## The ground has changed somewhere (a channel carved, a bank taken): the
## chunks it touches are drawn anew in the next frame.
var _ground_dirty := false
var _people: PersonRegistry
## The settlement's huts (prop ids), for whose lights are out.
var _hut_ids: Array[int] = []
var _house_lights_in := 0
## Lights are looked at this often (frames).
const HOUSE_LIGHTS_EVERY := 20
var _water_material: ShaderMaterial
var _rig: CameraRig
var _highlight: PickHighlight
var _effects: WorldEffects
var _loose: LooseObjectRegistry
var _loose_view: LooseObjectsView
var _people_view: PeopleView
var _chunk_order: Array[Vector2i] = []
var _water_cursor := 0
var _water_wait := 0

## The walls moving out after the box unfolded (M13.2): from, seconds, how far.
var _unfold_from := Rect2i()
var _unfold_seconds := 0.0
var _unfold_time := 0.0

## What is known of the box (M13.4): a texel a tile, drawn into the shaders'
## fog (land nobody knows dimmed and greyed).
var _knowledge: FogOfKnowledge
var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_dirty: Dictionary = {} # chunk coord -> true
var _seen_in := 0.0
## The player's look about is noted this often (seconds).
const SEEN_EVERY := 0.5

## Frames between two water mesh rebuilds.
const WATER_REBUILD_EVERY_FRAMES := 3

const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const PROP_SHADER := preload("res://assets/shaders/prop.gdshader")
const TERRAIN_SHADER := preload("res://assets/shaders/terrain.gdshader")
const WEATHER_FX := preload("res://scenes/world/weather_fx.tscn")


func _ready() -> void:
	_chunks = Node3D.new()
	_chunks.name = "Chunks"
	add_child(_chunks)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TERRAIN_SHADER
	_frame = BoxFrame.new()
	_frame.name = "BoxFrame"
	add_child(_frame)
	_lighting = WorldLighting.new()
	_lighting.name = "Lighting"
	add_child(_lighting)
	_water_material = ShaderMaterial.new()
	_water_material.shader = WATER_SHADER
	_prop_material = ShaderMaterial.new()
	_prop_material.shader = PROP_SHADER
	_prop_library = PropMeshLibrary.new()
	_loose_view = LooseObjectsView.new()
	_loose_view.name = "LooseObjects"
	_loose_view.setup(_prop_library, _prop_material)
	add_child(_loose_view)
	_ambient = AmbientLife.new()
	_ambient.name = "AmbientLife"
	add_child(_ambient)
	_people_view = PeopleView.new()
	_people_view.name = "People"
	add_child(_people_view)
	_animals_view = AnimalsView.new()
	_animals_view.name = "Animals"
	add_child(_animals_view)
	_day_night = DayNight.new()
	_day_night.name = "DayNight"
	add_child(_day_night)
	apply_palette(Config.terrain_palette)
	_rig = CameraRig.new(Config.camera)
	_rig.name = "CameraRig"
	add_child(_rig)
	_people_view.setup(_rig, _prop_material)
	_animals_view.setup(_rig, _prop_material)
	_highlight = PickHighlight.new()
	_highlight.name = "PickHighlight"
	add_child(_highlight)
	_effects = WorldEffects.new()
	_effects.name = "Effects"
	add_child(_effects)
	_effects.setup(_prop_material)
	_weather_fx = WEATHER_FX.instantiate()
	add_child(_weather_fx)
	_weather_fx.setup(_rig, _day_night, _lighting, _prop_material, _terrain_material, _water_material, _ambient)
	_tool_fx = ToolFx.new()
	add_child(_tool_fx)
	_tool_fx.setup(_effects, _day_night)
	_rig.set_view_size(get_viewport().get_visible_rect().size)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_apply_camera_settings()
	Settings.setting_changed.connect(_on_setting_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_streamer.stop() # (every worker's task is waited for)


## Shows `world` and what stands on it, replacing whatever was shown before.
## `start` (optional) tells the ambient effects where the campfire is.
func show_world(world: WorldData, props: PropRegistry = null, start: WorldSetup.StartInfo = null,
		loose: LooseObjectRegistry = null) -> void:
	clear()
	_world = world
	_props = props
	_loose = loose
	_loose_view.show_objects(world, loose)
	var started := Time.get_ticks_msec()
	var box_height := Config.world.height_levels * world.height_step + BOX_HEADROOM
	_frame.build(world.bounds, box_height)
	_lighting.fit_to_box(_frame.outer_rect(), _frame.bottom_y(), box_height)
	_rig.ground_height = _ground_height_at
	_rig.setup(Rect2(world.bounds), _frame.outer_rect(), _frame.bottom_y(), box_height)
	# What the camera sees is built now (the whole box, as it is framed);
	# the rest as it comes into sight.
	_streamer.bind(_chunks, _chunk_views, world, props, _prop_library, _terrain_material, _water_material,
		_prop_material, Config.world.height_levels * world.height_step)
	_streamer.fill(_streamer.visible_chunks(_rig))
	_chunk_order = world.chunk_coords()
	if props != null:
		props.chunk_changed.connect(_on_props_changed)
	world.ground_changed.connect(_on_ground_changed)
	_tool_fx.bind(world)
	var has_fire := start != null and start.campfire_id != 0
	_has_fire = has_fire
	_ambient.setup(world, start.settlement_tile if has_fire else Vector2i.ZERO, has_fire)
	var fire_at := Vector3.ZERO
	if has_fire:
		var tile := start.settlement_tile
		fire_at = Vector3(tile.x + 0.5, world.get_height(tile) * world.height_step, tile.y + 0.5)
	_day_night.set_fire(fire_at, has_fire)
	_hut_ids = start.hut_ids.duplicate() if start != null else ([] as Array[int])
	_weather_fx.fit_to_box(Rect2(world.bounds), 0.0, box_height)
	Log.info(Log.Category.WORLD, "World view built", {"chunks": _chunk_views.size(), "ms": Time.get_ticks_msec() - started})


## Shows the people of the world that is being shown (call after show_world).
func show_people(people: PersonRegistry, clock: GameClock, occupations: OccupationLibrary) -> void:
	_people_view.props = _props
	_people_view.show_people(_world, people, clock, occupations)
	_people = people
	_day_night.bind(clock) # the light of the day follows the same clock
	refresh_house_lights()


## Which houses have their lights out: those where everyone is asleep (or
## nobody lives). Looked at a few times a second; call directly to have it now.
func refresh_house_lights() -> void:
	var dark: Array[Vector3] = []
	if _world != null and _props != null:
		for id in _hut_ids:
			var hut := _props.get_prop(id)
			if hut == null:
				continue
			var anyone_up := false
			if _people != null:
				for person in _people.living_in(id):
					if not (person.pose == PersonData.Pose.SLEEP and person.has_flag(PersonData.FLAG_INDOORS)):
						anyone_up = true
						break
			if not anyone_up:
				var at := hut.position2d()
				dark.append(Vector3(at.x, _world.get_height(hut.tile) * _world.height_step, at.y))
	_day_night.set_dark_houses(dark)


## Shows the world's weather (call after show_world).
func show_weather(weather: WeatherSystem, clock: GameClock) -> void:
	_weather_fx.bind(weather, clock)


## The sky: rain and snow, clouds, fog, lightning.
func weather_fx() -> WeatherFx:
	return _weather_fx


## The material of the ground, and of everything that stands on it.
func terrain_material() -> ShaderMaterial:
	return _terrain_material


func prop_material() -> ShaderMaterial:
	return _prop_material


func water_material() -> ShaderMaterial:
	return _water_material


## The light of the day (sun, moon, windows, fire).
func day_night() -> DayNight:
	return _day_night


func clear() -> void:
	_people_view.clear()
	if _props != null and _props.chunk_changed.is_connected(_on_props_changed):
		_props.chunk_changed.disconnect(_on_props_changed)
	if _world != null and _world.ground_changed.is_connected(_on_ground_changed):
		_world.ground_changed.disconnect(_on_ground_changed)
	_ground_dirty = false
	_streamer.unbind()
	for view: ChunkView in _chunk_views.values():
		view.queue_free()
	_chunk_views.clear()
	_chunk_order.clear()
	_water_cursor = 0
	_props_dirty.clear()
	_highlight.clear()
	_effects.clear()
	_loose_view.clear()
	_world = null
	_props = null
	_loose = null
	_people = null
	_hut_ids = []


func ambient() -> AmbientLife:
	return _ambient


func box_frame() -> BoxFrame:
	return _frame


func lighting() -> WorldLighting:
	return _lighting


func camera_rig() -> CameraRig:
	return _rig


func pick_highlight() -> PickHighlight:
	return _highlight


## Shows the world's animals (call after show_world).
func show_animals(animals: AnimalRegistry, library: SpeciesLibrary, clock: GameClock) -> void:
	_animals_view.show_animals(_world, animals, library, clock)


func animals_view() -> AnimalsView:
	return _animals_view


## The settlement's fire burns, or has gone out: its light, its smoke and
## its crackle go with it (the flame itself is part of the prop's mesh).
## Lights the fires of the settlements founded since the first (M12.3).
## `fires`: [Settlement …] other than the first.
func show_other_fires(fires: Array) -> void:
	_day_night.clear_other_fires()
	for own: Settlement in fires:
		var tile := own.start_info().settlement_tile
		var light := _day_night.add_fire(Vector3(tile.x + 0.5, _world.get_height(tile) * _world.height_step, tile.y + 0.5))
		light.visible = own.fire_lit()
		own.fire_changed.connect(func(lit: bool) -> void:
			if is_instance_valid(light):
				light.visible = lit)


func set_fire_lit(lit: bool) -> void:
	_day_night.fire_light().visible = lit and _has_fire
	_ambient.set_fire_lit(lit and _has_fire)


## The view of one chunk (null if it is not shown: out of sight).
## (Its meshes may still be on their way: chunk_streamer().pending().)
func chunk_view(coord: Vector2i) -> ChunkView:
	return _chunk_views.get(coord)


## What has views, and builds them as the camera moves (M13.1).
func chunk_streamer() -> ChunkStreamer:
	return _streamer


func loose_view() -> LooseObjectsView:
	return _loose_view


func people_view() -> PeopleView:
	return _people_view


## What the player's powers look like (the rain cloud, a gust's dust).
func tool_fx() -> ToolFx:
	return _tool_fx


## Visual answers to touches (connect InteractionManager.responded to effects().play).
func effects() -> WorldEffects:
	return _effects


## What is under a screen position (viewport units)? `touch_radius` is the
## forgiveness around the finger, also in viewport units.
## `kind_mask` limits what can be picked (SpatialIndex.KIND_* bits).
func pick(screen: Vector2, touch_radius: float, kind_mask: int = SpatialIndex.KIND_ALL) -> Picker.Result:
	if _world == null:
		return Picker.Result.new()
	var spatial: SpatialIndex = null
	if _props != null:
		spatial = _props.spatial_index
	elif _loose != null:
		spatial = _loose.spatial_index
	return Picker.pick(screen, _rig, _world, spatial, _pick_shape, touch_radius, kind_mask)


## The person under a screen position (0 if there is none): for whoever
## wants a person in particular, whatever else is under the finger.
func pick_person(screen: Vector2, touch_radius: float) -> int:
	if _world == null or _props == null or _props.spatial_index == null:
		return 0
	var result := Picker.pick(screen, _rig, _world, _props.spatial_index, _people_view.pick_shape, touch_radius,
		SpatialIndex.KIND_PERSON)
	return result.entity_id if result.kind == Picker.Kind.ENTITY else 0


## Picking body of anything standing or lying in the world (null if unknown).
func _pick_shape(id: int) -> Variant:
	var shape: Variant = _props.pick_shape(id) if _props != null else null
	if shape == null and _loose != null:
		shape = _loose.pick_shape(id)
	if shape == null:
		shape = _people_view.pick_shape(id)
	if shape == null:
		shape = _animals_view.pick_shape(id)
	return shape


## Draws the debug highlight for a pick result (or clears it for a miss).
func show_pick(result: Picker.Result) -> void:
	_highlight.clear()
	if _world == null or not result.is_hit():
		return
	var surface := _world.get_height(result.tile) * _world.height_step + _world.get_water(result.tile)
	_highlight.show_tile(result.tile, surface, _world.get_water(result.tile) > WaterMesher.MIN_DEPTH)
	if result.kind != Picker.Kind.ENTITY:
		return
	var prop := _props.get_prop(result.entity_id) if _props != null else null
	var object := _loose.get_object(result.entity_id) if _loose != null else null
	if prop != null:
		var at := prop.position2d()
		var ground := _world.get_height(prop.tile) * _world.height_step
		_highlight.show_entity(Vector3(at.x, ground, at.y), prop.pick_shape().y * 1.15)
	elif object != null:
		_highlight.show_entity(object.world_position(_world), object.radius() * 1.15)


## Rebuilds the prop meshes of chunks whose props changed; returns how many.
## Runs automatically each frame; call directly when a rebuild is needed now.
func refresh_dirty_props() -> int:
	if _world == null or _props == null or _props_dirty.is_empty():
		return 0
	var rebuilt := 0
	for coord: Vector2i in _props_dirty:
		var view: ChunkView = _chunk_views.get(coord)
		if view != null:
			# The ground under them may have changed with them (a plot tilled).
			var chunk := _world.get_chunk(coord, false)
			if chunk != null and chunk.is_dirty(ChunkData.DIRTY_MESH):
				view.rebuild_terrain(_world)
			view.rebuild_props(_world, _props, _prop_library, _prop_material)
			rebuilt += 1
	_props_dirty.clear()
	return rebuilt


## The box has unfolded: its walls move out from `from` to where they stand
## now, over `seconds` (at once with reduced motion).
func animate_unfold(from: Rect2i, seconds: float) -> void:
	if _world == null:
		return
	_unfold_from = from
	_unfold_seconds = 0.0 if _rig.reduced_motion else seconds
	_unfold_time = 0.0
	_step_unfold(0.0)


## Shows what is known of the box (call after show_world).
func show_knowledge(knowledge: FogOfKnowledge) -> void:
	_knowledge = knowledge
	if _world == null or knowledge == null:
		return
	var b := _world.bounds
	_fog_image = Image.create(b.size.x, b.size.y, false, Image.FORMAT_L8)
	for y in b.size.y:
		for x in b.size.x:
			_fog_image.set_pixel(x, y, Color.WHITE if knowledge.is_known(b.position + Vector2i(x, y)) else Color.BLACK)
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	for material: ShaderMaterial in [_terrain_material, _prop_material, _water_material]:
		material.set_shader_parameter(&"fog_map", _fog_texture)
		material.set_shader_parameter(&"fog_rect", Vector4(b.position.x, b.position.y, b.size.x, b.size.y))
		material.set_shader_parameter(&"fog_strength", Config.world.fog_strength)
	knowledge.changed.connect(_on_knowledge_changed)


## How known a tile is in the fog texture (1 known, 0 not; for tests).
func fog_at(tile: Vector2i) -> float:
	if _fog_image == null:
		return 1.0
	return _fog_image.get_pixelv(tile - _world.bounds.position).r


func _on_knowledge_changed(coords: Array[Vector2i]) -> void:
	for coord in coords:
		_fog_dirty[coord] = true


## Draws again the fog of chunks whose knowledge changed; notes what the
## camera shows close up as seen by the player.
func _step_fog(delta: float) -> void:
	if _knowledge == null or _fog_image == null:
		return
	_seen_in -= delta
	if _seen_in <= 0.0:
		_seen_in = SEEN_EVERY
		if _rig.distance() <= Config.world.seen_from:
			var rect := _seen_rect()
			if rect.has_area():
				_knowledge.mark_seen(rect)
	if _fog_dirty.is_empty():
		return
	var b := _world.bounds
	for coord: Vector2i in _fog_dirty:
		var area := WorldCoords.chunk_rect(coord, _world.chunk_size).intersection(b)
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var tile := Vector2i(x, y)
				_fog_image.set_pixelv(tile - b.position, Color.WHITE if _knowledge.is_known(tile) else Color.BLACK)
	_fog_dirty.clear()
	_fog_texture.update(_fog_image)


## The ground the camera shows, as tiles (empty when it cannot tell).
func _seen_rect() -> Rect2i:
	var screen := _rig.view_size()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner in [Vector2.ZERO, Vector2(screen.x, 0.0), screen, Vector2(0.0, screen.y)]:
		var at: Variant = _rig.screen_to_ground(corner)
		if at == null:
			return Rect2i()
		low = Vector2(minf(low.x, (at as Vector3).x), minf(low.y, (at as Vector3).z))
		high = Vector2(maxf(high.x, (at as Vector3).x), maxf(high.y, (at as Vector3).z))
	return Rect2i(Vector2i(floori(low.x), floori(low.y)), Vector2i(ceili(high.x - low.x), ceili(high.y - low.y)))


func is_unfolding() -> bool:
	return _unfold_from.has_area()


func _step_unfold(delta: float) -> void:
	_unfold_time += delta
	var t := 1.0 if _unfold_seconds <= 0.0 else smoothstep(0.0, 1.0, _unfold_time / _unfold_seconds)
	var to := _world.bounds
	var start := Vector2(_unfold_from.position).lerp(Vector2(to.position), t)
	var end := Vector2(_unfold_from.end).lerp(Vector2(to.end), t)
	var walls := Rect2i(Vector2i(roundi(start.x), roundi(start.y)), Vector2i(roundi(end.x - start.x), roundi(end.y - start.y)))
	_frame.build(walls, _frame.box_height)
	if t >= 1.0:
		_unfold_from = Rect2i()


func _process(_delta: float) -> void:
	if _unfold_from.has_area():
		_step_unfold(_delta)
	_step_fog(_delta)
	# Ground that has changed is drawn anew (several tiles in one frame: once).
	if _ground_dirty:
		_ground_dirty = false
		refresh_dirty_chunks()
	# Several prop changes in one frame (e.g. clearing a glade) rebuild once.
	refresh_dirty_props()
	# Flowing water changes its chunks ten times a second; rebuilding a water
	# mesh costs milliseconds on a phone. One chunk at a time, a few frames
	# apart: moving water is redrawn several times a second, smoothly enough.
	# Chunks come into sight and go out of it with the camera.
	if _world != null:
		_streamer.update(_rig)
	_water_wait -= 1
	if _water_wait <= 0 and refresh_dirty_water(1) > 0:
		_water_wait = WATER_REBUILD_EVERY_FRAMES
	_lighting.set_view_distance(_rig.distance())
	_ambient.set_night(_day_night.night(), _day_night.hour())
	_house_lights_in -= 1
	if _house_lights_in <= 0:
		_house_lights_in = HOUSE_LIGHTS_EVERY
		refresh_house_lights()


func _on_props_changed(coord: Vector2i) -> void:
	_props_dirty[coord] = true


func _on_ground_changed(_tile: Vector2i) -> void:
	_ground_dirty = true


func chunk_view_count() -> int:
	return _chunk_views.size()


func get_chunk_view(coord: Vector2i) -> ChunkView:
	return _chunk_views.get(coord)


## Rebuilds the water meshes of chunks whose water changed (flowing water
## changes them several times a second), at most `limit` per call so a wide
## flood is spread over frames. Returns how many were rebuilt.
func refresh_dirty_water(limit: int = 1000) -> int:
	if _world == null:
		return 0
	var rebuilt := 0
	var count := _chunk_order.size()
	var first := _water_cursor # start after the chunk rebuilt last, so every chunk gets its turn
	for n in count:
		if rebuilt >= limit:
			break
		var coord: Vector2i = _chunk_order[(first + n) % count]
		var chunk := _world.get_chunk(coord, false)
		if chunk == null or not chunk.is_dirty(ChunkData.DIRTY_WATER) or chunk.is_dirty(ChunkData.DIRTY_MESH):
			continue # (terrain changes are rebuilt, with their water, by refresh_dirty_chunks)
		var view: ChunkView = _chunk_views.get(coord)
		if view == null:
			continue # out of sight: built as it is when it comes into sight
		view.rebuild_water(_world)
		rebuilt += 1
		_water_cursor = (first + n + 1) % count
	return rebuilt


## Rebuilds the meshes of chunks whose terrain or water changed; returns how
## many meshes were rebuilt. Call after tiles change.
func refresh_dirty_chunks() -> int:
	if _world == null:
		return 0
	var rebuilt := 0
	var reseat_loose := false
	for coord: Vector2i in _chunk_views:
		var chunk := _world.get_chunk(coord, false)
		if chunk == null:
			continue
		var view: ChunkView = _chunk_views[coord]
		if chunk.is_dirty(ChunkData.DIRTY_MESH):
			view.rebuild_terrain(_world)
			rebuilt += 1
			_props_dirty[coord] = true # props stand on the terrain: re-seat them
			reseat_loose = true
		if chunk.is_dirty(ChunkData.DIRTY_WATER):
			view.rebuild_water(_world)
			rebuilt += 1
	if reseat_loose:
		_loose_view.reseat() # loose objects lie on the terrain too
	return rebuilt


## Pushes palette values into the shared materials (call again after tuning).
func apply_palette(palette: TerrainPalette) -> void:
	_water_material.set_shader_parameter(&"shallow_color", palette.water_shallow)
	_water_material.set_shader_parameter(&"deep_color", palette.water_deep)
	_water_material.set_shader_parameter(&"foam_color", palette.water_foam)
	_water_material.set_shader_parameter(&"opacity_shallow", palette.water_opacity_shallow)
	_water_material.set_shader_parameter(&"opacity_deep", palette.water_opacity_deep)
	_water_material.set_shader_parameter(&"wave_height", palette.water_wave_height)
	_water_material.set_shader_parameter(&"foam_amount", palette.water_foam_amount)
	for material: ShaderMaterial in [_terrain_material, _water_material, _prop_material, _people_view.body_material(),
			_people_view.selected_material()]:
		material.set_shader_parameter(&"cloud_strength", palette.cloud_shadow_strength)
		material.set_shader_parameter(&"cloud_scale", 1.0 / maxf(palette.cloud_size_tiles, 1.0))
	var clouded: Array[ShaderMaterial] = [_terrain_material, _water_material, _prop_material, _people_view.body_material(),
		_people_view.selected_material()]
	_day_night.setup(_lighting, _prop_material, clouded, palette.cloud_shadow_strength)
	_day_night.refresh()


func _apply_camera_settings() -> void:
	_rig.twist_enabled = bool(Settings.get_value(&"camera/twist_rotate"))
	_rig.reduced_motion = bool(Settings.get_value(&"accessibility/reduced_motion"))
	_effects.reduced_motion = _rig.reduced_motion
	_people_view.reduced_motion = _rig.reduced_motion
	if _weather_fx != null:
		_weather_fx.reduced_motion = _rig.reduced_motion


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"camera/twist_rotate" or key == &"accessibility/reduced_motion":
		_apply_camera_settings()


func _on_viewport_resized() -> void:
	_rig.set_view_size(get_viewport().get_visible_rect().size)


## Terrain surface height (world units) at a world XZ position.
func _ground_height_at(world_xz: Vector2) -> float:
	if _world == null:
		return 0.0
	return _world.get_height(WorldCoords.world2d_to_tile(world_xz)) * _world.height_step
