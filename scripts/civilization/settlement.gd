class_name Settlement
extends RefCounted
## A settlement (bible §17.1): the people who live around one fire, their
## households and buildings, what they have in store and what needs doing.
## An aggregate over what is in the registries — it owns only its stockpile's
## books, its job board and its fire's burning. One settlement for now.

## The fire went out, or was lit again.
signal fire_changed(lit: bool)
## A flood has taken so much of something that lay in store.
signal flood_took(resource: StringName, amount: int)
## A hut the water stood in has been rebuilt on higher ground.
signal home_moved(hut_id: int, from: Vector2i, to: Vector2i)
## Food went bad in a pile (anywhere in the world).
signal spoiled(resource: StringName, amount: int)
## Someone took up another occupation (the first farmer).
signal took_up(person_id: int, occupation: StringName)
## It is short of food, or out of it, or has enough again (see Shortage).
signal shortage_changed(stage: int, was: int)
## Out of food, it has begun to eat the grain it kept for seed.
signal seed_released(units: int)
## The bushes around it are picked bare (or have berries again).
signal forage_changed(low: bool)
## Someone of it has worked something out (M12.4: &"toolmaking").
signal learned(person_id: int, what: StringName)

## The trade a settlement is known for, by what it brings in most (M12.4).
const SPECIALTY_TRADES := {"wood": &"woodcutter", "berries": &"forager", "grain": &"farmer", "meat": &"hunter", "fish": &"hunter"}
## Among other settlements, a settlement is known for what is at least this
## share of what it brings in and this many times its share of what all bring in.
const RELATIVE_SHARE := 0.15
const RELATIVE_LEAD := 1.15
## Work at these is helped by tools (and makes people better at it).
const TOOL_WORK: Array[StringName] = [&"tree", &"bush", &"field", &"game"]

## How short of food it is.
enum Shortage {
	NONE,
	## Too little in store: it rations what there is, and people go further
	## for berries.
	SHORT,
	## Nothing in store for hours: the seed grain is eaten.
	EMPTY,
}

## What the first farmer knows of farming when they take it up (a skill, 0 … 1).
const FIRST_FARMER_SKILL := 0.2
## How often it is looked at whether someone should take up farming.
const FARMER_CHECK_MINUTES := 60
## At most this many days are made up for at once (a clock set far ahead).
const MAX_DAYS_AT_ONCE := 30
const MAX_LOGS_AT_ONCE := 64

var id := 0
var stockpile: Stockpile
var jobs: JobBoard
## Its fields (null: this settlement cannot farm).
var farming: Farming
## The animals around it (null: nothing to hunt).
var fauna: AnimalSystem
## What people can be (null: nobody changes what they are).
var occupations: OccupationLibrary
## What the world's nodes still hold (null: the bushes are not looked at).
var nodes: ResourceNodes
var shortage: Shortage = Shortage.NONE
## The grain kept for seed has been given out to be eaten (until the
## shortage is over).
var seed_eaten := false
## Are the bushes around it picked bare?
var forage_low := false

var _start: WorldSetup.StartInfo
var _people: PersonRegistry
var _props: PropRegistry
var _piles: PileStore
var _library: ResourceLibrary
var _config: SettlementConfig
var _places: Places
## What is being built and repaired (M12.1; may be null).
var construction: ConstructionSystem
## What this settlement plans to build (M12.1; one planner each, M12.3).
var planner: SettlementPlanner
## Its name (M12.3: a placeholder — "Ama's camp" — until names come, M17), when
## it was founded, by whom and from where (0: the first settlement, by the band).
var settlement_name := ""
var founded_tick := 0
var founders: Array[int] = []
var founded_from := 0
## Trade between settlements (M12.4; may be null).
var trade: TradeSystem
## Who leads (M12.5; may be null).
var governance: Governance
## What it has brought in of late: resource (String) -> units (fading day by day).
var produced: Dictionary = {}
## What its people know how to do: what (String) -> tick it was worked out.
var knows: Dictionary = {}
var tools_made := 0
var _tool_level := 0.0
## Since when there has been too little in store (-1: there is enough),
## and nothing at all (-1: there is something).
var _low_since := -1
var _empty_since := -1
## Rationing: what each person has had from the stores today (person id ->
## bellies), and which day that is.
var _served: Dictionary = {}
var _served_day := -1_000_000
## The tick at which the fire wants its next piece of wood (-1 = not begun).
var _burn_tick := -1
## The weather, the river, the land and the paths (set by the session; may
## be null: then there is no cold, no flood and no moving house).
var weather: WeatherSystem
var hydrology: Hydrology
var world: WorldData
var pathfinder: Pathfinder
## The highest the water has ever stood in the settlement (world units; a
## hut is rebuilt above it), and the huts it has stood in, to be moved.
var flood_level := 0.0
var _moves: Array[int] = []
var _flood_hour := -1_000_000
var _move_day := -1_000_000
## The game day up to which the days' housekeeping (spoilage) is done.
var _day := -1_000_000
var _farmer_check_tick := -1_000_000
var _stepped_tick := -1_000_000


