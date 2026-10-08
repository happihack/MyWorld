class_name WorkStep
extends ActionStep
## Work at something: chop at a tree, pick from a bush, keep the fire — or,
## for children, play, which is their work. Work gives purpose; work at a
## resource node also yields what the node holds ("gather": the worker takes
## it up as they go, and stops when their arms are full or nothing is left).
##   {"type": "work", "kind": String, "target": int (prop id), "at": Vector2i,
##    "minutes": float, "elapsed": float, "strokes": int,
##    "gather": bool (optional), "effort": int (strokes towards the next unit),
##    "task": String (optional: field work that is done when the time is up — see Farming),
##    "log": int (optional: a fallen trunk — a loose LOG — cut up for its wood instead of a tree),
##    "fruit": bool (optional: fruit lying on the ground about "at" is picked up, when the time is up)}

const TYPE := &"work"
## Game minutes between two strokes of work that can be seen and heard.
const STROKE_MINUTES := 2.0
## A fallen trunk (an uprooted tree): what it gives, how much (an older save's
## log: a whole tree's worth), and the strokes a unit takes (half a standing
## tree's: it lies ready to cut).
const LOG_RESOURCE := &"wood"
const LOG_WOOD := 16
const LOG_STROKES_PER_UNIT := 6
## Fallen fruit (a shaken tree's) is food: berries, one unit a piece, picked up
## from this near (tiles) where they stoop.
const FRUIT_RESOURCE := &"berries"
## Fishing (M19.5): strokes of patience a fish takes from the bank with a line
## (a stroke is two minutes: a fish in about twenty) — more through the ice;
## from a boat, and with nets, fewer.
const FISH_STROKES := 10.0
const ICE_FACTOR := 2.0
const BOAT_FACTORS := {PropData.Boat.RAFT: 1.4, PropData.Boat.CANOE: 1.8, PropData.Boat.PLANK_BOAT: 2.3, PropData.Boat.SAIL: 2.8}
const NETS_FACTOR := 1.6
const FRUIT_REACH := 1.5


static func make(kind: StringName, target_id: int, at: Vector2i, minutes: float) -> Dictionary:
	return {"type": String(TYPE), "kind": String(kind), "target": target_id, "at": at,
		"minutes": minutes, "elapsed": 0.0, "strokes": 0}


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.TALK if str(step.get("kind")) == "fire" else PersonData.Pose.WORK
	if typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["at"]))


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	# What was being worked at may be gone (the tree uprooted under the axe).
	var target := int(step.get("target", 0))
	var prop := ctx.props.get_prop(target) if target != 0 else null
	if target != 0 and prop == null:
		return Status.DONE
	# (Or the log: gone — cut up by someone else, or carried off by the player.)
	var log: LooseObject = null
	if step.has("log"):
		log = ctx.loose.get_object(int(step["log"])) if ctx.loose != null else null
		if log == null:
			return Status.DONE
	Needs.satisfy(person.needs, Needs.Need.PURPOSE, minutes / Config.needs.full_work_minutes)
	# (In great heat the work goes slower: less of it gets done in the time.)
	var time_up := tick(step, minutes * Exposure.work_pace(ctx.temperature()))
	# (One stroke per turn at most: a turn that covers several is still one
	# thing seen and heard.)
	var strokes := int(float(step["elapsed"]) / STROKE_MINUTES)
	if strokes > int(step.get("strokes", 0)):
		var made := strokes - int(step.get("strokes", 0))
		step["strokes"] = strokes
		ctx.strokes.append([person.id, StringName(str(step.get("kind"))), target])
		if bool(step.get("fish", false)):
			if catch_fish(ctx, person, step, made):
				return Status.DONE
		elif log != null:
			if cut_log(ctx, person, step, log, made):
				return Status.DONE
		elif bool(step.get("gather", false)) and gather(ctx, person, step, prop, made):
			return Status.DONE
	# Fruit lying about: picked up when the time (stooping, gathering) is up.
	if time_up and bool(step.get("fruit", false)) and typeof(step.get("at")) == TYPE_VECTOR2I:
		pick_fruit(ctx, person, step["at"])
	# Field work other than reaping is done when its time is up.
	if time_up and step.has("task") and ctx.farming != null and typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.farming.finish(StringName(str(step["task"])), step["at"], target, ctx.now())
	return Status.DONE if time_up else Status.RUNNING


