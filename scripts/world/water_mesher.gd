class_name WaterMesher
extends RefCounted
## Builds the water surface mesh for one chunk (bible §10.3, §28.2).
##
## One quad per wet tile at terrain height + water depth. Corner heights are
## averaged over the wet tiles sharing the corner, so the surface stays smooth
## when neighbouring tiles hold different levels (water simulation, M3/M9).
## At the box wall the water gets a vertical face down to the bed, so its
## cross-section shows against the wall.
##
## Vertex colour carries data for the water shader (not a colour):
##   r = depth, 0 (film of water) .. 1 (deep)
##   g = shore, 1 at corners touching dry land, 0 in open water
## UV = world XZ position (for the animated pattern).
## Vertices are chunk-local, like TerrainMesher.

## Tiles with less water than this are treated as dry.
const MIN_DEPTH := 0.001

const _DRY := -1.0
const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


class Buffers:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func is_empty() -> bool:
		return indices.is_empty()

	func triangle_count() -> int:
		return indices.size() / 3


## `deep_depth` is the water depth (world units) that counts as fully deep.
static func build_buffers(world: WorldData, coord: Vector2i, deep_depth: float) -> Buffers:
	var out := Buffers.new()
	var chunk := world.get_chunk(coord)
	if chunk == null:
		return out
	var size := world.chunk_size
	var origin := WorldCoords.chunk_origin(coord, size)
	var step := world.height_step

	# Surface height per tile for this chunk plus a one-tile border.
	# _DRY = no water; tiles outside the box are flagged separately.
	var w := size + 2
	var surface := PackedFloat32Array()
	surface.resize(w * w)
	var outside := PackedByteArray()
	outside.resize(w * w)
	var any_water := false
	for gy in w:
		for gx in w:
			var tile := origin + Vector2i(gx - 1, gy - 1)
			var g := gy * w + gx
			if not world.is_in_bounds(tile):
				surface[g] = _DRY
				outside[g] = 1
				continue
			var depth := world.get_water(tile)
			if depth > MIN_DEPTH:
				surface[g] = world.get_height(tile) * step + depth
				if gx >= 1 and gx <= size and gy >= 1 and gy <= size:
					any_water = true
			else:
				surface[g] = _DRY
	if not any_water:
		return out

	for ly in size:
		for lx in size:
			var g := (ly + 1) * w + (lx + 1)
			if surface[g] == _DRY:
				continue
			var i := ly * size + lx
			var depth := chunk.water[i]
			var depth01 := clampf(depth / deep_depth, 0.0, 1.0) if deep_depth > 0.0 else 1.0
			var base := out.vertices.size()
			# Corners in the same order as TerrainMesher's top face.
			var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]
			for c in corners:
				var info := _corner(surface, outside, w, lx + 1 + c.x, ly + 1 + c.y)
				out.vertices.append(Vector3(lx + c.x, info.x, ly + c.y))
				out.normals.append(Vector3.UP)
				out.colors.append(Color(depth01, info.y, 0.0, 1.0))
				out.uvs.append(Vector2(origin.x + lx + c.x, origin.y + ly + c.y))
			_tri(out.indices, base, 0, 1, 2)
			_tri(out.indices, base, 0, 2, 3)

			# Cross-section against the box wall.
			var bed := chunk.height[i] * step
			for dir in _DIRS:
				if outside[g + dir.y * w + dir.x] == 1:
					_wall_face(out, origin, lx, ly, dir, surface[g], bed, depth01)
	return out


## The chunk's water ArrayMesh, or null if the chunk is dry.
static func build_mesh(world: WorldData, coord: Vector2i, deep_depth: float) -> ArrayMesh:
	return mesh_from(build_buffers(world, coord, deep_depth))


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
	arrays[Mesh.ARRAY_INDEX] = buffers.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## For the grid corner at (cx, cy) — shared by tiles (cx-1..cx, cy-1..cy) —
## returns Vector2(average surface height of the wet tiles, shore flag).
static func _corner(surface: PackedFloat32Array, outside: PackedByteArray, w: int, cx: int, cy: int) -> Vector2:
	var total := 0.0
	var wet := 0
	var touches_land := false
	for oy in [-1, 0]:
		for ox in [-1, 0]:
			var g: int = (cy + oy) * w + (cx + ox)
			if surface[g] != _DRY:
				total += surface[g]
				wet += 1
			elif outside[g] == 0:
				touches_land = true # dry tile inside the box; the wall is not a shore
	return Vector2(total / wet if wet > 0 else 0.0, 1.0 if touches_land else 0.0)


static func _wall_face(out: Buffers, origin: Vector2i, lx: int, ly: int, dir: Vector2i, y_top: float, y_bed: float, depth01: float) -> void:
	var a: Vector2
	var b: Vector2
	if dir.x == 1:
		a = Vector2(lx + 1, ly); b = Vector2(lx + 1, ly + 1)
	elif dir.x == -1:
		a = Vector2(lx, ly + 1); b = Vector2(lx, ly)
	elif dir.y == 1:
		a = Vector2(lx + 1, ly + 1); b = Vector2(lx, ly + 1)
	else:
		a = Vector2(lx, ly); b = Vector2(lx + 1, ly)
	var normal := Vector3(dir.x, 0, dir.y)
	var p: Array[Vector3] = [Vector3(a.x, y_top, a.y), Vector3(b.x, y_top, b.y), Vector3(b.x, y_bed, b.y), Vector3(a.x, y_bed, a.y)]
	var base := out.vertices.size()
	for v in p:
		out.vertices.append(v)
		out.normals.append(normal)
		out.colors.append(Color(depth01, 0.0, 0.0, 1.0))
		out.uvs.append(Vector2(origin.x + v.x, origin.y + v.z))
	if (p[2] - p[0]).cross(p[1] - p[0]).dot(normal) > 0.0:
		_tri(out.indices, base, 0, 1, 2)
		_tri(out.indices, base, 0, 2, 3)
	else:
		_tri(out.indices, base, 0, 2, 1)
		_tri(out.indices, base, 0, 3, 2)


static func _tri(indices: PackedInt32Array, base: int, a: int, b: int, c: int) -> void:
	indices.append(base + a)
	indices.append(base + b)
	indices.append(base + c)
