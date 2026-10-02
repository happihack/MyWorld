class_name Hydrology
extends RefCounted
## How the river stands (bible §10.3, M9.3): the coarse side of the water.
##
## The river is one body of level water. Where its surface stands — `level`,
## above or below where it was made — follows the weather: every look at
## the sky (three game hours) it comes nearer to where the rain of the last
## days and the heat let it settle (springs and the ground give when it is
## low and take when it is high), and rain and melting snow raise it at
## once. So it rises after storms and in the thaw, and falls in dry weeks.
##
## What that means for the tiles is an **equilibrium**, not a flow: every
## tile joined to the river whose ground lies under the surface holds water
## up to the surface. A low river bares its banks; a high one spreads over
## the valley floor (a flood, if people live there). Nothing depends on the
## frame rate, and the water cannot run away: the level has bounds.
##
## The water that moves (`WaterSim`) is the fine side: what the player
## pours or scoops flows in real time; what it adds to or takes from the
## river is found in its level at the next look.

## The level was set anew on the tiles.
signal level_changed(level: float)
## The river stands at its banks' edge or over them / is back in its bed.
signal high_water_changed(active: bool)
## The banks lie dry / are under water again.
signal low_water_changed(active: bool)
## Where people live is under water (`tiles` settled tiles, around `at`) / no longer.
signal flood_changed(active: bool, tiles: int, at: Vector2)
## The river took a tile of its bank.
signal eroded(tile: Vector2i)
## The water has run off these tiles (they were under it, and are dry now).
signal drained(tiles: Array[Vector2i])

const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const _SALT_SPRING := 0x51A7
const _SALT_ERODE := 0x0E20
## The water moving (someone poured or scooped) puts the look at the tiles
## off — this many times at most.
const MAX_PUT_OFF := 2
## Changes of depth smaller than this are not written.
const EPSILON := 0.0005

## Where the river stands, in world units above (+) or below (−) where it was made.
var level := 0.0
## The level the tiles have.
var applied := 0.0
var high_water := false
var low_water := false
var flooded := false
## Water put on the tiles and taken from them since the world began (depth, summed over tiles).
var added_total := 0.0
var removed_total := 0.0
## Tiles of bank the river has taken.
var eroded_count := 0
## How many times the level was set on the tiles (debug, tests).
var applies := 0

## The tiles where people live (Callable() -> Array[Vector2i]); not set: nobody does.
var settled_source := Callable()
## Whether something stands on a tile (Callable(tile) -> bool) — the river does not take such a tile.
var occupied_source := Callable()
## Off: the river stands still whatever the weather (tests of other things).
var enabled := true

var _world: WorldData
var _water: WaterSim
var _weather: WeatherSystem
var _config: HydrologyConfig
var _seed := 0
var _surface := 0.0 # the height of the river's surface as it was made (world units)
var _core: Array[Vector2i] = [] # the riverbed
var _body: Dictionary = {} # tile -> true: where the river's water is
var _snow := 0.0 # the snow that lay at the last look
var _put_off := 0
var _last_look := 0
var _disturbed := false # the moving water has changed something since the level was set
var _syncing := false
var _settle_to := 0.0 # where it was settling at the last look (debug)
var _springs: Array[Vector2i] = []


## `surface`: the height of the river's surface as the world was made
## (world units; `WorldGenerator.water_surface_height()`).
func bind(world: WorldData, water: WaterSim, weather: WeatherSystem, config: HydrologyConfig, world_seed: int,
		surface: float) -> void:
	if _weather != null and _weather.stepped.is_connected(_on_stepped):
		_weather.stepped.disconnect(_on_stepped)
		_weather.caught_up.disconnect(_on_caught_up)
	if _water != null and _water.tiles_changed.is_connected(_on_water_moved):
		_water.tiles_changed.disconnect(_on_water_moved)
	_world = world
	_water = water
	_weather = weather
	_config = config
	_seed = world_seed
	_surface = surface
	level = 0.0
	applied = 0.0
	high_water = false
	low_water = false
	flooded = false
	added_total = 0.0
	removed_total = 0.0
	eroded_count = 0
	applies = 0
	_put_off = 0
	_settle_to = 0.0
	_snow = weather.snow_cover if weather != null else 0.0
	_find_core()
	_body = _spread(_surface + applied)
	_find_springs()
	_disturbed = false
	if _weather != null:
		_weather.stepped.connect(_on_stepped)
		_weather.caught_up.connect(_on_caught_up)
	if _water != null:
		_water.tiles_changed.connect(_on_water_moved)


