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
var _chunks: Node3D
var _chunk_views: Dictionary = {} # Vector2i -> ChunkView
var _terrain_material: StandardMaterial3D
var _camera: Camera3D


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
	_build_temporary_camera_and_light()
	get_viewport().size_changed.connect(_frame_world)


## Shows `world`, replacing whatever was shown before.
func show_world(world: WorldData) -> void:
	clear()
	_world = world
	for coord in world.chunk_coords():
		var view := ChunkView.new()
		_chunks.add_child(view)
		view.setup(world, coord, _terrain_material)
		_chunk_views[coord] = view
	_frame_world()
	Log.info(Log.Category.WORLD, "World view built", {"chunks": _chunk_views.size()})


func clear() -> void:
	for view: ChunkView in _chunk_views.values():
		view.queue_free()
	_chunk_views.clear()
	_world = null


func chunk_view_count() -> int:
	return _chunk_views.size()


func get_chunk_view(coord: Vector2i) -> ChunkView:
	return _chunk_views.get(coord)


## Rebuilds the meshes of chunks whose terrain changed. Call when tiles change.
func refresh_dirty_chunks() -> int:
	if _world == null:
		return 0
	var rebuilt := 0
	for coord: Vector2i in _chunk_views:
		var chunk := _world.get_chunk(coord, false)
		if chunk != null and chunk.is_dirty(ChunkData.DIRTY_MESH):
			(_chunk_views[coord] as ChunkView).rebuild_terrain(_world)
			rebuilt += 1
	return rebuilt


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
