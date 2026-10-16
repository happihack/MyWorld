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
## A specialist trade split off its family here, its first holder (F2 step 2) —
## and merged back into it, its last.
signal trade_split(person_id: int, occupation: StringName)
signal trade_merged(person_id: int, occupation: StringName, into: StringName)
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
## Where each kind of thing was kept when last looked (see gather_stores):
## ResourceDef.Category -> Vector2.
var _kept_at: Dictionary = {}
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


## The trade the young are drawn to: what the place is known for, but not
## foraging with the bushes picked bare (the owner, 2026-10-16: a village known
## for berries made foragers of its young until the bushes were bare, and never
## farmed).
func trade_pull() -> StringName:
	var trade := specialty_trade()
	return &"" if trade == &"forager" and forage_low else trade


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


## What the toolmaker makes next (PR6): tools while they are wanted (and there
## is wood for them), else the weapon most wanted (&"": nothing).
func next_craft() -> StringName:
	if tools_wanted() and stockpile.available(&"wood") >= Config.trade.tool_wood:
		return &"tools"
	return Weapons.most_wanted(self)


## Is there work at the workshop: tools or weapons wanted?
func craft_wanted() -> bool:
	return tools_wanted() or Weapons.most_wanted(self) != Weapons.NONE


## Something is made at the workshop: what is wanted next. False: nothing was.
func craft(person: PersonData) -> bool:
	var kind := next_craft()
	if kind == &"tools":
		return make_tool(person)
	return kind != Weapons.NONE and Weapons.make(self, kind)


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
	return _staff_by_id(&"trader", now)


## Once it knows natural philosophy, and has nobody looking into the
## unexplained: the one it suits best becomes its scientist (M18).
func ensure_scientist(now: int) -> PersonData:
	return _staff_by_id(&"scientist", now)


## Someone makes tools, once there is a workshop and tools are wanted.
func ensure_toolmaker(now: int) -> PersonData:
	return _staff_by_id(&"toolmaker", now)


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
	_orchards(day)
	_treat_with_herbs()
	_count_trees()
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


## How much food has been coming in a day of late (in days of a person's
## eating, as the stores count it): from what it has brought in (`produced`,
## which forgets a little each day — at steady state it holds the rate over
## that forgetting).
func food_coming_in_per_day() -> float:
	var bellies := 0.0
	for resource: String in produced:
		var def := _library.get_def(StringName(resource)) if _library != null else null
		if def != null and def.is_food():
			bellies += float(produced[resource]) * def.nutrition
	return bellies * (1.0 - Config.trade.produced_kept_per_day)


## How many days of food there will be `days` from `now`: what is in store,
## and what comes in on the days that are not winter at the rate it has been
## coming in, less what is eaten meanwhile (the owner, 2026-10-15: a child is
## carried 18 days of a 24-day year, and one conceived in a good summer was
## born into a lean winter).
func days_of_food_in(days: int, now: int) -> float:
	var need := food_need_per_day()
	if need <= 0.0:
		return INF
	var growing := 0
	for day in range(1, days + 1):
		if Config.time.season_of(now + day * TimeConfig.MINUTES_PER_DAY) != Config.time.seasons_per_year - 1:
			growing += 1
	return (stockpile.food() + food_coming_in_per_day() * growing - need * days) / need


## Food (bellies) to have in store now to come through the winter (laying in,
## the owner 2026-10-15: two days' food, doubled as winter came, went into a
## winter of six, and every winter ended in rationing): from
## `winter_prepare_days` before it and through it, what is eaten until it
## ends, less what will still come in on the days that are not winter (at the
## rate it has been coming in), and the usual days in hand besides. 0 at
## other times.
func winter_food_wanted(now: int) -> float:
	if not Seasons.is_winter(now) and Seasons.days_until_winter(now) > _config.winter_prepare_days:
		return 0.0
	var days := 0
	var growing := 0
	var seen_winter := false
	var after := 0
	while days < Config.time.days_per_year():
		var tick := now + days * TimeConfig.MINUTES_PER_DAY
		var winter := Seasons.is_winter(tick)
		# (And into the spring, before anything is ripe: the stores were spent by
		# winter's end, and spring was the leanest time of all — the r7 round.)
		if seen_winter and not winter:
			after += 1
			if after > SPRING_GAP_DAYS:
				break
		seen_winter = seen_winter or winter
		growing += 0 if winter else 1
		days += 1
	var need := food_need_per_day()
	return maxf(need * (days + _config.food_days_wanted) - food_coming_in_per_day() * growing, 0.0)


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
	for prop in _props.of_kind(PropData.Kind.BUSH):
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


