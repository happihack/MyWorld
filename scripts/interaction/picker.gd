class_name Picker
extends RefCounted
## Turns a screen position into "what is under the finger" (bible §23.3).
##
## 1. Terrain: the ray is marched across the height grid tile by tile; it hits
##    block tops and the sides of steps, so high ground hides what is behind it.
##    A water surface counts as the hit where there is water.
## 2. Entities are picked in screen space: each nearby entity's body (a
##    base-to-top segment with a radius) is projected to the screen and compared
##    with the finger. A tap on a tree's canopy therefore selects the tree even
##    though the ray lands on the ground behind it.
## 3. A direct hit beats any near miss; among near misses (within the touch
##    radius) the kind priority decides, then the distance.
##
## No physics engine and no colliders: math only, testable headless.

enum Kind { NONE, TILE, WATER, ENTITY }

## Entities taller than this are not expected (bounds the candidate search).
const MAX_ENTITY_HEIGHT := 2.2
## Kind bits from most to least preferred (bible §23.3).
const PRIORITY: Array[int] = [
	SpatialIndex.KIND_PERSON,
	SpatialIndex.KIND_ANIMAL,
	SpatialIndex.KIND_LOOSE_OBJECT,
	SpatialIndex.KIND_MYSTERY,
	SpatialIndex.KIND_RESOURCE_NODE,
	SpatialIndex.KIND_BUILDING,
]


class Result:
	extends RefCounted
	var kind: Kind = Kind.NONE
	var tile := Vector2i.ZERO
	## World position of the terrain/water hit (also set for entities).
	var position := Vector3.ZERO
	var entity_id := 0
	## SpatialIndex kind bit of the picked entity.
	var entity_kind := 0
	## True if the finger was on the entity's body, false for a near miss.
	var direct := false

	func is_hit() -> bool:
		return kind != Kind.NONE


class TerrainHit:
	extends RefCounted
	var tile := Vector2i.ZERO
	var position := Vector3.ZERO
	var distance := 0.0
	var is_water := false
	var is_side := false


## What is under `screen` (viewport units)?
## `shape_for`: Callable(entity_id) -> Vector2(height, radius), or null to skip.
## `touch_radius`: forgiveness around the finger, in viewport units.
static func pick(screen: Vector2, rig: CameraRig, world: WorldData, spatial: SpatialIndex,
		shape_for: Callable, touch_radius: float, kind_mask: int = SpatialIndex.KIND_ALL) -> Result:
	var result := Result.new()
	var ray := rig.screen_ray(screen)
	var hit := raycast_terrain(world, ray[0], ray[1])
	if hit == null:
		return result
	result.kind = Kind.WATER if hit.is_water else Kind.TILE
	result.tile = hit.tile
	result.position = hit.position

	if spatial == null or not shape_for.is_valid():
		return result
	var entity := _pick_entity(screen, rig, world, spatial, shape_for, touch_radius, kind_mask, ray, hit)
	if not entity.is_empty():
		result.kind = Kind.ENTITY
		result.entity_id = entity["id"]
		result.entity_kind = entity["kind"]
		result.direct = entity["direct"]
		result.tile = WorldCoords.world2d_to_tile(spatial.get_position(result.entity_id))
	return result


