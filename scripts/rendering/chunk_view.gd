class_name ChunkView
extends Node3D
## Visual for one chunk (bible §31.7): the terrain mesh now; water (M1.4) and
## props (M1.5) are added as children. Views are disposable — all state lives
## in WorldData — and are rebuilt whenever the chunk is marked dirty.

var coord: Vector2i

var _terrain: MeshInstance3D


func _init() -> void:
	_terrain = MeshInstance3D.new()
	_terrain.name = "Terrain"
	add_child(_terrain)


## Binds this view to a chunk and builds its geometry.
func setup(world: WorldData, chunk_coord: Vector2i, material: Material) -> void:
	coord = chunk_coord
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	var origin := WorldCoords.chunk_origin(coord, world.chunk_size)
	position = Vector3(origin.x, 0.0, origin.y)
	_terrain.material_override = material
	rebuild_terrain(world)


func rebuild_terrain(world: WorldData) -> void:
	_terrain.mesh = TerrainMesher.build_mesh(world, coord, Config.terrain_palette, Config.world.height_step)
	var chunk := world.get_chunk(coord, false)
	if chunk != null:
		chunk.clear_dirty(ChunkData.DIRTY_MESH)


func terrain_mesh() -> Mesh:
	return _terrain.mesh
