class_name Planner
extends RefCounted
## Turns a decision into something to do (bible §13.4): a short list of steps,
## each plain data (see ActionStep). An empty list means it cannot be done
## right now — nothing to eat, nowhere to sleep, nobody to talk to.

const REQUIREMENTS: Array[StringName] = [&"home", &"food", &"water", &"work", &"company", &"parent"]
## Where on the storage tile someone stands to put things down (the piles
## lie around its middle).
const STORE_STAND := Vector2(0.5, 0.88)


## Is what an activity requires there for this person? (Cheap: asked for
## every activity at every decision.)
static func can(requirement: StringName, person: PersonData, ctx: AiContext) -> bool:
	match requirement:
		&"home":
			return ctx.places.home_tile(person) != null
		&"food":
			return ctx.places.has_food(person, ctx.settlement)
		&"water":
			return true # found out when planning: looking for water is not cheap
		&"work":
			var def := ctx.occupations.get_def(person.occupation_id) if ctx.occupations != null else null
			return def != null and def.work_target != &"" and def.allows(ctx.stage_of(person))
		&"company":
			return ctx.places.has_company(person, ctx.now())
		&"parent":
			return ctx.places.parent_about(person) != null
	return false


## The steps of `activity` for `person`, or [] if it cannot be done now.
static func plan(activity: StringName, person: PersonData, ctx: AiContext) -> Array:
	var rng := ctx.rng
	match activity:
		&"eat":
			var food: Variant = ctx.places.food_tile(person)
			if food == null:
				return []
			# Nothing in the stores (or nothing more for them today): to a bush
			# that has berries, and eat there.
			if ctx.settlement != null and person.food_in_hand <= 0.0 \
					and (ctx.settlement.stockpile.food_units() <= 0 or not ctx.settlement.serves(person.id)):
				var bush := ctx.places.forage_place(person, rng)
				if bush.is_empty():
					return []
				return [WalkToStep.make(bush["tile"], person.sub_tile_offset), EatStep.make(bush["tile"], false, bush["id"])]
			# A meal, if this is the hour for one: everyone in their place
			# around the fire, staying until it is over.
			var hour := ctx.clock.hour() if ctx.clock != null else 12.0
			var meal: bool = Brain.due_now(person, ctx, hour)[0] == &"eat"
			return [WalkToStep.make(ctx.places.meal_spot(person), Vector2(0.5, 0.5)), EatStep.make(food, meal)]
		&"drink":
			var water: Variant = ctx.places.water_tile(person.position, ctx.now())
			if water == null:
				return []
			return [WalkToStep.make(water), DrinkStep.make(water)]
		&"sleep":
			var home: Variant = ctx.places.home_tile(person)
			if home == null:
				return []
			return [WalkToStep.make(home, person.sub_tile_offset), SleepStep.make()]
		&"work":
			var def := ctx.occupations.get_def(person.occupation_id) if ctx.occupations != null else null
			if def == null or def.work_target == &"":
				return []
			# What is still in their arms goes to the stores first.
			if person.carrying_amount > 0 and ctx.piles != null:
				var stores: Variant = ctx.places.storage_tile(person.carrying)
				if stores != null:
					return [WalkToStep.make(stores, STORE_STAND), StoreStep.make()]
			# What the job board has for them (their own trade first; what is
			# pressing, whoever they are) — or, with nothing posted, their trade.
			var target := def.work_target
			if ctx.settlement != null:
				var job := ctx.settlement.jobs.choose(def.work_target, rng, def.helps_with)
				if job != null:
					target = job.node
			# The field: whatever it needs most right now. With nothing to do
			# there, a farmer turns to what else they do.
			if target == &"field" or target == &"game":
				var own_work := _field_work(person, ctx) if target == &"field" else _hunt(person, ctx)
				if not own_work.is_empty():
					return own_work
				if def.helps_with.is_empty():
					return []
				target = StringName(def.helps_with[0])
			var place := ctx.places.work_place(person, target, rng)
			if place.is_empty():
				return []
			var steps := [WalkToStep.make(place["tile"], person.sub_tile_offset),
				WorkStep.make(target, place["id"], place["tile"], snappedf(rng.randf_range(50.0, 110.0), 1.0))]
			# If it yields something the settlement has room for, they take
			# it up as they work and carry it home.
			var yields := ctx.gatherable(place["id"])
			if yields != &"":
				steps[1]["gather"] = true
				steps.append(WalkToStep.make(ctx.places.storage_tile(yields), STORE_STAND))
				steps.append(StoreStep.make())
			return steps
		&"socialize":
			var partner := ctx.places.company(person, rng)
			if partner == null:
				return []
			return [WalkToStep.make(_beside(partner.position, person.position, ctx), person.sub_tile_offset),
				SocializeStep.make(partner.id, snappedf(rng.randf_range(15.0, 35.0), 1.0))]
		&"explore":
			var target: Variant = ctx.places.explore_tile(person, ctx.stage_of(person), rng)
			if target == null:
				return []
			return [WalkToStep.make(target), RestStep.make(snappedf(rng.randf_range(5.0, 12.0), 1.0))]
		&"tag_along":
			# A child goes to a parent and keeps them company at whatever they are doing.
			var parent := ctx.places.parent_about(person)
			if parent == null:
				return []
			var walk := WalkToStep.make(_beside(parent.position, person.position, ctx), person.sub_tile_offset)
			walk["toward"] = parent.id
			return [walk, SocializeStep.make(parent.id, snappedf(rng.randf_range(25.0, 50.0), 1.0))]
		&"play":
			var spot: Variant = ctx.places.play_tile(person, rng)
			if spot == null:
				return []
			return [WalkToStep.make(spot, person.sub_tile_offset),
				WorkStep.make(&"play", 0, spot, snappedf(rng.randf_range(20.0, 50.0), 1.0))]
		&"go_home":
			var home: Variant = ctx.places.home_tile(person)
			if home == null:
				return []
			# At night, going home is going (back) to bed, until morning.
			if SleepStep.is_night_for(person, ctx.clock.hour() if ctx.clock != null else 12.0):
				return [WalkToStep.make(home, person.sub_tile_offset), SleepStep.make()]
			# In bad weather it is taking shelter: indoors, until it has been a while.
			var from := ctx.shelter_reason()
			if from != &"":
				var stay := Config.exposure.shelter_minutes
				return [WalkToStep.make(home, person.sub_tile_offset),
					RestStep.make(snappedf(rng.randf_range(stay.x, stay.y), 1.0), home, from)]
			return [WalkToStep.make(home, person.sub_tile_offset), RestStep.make(snappedf(rng.randf_range(20.0, 45.0), 1.0), home)]
	return []


