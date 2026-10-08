class_name Scenes
extends RefCounted
## What two people do that the others — and the player — should see (FC2,
## the owner 2026-10-08): a quarrel is raised voices and anger, then they
## walk apart; a fight is a scuffle (shoving, grappling: nothing worse),
## onlookers turning to it, a brave friend of one of them stepping in to pull
## them apart; then both walk off sore. Children squabble — voices, no blows —
## and a grown-up near scolds them. Two who make it up embrace; two who
## become friends wave. Staged after the turn in which it happened
## (BehaviorSystem.announce), as plans for those in it.

const QUARREL := &"argue"
const FIGHT := &"fight"
const SQUABBLE := &"squabble"
const EMBRACE := &"embrace"
const FRIENDS := &"friends"
const MOURN := &"mourn"

## The plans' reason (and the activity: held, like a reaction).
const REASON := &"scene"
## What people are not taken from for a scene (a meal, a drink, bed, home):
## they only show it (the sign) — but a fight, or a death, takes anyone.
## (A full suite caught it: scenes cost meals and gathering trips.)
const KEEP_DOING: Array[String] = ["eat", "drink", "sleep", "go_home"]
const TAKES_ANYONE: Array[StringName] = [&"fight", &"mourn"]

## A weightier scene breaks off a lighter one someone is in (a fight, a wave).
const WEIGHT := {FIGHT: 6, QUARREL: 5, SQUABBLE: 4, MOURN: 3, EMBRACE: 2, FRIENDS: 1}
## How long each lasts (game minutes): a quarrel, a fight (shorter if they
## are pulled apart), a squabble, a scolding, an embrace, a wave.
const QUARREL_MINUTES := Vector2(3.0, 6.0)
const FIGHT_MINUTES := Vector2(2.0, 5.0)
const PULLED_APART_MINUTES := 1.5
const SQUABBLE_MINUTES := Vector2(2.0, 3.0)
const SCOLD_MINUTES := 2.0
const EMBRACE_MINUTES := 2.0
const WAVE_MINUTES := 1.5
## Afterwards they walk this far apart (tiles), each its own way.
const APART := 4
## Who turns to look (tiles), and who may step in: a friend (affinity) of
## either, brave enough, within reach.
const ONLOOKERS := 8.0
const FRIEND_FROM := 0.3
const BRAVE_FROM := 0.2
## Pulled apart, the wounds are this much lighter.
const LIGHTER := 0.5


static func stage(behavior: BehaviorSystem, ctx: AiContext, kind: StringName, a_id: int, b_id: int) -> void:
	var a := ctx.people.get_person(a_id)
	var b := ctx.people.get_person(b_id)
	if not _free(a, kind) or not _free(b, kind):
		return
	_staging = kind
	var now := ctx.now()
	var rng := ctx.rng
	match kind:
		QUARREL:
			# (Then each back to what they were about: that takes them apart soon
			# enough — a walk away cost a quarrel before dinner the meal.)
			var minutes := snappedf(rng.randf_range(QUARREL_MINUTES.x, QUARREL_MINUTES.y), 0.5)
			for pair: Array in [[a, b], [b, a]]:
				_plan(behavior, pair[0], [ReactStep.make(PersonData.Pose.YELL, Signs.ANGRY, minutes, (pair[1] as PersonData).world2d())])
				Signs.flash(pair[0], Signs.ANGRY, now, int(minutes) + int(Signs.MINUTES[Signs.ANGRY]))
			_onlookers_turn(ctx, a, b, now)
		FIGHT:
			var separator := _separator(ctx, a, b, now)
			var minutes := snappedf(rng.randf_range(FIGHT_MINUTES.x, FIGHT_MINUTES.y), 0.5)
			if separator != null:
				minutes = PULLED_APART_MINUTES
				_lighten_wounds(a, now)
				_lighten_wounds(b, now)
				var middle := (a.world2d() + b.world2d()) * 0.5
				var to := Planner._beside(WorldCoords.world2d_to_tile(middle), separator.position, ctx)
				_plan(behavior, separator, [WalkToStep.make(to, Vector2(0.5, 0.5), 1.6, Signs.EXCLAIM),
					ReactStep.make(PersonData.Pose.YELL, Signs.EXCLAIM, minutes + 1.0, middle)])
				if ctx.day_log != null:
					ctx.day_log.note(separator.id, now, "social", "separate", a.id)
			for pair: Array in [[a, b], [b, a]]:
				_plan(behavior, pair[0], [ReactStep.make(PersonData.Pose.SCUFFLE, Signs.ANGRY, minutes, (pair[1] as PersonData).world2d()),
					ReactStep.make(PersonData.Pose.IDLE, Signs.HURT, 2.0, (pair[1] as PersonData).world2d()),
					_walk_apart(ctx, pair[0], pair[1])])
			_onlookers_turn(ctx, a, b, now)
		SQUABBLE:
			var minutes := snappedf(rng.randf_range(SQUABBLE_MINUTES.x, SQUABBLE_MINUTES.y), 0.5)
			for pair: Array in [[a, b], [b, a]]:
				_plan(behavior, pair[0], [ReactStep.make(PersonData.Pose.YELL, Signs.ANGRY, minutes, (pair[1] as PersonData).world2d()),
					_walk_apart(ctx, pair[0], pair[1])])
			var grown := _grown_one_near(ctx, a, b, now)
			if grown != null:
				var middle := (a.world2d() + b.world2d()) * 0.5
				_plan(behavior, grown, [WalkToStep.make(Planner._beside(WorldCoords.world2d_to_tile(middle), grown.position, ctx)),
					ReactStep.make(PersonData.Pose.YELL, Signs.EXCLAIM, SCOLD_MINUTES, middle)])
		EMBRACE:
			var record := ctx.relationships.between(a.id, b.id) if ctx.relationships != null else null
			var sign := Signs.LOVE if record != null and record.affinity > 0.5 else Signs.NOTE
			var walk := WalkToStep.make(b.position, b.sub_tile_offset)
			walk["toward"] = b.id
			_plan(behavior, a, [walk, ReactStep.make(PersonData.Pose.EMBRACE, sign, EMBRACE_MINUTES, b.world2d())])
			_plan(behavior, b, [ReactStep.make(PersonData.Pose.IDLE, &"", 1.0, a.world2d()),
				ReactStep.make(PersonData.Pose.EMBRACE, sign, EMBRACE_MINUTES, a.world2d())])
		FRIENDS:
			# (Not stopped for: a glad sign, and they turn to each other.)
			for pair: Array in [[a, b], [b, a]]:
				Signs.flash(pair[0], Signs.NOTE, now)
				ctx.face(pair[0], (pair[1] as PersonData).world2d())


