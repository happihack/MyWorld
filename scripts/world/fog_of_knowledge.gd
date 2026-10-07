class_name FogOfKnowledge
extends RefCounted
## What is known of the box (M13.4, bible §8.7), in three layers, a byte a
## tile in chunks of its own (saved with it — the land's chunks stay as the
## generator made them: knowing a place does not change it):
##   seen by the player   — what the camera has shown close up (WorldView marks it);
##   explored by the civ  — where anyone of the world has been, and what they
##                          saw from there (`SIGHT` tiles all round), once an hour;
##   mapped by the civ    — what is on their maps: none yet (cartography, M18).
## Explorers bring news: the first to see a region finds it ("Ama has found the
## eastern hills"), and the first to reach a wall comes to the Edge — the
## first thing the world knows of the box.

## A chunk's knowledge has changed (for the maps and the fog texture).
signal changed(coords: Array[Vector2i])
## Someone has found a region nobody of the world had seen before.
signal found(person_id: int, region_id: int)
## Someone has stood at a wall of the box.
signal at_the_edge(person_id: int, tile: Vector2i)

## How far people see about them (tiles).
const SIGHT := 6
## Where someone stood and saw nothing new: all of it is known already (it is
## never forgotten), so standing there again is passed over — at a thousand
## people, marking it all again was a quarter of a second an hour (M21).
## Forgotten when the box unfolds (new land past the old walls).
var _done := {}
var _done_in := Rect2i()
## A wall is reached this close (tiles).
const EDGE_REACH := 1

var regions := Regions.new()
## Regions the world has found (ids): those with any land explored — worked
## out again whenever the world is opened (regions are, and their ids change
## when the box unfolds), so one already known is never found twice.
var discovered: Dictionary = {}
var edge_reached := false

const SEEN := 1
const EXPLORED := 2
const MAPPED := 4

var _world: WorldData
var _people: PersonRegistry
var _bits: Dictionary = {} # chunk coord -> PackedByteArray (a byte a tile)
var _last: Dictionary = {} # person id -> tile they last looked about from
var _hour := -1_000_000


func bind(world: WorldData, people: PersonRegistry) -> void:
	_world = world
	_people = people
	_last.clear()
	_bits.clear()
	_done.clear()
	regions.compute(world)


## After what was known is restored: which regions are found.
func settle() -> void:
	_derive_discovered()


func _derive_discovered() -> void:
	discovered.clear()
	for region in regions.regions:
		if _any_explored(region):
			discovered[region.id] = true


func _any_explored(region: Regions.Region) -> bool:
	for block in region.blocks:
		for y in range(block.y * Regions.BLOCK, block.y * Regions.BLOCK + Regions.BLOCK):
			for x in range(block.x * Regions.BLOCK, block.x * Regions.BLOCK + Regions.BLOCK):
				if is_explored(Vector2i(x, y)):
					return true
	return false


## Once a game hour: everyone out of doors looks about.
func advance_to(now: int) -> void:
	@warning_ignore("integer_division")
	var hour := now / 60
	if hour == _hour or _world == null or _people == null:
		return
	_hour = hour
	look_about()


## Everyone out of doors marks what they see (from where they stand now).
func look_about() -> Array[Vector2i]:
	var coords := {}
	for person in _people.all_people():
		if person.has_flag(PersonData.FLAG_INDOORS):
			continue
		var at := person.position
		if _last.get(person.id, Vector2i.MAX) == at:
			continue
		_last[person.id] = at
		var bounds := _world.bounds
		if bounds != _done_in:
			_done_in = bounds
			_done.clear() # (the box has unfolded: new land beyond the old walls)
		if not _done.has(at) and _mark_around(person.id, at, coords) == 0:
			_done[at] = true
		if not edge_reached and (at.x - bounds.position.x <= EDGE_REACH or bounds.end.x - 1 - at.x <= EDGE_REACH
				or at.y - bounds.position.y <= EDGE_REACH or bounds.end.y - 1 - at.y <= EDGE_REACH):
			edge_reached = true
			at_the_edge.emit(person.id, at)
	var out: Array[Vector2i] = []
	for coord: Vector2i in coords:
		out.append(coord)
	if not out.is_empty():
		changed.emit(out)
	return out


