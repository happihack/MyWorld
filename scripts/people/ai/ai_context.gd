class_name AiContext
extends RefCounted
## What people's decisions and actions can see and use: the world, each other,
## the systems that move them, the dice. One per world (owned by the
## BehaviorSystem).

var world: WorldData
var props: PropRegistry
var people: PersonRegistry
var pathfinder: Pathfinder
var movement: MovementSystem
var clock: GameClock
var start: WorldSetup.StartInfo
var occupations: OccupationLibrary
var activities: ActivityLibrary
var places: Places
## The world's "ai" stream.
var rng: RandomNumberGenerator
## The world's "stories" stream: who tells a story at bedtime, how a story
## changes in the telling (its own dice, so that stories do not change what
## everyone does next). Falls back to `rng` if unset.
var story_rng: RandomNumberGenerator


func stories_rng() -> RandomNumberGenerator:
	return story_rng if story_rng != null else rng
## Strokes of work done since the BehaviorSystem last announced them: each
## [person id, kind, target id]. (Plain data rather than a callback: a callback
## into the system that owns this context would keep both alive for ever.)
var strokes: Array = []
## The seed of the world (what a settlement's people lean toward comes from it).
var world_seed := 0
## What people have noticed and not yet considered: person id -> Array of
## {"stimulus": Stimulus, "salience": float, "direct": bool, "witnesses": int}
## (see PerceptionSystem; considered by the BehaviorSystem at their next turn).
var perceptions: Dictionary = {}
## People who should take their next turn at once (someone is talking to them).
var nudges: Array[int] = []
## Children who have just gone to bed (announced by the BehaviorSystem as
## `bedtime`: the hook for bedtime stories, M11).
var bedtimes: Array[int] = []
## What everyone remembers (may be null: nobody remembers anything).
var memories: MemoryStore
## What everyone has been doing lately (may be null: nothing is written down).
var day_log: DayLog
## The world's resource nodes, its piles, and what resources there are (may
## be null: then work yields nothing, as before there were resources).
var nodes: ResourceNodes
var piles: PileStore
var resources: ResourceLibrary
## The settlement: its stores and its job board (may be null: then food is
## simply there at the fire and every node is worth working at, as before).
var settlement: Settlement
## Every settlement (M12.3; may be null: then there is only `settlement`).
## Whatever a person does, they do as one of their own settlement (see enter).
var settlements: Settlements
## The fields (may be null: nobody farms).
var farming: Farming
## The animals (may be null: there are none to hunt).
var fauna: AnimalSystem
## The boats (FB3).
var boats: BoatSystem
## The weather (may be null: there is none).
var weather: WeatherSystem
## What people are to each other (may be null: nobody is anything to anyone).
var relationships: RelationshipStore
## What came of people being together that is worth telling, not announced
## yet: [act, person id, other id] (see SocialActs).
var social_events: Array = []
## What two people do that others should see (FC2): [kind, a id, b id] —
## staged once the turn is over (Scenes).
var scenes: Array = []
## Kills not announced yet: [person id, species].
var kills: Array = []
## People who have fallen ill, or recovered, not announced yet:
## [person id, condition, ill (bool)].
var ailments: Array = []
## Is the water on this tile bad to drink (a puddle, floodwater: water that
## is not the river's, nor there of old)? (tile: Vector2i) -> bool; may be unset.
var bad_water: Callable
## Is there no water to drink anywhere now (the waters are blood:
## DisasterSystem)? () -> bool; may be unset.
var water_withheld: Callable
## Is this prop rubble — the old stones of a building that fell, there to be
## taken and built with again (not the world's ancient ruin, nor a mystery's
## stones)? (prop: PropData) -> bool; may be unset (then nothing is).
var is_rubble: Callable
## Who tells stories by each settlement's fire now: settlement id ->
## [person id, until tick] (FireStoryStep).
var fire_tellers: Dictionary = {}
## Births, partners, deaths (may be null: nobody is born or dies).
var lifecycle: Lifecycle
## What settlements remember together (may be null: nothing).
var culture: CulturalMemory
## What is being built (M12.1; may be null).
var construction: ConstructionSystem
## What the settlement decides to build (M12.1; may be null).
var planner: SettlementPlanner
## Footfall and paths (M12.2).
var traffic: Traffic
## People setting out to found settlements (M12.3; may be null).
var migration: Migration
## Trade between settlements (M12.4; may be null).
var trade: TradeSystem
## Who leads each settlement (M12.5; may be null).
var governance: Governance
## What makes each settlement's people theirs: traditions, festivals (M17.1).
var cultures: CultureSystem
## What is known of the unexplained (M18: the scientists go to look).
var archive: AnomalyArchive
## Where stone can be broken near a site: site -> [day, tile or null] (a day's memory).
var rocky_ground: Dictionary = {}
## The things lying about (for coming upon what the player moved; may be null).
var loose: LooseObjectRegistry
## The number the next stimulus gets (saved with the world: memories refer
## to the stimulus they came from).
var next_stimulus_id := 1