func _init() -> void:
	stockpile = Stockpile.new()
	jobs = JobBoard.new()


func bind(start: WorldSetup.StartInfo, people: PersonRegistry, props: PropRegistry, piles: PileStore, places: Places,
		library: ResourceLibrary, loose: LooseObjectRegistry, config: SettlementConfig = null) -> void:
	_start = start
	id = start.settlement_id if start != null else 0
	_people = people
	_props = props
	_piles = piles
	_library = library
	_config = config if config != null else Config.settlement
	_places = places
	jobs = JobBoard.new(_config)
	stockpile.bind(piles, places, library, loose)
	_burn_tick = -1
	_day = -1_000_000
	shortage = Shortage.NONE
	seed_eaten = false
	forage_low = false
	_low_since = -1
	_empty_since = -1
	_served.clear()
	_served_day = -1_000_000
	flood_level = 0.0
	_moves.clear()
	_flood_hour = -1_000_000
	_move_day = -1_000_000


func unbind() -> void:
	stockpile.unbind()
	_people = null
	_props = null
	# (The planner knows its settlement, and the settlement its planner: let go.)
	planner = null
	construction = null


# --- who and what ---------------------------------------------------------------------------------

## Everyone who lives here.
func members() -> Array[PersonData]:
	var out: Array[PersonData] = []
	if _people == null:
		return out
	for person in _people.all_people():
		if person.settlement_id == id:
			out.append(person)
	return out


func member_count() -> int:
	return members().size()


## Something has been brought in (gathered, reaped, hunted).
func note_produced(resource: StringName, units: int) -> void:
	if units > 0:
		produced[String(resource)] = float(produced.get(String(resource), 0.0)) + units


## What it is known for (&"": nothing yet, or nothing stands out): among
## other settlements, what it brings in more of than they do (a greater share
## of what it brings in than of what all bring in); alone, the greater part
## of what it brings in.
func specialty() -> StringName:
	var total := 0.0
	var best := ""
	var most := 0.0
	var kinds := produced.keys()
	kinds.sort()
	for resource: String in kinds:
		total += float(produced[resource])
		if float(produced[resource]) > most:
			most = produced[resource]
			best = resource
	if total < Config.trade.specialty_from:
		return &""
	var all: Array = trade.settlements.all() if trade != null and trade.settlements != null else []
	if all.size() >= 2:
		var world := {}
		var world_total := 0.0
		for own: Settlement in all:
			for resource: String in own.produced:
				world[resource] = float(world.get(resource, 0.0)) + float(own.produced[resource])
				world_total += float(own.produced[resource])
		var standout := ""
		var lead := RELATIVE_LEAD
		for resource: String in kinds:
			var share := float(produced[resource]) / total
			var lean := share / maxf(float(world.get(resource, 0.0)) / maxf(world_total, 0.001), 0.01)
			if share >= RELATIVE_SHARE and lean > lead:
				lead = lean
				standout = resource
		if standout != "":
			return StringName(standout)
	if most / maxf(total, 0.001) < Config.trade.specialty_share:
		return &""
	return StringName(best)


## The trade of what it is known for (&"": none).
func specialty_trade() -> StringName:
	return SPECIALTY_TRADES.get(String(specialty()), &"")


func knows_how(what: StringName) -> bool:
	return knows.has(String(what))


## Someone has worked something out: the settlement knows it now.
func learn(what: StringName, person_id: int, now: int) -> void:
	if knows_how(what):
		return
	knows[String(what)] = now
	learned.emit(person_id, what)


## How many of its people work at what tools help with.
func worker_count() -> int:
	var count := 0
	if occupations == null:
		return 0
	for person in members():
		var def := occupations.get_def(person.occupation_id)
		if def != null and TOOL_WORK.has(def.work_target):
			count += 1
	return count


## How well its workers are equipped: tools in store for every worker = 1.
func tool_level() -> float:
	return _tool_level


## Does it want more tools?
func tools_wanted() -> bool:
	return stockpile.amount(&"tools") < ceili(worker_count() * Config.trade.tools_per_worker)


## A tool is made (at the workshop): from wood and stone of the stores. False when they are not there.
func make_tool(_person: PersonData) -> bool:
	var config := Config.trade
	if stockpile.available(&"wood") < config.tool_wood or stockpile.available(&"stone") < config.tool_stone:
		return false
	stockpile.take(&"wood", config.tool_wood)
	stockpile.take(&"stone", config.tool_stone)
	stockpile.add(&"tools", 1)
	tools_made += 1
	_refresh_tools()
	return true


