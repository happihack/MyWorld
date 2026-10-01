class_name RngStreams
extends RefCounted
## Named, independently deterministic random streams derived from the world seed
## (bible §8.4). Each system uses its own stream so adding random calls in one
## system never changes the results of another:
##     var rng := rng_streams.stream(&"terrain")
##
## Stream seeds use our own FNV-1a hash rather than String.hash() so they stay
## identical across Godot versions and platforms (saves must stay deterministic).

const _FNV_OFFSET := 0x811C9DC5
const _FNV_PRIME := 0x01000193
const _MASK_32 := 0xFFFFFFFF
const _MASK_31 := 0x7FFFFFFF

var world_seed: int = 0
var _streams: Dictionary = {} # StringName -> RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	world_seed = seed_value


func stream(stream_name: StringName) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = _streams.get(stream_name)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = derive_seed(world_seed, stream_name)
		_streams[stream_name] = rng
	return rng


## Deterministic 64-bit seed for (world_seed, name).
static func derive_seed(seed_value: int, stream_name: StringName) -> int:
	var text := String(stream_name)
	var high := fnv1a_32(text) & _MASK_31
	var low := fnv1a_32(text + "#wiab")
	return seed_value ^ ((high << 32) | low)


## 32-bit FNV-1a over UTF-8 bytes. Intermediate products stay below 2^56, so no
## 64-bit overflow occurs.
static func fnv1a_32(text: String) -> int:
	var h := _FNV_OFFSET
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * _FNV_PRIME) & _MASK_32
	return h


## Random 63-bit seed for brand-new worlds (non-deterministic by design).
static func new_world_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return ((rng.randi() & _MASK_31) << 32) | rng.randi()


func to_dict() -> Dictionary:
	var states := {}
	for stream_name: StringName in _streams:
		states[String(stream_name)] = (_streams[stream_name] as RandomNumberGenerator).state
	return {"world_seed": world_seed, "states": states}


func from_dict(data: Dictionary) -> void:
	world_seed = int(data.get("world_seed", 0))
	_streams.clear()
	var states: Dictionary = data.get("states", {})
	for stream_name: String in states:
		var rng := stream(StringName(stream_name)) # seeds from world_seed
		rng.state = int(states[stream_name])
