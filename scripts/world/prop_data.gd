class_name PropData
extends RefCounted
## A static thing standing on a tile: tree, rock, bush, hut, campfire, ruin
## (bible §8.3). At most one prop per tile. Resource semantics (quantity,
## regrowth) arrive in M7; buildings become real Building entities in M12.
##
## All fields are integers so generated props are bit-identical everywhere.

enum Kind { TREE, ROCK, BUSH, HUT, CAMPFIRE, RUIN }

## Tree variants 0–1 are broadleaf, 2–3 are conifers (higher ground).
const TREE_CONIFER_FIRST_VARIANT := 2

## Generated ids have this bit set and encode the tile, so they are stable
## without being saved and can never collide with allocator ids.
const GENERATED_ID_BIT := 1 << 62
const _COORD_BIAS := 1 << 23 # supports tiles in ±8,388,608
const _COORD_MASK := (1 << 24) - 1

## Body used for picking, per kind: [height, radius] in tiles at 100% scale.
const PICK_BODY := {
	Kind.TREE: [1.5, 0.40],
	Kind.ROCK: [0.24, 0.26],
	Kind.BUSH: [0.30, 0.28],
	Kind.HUT: [0.94, 0.50],
	Kind.CAMPFIRE: [0.36, 0.26],
	Kind.RUIN: [0.70, 0.42],
}

var id: int = 0
var kind: Kind = Kind.TREE
var tile: Vector2i
var variant: int = 0
## Rotation around the vertical axis in 256ths of a turn.
var rotation_step: int = 0
var scale_percent: int = 100
## Offset from the tile centre in 256ths of a tile (each axis roughly ±77).
var offset_x: int = 0
var offset_y: int = 0


static func generated_id(prop_tile: Vector2i) -> int:
	return GENERATED_ID_BIT | ((prop_tile.x + _COORD_BIAS) << 24) | (prop_tile.y + _COORD_BIAS)


static func is_generated_id(prop_id: int) -> bool:
	return (prop_id & GENERATED_ID_BIT) != 0


## Tile encoded in a generated id.
static func tile_of_generated_id(prop_id: int) -> Vector2i:
	return Vector2i(((prop_id >> 24) & _COORD_MASK) - _COORD_BIAS, (prop_id & _COORD_MASK) - _COORD_BIAS)


func is_generated() -> bool:
	return is_generated_id(id)


## World position on the XZ plane (x = world X, y = world Z).
func position2d() -> Vector2:
	return Vector2(tile.x + 0.5 + offset_x / 256.0, tile.y + 0.5 + offset_y / 256.0)


func rotation_radians() -> float:
	return rotation_step * TAU / 256.0


func scale() -> float:
	return scale_percent / 100.0


## Height and radius of the body a finger can hit (Vector2(height, radius)).
func pick_shape() -> Vector2:
	var body: Array = PICK_BODY.get(kind, [0.5, 0.3])
	return Vector2(body[0], body[1]) * scale()


func spatial_kind() -> int:
	match kind:
		Kind.HUT, Kind.CAMPFIRE:
			return SpatialIndex.KIND_BUILDING
		Kind.RUIN:
			return SpatialIndex.KIND_MYSTERY
		_:
			return SpatialIndex.KIND_RESOURCE_NODE


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "tile": tile, "variant": variant,
		"rotation_step": rotation_step, "scale_percent": scale_percent,
		"offset_x": offset_x, "offset_y": offset_y,
	}


## Null if the record is unusable.
static func from_dict(data: Dictionary) -> PropData:
	if typeof(data.get("id")) != TYPE_INT or typeof(data.get("tile")) != TYPE_VECTOR2I:
		return null
	var kind_value := int(data.get("kind", -1))
	if kind_value < 0 or kind_value >= Kind.size():
		return null
	var prop := PropData.new()
	prop.id = data["id"]
	prop.kind = kind_value as Kind
	prop.tile = data["tile"]
	prop.variant = int(data.get("variant", 0))
	prop.rotation_step = int(data.get("rotation_step", 0)) & 0xFF
	prop.scale_percent = clampi(int(data.get("scale_percent", 100)), 10, 400)
	prop.offset_x = clampi(int(data.get("offset_x", 0)), -128, 128)
	prop.offset_y = clampi(int(data.get("offset_y", 0)), -128, 128)
	return prop