## A tool has worn out in use.
func wear_tool() -> void:
	if stockpile.take(&"tools", 1) > 0:
		_refresh_tools()


## Its workshop (null: it has none).
func workshop() -> PropData:
	if planner == null or _props == null:
		return null
	var ids := planner.standing_near(PropData.Kind.WORKSHOP)
	return _props.get_prop(ids[0]) if not ids.is_empty() else null


## Someone carries its trade, once there is trade to be done.
func ensure_trader(now: int) -> PersonData:
	if trade == null or occupations == null or not occupations.has_def(&"trader") or not trade.has_offer(id):
		return null
	for person in members():
		if person.occupation_id == &"trader":
			return null
	return _take_up(&"trader", Config.trade.trader_from, now)


## Someone makes tools, once there is a workshop and tools are wanted.
func ensure_toolmaker(now: int) -> PersonData:
	if occupations == null or not occupations.has_def(&"toolmaker") or workshop() == null or not tools_wanted():
		return null
	for person in members():
		if person.occupation_id == &"toolmaker":
			return null
	return _take_up(&"toolmaker", 3, now)


func _refresh_tools() -> void:
	var wanted := worker_count() * Config.trade.tools_per_worker
	_tool_level = clampf(float(stockpile.amount(&"tools")) / maxf(wanted, 1.0), 0.0, 1.0)


## A day has passed: what was brought in fades from memory; a skilled worker
## may work out how to make good tools.
func _each_day(day: int) -> void:
	var keep := Config.trade.produced_kept_per_day
	for resource: String in produced.keys():
		produced[resource] = float(produced[resource]) * keep
		if float(produced[resource]) < 0.05:
			produced.erase(resource)
	if knows_how(&"toolmaking"):
		return
	for person in members():
		var skill := 0.0
		for trade_id: Variant in person.skills:
			if String(trade_id) != "builder":
				skill = maxf(skill, float(person.skills[trade_id]))
		if skill < Config.trade.toolmaking_skill:
			continue
		var roll := float(posmod(hash([id, day, person.id, "toolmaking"]), 10000)) / 10000.0
		if roll < Config.trade.toolmaking_chance:
			learn(&"toolmaking", person.id, day * TimeConfig.MINUTES_PER_DAY)
			return


## A trait of its leader as it counts (−1 … +1; 0 without one) (M12.5).
func leader_lean(axis: int) -> float:
	return governance.lean(id, axis) if governance != null else 0.0


## Since when the stores have been low (-1: they are not).
func short_since() -> int:
	return _low_since


## Camp, hamlet, village … — by how many live here (bible §17.1).
func tier() -> Settlements.Tier:
	return Settlements.tier_for(member_count())


## What it is called ("the camp" for the first, until names come in M17).
func display_name() -> String:
	return settlement_name if settlement_name != "" else "the first camp"


## Its households: household id -> the ids of who belongs to it.
func households() -> Dictionary:
	var out := {}
	for person in members():
		var household: PackedInt64Array = out.get(person.household_id, PackedInt64Array())
		household.append(person.id)
		out[person.household_id] = household # (packed arrays are values: put it back)
	return out


## What it has built: the huts and the fire (those still standing).
func buildings() -> Array[PropData]:
	var out: Array[PropData] = []
	if _props == null or _start == null:
		return out
	for prop_id: int in [_start.campfire_id] + _start.hut_ids:
		var prop := _props.get_prop(prop_id)
		if prop != null:
			out.append(prop)
	return out


func fire() -> PropData:
	return _props.get_prop(_start.campfire_id) if _props != null and _start != null else null


## Is the fire burning? (A fire that has gone out is marked on its prop:
## stock 0, drawn without a flame.)
func fire_lit() -> bool:
	var prop := fire()
	return prop != null and prop.stock != 0


# --- housekeeping ---------------------------------------------------------------------------------

## What its people eat in a day, in bellies.
func food_need_per_day() -> float:
	return member_count() * _config.food_per_person_day


## How many days the food in store lasts.
func days_of_food() -> float:
	var need := food_need_per_day()
	return stockpile.food() / need if need > 0.0 else INF


## How many times as much as usual the settlement wants in store now, for
## something of which it wants `most` times as much by winter: more and
## more as winter comes near (SettlementConfig.winter_prepare_days), and in
## winter itself half way back to the usual (it lives off what it laid in).
func winter_factor(now: int, most: float) -> float:
	if Seasons.is_winter(now):
		return lerpf(1.0, most, 0.5)
	if _config.winter_prepare_days <= 0.0:
		return 1.0
	return lerpf(1.0, most, clampf(1.0 - Seasons.days_until_winter(now) / _config.winter_prepare_days, 0.0, 1.0))