# --- saving -------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"level": level, "applied": applied, "high": high_water, "low": low_water, "flooded": flooded, "snow": _snow,
		"added": added_total, "removed": removed_total, "eroded": eroded_count}


## Call after bind() (and after the weather has its saved state).
func from_dict(data: Dictionary) -> void:
	level = _number(data.get("level"), 0.0)
	applied = _number(data.get("applied"), 0.0)
	if _config != null:
		level = clampf(level, _config.lowest, _config.highest)
		applied = clampf(applied, _config.lowest, _config.highest)
	high_water = typeof(data.get("high")) == TYPE_BOOL and bool(data["high"])
	low_water = typeof(data.get("low")) == TYPE_BOOL and bool(data["low"])
	flooded = typeof(data.get("flooded")) == TYPE_BOOL and bool(data["flooded"])
	_snow = clampf(_number(data.get("snow"), _weather.snow_cover if _weather != null else 0.0), 0.0, 1.0)
	added_total = maxf(_number(data.get("added"), 0.0), 0.0)
	removed_total = maxf(_number(data.get("removed"), 0.0), 0.0)
	eroded_count = maxi(int(_number(data.get("eroded"), 0.0)), 0)
	_body = _spread(_surface + applied)


# --- what the river is ----------------------------------------------------------------------------------

## The height of the river's surface now (world units), as the tiles have it.
func surface() -> float:
	return _surface + applied


## How much of the moisture the land holds by itself is there now (1 = as
## the world was made): less beside a low river, a little more beside a high one.
func groundwater() -> float:
	if _config == null:
		return 1.0
	return clampf(1.0 + level * _config.groundwater_per_level, _config.groundwater_least, _config.groundwater_most)


## How fast soil dried on a day, compared with an ordinary one (1): by how warm it got.
func drying(day: int) -> float:
	if _config == null or _weather == null:
		return 1.0
	var warmest := _weather.warmest_on(day)
	if is_nan(warmest):
		return 1.0
	return clampf(warmest / _config.drying_normal_degrees, _config.drying_least, _config.drying_most)


## How strongly the river runs, compared with how it was made (1).
func flow() -> float:
	if _config == null:
		return 1.0
	return clampf(1.0 + level * _config.flow_per_level, _config.flow_least, _config.flow_most)


## Where the river's water is now.
func is_river(tile: Vector2i) -> bool:
	return _body.has(tile)


## How many tiles the river covers.
func body_size() -> int:
	return _body.size()


## The tiles of the riverbed.
func bed() -> Array[Vector2i]:
	return _core


## The springs in the riverbed (they feed it; where they are comes from the seed).
func springs() -> Array[Vector2i]:
	return _springs


## How many of the tiles where people live are under water.
func flooded_tiles() -> Array[Vector2i]:
	var under: Array[Vector2i] = []
	if _world == null or not settled_source.is_valid():
		return under
	for tile: Vector2i in settled_source.call():
		if _world.get_water(tile) >= _config.flood_depth:
			under.append(tile)
	return under


func debug_text() -> String:
	return "river: level %+.3f (tiles %+.2f, settling to %+.3f)  %d tiles  flow %.2f  groundwater %.2f%s%s%s\nwater put on %.1f, taken %.1f  bank tiles taken %d  springs %d" % [
		level, applied, _settle_to, _body.size(), flow(), groundwater(), "  HIGH WATER" if high_water else "",
		"  LOW WATER" if low_water else "", "  FLOOD" if flooded else "", added_total, removed_total, eroded_count, _springs.size()]


# --- time ---------------------------------------------------------------------------------------------

## The weather has looked at the sky: `hours` have passed up to `now`, under
## the weather there is now. The level moves; the tiles wait until the
## weather has caught up with the clock (after a long absence that is many
## looks at once: the tiles are set once, not a hundred times).
func _on_stepped(now: int, hours: float) -> void:
	if enabled:
		_last_look = now
		advance(now, hours)


func _on_caught_up() -> void:
	if enabled:
		settle(_last_look)


func _on_water_moved(_tiles: Array[Vector2i]) -> void:
	if not _syncing:
		_disturbed = true


