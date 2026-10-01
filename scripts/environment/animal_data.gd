class_name AnimalData
extends RefCounted
## One animal (bible §12): plain data, like a person but with much less to
## it. Where it is, what it is doing, where its group lives.

enum State { GRAZE, WANDER, DRINK, SLEEP, FLEE, HUNT }

var id: int = 0
var species: StringName = &""
## Ground-plane position (x = world X, y = world Z) and the way it faces (radians).
var position := Vector2.ZERO
var facing := 0.0
## The middle of where its group lives, and which group.
var home := Vector2.ZERO
var group: int = 0
var state: State = State.GRAZE
## The tick at which it thinks again about what to do.
var state_until: int = 0
## Where it is going (WANDER, DRINK, FLEE), or the animal it is after (HUNT).
var target := Vector2.ZERO
var quarry_id: int = 0
var born_tick: int = 0
## The tick of its last kill (predators) and the game day it last drank.
var fed_tick: int = 0
var drank_day: int = -1


func tile() -> Vector2i:
	return WorldCoords.world2d_to_tile(position)


func age_days(now: int) -> int:
	@warning_ignore("integer_division")
	return maxi(now - born_tick, 0) / TimeConfig.MINUTES_PER_DAY


func is_moving() -> bool:
	return state == State.WANDER or state == State.DRINK or state == State.FLEE or state == State.HUNT


func to_dict() -> Dictionary:
	return {
		"id": id, "species": String(species), "position": position, "facing": facing, "home": home, "group": group,
		"state": state, "state_until": state_until, "target": target, "quarry": quarry_id,
		"born": born_tick, "fed": fed_tick, "drank": drank_day,
	}


## Null if the record is unusable.
static func from_dict(data: Dictionary) -> AnimalData:
	if typeof(data.get("id")) != TYPE_INT or int(data["id"]) <= 0 or typeof(data.get("position")) != TYPE_VECTOR2:
		return null
	var at: Vector2 = data["position"]
	if not is_finite(at.x) or not is_finite(at.y) or str(data.get("species", "")) == "":
		return null
	var animal := AnimalData.new()
	animal.id = data["id"]
	animal.species = StringName(str(data["species"]))
	animal.position = at
	var turn := float(data.get("facing", 0.0))
	animal.facing = turn if is_finite(turn) else 0.0
	var home_at: Variant = data.get("home")
	animal.home = home_at if typeof(home_at) == TYPE_VECTOR2 and is_finite((home_at as Vector2).x) and is_finite((home_at as Vector2).y) else at
	animal.group = int(data.get("group", 0))
	animal.state = clampi(int(data.get("state", 0)), 0, State.size() - 1) as State
	animal.state_until = int(data.get("state_until", 0))
	var going: Variant = data.get("target")
	animal.target = going if typeof(going) == TYPE_VECTOR2 and is_finite((going as Vector2).x) and is_finite((going as Vector2).y) else at
	animal.quarry_id = maxi(int(data.get("quarry", 0)), 0)
	animal.born_tick = int(data.get("born", 0))
	animal.fed_tick = int(data.get("fed", 0))
	animal.drank_day = int(data.get("drank", -1))
	return animal