## Grief (FC3): someone has died. Their family and friends are sad; those
## out and near go to the cemetery to kneel a while (or kneel where they are,
## if there is none) — and a few others of the settlement come too.
const GRIEF_MINUTES := 60
const KNEEL_MINUTES := 20.0
const MOURN_REACH := 30.0
const MOURNERS_MORE := 4
const CLOSE_FROM := 0.45


static func mourn(behavior: BehaviorSystem, ctx: AiContext, dead_id: int, cemetery: Variant) -> void:
	var dead := ctx.people.get_person(dead_id)
	if dead == null:
		return
	var now := ctx.now()
	_staging = MOURN
	var at: Vector2 = Places.middle_of(cemetery) if cemetery != null else dead.world2d()
	var more := MOURNERS_MORE
	var everyone := ctx.people.all_people()
	everyone.sort_custom(func(x: PersonData, y: PersonData) -> bool: return x.id < y.id)
	for person in everyone:
		if person.id == dead_id:
			continue
		var close := false
		if ctx.relationships != null:
			var record := ctx.relationships.between(person.id, dead_id)
			close = ctx.relationships.is_family(person.id, dead_id) or (record != null and record.affinity >= CLOSE_FROM)
		if not close and (person.settlement_id != dead.settlement_id or more <= 0):
			continue
		if close:
			Signs.flash(person, Signs.SAD, now, GRIEF_MINUTES)
		if not _free(person, MOURN) or person.world2d().distance_to(at) > MOURN_REACH:
			continue
		if not close:
			more -= 1
		var steps: Array = []
		if cemetery != null:
			steps.append(WalkToStep.make(Planner._beside(cemetery, person.position, ctx)))
		steps.append(ReactStep.make(PersonData.Pose.KNEEL if close else PersonData.Pose.IDLE, Signs.SAD, KNEEL_MINUTES, at))
		_plan(behavior, person, steps)


## Not in a weightier scene already (`kind`: the one to be staged; &"": any
## scene is too much), nor running from a beast, nor out with a party.
static func _free(person: PersonData, kind: StringName = &"") -> bool:
	if person == null or person.has_flag(PersonData.FLAG_INDOORS) or person.pose == PersonData.Pose.SLEEP or person.aboard != 0:
		return false
	var reason := str(person.current_action.get("reason", ""))
	if reason == String(REASON):
		var current := StringName(str(person.current_action.get("scene", "")))
		return kind != &"" and int(WEIGHT.get(kind, 0)) > int(WEIGHT.get(current, 0))
	return reason != "predator" and reason != "hunting_party" and reason != "keep_near"


