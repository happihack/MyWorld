class_name FishWaters
extends RefCounted
## Where the fish are (FB1, bible §18.2a): the water of the box in cells of
## CELL × CELL tiles, each with its own fish — more in deep, quiet water (the
## ponds), fewer in shallows and where the river runs fast. A fisher takes
## from the cell they fish; a cell comes back by itself, faster in spring and
## summer, slowly in winter, and slowly too once fished hard. Every spring the
## fish **run** up one stretch of the river for a few days. What each
## settlement catches is counted by the year, so that a year far below its
## usual is told: a bad fishing year.
##
## Before FB1 the box held one stock of fish: `total()` and `set_total()`
## stand for it (an older save's stock is shared out by what each cell holds).

## A fish has been taken where they run (`at`: a water tile) — the first time a run is fished, the history tells of it.
signal run_began(at: Vector2i)
## A settlement caught far fewer fish last year than it is used to.
signal bad_year(settlement_id: int, caught: int, usual: float)

const CELL := 8
## One fish per so many tiles of water.
const TILES_PER_FISH := 1.0 # (was 5: a whole river then fed a village about as well as two berry bushes — the owner, 2026-10-07: fishing matters to the food)
## How deep is deep (more fish) and how shallow is shallow (fewer), in height
## levels; and a current faster than this (tiles/s) holds fewer.
const DEEP_LEVELS := 2.0
const SHALLOW_LEVELS := 0.5
const FAST_CURRENT := 0.6
const DEEP_SHARE := 1.5
const SHALLOW_SHARE := 0.4
const FAST_SHARE := 0.7
## The share of what is missing that comes back in a day — by season
## (spring, summer, autumn, winter) — and less once a cell is fished below
## HARD_FISHED of what it holds.
const REGROWTH := 0.2
const SEASON_REGROWTH: Array[float] = [1.2, 1.0, 0.6, 0.2]
const HARD_FISHED := 0.25
const HARD_FISHED_REGROWTH := 0.4
## The spring run: the cell it comes to holds RUN_SHARE times its fish for RUN_DAYS days.
const RUN_SHARE := 2.5
const RUN_DAYS := 4
## A bad fishing year: under this share of the usual (the years before, at
## most USUAL_YEARS of them), and only where at least USUAL_LEAST fish a year
## are usual.
const BAD_SHARE := 0.5
const USUAL_YEARS := 3
const USUAL_LEAST := 20.0

var _world: WorldData
var _current: Callable
var _cells: Dictionary = {} # Vector2i -> [stock, capacity]
var _run_cell := Vector2i.MAX
var _run_until := -1 # day index
var _run_told := false
var _caught: Dictionary = {} # settlement id -> {year: fish}
var _day := -1_000_000


func bind(world: WorldData, current: Callable = Callable()) -> void:
	_world = world
	_current = current
	measure()


## Works out what each cell of water holds (the water as it is now); the fish
## in each keep their share of it. Call when the water has changed much (a
## new world, a box unfolded, a day of river levels).
func measure() -> void:
	var kept := {}
	for cell: Vector2i in _cells:
		var entry: Array = _cells[cell]
		kept[cell] = float(entry[0]) / maxf(float(entry[1]), 0.0001)
	_cells.clear()
	if _world == null:
		return
	var step := _world.height_step
	var size := _world.chunk_size
	for coord in _world.chunk_coords():
		var chunk := _world.get_chunk(coord, false)
		if chunk == null:
			continue
		var origin := WorldCoords.chunk_origin(coord, size)
		for i in chunk.water.size():
			var depth: float = chunk.water[i]
			if depth <= 0.0:
				continue
			var tile := origin + Vector2i(i % size, i / size)
			var share := 1.0
			if depth >= DEEP_LEVELS * step:
				share = DEEP_SHARE
			elif depth < SHALLOW_LEVELS * step:
				share = SHALLOW_SHARE
			if _current.is_valid() and (_current.call(tile) as Vector2).length() > FAST_CURRENT:
				share *= FAST_SHARE
			var cell := cell_of(tile)
			if not _cells.has(cell):
				_cells[cell] = [0.0, 0.0]
			_cells[cell][1] = float(_cells[cell][1]) + share / TILES_PER_FISH
	for cell: Vector2i in _cells:
		var entry: Array = _cells[cell]
		entry[0] = float(entry[1]) * float(kept.get(cell, 0.8))


static func cell_of(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / CELL), floori(float(tile.y) / CELL))


## The middle tile of a cell.
static func middle_of(cell: Vector2i) -> Vector2i:
	return cell * CELL + Vector2i(CELL / 2, CELL / 2)


