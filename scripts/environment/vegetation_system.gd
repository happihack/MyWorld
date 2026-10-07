class_name VegetationSystem
extends RefCounted
## What grows on the land (bible §10.4, M9.4): grass and trees.
##
## **Grass** (`ChunkData.vegetation`, 0 … 255) goes towards what the soil
## lets grow: as lush as the land was made where the soil is as moist and
## as fertile as it was made, thinner where it is drier or poorer (a
## drought, a low river), thinner in winter. It thins faster than it comes
## back, and bare ground greens again from the grass beside it. Tilled or
## burnt ground that nothing is grown on turns to grass again.
## **Trees** are props (resource nodes): a grown tree seeds a sapling now
## and then on open ground near it (a felled tree with a little of its
## growth, so it grows up by the nodes' own rules); trees in soil that has
## dried out die, saplings die in a cold snap. The forest has bounds.
##
## It follows the soil: a chunk's plants have their day right after its
## soil (`SoilSystem.chunk_done`), so it is as coarse and as spread out.
##
## **Fire** (the fire system comes later; these are its hooks): `fuel_at`,
## `can_burn`, `burn`.

## A tree has died (of "drought" or "cold") / has been seeded.
signal tree_died(tile: Vector2i, cause: StringName)
signal tree_seeded(prop_id: int)
## A tile has burnt (`burn`).
signal burned(tile: Vector2i)

const CAUSE_DROUGHT := &"drought"
const CAUSE_COLD := &"cold"
const CAUSE_FIRE := &"fire"

## How many trees the world began with (the forest's bounds are shares of it).
var forest_base := 0
var seeded := 0
var died := 0
## How many chunks were drawn anew because their grass changed (debug, tests).
var redraws := 0

var _world: WorldData
var _props: PropRegistry
var _nodes: ResourceNodes
var _soil: SoilSystem
var _weather: WeatherSystem
var _ids: IdAllocator
var _rng: RandomNumberGenerator
var _clock: GameClock
var _config: VegetationConfig
var _settlement := Vector2.INF
var _shown: Dictionary = {} # chunk coord -> the grass as the chunk was last drawn
var _trees := 0 # trees standing (not felled ones, not saplings)
var _tree_props := 0 # all of them: standing, stumps and saplings


func bind(world: WorldData, props: PropRegistry, nodes: ResourceNodes, soil: SoilSystem, weather: WeatherSystem,
		ids: IdAllocator, rng: RandomNumberGenerator, clock: GameClock, config: VegetationConfig, settlement: Vector2 = Vector2.INF) -> void:
	if _soil != null and _soil.chunk_done.is_connected(_on_chunk_done):
		_soil.chunk_done.disconnect(_on_chunk_done)
	_world = world
	_props = props
	_nodes = nodes
	_soil = soil
	_weather = weather
	_ids = ids
	_rng = rng
	_clock = clock
	_config = config
	_settlement = settlement
	_shown.clear()
	seeded = 0
	died = 0
	redraws = 0
	if world != null:
		for coord in world.chunk_coords():
			var chunk := world.get_chunk(coord)
			if chunk != null:
				_shown[coord] = chunk.vegetation.duplicate()
	_count_trees()
	forest_base = _trees
	if _soil != null:
		_soil.chunk_done.connect(_on_chunk_done)


# --- saving -------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"forest_base": forest_base, "seeded": seeded, "died": died}


## Call after bind() (an older world's forest is the measure of itself).
func from_dict(data: Dictionary) -> void:
	if typeof(data.get("forest_base")) == TYPE_INT and int(data["forest_base"]) > 0:
		forest_base = int(data["forest_base"])
	seeded = maxi(int(data["seeded"]), 0) if typeof(data.get("seeded")) == TYPE_INT else 0
	died = maxi(int(data["died"]), 0) if typeof(data.get("died")) == TYPE_INT else 0


# --- what grows ---------------------------------------------------------------------------------------

## Grown trees standing.
func tree_count() -> int:
	return _trees


## The share of the land (everything but water, bed, sand and bare rock)
## that has a grown tree on it.
func forest_coverage() -> float:
	var land := 0
	if _world == null:
		return 0.0
	# (Every SAMPLE_STEP-th tile each way, counted for all those it stands for.)
	for chunk in _world.loaded_chunks():
		for i in _sampled(chunk):
			var terrain := chunk.terrain[i]
			if chunk.water[i] <= 0.0 and (terrain == ChunkData.Terrain.GRASS or terrain == ChunkData.Terrain.DIRT
					or terrain == ChunkData.Terrain.FARMLAND or terrain == ChunkData.Terrain.ASH):
				land += SAMPLE_STEP * SAMPLE_STEP
	return minf(float(_trees) / land, 1.0) if land > 0 else 0.0


