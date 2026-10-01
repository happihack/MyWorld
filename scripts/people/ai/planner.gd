class_name Planner
extends RefCounted
## Turns a decision into something to do (bible §13.4): a short list of steps,
## each plain data (see ActionStep). An empty list means it cannot be done
## right now — nothing to eat, nowhere to sleep, nobody to talk to.

const REQUIREMENTS: Array[StringName] = [&"home", &"food", &"water", &"work", &"company"]


## Is what an activity requires there for this person? (Cheap: asked for
## every activity at every decision.)
static func can(requirement: StringName, person: PersonData, ctx: AiContext) -> bool:
	match requirement:
		&"home":
			return ctx.places.home_tile(person) != null
		&"food":
			return ctx.places.food_tile(person) != null
		&"water":
			return true # found out when planning: looking for water is not cheap
		&"work":
			var def := ctx.occupations.get_def(person.occupation_id) if ctx.occupations != null else null
			return def != null and def.work_target != &"" and def.allows(ctx.stage_of(person))
		&"company":
			return ctx.places.has_company(person)
	return false


## The steps of `activity` for `person`, or [] if it cannot be done now.
static func plan(activity: StringName, person: PersonData, ctx: AiContext) -> Array:
	var rng := ctx.rng
	match activity:
		&"eat":
			var food: Variant = ctx.places.food_tile(person)
			if food == null:
				return []
			return [WalkToStep.make(food, person.sub_tile_offset), EatStep.make(food)]
		&"drink":
			var water: Variant = ctx.places.water_tile(person.position)
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
			var place := ctx.places.work_place(person, def.work_target, rng)
			if place.is_empty():
				return []
			return [WalkToStep.make(place["tile"], person.sub_tile_offset),
				WorkStep.make(def.work_target, place["id"], place["tile"], snappedf(rng.randf_range(50.0, 110.0), 1.0))]
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
			return [WalkToStep.make(home, person.sub_tile_offset), RestStep.make(snappedf(rng.randf_range(20.0, 45.0), 1.0), home)]
	return []


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