# --- the stock ---------------------------------------------------------------------------------------

## All the fish in the box (what the box held before FB1).
func total() -> float:
	var sum := 0.0
	for cell: Vector2i in _cells:
		sum += float(_cells[cell][0])
	return sum


func total_capacity() -> float:
	var sum := 0.0
	for cell: Vector2i in _cells:
		sum += float(_cells[cell][1])
	return sum


## Sets all the fish in the box, shared out by what each cell holds (an older
## save's one stock; tests).
func set_total(fish: float) -> void:
	var capacity := total_capacity()
	for cell: Vector2i in _cells:
		var entry: Array = _cells[cell]
		entry[0] = maxf(fish, 0.0) * float(entry[1]) / capacity if capacity > 0.0 else 0.0


## The fish in the cell of `tile` (0: no water there).
func stock_at(tile: Vector2i) -> float:
	var entry: Variant = _cells.get(cell_of(tile))
	return float(entry[0]) if entry != null else 0.0


## Sets the fish in the cell of `tile` (tests, debug).
func set_stock(tile: Vector2i, fish: float) -> void:
	var entry: Variant = _cells.get(cell_of(tile))
	if entry != null:
		entry[0] = maxf(fish, 0.0)


## Every cell with water, the richest first: [[cell, stock]].
func all_cells() -> Array:
	var out: Array = []
	for cell: Vector2i in _cells:
		out.append([cell, float(_cells[cell][0])])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] > b[1] or (a[1] == b[1] and (a[0].y < b[0].y or (a[0].y == b[0].y and a[0].x < b[0].x))))
	return out


## How many fish the cell of `tile` holds when full (0: no water there).
func capacity_at(tile: Vector2i) -> float:
	var entry: Variant = _cells.get(cell_of(tile))
	return float(entry[1]) if entry != null else 0.0


## How full the cell of `tile` is (0 … RUN_SHARE).
func richness_at(tile: Vector2i) -> float:
	var entry: Variant = _cells.get(cell_of(tile))
	return float(entry[0]) / float(entry[1]) if entry != null and float(entry[1]) > 0.0 else 0.0


## Takes up to `amount` fish from the water at `tile` — from its cell, or (no
## tile given: older callers) from wherever there are most. Returns how many.
func take(amount: int, tile: Variant = null) -> int:
	var cell: Variant = cell_of(tile) if typeof(tile) == TYPE_VECTOR2I else _richest()
	if cell == null or not _cells.has(cell):
		return 0
	var entry: Array = _cells[cell]
	var got := mini(amount, floori(float(entry[0])))
	entry[0] = float(entry[0]) - got
	if got > 0 and cell == _run_cell and not _run_told:
		_run_told = true
		run_began.emit(middle_of(cell))
	return got


func _richest() -> Variant:
	var best: Variant = null
	var most := 0.0
	for cell: Vector2i in _cells:
		if float(_cells[cell][0]) > most:
			most = float(_cells[cell][0])
			best = cell
	return best


## The cells near `tile` (within `reach` tiles of their middle), the richest first: [[cell, stock]].
func cells_near(tile: Vector2i, reach: float) -> Array:
	var out: Array = []
	for cell: Vector2i in _cells:
		if Vector2(middle_of(cell) - tile).length() <= reach and float(_cells[cell][0]) >= 1.0:
			out.append([cell, float(_cells[cell][0])])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] > b[1] or (a[1] == b[1] and (a[0].y < b[0].y or (a[0].y == b[0].y and a[0].x < b[0].x))))
	return out


## Where the fish run now (Vector2i.MAX: nowhere).
func run_cell() -> Vector2i:
	return _run_cell


# --- the days -----------------------------------------------------------------------------------------

## A day has passed (`now`): the fish come back, the run comes and goes, and
## at the turn of the year the year's catch is weighed.
func advance_day(now: int, rng: RandomNumberGenerator) -> void:
	var day := Config.time.day_index(now)
	if day == _day:
		return
	_day = day
	var season := Config.time.season_of(now)
	var rate := REGROWTH * SEASON_REGROWTH[clampi(season, 0, 3)]
	for cell: Vector2i in _cells:
		var entry: Array = _cells[cell]
		var stock := float(entry[0])
		var holds := float(entry[1])
		if stock > holds:
			# (A run thins out again once it is over.)
			entry[0] = stock if cell == _run_cell and day < _run_until else maxf(holds, stock * 0.6)
			continue
		var r := rate * (HARD_FISHED_REGROWTH if stock < holds * HARD_FISHED else 1.0)
		entry[0] = minf(stock + (holds - stock) * r, holds)
	if day >= _run_until:
		_run_cell = Vector2i.MAX
	# The first day of spring: the fish run up one stretch of the river.
	if season == Seasons.SPRING and Config.time.day_of_season(now) == 1 and not _cells.is_empty():
		_begin_run(day, rng)
	if Config.time.day_of_season(now) == 1 and season == Seasons.SPRING:
		_weigh_year(Config.time.year_of(now))


