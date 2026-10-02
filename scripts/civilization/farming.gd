class_name Farming
extends RefCounted
## Simple agriculture (bible §10.4): plots of tilled ground (terrain
## FARMLAND) with a crop on each, growing through its stages by what the
## soil gives it — moisture, fertility and the season — wilting and failing
## when the soil is dry, taking fertility out of the ground when harvested.
##
## A crop is a prop (PropData.Kind.CROP) on its tile, so it is drawn,
## picked, inspected and saved like every other thing that stands
## somewhere. On the prop:
##   variant      its Stage
##   growth       0 … 1000 (ripe at 1000)
##   vigor        0 … 1000 (health: falls in dry soil; at 0 the crop has failed)
##   stock        units of grain on a RIPE crop (harvested through
##                ResourceNodes like berries off a bush), -1 otherwise
##   stock_tick   up to when growth has been worked out (STUBBLE: when it
##                was harvested or cleared)
##   tended_tick  when someone last tended it

signal sown(crop_id: int)
signal ripened(crop_id: int)
signal failed(crop_id: int)
## The first field of the world was sown.
signal first_field(tile: Vector2i)
## A plot was sown without seed kept for it (it will bear little).
signal sown_thin(crop_id: int)
## Such a plot has ripened.
signal harvest_thin(crop_id: int)
## A dry spell began (so many days without rain), or ended.
signal dry_spell(began: bool, days: int)
## A growing crop was killed by frost.
signal frost_killed(crop_id: int)

enum Stage { SOWN, SPROUT, GROWING, RIPE, STUBBLE, FAILED }

## Tasks (WorkStep "task").
const SOW := &"sow"
const TEND := &"tend"
const CLEAR := &"clear"
const HARVEST := &"harvest"

## Growth (0 … 1000) from which a crop is a sprout, and from which it stands tall.
const SPROUT_FROM := 120
const GROWING_FROM := 450
const RIPE_AT := 1000
## A dry-looking crop is drawn with this added to its stage (PropMeshLibrary).
const DRY_VARIANT := 8
## Soil with water standing on or beside it is this wet at least.
const WET_SOIL := 210
const MAX_DAYS_AT_ONCE := 30
const _RAIN_SALT := 0x7A11

var last_settle_tick := -1_000_000
## The weather: called with a game day, returns whether it rained on it.
## Not set: the placeholder below (FarmingConfig.rain_chance) says.
var rain_source := Callable()
## Is the ground frozen? (The weather says; not set: never.)
var frozen_source := Callable()
## How much of the moisture the land holds by itself is there now (the
## river says: less when it stands low; not set: all of it).
var groundwater_source := Callable()
## How fast soil dried on a game day, compared with an ordinary one (by how
## warm it was; not set: as usual).
var drying_source := Callable()
## Where seed comes from: called with the units wanted, returns true if
## they were there (and are taken). Not set: sowing needs no seed.
var seed_source := Callable()

var _world: WorldData
var _props: PropRegistry
var _ids: IdAllocator
var _pathfinder: Pathfinder
var _start: WorldSetup.StartInfo
var _people: PersonRegistry
var _occupations: OccupationLibrary
var _generator: WorldGenerator
var _config: FarmingConfig
var _seed := 0
## The game day up to which the soil's days are done.
var _day := -1_000_000
var _crops: Array[PropData] = []
var _crops_version := -1
var _baseline: Dictionary = {} # tile -> the moisture the land holds by itself
## What is left over of a crop's growth after the whole points (crop id ->
## 0 … 1), so that hours of slow growth are not rounded away.
var _carry: Dictionary = {}
## How many plots have been reaped since the world began. (The first field
## is sown with what was gathered wild; after the first harvest, with grain
## kept for it.)
var _harvests := 0
## Plots sown without seed: crop id -> true.
var _thin: Dictionary = {}
## Days without rain in a row, and whether that is a dry spell by now.
var _dry_days := 0
var _dry := false


# --- rules (static) -------------------------------------------------------------------------------

static func stage_of(prop: PropData) -> Stage:
	return clampi(prop.variant, 0, Stage.size() - 1) as Stage if prop != null and prop.kind == PropData.Kind.CROP else Stage.STUBBLE


