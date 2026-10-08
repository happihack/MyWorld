class_name PredatorHabitat
extends RefCounted
## How well a place suits a big predator (PR1): there are no biomes, so a
## predator's land is a rule over what is there — trees around, water near,
## high or rocky ground, open grass — weighted by its species
## (SpeciesDef.habitat_*). Mountain and forest worlds (the other templates)
## will make them regional by themselves.

## How far around a place its trees are counted, and how near water counts.
const TREE_REACH := 3
const WATER_REACH := 6
## Ground this many height levels above the settlement's is "high" outright.
const HIGH_LEVELS := 4.0


## 0 … about 5: how much `def` would like it at `tile`. `floor_level`: the
## height of the settlement's ground (what is high is high above it).
static func score(world: WorldData, props: PropRegistry, def: SpeciesDef, tile: Vector2i, floor_level: int) -> float:
	if world == null or not world.is_in_bounds(tile):
		return 0.0
	var trees := tree_share(props, tile)
	var wet := 1.0 if water_near(world, tile) else 0.0
	var high := high_share(world, tile, floor_level)
	var terrain := world.get_terrain(tile)
	var open := (1.0 - trees) if terrain == ChunkData.Terrain.GRASS else 0.0
	return def.habitat_trees * trees + def.habitat_water * wet + def.habitat_high * high + def.habitat_open * open


## The share of the ground around `tile` that stands under trees (0 … 1).
static func tree_share(props: PropRegistry, tile: Vector2i) -> float:
	if props == null:
		return 0.0
	var trees := 0
	var side := TREE_REACH * 2 + 1
	for dy in range(-TREE_REACH, TREE_REACH + 1):
		for dx in range(-TREE_REACH, TREE_REACH + 1):
			var there := props.prop_at(tile + Vector2i(dx, dy))
			if there != null and there.kind == PropData.Kind.TREE:
				trees += 1
	# (A wood is a third of the ground under trees: that counts as full.)
	return clampf(float(trees) / (side * side) * 3.0, 0.0, 1.0)


static func water_near(world: WorldData, tile: Vector2i) -> bool:
	for dy in range(-WATER_REACH, WATER_REACH + 1):
		for dx in range(-WATER_REACH, WATER_REACH + 1):
			var there := tile + Vector2i(dx, dy)
			if world.is_in_bounds(there) and world.get_water(there) > 0.0:
				return true
	return false


## How high or rocky (0 … 1).
static func high_share(world: WorldData, tile: Vector2i, floor_level: int) -> float:
	var terrain := world.get_terrain(tile)
	if terrain == ChunkData.Terrain.ROCK or terrain == ChunkData.Terrain.SNOW:
		return 1.0
	return clampf((world.get_height(tile) - floor_level) / HIGH_LEVELS, 0.0, 1.0)
