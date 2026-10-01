class_name Pathfinder
extends RefCounted
## Finds ways across the world on foot (bible §13.7).
##
## The world is a graph of tiles (Godot's AStar2D): every tile is a point,
## and two neighbouring tiles are joined where a person can step from one to
## the other — the land rises in steps, and a step of more than one level is a
## cliff. Deep water and buildings cannot be stood on; wading, slopes,
## undergrowth and things lying in the way make a tile slower, so paths go
## around them when that is shorter in time.
##
## The graph follows the world: tiles that change (water rising, a tree
## felled, a boulder dropped) are re-examined one by one, never the whole map.
## Paths can be asked for at once (find_path) or queued (request) and served
## within a time budget per frame; answers are remembered until the graph
## changes.

## A person can wade through water up to this deep (in height levels).
const WADE_DEPTH := WorldSetup.WADE_DEPTH_LEVELS
## Water shallower than this is a wet patch, not something to wade through.
const WET_DEPTH := 0.02
const WEIGHT_WADING := 3.0
const WEIGHT_SLOPE := 0.35
const WEIGHT_TREE := 3.0
const WEIGHT_BUSH := 1.5
## A boulder or a log lying on the tile.
const WEIGHT_OBSTACLE := 7.0
const TERRAIN_WEIGHT := {
	ChunkData.Terrain.ROAD: 0.7,
	ChunkData.Terrain.SAND: 1.2,
	ChunkData.Terrain.ROCK: 1.15,
	ChunkData.Terrain.MUD: 1.6,
	ChunkData.Terrain.SNOW: 1.7,
	ChunkData.Terrain.RIVERBED: 1.3,
}
const CACHE_SIZE := 256
## How far from a tile that cannot be stood on a stand-in is looked for.
const NEAR_RADIUS := 3

const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
# Water as the graph sees it.
const _DRY := 0
const _WADE := 1
const _DEEP := 2


class Request:
	extends RefCounted
	var id := 0
	var from := Vector2i.ZERO
	var to := Vector2i.ZERO
	var on_done: Callable


## Goes up whenever the graph changes (a cached or half-walked path made
## before that may no longer be good).
var version := 0
## For the debug overlay.
var paths_found := 0
var cache_hits := 0
var last_serve_usec := 0
var last_path_usec := 0
var tiles_updated := 0

var _world: WorldData
var _props: PropRegistry
var _loose: LooseObjectRegistry
var _water: WaterSim
var _astar := AStar2D.new()
var _bounds := Rect2i()
var _width := 0
# What the graph was built from, per tile: to tell whether a change matters.
var _solid := PackedByteArray()
var _weight := PackedFloat32Array()
var _height := PackedInt32Array()
var _water_class := PackedByteArray()
var _prop_kind := PackedByteArray() # PropData.Kind + 1, 0 = nothing
var _dirty: Dictionary = {} # tile -> true
var _obstacles: Dictionary = {} # tile -> how many boulders / logs lie on it
var _obstacle_tile: Dictionary = {} # object id -> tile
var _cache: Dictionary = {} # key -> [version, Array[Vector2i]]
var _shore: Array[Vector2i] = []
var _shore_version := -1
var _queue: Array[Request] = []
var _next_request := 1


## Builds the graph of `world`. `props` and `loose` (optional) are what stands
## and lies in the way; `water` (optional) reports where water moves.
func bind(world: WorldData, props: PropRegistry = null, loose: LooseObjectRegistry = null, water: WaterSim = null) -> void:
	unbind()
	_world = world
	_props = props
	_loose = loose
	_water = water
	if world == null:
		return
	world.ground_changed.connect(mark_dirty)
	if props != null:
		props.chunk_changed.connect(_on_props_changed)
	if loose != null:
		loose.object_added.connect(_on_object_changed)
		loose.object_moved.connect(_on_object_changed)
		loose.object_removed.connect(_on_object_removed)
	if water != null:
		water.tiles_changed.connect(_on_water_changed)
	rebuild()


func unbind() -> void:
	if _world != null:
		_world.ground_changed.disconnect(mark_dirty)
	if _props != null:
		_props.chunk_changed.disconnect(_on_props_changed)
	if _loose != null:
		_loose.object_added.disconnect(_on_object_changed)
		_loose.object_moved.disconnect(_on_object_changed)
		_loose.object_removed.disconnect(_on_object_removed)
	if _water != null:
		_water.tiles_changed.disconnect(_on_water_changed)
	_world = null
	_props = null
	_loose = null
	_water = null
	_astar.clear()
	_dirty.clear()
	_cache.clear()
	_queue.clear()
	_obstacles.clear()
	_obstacle_tile.clear()
	_width = 0
	_bounds = Rect2i()