static func stage_for(growth: int) -> Stage:
	if growth >= RIPE_AT:
		return Stage.RIPE
	if growth >= GROWING_FROM:
		return Stage.GROWING
	return Stage.SPROUT if growth >= SPROUT_FROM else Stage.SOWN


## Is something alive on the plot (sown and not yet harvested or failed)?
static func is_growing(prop: PropData) -> bool:
	var stage := stage_of(prop)
	return stage == Stage.SOWN or stage == Stage.SPROUT or stage == Stage.GROWING


## Does the crop look dry (wilting)?
static func looks_dry(prop: PropData, config: FarmingConfig = null) -> bool:
	if config == null:
		config = Config.farming
	var stage := stage_of(prop)
	return (stage == Stage.SPROUT or stage == Stage.GROWING or stage == Stage.RIPE) and prop.vigor < config.looks_dry_below


## The shape a crop is drawn with: its stage, and the dry look of it.
static func shown_variant(prop: PropData, config: FarmingConfig = null) -> int:
	return int(stage_of(prop)) + (DRY_VARIANT if looks_dry(prop, config) else 0)


## How well a crop grows for the soil's moisture: 0 (wilting) … 1.
static func moisture_factor(moisture: int, config: FarmingConfig = null) -> float:
	if config == null:
		config = Config.farming
	return clampf(inverse_lerp(float(config.wilt_below), float(config.good_from), float(moisture)), 0.0, 1.0)


## ...and for its fertility: poor soil grows slowly and yields little.
static func fertility_factor(fertility: int) -> float:
	return clampf(0.4 + fertility / 255.0 * 0.8, 0.4, 1.2)


# --- the world's fields ---------------------------------------------------------------------------

func bind(world: WorldData, props: PropRegistry, ids: IdAllocator, pathfinder: Pathfinder, start: WorldSetup.StartInfo,
		people: PersonRegistry, occupations: OccupationLibrary, generator: WorldGenerator, world_seed: int,
		config: FarmingConfig = null) -> void:
	_world = world
	_props = props
	_ids = ids
	_pathfinder = pathfinder
	_start = start
	_people = people
	_occupations = occupations
	_generator = generator
	_seed = world_seed
	_config = config if config != null else Config.farming
	_day = -1_000_000
	last_settle_tick = -1_000_000
	_crops_version = -1
	_baseline.clear()
	_carry.clear()
	_harvests = 0
	_thin.clear()
	_dry_days = 0
	_dry = false


## Every plot there is (whatever stands on it).
func crops() -> Array[PropData]:
	if _props == null:
		return []
	if _crops_version != _props.version:
		_crops_version = _props.version
		_crops = []
		for prop in _props.all_props():
			if prop.kind == PropData.Kind.CROP:
				_crops.append(prop)
		_crops.sort_custom(func(a: PropData, b: PropData) -> bool: return a.id < b.id)
	return _crops


func plot_count() -> int:
	return crops().size()


## How many people farm (their occupation's work is the field).
func farmer_count() -> int:
	var count := 0
	if _people == null or _occupations == null:
		return 0
	for person in _people.all_people():
		var def := _occupations.get_def(person.occupation_id)
		if def != null and def.work_target == &"field":
			count += 1
	return count


func plots_wanted() -> int:
	return farmer_count() * _config.plots_per_farmer


## How many plots have been reaped so far.
func harvest_count() -> int:
	return _harvests


## Was this plot sown without seed?
func is_thin(crop_id: int) -> bool:
	return _thin.has(crop_id)


## Units of grain to keep for the next sowing: seed for every plot that is
## not growing anything (and for those still to be made). Nothing before the
## first harvest: until then there is no grain to keep.
func seed_wanted() -> int:
	if _harvests <= 0 or _config.seed_per_plot <= 0:
		return 0
	var plots := maxi(plots_wanted() - plot_count(), 0)
	for crop in crops():
		var stage := stage_of(crop)
		if stage == Stage.STUBBLE or stage == Stage.FAILED:
			plots += 1
	return plots * _config.seed_per_plot


## Is there a dry spell (see FarmingConfig.dry_spell_days)?
func is_dry_spell() -> bool:
	return _dry