## What the player has seen close up: the tiles of `rect`. Returns how many were new.
func mark_seen(rect: Rect2i) -> int:
	if _world == null:
		return 0
	var area := rect.intersection(_world.bounds)
	var fresh := 0
	var coords := {}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var tile := Vector2i(x, y)
			if not _has_bit(tile, SEEN):
				_put_bit(tile, SEEN)
				coords[WorldCoords.tile_to_chunk(tile, _world.chunk_size)] = true
				fresh += 1
	if fresh > 0:
		var out: Array[Vector2i] = []
		for coord: Vector2i in coords:
			out.append(coord)
		changed.emit(out)
	return fresh


## The world's own knowledge, as the map shows it.
func is_explored(tile: Vector2i) -> bool:
	return _has_bit(tile, EXPLORED)


func is_seen(tile: Vector2i) -> bool:
	return _has_bit(tile, SEEN)


func is_mapped(tile: Vector2i) -> bool:
	return _has_bit(tile, MAPPED)


func _has_bit(tile: Vector2i, bit: int) -> bool:
	if _world == null:
		return false
	var bytes: Variant = _bits.get(WorldCoords.tile_to_chunk(tile, _world.chunk_size))
	return bytes != null and ((bytes as PackedByteArray)[WorldCoords.tile_to_index(tile, _world.chunk_size)] & bit) != 0


func _put_bit(tile: Vector2i, bit: int) -> void:
	var coord := WorldCoords.tile_to_chunk(tile, _world.chunk_size)
	var bytes: PackedByteArray = _bits.get(coord, PackedByteArray())
	if bytes.is_empty():
		bytes.resize(_world.chunk_size * _world.chunk_size)
	var i := WorldCoords.tile_to_index(tile, _world.chunk_size)
	bytes[i] = bytes[i] | bit
	_bits[coord] = bytes


## Known to anyone (the player or the world): not in the fog.
func is_known(tile: Vector2i) -> bool:
	return is_seen(tile) or is_explored(tile)


## How much of a region the world has explored (0 … 1).
func explored_share(region: Regions.Region) -> float:
	var known := 0
	for block in region.blocks:
		for y in range(block.y * Regions.BLOCK, block.y * Regions.BLOCK + Regions.BLOCK, 2):
			for x in range(block.x * Regions.BLOCK, block.x * Regions.BLOCK + Regions.BLOCK, 2):
				if is_explored(Vector2i(x, y)):
					known += 1
	return float(known) / maxf(region.blocks.size() * (Regions.BLOCK * Regions.BLOCK / 4.0), 1.0)


## The regions found, in the order of their size (the largest first).
func found_regions() -> Array[Regions.Region]:
	var out: Array[Regions.Region] = []
	for region in regions.regions:
		if discovered.has(region.id):
			out.append(region)
	out.sort_custom(func(a: Regions.Region, b: Regions.Region) -> bool: return a.tiles > b.tiles)
	return out


## The land around home is known from the start (without news of it).
func know_home(tile: Vector2i) -> void:
	var coords := {}
	_mark_around(0, tile, coords, SIGHT * 2)


func _mark_around(person_id: int, at: Vector2i, coords: Dictionary, sight: int = SIGHT) -> int:
	var fresh := 0
	for dy in range(-sight, sight + 1):
		for dx in range(-sight, sight + 1):
			if dx * dx + dy * dy > sight * sight:
				continue
			var tile := at + Vector2i(dx, dy)
			if not _world.is_in_bounds(tile) or _has_bit(tile, EXPLORED):
				continue
			_put_bit(tile, EXPLORED)
			fresh += 1
			coords[WorldCoords.tile_to_chunk(tile, _world.chunk_size)] = true
			var region := regions.region_at(tile)
			if region != null and not discovered.has(region.id):
				discovered[region.id] = true
				if person_id != 0:
					found.emit(person_id, region.id)
	return fresh


func to_dict() -> Dictionary:
	var chunks: Array = []
	var coords: Array = _bits.keys()
	coords.sort()
	for coord: Vector2i in coords:
		chunks.append([coord, (_bits[coord] as PackedByteArray).duplicate()])
	return {"edge": edge_reached, "chunks": chunks}


func from_dict(data: Dictionary) -> void:
	edge_reached = bool(data.get("edge", false))
	var chunks: Variant = data.get("chunks")
	if typeof(chunks) != TYPE_ARRAY or _world == null:
		return
	var size := _world.chunk_size * _world.chunk_size
	for entry: Variant in chunks:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 2:
			continue
		if typeof(entry[0]) != TYPE_VECTOR2I or typeof(entry[1]) != TYPE_PACKED_BYTE_ARRAY or (entry[1] as PackedByteArray).size() != size:
			continue
		_bits[entry[0]] = (entry[1] as PackedByteArray).duplicate()