## How lush the grass is on average, 0 … 1 (over the tiles that are grass).
func grass_cover() -> float:
	var total := 0
	var tiles := 0
	if _world == null:
		return 0.0
	for chunk in _world.loaded_chunks():
		for i in _sampled(chunk):
			if chunk.terrain[i] == ChunkData.Terrain.GRASS:
				total += chunk.vegetation[i]
				tiles += 1
	return float(total) / (tiles * 255.0) if tiles > 0 else 0.0


## The land is looked over on every SAMPLE_STEP-th tile each way for the
## averages (M21: every tile of a 512-tile box, daily, was 170 ms).
const SAMPLE_STEP := 4


## The indexes of a chunk's sampled tiles.
func _sampled(chunk: ChunkData) -> PackedInt32Array:
	var size := _world.chunk_size
	if _sample_size != size:
		_sample_size = size
		_sample_ids.clear()
		for y in range(0, size, SAMPLE_STEP):
			for x in range(0, size, SAMPLE_STEP):
				_sample_ids.append(y * size + x)
	return _sample_ids


var _sample_ids := PackedInt32Array()
var _sample_size := -1


## What the soil of a tile lets grow there now (0 … 255): what the land was
## made with, by how moist and how fertile it is compared with how it was made.
func potential(tile: Vector2i, season_share: float = 1.0) -> int:
	if _world == null or _soil == null:
		return 0
	var chunk := _world.chunk_at_tile(tile)
	if chunk == null:
		return 0
	var i := _world.index_at_tile(tile)
	return _potential(_soil.base_vegetation(tile), chunk.moisture[i], _soil.base_moisture(tile), chunk.fertility[i],
		_soil.base_fertility(tile), season_share)


func debug_text() -> String:
	return "plants: grass %.0f%%  trees %d (began with %d; %d seeded, %d died)  forest on %.1f%% of the land  %d redraws" % [
		grass_cover() * 100.0, _trees, forest_base, seeded, died, forest_coverage() * 100.0, redraws]


# --- fire (hooks for the fire system: M12 / M32) --------------------------------------------------------

## How much there is to burn on a tile, 0 … 1: its grass and its tree, less
## the wetter the ground is; nothing in rain, under snow or under water.
func fuel_at(tile: Vector2i) -> float:
	if _world == null or _config == null or not _world.bounds.has_point(tile):
		return 0.0
	var chunk := _world.chunk_at_tile(tile)
	var i := _world.index_at_tile(tile)
	if chunk == null or chunk.water[i] > 0.0:
		return 0.0
	if _weather != null and (_weather.is_raining() or _weather.snow_cover > 0.3):
		return 0.0
	var fuel := 0.0
	if chunk.terrain[i] == ChunkData.Terrain.GRASS:
		fuel += _config.fuel_grass * chunk.vegetation[i] / 255.0
	var prop := _props.prop_at(tile) if _props != null else null
	if prop != null and prop.kind == PropData.Kind.TREE and not prop.felled:
		fuel += _config.fuel_tree
	return fuel * lerpf(1.0, _config.wet_fuel_share, chunk.moisture[i] / 255.0)


func can_burn(tile: Vector2i) -> bool:
	return _config != null and fuel_at(tile) >= _config.burn_from


## Burns a tile: its grass is gone, its tree too, the ground is ash (which
## feeds the soil, and turns to grass again in time). Returns what burnt:
## {"grass": 0 … 255, "tree": bool} — empty if nothing could. `scorch`: it
## burns whatever there is to burn (a falling star), on any dry ground.
func burn(tile: Vector2i, scorch: bool = false) -> Dictionary:
	if scorch:
		if _world == null or not _world.bounds.has_point(tile) or _world.get_water(tile) > 0.0:
			return {}
	elif not can_burn(tile):
		return {}
	var chunk := _world.chunk_at_tile(tile)
	var i := _world.index_at_tile(tile)
	var burnt := {"grass": int(chunk.vegetation[i]), "tree": false}
	var prop := _props.prop_at(tile) if _props != null else null
	if prop != null and prop.kind == PropData.Kind.TREE:
		burnt["tree"] = true
		_kill(prop, CAUSE_FIRE)
	chunk.vegetation[i] = 0
	chunk.fertility[i] = mini(int(chunk.fertility[i]) + _config.ash_gain, 255)
	if chunk.terrain[i] == ChunkData.Terrain.GRASS or chunk.terrain[i] == ChunkData.Terrain.DIRT:
		_world.set_terrain(tile, ChunkData.Terrain.ASH)
	chunk.mark_changed(ChunkData.DIRTY_MESH)
	if _shown.has(chunk.coord):
		(_shown[chunk.coord] as PackedByteArray)[i] = 0
	if _props != null:
		_props.chunk_changed.emit(chunk.coord)
	burned.emit(tile)
	return burnt