## Builds the whole graph from the world as it is now.
func rebuild() -> void:
	_bounds = _world.bounds
	_width = _bounds.size.x
	var count := _bounds.size.x * _bounds.size.y
	_astar.clear()
	_astar.reserve_space(count)
	_solid.resize(count)
	_weight.resize(count)
	_height.resize(count)
	_water_class.resize(count)
	_prop_kind.resize(count)
	_obstacles.clear()
	_obstacle_tile.clear()
	if _loose != null:
		for object in _loose.all_objects():
			if _is_obstacle(object):
				_obstacle_tile[object.id] = object.tile()
				_obstacles[object.tile()] = int(_obstacles.get(object.tile(), 0)) + 1
	# Read the whole world once, chunk by chunk (straight from the chunk arrays:
	# this runs for every tile of the box whenever a world is opened).
	var deep := WADE_DEPTH * _world.height_step
	var size := _world.chunk_size
	var hut := PropData.Kind.HUT + 1
	var fire := PropData.Kind.CAMPFIRE + 1
	var ruin := PropData.Kind.RUIN + 1
	for coord in _world.chunk_coords():
		var chunk := _world.get_chunk(coord)
		var origin := WorldCoords.chunk_origin(coord, size)
		for ly in size:
			var row := (origin.y + ly - _bounds.position.y) * _width - _bounds.position.x
			for lx in size:
				var x := origin.x + lx
				if x < _bounds.position.x or x >= _bounds.end.x or origin.y + ly < _bounds.position.y or origin.y + ly >= _bounds.end.y:
					continue
				var i := ly * size + lx
				var id := row + x
				var depth := chunk.water[i]
				var water := _DEEP if depth > deep else (_WADE if depth > WET_DEPTH else _DRY)
				var kind := _kind_at(Vector2i(x, origin.y + ly))
				_height[id] = chunk.height[i]
				_water_class[id] = water
				_prop_kind[id] = kind
				_solid[id] = 1 if water == _DEEP or kind == hut or kind == fire or kind == ruin else 0
				_astar.add_point(id, Vector2(x + 0.5, origin.y + ly + 0.5), 1.0)
	var height := _bounds.size.y
	for id in count:
		var tile := _tile(id)
		_weight[id] = _weigh(tile, id)
		_astar.set_point_weight_scale(id, _weight[id])
		if _solid[id] == 1:
			_astar.set_point_disabled(id, true)
		if _water_class[id] == _DEEP:
			continue # nothing leads into deep water
		# Each pair once: towards +X, +Y and the two diagonals that go +Y.
		var x := id % _width
		@warning_ignore("integer_division")
		var y := id / _width
		var level := _height[id]
		var right := x + 1 < _width and _water_class[id + 1] != _DEEP and absi(_height[id + 1] - level) <= WorldSetup.MAX_STEP_LEVELS
		var left := x > 0 and _water_class[id - 1] != _DEEP and absi(_height[id - 1] - level) <= WorldSetup.MAX_STEP_LEVELS
		if right:
			_astar.connect_points(id, id + 1)
		if y + 1 >= height:
			continue
		var below := id + _width
		var down := _water_class[below] != _DEEP and absi(_height[below] - level) <= WorldSetup.MAX_STEP_LEVELS
		if down:
			_astar.connect_points(id, below)
		# A diagonal needs both tiles it passes between to be passable too.
		if right and down and _solid[id + 1] == 0 and _solid[below] == 0 and _diagonal_ok(id, below + 1, id + 1, below):
			_astar.connect_points(id, below + 1)
		if left and down and _solid[id - 1] == 0 and _solid[below] == 0 and _diagonal_ok(id, below - 1, id - 1, below):
			_astar.connect_points(id, below - 1)
	_dirty.clear()
	_cache.clear()
	version += 1


# --- questions (always answered for the world as it is now) -------------------------------------

func is_bound() -> bool:
	return _world != null


## Is this a tile of the world the graph was built for?
func has_tile(tile: Vector2i) -> bool:
	return _world != null and _bounds.has_point(tile)


## Can a person stand on this tile?
func can_stand(tile: Vector2i) -> bool:
	refresh_dirty()
	return _bounds.has_point(tile) and _solid[_id(tile)] == 0