## How many of its people fish (M19.5).
func fisher_count() -> int:
	var count := 0
	if occupations == null:
		return 0
	for person in members():
		var def := occupations.get_def(person.occupation_id)
		if def != null and def.work_target == &"fish":
			count += 1
	return count


## Fish to be had: water near the fire (a bank to stand on) with fish in it.
func fish_near() -> bool:
	if fauna == null or fauna.fish < 1.0 or _places == null or fire() == null:
		return false
	var bank: Variant = _places.fishing_bank(fire().tile)
	return bank != null and Vector2(bank - fire().tile).length() <= _config.fish_reach


## With fish to be had and nobody fishing: one of the gatherers takes it up (M19.5).
func ensure_fisher(now: int) -> PersonData:
	return _staff_by_id(&"fisher", now)


## How many fishers the settlement wants (FB4): one — and one more for every
## FISHERS_PER_PEOPLE people, up to FISHERS_MOST, while the water near is not
## fished down (a soak, 2026-10-07: one fisher fed a village of 34 a sixth
## of what a fisher could).
const FISHERS_PER_PEOPLE := 10
const FISHERS_MOST := 4
## The water near is fished down below this share of what it holds: no more fishers.
const FISHED_DOWN := 0.4


func fishers_wanted() -> int:
	var wanted := clampi(1 + member_count() / FISHERS_PER_PEOPLE, 1, FISHERS_MOST)
	if wanted > 1 and fauna != null and fire() != null:
		var stock := 0.0
		var room := 0.0
		var reach := Config.settlement.fish_reach + FishWaters.CELL
		for entry: Array in fauna.waters.all_cells(): # (the fished-out ones too)
			var middle := FishWaters.middle_of(entry[0])
			if Vector2(middle - fire().tile).length() <= reach:
				stock += float(entry[1])
				room += fauna.waters.capacity_at(middle)
		if room <= 0.0 or stock < room * FISHED_DOWN:
			wanted = 1
	return wanted


## A settlement of gatherers with nobody farming: in a season for sowing,
## the one of them best suited to it takes it up (from the trade that has
## the most people, so that no work is left without anyone) — and as it
## grows, more (farmers_wanted). Returns who, or null.
func ensure_farmer(now: int) -> PersonData:
	return _staff_by_id(&"farmer", now)


## How many farmers a settlement that farms wants: one for every
## FARMERS_PER_PEOPLE people (at least one), up to FARMERS_MOST (the owner, 2026-10-07:
## one farmer, whatever the size of the village, was why food ran short; 4 and 8, not 6 and 6, at the owner's word 2026-10-12: two farmers' fields did not carry 12 to 17 people to the next harvest). A settlement of fewer than FARMERS_ONE_BELOW keeps one: a band of eight cannot spare two from gathering.
const FARMERS_PER_PEOPLE := 4
const FARMERS_MOST := 8
const FARMERS_ONE_BELOW := 12


func farmers_wanted() -> int:
	# (One more while the bushes are picked bare: the berries will not feed them.)
	var more := 1 if forage_low else 0
	if member_count() < FARMERS_ONE_BELOW:
		return 1 + more
	return clampi(member_count() / FARMERS_PER_PEOPLE + more, 1, FARMERS_MOST)


## Likewise with game about and nobody hunting.
## Likewise with something to build and nobody building (M12.1).
func ensure_builder(now: int) -> PersonData:
	return _staff_by_id(&"builder", now)