# --- short of food ------------------------------------------------------------------------------------

func is_short() -> bool:
	return shortage != Shortage.NONE


## Bellies of food each person gets from the stores in a day while it rations.
func ration() -> float:
	return _config.food_per_person_day * _config.ration_share


## May this person take (more) food from the stores today? Always, unless
## it is short of food and they have had their share.
func serves(person_id: int) -> bool:
	return shortage == Shortage.NONE or float(_served.get(person_id, 0.0)) < ration()


## Someone has taken food from the stores: `bellies` of it.
func note_served(person_id: int, bellies: float) -> void:
	_served[person_id] = float(_served.get(person_id, 0.0)) + bellies


## What a person has had from the stores today, in bellies.
func served_today(person_id: int) -> float:
	return float(_served.get(person_id, 0.0))


## The share of the bushes around the settlement that have nothing on
## them (0 if there are none, or nobody keeps count).
func bare_share() -> float:
	if nodes == null or _props == null or _start == null:
		return 0.0
	var bushes := 0
	var bare := 0
	for prop in _props.all_props():
		if prop.kind != PropData.Kind.BUSH or Vector2(prop.tile - _start.settlement_tile).length() > Places.WORK_RADIUS:
			continue
		bushes += 1
		if nodes.available(prop) <= 0:
			bare += 1
	return float(bare) / float(bushes) if bushes > 0 else 0.0


## How many of its people hunt.
func hunter_count() -> int:
	var count := 0
	if occupations == null:
		return 0
	for person in members():
		var def := occupations.get_def(person.occupation_id)
		if def != null and def.work_target == &"game":
			count += 1
	return count


## A settlement of gatherers with nobody farming: in a season for sowing,
## the one of them best suited to it takes it up (from the trade that has
## the most people, so that no work is left without anyone). Returns who,
## or null.
func ensure_farmer(now: int) -> PersonData:
	if farming == null or occupations == null or not occupations.has_def(&"farmer") or not farming.sowing_time(now) \
			or farming.farmer_count() > 0:
		return null
	return _take_up(&"farmer", _config.farmer_from_gatherers, now)


## Likewise with game about and nobody hunting.
## Likewise with something to build and nobody building (M12.1).
func ensure_builder(now: int) -> PersonData:
	if construction == null or occupations == null or not occupations.has_def(&"builder") or construction.projects_of(id).is_empty():
		return null
	for person in members():
		if person.occupation_id == &"builder":
			return null
	var taken := _take_up(&"builder", 2, now)
	if taken != null or not (_roofless() or _homes_need_work()):
		return taken
	# A home to build or mend, and nobody to spare: whoever is fittest builds.
	var builder := occupations.get_def(&"builder")
	var best: PersonData = null
	for person in members():
		var def := occupations.get_def(person.occupation_id)
		if def == null or def.work_target == &"" or not builder.allows(person.life_stage(now, Config.time.ticks_per_year(), Config.people)):
			continue
		if best == null or builder.affinity(person.traits) > builder.affinity(best.traits) \
				or (builder.affinity(person.traits) == builder.affinity(best.traits) and person.id < best.id):
			best = person
	if best == null:
		return null
	best.occupation_id = builder.id
	took_up.emit(best.id, builder.id)
	jobs.refresh(self, now)
	return best


## Is a home being built or mended?
func _homes_need_work() -> bool:
	for project in construction.projects_of(id):
		if str(project["def"]) == "hut":
			return true
	return false


## Is anyone without a roof (no home, or their home is gone)?
func _roofless() -> bool:
	for person in members():
		if person.home_building_id == 0 or _props == null or _props.get_prop(person.home_building_id) == null:
			return true
	return false


## The settlement's start (its huts, its fire), places and props (M12.1: the planner).
func start_info() -> WorldSetup.StartInfo:
	return _start


func places() -> Places:
	return _places


func props() -> PropRegistry:
	return _props


func ensure_hunter(now: int) -> PersonData:
	if fauna == null or occupations == null or not occupations.has_def(&"hunter") or hunter_count() > 0 or not fauna.has_game():
		return null
	return _take_up(&"hunter", _config.hunter_from_gatherers, now)


