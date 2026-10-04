class_name ChunkData
extends RefCounted
## One chunk of tile data (bible §8.3): packed per-tile layers, never per-tile
## objects. Entities are NOT stored here — they live in registries and are
## found through the SpatialIndex.
##
## `modified` means "differs from what the generator produces". Only modified
## chunks are saved; unmodified ones can be dropped and regenerated identically.
## Setters mark the chunk modified and dirty; the generator fills the arrays
## directly and then calls mark_pristine().

enum Terrain { GRASS, DIRT, SAND, ROCK, SNOW, FARMLAND, ROAD, RIVERBED, MUD, ASH }

## Per-tile flag bits (layer `flags`).
const FLAG_SEEN_BY_PLAYER := 1 << 0
const FLAG_EXPLORED_BY_CIV := 1 << 1
const FLAG_MAPPED_BY_CIV := 1 << 2
const FLAG_MODIFIED := 1 << 3
const FLAG_OCCUPIED := 1 << 4
const FLAG_BLOCKED := 1 << 5
const FLAG_SACRED := 1 << 6
const FLAG_RUIN := 1 << 7
const FLAG_EDGE := 1 << 8

## What needs rebuilding/saving (bitmask in `dirty`).
const DIRTY_MESH := 1 << 0
const DIRTY_WATER := 1 << 1
const DIRTY_SAVE := 1 << 2

const _TEMPERATURE_BIAS := 128 # i8 stored in a byte

var coord: Vector2i
var size: int
var modified := false
var dirty := 0

var height: PackedByteArray        ## terrain height level
var terrain: PackedByteArray       ## Terrain enum
var water: PackedFloat32Array      ## water depth above terrain, world units
var moisture: PackedByteArray      ## soil moisture 0..255
var fertility: PackedByteArray     ## soil fertility 0..255
var vegetation: PackedByteArray    ## ground cover density 0..255
var traffic: PackedByteArray       ## foot-traffic accumulator 0..255
var temperature: PackedByteArray   ## local offset, stored biased (see get_temperature_offset)
var flags: PackedInt32Array        ## FLAG_* bits


func _init(chunk_coord: Vector2i = Vector2i.ZERO, chunk_size: int = 16) -> void:
	coord = chunk_coord
	size = chunk_size
	var n := tile_count()
	height.resize(n)
	terrain.resize(n)
	water.resize(n)
	moisture.resize(n)
	fertility.resize(n)
	vegetation.resize(n)
	traffic.resize(n)
	temperature.resize(n)
	temperature.fill(_TEMPERATURE_BIAS)
	flags.resize(n)


func tile_count() -> int:
	return size * size


func index_of(local: Vector2i) -> int:
	return local.y * size + local.x


# --- setters (mark modified + dirty) -------------------------------------------

func set_height(i: int, level: int) -> void:
	height[i] = clampi(level, 0, 255)
	_touch(i, DIRTY_MESH | DIRTY_WATER)


func set_terrain(i: int, type: Terrain) -> void:
	terrain[i] = type
	_touch(i, DIRTY_MESH)


func set_water(i: int, depth: float) -> void:
	water[i] = maxf(depth, 0.0)
	_touch(i, DIRTY_WATER)


func set_moisture(i: int, value: int) -> void:
	moisture[i] = clampi(value, 0, 255)
	_touch(i, 0)


func set_fertility(i: int, value: int) -> void:
	fertility[i] = clampi(value, 0, 255)
	_touch(i, 0)


func set_vegetation(i: int, value: int) -> void:
	vegetation[i] = clampi(value, 0, 255)
	_touch(i, DIRTY_MESH)


func set_traffic(i: int, value: int) -> void:
	traffic[i] = clampi(value, 0, 255)
	_touch(i, 0)


## Local temperature offset in the range -128..127.
func set_temperature_offset(i: int, offset: int) -> void:
	temperature[i] = clampi(offset, -128, 127) + _TEMPERATURE_BIAS
	_touch(i, 0)


func get_temperature_offset(i: int) -> int:
	return temperature[i] - _TEMPERATURE_BIAS