## A home to build or mend, and nobody to spare from gathering: whoever is
## fittest builds.
func _press_builder(now: int) -> PersonData:
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
	return _staff_by_id(&"hunter", now)


# --- staffing (buildings & villagers F2) -------------------------------------------------------

## Once in a while: each trade the data staffs (OccupationDef.staffing_order),
## in that order — wanted more than it has, one more takes it up; a
## specialist no longer called for goes back to its family's trade.
func staff(now: int) -> void:
	for def in _staffed():
		_staff(def, now)
		if def.merges_into != &"":
			_merge_back(def, now)


## Specialists by demand (F2 step 2, §60–63): one split off its family is
## taken up only once the call for it has lasted SPLIT_DAYS (not for a
## passing need); with no call for it for MERGE_DAYS (a season), one of its
## holders — the least skilled first — goes back to the trade it came from
## (OccupationDef.merges_into), and another after as long again.
const SPLIT_DAYS := 1
## One builder wanted at once for every this many people (two at least).
const BUILDERS_PER := 25
## Two woodcutters at the least once a settlement has this many people: the
## fire takes about what one brings in (the owner's world, year 79).
const WOOD_LEAST := 2
const WOOD_LEAST_FROM := 8
## Days into the spring the food laid in for the winter is to last.
const SPRING_GAP_DAYS := 3
## How much further than usual woodcutters go for trees, short of wood.
const WOOD_FURTHER := 2.0
## A woodlot (the owner's world, year 79): with fewer standing trees than
## TREES_WANTED_BASE and one for every person within reach of the fire, the
## woodcutters plant saplings (Planner._plant_work).
const TREES_WANTED_BASE := 20
## Standing trees within reach of the fire (worked out once a day), and whether
## more are wanted.
var trees_near := -1
var woodlot_wanted := false

## One woodcutter for every this many people (one at least): the fire takes
## what one brings, and building wants more (the owner's world, 2026-10-15).
const WOOD_PER := 10
const MERGE_DAYS := 6
var _wanted_since: Dictionary = {} # trade (String) -> tick from which it has been wanted more than held
var _idle_since: Dictionary = {} # trade (String) -> tick from which it has been held more than wanted


func _merge_back(def: OccupationDef, now: int) -> void:
	var key := String(def.id)
	var demand := demand_of(def, now)
	if demand.is_empty() or int(demand["have"]) <= int(demand["wanted"]):
		_idle_since.erase(key)
		return
	var since := int(_idle_since.get(key, now))
	_idle_since[key] = since
	if now - since < MERGE_DAYS * TimeConfig.MINUTES_PER_DAY or occupations == null or not occupations.has_def(def.merges_into):
		return
	var into := occupations.get_def(def.merges_into)
	var leaving: PersonData = null
	for person in members():
		if person.occupation_id != def.id or not into.allows(person.life_stage(now, Config.time.ticks_per_year(), Config.people)):
			continue
		var skill := float(person.skills.get(key, 0.0))
		var best := float(leaving.skills.get(key, 0.0)) if leaving != null else INF
		if skill < best or (skill == best and person.id < leaving.id):
			leaving = person
	if leaving == null:
		return
	leaving.occupation_id = into.id
	_idle_since[key] = now # (the next, after as long again)
	if _holding(def.id) == 0:
		trade_merged.emit(leaving.id, def.id, into.id)
	jobs.refresh(self, now)


