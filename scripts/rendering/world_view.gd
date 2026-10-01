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
var _chunk_views: Dictionary = {} # Vector2i -> ChunkView
var _terrain_material: ShaderMaterial
var _frame: BoxFrame
var _lighting: WorldLighting
var _water_material: ShaderMaterial
var _rig: CameraRig

const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const PROP_SHADER := preload("res://assets/shaders/prop.gdshader")
const TERRAIN_SHADER := preload("res://assets/shaders/terrain.gdshader")


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
	_ambient = AmbientLife.new()
	_ambient.name = "AmbientLife"
	add_child(_ambient)
	apply_palette(Config.terrain_palette)
	_rig = CameraRig.new(Config.camera)
	_rig.name = "CameraRig"
	add_child(_rig)
	_rig.set_view_size(get_viewport().get_visible_rect().size)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_apply_camera_settings()
	Settings.setting_changed.connect(_on_setting_changed)


## Shows `world` and what stands on it, replacing whatever was shown before.
## `start` (optional) tells the ambient effects where the campfire is.
func show_world(world: WorldData, props: PropRegistry = null, start: WorldSetup.StartInfo = null) -> void:
	clear()
	_world = world
	_props = props
	var started := Time.get_ticks_msec()
	for coord in world.chunk_coords():
		var view := ChunkView.new()
		_chunks.add_child(view)
		view.setup(world, coord, _terrain_material, _water_material)
		if props != null:
			view.rebuild_props(world, props, _prop_library, _prop_material)
		_chunk_views[coord] = view
	if props != null:
		props.chunk_changed.connect(_on_props_changed)
	var box_height := Config.world.height_levels * world.height_step + BOX_HEADROOM
	_frame.build(world.bounds, box_height)
	_lighting.fit_to_box(_frame.outer_rect(), _frame.bottom_y(), box_height)
	var has_fire := start != null and start.campfire_id != 0
	_ambient.setup(world, start.settlement_tile if has_fire else Vector2i.ZERO, has_fire)
	_rig.ground_height = _ground_height_at
	_rig.setup(Rect2(world.bounds), _frame.outer_rect(), _frame.bottom_y(), box_height)
	Log.info(Log.Category.WORLD, "World view built", {"chunks": _chunk_views.size(), "ms": Time.get_ticks_msec() - started})


func clear() -> void:
	if _props != null and _props.chunk_changed.is_connected(_on_props_changed):
		_props.chunk_changed.disconnect(_on_props_changed)
	for view: ChunkView in _chunk_views.values():
		view.queue_free()
	_chunk_views.clear()
	_props_dirty.clear()
	_world = null
	_props = null


func ambient() -> AmbientLife:
	return _ambient


func box_frame() -> BoxFrame:
	return _frame


func lighting() -> WorldLighting:
	return _lighting


func camera_rig() -> CameraRig:
	return _rig


## Rebuilds the prop meshes of chunks whose props changed; returns how many.
## Runs automatically each frame; call directly when a rebuild is needed now.
func refresh_dirty_props() -> int:
	if _world == null or _props == null or _props_dirty.is_empty():
		return 0
	var rebuilt := 0
	for coord: Vector2i in _props_dirty:
		var view: ChunkView = _chunk_views.get(coord)
		if view != null:
			view.rebuild_props(_world, _props, _prop_library, _prop_material)
			rebuilt += 1
	_props_dirty.clear()
	return rebuilt


func _process(_delta: float) -> void:
	# Several prop changes in one frame (e.g. clearing a glade) rebuild once.
	refresh_dirty_props()
	_lighting.set_view_distance(_rig.distance())


func _on_props_changed(coord: Vector2i) -> void:
	_props_dirty[coord] = true


func chunk_view_count() -> int:
	return _chunk_views.size()


func get_chunk_view(coord: Vector2i) -> ChunkView:
	return _chunk_views.get(coord)


## Rebuilds the meshes of chunks whose terrain or water changed; returns how
## many meshes were rebuilt. Call after tiles change.
func refresh_dirty_chunks() -> int:
	if _world == null:
		return 0
	var rebuilt := 0
	for coord: Vector2i in _chunk_views:
		var chunk := _world.get_chunk(coord, false)
		if chunk == null:
			continue
		var view: ChunkView = _chunk_views[coord]
		if chunk.is_dirty(ChunkData.DIRTY_MESH):
			view.rebuild_terrain(_world)
			rebuilt += 1
			_props_dirty[coord] = true # props stand on the terrain: re-seat them
		if chunk.is_dirty(ChunkData.DIRTY_WATER):
			view.rebuild_water(_world)
			rebuilt += 1
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
	for material: ShaderMaterial in [_terrain_material, _water_material, _prop_material]:
		material.set_shader_parameter(&"cloud_strength", palette.cloud_shadow_strength)
		material.set_shader_parameter(&"cloud_scale", 1.0 / maxf(palette.cloud_size_tiles, 1.0))


func _apply_camera_settings() -> void:
	_rig.twist_enabled = bool(Settings.get_value(&"camera/twist_rotate"))
	_rig.reduced_motion = bool(Settings.get_value(&"accessibility/reduced_motion"))


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
