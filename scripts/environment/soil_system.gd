class_name SoilSystem
extends RefCounted
## The soil of all the land (bible §10.4, M9.4): how wet it is and how
## fertile. (The fields' own soil — what a crop draws, what lying fallow
## gives back — stays Farming's: tiles with a crop on them are left to it.)
##
## **Moisture:** a rainy day wets the ground, a dry day dries it — more on
## a hot one —, and it goes back towards what the land holds by itself
## (its place by the river, as the world was made), which is less while
## the river stands low. Ground under water is soaked.
## **Fertility:** land poorer than it is by itself recovers; a flood that
## runs off leaves silt, which fades slowly.
##
## Coarse: every chunk has its turn once a game day, the chunks one after
## the other through the day (never the whole box in one frame). After a
## long absence each chunk is brought up in one pass.

## A chunk's soil has had its day(s): `days` of them, up to game day `day`.
signal chunk_done(coord: Vector2i, days: int, day: int)

const DAY := TimeConfig.MINUTES_PER_DAY

## How many chunk passes have been made (debug, tests).
var passes := 0
## Tiles that got silt from a flood since the world began.
var silted := 0
## Time the last call that did something took, microseconds (debug overlay).
var last_usec := 0

var _world: WorldData
var _props: PropRegistry
var _weather: WeatherSystem
var _hydrology: Hydrology
var _config: VegetationConfig
var _farming: FarmingConfig
var _order: Array[Vector2i] = []
var _slot := -1 # the last turn taken (turns are counted from the world's first midnight)
var _last: Dictionary = {} # chunk coord -> the game day its soil is up to
## What the land holds by itself, chunk by chunk (as the world was made).
var _base_moisture: Dictionary = {}
var _base_fertility: Dictionary = {}
var _base_vegetation: Dictionary = {}


## `generator` makes the land as it was made (anything with `generate_chunk`);
## without one the land as it is now is taken for that.
func bind(world: WorldData, generator: WorldGenerator, props: PropRegistry, weather: WeatherSystem, hydrology: Hydrology,
		config: VegetationConfig, farming: FarmingConfig) -> void:
	if _hydrology != null and _hydrology.drained.is_connected(on_drained):
		_hydrology.drained.disconnect(on_drained)
	_world = world
	_props = props
	_weather = weather
	_hydrology = hydrology
	_config = config
	_farming = farming
	_order = []
	if world != null:
		_order = world.chunk_coords()
	_slot = -1
	_last.clear()
	_base_moisture.clear()
	_base_fertility.clear()
	_base_vegetation.clear()
	passes = 0
	silted = 0
	for coord in _order:
		# (What the generator kept as it made the world just now, if it did:
		# not made a second time.)
		var kept: Variant = generator.take_made(coord) if generator != null else null
		if kept != null:
			_base_moisture[coord] = kept[0]
			_base_fertility[coord] = kept[1]
			_base_vegetation[coord] = kept[2]
			continue
		var made: ChunkData = generator.generate_chunk(coord) if generator != null else world.get_chunk(coord)
		if made == null:
			continue
		_base_moisture[coord] = made.moisture.duplicate()
		_base_fertility[coord] = made.fertility.duplicate()
		_base_vegetation[coord] = made.vegetation.duplicate()
	if _hydrology != null:
		_hydrology.drained.connect(on_drained)


# --- saving -------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var coords: Array = []
	var days := PackedInt32Array()
	for coord: Vector2i in _last:
		coords.append(coord)
		days.append(int(_last[coord]))
	return {"slot": _slot, "coords": coords, "days": days, "silted": silted}


## Call after bind().
func from_dict(data: Dictionary) -> void:
	_slot = int(data["slot"]) if typeof(data.get("slot")) == TYPE_INT else -1
	silted = maxi(int(data["silted"]), 0) if typeof(data.get("silted")) == TYPE_INT else 0
	_last.clear()
	var coords: Variant = data.get("coords")
	var days: Variant = data.get("days")
	if typeof(coords) == TYPE_ARRAY and typeof(days) == TYPE_PACKED_INT32_ARRAY and (coords as Array).size() == (days as PackedInt32Array).size():
		for n in (coords as Array).size():
			if typeof(coords[n]) == TYPE_VECTOR2I and _base_moisture.has(coords[n]):
				_last[coords[n]] = int(days[n])


# --- what the land is by itself -------------------------------------------------------------------------

## The moisture, fertility and plant cover a tile has as the world was made.
func base_moisture(tile: Vector2i) -> int:
	return _base(_base_moisture, tile)


func base_fertility(tile: Vector2i) -> int:
	return _base(_base_fertility, tile)


func base_vegetation(tile: Vector2i) -> int:
	return _base(_base_vegetation, tile)


## The same, a chunk at a time (for those who go through whole chunks).
func base_layers(coord: Vector2i) -> Array:
	return [_base_moisture.get(coord), _base_fertility.get(coord), _base_vegetation.get(coord)]


func moisture(tile: Vector2i) -> int:
	var chunk := _world.chunk_at_tile(tile) if _world != null else null
	return chunk.moisture[_world.index_at_tile(tile)] if chunk != null else 0


func fertility(tile: Vector2i) -> int:
	var chunk := _world.chunk_at_tile(tile) if _world != null else null
	return chunk.fertility[_world.index_at_tile(tile)] if chunk != null else 0


func debug_text() -> String:
	return "soil: %d chunk passes (last %.2f ms)  silt on %d tiles" % [passes, last_usec / 1000.0, silted]


# --- time ---------------------------------------------------------------------------------------------