func dry_days() -> int:
	return _dry_days


## Is it a time for sowing: a season for it, the ground not frozen — and
## time enough left for what is sown to ripen before winter?
func sowing_time(now: int) -> bool:
	return _config.sows_in(Config.time.season_of(now)) and not ground_frozen() and ripens_before_winter(now)


func ground_frozen() -> bool:
	return frozen_source.is_valid() and bool(frozen_source.call())


## Would grain sown now ripen before winter? Counted in days of good
## growth: each day until winter counts what its season lets grow (a
## tended crop grows faster).
func ripens_before_winter(now: int) -> bool:
	return growing_days_left(now) * _config.ripen_margin >= _config.grow_days


## Days of full growth there are between `now` and winter, for a crop that
## is tended.
func growing_days_left(now: int) -> float:
	var time := Config.time
	var day := time.day_index(now)
	var total := 0.0
	for ahead in time.days_per_year():
		@warning_ignore("integer_division")
		var season := posmod(day + ahead, time.days_per_year()) / time.days_per_season
		if season == Seasons.WINTER:
			break
		total += _config.season_factor(season)
	return total * (1.0 + _config.tend_bonus)


## The soil's moisture at a tile, 0 … 255.
func soil(tile: Vector2i) -> int:
	var chunk := _world.chunk_at_tile(tile) if _world != null else null
	return chunk.moisture[_world.index_at_tile(tile)] if chunk != null else 0


func fertility(tile: Vector2i) -> int:
	var chunk := _world.chunk_at_tile(tile) if _world != null else null
	return chunk.fertility[_world.index_at_tile(tile)] if chunk != null else 0


## Did it rain on this game day? The weather says (see WeatherSystem);
## without weather, a placeholder: decided by the world's seed and the day.
func rain_on(day: int) -> bool:
	if rain_source.is_valid():
		return bool(rain_source.call(day))
	var season := posmod(floori(float(day) / float(Config.time.days_per_season)), Config.time.seasons_per_year)
	var chance := _config.rain_chance[season] if season < _config.rain_chance.size() else 0.0
	return float(HashNoise.hash2(day, _seed & 0xFFFF, _RAIN_SALT) % 1000) < chance * 1000.0


## Can a plot be made on this tile: open, dry, walkable ground that nothing
## stands on, away from the fire, the huts and the stores?
func suitable(tile: Vector2i) -> bool:
	if _world == null or _start == null or not _world.bounds.has_point(tile):
		return false
	var terrain := _world.get_terrain(tile)
	if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT and terrain != ChunkData.Terrain.FARMLAND:
		return false
	if _world.get_water(tile) > 0.0 or _props.has_prop_at(tile):
		return false
	if _pathfinder != null and not _pathfinder.can_stand(tile):
		return false
	var from_fire := Vector2(tile - _start.settlement_tile).length()
	if from_fire < _config.site_min_distance or from_fire > _config.site_max_distance:
		return false
	for hut_id in _start.hut_ids:
		var hut := _props.get_prop(hut_id)
		if hut != null and maxi(absi(hut.tile.x - tile.x), absi(hut.tile.y - tile.y)) <= 1:
			return false
	return true


## Where the next plot goes: beside the plots there are (a field is one
## piece of ground), the most fertile and moist of those places; the best
## place near the settlement for the first. Null if there is nowhere.
func next_plot() -> Variant:
	if _world == null or _start == null:
		return null
	var existing := crops()
	var best: Variant = null
	var best_score := -INF
	var reach := _config.site_max_distance
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var tile := _start.settlement_tile + Vector2i(dx, dy)
			if not suitable(tile):
				continue
			var score := fertility(tile) + soil(tile) * 0.5 - Vector2(dx, dy).length() * 6.0
			if not existing.is_empty():
				var beside := false
				for crop in existing:
					if absi(crop.tile.x - tile.x) + absi(crop.tile.y - tile.y) == 1:
						beside = true
						break
				if not beside:
					score -= 10000.0 # only if there is nowhere beside the field
			if score > best_score or (score == best_score and best != null and (tile.y < (best as Vector2i).y or (tile.y == (best as Vector2i).y and tile.x < (best as Vector2i).x))):
				best_score = score
				best = tile
	return best