func set_flag(i: int, flag: int, enabled: bool) -> void:
	var before := flags[i]
	var after := (before | flag) if enabled else (before & ~flag)
	if after == before:
		return
	flags[i] = after
	modified = true
	dirty |= DIRTY_SAVE


func has_flag(i: int, flag: int) -> bool:
	return (flags[i] & flag) != 0


# --- state -----------------------------------------------------------------------

## Called by the generator after filling the arrays directly.
func mark_pristine() -> void:
	modified = false
	dirty = DIRTY_MESH | DIRTY_WATER # freshly generated chunks still need meshes


## Layers were written directly (a whole chunk's soil or grass at once,
## without touching every tile): the chunk differs from what the generator
## makes, and must be saved — and drawn anew, if `extra_dirty` says so.
func mark_changed(extra_dirty: int = 0) -> void:
	modified = true
	dirty |= DIRTY_SAVE | extra_dirty


func clear_dirty(bits: int) -> void:
	dirty &= ~bits


func is_dirty(bits: int) -> bool:
	return (dirty & bits) != 0


func to_dict() -> Dictionary:
	return {
		"coord": coord,
		"size": size,
		# Copies: packed arrays are shared by reference, and a snapshot must not
		# change when the live chunk does.
		"height": height.duplicate(),
		"terrain": terrain.duplicate(),
		"water": water.duplicate(),
		"moisture": moisture.duplicate(),
		"fertility": fertility.duplicate(),
		"vegetation": vegetation.duplicate(),
		"traffic": traffic.duplicate(),
		"temperature": temperature.duplicate(),
		"flags": flags.duplicate(),
	}


## A copy of every layer that no longer changes with this chunk (for a worker
## thread to read while the simulation writes here).
func snapshot() -> ChunkData:
	var copy := ChunkData.new(coord, size)
	copy.height = height.duplicate()
	copy.terrain = terrain.duplicate()
	copy.water = water.duplicate()
	copy.moisture = moisture.duplicate()
	copy.fertility = fertility.duplicate()
	copy.vegetation = vegetation.duplicate()
	copy.traffic = traffic.duplicate()
	copy.temperature = temperature.duplicate()
	copy.flags = flags.duplicate()
	copy.modified = modified
	copy.dirty = dirty
	return copy


## Rebuilds a chunk from to_dict() output. Returns null if anything is missing
## or the wrong size (the caller then regenerates the chunk instead).
static func from_dict(data: Dictionary) -> ChunkData:
	if typeof(data.get("coord")) != TYPE_VECTOR2I or typeof(data.get("size")) != TYPE_INT:
		return null
	var chunk_size: int = data["size"]
	if chunk_size < 1 or chunk_size > 256:
		return null
	var chunk := ChunkData.new(data["coord"], chunk_size)
	var n := chunk.tile_count()
	var byte_layers: PackedStringArray = ["height", "terrain", "moisture", "fertility", "vegetation", "traffic", "temperature"]
	for layer in byte_layers:
		var bytes: Variant = data.get(layer)
		if typeof(bytes) != TYPE_PACKED_BYTE_ARRAY or (bytes as PackedByteArray).size() != n:
			return null
		chunk.set(layer, (bytes as PackedByteArray).duplicate())
	var water_layer: Variant = data.get("water")
	var flag_layer: Variant = data.get("flags")
	if typeof(water_layer) != TYPE_PACKED_FLOAT32_ARRAY or (water_layer as PackedFloat32Array).size() != n:
		return null
	if typeof(flag_layer) != TYPE_PACKED_INT32_ARRAY or (flag_layer as PackedInt32Array).size() != n:
		return null
	chunk.water = (water_layer as PackedFloat32Array).duplicate()
	chunk.flags = (flag_layer as PackedInt32Array).duplicate()
	chunk.modified = true # only modified chunks are ever saved
	chunk.dirty = DIRTY_MESH | DIRTY_WATER
	return chunk


func _touch(i: int, extra_dirty: int) -> void:
	modified = true
	flags[i] = flags[i] | FLAG_MODIFIED
	dirty |= DIRTY_SAVE | extra_dirty