## One of the gatherers takes up `occupation`: the one it suits best, from
## the trade with the most people (which keeps at least one). Null if
## there are fewer than `least` gatherers or no trade can spare anyone.
func _take_up(occupation: StringName, least: int, now: int) -> PersonData:
	var farmer := occupations.get_def(occupation)
	var by_trade := {}
	for person in members():
		var def := occupations.get_def(person.occupation_id)
		if def == null or def.placeholder or not farmer.allows(person.life_stage(now, Config.time.ticks_per_year(), Config.people)):
			continue
		if def.work_target != &"tree" and def.work_target != &"bush":
			continue
		if not by_trade.has(person.occupation_id):
			by_trade[person.occupation_id] = []
		(by_trade[person.occupation_id] as Array).append(person)
	var gatherers := 0
	var largest: Array = []
	var trades: Array = by_trade.keys()
	trades.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for trade: StringName in trades:
		var people: Array = by_trade[trade]
		gatherers += people.size()
		if people.size() > largest.size():
			largest = people
	if gatherers < least or largest.size() < 2:
		return null
	var best: PersonData = null
	for person: PersonData in largest:
		if best == null or farmer.affinity(person.traits) > farmer.affinity(best.traits) \
				or (farmer.affinity(person.traits) == farmer.affinity(best.traits) and person.id < best.id):
			best = person
	best.occupation_id = farmer.id
	# (They have seen things grow: not quite a beginner.)
	best.skills[String(farmer.id)] = maxf(float(best.skills.get(String(farmer.id), 0.0)), FIRST_FARMER_SKILL)
	took_up.emit(best.id, farmer.id)
	jobs.refresh(self, now)
	return best


## What a new settlement begins with: some food and some wood by the fire.
func stock_up(now: int) -> void:
	var berries := _library.get_def(&"berries") if _library != null else null
	if berries != null and berries.nutrition > 0.0:
		var units := ceili(food_need_per_day() * _config.starting_food_days / berries.nutrition)
		if units > 0:
			stockpile.add(&"berries", units)
	if _config.starting_wood > 0:
		stockpile.add(&"wood", _config.starting_wood)
	jobs.refresh(self, now)


## Time passes for the settlement: the fire burns its wood, food goes bad
## day by day, and the job board is kept up to date. Cheap to call often.
func step(now: int) -> void:
	if _props == null:
		return
	# (Stepped more often than the clock ticks — every frame, every half minute:
	# once a tick is enough.)
	if now == _stepped_tick:
		return
	_stepped_tick = now
	_burn(now)
	_flood(now)
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
	var made_up := 0
	while _day < today and made_up < MAX_DAYS_AT_ONCE:
		_day += 1
		made_up += 1
		_spoil()
		_each_day(_day)
	_day = today
	if farming != null:
		farming.settle(now)
	if today != _served_day:
		_served_day = today
		_served.clear() # a new day: everyone's share anew
	if now - _farmer_check_tick >= FARMER_CHECK_MINUTES or now < _farmer_check_tick:
		_farmer_check_tick = now
		ensure_farmer(now)
		ensure_hunter(now)
		ensure_builder(now)
		ensure_trader(now)
		ensure_toolmaker(now)
		_refresh_tools()
		_check_forage()
	if now - jobs.last_refresh_tick >= _config.job_check_minutes or now < jobs.last_refresh_tick:
		_keep_seed()
		_relocate(now)
		jobs.refresh(self, now)
		_check_shortage(now)


func debug_text() -> String:
	return "settlement %d: %d people in %d households, %d buildings  food for %.1f days%s  fire %s\nin store: %s   jobs: %s" % [
		id, member_count(), households().size(), buildings().size(), minf(days_of_food(), 99.0),
		["", "  SHORT OF FOOD (rationing)", "  OUT OF FOOD"][shortage] + ("  bushes bare" if forage_low else ""),
		"burning" if fire_lit() else "OUT", stockpile.debug_text(), jobs.debug_text()]


func to_dict() -> Dictionary:
	return {"burn_tick": _burn_tick, "day": _day, "jobs": jobs.to_dict(), "shortage": shortage, "seed_eaten": seed_eaten,
		"forage_low": forage_low, "low_since": _low_since, "empty_since": _empty_since,
		"served": _served.duplicate(), "served_day": _served_day,
		"flood_level": flood_level, "moves": _moves.duplicate(), "move_day": _move_day,
		"name": settlement_name, "founded": founded_tick, "founders": founders.duplicate(), "from": founded_from,
		"produced": produced.duplicate(), "knows": knows.duplicate(), "tools_made": tools_made}


