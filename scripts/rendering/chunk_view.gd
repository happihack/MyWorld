class_name ChunkView
extends Node3D
## Visual for one chunk (bible §31.7): terrain, water and one merged mesh for
## everything standing on the chunk. Views are disposable — all state lives in
## WorldData — and are rebuilt whenever the chunk is marked dirty.
##
## Views are pooled (M13.1): a view that goes out of sight is released and
## placed again on another chunk. Meshes built on a worker thread (ChunkStreamer)
## are applied only for the layers not rebuilt here in the meantime (`versions`).

var coord: Vector2i
## The worker build under way for this view (ChunkStreamer.Job), or null.
var job: RefCounted = null
## [terrain, water, props]: each grows with every rebuild of that layer here —
## a worker's mesh built from older data is dropped.
var versions := PackedInt32Array([0, 0, 0])

var _terrain: MeshInstance3D
var _water: MeshInstance3D
var _props: MeshInstance3D


func _init() -> void:
	_terrain = MeshInstance3D.new()
	_terrain.name = "Terrain"
	add_child(_terrain)
	_water = MeshInstance3D.new()
	_water.name = "Water"
	# Water never casts shadows (it is a thin transparent sheet).
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	_props = MeshInstance3D.new()
	_props.name = "Props"
	add_child(_props)


## Binds this view to a chunk and builds its geometry.
func setup(world: WorldData, chunk_coord: Vector2i, terrain_material: Material, water_material: Material) -> void:
	place(world, chunk_coord, terrain_material, water_material)
	rebuild_terrain(world)
	rebuild_water(world)


## Binds this view to a chunk without building anything (its meshes come later).
func place(world: WorldData, chunk_coord: Vector2i, terrain_material: Material, water_material: Material) -> void:
	coord = chunk_coord
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	var origin := WorldCoords.chunk_origin(coord, world.chunk_size)
	position = Vector3(origin.x, 0.0, origin.y)
	_terrain.material_override = terrain_material
	_water.material_override = water_material
	visible = true


## Out of sight: no meshes, no build under way (back to the pool).
func release() -> void:
	job = null
	for layer in 3:
		versions[layer] += 1
	_terrain.mesh = null
	_water.mesh = null
	_props.mesh = null
	visible = false


func rebuild_props(world: WorldData, props: PropRegistry, library: PropMeshLibrary, material: Material) -> void:
	_props.material_override = material
	set_props_mesh(PropMesher.build_mesh(world, props, coord, library))
	versions[2] += 1


func rebuild_terrain(world: WorldData) -> void:
	_terrain.mesh = TerrainMesher.build_mesh(world, coord, Config.terrain_palette, world.height_step)
	_clear_dirty(world, ChunkData.DIRTY_MESH)
	versions[0] += 1


func rebuild_water(world: WorldData) -> void:
	var deep := Config.terrain_palette.water_deep_levels * world.height_step
	set_water_mesh(WaterMesher.build_mesh(world, coord, deep))
	_clear_dirty(world, ChunkData.DIRTY_WATER)
	versions[1] += 1


## Meshes made elsewhere (a worker's buffers, made into meshes on the main thread).
func set_terrain_mesh(mesh: Mesh) -> void:
	_terrain.mesh = mesh


func set_water_mesh(mesh: Mesh) -> void:
	_water.mesh = mesh
	_water.visible = mesh != null


func set_props_mesh(mesh: Mesh, material: Material = null) -> void:
	if material != null:
		_props.material_override = material
	_props.mesh = mesh
	_props.visible = mesh != null


func terrain_mesh() -> Mesh:
	return _terrain.mesh


func water_mesh() -> Mesh:
	return _water.mesh


func props_mesh() -> Mesh:
	return _props.mesh


func _clear_dirty(world: WorldData, bits: int) -> void:
	var chunk := world.get_chunk(coord, false)
	if chunk != null:
		chunk.clear_dirty(bits)
