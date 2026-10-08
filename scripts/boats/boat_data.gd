class_name BoatData
extends RefCounted
## A boat (FB2, bible §18.2a): a thing of the world, not a picture at the
## landing — built, worn, mended, torn loose and lost; later (FB3) out on the
## water with people in it. Plain data; the BoatSystem moves it.

enum State {
	MOORED, ## at its landing
	OUT, ## out on the water with its crew (FB3)
	DRIFTING, ## torn loose: carried by the current, nobody aboard
	AGROUND, ## came to rest somewhere it was not tied up
	LAID_UP, ## iced in at its landing
}

## How far below the surface a boat reaches (world units), how fast it goes
## (tiles a second, paddled), how many it carries, and what it is made of
## (wood): by kind (PropData.Boat).
const DRAUGHT := {PropData.Boat.RAFT: 0.12, PropData.Boat.CANOE: 0.10, PropData.Boat.PLANK_BOAT: 0.20, PropData.Boat.SAIL: 0.25}
const SPEED := {PropData.Boat.RAFT: 0.6, PropData.Boat.CANOE: 1.2, PropData.Boat.PLANK_BOAT: 1.0, PropData.Boat.SAIL: 1.4}
const CREW := {PropData.Boat.RAFT: 1, PropData.Boat.CANOE: 2, PropData.Boat.PLANK_BOAT: 3, PropData.Boat.SAIL: 4}
## How many fish a boat holds besides what its fisher has in their arms (FB4:
## an armful of six was all a trip brought home — two hours' paddling for it).
const HOLD := {PropData.Boat.RAFT: 6, PropData.Boat.CANOE: 10, PropData.Boat.PLANK_BOAT: 20, PropData.Boat.SAIL: 24}
const WOOD := {PropData.Boat.RAFT: 6, PropData.Boat.CANOE: 10, PropData.Boat.PLANK_BOAT: 16, PropData.Boat.SAIL: 20}

var id := 0
var kind: int = PropData.Boat.RAFT
## The landing it belongs to (a prop id) and its settlement.
var landing_id := 0
var settlement_id := 0
## Where it is (world XZ), which way it points (radians), how high above the
## ground of its tile it floats (world units).
var position := Vector2.ZERO
var heading := 0.0
var height := 0.0
## 1 sound … 0 falling apart.
var condition := 1.0
var state: State = State.MOORED
## Who is aboard (FB3).
var crew: PackedInt64Array = PackedInt64Array()
## What it carries (FB4/FB6).
var load_resource: StringName = &""
var load_amount := 0
## When it was built, and what it has done.
var built_tick := 0
var trips := 0
var caught := 0
## Where a drift began (to tell how far it was carried).
var drift_from := Vector2.ZERO


func tile() -> Vector2i:
	return WorldCoords.world2d_to_tile(position)


func draught() -> float:
	return float(DRAUGHT.get(kind, 0.15))


func speed() -> float:
	return float(SPEED.get(kind, 0.8))


func crew_room() -> int:
	return int(CREW.get(kind, 1))


## Room in the hold for more of `resource` (none for another load).
func hold_room(resource: StringName) -> int:
	if load_amount > 0 and load_resource != resource:
		return 0
	return maxi(int(HOLD.get(kind, 0)) - load_amount, 0)


func to_dict() -> Dictionary:
	return {"id": id, "kind": kind, "landing": landing_id, "settlement": settlement_id,
		"x": position.x, "z": position.y, "heading": heading, "height": height, "condition": condition,
		"state": int(state), "crew": Array(crew), "load": String(load_resource), "load_amount": load_amount,
		"built": built_tick, "trips": trips, "caught": caught, "drift_x": drift_from.x, "drift_z": drift_from.y}


## A boat from saved data (null if unusable).
static func from_dict(data: Dictionary) -> BoatData:
	if typeof(data.get("id")) != TYPE_INT or int(data["id"]) <= 0:
		return null
	var boat := BoatData.new()
	boat.id = int(data["id"])
	boat.kind = clampi(int(data.get("kind", PropData.Boat.RAFT)), PropData.Boat.RAFT, PropData.Boat.SAIL)
	boat.landing_id = int(data.get("landing", 0))
	boat.settlement_id = int(data.get("settlement", 0))
	boat.position = Vector2(float(data.get("x", 0.0)), float(data.get("z", 0.0)))
	if not boat.position.is_finite():
		return null
	boat.heading = float(data.get("heading", 0.0))
	boat.height = maxf(float(data.get("height", 0.0)), 0.0)
	boat.condition = clampf(float(data.get("condition", 1.0)), 0.0, 1.0)
	boat.state = clampi(int(data.get("state", State.MOORED)), 0, State.size() - 1) as State
	for id: Variant in data.get("crew", []):
		boat.crew.append(int(id))
	boat.load_resource = StringName(str(data.get("load", "")))
	boat.load_amount = maxi(int(data.get("load_amount", 0)), 0)
	boat.built_tick = int(data.get("built", 0))
	boat.trips = int(data.get("trips", 0))
	boat.caught = int(data.get("caught", 0))
	boat.drift_from = Vector2(float(data.get("drift_x", boat.position.x)), float(data.get("drift_z", boat.position.y)))
	return boat