## Can a person step from `from` to the neighbouring tile `to`?
func can_step(from: Vector2i, to: Vector2i) -> bool:
	if not _bounds.has_point(from) or not can_stand(to):
		return false
	return _astar.are_points_connected(_id(from), _id(to))


## How hard the tile is to cross (1 = open ground; higher = slower).
func weight_at(tile: Vector2i) -> float:
	refresh_dirty()
	return _weight[_id(tile)] if _bounds.has_point(tile) else INF


## How fast one walks into this tile, as a fraction of walking on open ground.
func speed_factor(tile: Vector2i) -> float:
	return clampf(1.0 / weight_at(tile), 0.35, 1.3)


## The way from `from` to `to`, tile by tile, both ends included. If `to`
## cannot be stood on (a hut, a tree in deep water, ...) the way leads to a
## tile beside it. Empty if there is no way; [from] if already there.
func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if _world == null or not _bounds.has_point(from) or not _bounds.has_point(to):
		return empty
	refresh_dirty()
	var started := Time.get_ticks_usec()
	var from_id := _id(from)
	var path := empty
	for goal in _goals_for(from, to):
		var key := (from_id << 32) | _id(goal)
		var cached: Array = _cache.get(key, [])
		if not cached.is_empty() and cached[0] == version:
			cache_hits += 1
			path = cached[1]
		else:
			path = _search(from_id, _id(goal))
			_remember(key, path)
		if not path.is_empty():
			break
	last_path_usec = Time.get_ticks_usec() - started
	return path.duplicate()


func is_reachable(from: Vector2i, to: Vector2i) -> bool:
	return not find_path(from, to).is_empty()


## What walking a path costs: its length in tiles, each step counted at the
## weight of the tile stepped onto.
func path_cost(path: Array[Vector2i]) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += Vector2(path[i] - path[i - 1]).length() * weight_at(path[i])
	return total


