class_name Traffic
extends RefCounted
## Footfall (bible §17.3, M12.2): every tile people walk onto is counted.
## Once a game day what was walked is added to what the tile remembers of
## being walked, and the memory fades. Grass walked enough is worn to a path
## (ChunkData.Terrain.ROAD — open ground the pathfinder prefers, so a path
## draws more feet to it); a path nobody walks any more grows over again.
## (Bridges are wanted where land near the fire is cut off by water — the
## settlement planner's crossing — not where a ford is waded: M12 follow-up.)
##
## Roads proper (laid, not worn) come with technology (M18).

## A tile has become a path (`path` true) or grown over again (false).
signal worn(tile: Vector2i, path: bool)

## What a path may be worn into, and what it was before (to grow back to).
const WEARS: Array[int] = [ChunkData.Terrain.GRASS, ChunkData.Terrain.DIRT]

var _world: WorldData
var _props: PropRegistry
var _config: ConstructionConfig
var _fresh: Dictionary = {} # tile -> steps since the day began
var _level: Dictionary = {} # tile -> footfall remembered (fades daily)
var _was: Dictionary = {} # path tile -> the terrain it was worn from
var _day := -1_000_000
## For the debug overlay and the soak.
var paths_worn := 0
var paths_gone := 0


func bind(world: WorldData, props: PropRegistry, now: int, config: ConstructionConfig = null) -> void:
	_world = world
	_props = props
	_config = config if config != null else Config.construction
	_fresh.clear()
	_level.clear()
	_was.clear()
	_day = Config.time.day_index(now)
	paths_worn = 0
	paths_gone = 0


## Someone has walked onto `tile` (MovementSystem calls this for every step).
func add(tile: Vector2i) -> void:
	_fresh[tile] = int(_fresh.get(tile, 0)) + 1


## How much the tile has been walked of late (the day's steps not yet counted in).
func level(tile: Vector2i) -> float:
	return float(_level.get(tile, 0.0))


func is_path(tile: Vector2i) -> bool:
	return _was.has(tile)


func path_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tile: Vector2i in _was:
		out.append(tile)
	out.sort()
	return out


## Water one wades through (not a wet patch, not too deep to cross on foot).
func is_ford(tile: Vector2i) -> bool:
	if _world == null or not _world.is_in_bounds(tile):
		return false
	var depth := _world.get_water(tile)
	return depth > Pathfinder.WET_DEPTH and depth <= Pathfinder.WADE_DEPTH * _world.height_step


## Once a game day: the day's steps are counted in, the memory fades, paths
## are worn and grow over.
func advance_to(now: int) -> void:
	if _world == null:
		return
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	var days := mini(today - _day, 30)
	_day = today
	var fade := pow(_config.footfall_kept_per_day, days)
	for tile: Vector2i in _fresh:
		_level[tile] = float(_level.get(tile, 0.0)) + float(_fresh[tile])
	_fresh.clear()
	var tiles: Array = _level.keys()
	tiles.sort()
	for tile: Vector2i in tiles:
		var walked := float(_level[tile]) * fade
		if walked < 0.05 and not _was.has(tile):
			_level.erase(tile)
			continue
		_level[tile] = walked
		if not _was.has(tile) and walked >= _config.path_from:
			_wear(tile)
		elif _was.has(tile) and walked < _config.path_gone:
			_grow_over(tile)
	# (What has stopped being a path some other way — tilled, washed away.)
	for tile: Vector2i in _was.keys():
		if _world.get_terrain(tile) != ChunkData.Terrain.ROAD:
			_was.erase(tile)


func _wear(tile: Vector2i) -> void:
	var terrain := _world.get_terrain(tile)
	if not WEARS.has(terrain) or _world.get_water(tile) > 0.0 or (_props != null and _props.prop_at(tile) != null):
		return
	_was[tile] = terrain
	_world.set_terrain(tile, ChunkData.Terrain.ROAD)
	paths_worn += 1
	worn.emit(tile, true)


func _grow_over(tile: Vector2i) -> void:
	var was: int = _was[tile]
	_was.erase(tile)
	if _world.get_terrain(tile) == ChunkData.Terrain.ROAD:
		_world.set_terrain(tile, was as ChunkData.Terrain)
	paths_gone += 1
	worn.emit(tile, false)


func debug_text() -> String:
	return "traffic: %d tiles walked, %d paths (%d worn, %d grown over)" % [_level.size(), _was.size(), paths_worn, paths_gone]


# --- saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var walked := PackedInt32Array()
	var levels := PackedFloat32Array()
	var tiles: Array = _level.keys()
	tiles.sort()
	for tile: Vector2i in tiles:
		walked.append_array([tile.x, tile.y])
		levels.append(float(_level[tile]) + float(_fresh.get(tile, 0)))
	for tile: Vector2i in _fresh:
		if not _level.has(tile):
			walked.append_array([tile.x, tile.y])
			levels.append(float(_fresh[tile]))
	var paths := PackedInt32Array()
	for tile in path_tiles():
		paths.append_array([tile.x, tile.y, int(_was[tile])])
	return {"day": _day, "tiles": walked, "levels": levels, "paths": paths, "worn": paths_worn, "gone": paths_gone}


func from_dict(data: Dictionary) -> void:
	_fresh.clear()
	_level.clear()
	_was.clear()
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	var tiles: Variant = data.get("tiles")
	var levels: Variant = data.get("levels")
	if typeof(tiles) == TYPE_PACKED_INT32_ARRAY and typeof(levels) == TYPE_PACKED_FLOAT32_ARRAY \
			and (tiles as PackedInt32Array).size() == (levels as PackedFloat32Array).size() * 2:
		for i in (levels as PackedFloat32Array).size():
			var walked: float = levels[i]
			if is_finite(walked) and walked > 0.0:
				_level[Vector2i(tiles[i * 2], tiles[i * 2 + 1])] = walked
	var paths: Variant = data.get("paths")
	if typeof(paths) == TYPE_PACKED_INT32_ARRAY and (paths as PackedInt32Array).size() % 3 == 0:
		for i in (paths as PackedInt32Array).size() / 3:
			var tile := Vector2i(paths[i * 3], paths[i * 3 + 1])
			if WEARS.has(paths[i * 3 + 2]) and _world != null and _world.get_terrain(tile) == ChunkData.Terrain.ROAD:
				_was[tile] = paths[i * 3 + 2]
	paths_worn = maxi(int(data.get("worn", 0)), 0)
	paths_gone = maxi(int(data.get("gone", 0)), 0)