func from_dict(data: Dictionary) -> void:
	_burn_tick = int(data["burn_tick"]) if typeof(data.get("burn_tick")) == TYPE_INT else -1
	var level: Variant = data.get("flood_level")
	flood_level = maxf(float(level), 0.0) if (typeof(level) == TYPE_FLOAT or typeof(level) == TYPE_INT) and is_finite(float(level)) else 0.0
	_moves.clear()
	var moves: Variant = data.get("moves")
	if typeof(moves) == TYPE_ARRAY:
		for hut_id: Variant in moves:
			if typeof(hut_id) == TYPE_INT and _start != null and _start.hut_ids.has(hut_id) and not _moves.has(hut_id):
				_moves.append(hut_id)
	_move_day = int(data["move_day"]) if typeof(data.get("move_day")) == TYPE_INT else -1_000_000
	_day = int(data["day"]) if typeof(data.get("day")) == TYPE_INT else -1_000_000
	var board: Variant = data.get("jobs")
	jobs.from_dict(board if typeof(board) == TYPE_DICTIONARY else {})
	shortage = clampi(int(data["shortage"]), 0, Shortage.size() - 1) as Shortage if typeof(data.get("shortage")) == TYPE_INT \
		else Shortage.NONE
	seed_eaten = bool(data["seed_eaten"]) if typeof(data.get("seed_eaten")) == TYPE_BOOL else false
	forage_low = bool(data["forage_low"]) if typeof(data.get("forage_low")) == TYPE_BOOL else false
	_low_since = int(data["low_since"]) if typeof(data.get("low_since")) == TYPE_INT else -1
	_empty_since = int(data["empty_since"]) if typeof(data.get("empty_since")) == TYPE_INT else -1
	_served_day = int(data["served_day"]) if typeof(data.get("served_day")) == TYPE_INT else -1_000_000
	_served.clear()
	var served: Variant = data.get("served")
	if typeof(served) == TYPE_DICTIONARY:
		for person_id: Variant in served:
			var had: Variant = (served as Dictionary)[person_id]
			if typeof(person_id) == TYPE_INT and (typeof(had) == TYPE_FLOAT or typeof(had) == TYPE_INT):
				_served[person_id] = float(had)
	settlement_name = str(data.get("name", "")) if typeof(data.get("name")) == TYPE_STRING else ""
	founded_tick = int(data["founded"]) if typeof(data.get("founded")) == TYPE_INT else 0
	founded_from = maxi(int(data["from"]), 0) if typeof(data.get("from")) == TYPE_INT else 0
	produced.clear()
	if typeof(data.get("produced")) == TYPE_DICTIONARY:
		for resource: Variant in data["produced"]:
			produced[str(resource)] = maxf(float(data["produced"][resource]), 0.0)
	knows.clear()
	if typeof(data.get("knows")) == TYPE_DICTIONARY:
		for what: Variant in data["knows"]:
			knows[str(what)] = int(data["knows"][what])
	tools_made = maxi(int(data.get("tools_made", 0)), 0)
	founders.clear()
	if typeof(data.get("founders")) == TYPE_ARRAY:
		for id: Variant in data["founders"]:
			if typeof(id) == TYPE_INT:
				founders.append(id)
	_keep_seed()
	_apply_reach()


# --- internals ------------------------------------------------------------------------------------

## The grain for the next sowing is kept back from what is eaten — until
## hunger has the settlement eat it.
func _keep_seed() -> void:
	var wanted := farming.seed_wanted() if farming != null and not seed_eaten else 0
	stockpile.set_reserve(&"grain", wanted)


## Short of food, people go further for berries.
func _apply_reach() -> void:
	if _places != null:
		_places.forage_reach = _config.forage_further_factor if shortage != Shortage.NONE else 1.0


## Looks at what is in store: too little for some hours is a shortage
## (rationing, foraging further); nothing at all for some hours and the
## seed grain is eaten; enough again and it is over.
func _check_shortage(now: int) -> void:
	if member_count() == 0:
		return
	var days := days_of_food()
	if days < _config.shortage_below_days:
		if _low_since < 0 or now < _low_since:
			_low_since = now
	else:
		_low_since = -1
	if stockpile.food_units() <= 0:
		if _empty_since < 0 or now < _empty_since:
			_empty_since = now
	else:
		_empty_since = -1
	match shortage:
		Shortage.NONE:
			if _low_since >= 0 and now - _low_since >= _config.shortage_after_minutes:
				_set_shortage(Shortage.SHORT)
		Shortage.SHORT:
			if days >= _config.shortage_over_days:
				_set_shortage(Shortage.NONE)
			elif _empty_since >= 0 and now - _empty_since >= _config.empty_after_minutes:
				_set_shortage(Shortage.EMPTY)
		Shortage.EMPTY:
			if days >= _config.shortage_over_days:
				_set_shortage(Shortage.NONE)
			elif days >= _config.shortage_below_days:
				_set_shortage(Shortage.SHORT)


