class_name TerrainMesher
extends RefCounted
## Builds the stepped-block terrain mesh for one chunk (bible §28.2, §31.7).
##
## Each tile is a block: a top face at its height, plus side faces wherever a
## neighbour is lower. Outside the box the ground is treated as absent, so the
## rim of the world shows its full side down to y = 0. Vertices are in chunk-
## local space (x, z in 0..chunk_size); place the mesh at the chunk origin.
##
## Colours are per-vertex (no textures): terrain colour, slight per-tile
## variation, corner ambient occlusion on top faces and a darker base on sides.
## Pure functions: safe to call headless and (later) from worker threads, as
## long as the chunks involved are not being modified.

const OUTSIDE := -1 # height used for tiles outside the box

const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


class Buffers:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func is_empty() -> bool:
		return indices.is_empty()

	func triangle_count() -> int:
		return indices.size() / 3


## Vertex/index data for the chunk at `coord`.
static func build_buffers(world: WorldData, coord: Vector2i, palette: TerrainPalette, height_step: float) -> Buffers:
	var out := Buffers.new()
	var chunk := world.get_chunk(coord)
	if chunk == null:
		return out
	var size := world.chunk_size
	var origin := WorldCoords.chunk_origin(coord, size)

	# Heights of this chunk plus a one-tile border (neighbours, or OUTSIDE).
	var w := size + 2
	var grid := PackedInt32Array()
	grid.resize(w * w)
	for gy in w:
		for gx in w:
			var tile := origin + Vector2i(gx - 1, gy - 1)
			grid[gy * w + gx] = world.get_height(tile) if world.is_in_bounds(tile) else OUTSIDE

	for ly in size:
		for lx in size:
			var tile := origin + Vector2i(lx, ly)
			if not world.is_in_bounds(tile):
				continue
			var i := ly * size + lx
			var level := chunk.height[i]
			var terrain := chunk.terrain[i]
			var g := (ly + 1) * w + (lx + 1)
			var y := level * height_step
			var shade := _tile_shade(tile, palette.tile_variation)
			var top_color := _scaled(palette.top(terrain), shade)

			# Top face with corner ambient occlusion.
			var ao00 := _corner_light(grid, w, g, -1, -1, level, palette.corner_occlusion)
			var ao10 := _corner_light(grid, w, g, 1, -1, level, palette.corner_occlusion)
			var ao11 := _corner_light(grid, w, g, 1, 1, level, palette.corner_occlusion)
			var ao01 := _corner_light(grid, w, g, -1, 1, level, palette.corner_occlusion)
			var base := out.vertices.size()
			out.vertices.append(Vector3(lx, y, ly))
			out.vertices.append(Vector3(lx + 1, y, ly))
			out.vertices.append(Vector3(lx + 1, y, ly + 1))
			out.vertices.append(Vector3(lx, y, ly + 1))
			for n in 4:
				out.normals.append(Vector3.UP)
			out.colors.append(_scaled(top_color, ao00))
			out.colors.append(_scaled(top_color, ao10))
			out.colors.append(_scaled(top_color, ao11))
			out.colors.append(_scaled(top_color, ao01))
			# Split along the brighter diagonal so the shading looks even.
			if ao00 + ao11 >= ao10 + ao01:
				_tri(out.indices, base, 0, 1, 2)
				_tri(out.indices, base, 0, 2, 3)
			else:
				_tri(out.indices, base, 1, 2, 3)
				_tri(out.indices, base, 1, 3, 0)

			# Side faces down to each lower neighbour.
			var side_color := _scaled(palette.side(terrain), shade)
			var side_low := _scaled(side_color, palette.side_base_shade)
			for dir in _DIRS:
				var neighbour := grid[g + dir.y * w + dir.x]
				if neighbour >= level:
					continue
				var y_low := maxi(neighbour, 0) * height_step
				_side(out, lx, ly, dir, y, y_low, side_color, side_low)
	return out


## The chunk's ArrayMesh, or null if it has no geometry.
static func build_mesh(world: WorldData, coord: Vector2i, palette: TerrainPalette, height_step: float) -> ArrayMesh:
	var buffers := build_buffers(world, coord, palette, height_step)
	if buffers.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffers.vertices
	arrays[Mesh.ARRAY_NORMAL] = buffers.normals
	arrays[Mesh.ARRAY_COLOR] = buffers.colors
	arrays[Mesh.ARRAY_INDEX] = buffers.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Light factor for a top-face corner: 1 minus occlusion per taller tile among
## the three other tiles that share the corner.
static func _corner_light(grid: PackedInt32Array, w: int, g: int, dx: int, dy: int, level: int, occlusion: float) -> float:
	var taller := 0
	if grid[g + dx] > level:
		taller += 1
	if grid[g + dy * w] > level:
		taller += 1
	if grid[g + dy * w + dx] > level:
		taller += 1
	return 1.0 - occlusion * taller


static func _side(out: Buffers, lx: int, ly: int, dir: Vector2i, y_top: float, y_low: float, top_color: Color, low_color: Color) -> void:
	# The two ends of the tile edge facing `dir`.
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
	var p0 := Vector3(a.x, y_top, a.y)
	var p1 := Vector3(b.x, y_top, b.y)
	var p2 := Vector3(b.x, y_low, b.y)
	var p3 := Vector3(a.x, y_low, a.y)
	var base := out.vertices.size()
	out.vertices.append(p0)
	out.vertices.append(p1)
	out.vertices.append(p2)
	out.vertices.append(p3)
	for n in 4:
		out.normals.append(normal)
	out.colors.append(top_color)
	out.colors.append(top_color)
	out.colors.append(low_color)
	out.colors.append(low_color)
	# Godot's front faces wind clockwise: front normal = (p2 - p0) x (p1 - p0).
	if (p2 - p0).cross(p1 - p0).dot(normal) > 0.0:
		_tri(out.indices, base, 0, 1, 2)
		_tri(out.indices, base, 0, 2, 3)
	else:
		_tri(out.indices, base, 0, 2, 1)
		_tri(out.indices, base, 0, 3, 2)


static func _tri(indices: PackedInt32Array, base: int, a: int, b: int, c: int) -> void:
	indices.append(base + a)
	indices.append(base + b)
	indices.append(base + c)


## Brightness factor for a tile, varying by ±variation.
static func _tile_shade(tile: Vector2i, variation: float) -> float:
	var n := HashNoise.tile_value(tile.x, tile.y, 0x7E44A1) # 0..65535
	return 1.0 + (n / 32767.5 - 1.0) * variation


static func _scaled(color: Color, factor: float) -> Color:
	return Color(color.r * factor, color.g * factor, color.b * factor, color.a)