# --- time ---------------------------------------------------------------------------------------------

## A chunk's soil has had `days` days, up to game day `day`: now its plants.
func _on_chunk_done(coord: Vector2i, days: int, _day: int) -> void:
	if _world == null or _config == null:
		return
	var now := _clock.tick if _clock != null else 0
	_grass_days(coord, days, now)
	_tree_days(coord, days, now)


func _grass_days(coord: Vector2i, days: int, now: int) -> void:
	var chunk := _world.get_chunk(coord)
	var layers := _soil.base_layers(coord)
	if chunk == null or layers[0] == null:
		return
	var base_m: PackedByteArray = layers[0]
	var base_f: PackedByteArray = layers[1]
	var base_v: PackedByteArray = layers[2]
	var season := Seasons.blend(_config.by_season, Seasons.position(now))
	var grow := 1.0 - pow(1.0 - _config.grow_per_day, days)
	var grow_alone := 1.0 - pow(1.0 - _config.grow_per_day * _config.alone_share, days)
	var die := 1.0 - pow(1.0 - _config.die_per_day, days)
	var reclaim := 1.0 - pow(1.0 - _config.reclaim_chance_per_day, days)
	var size := chunk.size
	var vegetation := chunk.vegetation
	var terrain := chunk.terrain
	var water := chunk.water
	var moisture := chunk.moisture
	var fertility := chunk.fertility
	var shown: PackedByteArray = _shown.get(coord, PackedByteArray())
	if shown.size() != vegetation.size():
		shown = vegetation.duplicate()
	var origin := WorldCoords.chunk_origin(coord, size)
	var changed := false
	var redraw := false
	for i in vegetation.size():
		var kind := terrain[i]
		if kind != ChunkData.Terrain.GRASS:
			# Tilled or burnt ground nothing is grown on turns to grass again.
			if (kind == ChunkData.Terrain.FARMLAND or kind == ChunkData.Terrain.ASH) and water[i] <= 0.0 and _rng.randf() < reclaim:
				@warning_ignore("integer_division")
				var tile := origin + Vector2i(i % size, i / size)
				if _props == null or not _props.has_prop_at(tile):
					_world.set_terrain(tile, ChunkData.Terrain.GRASS)
					vegetation[i] = mini(vegetation[i], _config.bare_below / 2)
					changed = true
					redraw = true
			continue
		if water[i] > 0.0:
			continue
		var before := int(vegetation[i])
		var could := _potential(base_v[i], moisture[i], base_m[i], fertility[i], base_f[i], season)
		var v := before
		if could > v:
			var share := grow
			if v < _config.bare_below and not _beside_grass(vegetation, terrain, i, size):
				share = grow_alone
			v += ceili((could - v) * share)
		elif could < v:
			v -= ceili((v - could) * die)
		if v == before:
			continue
		vegetation[i] = v
		changed = true
		# (Drawn anew only when it shows: a tile's grass far from how it was drawn.)
		if absi(v - int(shown[i])) >= _config.redraw_step:
			redraw = true
	if not changed:
		return
	chunk.vegetation = vegetation
	chunk.mark_changed(ChunkData.DIRTY_MESH if redraw else 0)
	if redraw:
		_shown[coord] = vegetation.duplicate()
		redraws += 1
		if _props != null:
			_props.chunk_changed.emit(coord)


func _tree_days(coord: Vector2i, days: int, now: int) -> void:
	if _props == null:
		return
	var chunk := _world.get_chunk(coord)
	if chunk == null:
		return
	var season := Config.time.season_of(now)
	var growing := season == Seasons.SPRING or season == Seasons.SUMMER
	var seed_chance := 1.0 - pow(1.0 - _config.sapling_chance_per_day, days)
	var dry_chance := 1.0 - pow(1.0 - _config.dry_death_per_day, days)
	var cold_chance := 1.0 - pow(1.0 - _config.cold_death_per_day, days)
	var cold := _weather != null and _weather.has_condition(WeatherSystem.COLD_SNAP)
	var most := roundi(forest_base * _config.forest_most)
	var least := roundi(forest_base * _config.forest_least)
	for prop: PropData in _props.props_in_chunk(coord).duplicate():
		if prop.kind != PropData.Kind.TREE:
			continue
		var i := _world.index_at_tile(prop.tile)
		if prop.felled:
			# A sapling (or a stump): the cold takes the young.
			if cold and _rng.randf() < cold_chance:
				_kill(prop, CAUSE_COLD)
			continue
		if chunk.moisture[i] < _config.dry_below and _trees > least and _rng.randf() < dry_chance:
			_kill(prop, CAUSE_DROUGHT)
			continue
		if growing and _tree_props < most and _rng.randf() < seed_chance:
			_seed_from(prop, now)


