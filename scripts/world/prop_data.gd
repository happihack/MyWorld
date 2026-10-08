class_name PropData
extends RefCounted
## A static thing standing on a tile: tree, rock, bush, hut, campfire, ruin
## (bible §8.3). At most one prop per tile. Trees, bushes and rocks are
## resource nodes (see ResourceNodes); buildings become real Building
## entities in M12.
##
## All fields are integers so generated props are bit-identical everywhere.

## (Saved by number: append, never reorder.)
enum Kind { TREE, ROCK, BUSH, HUT, CAMPFIRE, RUIN, CROP, GRAVE, SITE, STOREHOUSE, WELL, WORKSHOP, BRIDGE,
	KILN, HERB_RACK, RECORD_STONE, STONE_CIRCLE, SHRINE, CEMETERY, LANDING, WOODSHED, MUSHROOM, ROOTS, BORDER_STONES }
## Wild food that grows on the ground (the owner, 2026-10-06), foraged like a
## bush: mushrooms on damp ground in and by the woods, roots in the meadows.
const FORAGE: Array[int] = [Kind.BUSH, Kind.MUSHROOM, Kind.ROOTS]
## Buildings: what is built, decays, is damaged and repaired (M12.1).
const BUILDINGS: Array[int] = [Kind.HUT, Kind.STOREHOUSE, Kind.WELL, Kind.WORKSHOP, Kind.BRIDGE,
	Kind.KILN, Kind.HERB_RACK, Kind.RECORD_STONE, Kind.STONE_CIRCLE, Kind.SHRINE, Kind.LANDING, Kind.WOODSHED]
## A landing (M19.5): its variant is the boat moored at it (0: none yet).
enum Boat { NONE, RAFT, CANOE, PLANK_BOAT, SAIL }
## Solid: nobody walks through it.
const SOLID: Array[int] = [Kind.HUT, Kind.CAMPFIRE, Kind.RUIN, Kind.SITE, Kind.STOREHOUSE, Kind.WELL, Kind.WORKSHOP,
	Kind.KILN, Kind.HERB_RACK, Kind.RECORD_STONE, Kind.STONE_CIRCLE, Kind.SHRINE, Kind.WOODSHED]
## A building's full condition (see `condition`).
const SOUND := 1000
## A bridge (M12.2) is built where it stands: posts (0), beams (1), then it
## can be walked (this variant).
const BRIDGE_DONE := 2
## How far above the bed of the ford a bridge's deck is (world units).
const BRIDGE_DECK := 0.3

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
	Kind.CROP: [0.30, 0.42],
	Kind.GRAVE: [0.40, 0.34],
	Kind.SITE: [0.80, 0.46],
	Kind.STOREHOUSE: [0.90, 0.50],
	Kind.WELL: [0.60, 0.40],
	Kind.WORKSHOP: [0.90, 0.50],
	Kind.BRIDGE: [0.36, 0.48],
	Kind.KILN: [0.70, 0.44],
	Kind.HERB_RACK: [0.70, 0.40],
	Kind.RECORD_STONE: [0.80, 0.30],
	Kind.BORDER_STONES: [0.45, 0.40],
	Kind.STONE_CIRCLE: [0.60, 0.48],
	Kind.SHRINE: [0.70, 0.36],
	Kind.CEMETERY: [0.50, 0.95],
	Kind.LANDING: [0.40, 0.50],
	Kind.WOODSHED: [0.70, 0.50],
	Kind.MUSHROOM: [0.16, 0.22],
	Kind.ROOTS: [0.22, 0.26],
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
## How much of what the prop bears has been taken (fruit shaken from a tree).
var taken: int = 0
## Resource node (see ResourceNodes): units left of what it yields, or -1 for
## one that is whole (nothing taken, or all grown back) — which is how every
## prop is made, so untouched nodes need not be saved.
var stock: int = -1
## The tick up to which regrowth has been worked out (while stock >= 0).
var stock_tick: int = 0
## A tree whose last wood was taken: a stump, then a sapling, until it has
## grown back whole.
var felled: bool = false
## Crops only (see Farming): how far it has grown (0 … 1000), how healthy it
## is (0 … 1000) and when it was last tended. `variant` is its stage.
var growth: int = 0
var vigor: int = 1000
var tended_tick: int = 0
## A building's condition, 0 (fallen) … SOUND (as built): floods and storms
## take from it, repairs give it back, neglect wears it away (M12.1).
var condition: int = SOUND


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


