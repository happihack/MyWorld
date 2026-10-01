class_name WorldSetup
extends RefCounted
## One-time world creation steps on top of the generated terrain (bible §8.5):
## populate props, choose the starting settlement site, place the first huts
## and a dormant ruin, and validate that the world is livable.
##
## Everything here is deterministic for a given (seed, template, bounds). The
## results are created entities (allocator ids) and are saved with the world.

## Radius of the cleared, flat square a settlement site needs (2 -> 5x5 tiles).
const SITE_RADIUS := 2
## Sites keep this many tiles away from the box walls.
const WALL_MARGIN := 6
## Closer to water than this is flood-prone; farther than MAX is a long walk.
const MIN_WATER_DISTANCE := 3
const IDEAL_WATER_DISTANCE := 5
const MAX_WATER_DISTANCE := 14
const TREE_SEARCH_RADIUS := 9
const HUT_OFFSETS: Array[Vector2i] = [Vector2i(-2, -1), Vector2i(2, -1), Vector2i(0, 2)]
const RUIN_MIN_DISTANCE := 18

## A person can step between tiles whose heights differ by at most this.
const MAX_STEP_LEVELS := 1
## Water deeper than this many height levels cannot be waded (banks are ~0.4
## levels deep, the river bed ~1.4).
const WADE_DEPTH_LEVELS := 0.6

## validate() requirements.
const MIN_BUILDABLE_TILES := 150
const MIN_FOOD_BUSHES := 4
const MIN_TREES := 12
const MIN_ROCKS := 2
const MAX_WATER_WALK := 30


class StartInfo:
	extends RefCounted
	var ok := false
	var settlement_tile := Vector2i.ZERO
	## Id of the settlement itself (given when its first people arrive; 0 before).
	var settlement_id := 0
	var campfire_id := 0
	var hut_ids: Array[int] = []
	var ruin_id := 0
	var ruin_tile := Vector2i.ZERO
	var problems: PackedStringArray = []

	func to_dict() -> Dictionary:
		return {"settlement_tile": settlement_tile, "settlement_id": settlement_id, "campfire_id": campfire_id,
			"hut_ids": hut_ids.duplicate(), "ruin_id": ruin_id, "ruin_tile": ruin_tile}

	## Restores saved start info as-is (it is never recomputed, so later changes
	## to the site scoring cannot move an existing settlement). Null if unusable.
	static func from_dict(data: Dictionary) -> StartInfo:
		if typeof(data.get("settlement_tile")) != TYPE_VECTOR2I:
			return null
		var info := StartInfo.new()
		info.settlement_tile = data["settlement_tile"]
		info.settlement_id = maxi(int(data.get("settlement_id", 0)), 0)
		info.campfire_id = int(data.get("campfire_id", 0))
		info.ruin_id = int(data.get("ruin_id", 0))
		var ruin: Variant = data.get("ruin_tile", Vector2i.ZERO)
		info.ruin_tile = ruin if typeof(ruin) == TYPE_VECTOR2I else Vector2i.ZERO
		var huts: Variant = data.get("hut_ids", [])
		if typeof(huts) == TYPE_ARRAY:
			for id: Variant in huts:
				if typeof(id) == TYPE_INT:
					info.hut_ids.append(id)
		info.ok = true
		return info


## Generates every chunk in bounds and registers what stands and lies on it.
## With a `loose` registry, generated rocks become loose objects (things the
## player can move); without one they stay props.
static func populate_all(world: WorldData, generator: WorldGenerator, props: PropRegistry,
		loose: LooseObjectRegistry = null) -> void:
	for coord in world.chunk_coords():
		populate_chunk(world, generator, props, coord, loose)