## How many of a trade the settlement wants now, and how it finds them: {"wanted":
## people, "have": people, "least": gatherers there must be to spare one,
## "anywhere": from any trade but the food trades (_take_up)} — {} if it wants none.
func demand_of(def: OccupationDef, now: int) -> Dictionary:
	match def.demand:
		&"farm":
			if farming == null:
				return {}
			var farmers := farming.farmer_count()
			# (The first in a season for sowing; more as the settlement grows, any time.)
			# (The bushes picked bare, or the stores short: a first farmer at once, to
			# have the fields ready by the sowing — the owner, 2026-10-16: a berry
			# village never farmed.)
			var wanted := 0 if farmers == 0 and not farming.sowing_time(now) and not forage_low and not is_short() else farmers_wanted()
			return {"wanted": wanted, "have": farmers, "least": _config.farmer_from_gatherers if farmers == 0 else 2, "anywhere": true}
		&"hunt":
			if fauna == null:
				return {}
			return {"wanted": 1 if fauna.has_game() else 0, "have": hunter_count(), "least": _config.hunter_from_gatherers, "anywhere": false}
		&"fish":
			if not fish_near():
				return {}
			var fishers := fisher_count()
			return {"wanted": fishers_wanted(), "have": fishers, "least": _config.fisher_from_gatherers if fishers == 0 else 2, "anywhere": true}
		&"build":
			if construction == null:
				return {}
			# (Two at once (F4), more in a bigger place — and a ruin to clear is work too:
			# the owner, 2026-10-15, builders stood idle and ruins stood for good.)
			var work := construction.projects_of(id).size() + (1 if not construction.ruins_of(id).is_empty() else 0)
			return {"wanted": mini(work, maxi(2, floori(member_count() / float(BUILDERS_PER)))), "have": _holding(def.id), "least": 2, "anywhere": false}
		&"trade":
			if trade == null:
				return {}
			return {"wanted": 1 if trade.has_offer(id) else 0, "have": _holding(def.id), "least": Config.trade.trader_from, "anywhere": false}
		&"craft":
			return {"wanted": 1 if workshop() != null and craft_wanted() else 0, "have": _holding(def.id), "least": 3, "anywhere": false}
		&"cook":
			# (W1) A cook, once there is a smokehouse or drying rack and meat or fish has
			# been coming in — not only at the moment some is in store: fish, spoiling
			# first, is eaten first, and a 30-year soak never found three in store.)
			var brought := float(produced.get("fish", 0.0)) + float(produced.get("meat", 0.0))
			# (… or berries and fruit, to dry for the winter where a drying rack stands: laying in.)
			var picked := float(produced.get("berries", 0.0)) + float(produced.get("fruit", 0.0))
			var drying := planner != null and not planner.standing_near(PropData.Kind.DRYING_RACK).is_empty()
			var wanted_cook := 1 if _has_workplace(def) and (brought >= SettlementPlanner.SMOKE_FROM or (drying and picked >= SettlementPlanner.DRY_FROM)) else 0
			return {"wanted": wanted_cook, "have": _holding(def.id), "least": 3, "anywhere": false}
		&"workplace":
			# (W1) One to work a building with a recipe, while there is something to make there.
			var lib := construction.buildings if construction != null else null
			var wanted_one := 0
			for place in def.workplaces:
				var building := lib.get_def(StringName(place)) if lib != null else null
				if Recipes.workplace(self, building) != null and Recipes.next_step(self, building) >= 0:
					wanted_one = 1
			var tech := StringName(str(def.requires.get("tech", "")))
			if tech != &"" and not knows_how(tech):
				wanted_one = 0
			return {"wanted": wanted_one, "have": _holding(def.id), "least": 3, "anywhere": false}
		&"science":
			return {"wanted": 1 if knows_how(&"natural_philosophy") else 0, "have": _holding(def.id), "least": 3, "anywhere": false}
		&"wood":
			# (The owner's world, year 62, 2026-10-15: every woodcutter had been
			# taken up into the other trades, nobody brought wood, and nothing
			# was built or mended for want of it. One for every WOOD_PER people.)
			var least := WOOD_LEAST if member_count() >= WOOD_LEAST_FROM else 1
			return {"wanted": maxi(least, floori(member_count() / float(WOOD_PER))), "have": _holding(def.id), "least": 2, "anywhere": false}
	return {}


## Wanted against held, trade by trade (F8): "farmer 3/4  fisher 2/2 …".
func staffing_text(now: int) -> String:
	var parts := PackedStringArray()
	for def in _staffed():
		var demand := demand_of(def, now)
		if not demand.is_empty():
			parts.append("%s %d/%d" % [def.id, int(demand["have"]), int(demand["wanted"])])
	return "  ".join(parts)


