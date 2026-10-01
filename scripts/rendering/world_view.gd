class_name WorldView
extends Node3D
## Everything visible of the world (bible §31.3): chunk views now; the box
## frame, props, entities and weather effects join in later sub-phases.
## Views only read world state; they never own or change it.
##
## TEMPORARY (until M1.6 / M1.7): a fixed camera that frames the whole box and
## a basic sun + environment, so the terrain can be seen and judged.

const CAMERA_FOV := 32.0
const CAMERA_PITCH_DEG := 52.0
const FRAME_MARGIN := 1.12

var _world: WorldData
var _props: PropRegistry
var _prop_library: PropMeshLibrary
var _prop_material: ShaderMaterial
var _props_dirty: Dictionary = {} # chunk coord -> true
var _ambient: AmbientLife
var _chunks: Node3D
var _chunk_views: Dictionary = {} # Vector2i -> ChunkView
var _terrain_material: StandardMaterial3D
var _water_material: ShaderMaterial
var _camera: Camera3D

const WATER_SHADER := preload("res://assets/shaders/water.gdshader")
const PROP_SHADER := preload("res://assets/shaders/prop.gdshader")


func _ready() -> void:
	_chunks = Node3D.new()
	_chunks.name = "Chunks"
	add_child(_chunks)
	_terrain_material = StandardMaterial3D.new()
	_terrain_material.vertex_color_use_as_albedo = true
	# Palette colours are authored in sRGB; without this they render washed out.
	_terrain_material.vertex_color_is_srgb = true
	_terrain_material.roughness = 1.0
	_terrain_material.metallic_specular = 0.0
	_water_material = ShaderMaterial.new()
	_water_material.shader = WATER_SHADER
	_prop_material = ShaderMaterial.new()
	_prop_material.shader = PROP_SHADER
	_prop_library = PropMeshLibrary.new()
	_ambient = AmbientLife.new()
	_ambient.name = "AmbientLife"
	add_child(_ambient)
	apply_palette(Config.terrain_palette)
	_build_temporary_camera_and_light()
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


# --- temporary camera / light (replaced in M1.6 and M1.7) ----------------------------

func _build_temporary_camera_and_light() -> void:
	_camera = Camera3D.new()
	_camera.name = "TempCamera"
	_camera.fov = CAMERA_FOV
	add_child(_camera)

	var sun := DirectionalLight3D.new()
	sun.name = "TempSun"
	sun.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.97, 0.90)
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.113725, 0.141176, 0.188235)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.80)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.name = "TempEnvironment"
	world_env.environment = env
	add_child(world_env)


## Places the camera so the whole box fits the screen in any orientation.
func _frame_world() -> void:
	if _world == null or _camera == null:
		return
	var b := _world.bounds
	var center := Vector3(b.position.x + b.size.x * 0.5, 0.0, b.position.y + b.size.y * 0.5)
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
