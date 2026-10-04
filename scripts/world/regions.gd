class_name Regions
extends RefCounted
## The regions of the box (M13.4, bible §8.7): worked out from the land
## itself — blocks of 8 × 8 tiles sorted into water, hills and lowland by
## their water, rock and height, joined with their like into regions — and
## named by what they are and where they lie: "the river", "the eastern
## hills", "the valley". (Names from the people's own words come with M17.)

const BLOCK := 8
## Regions of fewer blocks join the neighbour they share most of their edge with.
const LEAST_BLOCKS := 3
## Water on at least this share of a block makes it water; rock on this
## share, or ground this high (a share of the highest), makes it hills.
const WATER_FROM := 0.35
const ROCK_FROM := 0.4
const HIGH_FROM := 0.55
## Within this share of the box's size of its middle, a region lies "in the middle".
const MIDDLE := 0.18

enum Kind { WATER, HILLS, LOWLAND }


class Region:
	extends RefCounted
	var id := 0 ## stable: from its first block (the one most north-west)
	var kind: int = Kind.LOWLAND
	var name := ""
	var blocks: Array[Vector2i] = []
	var centre := Vector2.ZERO
	var tiles := 0


var regions: Array[Region] = []
var _world: WorldData
var _by_block: Dictionary = {} # block -> Region


## Works the regions out from the world as it is.
func compute(world: WorldData) -> void:
	_world = world
	regions.clear()
	_by_block.clear()
	if world == null:
		return
	var kinds := {}
	var b := world.bounds
	var high := float(Config.world.height_levels - 1) * HIGH_FROM
	for by in range(floori(float(b.position.y) / BLOCK), ceili(float(b.end.y) / BLOCK)):
		for bx in range(floori(float(b.position.x) / BLOCK), ceili(float(b.end.x) / BLOCK)):
			var water := 0
			var rock := 0
			var height := 0
			var count := 0
			for y in range(by * BLOCK, by * BLOCK + BLOCK):
				for x in range(bx * BLOCK, bx * BLOCK + BLOCK):
					var tile := Vector2i(x, y)
					if not world.is_in_bounds(tile):
						continue
					count += 1
					if world.get_water(tile) > Pathfinder.WET_DEPTH:
						water += 1
					if world.get_terrain(tile) == ChunkData.Terrain.ROCK or world.get_terrain(tile) == ChunkData.Terrain.SNOW:
						rock += 1
					height += world.get_height(tile)
			if count == 0:
				continue
			var kind := Kind.LOWLAND
			if float(water) / count >= WATER_FROM:
				kind = Kind.WATER
			elif float(rock) / count >= ROCK_FROM or float(height) / count >= high:
				kind = Kind.HILLS
			kinds[Vector2i(bx, by)] = kind
	# Joined with their like.
	var blocks: Array = kinds.keys()
	blocks.sort_custom(func(a: Vector2i, c: Vector2i) -> bool: return a.y < c.y or (a.y == c.y and a.x < c.x))
	for block: Vector2i in blocks:
		if _by_block.has(block):
			continue
		var region := Region.new()
		region.kind = kinds[block]
		region.id = _id_of(block)
		var queue: Array[Vector2i] = [block]
		_by_block[block] = region
		while not queue.is_empty():
			var at: Vector2i = queue.pop_back()
			region.blocks.append(at)
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next := at + step
				if kinds.has(next) and not _by_block.has(next) and kinds[next] == region.kind:
					_by_block[next] = region
					queue.append(next)
		regions.append(region)
	_merge_small()
	for region in regions:
		_measure(region)
	_name_all()


func region_at(tile: Vector2i) -> Region:
	return _by_block.get(Vector2i(floori(float(tile.x) / BLOCK), floori(float(tile.y) / BLOCK)))


func get_region(id: int) -> Region:
	for region in regions:
		if region.id == id:
			return region
	return null


static func _id_of(block: Vector2i) -> int:
	return (block.y + 4096) * 8192 + (block.x + 4096)


## Small regions join the neighbour they touch most.
func _merge_small() -> void:
	var merged := true
	while merged:
		merged = false
		for region in regions:
			if region.blocks.size() >= LEAST_BLOCKS:
				continue
			var touching := {}
			for block in region.blocks:
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var other: Region = _by_block.get(block + step)
					if other != null and other != region:
						touching[other] = int(touching.get(other, 0)) + 1
			if touching.is_empty():
				continue
			var best: Region = null
			for other: Region in touching:
				if best == null or int(touching[other]) > int(touching[best]) or (touching[other] == touching[best] and other.id < best.id):
					best = other
			for block in region.blocks:
				best.blocks.append(block)
				_by_block[block] = best
			best.id = mini(best.id, region.id)
			regions.erase(region)
			merged = true
			break


func _measure(region: Region) -> void:
	var sum := Vector2.ZERO
	region.tiles = 0
	for block in region.blocks:
		for y in range(block.y * BLOCK, block.y * BLOCK + BLOCK):
			for x in range(block.x * BLOCK, block.x * BLOCK + BLOCK):
				if _world.is_in_bounds(Vector2i(x, y)):
					sum += Vector2(x, y) + Vector2(0.5, 0.5)
					region.tiles += 1
	region.centre = sum / maxf(region.tiles, 1.0)


func _name_all() -> void:
	var middle := Rect2(_world.bounds).get_center()
	var reach := maxf(_world.bounds.size.x, _world.bounds.size.y)
	# The largest water is the river; the rest by direction. The larger keeps a name taken twice.
	var by_size := regions.duplicate()
	by_size.sort_custom(func(a: Region, c: Region) -> bool: return a.tiles > c.tiles or (a.tiles == c.tiles and a.id < c.id))
	var taken := {}
	var river_named := false
	for region: Region in by_size:
		var offset := region.centre - middle
		var direction := "" if offset.length() < reach * MIDDLE else _direction(offset)
		var name := ""
		match region.kind:
			Kind.WATER:
				if not river_named:
					name = MemoryText.translate("REGION_RIVER")
					river_named = true
				else:
					name = MemoryText.translate("REGION_LAKE" if direction == "" else "REGION_LAKE_DIR").format({"dir": direction})
			Kind.HILLS:
				name = MemoryText.translate("REGION_HILLS_MIDDLE" if direction == "" else "REGION_HILLS").format({"dir": direction})
			_:
				name = MemoryText.translate("REGION_VALLEY" if direction == "" else "REGION_LOWLAND").format({"dir": direction})
		if taken.has(name):
			name = MemoryText.translate("REGION_FAR").format({"name": name})
		taken[name] = true
		region.name = name


## "northern", "south-eastern", … of an offset from the middle (z grows south).
static func _direction(offset: Vector2) -> String:
	var angle := fposmod(rad_to_deg(atan2(offset.x, -offset.y)), 360.0) # 0 north, 90 east
	var keys := ["DIR_NORTH", "DIR_NORTH_EAST", "DIR_EAST", "DIR_SOUTH_EAST", "DIR_SOUTH", "DIR_SOUTH_WEST", "DIR_WEST", "DIR_NORTH_WEST"]
	return MemoryText.translate(keys[int(round(angle / 45.0)) % 8])