func _set_shortage(stage: Shortage) -> void:
	var was := shortage
	if stage == was:
		return
	shortage = stage
	# (Out of food altogether counts from when the shortage began.)
	if was == Shortage.NONE and _empty_since >= 0:
		_empty_since = maxi(_empty_since, jobs.last_refresh_tick)
	_apply_reach()
	if stage == Shortage.NONE:
		seed_eaten = false
		_keep_seed()
	shortage_changed.emit(stage, was)
	if stage == Shortage.EMPTY and not seed_eaten:
		# Nothing left but the seed: it is eaten (and the next sowing is the poorer for it).
		var seed := stockpile.reserved(&"grain")
		if seed > 0:
			seed_eaten = true
			_keep_seed()
			seed_released.emit(seed)


## Are the bushes around the settlement picked bare — or do they have
## berries again?
func _check_forage() -> void:
	if nodes == null:
		return
	var share := bare_share()
	if not forage_low and share >= _config.forage_low_share:
		forage_low = true
		forage_changed.emit(true)
	elif forage_low and share <= _config.forage_recovered_share:
		forage_low = false
		forage_changed.emit(false)


## The fire takes a piece of wood from the stores every so often; with none
## to take it goes out, and is lit again as soon as there is wood.
func _burn(now: int) -> void:
	var prop := fire()
	if prop == null or _config.fire_wood_per_day <= 0.0:
		return
	# Under water there is no fire (and none is lit).
	if is_under_water(prop.tile):
		if prop.stock != 0:
			prop.stock = 0
			_props.changed(prop.id)
			fire_changed.emit(false)
		return
	# (Burning, and the next log not due yet: nothing to do — the common case.)
	if prop.stock != 0 and _burn_tick >= 0 and now < _burn_tick and _burn_tick - now <= Config.time.MINUTES_PER_DAY:
		return
	# (In the cold it burns more.)
	var minutes_per_log := maxi(roundi(Config.time.MINUTES_PER_DAY / (_config.fire_wood_per_day * cold_factor(now))), 1)
	if _burn_tick < 0 or now < _burn_tick - minutes_per_log:
		_burn_tick = now + minutes_per_log # (a new fire, or the clock set back)
	var lit := prop.stock != 0
	var logs := 0
	while now >= _burn_tick and logs < MAX_LOGS_AT_ONCE:
		logs += 1
		_burn_tick += minutes_per_log
		lit = stockpile.take(&"wood", 1) == 1
		if not lit:
			break
	if now >= _burn_tick:
		_burn_tick = now + minutes_per_log
	# A cold fire is lit again as soon as there is something to burn.
	if not lit and stockpile.amount(&"wood") > 0:
		stockpile.take(&"wood", 1)
		_burn_tick = now + minutes_per_log
		lit = true
	if lit != (prop.stock != 0):
		prop.stock = -1 if lit else 0
		_props.changed(prop.id)
		fire_changed.emit(lit)


# --- cold and flood -----------------------------------------------------------------------------------

## How many times as much wood the fire burns for the cold (1 = as usual).
func cold_factor(now: int) -> float:
	return Exposure.fire_factor(weather.temperature(now)) if weather != null else 1.0


## Does water stand on a tile deep enough to count as a flood?
func is_under_water(tile: Vector2i) -> bool:
	return world != null and world.get_water(tile) >= Config.hydrology.flood_depth


## How many huts are waiting to be rebuilt on higher ground.
func pending_moves() -> int:
	return _moves.size()


## Once a game hour: is the water in the settlement? Then it is remembered
## how high it stood and which huts it stood in, everyone flooded out has
## somewhere dry to go, and the flood takes of what lies in store.
func _flood(now: int) -> void:
	@warning_ignore("integer_division")
	var hour := now / 60
	if hour == _flood_hour or world == null or _start == null:
		return
	_flood_hour = hour
	var wet: Array[PropData] = []
	for prop in buildings():
		if is_under_water(prop.tile):
			wet.append(prop)
	if wet.is_empty():
		if _places != null:
			_places.refuge = null
		return
	for prop in wet:
		flood_level = maxf(flood_level, world.get_height(prop.tile) * world.height_step + world.get_water(prop.tile))
		if prop.kind == PropData.Kind.HUT and not _moves.has(prop.id):
			_moves.append(prop.id)
	if _places != null and _places.refuge == null:
		_places.refuge = _find_refuge()
	# The stores: food spoils in the water, wood floats away.
	if _piles == null or _library == null:
		return
	var config := Config.exposure
	var lost := {}
	for pile in _piles.piles():
		if not is_under_water(pile.tile()):
			continue
		var def := _library.get_def(pile.resource)
		var share := config.flood_food_share_per_hour if def != null and def.is_food() else \
			(config.flood_wood_share_per_hour if pile.resource == &"wood" else 0.0)
		if share <= 0.0:
			continue
		pile.spoil += pile.amount * share
		var gone := mini(floori(pile.spoil), pile.amount)
		if gone <= 0:
			continue
		pile.spoil -= gone
		var resource := pile.resource
		_piles.take_from(pile.id, gone)
		lost[resource] = int(lost.get(resource, 0)) + gone
	for resource: StringName in lost:
		flood_took.emit(resource, int(lost[resource]))