## A hunt: after the nearest game there is; with a kill, home to the stores
## with the meat. [] if there is nothing to hunt.
static func _hunt(person: PersonData, ctx: AiContext) -> Array:
	if ctx.fauna == null or ctx.settlement == null or ctx.settlement.fire() == null:
		return []
	var quarry := ctx.fauna.quarry_for(person.world2d(), ctx.settlement.fire().position2d(), Config.settlement.hunt_radius)
	if quarry == null:
		return []
	var steps := [HuntStep.make(quarry.id)]
	var stores: Variant = ctx.places.storage_tile(&"meat")
	if stores != null:
		steps.append(WalkToStep.make(stores, STORE_STAND))
		steps.append(StoreStep.make())
	return steps


## Work on the field: to the plot, do what it needs — and with a harvest,
## home to the stores with it. [] if the field needs nothing.
static func _field_work(person: PersonData, ctx: AiContext) -> Array:
	if ctx.farming == null:
		return []
	var task := ctx.farming.task_for(person, ctx.now())
	if task.is_empty():
		return []
	var what: StringName = task["task"]
	var tile: Vector2i = task["tile"]
	var work := WorkStep.make(&"field", int(task["id"]), tile, ctx.farming.minutes_for(what))
	var steps := [WalkToStep.make(tile, Vector2(0.5, 0.82)), work]
	if what == Farming.HARVEST:
		# Reaping is gathering: the grain is taken up and carried home.
		work["gather"] = true
		var stores: Variant = ctx.places.storage_tile(&"grain")
		if stores != null:
			steps.append(WalkToStep.make(stores, STORE_STAND))
			steps.append(StoreStep.make())
	else:
		work["task"] = String(what)
	return steps


## A tile to stand on next to `tile`, on the side `from` comes from (so that
## two people talking stand side by side, not on top of each other).
static func _beside(tile: Vector2i, from: Vector2i, ctx: AiContext) -> Vector2i:
	var best := tile
	var best_distance := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var other := tile + Vector2i(dx, dy)
			if other == tile or not ctx.pathfinder.can_stand(other):
				continue
			var distance := float((other - from).length_squared())
			if distance < best_distance:
				best_distance = distance
				best = other
	return best
