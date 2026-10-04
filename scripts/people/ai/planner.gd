class_name Planner
extends RefCounted
## Turns a decision into something to do (bible §13.4): a short list of steps,
## each plain data (see ActionStep). An empty list means it cannot be done
## right now — nothing to eat, nowhere to sleep, nobody to talk to.

const REQUIREMENTS: Array[StringName] = [&"home", &"food", &"water", &"work", &"company", &"parent", &"grave"]
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
		&"grave":
			return not ctx.places.grave_to_visit(person).is_empty()
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
			# Stone for a building: the builder brings it to the site, from the
			# stores or from the stones lying about.
			if target == &"rock" and def.work_target == &"site":
				target = &"site"
			# The field: whatever it needs most right now. With nothing to do
			# there, a farmer turns to what else they do.
			if target == &"field" or target == &"game" or target == &"site" or target == &"trade" or target == &"workshop":
				var own_work: Array
				match target:
					&"field":
						own_work = _field_work(person, ctx)
					&"game":
						own_work = _hunt(person, ctx)
					&"trade":
						own_work = _trade_work(person, ctx)
					&"workshop":
						own_work = _craft_work(person, ctx)
					_:
						own_work = _build_work(person, ctx)
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
			# (Not far from home: a child does not follow an explorer to the frontier, M13.4.)
			var home: Variant = ctx.places.home_tile(person)
			if home != null and Vector2(parent.position - (home as Vector2i)).length() > Places.EXPLORE_CHILD_MAX + 2.0:
				return []
			var walk := WalkToStep.make(_beside(parent.position, person.position, ctx), person.sub_tile_offset)
			walk["toward"] = parent.id
			return [walk, SocializeStep.make(parent.id, snappedf(rng.randf_range(25.0, 50.0), 1.0))]
		&"visit_grave":
			# To the grave of someone they have lost, to kneel there a while.
			var grave := ctx.places.grave_to_visit(person)
			if grave.is_empty():
				return []
			var rest := RestStep.make(snappedf(rng.randf_range(20.0, 40.0), 1.0), grave["tile"])
			rest["kneel"] = true
			rest["grave_of"] = grave["of"]
			# (At its foot, if one can stand there: the stone is at its head.)
			var foot: Vector2i = grave["tile"] + Vector2i(0, 1)
			var at := foot if ctx.pathfinder.can_stand(foot) else _beside(grave["tile"], person.position, ctx)
			return [WalkToStep.make(at, Vector2(0.5, 0.35)), rest]
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
## Building (M12.1): materials the site still needs that are in the stores
## are fetched and brought there; with enough brought, the builder builds.
## [] if there is nothing they can do there now (then they gather what is
## missing: their trade helps with stone and wood).
static func _build_work(person: PersonData, ctx: AiContext) -> Array:
	if ctx.construction == null or ctx.settlement == null:
		return []
	# Homes first (built or mended), then the rest; the oldest first within each.
	var projects: Array[Dictionary] = []
	for home_first in [true, false]:
		for project in (ctx.construction.projects_of(ctx.settlement.id) if ctx.settlement != null else ctx.construction.projects()):
			if (str(project["def"]) == "hut") == home_first:
				projects.append(project)
	for project: Dictionary in projects:
		var tile: Vector2i = project["tile"]
		var beside := _beside(tile, person.position, ctx)
		var left := ctx.construction.still_needed(project)
		# What is in their arms, if the site needs it.
		if person.carrying_amount > 0 and left.has(person.carrying):
			return [WalkToStep.make(beside, person.sub_tile_offset), BuildStep.deliver(int(project["id"]), tile)]
		if ctx.construction.can_work(project):
			return [WalkToStep.make(beside, person.sub_tile_offset),
				BuildStep.make(int(project["id"]), tile, snappedf(ctx.rng.randf_range(40.0, 90.0), 1.0))]
		for resource: StringName in left:
			var there := ctx.settlement.stockpile.available(resource) # (not the seed kept back)
			if there <= 0:
				continue
			var stores: Variant = ctx.places.storage_tile(resource)
			if stores == null or person.carrying_amount > 0:
				continue
			return [WalkToStep.make(stores, STORE_STAND), BuildStep.fetch(resource, mini(int(left[resource]), there)),
				WalkToStep.make(beside, person.sub_tile_offset), BuildStep.deliver(int(project["id"]), tile)]
		# Stone not in the stores: the stones lying about will do — or stone
		# broken from rocky ground, once there are none near.
		if left.has(&"stone") and person.carrying_amount <= 0:
			var getting := _stone_steps(tile, ctx)
			if not getting.is_empty():
				return getting + [WalkToStep.make(beside, person.sub_tile_offset), BuildStep.deliver(int(project["id"]), tile)]
	return []


## How to come by stone near `site` (M12.1, M12.4): a stone lying about, or
## stone broken from the nearest rocky ground ([]: neither).
static func _stone_steps(site: Vector2i, ctx: AiContext) -> Array:
	var stone := _loose_stone(site, ctx)
	if stone != null:
		return [WalkToStep.make(Vector2i(stone.position.floor())), BuildStep.quarry(stone.id)]
	var rock: Variant = _rocky_ground(site, ctx)
	if rock == null:
		return []
	return [WalkToStep.make(rock), BuildStep.break_stone(rock)]