## Dry ground near the fire, not lower than it, for those flooded out.
func _find_refuge() -> Variant:
	var hearth := fire()
	if hearth == null or world == null:
		return null
	var best: Variant = null
	var best_distance := INF
	var reach := ceili(Config.exposure.move_radius)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var tile := hearth.tile + Vector2i(dx, dy)
			if not world.is_in_bounds(tile) or world.get_water(tile) > 0.0 or world.get_height(tile) <= world.get_height(hearth.tile):
				continue
			if _props.has_prop_at(tile) or (pathfinder != null and not pathfinder.can_stand(tile)):
				continue
			var distance := Vector2(dx, dy).length()
			if distance < best_distance:
				best_distance = distance
				best = tile
	return best


## Once a day, by daylight, when the water has gone and there is wood for
## it: a hut the flood stood in is rebuilt on ground the water has never
## reached (what the settlement remembers of floods decides where).
func _relocate(now: int) -> void:
	if _moves.is_empty() or world == null or _props == null:
		return
	var today := Config.time.day_index(now)
	var hour := Config.time.minute_of_day(now) / 60.0
	if today == _move_day or hour < 9.0 or hour > 17.0 or (_places != null and _places.refuge != null):
		return
	var config := Config.exposure
	if stockpile.amount(&"wood") < config.move_wood + ceili(_config.fire_wood_per_day):
		return
	# The first of them that nobody is in (not from under someone asleep or sheltering).
	var indoors := {}
	for person in members():
		if person.has_flag(PersonData.FLAG_INDOORS):
			indoors[person.home_building_id] = true
	var hut: PropData = null
	for hut_id: int in _moves.duplicate():
		var prop := _props.get_prop(hut_id)
		if prop == null:
			_moves.erase(hut_id)
		elif not indoors.has(hut_id):
			hut = prop
			break
	if hut == null:
		return
	_move_day = today
	var site: Variant = _site_for(hut)
	if site == null:
		_moves.erase(hut.id) # (no higher ground in reach: it stays where it is)
		return
	var from := hut.tile
	_props.remove(hut.id)
	hut.tile = site
	if not _props.add(hut):
		hut.tile = from
		_props.add(hut)
		_moves.erase(hut.id)
		return
	stockpile.take(&"wood", config.move_wood)
	_moves.erase(hut.id)
	home_moved.emit(hut.id, from, site)


## Where a hut is rebuilt: open ground above the highest water the
## settlement has seen, that can be walked to, clear of other buildings —
## the nearest such to the fire.
func _site_for(hut: PropData) -> Variant:
	var hearth := fire()
	if hearth == null:
		return null
	var config := Config.exposure
	var best: Variant = null
	var best_distance := INF
	var reach := ceili(config.move_radius)
	# (Not where someone is standing, or something lies.)
	var taken := {}
	if _people != null:
		for person in _people.all_people():
			taken[person.position] = true
	if _piles != null:
		for pile in _piles.piles():
			taken[pile.tile()] = true
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var distance := Vector2(dx, dy).length()
			if distance > config.move_radius or distance >= best_distance:
				continue
			var tile := hearth.tile + Vector2i(dx, dy)
			if taken.has(tile):
				continue
			if not world.is_in_bounds(tile) or world.get_water(tile) > 0.0 \
					or world.get_height(tile) * world.height_step <= flood_level + 0.01:
				continue
			var terrain := world.get_terrain(tile)
			if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT:
				continue
			var clear := true
			for y in range(-config.move_spacing, config.move_spacing + 1):
				for x in range(-config.move_spacing, config.move_spacing + 1):
					var near := _props.prop_at(tile + Vector2i(x, y))
					if near != null and near.id != hut.id and (x == 0 and y == 0 or near.kind == PropData.Kind.HUT
							or near.kind == PropData.Kind.CAMPFIRE or near.kind == PropData.Kind.CROP):
						clear = false
			if not clear:
				continue
			if pathfinder != null and (not pathfinder.can_stand(tile) or not pathfinder.is_reachable(hearth.tile + Vector2i(1, 0), tile)):
				continue
			best = tile
			best_distance = distance
	return best


func _spoil() -> void:
	if _piles == null:
		return
	# (A storehouse keeps food longer: M12.1.)
	var kept := construction != null and not construction.standing(PropData.Kind.STOREHOUSE).is_empty()
	var lost := _piles.spoil(Config.construction.storehouse_spoil_factor if kept else 1.0)
	for resource: StringName in lost:
		spoiled.emit(resource, int(lost[resource]))
