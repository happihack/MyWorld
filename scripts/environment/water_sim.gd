class_name WaterSim
extends Node
## Water that moves (bible §10.3): a cellular heightfield, not fluid physics.
## Every tile has a water depth; each step, water runs to lower neighbours in
## proportion to the difference in surface level (ground + water).
##
## v0 (M3.5):
##  - Only tiles that were disturbed are simulated. Still water is left alone,
##    so the generated river — which lies level — costs nothing and its chunks
##    stay unmodified (and unsaved) until the player does something.
##  - Water is conserved: what leaves one tile arrives in another. Nothing
##    drains through the walls of the box. The only sink is the soil, which
##    slowly soaks up thin water (and gets wetter); everything is accounted for.
##  - A thin film clings to the ground and does not flow, so a spill ends as
##    puddles instead of spreading thinner and thinner for ever.
##  - `current_at()` tells loose objects which way the water carries them:
##    the flow of the simulation, plus the river's own gentle current — a
##    placeholder until springs and inflow arrive with hydrology (M9.3).

## Tiles whose water depth changed in the last step.
signal tiles_changed(tiles: Array[Vector2i])

const STEP_SECONDS := 0.1
const MAX_STEPS_PER_FRAME := 2
## Share of the level difference that moves to one neighbour per step. Must
## stay at or below 0.25 for the four-neighbour scheme to be stable.
const FLOW_SHARE := 0.2
## Level differences smaller than this do not flow (still water stays still).
const MIN_DIFF := 0.004
## Water thinner than this clings to the ground and does not flow.
const FILM := 0.02
## Changes smaller than this are not written back.
const EPSILON := 0.00001
## Water thinner than this is soaked up by soil.
const SOAK_BELOW := 0.08
## Most tiles handled in one step; the rest wait for the next (time budget).
const MAX_TILES_PER_STEP := 600
## Speed (tiles/s) of the river's own current in deep water.
const RIVER_CURRENT := 0.55
const _DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## Depth soaked up per second by soil under thin water (0 = never).
var soak_per_second := 0.008
## Everything the soil has soaked up since the world began.
var soaked_total := 0.0
## Water the player has scooped up and not yet poured out again. It is part
## of the world's water (and saved with it): scooping must not destroy water.
var carried := 0.0
## Time the last frame's stepping took, microseconds (debug overlay).
var last_step_usec := 0

var _world: WorldData
var _generator: WorldGenerator
# The simulation works on its own flat copies of the ground and the water
# (one entry per tile of the box, row by row): no per-tile world lookups in
# the inner loop. Changes are written back to the world tile by tile.
var _origin := Vector2i.ZERO
var _width := 0
var _rows := 0
var _ground := PackedFloat32Array() # ground height, world units
var _depth := PackedFloat32Array() # water depth
var _change := PackedFloat32Array() # scratch: change of depth in the running step
var _marked := PackedByteArray() # scratch: 1 where _change has an entry
var _active: Dictionary = {} # tile index -> true
var _flow: Dictionary = {} # tile index -> Vector2, water moved out last step (depth, by direction)
var _time_bank := 0.0


## `generator` (optional) supplies the river's course for its ambient current.
func bind(world: WorldData, generator: WorldGenerator = null) -> void:
	_world = world
	_generator = generator
	_active.clear()
	_flow.clear()
	_time_bank = 0.0
	soaked_total = 0.0
	carried = 0.0
	_width = 0
	_rows = 0
	if world == null:
		return
	_origin = world.bounds.position
	_width = world.bounds.size.x
	_rows = world.bounds.size.y
	var count := _width * _rows
	_ground.resize(count)
	_depth.resize(count)
	_change.resize(count)
	_change.fill(0.0)
	_marked.resize(count)
	_marked.fill(0)
	var size := world.chunk_size
	for coord in world.chunk_coords():
		var chunk := world.get_chunk(coord)
		if chunk == null:
			continue
		var corner := WorldCoords.chunk_origin(coord, size) - _origin
		for ly in size:
			var row := (corner.y + ly) * _width + corner.x
			for lx in size:
				var i := ly * size + lx
				_ground[row + lx] = chunk.height[i] * world.height_step
				_depth[row + lx] = chunk.water[i]
				# Water in changed chunks may have been saved in mid-flow: let it go on.
				if chunk.modified and chunk.water[i] > 0.0:
					_active[row + lx] = true