## `strokes` of work at a node: every so many yield a unit, taken up by the
## worker. True when there is no point going on: their arms are full, or the
## node has nothing left.
static func gather(ctx: AiContext, person: PersonData, step: Dictionary, prop: PropData, strokes: int) -> bool:
	if ctx.nodes == null or prop == null:
		return false
	var resource := ctx.nodes.resource_of(prop)
	if resource == &"":
		return false
	if person.carrying_amount > 0 and person.carrying != resource:
		return true # their arms are full of something else
	var capacity := ctx.carry_capacity(resource)
	var per_unit := ctx.nodes.strokes_per_unit(prop)
	var trade := Config.trade
	var skill_key := String(person.occupation_id)
	var skill := float(person.skills.get(skill_key, 0.0))
	var tools := ctx.settlement.tool_level() if ctx.settlement != null else 0.0
	var effort := float(step.get("effort", 0)) + strokes * pace(ctx, person)
	while effort >= per_unit and person.carrying_amount < capacity:
		if ctx.nodes.take(prop.id, 1, ctx.now()) <= 0:
			break
		effort -= per_unit
		person.carrying = resource
		person.carrying_amount += 1
		skill = minf(skill + trade.skill_per_unit, 1.0)
		person.skills[skill_key] = skill
		if tools > 0.0 and ctx.rng != null and ctx.rng.randf() < trade.tool_wear:
			ctx.settlement.wear_tool()
	step["effort"] = minf(effort, float(per_unit))
	return person.carrying_amount >= capacity or ctx.nodes.available(prop) <= 0


## Fruit (or nuts) lying on the ground near `at` (not what the player has put
## somewhere): picked up as what it is — berries, nuts — one kind at a time,
## as much as their arms hold. Returns how much.
static func pick_fruit(ctx: AiContext, person: PersonData, at: Vector2i) -> int:
	if ctx.loose == null:
		return 0
	var middle_of := Places.middle_of(at)
	var picked := 0
	for object in ctx.loose.all_objects():
		if not is_fallen_fruit(object) or object.position.distance_to(middle_of) > FRUIT_REACH:
			continue
		var resource := fruit_resource(object)
		if person.carrying_amount > 0 and person.carrying != resource:
			continue
		if person.carrying_amount >= ctx.carry_capacity(resource):
			break
		ctx.loose.remove(object.id)
		person.carrying = resource
		person.carrying_amount += 1
		picked += 1
	return picked


## What a fallen fruit is when picked up: nuts, or berries.
static func fruit_resource(object: LooseObject) -> StringName:
	return object.resource if object.resource != &"" else FRUIT_RESOURCE


## Fruit lying on the ground, there to be picked up (not the player's, not afloat).
static func is_fallen_fruit(object: LooseObject) -> bool:
	return object.kind == LooseObject.Kind.FRUIT and not object.placed_by_player and object.state == LooseObject.State.RESTING


## How much more a fisher of `own` catches: from a boat at the landing (the
## best the settlement builds), and with nets.
static func catch_factor(own: Settlement, from_landing: bool) -> float:
	var factor := 1.0
	if own == null:
		return factor
	if from_landing:
		factor *= float(BOAT_FACTORS.get(boat_of(own), 1.0))
	if own.knows_how(&"nets"):
		factor *= NETS_FACTOR
	return factor


## The best boat a settlement knows how to build (PropData.Boat).
static func boat_of(own: Settlement) -> int:
	if own == null:
		return PropData.Boat.NONE
	for pair: Array in [[&"sail", PropData.Boat.SAIL], [&"plank_boat", PropData.Boat.PLANK_BOAT], [&"canoe", PropData.Boat.CANOE],
			[&"raft", PropData.Boat.RAFT]]:
		if own.knows_how(pair[0]):
			return pair[1]
	return PropData.Boat.NONE


