class_name WorldView
extends Node3D
## Everything visible of the world (bible §31.3): the box frame, chunk views
## (terrain, water, props), ambient life and lighting. Entities and weather
## effects join in later milestones. Views only read world state; they never
## own or change it.
##
## TEMPORARY (until M1.7): a fixed camera that frames the whole box.

const CAMERA_FOV := 32.0
const CAMERA_PITCH_DEG := 52.0
const FRAME_MARGIN := 1.10
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
var _camera: Camera3D

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
	_camera = Camera3D.new()
	_camera.name = "TempCamera"
	_camera.fov = CAMERA_FOV
	add_child(_camera)
	get_viewport().size_changed.connect(_frame_world)


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
	_frame_world()
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


# --- temporary camera (replaced in M1.7) ------------------------------------------

## Places the camera so the whole box fits the screen in any orientation.
func _frame_world() -> void:
	if _world == null or _camera == null:
		return
	var b := _frame.outer_rect() # the whole box, frame included
	var center := Vector3(b.position.x + b.size.x * 0.5, 1.0, b.position.y + b.size.y * 0.5)
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / size.y if size.y > 0.0 else 1.0
	var half_v := deg_to_rad(CAMERA_FOV) * 0.5
	var half_h := atan(tan(half_v) * aspect)
	var pitch := deg_to_rad(CAMERA_PITCH_DEG)
	# Width must fit horizontally; depth (foreshortened by the pitch) vertically.
	var for_width := (b.size.x * 0.5) / tan(half_h)
	var for_depth := (b.size.y * 0.5 * sin(pitch)) / tan(half_v) + b.size.y * 0.5 * cos(pitch)
	var distance := maxf(for_width, for_depth) * FRAME_MARGIN
	_camera.position = center + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	_camera.look_at(center, Vector3.UP)
	_camera.far = distance * 3.0
