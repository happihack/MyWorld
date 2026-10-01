class_name LooseObject
extends RefCounted
## A thing that lies in the world and can be moved (bible §8.3, §23.2): a
## pebble, a rock, a boulder, a log, a fruit, a seed, a strange object.
## Unlike props, loose objects are not tied to one tile: several can share a
## tile, and they can be carried, dropped, pushed and washed away (M3.2–M3.5).
##
## Where it is: `position` on the ground plane (x = world X, y = world Z) plus
## `height_offset` above whatever it rests on, so an object lying on the ground
## follows the ground if the terrain under it changes.

enum Kind { PEBBLE, ROCK, BOULDER, LOG, FRUIT, SEED, STRANGE_OBJECT }
enum State { RESTING, HELD, FALLING, SLIDING }

## Per kind at 100 % size: body radius and height in tiles, mass in kilograms,
## and whether it floats.
const SPECS := {
	Kind.PEBBLE: {"radius": 0.09, "height": 0.08, "mass": 0.3, "floats": false},
	Kind.ROCK: {"radius": 0.26, "height": 0.24, "mass": 14.0, "floats": false},
	Kind.BOULDER: {"radius": 0.42, "height": 0.44, "mass": 190.0, "floats": false},
	Kind.LOG: {"radius": 0.45, "height": 0.22, "mass": 45.0, "floats": true},
	Kind.FRUIT: {"radius": 0.07, "height": 0.12, "mass": 0.15, "floats": true},
	Kind.SEED: {"radius": 0.04, "height": 0.05, "mass": 0.01, "floats": true},
	Kind.STRANGE_OBJECT: {"radius": 0.13, "height": 0.24, "mass": 2.0, "floats": false},
}

## A generated rock at least this big (PropData.scale_percent) is a boulder.
const BOULDER_FROM_SCALE := 110

var id: int = 0
var kind: Kind = Kind.ROCK
var variant: int = 0
## Ground-plane position (x = world X, y = world Z).
var position := Vector2.ZERO
## Height above the surface it rests on (0 = lying on it).
var height_offset := 0.0
## Rotation around the vertical axis, radians.
var yaw := 0.0
var scale_percent: int = 100
var velocity := Vector3.ZERO
var state: State = State.RESTING
## Ids of inhabitants who know about this object (M4+).
var discovered_by := PackedInt64Array()
var placed_by_player := false
## How many times the player has moved it.
var moved_count := 0


## The loose object a generated rock prop turns into: same tile-encoded id,
## place, turn and look, so it is identical on every device and need not be
## saved until it is moved.
static func from_generated_rock(prop: PropData) -> LooseObject:
	var object := LooseObject.new()
	object.id = prop.id
	object.position = prop.position2d()
	object.yaw = prop.rotation_radians()
	object.variant = prop.variant
	if prop.scale_percent >= BOULDER_FROM_SCALE:
		object.kind = Kind.BOULDER
		object.scale_percent = prop.scale_percent - 15 # 95..105 %: boulders vary less
	else:
		object.kind = Kind.ROCK
		object.scale_percent = prop.scale_percent
	return object


func is_generated() -> bool:
	return PropData.is_generated_id(id)


func tile() -> Vector2i:
	return WorldCoords.world2d_to_tile(position)


func scale() -> float:
	return scale_percent / 100.0


## Where it is in the world: on (or `height_offset` above) the ground of its tile.
func world_position(world: WorldData) -> Vector3:
	return Vector3(position.x, world.get_height(tile()) * world.height_step + height_offset, position.y)


func spec() -> Dictionary:
	return SPECS.get(kind, SPECS[Kind.ROCK])


## Kilograms; grows with the cube of the size.
func mass() -> float:
	var s := scale()
	return float(spec()["mass"]) * s * s * s


func radius() -> float:
	return float(spec()["radius"]) * scale()


func height() -> float:
	return float(spec()["height"]) * scale()


func floats() -> bool:
	return bool(spec()["floats"])


## How strongly it gives way to a finger: 1 for an ordinary rock, less for
## heavier things, more for lighter ones.
func give() -> float:
	var ordinary: float = SPECS[Kind.ROCK]["mass"]
	return clampf(sqrt(ordinary / maxf(mass(), 0.001)), 0.2, 1.8)


## Height and radius of the body a finger can hit (Vector2(height, radius)).
func pick_shape() -> Vector2:
	return Vector2(height(), radius())


func is_stone() -> bool:
	return kind == Kind.PEBBLE or kind == Kind.ROCK or kind == Kind.BOULDER


func to_dict() -> Dictionary:
	# Saved objects are at rest: one that is held or in the air is saved lying
	# on the ground below it.
	var above := height_offset if state == State.RESTING else 0.0
	return {
		"id": id, "kind": kind, "variant": variant, "position": position,
		"height_offset": above, "yaw": yaw, "scale_percent": scale_percent,
		"discovered_by": discovered_by, "placed_by_player": placed_by_player,
		"moved_count": moved_count,
	}


## Null if the record is unusable. Saved objects are always at rest.
static func from_dict(data: Dictionary) -> LooseObject:
	if typeof(data.get("id")) != TYPE_INT or typeof(data.get("position")) != TYPE_VECTOR2:
		return null
	var kind_value := int(data.get("kind", -1))
	if kind_value < 0 or kind_value >= Kind.size():
		return null
	var pos: Vector2 = data["position"]
	if not is_finite(pos.x) or not is_finite(pos.y):
		return null
	var object := LooseObject.new()
	object.id = data["id"]
	object.kind = kind_value as Kind
	object.position = pos
	object.variant = int(data.get("variant", 0))
	var above := float(data.get("height_offset", 0.0))
	object.height_offset = maxf(above, 0.0) if is_finite(above) else 0.0
	var turn := float(data.get("yaw", 0.0))
	object.yaw = turn if is_finite(turn) else 0.0
	object.scale_percent = clampi(int(data.get("scale_percent", 100)), 10, 400)
	var known: Variant = data.get("discovered_by", PackedInt64Array())
	if typeof(known) == TYPE_PACKED_INT64_ARRAY:
		object.discovered_by = known
	object.placed_by_player = bool(data.get("placed_by_player", false))
	object.moved_count = maxi(int(data.get("moved_count", 0)), 0)
	return object
