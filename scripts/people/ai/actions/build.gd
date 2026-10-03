class_name BuildStep
extends ActionStep
## Building (M12.1), in three kinds of step:
##   {"type": "fetch", "resource": String, "units": int, "minutes", "elapsed"} — take materials out of the stores;
##   {"type": "quarry", "object": int, "minutes", "elapsed"} — pick up a stone lying about (a loose
##     rock or pebble: it is gone from the world and in their arms, as stone);
##   {"type": "break", "at": Vector2i, "minutes", "elapsed", "strokes"} — break stone from rocky
##     ground (M12.4: when no stones lie about);
##   {"type": "deliver", "project": int, "at": Vector2i, "minutes", "elapsed"} — put them down at the site;
##   {"type": "build", "project": int, "at": Vector2i, "minutes", "elapsed", "strokes"} — build on it,
##     as far as what has been brought allows (see ConstructionSystem).
## One handler for the three (the BehaviorSystem knows it by each type).

const TYPE := &"build"
const FETCH := &"fetch"
const DELIVER := &"deliver"
const QUARRY := &"quarry"
const BREAK := &"break"
## Game minutes of breaking stone for a load.
const BREAK_MINUTES := 40.0
## The loose things that are stone to build with.
const STONES: Array[int] = [LooseObject.Kind.PEBBLE, LooseObject.Kind.ROCK]
## Game minutes between two strokes that can be seen and heard.
const STROKE_MINUTES := 2.0
const HANDLING_MINUTES := 3.0


static func fetch(resource: StringName, units: int) -> Dictionary:
	return {"type": String(FETCH), "resource": String(resource), "units": units, "minutes": HANDLING_MINUTES, "elapsed": 0.0}


static func break_stone(at: Vector2i) -> Dictionary:
	return {"type": String(BREAK), "at": at, "minutes": BREAK_MINUTES, "elapsed": 0.0, "strokes": 0}


static func quarry(object_id: int) -> Dictionary:
	return {"type": String(QUARRY), "object": object_id, "minutes": HANDLING_MINUTES * 2.0, "elapsed": 0.0}


## How much stone a loose stone is (by its weight; at least one unit).
static func stone_units(object: LooseObject, ctx: AiContext) -> int:
	var def := ctx.resources.get_def(&"stone") if ctx.resources != null else null
	var weight := def.weight if def != null else 8.0
	return clampi(roundi(object.mass() / maxf(weight, 0.1)), 1, ctx.carry_capacity(&"stone"))


static func deliver(project_id: int, at: Vector2i) -> Dictionary:
	return {"type": String(DELIVER), "project": project_id, "at": at, "minutes": HANDLING_MINUTES, "elapsed": 0.0}


static func make(project_id: int, at: Vector2i, minutes: float) -> Dictionary:
	return {"type": String(TYPE), "project": project_id, "at": at, "minutes": minutes, "elapsed": 0.0, "strokes": 0}


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.WORK
	if typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["at"]))


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	if ctx.construction == null:
		return Status.FAILED
	match StringName(str(step.get("type", ""))):
		FETCH:
			if not tick(step, minutes):
				return Status.RUNNING
			var resource := StringName(str(step.get("resource", "")))
			if person.carrying_amount > 0 and person.carrying != resource:
				return Status.FAILED # (their arms are full of something else)
			var units := mini(int(step.get("units", 0)), ctx.carry_capacity(resource) - person.carrying_amount)
			var taken := ctx.settlement.stockpile.take(resource, units) if ctx.settlement != null and units > 0 else 0
			if taken <= 0:
				return Status.FAILED # (it is not there after all)
			person.carrying = resource
			person.carrying_amount += taken
			return Status.DONE
		BREAK:
			Needs.satisfy(person.needs, Needs.Need.PURPOSE, minutes / Config.needs.full_work_minutes)
			var done := tick(step, minutes)
			var stroke := int(float(step["elapsed"]) / STROKE_MINUTES)
			if stroke > int(step.get("strokes", 0)):
				step["strokes"] = stroke
				ctx.strokes.append([person.id, &"craft", 0])
			if not done:
				return Status.RUNNING
			if person.carrying_amount > 0 and person.carrying != &"stone":
				return Status.FAILED
			person.carrying = &"stone"
			person.carrying_amount = maxi(person.carrying_amount, ctx.carry_capacity(&"stone"))
			return Status.DONE
		QUARRY:
			if not tick(step, minutes):
				return Status.RUNNING
			var object := ctx.loose.get_object(int(step.get("object", 0))) if ctx.loose != null else null
			if object == null or not STONES.has(object.kind) or (person.carrying_amount > 0 and person.carrying != &"stone"):
				return Status.FAILED # (someone else took it, or the player did)
			var units := stone_units(object, ctx)
			ctx.loose.remove(object.id)
			person.carrying = &"stone"
			person.carrying_amount += units
			return Status.DONE
		DELIVER:
			if not tick(step, minutes):
				return Status.RUNNING
			var project := ctx.construction.project(int(step.get("project", 0)))
			if project.is_empty() or person.carrying_amount <= 0:
				return Status.DONE # (what is left in their arms goes back to the stores)
			var taken := ctx.construction.deliver(project, person.carrying, person.carrying_amount)
			person.carrying_amount -= taken
			if person.carrying_amount <= 0:
				person.carrying = &""
				person.carrying_amount = 0
			Needs.satisfy(person.needs, Needs.Need.PURPOSE, Config.resources.load_purpose)
			return Status.DONE
	# Building.
	var project := ctx.construction.project(int(step.get("project", 0)))
	if project.is_empty() or not ctx.construction.can_work(project):
		return Status.DONE
	Needs.satisfy(person.needs, Needs.Need.PURPOSE, minutes / Config.needs.full_work_minutes)
	var working := minutes * Exposure.work_pace(ctx.temperature())
	var time_up := tick(step, working)
	var strokes := int(float(step["elapsed"]) / STROKE_MINUTES)
	if strokes > int(step.get("strokes", 0)):
		step["strokes"] = strokes
		ctx.strokes.append([person.id, &"build", int(project["site"])])
	if ctx.construction.work(project, person, working, ctx.now()):
		return Status.DONE # (it stands)
	return Status.DONE if time_up else Status.RUNNING


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.WORKING


func patience(step: Dictionary) -> int:
	return 1 if str(step.get("type", "")) == String(TYPE) else 2