## The nearest rocky ground to `site` that can be stood on and walked to
## (null: none in reach). Remembered for a day.
static func _rocky_ground(site: Vector2i, ctx: AiContext) -> Variant:
	var day := Config.time.day_index(ctx.now())
	var known: Variant = ctx.rocky_ground.get(site)
	if typeof(known) == TYPE_ARRAY and int(known[0]) == day:
		return known[1]
	var reach := ceili(Config.construction.stone_reach)
	var near: Array = [] # [distance, tile]
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var tile := site + Vector2i(dx, dy)
			if ctx.world == null or not ctx.world.is_in_bounds(tile) or ctx.world.get_terrain(tile) != ChunkData.Terrain.ROCK:
				continue
			if ctx.world.get_water(tile) > 0.0 or (ctx.pathfinder != null and not ctx.pathfinder.can_stand(tile)):
				continue
			near.append([Vector2(dx, dy).length(), tile])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var found: Variant = null
	var from := _beside(site, site + Vector2i(1, 1), ctx)
	for i in mini(near.size(), 6):
		if ctx.pathfinder == null or not ctx.pathfinder.is_bound() or ctx.pathfinder.is_reachable(from, near[i][1]):
			found = near[i][1]
			break
	ctx.rocky_ground[site] = [day, found]
	return found


## A trader's run (M12.4): the settlement's offer for the day — its surplus to
## the settlement that lacks it, and on the way back what that one can spare.
static func _trade_work(person: PersonData, ctx: AiContext) -> Array:
	if ctx.trade == null or ctx.settlement == null or ctx.settlements == null or person.carrying_amount > 0:
		return []
	var offered := ctx.trade.offer_for(ctx.settlement.id)
	if offered.is_empty():
		return []
	var pack := Config.trade.pack_factor
	var offer := ctx.trade.claim(ctx.settlement.id, floori(ctx.carry_capacity(StringName(str(offered["out"]))) * pack),
		floori(ctx.carry_capacity(StringName(str(offered.get("back", "")))) * pack) if str(offered.get("back", "")) != "" else 0)
	var other := ctx.settlements.get_settlement(int(offer["to"]))
	if other == null:
		return []
	var own_id := ctx.settlement.id
	var out := StringName(str(offer["out"]))
	var here: Variant = ctx.places.storage_tile(out)
	var there: Variant = other.places().storage_tile(out)
	if here == null or there == null:
		return []
	var steps := [WalkToStep.make(here, STORE_STAND), TradeStep.load_at(own_id, out, int(offer["units"])),
		WalkToStep.make(there, STORE_STAND), TradeStep.unload_at(other.id, own_id)]
	var back := StringName(str(offer.get("back", "")))
	if back != &"":
		var back_there: Variant = other.places().storage_tile(back)
		var back_here: Variant = ctx.places.storage_tile(back)
		if back_there != null and back_here != null:
			steps.append_array([WalkToStep.make(back_there, STORE_STAND), TradeStep.load_at(other.id, back, int(offer["back_units"])),
				WalkToStep.make(back_here, STORE_STAND), TradeStep.unload_at(own_id, other.id)])
	return steps


## A toolmaker's work (M12.4): at the workshop, while tools are wanted and
## there is wood and stone to make them of.
static func _craft_work(person: PersonData, ctx: AiContext) -> Array:
	if ctx.settlement == null:
		return []
	var shop := ctx.settlement.workshop()
	var config := Config.trade
	if shop == null or not ctx.settlement.tools_wanted() or ctx.settlement.stockpile.available(&"wood") < config.tool_wood:
		return []
	if ctx.settlement.stockpile.available(&"stone") < config.tool_stone:
		# No stone in store: stone fetched for it (lying about, or broken from rocky ground).
		var getting := _stone_steps(shop.tile, ctx)
		var stores: Variant = ctx.places.storage_tile(&"stone")
		if getting.is_empty() or stores == null or person.carrying_amount > 0:
			return []
		return getting + [WalkToStep.make(stores, STORE_STAND), StoreStep.make()]
	return [WalkToStep.make(_beside(shop.tile, person.position, ctx), person.sub_tile_offset),
		TradeStep.craft(shop.id, shop.tile, config.craft_minutes)]


## The nearest stone lying about near a site that can be walked to from it
## (a loose rock or pebble, not one the player put down) (null: none).
static func _loose_stone(site: Vector2i, ctx: AiContext) -> LooseObject:
	if ctx.loose == null:
		return null
	var reach := Config.construction.stone_reach
	var near: Array = [] # [distance, object]
	for object in ctx.loose.all_objects():
		if not BuildStep.STONES.has(object.kind) or object.placed_by_player:
			continue
		var distance := object.position.distance_to(Places.middle_of(site))
		if distance <= reach:
			near.append([distance, object])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var from := _beside(site, site + Vector2i(1, 1), ctx)
	var tries := 0
	for entry: Array in near:
		var object: LooseObject = entry[1]
		var at := Vector2i(object.position.floor())
		if ctx.pathfinder == null or not ctx.pathfinder.is_bound():
			return object
		if not ctx.pathfinder.can_stand(at):
			continue
		if ctx.pathfinder.is_reachable(from, at):
			return object
		tries += 1
		if tries >= 6:
			break # (the rest are further still, over the same water)
	return null


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
