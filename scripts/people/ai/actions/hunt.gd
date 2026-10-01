class_name HuntStep
extends ActionStep
## Hunt an animal: creep up on it (someone stalking is noticed only from
## half as far) and, within reach, throw. A hit kills — the hunter takes
## up the meat; a miss sends it running, and that hunt is over.
##   {"type": "hunt", "animal": int, "minutes": float, "elapsed": float,
##    "target": Vector2i (where one is headed), "thrown": bool}

const TYPE := &"hunt"
## Tiles from which a spear is thrown.
const REACH := 2.6
## If the quarry has moved this far from where one is headed, one heads for it anew.
const RETARGET := 2.0
## How likely a throw is to hit: for a beginner, and for someone skilled.
const HIT_UNSKILLED := 0.4
const HIT_SKILLED := 0.85
## A hunt is given up after this many game minutes.
const GIVE_UP_MINUTES := 150.0
const SKILL := "hunter"


static func make(animal_id: int) -> Dictionary:
	return {"type": String(TYPE), "animal": animal_id, "minutes": GIVE_UP_MINUTES, "elapsed": 0.0}


func begin(ctx: AiContext, person: PersonData, _step: Dictionary) -> void:
	person.pose = PersonData.Pose.IDLE
	ctx.take_walk_result(person.id)


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	var animal := ctx.fauna.registry.get_animal(int(step.get("animal", 0))) if ctx.fauna != null else null
	if animal == null:
		return Status.FAILED # gone (taken by a fox, or by someone else)
	if tick(step, minutes):
		return Status.FAILED # it got away
	var distance := person.world2d().distance_to(animal.position)
	if distance <= REACH:
		ctx.movement.stop(person.id)
		ctx.face(person, animal.position)
		person.pose = PersonData.Pose.WORK
		var skill := clampf(float(person.skills.get(SKILL, 0.0)), 0.0, 1.0)
		if ctx.rng.randf() < lerpf(HIT_UNSKILLED, HIT_SKILLED, skill):
			var kind := animal.species
			var meat := ctx.fauna.hunted(animal.id)
			if meat > 0:
				person.carrying = &"meat"
				person.carrying_amount = mini(meat, ctx.carry_capacity(&"meat"))
			person.skills[SKILL] = minf(skill + 0.02, 1.0)
			Needs.satisfy(person.needs, Needs.Need.PURPOSE, 0.3)
			ctx.kills.append([person.id, kind])
			return Status.DONE
		ctx.fauna.missed(animal.id, person.world2d(), ctx.now())
		person.skills[SKILL] = minf(skill + 0.005, 1.0)
		return Status.FAILED
	# Not near enough yet: after it, wherever it has got to.
	var result := ctx.take_walk_result(person.id)
	var heading: Variant = step.get("target")
	var quarry_tile := animal.tile()
	if result == &"blocked":
		# No way to where it is: that group is left alone for a day.
		ctx.fauna.out_of_reach(animal.group, ctx.now())
		return Status.FAILED
	var under_way := ctx.movement.is_walking(person.id) or ctx.movement.is_waiting(person.id)
	if typeof(heading) != TYPE_VECTOR2I or Vector2(quarry_tile - (heading as Vector2i)).length() > RETARGET \
			or not under_way:
		step["target"] = quarry_tile
		ctx.movement.stop(person.id)
		ctx.take_walk_result(person.id)
		if not ctx.movement.walk_to(person.id, quarry_tile):
			return Status.FAILED
	return Status.RUNNING


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	ctx.movement.stop(person.id)
	ctx.take_walk_result(person.id)
	super.end(ctx, person, step)


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.WORKING


func patience(_step: Dictionary) -> int:
	return 1
