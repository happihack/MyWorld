class_name ChunkView
extends Node3D
## Visual for one chunk (bible §31.7): terrain and water meshes now; props
## (M1.5) are added as children. Views are disposable — all state lives in
## WorldData — and are rebuilt whenever the chunk is marked dirty.

var coord: Vector2i

var _terrain: MeshInstance3D
var _water: MeshInstance3D


func _init() -> void:
	_terrain = MeshInstance3D.new()
	_terrain.name = "Terrain"
	add_child(_terrain)
	_water = MeshInstance3D.new()
	_water.name = "Water"
	# Water never casts shadows (it is a thin transparent sheet).
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)


## Binds this view to a chunk and builds its geometry.
func setup(world: WorldData, chunk_coord: Vector2i, terrain_material: Material, water_material: Material) -> void:
	coord = chunk_coord
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	var origin := WorldCoords.chunk_origin(coord, world.chunk_size)
	position = Vector3(origin.x, 0.0, origin.y)
	_terrain.material_override = terrain_material
	_water.material_override = water_material
	rebuild_terrain(world)
	rebuild_water(world)


func rebuild_terrain(world: WorldData) -> void:
	_terrain.mesh = TerrainMesher.build_mesh(world, coord, Config.terrain_palette, world.height_step)
	_clear_dirty(world, ChunkData.DIRTY_MESH)


func rebuild_water(world: WorldData) -> void:
	var deep := Config.terrain_palette.water_deep_levels * world.height_step
	_water.mesh = WaterMesher.build_mesh(world, coord, deep)
	_water.visible = _water.mesh != null
	_clear_dirty(world, ChunkData.DIRTY_WATER)


func terrain_mesh() -> Mesh:
	return _terrain.mesh


func water_mesh() -> Mesh:
	return _water.mesh


func _clear_dirty(world: WorldData, bits: int) -> void:
	var chunk := world.get_chunk(coord, false)
	if chunk != null:
		chunk.clear_dirty(bits)