## One look at the river: time passes for its level, and the tiles are
## set (tests call it directly).
func step(now: int, hours: float) -> void:
	advance(now, hours)
	settle(now)


## `hours` pass for the river's level, up to `now`, under the weather there is.
func advance(now: int, hours: float) -> void:
	if _world == null or _config == null or _weather == null or _core.is_empty():
		return
	# Where it settles: the rain of the last days, and the heat.
	var day := Config.time.day_index(now)
	var rain := 0.0
	for d in range(day - _config.rain_days + 1, day + 1):
		rain += _weather.rainfall_total(d, 1) if _weather.watched(d) else _config.normal_rain_per_day
	var wet := clampf(rain / (_config.normal_rain_per_day * _config.rain_days), 0.0, _config.wet_most)
	var frozen := _weather.is_frozen()
	var heat := 0.0
	if not frozen:
		heat = maxf(_weather.temperature(now) - _config.heat_from, 0.0) / 10.0 * (1.0 + _weather.wind_speed * _config.wind_factor)
	_settle_to = (_config.wet_span if wet >= 1.0 else _config.dry_span) * (wet - 1.0) - _config.heat_fall * heat
	var settle_hours := _config.settle_hours * (_config.frozen_slower if frozen else 1.0)
	level += (_settle_to - level) * (1.0 - exp(-hours / settle_hours))
	# What falls runs off the land into it; what melts too.
	if _weather.is_raining():
		level += _config.rain_rise * _weather.precipitation() * hours
	var snow := _weather.snow_cover
	if snow < _snow:
		level += _config.melt_rise * (_snow - snow)
	_snow = snow
	level = clampf(level, _config.lowest, _config.highest)
	if _water != null:
		_water.river_flow = flow()


## The level is set on the tiles, and what it means is judged.
func settle(now: int) -> void:
	if _world == null or _config == null or _weather == null or _core.is_empty():
		return
	var moving := _water != null and not _water.is_still()
	var stirred := false
	if not moving and _disturbed:
		_disturbed = false
		stirred = _take_stock()
		_water.river_flow = flow()
	# Not while the water is moving (it would be set over what is flowing).
	if moving and _put_off < MAX_PUT_OFF:
		_put_off += 1
	else:
		_put_off = 0
		apply(stirred) # (what was stirred up is laid level again)
	_judge(now)


## Sets the level on the tiles, if it has moved far enough (or `force`).
## Returns the tiles whose water changed.
func apply(force: bool = false) -> Array[Vector2i]:
	var changed: Array[Vector2i] = []
	if _world == null or _config == null:
		return changed
	var target := snappedf(level, _config.apply_step)
	if not force and absf(target - applied) < _config.apply_step * 0.5:
		return changed
	applied = target
	applies += 1
	var wet := _spread(_surface + applied)
	var height_step := _world.height_step
	var top := _surface + applied
	for tile: Vector2i in wet:
		_set_depth(tile, top - _world.get_height(tile) * height_step, changed, not _body.has(tile))
	var left: Array[Vector2i] = []
	for tile: Vector2i in _body:
		if not wet.has(tile):
			_set_depth(tile, 0.0, changed, false)
			left.append(tile)
	_body = wet
	if _water != null and not changed.is_empty():
		_syncing = true
		_water.sync(changed)
		_syncing = false
	if not left.is_empty():
		drained.emit(left)
	level_changed.emit(applied)
	return changed


# --- internals ----------------------------------------------------------------------------------------

## Every tile joined to the riverbed whose ground lies under `top`.
func _spread(top: float) -> Dictionary:
	var wet := {}
	if _world == null or _config == null:
		return wet
	var height_step := _world.height_step
	var seen := {}
	var queue: Array[Vector2i] = []
	for tile in _core:
		seen[tile] = true
		queue.append(tile)
	var head := 0
	while head < queue.size():
		var tile := queue[head]
		head += 1
		if top - _world.get_height(tile) * height_step < _config.least_depth:
			continue # (bared: the water does not go on from here)
		wet[tile] = true
		for offset in _DIRS:
			var next := tile + offset
			if seen.has(next) or not _world.bounds.has_point(next):
				continue
			seen[next] = true
			if top - _world.get_height(next) * height_step >= _config.least_depth:
				queue.append(next)
	return wet