static func populate_chunk(world: WorldData, generator: WorldGenerator, props: PropRegistry, coord: Vector2i,
		loose: LooseObjectRegistry = null) -> void:
	if props.is_chunk_populated(coord):
		return
	var chunk := world.get_chunk(coord)
	if chunk == null:
		return
	# What grows and lies in a chunk is decided by the land as it was made, not
	# as it is now: a tree the player flooded or dug beside is still that tree
	# (a changed chunk would otherwise lose or gain props on every load).
	var made := generator.generate_chunk(coord) if chunk.modified else chunk
	var generated := generator.generate_props(made)
	if loose == null:
		props.populate_chunk(coord, generated)
		return
	var standing: Array[PropData] = []
	var lying: Array[LooseObject] = []
	for prop in generated:
		if prop.kind == PropData.Kind.ROCK:
			lying.append(LooseObject.from_generated_rock(prop))
		else:
			standing.append(prop)
	props.populate_chunk(coord, standing)
	loose.populate_chunk(coord, lying)


## Full start-of-world setup. `ids` supplies ids for the created props.
static func create_start(world: WorldData, generator: WorldGenerator, props: PropRegistry, ids: IdAllocator,
		loose: LooseObjectRegistry = null) -> StartInfo:
	var info := StartInfo.new()
	populate_all(world, generator, props, loose)
	var site: Variant = find_settlement_site(world, generator, props)
	if site == null:
		info.problems.append("no suitable settlement site")
		return info
	info.settlement_tile = site
	_place_settlement(info, props, ids, generator.world_seed, loose)
	_place_ruin(info, world, props, ids, generator.world_seed, loose)
	info.problems = validate(world, props, info.settlement_tile, loose)
	info.ok = info.problems.is_empty()
	return info


## Best site for the first settlement, or null if none qualifies. Requires a
## flat, dry (2*SITE_RADIUS+1)^2 square; prefers a short walk to water without
## being on the bank, trees nearby, fertile ground and the middle of the box.
static func find_settlement_site(world: WorldData, generator: WorldGenerator, props: PropRegistry) -> Variant:
	var b := world.bounds
	var inner := b.grow(-WALL_MARGIN)
	if inner.size.x <= 0 or inner.size.y <= 0:
		return null
	var trees := _tree_integral(world, props)
	var best_score := -1
	var best_tile := Vector2i.ZERO
	var found := false
	var center := b.position + b.size / 2
	for y in range(inner.position.y, inner.end.y):
		var river_half := generator.river_half_width_fp(y)
		for x in range(inner.position.x, inner.end.x):
			var tile := Vector2i(x, y)
			# Distance from the water's edge (river + bank), in whole tiles.
			var edge_fp := generator.distance_to_river_fp(tile) - river_half - WorldGenerator.FP * 3 / 2
			var water_distance := edge_fp / WorldGenerator.FP
			if water_distance < MIN_WATER_DISTANCE or water_distance > MAX_WATER_DISTANCE:
				continue
			if not _is_flat_dry_square(world, tile, SITE_RADIUS):
				continue
			var tree_count := _count_in_square(trees, b, tile, TREE_SEARCH_RADIUS)
			var score := 1000
			score -= absi(water_distance - IDEAL_WATER_DISTANCE) * 40
			score += mini(tree_count, 25) * 12
			score += world.chunk_at_tile(tile).fertility[world.index_at_tile(tile)] / 4
			score -= (absi(x - center.x) + absi(y - center.y)) * 4
			# Deterministic tie-break so equal scores never depend on scan order.
			score = score * 64 + (HashNoise.hash2(x, y, generator.world_seed & 0xFFFFFFFF) & 63)
			if score > best_score:
				best_score = score
				best_tile = tile
				found = true
	return best_tile if found else null