## Orchards (W1): planted, they bear only after ORCHARD_YEARS; then, but in
## winter, fruit ripens on them day by day, up to ORCHARD_HOLDS, for the
## foragers to pick. Their look follows: young, grown, bearing.
const ORCHARD_YEARS := 3
const ORCHARD_FRUIT_PER_DAY := 2
const ORCHARD_HOLDS := 20


func _orchards(day: int) -> void:
	if planner == null or _props == null:
		return
	var now := day * TimeConfig.MINUTES_PER_DAY
	for id in planner.standing_near(PropData.Kind.ORCHARD):
		var orchard := _props.get_prop(id)
		if orchard == null:
			continue
		if orchard.stock < 0:
			orchard.stock = 0
			orchard.stock_tick = now # (planted)
		var grown := now - orchard.stock_tick >= ORCHARD_YEARS * Config.time.ticks_per_year()
		if grown and Config.time.season_of(now) != 3:
			orchard.stock = mini(orchard.stock + ORCHARD_FRUIT_PER_DAY, ORCHARD_HOLDS)
		var look := 0 if not grown else (2 if orchard.stock >= 3 else 1)
		if look != orchard.variant:
			orchard.variant = look
			_props.changed(orchard.id)


func _count_trees() -> void:
	if _props == null or fire() == null:
		return
	var at := fire().tile
	var count := 0
	for tree in _props.of_kind(PropData.Kind.TREE):
		if not tree.felled and Vector2(tree.tile - at).length() <= Places.WORK_RADIUS:
			count += 1
	trees_near = count
	woodlot_wanted = count < TREES_WANTED_BASE + member_count()


## Herbs from the stores (W1): the ill and the hurt are treated, a bunch each a
## day while there are any, and heal faster for it (Health.recovery).
func _treat_with_herbs() -> void:
	for person in members():
		var ailing := Health.is_ill(person) or not person.injuries.is_empty()
		person.set_flag(PersonData.FLAG_HERBS, ailing and stockpile.take(&"herbs", 1) > 0)


## Does it keep one of `def`'s workplaces?
func _has_workplace(def: OccupationDef) -> bool:
	var lib := construction.buildings if construction != null else null
	for place in def.workplaces:
		if Recipes.workplace(self, lib.get_def(StringName(place)) if lib != null else null) != null:
			return true
	return false


## Is there something to make at a building with a recipe that it keeps (W1)?
func recipe_wanted() -> bool:
	var lib := construction.buildings if construction != null else null
	if lib == null:
		return false
	for id in lib.ids():
		var def := lib.get_def(id)
		if not def.recipe.is_empty() and Recipes.workplace(self, def) != null and Recipes.next_step(self, def) >= 0:
			return true
	return false


func _staff_by_id(occupation: StringName, now: int) -> PersonData:
	if occupations == null or not occupations.has_def(occupation):
		return null
	return _staff(occupations.get_def(occupation), now)


func _staff(def: OccupationDef, now: int) -> PersonData:
	var demand := demand_of(def, now)
	if demand.is_empty() or int(demand["have"]) >= int(demand["wanted"]):
		_wanted_since.erase(String(def.id))
		return null
	if def.merges_into != &"":
		# (A specialist: only once the call for it has lasted.)
		var since := int(_wanted_since.get(String(def.id), now))
		_wanted_since[String(def.id)] = since
		if now - since < SPLIT_DAYS * TimeConfig.MINUTES_PER_DAY:
			return null
	var taken := _take_up(def.id, int(demand["least"]), now, bool(demand["anywhere"]))
	# (Pressed into building only when nobody builds at all: a second builder is
	# never pressed — it took the farmer, and the farm a fisher, hour after hour.)
	if taken == null and def.demand == &"build" and int(demand["have"]) == 0 and (_roofless() or _homes_need_work()):
		taken = _press_builder(now)
	# (W1's trades at a workplace: villages of farmers seldom have three gatherers
	# to spare one, so one comes from a trade that has more than it wants.)
	if taken == null and (def.demand == &"cook" or def.demand == &"workplace" or def.demand == &"build" or def.demand == &"wood"):
		taken = _take_spare(def, now)
	if taken != null and def.merges_into != &"" and int(demand["have"]) == 0:
		trade_split.emit(taken.id, def.id)
	return taken


