class_name PropMesher
extends RefCounted
## Merges everything standing on a chunk into ONE mesh (bible §31.7): trees,
## rocks, bushes, huts, the campfire, ruins and grass tufts. One draw call per
## chunk instead of one per prop type; rebuilt when a prop on the chunk changes.
##
## Each prop is a PropMeshLibrary template transformed by its PropData (tile,
## offset, rotation, scale) and stood on the terrain. Vertices are chunk-local.
## Colour alpha stays the wind-sway weight for the prop shader.

## Grass tufts grow on grass tiles at least this lush (ChunkData.vegetation)...
const TUFT_MIN_VEGETATION := 120
## ...with this chance per tile (out of 100), decided by a tile hash.
const TUFT_CHANCE_PERCENT := 40
const _TUFT_SALT := 0x70F7
const _TINT_SALT := 0x71C7


class Buffers:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	## x = what glows (PropMeshLibrary.Template.glow).
	var uvs := PackedVector2Array()

	func is_empty() -> bool:
		return vertices.is_empty()

	func triangle_count() -> int:
		return vertices.size() / 3


static func build_buffers(world: WorldData, props: PropRegistry, coord: Vector2i,
		library: PropMeshLibrary, with_tufts: bool = true) -> Buffers:
	var out := Buffers.new()
	var chunk := world.get_chunk(coord)
	if chunk == null:
		return out
	var size := world.chunk_size
	var origin := WorldCoords.chunk_origin(coord, size)
	var step := world.height_step

	for prop in props.props_in_chunk(coord):
		# A node that has given up what it had looks it (a stump, a bare bush).
		var look := ResourceNodes.look_of(prop) if prop.stock >= 0 else ResourceNodes.Look.FULL
		var template := library.template_for(prop.kind, prop.variant, look)
		if template == null:
			continue
		var pos := prop.position2d()
		var ground := world.get_height(prop.tile) * step
		var shown := prop.scale() * (ResourceNodes.look_scale(prop) if prop.stock >= 0 else 1.0)
		var xform := Transform3D(
			Basis(Vector3.UP, prop.rotation_radians()).scaled(Vector3.ONE * shown),
			Vector3(pos.x - origin.x, ground, pos.y - origin.y))
		_append(out, template, xform, _tint(prop))

	if with_tufts:
		var tuft := library.grass_tuft()
		for ly in size:
			for lx in size:
				var i := ly * size + lx
				if chunk.terrain[i] != ChunkData.Terrain.GRASS or chunk.vegetation[i] < TUFT_MIN_VEGETATION \
						or chunk.water[i] > 0.0:
					continue
				var tile := origin + Vector2i(lx, ly)
				var h := HashNoise.hash2(tile.x, tile.y, _TUFT_SALT)
				if int(h % 100) >= TUFT_CHANCE_PERCENT or props.has_prop_at(tile):
					continue
				var ox := ((h >> 8) & 0xFF) / 255.0 * 0.7 + 0.15
				var oz := ((h >> 16) & 0xFF) / 255.0 * 0.7 + 0.15
				var yaw := ((h >> 24) & 0xFF) / 255.0 * TAU
				var scale := 0.8 + ((h >> 4) & 0xF) / 15.0 * 0.5
				var xform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale),
					Vector3(lx + ox, chunk.height[i] * step, ly + oz))
				_append(out, tuft, xform, 1.0)
	return out


## The chunk's merged prop mesh, or null if nothing stands on it.
static func build_mesh(world: WorldData, props: PropRegistry, coord: Vector2i,
		library: PropMeshLibrary, with_tufts: bool = true) -> ArrayMesh:
	var buffers := build_buffers(world, props, coord, library, with_tufts)
	if buffers.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffers.vertices
	arrays[Mesh.ARRAY_NORMAL] = buffers.normals
	arrays[Mesh.ARRAY_COLOR] = buffers.colors
	arrays[Mesh.ARRAY_TEX_UV] = buffers.uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append(out: Buffers, template: PropMeshLibrary.Template, xform: Transform3D, tint: float) -> void:
	# Rotation + uniform scale: normals only need the rotation.
	var normal_basis := xform.basis.orthonormalized()
	for i in template.vertices.size():
		out.vertices.append(xform * template.vertices[i])
		out.normals.append(normal_basis * template.normals[i])
		var c := template.colors[i]
		out.colors.append(Color(c.r * tint, c.g * tint, c.b * tint, c.a))
		out.uvs.append(Vector2(template.glow_of(i), 0.0))


## Living things vary a little in brightness; built things do not.
static func _tint(prop: PropData) -> float:
	match prop.kind:
		PropData.Kind.TREE, PropData.Kind.BUSH, PropData.Kind.ROCK:
			var n := HashNoise.tile_value(prop.tile.x, prop.tile.y, _TINT_SALT) # 0..65535
			return 0.88 + n / 65535.0 * 0.24
		_:
			return 1.0