## Up to `count` different tiles people can stand on, nearest to `tile` first
## (the tile itself included, if it can be stood on).
func standable_near(tile: Vector2i, count: int, radius: int = 6) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var other := tile + Vector2i(dx, dy)
			if can_stand(other) and weight_at(other) < WEIGHT_OBSTACLE:
				found.append(other)
	found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - tile).length_squared()
		var db := (b - tile).length_squared()
		return da < db or (da == db and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	if found.size() > count:
		found.resize(count)
	return found


## Water one can drink from: tiles of water with dry ground to stand on
## beside them. Remembered until the graph changes.
func shore_tiles() -> Array[Vector2i]:
	refresh_dirty()
	if _shore_version == version:
		return _shore
	_shore_version = version
	_shore.clear()
	var height := _bounds.size.y
	for id in _width * height:
		if _water_class[id] == _DRY:
			continue
		var x := id % _width
		@warning_ignore("integer_division")
		var y := id / _width
		if (x > 0 and _dry_stand(id - 1)) or (x + 1 < _width and _dry_stand(id + 1)) \
				or (y > 0 and _dry_stand(id - _width)) or (y + 1 < height and _dry_stand(id + _width)):
			_shore.append(_tile(id))
	return _shore


func _dry_stand(id: int) -> bool:
	return _solid[id] == 0 and _water_class[id] == _DRY


# --- queue --------------------------------------------------------------------------------------

## Asks for a path to be found when there is time (see serve). `on_done` is
## called with the path (as find_path returns it). Returns the request's id.
func request(from: Vector2i, to: Vector2i, on_done: Callable) -> int:
	var asked := Request.new()
	asked.id = _next_request
	_next_request += 1
	asked.from = from
	asked.to = to
	asked.on_done = on_done
	_queue.append(asked)
	return asked.id


## Withdraws a request that has not been served yet.
func cancel(request_id: int) -> bool:
	for i in _queue.size():
		if _queue[i].id == request_id:
			_queue.remove_at(i)
			return true
	return false


func queue_size() -> int:
	return _queue.size()


## Brings the graph up to date and answers queued requests, oldest first,
## until `budget_usec` is used up (at least one request is always answered,
## so the queue cannot stall). Returns how many were answered.
func serve(budget_usec: int = 1000) -> int:
	if _world == null:
		return 0
	var started := Time.get_ticks_usec()
	refresh_dirty()
	var served := 0
	while not _queue.is_empty():
		var asked: Request = _queue.pop_front()
		var path := find_path(asked.from, asked.to)
		served += 1
		if asked.on_done.is_valid():
			asked.on_done.call(path)
		if Time.get_ticks_usec() - started >= budget_usec:
			break
	last_serve_usec = Time.get_ticks_usec() - started
	return served


# --- keeping up with the world ------------------------------------------------------------------

## The tile may have changed (ground, water, what stands or lies on it).
func mark_dirty(tile: Vector2i) -> void:
	if _bounds.has_point(tile):
		_dirty[tile] = true


func dirty_count() -> int:
	return _dirty.size()


## Re-examines the tiles that may have changed. Returns how many did.
func refresh_dirty() -> int:
	if _dirty.is_empty():
		return 0
	var changed := 0
	var tiles: Array = _dirty.keys()
	_dirty.clear()
	for tile: Vector2i in tiles:
		if _update_tile(tile):
			changed += 1
	if changed > 0:
		version += 1
		tiles_updated += changed
	return changed


func _on_props_changed(coord: Vector2i) -> void:
	# The registry says which chunk, not which tile: find what is different.
	var origin := WorldCoords.chunk_origin(coord, _world.chunk_size)
	for ly in _world.chunk_size:
		for lx in _world.chunk_size:
			var tile := origin + Vector2i(lx, ly)
			if _bounds.has_point(tile) and _prop_kind[_id(tile)] != _kind_at(tile):
				_dirty[tile] = true


func _on_water_changed(tiles: Array[Vector2i]) -> void:
	for tile in tiles:
		if _bounds.has_point(tile) and _water_class[_id(tile)] != _water_at(tile):
			_dirty[tile] = true


func _on_object_changed(id: int) -> void:
	var object := _loose.get_object(id)
	if object == null or not _is_obstacle(object):
		return
	var now := object.tile()
	var before: Variant = _obstacle_tile.get(id)
	if before != null and before == now:
		return
	if before != null:
		_lift_obstacle(before)
	_obstacle_tile[id] = now
	_obstacles[now] = int(_obstacles.get(now, 0)) + 1
	mark_dirty(now)


func _on_object_removed(id: int) -> void:
	var before: Variant = _obstacle_tile.get(id)
	if before != null:
		_obstacle_tile.erase(id)
		_lift_obstacle(before)


func _lift_obstacle(tile: Vector2i) -> void:
	var left := int(_obstacles.get(tile, 0)) - 1
	if left > 0:
		_obstacles[tile] = left
	else:
		_obstacles.erase(tile)
	mark_dirty(tile)


static func _is_obstacle(object: LooseObject) -> bool:
	return object.kind == LooseObject.Kind.BOULDER or object.kind == LooseObject.Kind.LOG


# --- internals ----------------------------------------------------------------------------------

func _id(tile: Vector2i) -> int:
	return (tile.y - _bounds.position.y) * _width + (tile.x - _bounds.position.x)


func _tile(id: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(id % _width + _bounds.position.x, id / _width + _bounds.position.y)


func _kind_at(tile: Vector2i) -> int:
	var prop := _props.prop_at(tile) if _props != null else null
	return prop.kind + 1 if prop != null else 0


func _water_at(tile: Vector2i) -> int:
	var depth := _world.get_water(tile)
	if depth > WADE_DEPTH * _world.height_step:
		return _DEEP
	return _WADE if depth > WET_DEPTH else _DRY


## Reads what decides whether a tile can be stood on and how it joins its
## neighbours. True if any of it differs from what the graph was built from.
func _read(tile: Vector2i, id: int) -> bool:
	var height := _world.get_height(tile)
	var water := _water_at(tile)
	var kind := _kind_at(tile)
	var solid := 1 if water == _DEEP or kind == PropData.Kind.HUT + 1 or kind == PropData.Kind.CAMPFIRE + 1 \
		or kind == PropData.Kind.RUIN + 1 else 0
	var changed := _height[id] != height or _solid[id] != solid
	_height[id] = height
	_water_class[id] = water
	_prop_kind[id] = kind
	_solid[id] = solid
	return changed


func _weigh(tile: Vector2i, id: int) -> float:
	var weight: float = TERRAIN_WEIGHT.get(_world.get_terrain(tile), 1.0)
	if _water_class[id] == _WADE:
		weight += WEIGHT_WADING
	match _prop_kind[id] - 1:
		PropData.Kind.TREE:
			weight += WEIGHT_TREE
		PropData.Kind.BUSH:
			weight += WEIGHT_BUSH
	if _obstacles.has(tile):
		weight += WEIGHT_OBSTACLE
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var other := tile + offset
		if _bounds.has_point(other) and _height[_id(other)] != _height[id]:
			weight += WEIGHT_SLOPE
			break
	return weight


## Is there a step between two neighbouring tiles? A straight step needs
## nearly level ground; a diagonal one also needs both tiles it passes
## between to be passable, so that nobody cuts through the corner of a hut or
## across the lip of a cliff.
func _edge_allowed(a: Vector2i, b: Vector2i) -> bool:
	var ia := _id(a)
	var ib := _id(b)
	if absi(_height[ia] - _height[ib]) > WorldSetup.MAX_STEP_LEVELS:
		return false
	if _water_class[ia] == _DEEP or _water_class[ib] == _DEEP:
		return false
	if a.x == b.x or a.y == b.y:
		return true
	for side: Vector2i in [Vector2i(a.x, b.y), Vector2i(b.x, a.y)]:
		var i := _id(side)
		if _solid[i] == 1 or absi(_height[i] - _height[ia]) > WorldSetup.MAX_STEP_LEVELS \
				or absi(_height[i] - _height[ib]) > WorldSetup.MAX_STEP_LEVELS:
			return false
	return true


## The height part of the diagonal rule, by point ids (see _edge_allowed).
func _diagonal_ok(a: int, b: int, side_1: int, side_2: int) -> bool:
	var step := WorldSetup.MAX_STEP_LEVELS
	return _water_class[b] != _DEEP and absi(_height[a] - _height[b]) <= step 		and absi(_height[side_1] - _height[b]) <= step and absi(_height[side_2] - _height[b]) <= step


## Brings one tile of the graph up to date. True if anything changed.
func _update_tile(tile: Vector2i) -> bool:
	var id := _id(tile)
	var structural := _read(tile, id)
	var changed := structural
	if structural:
		_astar.set_point_disabled(id, _solid[id] == 1)
		# Steps to and from the tile, and the diagonals that pass beside it.
		for offset in _NEIGHBOURS:
			_set_edge(tile, tile + offset)
		_set_edge(tile + Vector2i(-1, 0), tile + Vector2i(0, -1))
		_set_edge(tile + Vector2i(0, -1), tile + Vector2i(1, 0))
		_set_edge(tile + Vector2i(1, 0), tile + Vector2i(0, 1))
		_set_edge(tile + Vector2i(0, 1), tile + Vector2i(-1, 0))
	# The tile's weight, and (a slope is a difference to a neighbour) theirs.
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var other := tile + offset
		if not _bounds.has_point(other) or (offset != Vector2i.ZERO and not structural):
			continue
		var other_id := _id(other)
		var weight := _weigh(other, other_id)
		if weight != _weight[other_id]:
			_weight[other_id] = weight
			_astar.set_point_weight_scale(other_id, weight)
			changed = true
	return changed


func _set_edge(a: Vector2i, b: Vector2i) -> void:
	if not _bounds.has_point(a) or not _bounds.has_point(b):
		return
	var ia := _id(a)
	var ib := _id(b)
	var wanted := _edge_allowed(a, b)
	if wanted != _astar.are_points_connected(ia, ib):
		if wanted:
			_astar.connect_points(ia, ib)
		else:
			_astar.disconnect_points(ia, ib)


## Where to go for `to`: the tile itself, or — if it cannot be stood on — the
## tiles around it that can, those nearest to `from` first.
func _goals_for(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var goals: Array[Vector2i] = []
	if can_stand(to):
		goals.append(to)
		return goals
	for radius in range(1, NEAR_RADIUS + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) == radius and can_stand(to + Vector2i(dx, dy)):
					goals.append(to + Vector2i(dx, dy))
		if not goals.is_empty():
			break
	goals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - from).length_squared()
		var db := (b - from).length_squared()
		return da < db or (da == db and (a.x < b.x or (a.x == b.x and a.y < b.y))))
	if goals.size() > 4:
		goals.resize(4)
	return goals


func _search(from_id: int, goal_id: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	# Someone standing where nobody can stand (the ground changed under them)
	# may still walk away from it.
	var stuck := _solid[from_id] == 1
	if stuck:
		_astar.set_point_disabled(from_id, false)
	var ids := _astar.get_id_path(from_id, goal_id)
	if stuck:
		_astar.set_point_disabled(from_id, true)
	for id in ids:
		out.append(_tile(id))
	paths_found += 1
	return out


func _remember(key: int, path: Array[Vector2i]) -> void:
	if _cache.size() >= CACHE_SIZE:
		_cache.erase(_cache.keys()[0]) # the oldest
	_cache[key] = [version, path]