func _seed_from(parent: PropData, now: int) -> void:
	var reach := _config.sapling_reach
	var tile := parent.tile + Vector2i(_rng.randi_range(-reach, reach), _rng.randi_range(-reach, reach))
	if tile == parent.tile or not _world.bounds.has_point(tile) or _props.has_prop_at(tile) or Graves.on_plot(_props, tile):
		return
	var chunk := _world.chunk_at_tile(tile)
	var i := _world.index_at_tile(tile)
	var terrain := chunk.terrain[i]
	if (terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT) or chunk.water[i] > 0.0:
		return
	if chunk.moisture[i] < _config.sapling_moisture or absi(_world.get_height(tile) - _world.get_height(parent.tile)) > 1:
		return
	if _settlement != Vector2.INF and (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(_settlement) < _config.settlement_clearance:
		return
	var around := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var other := _props.prop_at(tile + Vector2i(dx, dy))
			if other != null and other.kind == PropData.Kind.TREE:
				around += 1
	if around > _config.sapling_crowd:
		return
	var sapling := PropData.new()
	sapling.id = _ids.next_id()
	sapling.kind = PropData.Kind.TREE
	sapling.tile = tile
	# (Its parent's kind: broadleaf or conifer; one of the two shapes of it.)
	sapling.variant = (PropData.TREE_CONIFER_FIRST_VARIANT if parent.is_conifer() else 0) + _rng.randi_range(0, 1)
	sapling.rotation_step = _rng.randi_range(0, 255)
	sapling.scale_percent = _rng.randi_range(85, 120)
	sapling.offset_x = _rng.randi_range(-60, 60)
	sapling.offset_y = _rng.randi_range(-60, 60)
	if not _props.add(sapling):
		return
	if _nodes != null:
		_nodes.plant(sapling, now)
	seeded += 1
	_tree_props += 1
	tree_seeded.emit(sapling.id)


func _kill(prop: PropData, cause: StringName) -> void:
	var tile := prop.tile
	if not prop.felled:
		_trees -= 1
	_tree_props -= 1
	_props.remove(prop.id)
	died += 1
	tree_died.emit(tile, cause)


## A tree has grown up whole (the nodes say so) — a sapling, or a felled
## one that grew back: it stands again.
func on_regrown(prop_id: int) -> void:
	var prop := _props.get_prop(prop_id) if _props != null else null
	if prop != null and prop.kind == PropData.Kind.TREE:
		_trees += 1


## A tree has been felled (its last wood taken): it stands no longer.
func on_depleted(prop_id: int) -> void:
	var prop := _props.get_prop(prop_id) if _props != null else null
	if prop != null and prop.kind == PropData.Kind.TREE:
		_trees -= 1


func _count_trees() -> void:
	_trees = 0
	_tree_props = 0
	if _props != null:
		for prop in _props.of_kind(PropData.Kind.TREE):
			if prop.kind == PropData.Kind.TREE:
				_tree_props += 1
				if not prop.felled:
					_trees += 1


## Is there grass beside tile `i` of a chunk from which it can spread (the
## four tiles about it; over the chunk's edge: taken to be there)?
func _beside_grass(vegetation: PackedByteArray, terrain: PackedByteArray, i: int, size: int) -> bool:
	var x := i % size
	@warning_ignore("integer_division")
	var y := i / size
	if x == 0 or y == 0 or x == size - 1 or y == size - 1:
		return true
	for n: int in [i - 1, i + 1, i - size, i + size]:
		if terrain[n] == ChunkData.Terrain.GRASS and vegetation[n] >= _config.spread_from:
			return true
	return false


static func _potential(base_cover: int, moisture: int, base_moisture: int, fertility: int, base_fertility: int, season_share: float) -> int:
	var wet := float(moisture) / maxf(base_moisture, 1.0)
	var rich := float(fertility) / maxf(base_fertility, 1.0)
	return clampi(roundi(base_cover * minf(wet, 1.5) * minf(rich, 1.5) * season_share), 0, 255)
