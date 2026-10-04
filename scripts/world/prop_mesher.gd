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
	if world.get_chunk(coord) == null:
		return Buffers.new()
	return build_from(world, coord, placements(world, props, coord, library), taken_tiles(world, props, coord),
		library.grass_tuft() if with_tufts else null)


## What stands on a chunk, as [template, transform, tint] for each prop (read
## from the registry: main thread). See build_from.
static func placements(world: WorldData, props: PropRegistry, coord: Vector2i, library: PropMeshLibrary) -> Array:
	var out: Array = []
	var origin := WorldCoords.chunk_origin(coord, world.chunk_size)
	var step := world.height_step
	for prop in props.props_in_chunk(coord):
		# A node that has given up what it had looks it (a stump, a bare bush).
		var look := ResourceNodes.look_of(prop) if prop.stock >= 0 else ResourceNodes.Look.FULL
		# (A crop's shape is its stage, and the dry look of it.)
		var variant := Farming.shown_variant(prop) if prop.kind == PropData.Kind.CROP else prop.variant
		var template := library.template_for(prop.kind, variant, look)
		if template == null:
			continue
		var pos := prop.position2d()
		var ground := world.get_height(prop.tile) * step
		var shown := prop.scale() * (ResourceNodes.look_scale(prop) if prop.stock >= 0 else 1.0)
		var xform := Transform3D(
			Basis(Vector3.UP, prop.rotation_radians()).scaled(Vector3.ONE * shown),
			Vector3(pos.x - origin.x, ground, pos.y - origin.y))
		out.append([template, xform, _tint(prop)])
	return out


## Which tiles of a chunk something stands on (1 each; main thread): no grass
## tufts grow there.
static func taken_tiles(world: WorldData, props: PropRegistry, coord: Vector2i) -> PackedByteArray:
	var size := world.chunk_size
	var origin := WorldCoords.chunk_origin(coord, size)
	var out := PackedByteArray()
	out.resize(size * size)
	for ly in size:
		for lx in size:
			if props.has_prop_at(origin + Vector2i(lx, ly)):
				out[ly * size + lx] = 1
	return out


## The merged buffers of `placements` and, with a `tuft`, the grass tufts.
## Touches no registry: safe on a worker thread with a world of its own.
static func build_from(world: WorldData, coord: Vector2i, placed: Array, taken: PackedByteArray,
		tuft: PropMeshLibrary.Template) -> Buffers:
	var out := Buffers.new()
	var chunk := world.get_chunk(coord)
	if chunk == null:
		return out
	var size := world.chunk_size
	var origin := WorldCoords.chunk_origin(coord, size)
	var step := world.height_step
	for one: Array in placed:
		_append(out, one[0], one[1], one[2])

	if tuft != null:
		for ly in size:
			for lx in size:
				var i := ly * size + lx
				if chunk.terrain[i] != ChunkData.Terrain.GRASS or chunk.vegetation[i] < TUFT_MIN_VEGETATION \
						or chunk.water[i] > 0.0:
					continue
				var tile := origin + Vector2i(lx, ly)
				var h := HashNoise.hash2(tile.x, tile.y, _TUFT_SALT)
				if int(h % 100) >= TUFT_CHANCE_PERCENT or taken[i] != 0:
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
	return mesh_from(build_buffers(world, props, coord, library, with_tufts))


## The mesh of built buffers (main thread), or null if they are empty.
static func mesh_from(buffers: Buffers) -> ArrayMesh:
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
		out.uvs.append(Vector2(template.glow_of(i), template.leaf_of(i)))


## Living things vary a little in brightness; built things do not.
static func _tint(prop: PropData) -> float:
	match prop.kind:
		PropData.Kind.TREE, PropData.Kind.BUSH, PropData.Kind.ROCK, PropData.Kind.CROP:
			var n := HashNoise.tile_value(prop.tile.x, prop.tile.y, _TINT_SALT) # 0..65535
			return 0.88 + n / 65535.0 * 0.24
		_:
			return 1.0