## First terrain (or water) surface the ray meets inside the box, or null.
static func raycast_terrain(world: WorldData, origin: Vector3, direction: Vector3, max_distance: float = 4096.0) -> TerrainHit:
	var dir := direction.normalized()
	var b := world.bounds
	if b.size.x <= 0 or b.size.y <= 0:
		return null
	# Clip the ray to the box footprint on the XZ plane.
	var t0 := 0.0
	var t1 := max_distance
	for axis in 2:
		var o := origin.x if axis == 0 else origin.z
		var d := dir.x if axis == 0 else dir.z
		var lo := float(b.position.x if axis == 0 else b.position.y)
		var hi := float(b.end.x if axis == 0 else b.end.y)
		if absf(d) < 0.0000001:
			if o < lo or o >= hi:
				return null
		else:
			var ta := (lo - o) / d
			var tb := (hi - o) / d
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
	if t0 > t1:
		return null

	var step := world.height_step
	var t := t0
	var start := origin + dir * (t0 + 0.00001)
	var tile := Vector2i(
		clampi(floori(start.x), b.position.x, b.end.x - 1),
		clampi(floori(start.z), b.position.y, b.end.y - 1))
	var step_x := 1 if dir.x > 0.0 else -1
	var step_z := 1 if dir.z > 0.0 else -1
	var t_delta_x := absf(1.0 / dir.x) if absf(dir.x) > 0.0000001 else INF
	var t_delta_z := absf(1.0 / dir.z) if absf(dir.z) > 0.0000001 else INF
	var next_x := float(tile.x + (1 if step_x > 0 else 0))
	var next_z := float(tile.y + (1 if step_z > 0 else 0))
	var t_max_x := (next_x - origin.x) / dir.x if t_delta_x != INF else INF
	var t_max_z := (next_z - origin.z) / dir.z if t_delta_z != INF else INF

	for i in b.size.x + b.size.y + 4:
		var t_exit := minf(minf(t_max_x, t_max_z), t1)
		var y_enter := origin.y + dir.y * t
		var y_exit := origin.y + dir.y * t_exit
		var chunk := world.chunk_at_tile(tile)
		if chunk != null:
			var idx := world.index_at_tile(tile)
			var depth := chunk.water[idx]
			var wet := depth > WaterMesher.MIN_DEPTH
			var surface := chunk.height[idx] * step + (depth if wet else 0.0)
			if minf(y_enter, y_exit) <= surface:
				var hit := TerrainHit.new()
				hit.tile = tile
				hit.is_water = wet
				if y_enter <= surface:
					# Entered this block below its top: the ray struck its side.
					hit.distance = t
					hit.is_side = true
				else:
					hit.distance = (surface - origin.y) / dir.y
				hit.position = origin + dir * hit.distance
				return hit
		if t_exit >= t1:
			break
		if t_max_x < t_max_z:
			tile.x += step_x
			t = t_max_x
			t_max_x += t_delta_x
		else:
			tile.y += step_z
			t = t_max_z
			t_max_z += t_delta_z
		if not b.has_point(tile):
			break
	return null


## Priority rank of a kind bit: 0 is most preferred.
static func priority_of(kind: int) -> int:
	for i in PRIORITY.size():
		if (kind & PRIORITY[i]) != 0:
			return i
	return PRIORITY.size()


static func _pick_entity(screen: Vector2, rig: CameraRig, world: WorldData, spatial: SpatialIndex,
		shape_for: Callable, touch_radius: float, kind_mask: int, ray: Array[Vector3], hit: TerrainHit) -> Dictionary:
	var origin := ray[0]
	var dir := ray[1]
	# Entities whose tops can reach the ray stand on the ground between the hit
	# and a point `reach` back toward the camera.
	var horizontal := Vector2(dir.x, dir.z)
	var slope := horizontal.length() / maxf(absf(dir.y), 0.05)
	var reach := MAX_ENTITY_HEIGHT * slope
	var units_per_px := rig.world_units_per_screen_unit(hit.position)
	var touch_world := touch_radius * units_per_px
	var back := horizontal.normalized() * (-reach * 0.5) if horizontal.length() > 0.0001 else Vector2.ZERO
	var center := Vector2(hit.position.x, hit.position.z) + back
	var candidates := spatial.query_radius(center, reach * 0.5 + touch_world + 1.5, kind_mask)

	var best: Dictionary = {}
	var best_score: Array = []
	for id in candidates:
		var shape: Variant = shape_for.call(id)
		if typeof(shape) != TYPE_VECTOR2:
			continue
		var pos2 := spatial.get_position(id)
		var ground := world.get_height(WorldCoords.world2d_to_tile(pos2)) * world.height_step
		var base := Vector3(pos2.x, ground, pos2.y)
		var top := base + Vector3(0.0, (shape as Vector2).x, 0.0)
		# Hidden behind nearer terrain?
		if origin.distance_to(base) > hit.distance + (shape as Vector2).x + 1.0:
			continue
		var a := rig.world_to_screen(base)
		var c := rig.world_to_screen(top)
		if a == Vector2.INF or c == Vector2.INF:
			continue
		var body_px := (shape as Vector2).y / maxf(rig.world_units_per_screen_unit(base), 0.000001)
		var distance := _distance_to_segment(screen, a, c)
		var direct := distance <= body_px
		if not direct and distance > body_px + touch_radius:
			continue
		var kind := spatial.get_kind(id)
		# Direct hits first; then by kind priority; then nearest; then lowest id.
		var score := [0 if direct else 1, priority_of(kind), distance, id]
		if best.is_empty() or score < best_score:
			best_score = score
			best = {"id": id, "kind": kind, "direct": direct}
	return best


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
	return p.distance_to(a + ab * t)