# --- changing the water -----------------------------------------------------------------

## Pours `amount` (depth) onto a tile. Returns how much was added.
func add_water(tile: Vector2i, amount: float) -> float:
	if _world == null or not _world.is_in_bounds(tile) or amount <= 0.0 or not is_finite(amount):
		return 0.0
	_world.set_water(tile, _world.get_water(tile) + amount)
	wake(tile)
	return amount


## Takes up to `amount` (depth) from a tile. Returns how much was taken.
func take_water(tile: Vector2i, amount: float) -> float:
	if _world == null or not _world.is_in_bounds(tile) or amount <= 0.0 or not is_finite(amount):
		return 0.0
	var depth := _world.get_water(tile)
	var taken := minf(depth, amount)
	if taken <= 0.0:
		return 0.0
	_world.set_water(tile, depth - taken)
	wake(tile)
	return taken


## Something changed at `tile` (its water, or the ground under it): the tile
## and its neighbours are read from the world again and looked at anew. Call
## this after changing the world's water or height yourself.
func wake(tile: Vector2i) -> void:
	if _world == null or _width == 0:
		return
	for offset: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t := tile + offset
		if not _world.is_in_bounds(t):
			continue
		var i := _index(t)
		_ground[i] = _world.get_height(t) * _world.height_step
		_depth[i] = _world.get_water(t)
		_active[i] = true


# --- saving -----------------------------------------------------------------------------

## The water's books (the depths themselves are saved with their chunks).
func to_dict() -> Dictionary:
	return {"carried": carried, "soaked_total": soaked_total}


## Call after bind().
func from_dict(data: Dictionary) -> void:
	var held := float(data.get("carried", 0.0))
	var soaked := float(data.get("soaked_total", 0.0))
	carried = maxf(held, 0.0) if is_finite(held) else 0.0
	soaked_total = maxf(soaked, 0.0) if is_finite(soaked) else 0.0


# --- queries ----------------------------------------------------------------------------

func active_count() -> int:
	return _active.size()


func is_still() -> bool:
	return _active.is_empty()


## All the water in the world (depth summed over tiles).
func total_volume() -> float:
	var total := 0.0
	if _world != null:
		for chunk in _world.loaded_chunks():
			for depth in chunk.water:
				total += depth
	return total


## Which way, and how fast (tiles/s), the water at `tile` carries what floats on it.
func current_at(tile: Vector2i) -> Vector2:
	if _world == null or not _world.is_in_bounds(tile):
		return Vector2.ZERO
	var depth := _world.get_water(tile)
	if depth <= WaterMesher.MIN_DEPTH:
		return Vector2.ZERO
	var current := Vector2.ZERO
	var moved: Vector2 = _flow.get(_index(tile), Vector2.ZERO)
	if moved != Vector2.ZERO:
		# Depth moved per step, through a column `depth` deep.
		current = (moved / maxf(depth, FILM) / STEP_SECONDS).limit_length(3.0)
	if _generator != null and _world.get_terrain(tile) == ChunkData.Terrain.RIVERBED:
		var strength := RIVER_CURRENT * clampf((depth - 0.1) / 0.3, 0.0, 1.0)
		# Downstream, and gently toward the middle of the channel, so what
		# floats follows the river round its bends instead of nosing into a bank.
		var to_middle := clampf((_generator.river_center_x(tile.y) - (tile.x + 0.5)) * 0.4, -0.6, 0.6)
		current += (_generator.river_direction(tile) + Vector2(to_middle, 0.0)) * strength
	return current


# --- stepping ---------------------------------------------------------------------------

## Advances time. Called every frame; tests call it directly.
func step(delta: float) -> void:
	if _active.is_empty() or _world == null:
		_time_bank = 0.0
		last_step_usec = 0
		if not _flow.is_empty():
			_flow.clear()
		return
	var started := Time.get_ticks_usec()
	_time_bank = minf(_time_bank + delta, STEP_SECONDS * MAX_STEPS_PER_FRAME)
	while _time_bank >= STEP_SECONDS - 0.000001:
		_time_bank -= STEP_SECONDS
		step_once()
		if _active.is_empty():
			_time_bank = 0.0
			break
	last_step_usec = Time.get_ticks_usec() - started


func _process(delta: float) -> void:
	step(delta)