## Everything a starting band needs must be reachable on foot from the site.
static func validate(world: WorldData, props: PropRegistry, settlement_tile: Vector2i,
		loose: LooseObjectRegistry = null) -> PackedStringArray:
	var problems := PackedStringArray()
	if not world.is_in_bounds(settlement_tile) or not is_walkable(world, settlement_tile):
		problems.append("settlement tile is not walkable")
		return problems
	var reach := _flood_walkable(world, settlement_tile)
	var buildable := 0
	var bushes := 0
	var trees := 0
	var rocks := 0
	var nearest_water := -1
	for tile: Vector2i in reach:
		var steps: int = reach[tile]
		var chunk := world.chunk_at_tile(tile)
		var i := world.index_at_tile(tile)
		var terrain := chunk.terrain[i]
		if chunk.water[i] <= 0.0 and (terrain == ChunkData.Terrain.GRASS or terrain == ChunkData.Terrain.DIRT) \
				and not props.has_prop_at(tile):
			buildable += 1
		if _touches_water(world, tile) and (nearest_water < 0 or steps < nearest_water):
			nearest_water = steps
		var prop := props.prop_at(tile)
		if prop != null:
			match prop.kind:
				PropData.Kind.BUSH: bushes += 1
				PropData.Kind.TREE: trees += 1
				PropData.Kind.ROCK: rocks += 1
	if loose != null:
		for object in loose.all_objects():
			if object.is_stone() and reach.has(object.tile()):
				rocks += 1
	if nearest_water < 0:
		problems.append("no water reachable on foot")
	elif nearest_water > MAX_WATER_WALK:
		problems.append("water is %d steps away (max %d)" % [nearest_water, MAX_WATER_WALK])
	if buildable < MIN_BUILDABLE_TILES:
		problems.append("only %d buildable tiles reachable (need %d)" % [buildable, MIN_BUILDABLE_TILES])
	if bushes < MIN_FOOD_BUSHES:
		problems.append("only %d food bushes reachable (need %d)" % [bushes, MIN_FOOD_BUSHES])
	if trees < MIN_TREES:
		problems.append("only %d trees reachable (need %d)" % [trees, MIN_TREES])
	if rocks < MIN_ROCKS:
		problems.append("only %d rocks reachable (need %d)" % [rocks, MIN_ROCKS])
	return problems


## Can a person stand here? (Dry or shallow water; props do not block yet.)
static func is_walkable(world: WorldData, tile: Vector2i) -> bool:
	return world.is_in_bounds(tile) and world.get_water(tile) <= WADE_DEPTH_LEVELS * world.height_step


static func can_step(world: WorldData, from: Vector2i, to: Vector2i) -> bool:
	return is_walkable(world, to) and absi(world.get_height(to) - world.get_height(from)) <= MAX_STEP_LEVELS


# --- placement -------------------------------------------------------------------

static func _place_settlement(info: StartInfo, props: PropRegistry, ids: IdAllocator, seed_value: int,
		loose: LooseObjectRegistry = null) -> void:
	var site := info.settlement_tile
	# Clear the site: the band camps in an open glade.
	for dy in range(-SITE_RADIUS, SITE_RADIUS + 1):
		for dx in range(-SITE_RADIUS, SITE_RADIUS + 1):
			_clear_tile(site + Vector2i(dx, dy), props, loose)
	var fire := _make_prop(ids, PropData.Kind.CAMPFIRE, site, seed_value)
	fire.offset_x = 0
	fire.offset_y = 0
	props.add(fire)
	info.campfire_id = fire.id
	for offset in HUT_OFFSETS:
		var hut := _make_prop(ids, PropData.Kind.HUT, site + offset, seed_value)
		hut.offset_x = 0
		hut.offset_y = 0
		hut.scale_percent = 100
		# Doors face the fire: 0 = +X, 64 = +Z (a quarter turn each 64 steps).
		hut.rotation_step = roundi(Vector2(-offset).angle() / TAU * 256.0) & 0xFF
		props.add(hut)
		info.hut_ids.append(hut.id)


## One dormant ruin, far from the settlement, on dry walkable ground (the full
## mystery system arrives in M18; this proves the pipeline).
static func _place_ruin(info: StartInfo, world: WorldData, props: PropRegistry, ids: IdAllocator, seed_value: int,
		loose: LooseObjectRegistry = null) -> void:
	var b := world.bounds.grow(-3)
	var best_score := -1
	var best_tile := Vector2i.ZERO
	var found := false
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			var tile := Vector2i(x, y)
			var distance := maxi(absi(x - info.settlement_tile.x), absi(y - info.settlement_tile.y))
			if distance < RUIN_MIN_DISTANCE or world.get_water(tile) > 0.0:
				continue
			var terrain := world.get_terrain(tile)
			if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT:
				continue
			# Far away and high up, with a seeded shuffle among similar spots.
			var score := distance * 8 + world.get_height(tile) * 6 \
				+ (HashNoise.hash2(x, y, (seed_value ^ 0x5EED) & 0xFFFFFFFF) & 63)
			if score > best_score:
				best_score = score
				best_tile = tile
				found = true
	if not found:
		return
	_clear_tile(best_tile, props, loose)
	var ruin := _make_prop(ids, PropData.Kind.RUIN, best_tile, seed_value)
	props.add(ruin)
	info.ruin_id = ruin.id
	info.ruin_tile = best_tile