## Sows a plot: tills the ground if it is new, and puts seed in it. Returns
## the crop, or null if nothing can be sown there.
func sow(tile: Vector2i, now: int) -> PropData:
	var crop := _props.prop_at(tile) if _props != null else null
	if crop != null:
		if crop.kind != PropData.Kind.CROP or stage_of(crop) != Stage.STUBBLE:
			return null
	else:
		if not suitable(tile):
			return null
		var first := crops().is_empty()
		_world.set_terrain(tile, ChunkData.Terrain.FARMLAND)
		crop = PropData.new()
		crop.id = _ids.next_id()
		crop.kind = PropData.Kind.CROP
		crop.tile = tile
		crop.scale_percent = 100
		if not _props.add(crop):
			return null
		if first:
			first_field.emit(tile)
	# Seed: from what was kept of the last harvest. Without it the plot is
	# sown with whatever can be gleaned, and bears little.
	var seeded := true
	if _config.seed_per_plot > 0 and _harvests > 0 and seed_source.is_valid():
		seeded = bool(seed_source.call(_config.seed_per_plot))
	crop.variant = Stage.SOWN
	crop.growth = 0
	crop.vigor = 1000
	crop.stock = -1
	crop.stock_tick = now
	crop.tended_tick = now
	_props.changed(crop.id)
	if seeded:
		_thin.erase(crop.id)
	else:
		_thin[crop.id] = true
	sown.emit(crop.id)
	if not seeded:
		sown_thin.emit(crop.id)
	return crop


## What there is for a farmer to do now, the most pressing first: reap what
## is ripe, clear what has failed, sow what lies ready (in a sowing season),
## tend what grows. {"task", "tile", "id" (0 for a plot yet to be made)} or {}.
func task_for(person: PersonData, now: int) -> Dictionary:
	var from := person.position if person != null else (_start.settlement_tile if _start != null else Vector2i.ZERO)
	var nearest := func(wanted: Callable) -> PropData:
		var found: PropData = null
		for crop in crops():
			if wanted.call(crop) and (found == null or (crop.tile - from).length_squared() < (found.tile - from).length_squared()):
				found = crop
		return found
	var ripe: PropData = nearest.call(func(crop: PropData) -> bool: return stage_of(crop) == Stage.RIPE and crop.stock > 0)
	if ripe != null:
		return {"task": HARVEST, "tile": ripe.tile, "id": ripe.id}
	var dead: PropData = nearest.call(func(crop: PropData) -> bool: return stage_of(crop) == Stage.FAILED)
	if dead != null:
		return {"task": CLEAR, "tile": dead.tile, "id": dead.id}
	if sowing_time(now):
		var fallow := roundi(_config.fallow_days * Config.time.MINUTES_PER_DAY)
		var ready: PropData = nearest.call(func(crop: PropData) -> bool:
			return stage_of(crop) == Stage.STUBBLE and now - crop.stock_tick >= fallow)
		if ready != null:
			return {"task": SOW, "tile": ready.tile, "id": ready.id}
		if plot_count() < plots_wanted():
			var tile: Variant = next_plot()
			if tile != null:
				return {"task": SOW, "tile": tile, "id": 0}
	var untended: PropData = null
	for crop in crops():
		if is_growing(crop) and now - crop.tended_tick >= _config.tend_every_minutes \
				and (untended == null or crop.tended_tick < untended.tended_tick):
			untended = crop
	if untended != null:
		return {"task": TEND, "tile": untended.tile, "id": untended.id}
	return {}


## How pressing the field work is, 0 … 1 (for the job board): ripe grain
## most of all, then sowing and clearing, then tending.
func pressing(now: int) -> float:
	var task := task_for(null, now)
	match task.get("task", &""):
		HARVEST:
			return 0.9
		SOW, CLEAR:
			return 0.7
		TEND:
			return 0.4
	return 0.0


## Game minutes of work a task takes (reaping takes as long as it takes).
func minutes_for(task: StringName) -> float:
	match task:
		SOW:
			return _config.sow_minutes
		TEND:
			return _config.tend_minutes
		CLEAR:
			return _config.clear_minutes
	return 60.0