## One from a trade holding more than it wants now (a third farmer where two
## would do) takes up `def` (null: no trade has one to spare).
func _take_spare(def: OccupationDef, now: int) -> PersonData:
	var spare := {}
	for other in _staffed():
		if other == def:
			continue
		var demand := demand_of(other, now)
		# (The hunter and the fisher only with two more than wanted: they are wanted
		# as the game and the fish come and go, and, once gone, seldom found again —
		# a soak lost its hunting so; but the owner's world had four fishers where
		# one would do, and no woodcutter, 2026-10-15.)
		var keep := 2 if other.demand == &"hunt" or other.demand == &"fish" else 1
		# (Never the last of a trade: a band's one farmer became its cook, and the
		# harvest stood in the field — 2026-10-15.)
		if not demand.is_empty() and int(demand["have"]) >= int(demand["wanted"]) + keep and _holding(other.id) >= 2:
			spare[other.id] = true
	var best: PersonData = null
	for person in members():
		if not spare.has(person.occupation_id) or not def.allows(person.life_stage(now, Config.time.ticks_per_year(), Config.people)):
			continue
		if best == null or def.affinity(person.traits) > def.affinity(best.traits) \
				or (def.affinity(person.traits) == def.affinity(best.traits) and person.id < best.id):
			best = person
	if best == null:
		return null
	best.occupation_id = def.id
	best.skills[String(def.id)] = maxf(float(best.skills.get(String(def.id), 0.0)), FIRST_FARMER_SKILL)
	took_up.emit(best.id, def.id)
	jobs.refresh(self, now)
	return best


## How many of its people hold `occupation`.
func _holding(occupation: StringName) -> int:
	var count := 0
	for person in members():
		if person.occupation_id == occupation:
			count += 1
	return count


## The trades the data staffs, in order (worked out once: the data does not change).
func _staffed() -> Array[OccupationDef]:
	if _staffed_defs.is_empty() and occupations != null:
		for occupation in occupations.ids():
			var def := occupations.get_def(occupation)
			if def.staffing_order > 0:
				_staffed_defs.append(def)
		_staffed_defs.sort_custom(func(a: OccupationDef, b: OccupationDef) -> bool: return a.staffing_order < b.staffing_order)
	return _staffed_defs


var _staffed_defs: Array[OccupationDef] = []


## One of the gatherers takes up `occupation`: the one it suits best, from
## the trade with the most people (which keeps at least one). Null if
## there are fewer than `least` gatherers or no trade can spare anyone.
## `from_anywhere` (the food trades — the owner, 2026-10-07: "they should be
## able to come from anywhere"): from any trade but the food trades, and from
## a trade of one too when none has two — never the last woodcutter (the
## fire), nor the last builder while something is being built.
const FOOD_TRADES: Array[StringName] = [&"farmer", &"fisher", &"hunter"]