const _BEARS_SALT := 0xF2017

## How many fruit (broadleaf) or cones (conifer) a tree bears when untouched.
## Decided by its tile, so it is the same on every device.
func bears() -> int:
	if kind != Kind.TREE:
		return 0
	var h := HashNoise.hash2(tile.x, tile.y, _BEARS_SALT)
	return 1 + int(h % 2) if is_conifer() else 2 + int(h % 3)


## What is still on the tree (nothing on a stump or a sapling).
func bears_left() -> int:
	return 0 if felled else maxi(bears() - taken, 0)


func is_conifer() -> bool:
	return kind == Kind.TREE and variant >= TREE_CONIFER_FIRST_VARIANT


## Radius (tiles, at 100 % scale) of the part of each kind that loose objects
## bump into: walls and stone, a tree's trunk. Bushes give way: no entry.
const COLLISION_RADIUS := {
	Kind.TREE: 0.09,
	Kind.ROCK: 0.24,
	Kind.HUT: 0.42,
	Kind.CAMPFIRE: 0.22,
	Kind.RUIN: 0.40,
}


## Radius of the solid part of the prop (0 if things pass through it).
func collision_radius() -> float:
	return float(COLLISION_RADIUS.get(kind, 0.0)) * scale()


## What a finger can hit of a felled tree: the stump, or the young tree.
const FELLED_BODY: Array = [0.5, 0.2]


## Height and radius of the body a finger can hit (Vector2(height, radius)).
func pick_shape() -> Vector2:
	var body: Array = FELLED_BODY if felled else PICK_BODY.get(kind, [0.5, 0.3])
	return Vector2(body[0], body[1]) * scale()


func spatial_kind() -> int:
	match kind:
		Kind.HUT, Kind.CAMPFIRE, Kind.GRAVE, Kind.SITE, Kind.STOREHOUSE, Kind.WELL, Kind.WORKSHOP, Kind.BRIDGE, Kind.KILN, Kind.HERB_RACK, Kind.RECORD_STONE, Kind.STONE_CIRCLE, Kind.SHRINE, Kind.CEMETERY, Kind.LANDING, Kind.WOODSHED, Kind.BORDER_STONES:
			return SpatialIndex.KIND_BUILDING
		Kind.RUIN:
			return SpatialIndex.KIND_MYSTERY
		_:
			return SpatialIndex.KIND_RESOURCE_NODE


func to_dict() -> Dictionary:
	var record := {
		"id": id, "kind": kind, "tile": tile, "variant": variant,
		"rotation_step": rotation_step, "scale_percent": scale_percent,
		"offset_x": offset_x, "offset_y": offset_y, "taken": taken,
		"stock": stock, "stock_tick": stock_tick, "felled": felled,
	}
	if kind == Kind.CROP:
		record["growth"] = growth
		record["vigor"] = vigor
		record["tended_tick"] = tended_tick
	if condition != SOUND:
		record["condition"] = condition
	return record


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
	prop.taken = maxi(int(data.get("taken", 0)), 0)
	prop.stock = maxi(int(data.get("stock", -1)), -1)
	prop.stock_tick = int(data.get("stock_tick", 0))
	prop.felled = bool(data.get("felled", false)) and prop.kind == Kind.TREE and prop.stock >= 0
	if prop.kind == Kind.CROP:
		prop.growth = clampi(int(data.get("growth", 0)), 0, 1000)
		prop.vigor = clampi(int(data.get("vigor", 1000)), 0, 1000)
		prop.tended_tick = int(data.get("tended_tick", 0))
	prop.condition = clampi(int(data.get("condition", SOUND)), 0, SOUND)
	return prop


func is_building() -> bool:
	return BUILDINGS.has(kind)