## Removes whatever stands or lies on a tile.
static func _clear_tile(tile: Vector2i, props: PropRegistry, loose: LooseObjectRegistry) -> void:
	var existing := props.prop_at(tile)
	if existing != null:
		props.remove(existing.id)
	if loose != null:
		for object in loose.objects_at(tile):
			loose.remove(object.id)


static func _make_prop(ids: IdAllocator, kind: PropData.Kind, tile: Vector2i, seed_value: int) -> PropData:
	var h := HashNoise.hash2(tile.x, tile.y, (seed_value ^ 0xC0FFEE) & 0xFFFFFFFF)
	var prop := PropData.new()
	prop.id = ids.next_id()
	prop.kind = kind
	prop.tile = tile
	prop.variant = h & 1
	prop.rotation_step = (h >> 1) & 0xFF
	prop.scale_percent = 100
	return prop


# --- helpers ---------------------------------------------------------------------

static func _is_flat_dry_square(world: WorldData, center: Vector2i, radius: int) -> bool:
	var level := world.get_height(center)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var tile := center + Vector2i(dx, dy)
			if not world.is_in_bounds(tile) or world.get_height(tile) != level or world.get_water(tile) > 0.0:
				return false
			var terrain := world.get_terrain(tile)
			if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT:
				return false
	return true


static func _touches_water(world: WorldData, tile: Vector2i) -> bool:
	if world.get_water(tile) > 0.0:
		return true
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if world.get_water(tile + d) > 0.0:
			return true
	return false


## Breadth-first walk from `start`; returns tile -> steps for every reachable tile.
static func _flood_walkable(world: WorldData, start: Vector2i) -> Dictionary:
	var steps := {start: 0}
	var frontier: Array[Vector2i] = [start]
	var head := 0
	while head < frontier.size():
		var tile := frontier[head]
		head += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = tile + d
			if not steps.has(next) and can_step(world, tile, next):
				steps[next] = int(steps[tile]) + 1
				frontier.append(next)
	return steps


## Summed-area table of tree positions over the bounds: entry (x+1, y+1) holds
## the number of trees in the rectangle from the bounds origin to (x, y).
static func _tree_integral(world: WorldData, props: PropRegistry) -> PackedInt32Array:
	var b := world.bounds
	var w := b.size.x + 1
	var table := PackedInt32Array()
	table.resize(w * (b.size.y + 1))
	for y in b.size.y:
		var row := 0
		for x in b.size.x:
			var prop := props.prop_at(b.position + Vector2i(x, y))
			if prop != null and prop.kind == PropData.Kind.TREE:
				row += 1
			table[(y + 1) * w + (x + 1)] = table[y * w + (x + 1)] + row
	return table


static func _count_in_square(table: PackedInt32Array, bounds: Rect2i, center: Vector2i, radius: int) -> int:
	var w := bounds.size.x + 1
	var x0 := clampi(center.x - radius - bounds.position.x, 0, bounds.size.x)
	var y0 := clampi(center.y - radius - bounds.position.y, 0, bounds.size.y)
	var x1 := clampi(center.x + radius + 1 - bounds.position.x, 0, bounds.size.x)
	var y1 := clampi(center.y + radius + 1 - bounds.position.y, 0, bounds.size.y)
	return table[y1 * w + x1] - table[y0 * w + x1] - table[y1 * w + x0] + table[y0 * w + x0]