func _begin_run(day: int, rng: RandomNumberGenerator) -> void:
	var cells: Array = _cells.keys()
	cells.sort()
	var total_holds := 0.0
	for cell: Vector2i in cells:
		total_holds += float(_cells[cell][1])
	if total_holds <= 0.0:
		return
	var roll := rng.randf() * total_holds
	for cell: Vector2i in cells:
		roll -= float(_cells[cell][1])
		if roll <= 0.0:
			_run_cell = cell
			break
	if _run_cell == Vector2i.MAX:
		_run_cell = cells[-1]
	_run_until = day + RUN_DAYS
	_run_told = false
	var entry: Array = _cells[_run_cell]
	entry[0] = float(entry[1]) * RUN_SHARE


# --- what each settlement catches ---------------------------------------------------------------------

## A settlement's fisher brought in `fish` (`now`).
func note_catch(settlement_id: int, fish: int, now: int) -> void:
	if fish <= 0:
		return
	var year := Config.time.year_of(now)
	if not _caught.has(settlement_id):
		_caught[settlement_id] = {}
	var years: Dictionary = _caught[settlement_id]
	years[year] = int(years.get(year, 0)) + fish


## What `settlement_id` caught in `year`.
func caught(settlement_id: int, year: int) -> int:
	return int((_caught.get(settlement_id, {}) as Dictionary).get(year, 0))


## The year that has just ended (`year` has begun): a settlement that caught
## far fewer than usual has had a bad fishing year.
func _weigh_year(year: int) -> void:
	var ids: Array = _caught.keys()
	ids.sort()
	for settlement_id: int in ids:
		var last := caught(settlement_id, year - 1)
		var before := 0.0
		var counted := 0
		for back in range(2, USUAL_YEARS + 2):
			var years: Dictionary = _caught[settlement_id]
			if years.has(year - back):
				before += float(years[year - back])
				counted += 1
		if counted == 0:
			continue
		var usual := before / counted
		if usual >= USUAL_LEAST and float(last) < usual * BAD_SHARE:
			bad_year.emit(settlement_id, last, usual)
		# (Only the years that may still be weighed are kept.)
		var years: Dictionary = _caught[settlement_id]
		for y: int in years.keys():
			if y < year - USUAL_YEARS - 1:
				years.erase(y)


# --- saving ------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var cells: Array = []
	var keys: Array = _cells.keys()
	keys.sort()
	for cell: Vector2i in keys:
		cells.append([cell, float(_cells[cell][0])])
	var caught_out := {}
	for settlement_id: int in _caught:
		var years := {}
		for y: int in _caught[settlement_id]:
			years[str(y)] = int(_caught[settlement_id][y])
		caught_out[str(settlement_id)] = years
	return {"cells": cells, "run": [_run_cell, _run_until, _run_told], "caught": caught_out, "day": _day}


## Restores the fish (call after bind/measure). False if there was nothing usable.
func from_dict(data: Dictionary) -> bool:
	var saved: Variant = data.get("cells")
	if typeof(saved) != TYPE_ARRAY:
		return false
	for item: Variant in saved:
		if typeof(item) == TYPE_ARRAY and (item as Array).size() == 2 and typeof(item[0]) == TYPE_VECTOR2I and _cells.has(item[0]):
			var stock := float(item[1])
			if is_finite(stock):
				_cells[item[0]][0] = clampf(stock, 0.0, float(_cells[item[0]][1]) * RUN_SHARE)
	var run: Variant = data.get("run")
	if typeof(run) == TYPE_ARRAY and (run as Array).size() == 3 and typeof(run[0]) == TYPE_VECTOR2I:
		_run_cell = run[0]
		_run_until = int(run[1])
		_run_told = bool(run[2])
	var caught_in: Variant = data.get("caught")
	if typeof(caught_in) == TYPE_DICTIONARY:
		for key: Variant in caught_in:
			var years := {}
			if typeof(caught_in[key]) == TYPE_DICTIONARY:
				for y: Variant in caught_in[key]:
					years[int(str(y))] = int(caught_in[key][y])
			_caught[int(str(key))] = years
	_day = int(data.get("day", -1_000_000))
	return true
