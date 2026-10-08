class_name Assemblies
extends RefCounted
## Strife between and within settlements, seen (FC7, the owner 2026-10-08).
## A **dispute**: the two leaders (each with one of their own) walk out to meet
## halfway between their fires, talk, then argue, and go home — or, with no
## way between them, each harangues their own at the fire. A **revolution**:
## the discontented gather at the fire around the leader they turn on,
## yelling; the deposed one shrugs; the one who leads now steps forward. What
## happens in the night is staged the next morning; what was missed by a day
## and more is let go.

const DISPUTE := &"dispute"
const REVOLUTION := &"revolution"
## Peace (FC6): the leaders meet on the meeting ground, talk, and part friends.
const PEACE := &"peace"
## How often it looks (game minutes); between which hours it stages anything.
const CHECK_MINUTES := 10
const FROM_HOUR := 8.0
const TO_HOUR := 17.0
## What is not staged within this long (game minutes) is let go.
const STALE := 2 * 24 * 60
## How long each part lasts (minutes): the talk, the argument, the crowd's anger.
const TALK_MINUTES := 10.0
const ARGUE_MINUTES := 6.0
const CROWD_MINUTES := 12.0
## A crowd of at most this many.
const CROWD := 8
const REASON := &"assembly"

var people: PersonRegistry
var behavior: BehaviorSystem
var settlements: Settlements
var governance: Governance
var pathfinder: Pathfinder

## [kind, settlement a, settlement b (or the deposed person for a revolution), tick]
var _pending: Array = []
var _last := -1_000_000


func bind(now: int) -> void:
	_pending.clear()
	_last = now


func dispute(a: int, b: int, now: int) -> void:
	_pending.append([DISPUTE, a, b, now])


func peace(a: int, b: int, now: int) -> void:
	_pending.append([PEACE, a, b, now])


func revolution(settlement_id: int, deposed_id: int, now: int) -> void:
	_pending.append([REVOLUTION, settlement_id, deposed_id, now])


func pending() -> Array:
	return _pending


func advance_to(now: int) -> void:
	if _pending.is_empty() or behavior == null or now - _last < CHECK_MINUTES:
		return
	_last = now
	var hour := Config.time.minute_of_day(now) / 60.0
	for entry: Array in _pending.duplicate():
		if now - int(entry[3]) > STALE:
			_pending.erase(entry)
			continue
		if hour < FROM_HOUR or hour >= TO_HOUR:
			continue
		_pending.erase(entry)
		if StringName(entry[0]) == DISPUTE:
			stage_dispute(int(entry[1]), int(entry[2]))
		elif StringName(entry[0]) == PEACE:
			stage_dispute(int(entry[1]), int(entry[2]), true)
		else:
			stage_revolution(int(entry[1]), int(entry[2]))


## The leaders (and one each) meet halfway, talk, argue, go home — or, making
## peace, talk and part with a wave. Returns who went.
func stage_dispute(a_id: int, b_id: int, making_peace: bool = false) -> Array[PersonData]:
	var went: Array[PersonData] = []
	var a := settlements.get_settlement(a_id)
	var b := settlements.get_settlement(b_id)
	if a == null or b == null or a.fire() == null or b.fire() == null:
		return went
	var ctx := behavior.ctx
	var middle := (Vector2(a.fire().tile) + Vector2(b.fire().tile)) * 0.5
	var meet: Variant = null
	var found := pathfinder.standable_near(WorldCoords.world2d_to_tile(middle), 1, 4) if pathfinder != null else []
	if not found.is_empty() and pathfinder.is_reachable(a.fire().tile + Vector2i(1, 0), found[0]) \
			and pathfinder.is_reachable(b.fire().tile + Vector2i(1, 0), found[0]):
		meet = found[0]
	for own: Settlement in [a, b]:
		var other: Settlement = b if own == a else a
		for person in _delegation(own):
			var steps: Array = []
			if meet != null:
				var spot := Planner._beside(meet, person.position, ctx)
				steps = [WalkToStep.make(spot, Vector2(0.5, 0.5), 1.1),
					ReactStep.make(PersonData.Pose.TALK, Signs.SPEECH, TALK_MINUTES, Vector2(other.fire().tile)),
					ReactStep.make(PersonData.Pose.WAVE, Signs.NOTE, ARGUE_MINUTES, Vector2(other.fire().tile)) if making_peace \
						else ReactStep.make(PersonData.Pose.YELL, Signs.ANGRY, ARGUE_MINUTES, Vector2(other.fire().tile)),
					WalkToStep.make(Planner._beside(own.fire().tile, spot, ctx))]
			else:
				# (No way between them: each speaks against the others at home.)
				steps = [WalkToStep.make(Planner._beside(own.fire().tile, person.position, ctx)),
					ReactStep.make(PersonData.Pose.TALK if making_peace else PersonData.Pose.YELL,
						Signs.SPEECH if making_peace else Signs.ANGRY, ARGUE_MINUTES, Vector2(other.fire().tile))]
			behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON, steps, 7.0)
			went.append(person)
	return went


