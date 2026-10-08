class_name WaterPaths
extends RefCounted
## Ways over the water for a boat (FB3, bible §18.2a): a search over the tiles
## deep enough for its draught — not onto land, not over ice, not with a mast
## under a bridge. Ways found are kept until the water changes (cleared each
## day, and when a flood comes or goes).

## The most tiles a search looks at before it gives up.
const MAX_NODES := 6000
const DIAGONAL := 1.41421356
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
## Ways kept at most (the oldest forgotten first).
const CACHE_SIZE := 64

## Callable(tile: Vector2i) -> bool: ice there (no boat goes over it).
var is_ice: Callable
## Callable(tile: Vector2i) -> bool: a bridge there (a mast does not pass under).
var is_bridge: Callable

var _world: WorldData
var _cache: Dictionary = {} # key -> Array[Vector2i]


func bind(world: WorldData) -> void:
	_world = world
	_cache.clear()


## The water changed: the ways kept may no longer be.
func clear_cache() -> void:
	_cache.clear()


## Can a boat of this draught (and mast) be on `tile`?
func can_float(tile: Vector2i, draught: float, mast: bool = false) -> bool:
	if _world == null or not _world.is_in_bounds(tile) or _world.get_water(tile) < draught:
		return false
	if is_ice.is_valid() and bool(is_ice.call(tile)):
		return false
	return not (mast and is_bridge.is_valid() and bool(is_bridge.call(tile)))


## The water a boat can be on nearest `tile` (itself if it can), within
## `reach` tiles — null if none.
func water_near(tile: Vector2i, draught: float, reach: int = 2, mast: bool = false) -> Variant:
	if can_float(tile, draught, mast):
		return tile
	var best: Variant = null
	var best_d := INF
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var at := tile + Vector2i(dx, dy)
			var d := Vector2(dx, dy).length_squared()
			if d < best_d and can_float(at, draught, mast):
				best = at
				best_d = d
	return best


## The way over the water from `from` to `to` (both included), tile by tile;
## empty if there is none (or either end is not water the boat floats on).
func find(from: Vector2i, to: Vector2i, draught: float, mast: bool = false) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not can_float(from, draught, mast) or not can_float(to, draught, mast):
		return out
	if from == to:
		out.append(from)
		return out
	var key := "%d,%d>%d,%d@%d%s" % [from.x, from.y, to.x, to.y, roundi(draught * 100.0), "m" if mast else ""]
	if _cache.has(key):
		out.assign(_cache[key])
		return out
	var came: Dictionary = {from: from}
	var cost: Dictionary = {from: 0.0}
	var open := _Heap.new()
	open.push(from, _guess(from, to))
	var looked := 0
	while not open.is_empty():
		var here: Vector2i = open.pop()
		if here == to:
			break
		looked += 1
		if looked > MAX_NODES:
			return out
		var here_cost: float = cost[here]
		for step in NEIGHBOURS:
			var next := here + step
			var diagonal := step.x != 0 and step.y != 0
			if not can_float(next, draught, mast):
				continue
			# (Not across a corner of land.)
			if diagonal and (not can_float(here + Vector2i(step.x, 0), draught, mast) or not can_float(here + Vector2i(0, step.y), draught, mast)):
				continue
			var next_cost := here_cost + (DIAGONAL if diagonal else 1.0)
			if next_cost < float(cost.get(next, INF)):
				cost[next] = next_cost
				came[next] = here
				open.push(next, next_cost + _guess(next, to))
	if not came.has(to):
		return out
	var at := to
	while at != from:
		out.append(at)
		at = came[at]
	out.append(from)
	out.reverse()
	if _cache.size() >= CACHE_SIZE:
		_cache.erase(_cache.keys()[0])
	_cache[key] = out.duplicate()
	return out


## A way as points to steer by (tile middles; the ends as given).
static func points_of(way: Array[Vector2i], from: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(from)
	for i in range(1, way.size() - 1):
		points.append(Vector2(way[i]) + Vector2(0.5, 0.5))
	points.append(to)
	return points


static func _guess(a: Vector2i, b: Vector2i) -> float:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return maxi(dx, dy) + (DIAGONAL - 1.0) * mini(dx, dy)


## A small binary heap of tiles by priority (the least first).
class _Heap:
	extends RefCounted
	var _tiles: Array[Vector2i] = []
	var _keys: PackedFloat32Array = PackedFloat32Array()

	func is_empty() -> bool:
		return _tiles.is_empty()

	func push(tile: Vector2i, key: float) -> void:
		_tiles.append(tile)
		_keys.append(key)
		var i := _tiles.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if _keys[parent] <= _keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Vector2i:
		var top := _tiles[0]
		var last := _tiles.size() - 1
		_swap(0, last)
		_tiles.resize(last)
		_keys.resize(last)
		var i := 0
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var least := i
			if left < last and _keys[left] < _keys[least]:
				least = left
			if right < last and _keys[right] < _keys[least]:
				least = right
			if least == i:
				break
			_swap(i, least)
			i = least
		return top

	func _swap(a: int, b: int) -> void:
		var tile := _tiles[a]
		_tiles[a] = _tiles[b]
		_tiles[b] = tile
		var key := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