## The work on a plot is done. True if it changed anything.
func finish(task: StringName, tile: Vector2i, crop_id: int, now: int) -> bool:
	var crop := _props.get_prop(crop_id) if _props != null and crop_id != 0 else null
	match task:
		SOW:
			return sow(tile, now) != null
		TEND:
			if crop == null or not is_growing(crop):
				return false
			crop.tended_tick = now
			_props.touch(crop.id)
			return true
		CLEAR:
			if crop == null or stage_of(crop) != Stage.FAILED:
				return false
			_to_stubble(crop, now)
			return true
	return false


## The last grain has been taken off a ripe crop (see ResourceNodes.take).
func reaped(crop: PropData, now: int) -> void:
	_harvests += 1
	_to_stubble(crop, now)


## Time passes for the fields: the soil's days (rain, drying, ground water)
## and the crops' growth. Cheap to call often.
func settle(now: int) -> void:
	if _props == null or now - last_settle_tick < _config.settle_minutes and now >= last_settle_tick:
		return
	last_settle_tick = now
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
	var made_up := 0
	while _day < today and made_up < MAX_DAYS_AT_ONCE:
		_day += 1
		made_up += 1
		_weather_day(_day - 1)
		_soil_day(_day - 1)
	_day = today
	var frost := ground_frozen()
	for crop in crops():
		if frost and is_growing(crop):
			# Frost: what was still growing is dead.
			crop.variant = Stage.FAILED
			crop.stock = -1
			crop.stock_tick = now
			_props.changed(crop.id)
			frost_killed.emit(crop.id)
			continue
		_grow(crop, now)


func debug_text(now: int) -> String:
	var stages := {}
	var moisture := 0
	for crop in crops():
		var word := String(Stage.keys()[stage_of(crop)]).to_lower() + ("*" if looks_dry(crop, _config) else "")
		stages[word] = int(stages.get(word, 0)) + 1
		moisture += soil(crop.tile)
	var parts := PackedStringArray()
	for word: String in stages:
		parts.append("%s %d" % [word, stages[word]])
	return "fields: %d of %d plots (%s)  soil %d  farmers %d  rain today: %s" % [plot_count(), plots_wanted(),
		", ".join(parts) if not parts.is_empty() else "none", moisture / maxi(plot_count(), 1), farmer_count(),
		"yes" if rain_on(Config.time.day_index(now)) else "no"]


func to_dict() -> Dictionary:
	var thin: Array = _thin.keys()
	thin.sort()
	return {"day": _day, "harvests": _harvests, "thin": thin, "dry_days": _dry_days, "dry": _dry}


func from_dict(data: Dictionary) -> void:
	_day = int(data["day"]) if typeof(data.get("day")) == TYPE_INT else -1_000_000
	_harvests = maxi(int(data["harvests"]), 0) if typeof(data.get("harvests")) == TYPE_INT else 0
	_dry_days = maxi(int(data["dry_days"]), 0) if typeof(data.get("dry_days")) == TYPE_INT else 0
	_dry = bool(data["dry"]) if typeof(data.get("dry")) == TYPE_BOOL else false
	_thin.clear()
	var thin: Variant = data.get("thin")
	if typeof(thin) == TYPE_ARRAY:
		for id: Variant in thin:
			if typeof(id) == TYPE_INT:
				_thin[int(id)] = true


# --- internals ------------------------------------------------------------------------------------

func _to_stubble(crop: PropData, now: int) -> void:
	_carry.erase(crop.id)
	_thin.erase(crop.id)
	crop.variant = Stage.STUBBLE
	crop.growth = 0
	crop.vigor = 1000
	crop.stock = -1
	crop.stock_tick = now
	_props.changed(crop.id)


## What the land at `tile` holds by itself (as it was made).
func _baseline_of(tile: Vector2i) -> int:
	if not _baseline.has(tile):
		_baseline[tile] = int(_generator.sample_tile(tile)["moisture"]) if _generator != null else soil(tile)
	return _baseline[tile]