func _take_up(occupation: StringName, least: int, now: int, from_anywhere: bool = false) -> PersonData:
	var farmer := occupations.get_def(occupation)
	var by_trade := {}
	for person in members():
		var def := occupations.get_def(person.occupation_id)
		if def == null or def.placeholder or not farmer.allows(person.life_stage(now, Config.time.ticks_per_year(), Config.people)):
			continue
		if from_anywhere:
			if person.occupation_id == occupation or FOOD_TRADES.has(person.occupation_id) or def.work_target == &"":
				continue
		elif def.work_target != &"tree" and def.work_target != &"bush" or person.occupation_id == occupation:
			continue # (a woodcutter is not taken up from the woodcutters)
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
	if gatherers < least:
		return null
	if largest.size() < 2:
		# (Every trade down to one: from anywhere, one of those can still be spared.)
		largest = []
		if from_anywhere:
			for trade: StringName in trades:
				if trade == &"woodcutter" or (trade == &"builder" and construction != null and not construction.projects_of(id).is_empty()):
					continue
				largest.append_array(by_trade[trade])
		if largest.is_empty():
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
		gather_stores()
		_each_day(_day)
	_day = today
	if farming != null:
		farming.settle(now)
	if today != _served_day:
		_served_day = today
		_served.clear() # a new day: everyone's share anew
	if now - _farmer_check_tick >= FARMER_CHECK_MINUTES or now < _farmer_check_tick:
		_farmer_check_tick = now
		staff(now)
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
		"produced": produced.duplicate(), "knows": knows.duplicate(), "tools_made": tools_made}.merged(_staffing_waits())


## Staffing's memory (F2 step 2), written only when there is any.
func _staffing_waits() -> Dictionary:
	var out := {}
	if not _wanted_since.is_empty():
		out["wanted_since"] = _wanted_since.duplicate()
	if not _idle_since.is_empty():
		out["idle_since"] = _idle_since.duplicate()
	return out


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
	for pair: Array in [[_wanted_since, "wanted_since"], [_idle_since, "idle_since"]]:
		var into: Dictionary = pair[0]
		into.clear()
		var saved: Variant = data.get(pair[1])
		if typeof(saved) == TYPE_DICTIONARY:
			for trade: Variant in saved:
				if typeof((saved as Dictionary)[trade]) == TYPE_INT:
					into[str(trade)] = int((saved as Dictionary)[trade])
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
		# (Short of wood: further for trees.)
		_places.wood_reach = WOOD_FURTHER if jobs.wants(&"wood") else 1.0


## How many days the food in store lasts, not counting the grain that would
## be kept for seed were it not being eaten.
func _days_beyond_seed() -> float:
	var need := food_need_per_day()
	var grain := _library.get_def(&"grain") if _library != null else null
	if need <= 0.0 or farming == null or grain == null:
		return days_of_food()
	var seed := mini(farming.seed_wanted(), stockpile.available(&"grain"))
	return maxf(stockpile.food() - seed * grain.nutrition, 0.0) / need


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
			# (A seed store holds the seed back a while longer: W1.)
			if not seed_eaten and has_seed_store() and _empty_since >= 0 and now - _empty_since >= SEED_STORE_HOLDS_MINUTES:
				_release_seed()
			# (The seed being eaten is not food come in: it does not end the
			# shortage — or it was kept back again at once, uneaten, wherever
			# the seed alone made a day's food. The 200-year soaks, 2026-10-12.)
			var beyond := _days_beyond_seed() if seed_eaten else days
			if beyond >= _config.shortage_over_days:
				_set_shortage(Shortage.NONE)
			elif beyond >= _config.shortage_below_days:
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
	if stage == Shortage.EMPTY and not seed_eaten and not has_seed_store():
		# Nothing left but the seed: it is eaten (and the next sowing is the poorer for it).
		_release_seed()


func _release_seed() -> void:
	var seed := stockpile.reserved(&"grain")
	if seed > 0:
		seed_eaten = true
		_keep_seed()
		seed_released.emit(seed)


## Food cooked for the band's meals (W1: a cook) feeds this much more — less
## wasted, nothing burnt or left to spoil in the pot.
const COOKED := 1.15


func has_cook() -> bool:
	return _holding(&"cook") > 0


## A seed store (W1) keeps the seed grain: from floods, and from being eaten
## until the stores have been empty this long.
const SEED_STORE_HOLDS_MINUTES := 2 * 1440