## Time has come to `now`: the chunks whose turn has come have their day.
func advance_to(now: int) -> void:
	if _world == null or _config == null or _order.is_empty():
		return
	var count := _order.size()
	var calendar := now + roundi(Config.time.start_hour * 60.0)
	@warning_ignore("integer_division")
	var target := floori(float(calendar) * count / DAY)
	if _slot < 0 or target < _slot:
		_slot = target
		return
	if target == _slot:
		return
	var started := Time.get_ticks_usec()
	var today := Config.time.day_index(now)
	if target - _slot >= count:
		# Everyone's turn has come (more than once, after a long absence): one pass each.
		for coord in _order:
			_turn(coord, today)
	else:
		for slot in range(_slot + 1, target + 1):
			_turn(_order[posmod(slot, count)], today)
	_slot = target
	last_usec = Time.get_ticks_usec() - started


## Brings every chunk up to the day before `now`'s at once (tests; a world
## that must be level before something is measured).
func settle_all(now: int) -> void:
	var today := Config.time.day_index(now)
	for coord in _order:
		_turn(coord, today)


## A flood has run off these tiles: it leaves silt on the land.
func on_drained(tiles: Array[Vector2i]) -> void:
	if _world == null or _config == null or _config.silt_gain <= 0:
		return
	for tile in tiles:
		var chunk := _world.chunk_at_tile(tile)
		if chunk == null:
			continue
		var i := _world.index_at_tile(tile)
		if not _takes_silt(chunk.terrain[i]):
			continue
		var base: PackedByteArray = _base_fertility.get(chunk.coord, PackedByteArray())
		var most := mini((int(base[i]) if i < base.size() else 0) + _config.silt_most, 255)
		var now := int(chunk.fertility[i])
		if now >= most:
			continue
		chunk.fertility[i] = mini(now + _config.silt_gain, most)
		chunk.mark_changed()
		silted += 1


# --- internals ----------------------------------------------------------------------------------------

## One chunk's turn: its soil is brought up to yesterday (the last whole day).
func _turn(coord: Vector2i, today: int) -> void:
	var day := today - 1
	if not _last.has(coord):
		# The first time it is looked at: from here on.
		_last[coord] = day
		return
	var since: int = _last[coord]
	if day <= since:
		return
	var days := mini(day - since, _config.days_made_up)
	_last[coord] = day
	_soil_days(coord, days, day)
	passes += 1
	chunk_done.emit(coord, days, day)


func _soil_days(coord: Vector2i, days: int, day: int) -> void:
	var chunk := _world.get_chunk(coord)
	var base_m: PackedByteArray = _base_moisture.get(coord, PackedByteArray())
	var base_f: PackedByteArray = _base_fertility.get(coord, PackedByteArray())
	if chunk == null or base_m.size() != chunk.moisture.size():
		return
	# What the days were like.
	var rain_days := 0
	var dried := 0.0
	for d in range(day - days + 1, day + 1):
		if _weather != null and _weather.rain_on(d):
			rain_days += 1
		dried += _hydrology.drying(d) if _hydrology != null else 1.0
	var rain := rain_days * _farming.rain_moisture
	var dry := roundi(dried * _farming.evaporation_per_day)
	var ground := _hydrology.groundwater() if _hydrology != null else 1.0
	var seep := 1.0 - pow(1.0 - _farming.seep_share, days)
	var drain := 1.0 - pow(1.0 - _config.drain_share, days)
	var recover := roundi(_config.fertility_recover_per_day * days)
	@warning_ignore("integer_division")
	var fade := day / _config.silt_fade_days - (day - days) / _config.silt_fade_days
	# (The fields' tiles are Farming's.)
	var fields := {}
	if _props != null:
		for prop in _props.props_in_chunk(coord):
			if prop.kind == PropData.Kind.CROP:
				fields[_world.index_at_tile(prop.tile)] = true
	var moisture := chunk.moisture
	var fertility := chunk.fertility
	var terrain := chunk.terrain
	var water := chunk.water
	var changed := false
	for i in moisture.size():
		if terrain[i] == ChunkData.Terrain.RIVERBED or fields.has(i):
			continue
		var before := int(moisture[i])
		var m := before
		if water[i] > 0.0:
			m = 255
		else:
			m = maxi(m + rain - dry, 0)
			var base := roundi(base_m[i] * ground)
			if m < base:
				m += ceili((base - m) * seep)
			elif m > base:
				m -= floori((m - base) * drain)
			m = mini(m, 255)
		if m != before:
			moisture[i] = m
			changed = true
		var f := int(fertility[i])
		var by_itself := int(base_f[i])
		if f < by_itself and recover > 0:
			fertility[i] = mini(f + recover, by_itself)
			changed = true
		elif f > by_itself and fade > 0:
			fertility[i] = maxi(f - fade, by_itself)
			changed = true
	if changed:
		chunk.moisture = moisture
		chunk.fertility = fertility
		chunk.mark_changed()


func _base(layers: Dictionary, tile: Vector2i) -> int:
	if _world == null or not _world.bounds.has_point(tile):
		return 0
	var layer: PackedByteArray = layers.get(WorldCoords.tile_to_chunk(tile, _world.chunk_size), PackedByteArray())
	var i := _world.index_at_tile(tile)
	return layer[i] if i < layer.size() else 0


static func _takes_silt(terrain: int) -> bool:
	return terrain == ChunkData.Terrain.GRASS or terrain == ChunkData.Terrain.DIRT or terrain == ChunkData.Terrain.FARMLAND \
		or terrain == ChunkData.Terrain.ASH or terrain == ChunkData.Terrain.MUD