## The discontented gather round the one they turn on. Returns the crowd.
func stage_revolution(settlement_id: int, deposed_id: int) -> Array[PersonData]:
	var crowd: Array[PersonData] = []
	var own := settlements.get_settlement(settlement_id)
	if own == null or own.fire() == null:
		return crowd
	var ctx := behavior.ctx
	var now := ctx.now()
	var fire := own.fire().tile
	var deposed := people.get_person(deposed_id)
	var leader := people.get_person(governance.leader_of(settlement_id)) if governance != null else null
	if deposed != null and _free(deposed):
		behavior.set_plan(deposed, BehaviorSystem.ACTIVITY_CALLED, REASON, [WalkToStep.make(Planner._beside(fire, deposed.position, ctx)),
			ReactStep.make(PersonData.Pose.SHRUG, Signs.DOTS, CROWD_MINUTES, Vector2(fire))], 7.0)
	var members := own.members()
	members.sort_custom(func(x: PersonData, y: PersonData) -> bool: return x.id < y.id)
	for person in members:
		if crowd.size() >= CROWD or person == deposed or person == leader or not _free(person):
			continue
		var stage := person.life_stage(now, Config.time.ticks_per_year(), Config.people)
		if stage != PersonData.LifeStage.ADULT and stage != PersonData.LifeStage.ELDER:
			continue
		var at := Vector2(deposed.position) if deposed != null else Vector2(fire)
		behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON, [WalkToStep.make(Planner._beside(fire, person.position, ctx), Vector2(0.5, 0.5), 1.2),
			ReactStep.make(PersonData.Pose.YELL, Signs.ANGRY, CROWD_MINUTES, at)], 7.0)
		crowd.append(person)
	if leader != null and _free(leader):
		behavior.set_plan(leader, BehaviorSystem.ACTIVITY_CALLED, REASON, [WalkToStep.make(Planner._beside(fire, leader.position, ctx)),
			ReactStep.make(PersonData.Pose.IDLE, &"", CROWD_MINUTES * 0.6, Vector2(fire)),
			ReactStep.make(PersonData.Pose.WAVE, Signs.NOTE, 4.0, Vector2(fire))], 7.0)
	return crowd


## A settlement's leader and one other (the boldest grown) — or two of its
## grown if it has no leader.
func _delegation(own: Settlement) -> Array[PersonData]:
	var out: Array[PersonData] = []
	var now := behavior.ctx.now()
	var leader := people.get_person(governance.leader_of(own.id)) if governance != null else null
	if leader != null and _free(leader):
		out.append(leader)
	var grown: Array[PersonData] = []
	for person in own.members():
		if person != leader and _free(person) \
				and person.life_stage(now, Config.time.ticks_per_year(), Config.people) == PersonData.LifeStage.ADULT:
			grown.append(person)
	grown.sort_custom(func(x: PersonData, y: PersonData) -> bool:
		return Traits.value(x.traits, Traits.Axis.BRAVERY) > Traits.value(y.traits, Traits.Axis.BRAVERY) or \
			(Traits.value(x.traits, Traits.Axis.BRAVERY) == Traits.value(y.traits, Traits.Axis.BRAVERY) and x.id < y.id))
	for person in grown:
		if out.size() >= 2:
			break
		out.append(person)
	return out


func _free(person: PersonData) -> bool:
	if person == null or person.aboard != 0 or person.pose == PersonData.Pose.SLEEP:
		return false
	var reason := str(person.current_action.get("reason", ""))
	return reason != "predator" and reason != "hunting_party" and reason != String(REASON)


func to_dict() -> Dictionary:
	var list: Array = []
	for entry: Array in _pending:
		list.append([String(entry[0]), entry[1], entry[2], entry[3]])
	return {"pending": list, "last": _last}


func from_dict(data: Dictionary) -> void:
	_pending.clear()
	for item: Variant in data.get("pending", []):
		if typeof(item) == TYPE_ARRAY and (item as Array).size() == 4:
			_pending.append([StringName(str(item[0])), int(item[1]), int(item[2]), int(item[3])])
	_last = int(data.get("last", _last))