## (The scene being staged: noted on the plans.)
static var _staging: StringName = &""


static func _plan(behavior: BehaviorSystem, person: PersonData, steps: Array) -> void:
	# At a meal, a drink, bed, on their way home: only the sign (the first that has one).
	if not TAKES_ANYONE.has(_staging) and KEEP_DOING.has(str(person.current_action.get("activity", ""))):
		for step: Variant in steps:
			if typeof(step) == TYPE_DICTIONARY and str((step as Dictionary).get("emote", "")) != "":
				Signs.flash(person, StringName(str(step["emote"])), behavior.ctx.now())
				break
		return
	var kept: Array = []
	for step: Variant in steps:
		if step != null:
			kept.append(step)
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_REACT, REASON, kept, 7.0)
	person.current_action["scene"] = String(_staging)


## A few tiles away from the other, on ground that can be stood on (null:
## nowhere: they stay).
static func _walk_apart(ctx: AiContext, person: PersonData, other: PersonData) -> Variant:
	var away := person.world2d() - other.world2d()
	if away.length() < 0.05:
		away = Vector2.RIGHT.rotated(float(person.id % 360) * 0.0174533)
	var tile := WorldCoords.world2d_to_tile(person.world2d() + away.normalized() * APART)
	var found := ctx.pathfinder.standable_near(tile, 1, 2) if ctx.pathfinder != null else []
	return WalkToStep.make(found[0]) if not found.is_empty() else null


## Those near turn to look (a question).
static func _onlookers_turn(ctx: AiContext, a: PersonData, b: PersonData, now: int) -> void:
	var middle := (a.world2d() + b.world2d()) * 0.5
	for id in ctx.people.spatial_index.query_radius(middle, ONLOOKERS, SpatialIndex.KIND_PERSON):
		var other := ctx.people.get_person(id)
		if other == null or other == a or other == b or other.has_flag(PersonData.FLAG_INDOORS) or other.pose == PersonData.Pose.SLEEP:
			continue
		Signs.flash(other, Signs.QUESTION, now)
		ctx.face(other, middle)


## A brave friend of either near enough to step in (null: none).
static func _separator(ctx: AiContext, a: PersonData, b: PersonData, now: int) -> PersonData:
	if ctx.relationships == null:
		return null
	var middle := (a.world2d() + b.world2d()) * 0.5
	var best: PersonData = null
	var best_bond := FRIEND_FROM
	for id in ctx.people.spatial_index.query_radius(middle, ONLOOKERS, SpatialIndex.KIND_PERSON):
		var other := ctx.people.get_person(id)
		if other == null or other == a or other == b or not _free(other):
			continue
		if other.life_stage(now, Config.time.ticks_per_year(), Config.people) != PersonData.LifeStage.ADULT \
				and other.life_stage(now, Config.time.ticks_per_year(), Config.people) != PersonData.LifeStage.ELDER:
			continue
		if Traits.value(other.traits, Traits.Axis.BRAVERY) < BRAVE_FROM:
			continue
		var bond := 0.0
		for fighter: PersonData in [a, b]:
			var record := ctx.relationships.between(other.id, fighter.id)
			if record != null:
				bond = maxf(bond, record.affinity)
		if bond > best_bond:
			best = other
			best_bond = bond
	return best


## A grown-up near two children squabbling (null: none).
static func _grown_one_near(ctx: AiContext, a: PersonData, b: PersonData, now: int) -> PersonData:
	var middle := (a.world2d() + b.world2d()) * 0.5
	for id in ctx.people.spatial_index.query_radius(middle, ONLOOKERS, SpatialIndex.KIND_PERSON):
		var other := ctx.people.get_person(id)
		if other == null or other == a or other == b or not _free(other):
			continue
		var stage := other.life_stage(now, Config.time.ticks_per_year(), Config.people)
		if stage == PersonData.LifeStage.ADULT or stage == PersonData.LifeStage.ELDER:
			return other
	return null


## Pulled apart: the fight's wounds (just given) half as bad.
static func _lighten_wounds(person: PersonData, now: int) -> void:
	for injury: Variant in person.injuries:
		if typeof(injury) != TYPE_DICTIONARY or str(injury.get("kind", "")) != String(Health.FIGHT) or int(injury.get("since", -1)) != now:
			continue
		var took := float(injury.get("took", 0.0)) * LIGHTER
		injury["severity"] = float(injury["severity"]) * LIGHTER
		injury["initial"] = float(injury["initial"]) * LIGHTER
		injury["took"] = float(injury["took"]) - took
		person.health = minf(person.health + took, 1.0)