func _set_depth(tile: Vector2i, depth: float, changed: Array[Vector2i], newly: bool) -> void:
	var chunk := _world.chunk_at_tile(tile)
	if chunk == null:
		return
	var i := _world.index_at_tile(tile)
	var before := chunk.water[i]
	if absf(depth - before) < EPSILON:
		return
	chunk.set_water(i, depth)
	if depth > before:
		added_total += depth - before
	else:
		removed_total += before - depth
	# Land the river comes over is soaked.
	if newly and depth > 0.0 and chunk.terrain[i] != ChunkData.Terrain.RIVERBED and chunk.terrain[i] != ChunkData.Terrain.ROCK:
		chunk.set_moisture(i, 255)
	changed.append(tile)


## What the moving water has added to the river or taken from it since the
## level was set (someone poured, or scooped): it is in the level now.
## True if there was any.
func _take_stock() -> bool:
	var height_step := _world.height_step
	var top := _surface + applied
	var off := 0.0
	var count := 0
	for tile in _core:
		var should := top - _world.get_height(tile) * height_step
		if should < _config.least_depth:
			continue
		off += _world.get_water(tile) - should
		count += 1
	if count == 0:
		return false
	off /= count
	if absf(off) < 0.001:
		return false
	level = clampf(level + off, _config.lowest, _config.highest)
	return true


## High water, low water, and whether people's ground is under water.
func _judge(_now: int) -> void:
	var high := level >= _config.high_from if not high_water else level > _config.high_over
	if high != high_water:
		high_water = high
		high_water_changed.emit(high)
		if high:
			_erode()
	var low := level <= _config.low_from if not low_water else level < _config.low_over
	if low != low_water:
		low_water = low
		low_water_changed.emit(low)
	var under := flooded_tiles()
	var flood := under.size() >= _config.flood_tiles if not flooded else not under.is_empty()
	if flood != flooded:
		flooded = flood
		var middle := Vector2.ZERO
		for tile in under:
			middle += Vector2(tile) + Vector2(0.5, 0.5)
		flood_changed.emit(flood, under.size(), middle / under.size() if not under.is_empty() else Vector2.INF)


## High water takes a tile of the bank now and then (very slowly: bible
## §10.3): a tile of sand beside the bed becomes bed.
func _erode() -> void:
	if eroded_count >= _config.erosion_most:
		return
	if _hash(eroded_count * 7 + int(added_total * 10.0), _SALT_ERODE) % 1000 >= roundi(_config.erosion_chance * 1000.0):
		return
	var banks: Array[Vector2i] = []
	for tile in _core:
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
			var beside := tile + offset
			if not _world.bounds.has_point(beside) or _world.get_terrain(beside) != ChunkData.Terrain.SAND:
				continue
			if _world.get_height(beside) != _world.get_height(tile) + 1:
				continue
			if occupied_source.is_valid() and bool(occupied_source.call(beside)):
				continue
			banks.append(beside)
	if banks.is_empty():
		return
	var taken := banks[_hash(eroded_count, _SALT_ERODE ^ 0x55) % banks.size()]
	_world.set_height(taken, _world.get_height(taken) - 1)
	_world.set_terrain(taken, ChunkData.Terrain.RIVERBED)
	_core.append(taken)
	eroded_count += 1
	if _water != null:
		var moved: Array[Vector2i] = [taken]
		_syncing = true
		_water.sync(moved)
		_syncing = false
	apply(true)
	eroded.emit(taken)


## The riverbed: every tile of that kind of ground.
func _find_core() -> void:
	_core = []
	if _world == null:
		return
	var size := _world.chunk_size
	for coord in _world.chunk_coords():
		var chunk := _world.get_chunk(coord)
		if chunk == null:
			continue
		var corner := WorldCoords.chunk_origin(coord, size)
		for i in chunk.terrain.size():
			if chunk.terrain[i] == ChunkData.Terrain.RIVERBED:
				@warning_ignore("integer_division")
				_core.append(corner + Vector2i(i % size, i / size))


func _find_springs() -> void:
	_springs = []
	if _config == null or _core.is_empty():
		return
	for n in _config.spring_count:
		var tile := _core[_hash(n, _SALT_SPRING) % _core.size()]
		if not _springs.has(tile):
			_springs.append(tile)


func _hash(index: int, salt: int) -> int:
	return absi(HashNoise.hash2(index, _seed & 0xFFFF, salt ^ ((_seed >> 16) & 0xFFFF)))


static func _number(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	return float(value) if is_finite(float(value)) else fallback