# How each person's last walk ended, until the step that asked for it has
# looked: person id -> &"arrived" / &"blocked".
var _walk_results: Dictionary = {}
var _stages: Dictionary = {} # person id -> Vector2i(game day, stage)


## Switches to the person's settlement: its stores, its places, its plans
## (M12.3). Cheap when it is the one already in use.
func enter(person: PersonData) -> void:
	if settlements == null or person == null:
		return
	var own := settlements.of(person)
	if own == null:
		return
	if own != settlement:
		use(own)
	elif farming != null:
		farming.use_start(start) # (the settlements' housekeeping may have used another's)


## Makes `own` the settlement everything refers to.
func use(own: Settlement) -> void:
	settlement = own
	places = own.places()
	start = own.start_info()
	planner = own.planner
	if farming != null:
		farming.use_start(start)


func take_stimulus_id() -> int:
	next_stimulus_id += 1
	return next_stimulus_id - 1


func now() -> int:
	return clock.tick if clock != null else 0


# The weather as people feel it, worked out once for every moment (it is
# asked about for every activity of every decision).
var _weather_tick := -1_000_000
var _shelter_pull := 0.0
var _shelter_reason: StringName = &""
var _temperature := 15.0


## How strongly the weather drives people indoors now, 0 … 1.
func shelter_pull() -> float:
	_feel_weather()
	return _shelter_pull


## What they take shelter from ("rain", "storm", "snow", "cold"); &"" if nothing.
func shelter_reason() -> StringName:
	_feel_weather()
	return _shelter_reason


## How warm it is at the settlement now (°C).
func temperature() -> float:
	_feel_weather()
	return _temperature


func _feel_weather() -> void:
	var tick := now()
	if tick == _weather_tick:
		return
	_weather_tick = tick
	if weather == null:
		_shelter_pull = 0.0
		_shelter_reason = &""
		_temperature = 15.0
		return
	_temperature = weather.temperature(tick)
	_shelter_pull = Exposure.pull(weather, tick)
	_shelter_reason = Exposure.reason(weather, tick)


## The person's stage of life (looked up once per game day and person:
## everything a person does asks for it).
func stage_of(person: PersonData) -> PersonData.LifeStage:
	@warning_ignore("integer_division")
	var day := now() / TimeConfig.MINUTES_PER_DAY
	var known: Variant = _stages.get(person.id)
	if known != null and (known as Vector2i).x == day:
		return (known as Vector2i).y as PersonData.LifeStage
	var stage := person.life_stage(now(), Config.time.ticks_per_year(), Config.people)
	_stages[person.id] = Vector2i(day, stage)
	return stage


func note_walk(person_id: int, result: StringName) -> void:
	_walk_results[person_id] = result


## How the person's walk ended (&"" if it has not), forgetting it.
func take_walk_result(person_id: int) -> StringName:
	var result: StringName = _walk_results.get(person_id, &"")
	_walk_results.erase(person_id)
	return result


## How many units of `resource` someone carries at once.
func carry_capacity(resource: StringName) -> int:
	var def := resources.get_def(resource) if resources != null else null
	if def == null:
		return 1
	return def.units_carried(Config.resources.carry_weight, Config.resources.carry_units_max)


## What working at a prop would yield right now: the resource — or &"" if
## it has nothing to give, or the settlement's stores of it are full (then
## work is only work, as it was before there were resources).
func gatherable(prop_id: int) -> StringName:
	if nodes == null or piles == null or props == null or places == null:
		return &""
	var prop := props.get_prop(prop_id)
	if prop == null or nodes.available(prop) <= 0:
		return &""
	var resource := nodes.resource_of(prop)
	if resource == &"" or (resources != null and not resources.has_def(resource)):
		return &""
	var store := places.store_point(resource)
	if store == Vector2.INF or piles.room(resource, store) <= 0:
		return &""
	# ...or the settlement has enough of it for now (nothing posted).
	if settlement != null and not settlement.jobs.wants(resource):
		return &""
	return resource


## The person puts what they carry down at the settlement's stores. Returns
## how much it was.
func put_down(person: PersonData) -> int:
	var amount := person.carrying_amount
	var resource := person.carrying
	person.carrying = &""
	person.carrying_amount = 0
	if amount <= 0 or resource == &"" or piles == null or places == null:
		return 0
	var store := places.store_point(resource)
	var at := store if store != Vector2.INF else person.world2d()
	piles.add(resource, amount, at)
	if settlement != null:
		settlement.note_produced(resource, amount)
	return amount


func forget(person_id: int) -> void:
	_walk_results.erase(person_id)
	_stages.erase(person_id)


## Turns a person to look at a point of the world.
func face(person: PersonData, at: Vector2) -> void:
	var to := at - person.world2d()
	if to.length_squared() > 0.0001:
		people.move(person.id, person.position, person.sub_tile_offset, to.angle())