## One day of the weather: rain, or one more day without.
func _weather_day(day: int) -> void:
	if rain_on(day):
		var was := _dry_days
		_dry_days = 0
		if _dry:
			_dry = false
			dry_spell.emit(false, was)
		return
	_dry_days += 1
	if not _dry and _dry_days >= _config.dry_spell_days:
		_dry = true
		dry_spell.emit(true, _dry_days)


## One day for the soil of every plot.
func _soil_day(day: int) -> void:
	var rain := _config.rain_moisture if rain_on(day) else 0
	var dried := roundi(_config.evaporation_per_day * (float(drying_source.call(day)) if drying_source.is_valid() else 1.0))
	var ground := float(groundwater_source.call()) if groundwater_source.is_valid() else 1.0
	for crop in crops():
		var chunk := _world.chunk_at_tile(crop.tile)
		if chunk == null:
			continue
		var i := _world.index_at_tile(crop.tile)
		var moisture := int(chunk.moisture[i]) + rain - dried
		if is_growing(crop) or stage_of(crop) == Stage.RIPE:
			moisture -= _config.crop_draw_per_day
		moisture = maxi(moisture, 0)
		var base := roundi(_baseline_of(crop.tile) * ground)
		if moisture < base:
			moisture += ceili((base - moisture) * _config.seep_share)
		if _wet_beside(crop.tile):
			moisture = maxi(moisture, WET_SOIL)
		chunk.set_moisture(i, moisture)
		# A plot with nothing on it rests.
		if stage_of(crop) == Stage.STUBBLE:
			chunk.set_fertility(i, mini(int(chunk.fertility[i]) + _config.fallow_gain_per_day, 255))


func _wet_beside(tile: Vector2i) -> bool:
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _world.bounds.has_point(tile + offset) and _world.get_water(tile + offset) > 0.0:
			return true
	return false


## Growth and health of one crop up to `now`.
func _grow(crop: PropData, now: int) -> void:
	if not is_growing(crop):
		return
	var elapsed := now - crop.stock_tick
	if elapsed <= 0:
		return
	crop.stock_tick = now
	var shown := shown_variant(crop, _config)
	var moisture := soil(crop.tile)
	var day := float(Config.time.MINUTES_PER_DAY)
	# Health: dry soil wears it down, moist soil brings it back.
	if moisture < _config.wilt_below:
		crop.vigor = maxi(crop.vigor - ceili(elapsed * 1000.0 / (_config.wilt_days * day)), 0)
	else:
		crop.vigor = mini(crop.vigor + floori(elapsed * 1000.0 / (_config.recover_days * day)), 1000)
	if crop.vigor <= 0:
		crop.variant = Stage.FAILED
		crop.stock = -1
		_props.changed(crop.id)
		failed.emit(crop.id)
		return
	var rate := moisture_factor(moisture, _config) * fertility_factor(fertility(crop.tile)) \
		* _config.season_factor(Config.time.season_of(now))
	if now - crop.tended_tick < _config.tend_every_minutes:
		rate *= 1.0 + _config.tend_bonus
	var grown := elapsed * 1000.0 * rate / (_config.grow_days * day) + float(_carry.get(crop.id, 0.0))
	_carry[crop.id] = grown - floorf(grown)
	crop.growth = mini(crop.growth + floori(grown), RIPE_AT)
	crop.variant = stage_for(crop.growth)
	if crop.variant == Stage.RIPE:
		# What it bears: more in fertile soil, less if it has suffered. The
		# soil is the poorer for it.
		var health := lerpf(0.5, 1.0, crop.vigor / 1000.0)
		crop.stock = maxi(roundi(_config.yield_units * fertility_factor(fertility(crop.tile)) * health
			* (_config.thin_yield if _thin.has(crop.id) else 1.0)), 1)
		var chunk := _world.chunk_at_tile(crop.tile)
		var i := _world.index_at_tile(crop.tile)
		chunk.set_fertility(i, maxi(int(chunk.fertility[i]) - _config.fertility_cost, mini(_config.fertility_floor, int(chunk.fertility[i]))))
		_props.changed(crop.id)
		ripened.emit(crop.id)
		if _thin.has(crop.id):
			harvest_thin.emit(crop.id)
	elif shown_variant(crop, _config) != shown:
		_props.changed(crop.id)
	else:
		_props.touch(crop.id)
