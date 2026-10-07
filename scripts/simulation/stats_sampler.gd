class_name StatsSampler
extends RefCounted
## The world's numbers as they are now (bible §27.1, M15), worked out from the
## simulation itself — never kept by hand — for the StatsRecorder to write
## down every game hour. What is in store is every settlement's together.

## The statistics count food lasting more days than this as this many.
const FOOD_DAYS_MOST := 999.0
## The soil is looked at on every this-many-th tile each way.
const SOIL_STEP := 4


static func sample(s: WorldSession) -> Dictionary:
	var out := {}
	var year_ticks := Config.time.ticks_per_year()
	var count := 0
	var health := 0.0
	var mood := 0.0
	var hunger := 0.0
	var safety := 0.0
	var ages := 0
	var sick := 0
	var children := 0
	var adults := 0
	var elders := 0
	var divine := 0.0
	var natural := 0.0
	var deity := ReactionTable.INTERPRETATIONS.find(ReactionTable.DEITY)
	var nature := ReactionTable.INTERPRETATIONS.find(ReactionTable.NATURAL)
	for person in s.people.all_people():
		count += 1
		health += person.health
		mood += Needs.mood(person.needs)
		hunger += person.needs[Needs.Need.HUNGER] if person.needs.size() > Needs.Need.HUNGER else 0.0
		safety += person.needs[Needs.Need.SAFETY] if person.needs.size() > Needs.Need.SAFETY else 1.0
		ages += person.age_years(s.clock.tick, year_ticks)
		if person.health < 0.5:
			sick += 1
		match person.life_stage(s.clock.tick, year_ticks, Config.people):
			PersonData.LifeStage.CHILD, PersonData.LifeStage.ADOLESCENT:
				children += 1
			PersonData.LifeStage.ADULT:
				adults += 1
			_:
				elders += 1
		var beliefs := Interpretation.beliefs_of(person)
		if deity >= 0 and deity < beliefs.size():
			divine += beliefs[deity]
		if nature >= 0 and nature < beliefs.size():
			natural += beliefs[nature]
	var per := 1.0 / count if count > 0 else 0.0
	out[&"population"] = float(count)
	out[&"health"] = health * per
	out[&"mood"] = mood * per
	out[&"nutrition"] = hunger * per
	out[&"fear"] = (1.0 - safety * per) if count > 0 else 0.0
	out[&"average_age"] = ages * per
	out[&"sick"] = float(sick)
	out[&"children"] = float(children)
	out[&"adults"] = float(adults)
	out[&"elders"] = float(elders)
	out[&"divine"] = divine * per
	out[&"natural"] = natural * per
	out[&"births"] = float(s.events.of_type(&"person_born").size())
	out[&"deaths"] = float(s.events.of_type(&"person_died").size())
	out[&"migrants"] = float(s.events.of_type(&"migration").size())
	out[&"settlements"] = float(s.settlements.size())
	# What is in store, and what has been brought in.
	var food := 0.0
	var need := 0.0
	var wood := 0
	var stone := 0
	var tools := 0
	var produced := 0.0
	for own in s.settlements.all():
		food += own.stockpile.food()
		need += own.food_need_per_day()
		wood += own.stockpile.amount(&"wood")
		stone += own.stockpile.amount(&"stone")
		tools += own.stockpile.amount(&"tools")
		for resource: Variant in own.produced:
			produced += float(own.produced[resource])
	out[&"food"] = food
	out[&"food_days"] = minf(food / need, FOOD_DAYS_MOST) if need > 0.0 else 0.0
	out[&"wood"] = float(wood)
	out[&"stone"] = float(stone)
	out[&"tools"] = float(tools)
	out[&"produced"] = produced
	out[&"trade"] = float(s.trade.trips) if s.trade != null else 0.0
	var buildings := 0
	for prop in s.props.buildings():
		if prop.is_building() and prop.kind != PropData.Kind.CAMPFIRE:
			buildings += 1
	out[&"buildings"] = float(buildings)
	out[&"fields"] = float(s.farming.crops().size()) if s.farming != null else 0.0
	# Between them: how much they like each other, the friends, the feuds.
	var pairs := 0
	var affinity := 0.0
	var friends := 0
	var feuds := 0
	if s.relationships != null:
		var all: Array = s.relationships.summary()
		pairs = int(all[0])
		affinity = float(all[1])
		friends = int(all[2])
		feuds = int(all[3])
	out[&"trust"] = affinity / pairs if pairs > 0 else 0.0
	out[&"friendships"] = float(friends)
	out[&"conflict"] = float(feuds)
	# The land and the sky.
	out[&"water"] = s.water.total_volume()
	out[&"temperature"] = s.weather.temperature(s.clock.tick)
	out[&"rainfall"] = s.weather.rainfall_on(s.clock.day())
	out[&"trees"] = float(s.vegetation.tree_count())
	var land := _land(s)
	out[&"grass"] = land[0]
	out[&"forest"] = land[1]
	out[&"wildlife"] = float(s.animals.size()) if s.animals != null else 0.0
	out[&"soil"] = land[2]
	# The player.
	out[&"interventions"] = float(s.history.stats()["total_interactions"]) if s.history != null else 0.0
	out[&"remembered"] = float(PlayerConsequences.people_who_remember(s))
	return out


## The land changes slowly: its grass, forest and soil are looked over once a
## game day and kept for the day's samples (M21: every tile every hour was
## near 50 ms on a 256-tile box). [grass, forest, soil].
static var _land_day := {} # session instance id -> [day, [grass, forest, soil]]


static func _land(s: WorldSession) -> Array:
	var day := s.clock.day()
	var kept: Variant = _land_day.get(s.get_instance_id())
	if kept != null and int(kept[0]) == day:
		return kept[1]
	var land := [s.vegetation.grass_cover(), s.vegetation.forest_coverage(), _soil(s)]
	_land_day.clear() # (one world at a time)
	_land_day[s.get_instance_id()] = [day, land]
	return land


## How fertile the land is, on average (0 … 1).
static func _soil(s: WorldSession) -> float:
	if s.soil == null:
		return 0.0
	var b := s.world.bounds
	var total := 0
	var tiles := 0
	for y in range(b.position.y, b.end.y, SOIL_STEP):
		for x in range(b.position.x, b.end.x, SOIL_STEP):
			var tile := Vector2i(x, y)
			if s.world.get_water(tile) > 0.0:
				continue
			total += s.soil.fertility(tile)
			tiles += 1
	return float(total) / (tiles * 255.0) if tiles > 0 else 0.0