func has_seed_store() -> bool:
	return planner != null and not planner.standing_near(PropData.Kind.SEED_STORE).is_empty()


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
## somewhere dry to go, and the flood takes of what lies in store. While it
## is dry, how high the water stood is slowly forgotten.
func _flood(now: int) -> void:
	@warning_ignore("integer_division")
	var hour := now / 60
	if hour == _flood_hour or world == null or _start == null:
		return
	var hours := hour - _flood_hour if _flood_hour > -1_000_000 and hour > _flood_hour else 1
	_flood_hour = hour
	var wet: Array[PropData] = []
	for prop in buildings():
		if is_under_water(prop.tile):
			wet.append(prop)
	if wet.is_empty():
		if _places != null:
			_places.refuge = null
		# (Dry: what is remembered of the water fades, year by year — a mark that
		# only ever rose left a settlement on level land no ground to build on,
		# for good: the 200-year soaks, 2026-10-10.)
		if flood_level > 0.0:
			flood_level = maxf(flood_level - Config.exposure.flood_mark_fades_per_year * float(hours) / float(Config.time.days_per_year() * 24), 0.0)
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
		if pile.resource == &"grain" and has_seed_store():
			# (The seed is in the seed store, out of the water: W1.)
			gone = mini(gone, maxi(stockpile.amount(&"grain") - stockpile.reserved(&"grain"), 0))
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
			if not clear or Graves.near_cemetery(_props, tile):
				continue
			if pathfinder != null and (not pathfinder.can_stand(tile) or not pathfinder.is_reachable(hearth.tile + Vector2i(1, 0), tile)):
				continue
			best = tile
			best_distance = distance
	return best


## Keeps the food in the storehouse `storehouse_id` and the materials in
## the woodshed `woodshed_id` from now on (0: by the fire, as before there
## was one), and puts what lies where they were kept there.
func keep_in(storehouse_id: int, woodshed_id: int) -> void:
	if _places == null:
		return
	_places.storehouse_id = storehouse_id
	_places.woodshed_id = woodshed_id
	gather_stores()


## The settlement's food and materials that lie where they used to be kept
## (by the fire, at another storehouse or woodshed of its own, at one that
## is gone) are put where they are kept now — onto the piles there first.
func gather_stores() -> void:
	if _piles == null or _places == null or _library == null:
		return
	var radius := Config.resources.storage_radius
	var before := {ResourceDef.Category.FOOD: [], ResourceDef.Category.MATERIAL: []}
	for category: int in _kept_at:
		if before.has(category):
			(before[category] as Array).append(_kept_at[category])
	if planner != null:
		for id in planner.standing_near(PropData.Kind.STOREHOUSE) + planner.standing_near(PropData.Kind.GRANARY):
			(before[ResourceDef.Category.FOOD] as Array).append(Places.middle_of(props().get_prop(id).tile))
		for id in planner.standing_near(PropData.Kind.WOODSHED):
			(before[ResourceDef.Category.MATERIAL] as Array).append(Places.middle_of(props().get_prop(id).tile))
	for pile in _piles.piles():
		var def := _library.get_def(pile.resource)
		if def == null or not before.has(def.category):
			continue
		var to := _places.store_point(pile.resource)
		if to == Vector2.INF:
			continue
		_kept_at[def.category] = to
		if pile.position.distance_to(to) <= radius:
			continue
		var by_fire: Variant = _places.fire_storage_tile(pile.resource)
		var ours := by_fire != null and pile.position.distance_to(Places.middle_of(by_fire)) <= radius
		for at: Vector2 in before[def.category]:
			ours = ours or pile.position.distance_to(at) <= radius
		if ours:
			_piles.gather(pile.id, to)


## Food in a granary goes bad this much as fast as in a storehouse.
const GRANARY_KEEPS := 0.5


func _spoil() -> void:
	if _piles == null:
		return
	# (Food kept in the storehouse keeps longer: M12.1.)
	var store := _places.storehouse() if _places != null else null
	var factor := Config.construction.storehouse_spoil_factor
	if store != null and store.kind == PropData.Kind.GRANARY:
		factor *= GRANARY_KEEPS # (W1: dry, off the ground, out of the mice's reach)
	var lost := _piles.spoil(1.0, Places.middle_of(store.tile) if store != null else Vector2.INF, factor)
	for resource: StringName in lost:
		spoiled.emit(resource, int(lost[resource]))