## `strokes` of fishing: every so many a fish, out of the water's stock and into
## the fisher's arms. True when there is no point going on (arms full, or the
## water fished out).
static func catch_fish(ctx: AiContext, person: PersonData, step: Dictionary, strokes: int) -> bool:
	if ctx.fauna == null:
		return true
	if person.carrying_amount > 0 and person.carrying != &"fish":
		return true
	var at: Variant = step.get("at")
	var iced := typeof(at) == TYPE_VECTOR2I and ctx.pathfinder != null and ctx.pathfinder.is_bound() and ctx.pathfinder.is_ice(at)
	var per_fish := FISH_STROKES * (ICE_FACTOR if iced else 1.0) / catch_factor(ctx.settlement, int(step.get("landing", 0)) != 0)
	var capacity := ctx.carry_capacity(&"fish")
	# (Out in a boat, what the arms cannot hold goes in the hold — FB4.)
	var boat: BoatData = ctx.boats.get_boat(int(step.get("boat", 0))) if ctx.boats != null and step.has("phase") else null
	var effort := float(step.get("effort", 0)) + strokes * pace(ctx, person)
	var skill_key := String(person.occupation_id)
	while effort >= per_fish and (person.carrying_amount < capacity or (boat != null and boat.hold_room(&"fish") > 0)):
		if ctx.fauna.take_fish(1, at) <= 0:
			return true # (fished out here, for now)
		var own := ctx.settlements.of(person) if ctx.settlements != null else ctx.settlement
		ctx.fauna.waters.note_catch(own.id if own != null else 0, 1, ctx.now())
		effort -= per_fish
		if person.carrying_amount < capacity:
			person.carrying = &"fish"
			person.carrying_amount += 1
		else:
			boat.load_resource = &"fish"
			boat.load_amount += 1
		if boat != null:
			boat.caught += 1
		person.skills[skill_key] = minf(float(person.skills.get(skill_key, 0.0)) + Config.trade.skill_per_unit, 1.0)
	step["effort"] = minf(effort, per_fish)
	return person.carrying_amount >= capacity and (boat == null or boat.hold_room(&"fish") <= 0)


## How fast someone works: the skilled faster, and with tools faster still (M12.4).
static func pace(ctx: AiContext, person: PersonData) -> float:
	var trade := Config.trade
	var skill := float(person.skills.get(String(person.occupation_id), 0.0))
	var tools := ctx.settlement.tool_level() if ctx.settlement != null else 0.0
	return (1.0 + trade.skill_speed * skill) * (1.0 + trade.tool_bonus * tools)


## The wood still in a fallen trunk.
static func log_wood(log: LooseObject) -> int:
	if log.resource == LOG_RESOURCE:
		return log.amount
	return maxi(roundi(LOG_WOOD * log.scale_percent / 100.0), 1) # (an older save's: never cut)


## `strokes` of work at a fallen trunk: every so many give a unit of wood,
## taken up by the worker; the last of it gone, so is the log. True when there
## is no point going on (arms full, or nothing left).
static func cut_log(ctx: AiContext, person: PersonData, step: Dictionary, log: LooseObject, strokes: int) -> bool:
	if person.carrying_amount > 0 and person.carrying != LOG_RESOURCE:
		return true # their arms are full of something else
	var capacity := ctx.carry_capacity(LOG_RESOURCE)
	var left := log_wood(log)
	var effort := float(step.get("effort", 0)) + strokes * pace(ctx, person)
	var skill_key := String(person.occupation_id)
	while effort >= LOG_STROKES_PER_UNIT and person.carrying_amount < capacity and left > 0:
		effort -= LOG_STROKES_PER_UNIT
		left -= 1
		person.carrying = LOG_RESOURCE
		person.carrying_amount += 1
		person.skills[skill_key] = minf(float(person.skills.get(skill_key, 0.0)) + Config.trade.skill_per_unit, 1.0)
		if ctx.settlement != null and ctx.settlement.tool_level() > 0.0 and ctx.rng != null and ctx.rng.randf() < Config.trade.tool_wear:
			ctx.settlement.wear_tool()
	step["effort"] = minf(effort, float(LOG_STROKES_PER_UNIT))
	if left <= 0:
		ctx.loose.remove(log.id) # (cut up and carried off)
		return true
	log.resource = LOG_RESOURCE
	log.amount = left
	ctx.loose.touch(log.id)
	return person.carrying_amount >= capacity


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.WORKING


func patience(_step: Dictionary) -> int:
	return int(STROKE_MINUTES) # a turn for every stroke