## One fixed step of the simulation.
func step_once() -> void:
	if _world == null or _width == 0:
		return
	var width := _width
	var last_column := width - 1
	var last_row := _rows - 1
	var touched := PackedInt32Array() # indices with an entry in _change
	var flows: Dictionary = {}
	var next: Dictionary = {}
	var handled := 0

	for i: int in _active:
		if handled >= MAX_TILES_PER_STEP:
			next[i] = true # over the budget: next step
			continue
		handled += 1
		var depth := _depth[i]
		var free := depth - FILM # what is not clinging to the ground
		if free <= 0.0:
			continue
		var surface := _ground[i] + depth
		var x := i % width
		var y := i / width
		# Level differences to the four neighbours (0 = no flow that way). At
		# the walls of the box there is no neighbour: nothing leaves.
		var east := 0.0
		var west := 0.0
		var south := 0.0
		var north := 0.0
		if x < last_column:
			east = surface - _ground[i + 1] - _depth[i + 1]
		if x > 0:
			west = surface - _ground[i - 1] - _depth[i - 1]
		if y < last_row:
			south = surface - _ground[i + width] - _depth[i + width]
		if y > 0:
			north = surface - _ground[i - width] - _depth[i - width]
		if east <= MIN_DIFF:
			east = 0.0
		if west <= MIN_DIFF:
			west = 0.0
		if south <= MIN_DIFF:
			south = 0.0
		if north <= MIN_DIFF:
			north = 0.0
		var wanted := (east + west + south + north) * FLOW_SHARE
		if wanted <= 0.0:
			continue
		var share := FLOW_SHARE * minf(1.0, free / wanted) # never give more than there is
		_add_change(touched, i, -(east + west + south + north) * share)
		if east > 0.0:
			_add_change(touched, i + 1, east * share)
		if west > 0.0:
			_add_change(touched, i - 1, west * share)
		if south > 0.0:
			_add_change(touched, i + width, south * share)
		if north > 0.0:
			_add_change(touched, i - width, north * share)
		flows[i] = Vector2(east - west, south - north) * share

	var changed: Array[Vector2i] = []
	var soaked: Dictionary = {}
	for i in touched:
		var change := _change[i]
		_change[i] = 0.0
		_marked[i] = 0
		if absf(change) < EPSILON:
			continue
		var depth := maxf(_depth[i] + change, 0.0)
		_depth[i] = depth
		var tile := _tile(i)
		_world.set_water(tile, depth)
		changed.append(tile)
		soaked[i] = true
		next[i] = true
		var x := i % width
		var y := i / width
		if x < last_column:
			next[i + 1] = true
		if x > 0:
			next[i - 1] = true
		if y < last_row:
			next[i + width] = true
		if y > 0:
			next[i - width] = true

	# Thin water soaks into soil (and keeps being looked at until it is gone).
	if soak_per_second > 0.0:
		var soak := soak_per_second * STEP_SECONDS
		for i: int in _active:
			var depth := _depth[i]
			if depth <= 0.0 or depth >= SOAK_BELOW:
				continue
			var tile := _tile(i)
			var chunk := _world.chunk_at_tile(tile)
			var j := _world.index_at_tile(tile)
			if not _soaks(chunk.terrain[j]):
				continue
			var taken := minf(depth, soak)
			_depth[i] = depth - taken
			chunk.set_water(j, depth - taken)
			chunk.set_moisture(j, chunk.moisture[j] + ceili(taken * 400.0))
			soaked_total += taken
			if not soaked.has(i):
				changed.append(tile)
			if depth - taken > 0.0:
				next[i] = true

	_active = next
	_flow = flows
	if not changed.is_empty():
		tiles_changed.emit(changed)


## Adds to a tile's pending change, remembering which tiles have one.
func _add_change(touched: PackedInt32Array, index: int, amount: float) -> void:
	if _marked[index] == 0:
		_marked[index] = 1
		touched.append(index)
	_change[index] += amount


func _index(tile: Vector2i) -> int:
	return (tile.y - _origin.y) * _width + (tile.x - _origin.x)


func _tile(index: int) -> Vector2i:
	return _origin + Vector2i(index % _width, index / _width)


static func _soaks(terrain: int) -> bool:
	return terrain != ChunkData.Terrain.RIVERBED and terrain != ChunkData.Terrain.ROCK
