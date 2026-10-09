class_name WorldSession
extends Node
## Owns ALL state of the currently open world (bible §31.3, D-06).
##
## Deliberately not an autoload: New World / Reset / tests create and free
## sessions cleanly. Systems (people, environment, ...) are added as
## children/fields of this node in later milestones.
##
## World persistence is sparse (bible §8.4): the save holds only what differs
## from the generator's output — modified chunks, removed/added props — plus the
## start info, so an untouched world costs almost nothing to save.

## Emitted by shutdown() while the world is still active, so listeners (e.g.
## SaveManager) can persist it on every orderly exit path.
signal about_to_close
## The box has unfolded (M13.2): the walls stand at `new_bounds` now (they
## stood at `old_bounds`). Everything of the world was opened again for it.
signal unfolded(old_bounds: Rect2i, new_bounds: Rect2i)

const FORMAT_KEYS: PackedStringArray = ["world_id", "world_seed", "created_unix", "clock", "ids", "rng"]
const DEFAULT_TEMPLATE_ID := &"river_valley"
## The lands a new world may be (2026-10-08: terraced, and more of them). The
## first worlds' river valley (DEFAULT_TEMPLATE_ID) stays as it was for them —
## and for the tests and soaks, which make their worlds by seed.
const LANDS: Array[StringName] = [&"broad_valley", &"lake_country", &"open_plains", &"highlands", &"forest_vale", &"river_bluffs"]
const TEMPLATE_DIR := "res://data/worldgen/"
## A random seed whose world is not livable is re-rolled up to this many times.
const MAX_SEED_ATTEMPTS := 8
## The culture of the starting band (cultures become entities in M17).
const FIRST_CULTURE_ID := 1

var world_id: String = ""
var world_seed: int = 0
var created_unix: int = 0
var clock: GameClock
var ids: IdAllocator
var rng: RngStreams
var is_active := false
## Raids made by people walking over (FC5) — off while the time away is lived.
var walking_raids := true

## The tile world and what stands on it.
var template_id: StringName = DEFAULT_TEMPLATE_ID
var world: WorldData
var generator: WorldGenerator
var props: PropRegistry
var spatial: SpatialIndex
## Things lying in the world that can be moved (rocks, boulders, ...).
var loose: LooseObjectRegistry
var start: WorldSetup.StartInfo
## Where every player touch of the world is answered.
var interactions: InteractionManager
## Moves the loose objects that are not at rest.
var loose_system: LooseObjectSystem
## Moves the water.
var water: WaterSim
## How the river stands: rain, dry weeks, floods (the coarse side of the water).
var hydrology: Hydrology
## What people are to each other.
var relationships: RelationshipStore
## Who lives with whom, under which roof (M10.2).
var households: Households
## Births, partners, ageing, death (M10.2).
var lifecycle: Lifecycle
## Everyone who has died.
var archive: HistoryArchive
## What settlements remember together, and their myths (M11.1).
var culture: CulturalMemory
## Who matters to the world's history (M11.2).
var significance: Significance
## What is built, repaired and falls into ruin, and what the settlement
## decides to build (M12.1).
var construction: ConstructionSystem
var planner: SettlementPlanner
## Where people walk, the paths they wear (M12.2).
var traffic: Traffic
## People setting out to found new settlements (M12.3).
var migration: Migration
## Trade between settlements (M12.4).
var trade: TradeSystem
## Who leads each settlement (M12.5).
var governance: Governance
var buildings: BuildingLibrary
## Where the dead are laid (M10.3).
var graves: Graves
## Which of the player's powers have shown themselves (rain, wind, water).
var powers: ToolReveals
## The soil of all the land, and what grows on it.
var soil: SoilSystem
var vegetation: VegetationSystem
## What the player has done to this world.
var history: PlayerHistory
## Everyone who lives here.
var people: PersonRegistry
## Makes names in the sounds of the first culture.
var names: NameGenerator
## What people can do with their days (data/occupations).
var occupations: OccupationLibrary
## Finds ways across the world on foot.
var pathfinder: Pathfinder
## Walks people along those ways.
var movement: MovementSystem
## What people can decide to do (data/activities).
var activities: ActivityLibrary
## People living their days: needs, decisions, plans.
var behavior: BehaviorSystem
## Who notices what the player (and the world) does.
var perception: PerceptionSystem
## What everyone remembers.
var memories: MemoryStore
## What everyone has been doing lately (the card's "Today").
var day_log: DayLog
## What resources there are (data/resources), what the world's nodes still
## hold, and the piles of what has been gathered.
var resources: ResourceLibrary
var nodes: ResourceNodes
var piles: PileStore
## The settlement around the fire: its stores, its job board (null in a
## world without one).
var settlement: Settlement
## Every settlement: the first (`settlement`) and those founded since (M12.3).
var settlements := Settlements.new()
## The fields and what grows on them.
var farming: Farming
## What the player does frightens the animals at least this near to it (tiles).
const STARTLE_RADIUS := 3.0
## The weather: what the sky does, how warm it is, what has fallen.
var weather: WeatherSystem
## The disasters the player brings down (the Disaster button).
var disasters: DisasterSystem
## What kinds of animals there are, the animals themselves, and their lives.
var species: SpeciesLibrary
var animals: AnimalRegistry
var fauna: AnimalSystem
## The boats (FB2): built at the landings, worn, torn loose and lost.
var boats: BoatSystem
## Big predators seen, and the alarm (PR2).
var predators: PredatorWatch
## The hunting parties sent after them (PR4).
var parties: HuntingParties
## Disputes and revolutions, seen (FC7).
var assemblies: Assemblies
## Raids walked (FC5).
var raids: RaidParties
## War fought in the open (FC6).
var wars: WarParties
## How long the player has stayed with one person (the OBSERVER achievement).
var observer: ObserverWatch
## What has happened in this world, and what led to what (data/events).
var event_defs: EventLibrary
var events: EventLog
## Writes it down as it happens.
var chronicle: Chronicler
## The world's numbers, hour by hour.
var stats: StatsRecorder
## When the box unfolds (M13.2).
var unfolder := BoxUnfolder.new()
## What is known of the box: seen, explored, mapped; its regions (M13.4).
var knowledge := FogOfKnowledge.new()
## What people know, in ten domains (M16.1; not to be confused with what the
## player knows of the box, above).
var learning := Knowledge.new()
## What a storehouse holds more, with pots (pottery) and with counting (mathematics).
const POTTERY_ROOM := 1.5
const COUNTED_ROOM := 1.25
var _saved_learning: Dictionary = {}
## What can be worked out, and what has been, where (M16.2; data/technologies).
var technologies: TechnologyLibrary
var technology := TechnologySystem.new()
var _saved_technology: Dictionary = {}
## What makes each settlement's people theirs: profiles, traditions, festivals (M17.1).
var cultures := CultureSystem.new()
var _saved_cultures: Dictionary = {}
## What becomes of myths: sacred places, founders, shrines, schisms (M17.2).
var faith := MythSystem.new()
var _saved_faith: Dictionary = {}
## Each settlement's words, in its own sounds (M17.3).
var lexicon := Lexicon.new()
var _saved_lexicon: Dictionary = {}
## The unexplained, recorded; scholars looking into it; the seeded mysteries (M18).
var anomaly_archive := AnomalyArchive.new()
var science := ScienceSystem.new()
var mysteries := MysterySystem.new()
## Disputes, raids, wars, revolutions (M19.1).
var conflicts := ConflictSystem.new()
var _saved_conflicts: Dictionary = {}
## The stories history tells (M19.2–19.3).
var stories := StoryEngine.new()
var _saved_stories: Dictionary = {}
var _saved_archive_m18: Dictionary = {}
var _saved_science: Dictionary = {}
var _saved_mysteries: Dictionary = {}
var _saved_knowledge: Dictionary = {}
## It is time to unfold: done at the next step (not inside the clock's own signal).
var unfold_pending := false
## The size of a new world's box (tiles; 0: Config.world.initial_world_tiles).
var _start_size := 0
## Makes time pass for all of that, in turns and within a budget.
var simulation: SimulationManager
var _saved_water: Dictionary = {} # the water's books from a save, until the water is bound
var _saved_hydrology: Dictionary = {}
var _saved_soil: Dictionary = {}
var _saved_vegetation: Dictionary = {}
var _saved_powers: Dictionary = {}
var _saved_relationships: Dictionary = {}
var _saved_households: Dictionary = {}
var _saved_lifecycle: Dictionary = {}
var _saved_archive: Dictionary = {}
var _saved_culture: Dictionary = {}
var _saved_construction: Dictionary = {}
var _saved_planner: Dictionary = {}
var _saved_traffic: Dictionary = {}
var _saved_disasters: Dictionary = {}
## (null: a world from before boats were things — its landings get theirs.)
var _saved_boats: Variant = {}
var _saved_predators: Dictionary = {}
var _saved_parties: Dictionary = {}
var _saved_assemblies: Dictionary = {}
var _saved_raids: Dictionary = {}
var _saved_wars: Dictionary = {}
var _saved_migration: Dictionary = {}
var _saved_trade: Dictionary = {}
var _saved_governance: Dictionary = {}
var _powers_looked := -1_000_000 # the game hour the dry-crop look was last taken in
var _saved_behavior: Dictionary = {} # likewise what the band knows, until behaviour is bound
var _saved_memories: Dictionary = {} # likewise what everyone remembers
var _saved_perception: Dictionary = {}
var _saved_day_log: Dictionary = {}
var _saved_settlement: Dictionary = {}
var _saved_settlements: Array = []
var _saved_farming: Dictionary = {}
var _saved_animals: Dictionary = {}
var _saved_events: Dictionary = {}
var _saved_weather: Dictionary = {}
var _saved_chronicle: Dictionary = {}
var _saved_stats: Dictionary = {}


func _init() -> void:
	day_log = DayLog.new()
	observer = ObserverWatch.new()
	nodes = ResourceNodes.new()
	piles = PileStore.new()
	farming = Farming.new()
	fauna = AnimalSystem.new()
	boats = BoatSystem.new()
	predators = PredatorWatch.new()
	parties = HuntingParties.new()
	assemblies = Assemblies.new()
	raids = RaidParties.new()
	wars = WarParties.new()
	weather = WeatherSystem.new()
	disasters = DisasterSystem.new()
	events = EventLog.new()
	chronicle = Chronicler.new()
	stats = StatsRecorder.new()
	stats.source = sample_stats
	# What the fields and the stores report is written down (see Chronicler).
	farming.first_field.connect(chronicle.on_first_field)
	farming.failed.connect(chronicle.on_crop_failed)
	farming.sown_thin.connect(chronicle.on_sown_thin)
	farming.harvest_thin.connect(chronicle.on_harvest_thin)
	farming.dry_spell.connect(chronicle.on_dry_spell)
	piles.stored.connect(chronicle.on_stored)
	weather.changed.connect(chronicle.on_weather_changed)
	weather.condition_changed.connect(chronicle.on_condition_changed)
	# The fields' rain is the weather's, and its frost.
	farming.rain_source = weather.rain_on
	farming.frozen_source = weather.is_frozen
	farming.frost_killed.connect(chronicle.on_crop_frozen)
	farming.drowned.connect(chronicle.on_crop_drowned)
	# The river: its level is the weather's doing; the fields feel it.
	hydrology = Hydrology.new()
	hydrology.settled_source = settled_tiles
	hydrology.occupied_source = func(tile: Vector2i) -> bool:
		return props != null and props.prop_at(tile) != null
	hydrology.high_water_changed.connect(chronicle.on_high_water)
	hydrology.low_water_changed.connect(chronicle.on_low_water)
	hydrology.flood_changed.connect(chronicle.on_flood)
	hydrology.eroded.connect(chronicle.on_bank_eroded)
	farming.groundwater_source = hydrology.groundwater
	farming.drying_source = hydrology.drying
	# The land: its soil, its grass and its trees.
	soil = SoilSystem.new()
	vegetation = VegetationSystem.new()
	nodes.depleted.connect(vegetation.on_depleted)
	nodes.regrown.connect(vegetation.on_regrown)
	vegetation.tree_died.connect(chronicle.on_tree_died)
	# A storm breaking, the rain coming back after a drought, the river in
	# the huts: nature's doing — and noticed.
	weather.changed.connect(func(_old: StringName, now: StringName) -> void:
		if now == WeatherSystem.STORM:
			emit_natural(Stimulus.THUNDERSTORM))
	weather.condition_changed.connect(func(condition: StringName, active: bool) -> void:
		if condition == WeatherSystem.DROUGHT and not active:
			emit_natural(Stimulus.RAIN_RETURNED))
	hydrology.flood_changed.connect(func(active: bool, _tiles: int, at: Vector2) -> void:
		if active:
			emit_natural(Stimulus.FLOOD, at))
	# What people are to each other; what is worth telling of it is told.
	relationships = RelationshipStore.new()
	relationships.kind_changed.connect(func(a: int, b: int, kind: int, gained: bool) -> void:
		# (Seen, FC2: friends wave; those who make it up embrace.)
		if behavior != null and behavior.ctx != null:
			if kind == Relationship.Kind.FRIEND and gained:
				behavior.ctx.scenes.append([Scenes.FRIENDS, a, b])
			elif kind == Relationship.Kind.RIVAL and not gained:
				behavior.ctx.scenes.append([Scenes.EMBRACE, a, b])
		var event := chronicle.on_kind_changed(a, b, kind, gained)
		var record := relationships.between(a, b)
		if event != null and record != null:
			record.note_event(event.id))
	# Lives begin and end; what is worth telling of it is told.
	archive = HistoryArchive.new()
	graves = Graves.new()
	culture = CulturalMemory.new()
	significance = Significance.new()
	significance.became_important.connect(chronicle.on_became_important)
	construction = ConstructionSystem.new()
	planner = SettlementPlanner.new()
	traffic = Traffic.new()
	traffic.worn.connect(chronicle.on_path_worn)
	migration = Migration.new()
	migration.set_out.connect(func(journey: Dictionary) -> void:
		chronicle.on_set_out(journey, settlements.get_settlement(int(journey["from"]))))
	migration.founded.connect(chronicle.on_founded_by)
	# Where the fish are (FB1): a run, a bad year.
	fauna.waters.run_began.connect(chronicle.on_fish_run)
	fauna.waters.bad_year.connect(chronicle.on_bad_fishing_year)
	# The boats (FB2): the first of a kind, one lost.
	boats.boat_built.connect(chronicle.on_boat_built)
	boats.boat_lost.connect(chronicle.on_boat_lost)
	boats.swamped.connect(_on_boat_swamped)
	parties.ended.connect(chronicle.on_party_ended)
	parties.wounded.connect(chronicle.on_hurt_in_hunt)
	# Big predators (PR2): seen — told; gone back to the wilds — told, if they had been seen.
	predators.spotted.connect(func(kind: StringName, _group: int, at: Vector2, by_id: int, settlement_id: int) -> void:
		chronicle.on_predator_spotted(kind, at, by_id, settlement_id))
	predators.attacked.connect(func(person_id: int, kind: StringName, _severity: float, _killed: bool, settlement_id: int) -> void:
		chronicle.on_mauled(person_id, kind, settlement_id))
	fauna.left.connect(func(kind: StringName, group: int) -> void:
		var seen := predators.known(group)
		if not seen.is_empty():
			chronicle.on_predator_gone(kind, int(seen["settlement"])))
	migration.joining.connect(func(journey: Dictionary) -> void:
		var from := settlements.get_settlement(int(journey["from"]))
		var to := settlements.get_settlement(int(journey["target"]))
		chronicle.on_joining(journey, from.display_name() if from != null else "", to.display_name() if to != null else ""))
	migration.abandoned.connect(func(id: int, name: String, at: Vector2i) -> void:
		chronicle.on_abandoned(id, name, at)
		learning.forget_settlement(id)
		cultures.forget_settlement(id)
		lexicon.forget_settlement(id)
		conflicts.forget_settlement(id)
		_place_settlements())
	governance = Governance.new()
	governance.led.connect(func(settlement_id: int, leader_id: int, was: int, why: StringName) -> void:
		var own := settlements.get_settlement(settlement_id)
		chronicle.on_led(settlement_id, own.display_name() if own != null else "", leader_id, was, why))
	trade = TradeSystem.new()
	trade.route_opened.connect(func(record: Dictionary) -> void:
		var from := settlements.get_settlement(int(record["from"]))
		var to := settlements.get_settlement(int(record["to"]))
		chronicle.on_route_opened(record, from.display_name() if from != null else "", to.display_name() if to != null else ""))
	# What one settlement knows travels with its loads and its founders (M16.2).
	trade.traded.connect(technology.on_traded)
	# Traditions and festivals (M17.1).
	cultures.tradition_formed.connect(chronicle.on_tradition)
	cultures.tradition_faded.connect(chronicle.on_tradition_faded)
	cultures.festival.connect(chronicle.on_festival)
	migration.founded.connect(cultures.on_founded)
	# Myths: hallowed, spoken for, carried, split (M17.2).
	culture.myth_formed.connect(faith.on_myth)
	migration.founded.connect(faith.on_founded)
	trade.traded.connect(faith.on_traded)
	faith.founded.connect(chronicle.on_faith_founded)
	faith.spread.connect(func(myth: Dictionary, _from: int) -> void: chronicle.on_myth_spread(myth))
	faith.schism.connect(chronicle.on_schism)
	# Words: coined, inherited, borrowed; a settlement named in its own (M17.3).
	migration.founded.connect(lexicon.on_founded)
	trade.traded.connect(lexicon.on_traded)
	lexicon.renamed.connect(chronicle.on_renamed)
	# Strife (M19.1): each step told, with what caused it; the next step names it.
	conflicts.dispute.connect(func(a: int, b: int, _causes: Array) -> void:
		assemblies.dispute(a, b, clock.tick)) # (seen the next morning: FC7)
	conflicts.revolution.connect(func(id: int, deposed_id: int) -> void:
		assemblies.revolution(id, deposed_id, clock.tick))
	raids.done.connect(func(raid: Dictionary, taken: int, was_repelled: bool) -> void:
		conflicts.raid_done(int(raid["raider"]), int(raid["victim"]), taken, int(raid["leader"]), raid["causes"], was_repelled))
	wars.ended.connect(conflicts.battle_done)
	conflicts.repelled.connect(func(raider: int, victim: int, leader: int, causes: Array) -> void:
		chronicle.on_conflict(&"raid_repelled", raider, victim, [leader] if leader != 0 else [], causes))
	conflicts.dispute.connect(func(a: int, b: int, causes: Array) -> void:
		var e := chronicle.on_conflict(&"dispute", a, b, [], causes)
		if e != null:
			conflicts.note_event(a, b, "dispute", e.id))
	conflicts.raided.connect(func(raider: int, victim: int, units: int, leader: int, causes: Array) -> void:
		var e := chronicle.on_conflict(&"raid", raider, victim, [leader] if leader != 0 else [], causes, {"units": units})
		if e != null:
			conflicts.note_event(raider, victim, "raid", e.id))
	conflicts.war_begun.connect(func(a: int, b: int, causes: Array) -> void:
		var e := chronicle.on_conflict(&"war_begun", a, b, [], causes)
		if e != null:
			conflicts.note_event(a, b, "war", e.id))
	conflicts.battle.connect(func(a: int, b: int, fallen: Array, heroes: Array) -> void:
		var war := int((conflicts.pair(a, b)["war"] as Dictionary).get("event", 0))
		var e := chronicle.on_conflict(&"battle", a, b, heroes, [war] if war > 0 else [], {"fallen": fallen.size()})
		if e != null:
			conflicts.note_event(a, b, "battle", e.id))
	conflicts.peace.connect(func(a: int, b: int, fallen: int) -> void:
		var war := chronicle.latest_between(&"war_begun", a, b)
		chronicle.on_conflict(&"peace", a, b, [], [war] if war > 0 else [], {"fallen": fallen})
		# (FC6: border stones where they fought; the leaders meet there, seen.)
		border_stones(a, b)
		if walking_raids:
			assemblies.peace(a, b, clock.tick))
	conflicts.revolution.connect(func(id: int, deposed_id: int) -> void:
		chronicle.on_conflict(&"revolution", id, id, [deposed_id], []))
	# Stories (M19.2): looked for yearly, and soon after anything momentous.
	events.recorded.connect(stories.on_recorded)
	stories.reinterpreted.connect(func(story: Dictionary, historian_id: int) -> void:
		chronicle.on_reinterpreted(stories.name_of(story), historian_id, int(story["events"][0])))
	# Science and the mysteries (M18).
	science.hypothesis_formed.connect(chronicle.on_hypothesis)
	science.stage_reached.connect(chronicle.on_box_research)
	mysteries.clue_found.connect(func(id: StringName, step: int, person_id: int) -> void:
		var def := mysteries.get_def(id)
		var entry: Dictionary = mysteries.placed.get(id, {})
		chronicle.on_clue(id, step, person_id, Vector2(entry.get("tile", Vector2i.ZERO)) + Vector2(0.5, 0.5),
			def.significance if def != null else 0.6))
	weather.condition_changed.connect(func(condition: StringName, active: bool) -> void:
		if is_active:
			cultures.on_condition(condition, active, clock.tick))
	technology.era_entered.connect(chronicle.on_era)
	# Something new is known: what it changes, at once (M16.3; and see _make_settlement).
	technology.spread.connect(func(_settlement_id: int, _tech: StringName, _person: int, _from: int) -> void:
		_apply_storehouses()
		technology.apply_effects())
	migration.founded.connect(technology.on_founded)
	technology.spread.connect(func(settlement_id: int, tech_id: StringName, person_id: int, from_id: int) -> void:
		var from := settlements.get_settlement(from_id)
		chronicle.on_knowledge_spread(settlement_id, tech_id, person_id, from.display_name() if from != null else ""))
	construction.begun.connect(chronicle.on_building_begun)
	construction.finished.connect(chronicle.on_building_built)
	construction.finished.connect(func(_project: Dictionary, _id: int) -> void: _apply_storehouses())
	# A new home: a household that shares a crowded roof moves in.
	construction.finished.connect(func(_project: Dictionary, id: int) -> void:
		if start != null and start.hut_ids.has(id):
			households.take_new_home(id))
	# (A building mended, food gone bad: everyday, and no longer written into
	# history — a third of the log was spoilage: the owner, 2026-10-06.)
	construction.damaged.connect(chronicle.on_building_damaged)
	construction.ruined.connect(chronicle.on_building_ruined)
	# (A bridge finished where it stood: the way over it is open.)
	construction.finished.connect(func(project: Dictionary, _id: int) -> void:
		pathfinder.mark_dirty(project["tile"])
		# (… and what had no way to it may have one now.)
		for own in settlements.all():
			if own.places() != null:
				own.places().forget_out_of_reach()
		if behavior.ctx != null and behavior.ctx.places != null:
			behavior.ctx.places.forget_out_of_reach())
	construction.ruined.connect(func(_id: int, _def: StringName, _why: StringName) -> void:
		_apply_storehouses()
		households.rehouse())
	# Floods and storms wear the buildings (M12.1).
	hydrology.flood_changed.connect(func(active: bool, _tiles: int, _at: Vector2) -> void:
		if active and is_active:
			for prop in props.all_props():
				# (A bridge stands in the water: only water up to its deck harms it.)
				var harmed := Crossing.flooded(world, props, prop) if prop.kind == PropData.Kind.BRIDGE else world.get_water(prop.tile) > 0.0
				if prop.is_building() and harmed:
					construction.damage(prop.id, Config.construction.flood_damage, &"flood", clock.tick))
	weather.changed.connect(func(_old: StringName, now: StringName) -> void:
		if (now == WeatherSystem.STORM or now == WeatherSystem.BLIZZARD) and is_active:
			for prop in props.buildings():
				if prop.is_building():
					construction.damage(prop.id, Config.construction.storm_damage, now, clock.tick))
	culture.formed.connect(chronicle.on_cultural_memory)
	culture.myth_formed.connect(chronicle.on_myth)
	households = Households.new()
	lifecycle = Lifecycle.new()
	lifecycle.born.connect(chronicle.on_born)
	learning.lost.connect(chronicle.on_knowledge_lost)
	# What goes wrong teaches (M16.1).
	events.recorded.connect(learning.on_event)
	lifecycle.died.connect(func(person_id: int, cause: StringName, causes: Array) -> void:
		var obituary := chronicle.on_died(person_id, cause, causes)
		var record := archive.get_record(person_id)
		if obituary != null and record != null:
			record.obituary_event = obituary.id)
	# What only the dying knew goes with them (they are still counted here).
	lifecycle.died.connect(func(person_id: int, _cause: StringName, _causes: Array) -> void:
		learning.on_dying(person_id))
	lifecycle.partnered.connect(chronicle.on_partnered)
	# Seen (FC3): mourners at the grave; a new couple's embrace; the parents' joy.
	lifecycle.died.connect(func(person_id: int, _cause: StringName, _causes: Array) -> void:
		var dead := people.get_person(person_id)
		if dead != null and behavior != null and behavior.ctx != null:
			Scenes.mourn(behavior, behavior.ctx, person_id, _cemetery_near(dead.position)))
	lifecycle.partnered.connect(func(a: int, b: int) -> void:
		if behavior != null and behavior.ctx != null:
			for id: int in [a, b]:
				Signs.flash(people.get_person(id), Signs.LOVE, clock.tick)
			behavior.ctx.scenes.append([Scenes.EMBRACE, a, b]))
	lifecycle.born.connect(func(_child: int, mother: int, father: int) -> void:
		for id: int in [mother, father]:
			Signs.flash(people.get_person(id), Signs.LOVE, clock.tick, 30))
	lifecycle.came_of_age.connect(chronicle.on_came_of_age)
	lifecycle.injured.connect(chronicle.on_injured)
	lifecycle.taken_in.connect(chronicle.on_taken_in)
	lifecycle.arrived.connect(chronicle.on_arrived)
	# The player's powers show themselves when the world gives the idea of them.
	powers = ToolReveals.new()
	weather.changed.connect(func(_old: StringName, now: StringName) -> void:
		if is_active:
			powers.on_weather(now, clock.tick))
	fauna.migrated.connect(chronicle.on_migrated)
	# Shallow water that is frozen carries.
	weather.frozen_changed.connect(func(frozen: bool) -> void:
		pathfinder.set_frozen(frozen, Config.seasons.ice_depth))
	# A field is sown with grain from the stores.
	farming.seed_source = func(units: int) -> bool:
		return settlement != null and settlement.stockpile.take(&"grain", units) == units
	nodes.reaped.connect(func(prop_id: int) -> void:
		var crop := props.get_prop(prop_id) if props != null else null
		if crop != null:
			farming.reaped(crop, clock.tick))
	interactions = InteractionManager.new()
	interactions.name = "InteractionManager"
	add_child(interactions)
	loose_system = LooseObjectSystem.new()
	loose_system.name = "LooseObjectSystem"
	add_child(loose_system)
	water = WaterSim.new()
	water.name = "WaterSim"
	add_child(water)
	water.tiles_changed.connect(loose_system.on_water_changed)
	pathfinder = Pathfinder.new()
	movement = MovementSystem.new()
	behavior = BehaviorSystem.new()
	perception = PerceptionSystem.new()
	memories = MemoryStore.new()
	memories.remembered.connect(learning.on_remembered)
	interactions.stimulus_emitted.connect(perception.emit)
	# What the player does startles the animals near it.
	interactions.stimulus_emitted.connect(func(stimulus: Stimulus) -> void:
		if stimulus != null and clock != null:
			fauna.startle(stimulus.position, maxf(stimulus.radius, STARTLE_RADIUS), clock.tick))
	perception.noticed.connect(behavior.notice)
	interactions.stimulus_emitted.connect(func(stimulus: Stimulus) -> void:
		if is_active and perception.last == stimulus:
			anomaly_archive.on_stimulus(stimulus, perception.last_noticed, clock.tick))
	interactions.intervention_applied.connect(chronicle.on_intervention)
	interactions.intervention_applied.connect(func(iv: Intervention) -> void:
		if iv != null and iv.applied and iv.type == Intervention.TOUCH and iv.subject == &"water":
			powers.on_water_touched(history.count(Intervention.TOUCH, &"water"), clock.tick))
	behavior.hunted.connect(chronicle.on_hunted)
	behavior.social.connect(func(act: StringName, a: int, b: int) -> void:
		var event := chronicle.on_social(act, a, b)
		var record := relationships.between(a, b)
		if event != null and record != null:
			record.note_event(event.id))
	behavior.fell_ill.connect(chronicle.on_fell_ill)
	# A child goes to bed: perhaps a story (M11.1).
	behavior.bedtime.connect(func(child_id: int) -> void:
		var child := people.get_person(child_id) if people != null else null
		if child != null and behavior.ctx != null:
			Stories.bedtime(behavior.ctx, child))
	# A flood in the settlement: everyone remembers living through it.
	hydrology.flood_changed.connect(func(active: bool, _tiles: int, _at: Vector2) -> void:
		if active and is_active:
			lifecycle.remember_all(&"life_flood", clock.tick, 0.6))
	behavior.recovered.connect(chronicle.on_recovered)
	simulation = SimulationManager.new()
	simulation.name = "SimulationManager"
	add_child(simulation)


## Starts a brand-new world. seed_value 0 picks a random seed and re-rolls it
## until the world is livable; an explicit seed is always used as given.
func create_new(seed_value: int = 0, size_tiles: int = 0, land: StringName = &"") -> void:
	if is_active:
		shutdown()
	_start_size = size_tiles
	unfolder = BoxUnfolder.new()
	unfold_pending = false
	created_unix = int(Time.get_unix_time_from_system())
	clock = GameClock.new(Config.time)
	template_id = land if land != &"" and ResourceLoader.exists("%s%s.tres" % [TEMPLATE_DIR, land]) else DEFAULT_TEMPLATE_ID
	history = PlayerHistory.new()
	observer.reset()
	_saved_behavior = {}
	_saved_memories = {}
	_saved_perception = {}
	_saved_day_log = {}
	_saved_events = {}
	_saved_chronicle = {}
	_saved_stats = {}
	_saved_weather = {}
	_saved_hydrology = {}
	_saved_soil = {}
	_saved_vegetation = {}
	_saved_powers = {}
	_saved_relationships = {}
	_saved_households = {}
	_saved_lifecycle = {}
	_saved_archive = {}
	_saved_culture = {}
	_saved_construction = {}
	_saved_planner = {}
	_saved_traffic = {}
	_saved_disasters = {}
	_saved_boats = {}
	_saved_predators = {}
	_saved_parties = {}
	_saved_assemblies = {}
	_saved_raids = {}
	_saved_wars = {}
	var explicit := seed_value != 0
	for attempt in MAX_SEED_ATTEMPTS:
		world_seed = seed_value if explicit else RngStreams.new_world_seed()
		ids = IdAllocator.new()
		_build_new_world(ids)
		if start.ok or explicit:
			break
		Log.warn(Log.Category.WORLD, "Re-rolling seed: world not livable", {"seed": world_seed, "problems": start.problems})
	if not start.ok:
		Log.warn(Log.Category.WORLD, "World has problems", {"seed": world_seed, "problems": start.problems})
	world_id = _make_world_id(world_seed, created_unix)
	rng = RngStreams.new(world_seed)
	_restore_people({})
	_activate()
	if settlement != null:
		# (What it is given to begin with is no event; that it began is the first.)
		chronicle.listening = false
		settlement.stock_up(clock.tick)
		chronicle.listening = true
		chronicle.founded()
		settlement.ensure_farmer(clock.tick)
		settlement.ensure_hunter(clock.tick)
	Log.info(Log.Category.WORLD, "New world created", {"world_id": world_id, "seed": world_seed})


## Restores a world from to_dict() output. Returns false (and stays inactive)
## if the data is unusable; the caller decides how to recover.
func load_from(data: Dictionary) -> bool:
	for key in FORMAT_KEYS:
		if not data.has(key):
			Log.error(Log.Category.LOAD, "World data missing key", {"key": key})
			return false
	if is_active:
		shutdown()
	world_id = String(data["world_id"])
	world_seed = int(data["world_seed"])
	created_unix = int(data["created_unix"])
	clock = GameClock.new(Config.time)
	clock.from_dict(data["clock"])
	ids = IdAllocator.new()
	ids.from_dict(data["ids"])
	rng = RngStreams.new(world_seed)
	rng.from_dict(data["rng"])

	var state: Variant = data.get("world_state", {})
	history = PlayerHistory.new()
	_saved_water = {}
	_saved_behavior = {}
	_saved_memories = {}
	_saved_perception = {}
	_saved_day_log = {}
	_saved_settlement = {}
	_saved_settlements = []
	_saved_migration = {}
	_saved_trade = {}
	_saved_governance = {}
	_saved_farming = {}
	_saved_animals = {}
	_saved_events = {}
	_saved_chronicle = {}
	_saved_stats = {}
	_saved_weather = {}
	_saved_hydrology = {}
	_saved_soil = {}
	_saved_vegetation = {}
	_saved_powers = {}
	_saved_relationships = {}
	_saved_households = {}
	_saved_lifecycle = {}
	_saved_archive = {}
	_saved_culture = {}
	_saved_construction = {}
	_saved_planner = {}
	_saved_traffic = {}
	_saved_disasters = {}
	observer.reset()
	if typeof(state) == TYPE_DICTIONARY:
		if typeof((state as Dictionary).get("traffic")) == TYPE_DICTIONARY:
			_saved_traffic = state["traffic"]
		_saved_disasters = state["disasters"] if typeof((state as Dictionary).get("disasters")) == TYPE_DICTIONARY else {}
		_saved_boats = state["boats"] if typeof((state as Dictionary).get("boats")) == TYPE_DICTIONARY else null
		_saved_predators = state["predators"] if typeof((state as Dictionary).get("predators")) == TYPE_DICTIONARY else {}
		_saved_parties = state["parties"] if typeof((state as Dictionary).get("parties")) == TYPE_DICTIONARY else {}
		_saved_assemblies = state["assemblies"] if typeof((state as Dictionary).get("assemblies")) == TYPE_DICTIONARY else {}
		_saved_raids = state["raids"] if typeof((state as Dictionary).get("raids")) == TYPE_DICTIONARY else {}
		_saved_wars = state["wars"] if typeof((state as Dictionary).get("wars")) == TYPE_DICTIONARY else {}
		if typeof((state as Dictionary).get("construction")) == TYPE_DICTIONARY:
			_saved_construction = state["construction"]
		if typeof((state as Dictionary).get("planner")) == TYPE_DICTIONARY:
			_saved_planner = state["planner"]
		if typeof((state as Dictionary).get("culture")) == TYPE_DICTIONARY:
			_saved_culture = state["culture"]
		if typeof((state as Dictionary).get("relationships")) == TYPE_DICTIONARY:
			_saved_relationships = state["relationships"]
		if typeof((state as Dictionary).get("households")) == TYPE_DICTIONARY:
			_saved_households = state["households"]
		if typeof((state as Dictionary).get("lifecycle")) == TYPE_DICTIONARY:
			_saved_lifecycle = state["lifecycle"]
		if typeof((state as Dictionary).get("archive")) == TYPE_DICTIONARY:
			_saved_archive = state["archive"]
		if typeof((state as Dictionary).get("powers")) == TYPE_DICTIONARY:
			_saved_powers = state["powers"]
		if typeof((state as Dictionary).get("soil")) == TYPE_DICTIONARY:
			_saved_soil = state["soil"]
		if typeof((state as Dictionary).get("vegetation")) == TYPE_DICTIONARY:
			_saved_vegetation = state["vegetation"]
		if typeof((state as Dictionary).get("hydrology")) == TYPE_DICTIONARY:
			_saved_hydrology = state["hydrology"]
		if typeof((state as Dictionary).get("weather")) == TYPE_DICTIONARY:
			_saved_weather = state["weather"]
		if typeof((state as Dictionary).get("events")) == TYPE_DICTIONARY:
			_saved_events = state["events"]
		if typeof((state as Dictionary).get("chronicle")) == TYPE_DICTIONARY:
			_saved_chronicle = state["chronicle"]
		if typeof((state as Dictionary).get("stats")) == TYPE_DICTIONARY:
			_saved_stats = state["stats"]
		_saved_learning = state["learning"] if typeof((state as Dictionary).get("learning")) == TYPE_DICTIONARY else {}
		_saved_technology = state["technology"] if typeof((state as Dictionary).get("technology")) == TYPE_DICTIONARY else {}
		_saved_cultures = state["cultures"] if typeof((state as Dictionary).get("cultures")) == TYPE_DICTIONARY else {}
		_saved_faith = state["faith"] if typeof((state as Dictionary).get("faith")) == TYPE_DICTIONARY else {}
		_saved_lexicon = state["lexicon"] if typeof((state as Dictionary).get("lexicon")) == TYPE_DICTIONARY else {}
		_saved_archive_m18 = state["anomalies"] if typeof((state as Dictionary).get("anomalies")) == TYPE_DICTIONARY else {}
		_saved_science = state["science"] if typeof((state as Dictionary).get("science")) == TYPE_DICTIONARY else {}
		_saved_mysteries = state["mysteries"] if typeof((state as Dictionary).get("mysteries")) == TYPE_DICTIONARY else {}
		_saved_conflicts = state["conflicts"] if typeof((state as Dictionary).get("conflicts")) == TYPE_DICTIONARY else {}
		_saved_stories = state["stories"] if typeof((state as Dictionary).get("stories")) == TYPE_DICTIONARY else {}
		unfolder = BoxUnfolder.new()
		unfold_pending = false
		if typeof((state as Dictionary).get("unfolder")) == TYPE_DICTIONARY:
			unfolder.from_dict(state["unfolder"])
		_saved_knowledge = state["knowledge"] if typeof((state as Dictionary).get("knowledge")) == TYPE_DICTIONARY else {}
		if typeof((state as Dictionary).get("animals")) == TYPE_DICTIONARY:
			_saved_animals = state["animals"]
		if typeof((state as Dictionary).get("farming")) == TYPE_DICTIONARY:
			_saved_farming = state["farming"]
		if typeof((state as Dictionary).get("settlement")) == TYPE_DICTIONARY:
			_saved_settlement = state["settlement"]
		if typeof((state as Dictionary).get("settlements")) == TYPE_ARRAY:
			_saved_settlements = state["settlements"]
		if typeof((state as Dictionary).get("migration")) == TYPE_DICTIONARY:
			_saved_migration = state["migration"]
		if typeof((state as Dictionary).get("trade")) == TYPE_DICTIONARY:
			_saved_trade = state["trade"]
		if typeof((state as Dictionary).get("governance")) == TYPE_DICTIONARY:
			_saved_governance = state["governance"]
		if typeof((state as Dictionary).get("day_log")) == TYPE_DICTIONARY:
			_saved_day_log = state["day_log"]
		if typeof((state as Dictionary).get("observer")) == TYPE_DICTIONARY:
			observer.from_dict(state["observer"])
		if typeof((state as Dictionary).get("history")) == TYPE_DICTIONARY:
			history.from_dict(state["history"])
		if typeof((state as Dictionary).get("water")) == TYPE_DICTIONARY:
			_saved_water = state["water"]
		if typeof((state as Dictionary).get("behavior")) == TYPE_DICTIONARY:
			_saved_behavior = state["behavior"]
		if typeof((state as Dictionary).get("memories")) == TYPE_DICTIONARY:
			_saved_memories = state["memories"]
		if typeof((state as Dictionary).get("perception")) == TYPE_DICTIONARY:
			_saved_perception = state["perception"]
	if typeof(state) != TYPE_DICTIONARY or not _restore_world(state):
		# No usable world state (a migrated version-1 save, or damaged data):
		# rebuild from the seed. The setup's props take the same low ids they
		# had when the world was created; keep the allocator clear of them.
		if typeof(state) == TYPE_DICTIONARY and not (state as Dictionary).is_empty():
			Log.error(Log.Category.LOAD, "World state unusable; rebuilding the world from its seed")
		template_id = DEFAULT_TEMPLATE_ID
		var setup_ids := IdAllocator.new()
		_build_new_world(setup_ids)
		ids.reserve_above(setup_ids.peek() - 1)
	var saved_people: Variant = (state as Dictionary).get("people") if typeof(state) == TYPE_DICTIONARY else null
	_restore_people(saved_people if typeof(saved_people) == TYPE_DICTIONARY else {})
	_activate()
	Log.info(Log.Category.LOAD, "World loaded", {"world_id": world_id, "tick": clock.tick})
	return true


## Tells the world whom the camera is with right now (0 = nobody): staying
## with one person for a whole day is the OBSERVER achievement. Returns true
## at the moment it is unlocked.
func watch_followed(person_id: int) -> bool:
	if not is_active or history.has_achievement(PlayerHistory.OBSERVER):
		return false
	if person_id != 0 and people.get_person(person_id) == null:
		person_id = 0
	if not observer.update(clock.tick, person_id):
		return false
	history.unlock(PlayerHistory.OBSERVER, clock.tick)
	for achievement in history.take_unlocked():
		Log.info(Log.Category.WORLD, "Achievement unlocked", {"achievement": achievement, "tick": clock.tick})
		EventBus.achievement_unlocked.emit(achievement)
	SaveManager.note_world_changed()
	return true


## Everything about the world that is saved. (Before it is written, everyone
## lives the time that has built up for them: nobody is saved "behind".)
func to_dict() -> Dictionary:
	if is_active:
		simulation.settle()
	return {
		"world_id": world_id,
		"world_seed": world_seed,
		"created_unix": created_unix,
		"clock": clock.to_dict(),
		"ids": ids.to_dict(),
		"rng": rng.to_dict(),
		"world_state": {
			"template_id": String(template_id),
			"generator_version": WorldGenerator.GENERATOR_VERSION,
			"world": world.to_dict(),
			"props": props.to_dict(),
			"loose": loose.to_dict(),
			"history": history.to_dict(),
			"water": water.to_dict(),
			"people": people.to_dict(),
			"behavior": behavior.to_dict(),
			"memories": memories.to_dict(),
			"day_log": day_log.to_dict(),
			"observer": observer.to_dict(),
			"settlement": settlement.to_dict() if settlement != null else {},
			"settlements": _settlements_to_save(),
			"migration": migration.to_dict(),
			"trade": trade.to_dict(),
			"governance": governance.to_dict(),
			"farming": farming.to_dict(),
			"animals": fauna.to_dict(),
			"events": events.to_dict(),
			"chronicle": chronicle.to_dict(),
			"stats": stats.to_dict(),
			"learning": learning.to_dict(),
			"technology": technology.to_dict(),
			"cultures": cultures.to_dict(),
			"faith": faith.to_dict(),
			"lexicon": lexicon.to_dict(),
			"anomalies": anomaly_archive.to_dict(),
			"science": science.to_dict(),
			"mysteries": mysteries.to_dict(),
			"conflicts": conflicts.to_dict(),
			"stories": stories.to_dict(),
			"unfolder": unfolder.to_dict(),
			"knowledge": knowledge.to_dict(),
			"weather": weather.to_dict(),
			"hydrology": hydrology.to_dict(),
			"powers": powers.to_dict(),
			"relationships": relationships.to_dict(),
			"households": households.to_dict(),
			"lifecycle": lifecycle.to_dict(),
			"archive": archive.to_dict(),
			"culture": culture.to_dict(),
			"construction": construction.to_dict(),
			"planner": planner.to_dict(),
			"traffic": traffic.to_dict(),
			"disasters": disasters.to_dict(),
			"boats": boats.to_dict(),
			"predators": predators.to_dict(),
			"parties": parties.to_dict(),
			"assemblies": assemblies.to_dict(),
			"raids": raids.to_dict(),
			"wars": wars.to_dict(),
			"soil": soil.to_dict(),
			"vegetation": vegetation.to_dict(),
			"perception": {"next_stimulus_id": behavior.ctx.next_stimulus_id if behavior.ctx != null else 1},
			"start": start.to_dict(),
		},
	}


func shutdown() -> void:
	if not is_active:
		return
	about_to_close.emit()
	is_active = false
	movement.stop_all()
	clock.speed_changed.disconnect(_on_speed_changed)
	clock.day_started.disconnect(_on_day_started)
	clock.season_changed.disconnect(_on_season_changed)
	clock.year_started.disconnect(_on_year_started)
	# (Settlements and their planners refer to each other: they are let go of here.)
	settlements.clear()
	settlement = null
	trade.settlements = null
	governance.settlements = null
	migration.behavior = null # (the behaviour's context knows migration)
	migration.add_settlement = Callable()
	Log.info(Log.Category.WORLD, "World closed", {"world_id": world_id})
	EventBus.world_unloaded.emit()


## Someone has found a region nobody had seen (M13.4): history says so.
func _on_region_found(person_id: int, region_id: int) -> void:
	var region := knowledge.regions.get_region(region_id)
	if region == null:
		return
	var person := people.get_person(person_id)
	events.record(&"region_found", {"participants": [person_id], "place": region.name, "position": region.centre,
		"settlement": person.settlement_id if person != null else 0})


## Unfolds the box if it is time (checked once a day; done here, between
## steps). Returns whether it did. (The soak calls it too.)
func unfold_if_due() -> bool:
	if not unfold_pending:
		return false
	unfold_pending = false
	return unfold()


## The box unfolds (M13.2, bible §8.6): a ring of chunks all round, the walls
## moved out, and history says so ("The edge of the world has moved"). The
## world is written down and opened again as it now is — every part of it
## the size of the new box, the new land as the generator makes it (its trees,
## rocks and water as everywhere else). False if it is as large as it may be.
func unfold() -> bool:
	if not is_active:
		return false
	var old := world.bounds
	var grown := old.grow(world.chunk_size)
	if grown.size.x > Config.world.max_world_tiles or grown.size.y > Config.world.max_world_tiles:
		return false
	unfolder.note(clock.tick)
	var at := Vector2(start.settlement_tile) + Vector2(0.5, 0.5) if start != null else Vector2.INF
	events.record(&"edge_moved", {"from": old.size.x, "to": grown.size.x, "position": at})
	world.bounds = grown
	var data := to_dict()
	if not load_from(data):
		Log.error(Log.Category.WORLD, "The box could not unfold", {"from": old, "to": grown})
		return false
	Log.info(Log.Category.WORLD, "The box unfolded", {"from": old.size, "to": grown.size})
	unfolded.emit(old, grown)
	return true


## Freeing the session always closes the world cleanly.
func _exit_tree() -> void:
	shutdown()


func _process(delta: float) -> void:
	if is_active:
		unfold_if_due()
		var t := Time.get_ticks_usec() if profiling else 0
		simulation.advance(delta)
		t = _timed(&"people", t)
		if not clock.is_paused():
			boats.step(delta * clock.speed_multiplier())
		advance_systems()
		if profiling:
			_profile_frames += 1


## Timing each part of the frame (the debug overlay's "profile" lines, for
## measuring on the phone — 2026-10-06): name -> [average µs, worst µs in the
## last PROFILE_WINDOW frames, worst in the window before, this frame's].
var profiling := false
var profile := {}
var _profile_frames := 0
const PROFILE_WINDOW := 600


## Notes how long `name` took since `since` (µs); returns now. Nothing while
## not profiling.
func _timed(name: StringName, since: int) -> int:
	if not profiling:
		return 0
	var now := Time.get_ticks_usec()
	var took := now - since
	var entry: Array = profile.get(name, [0.0, 0, 0, 0])
	entry[0] = lerpf(entry[0], float(took), 0.02)
	if _profile_frames % PROFILE_WINDOW == 0 and _profile_frames > 0 and name == &"people":
		_turn_profile_window()
		entry = profile.get(name, [0.0, 0, 0, 0])
	entry[1] = maxi(int(entry[1]), took)
	if entry.size() < 4:
		entry.append(0)
	entry[3] = took # (this frame's)
	profile[name] = entry
	return now


func _turn_profile_window() -> void:
	for name: StringName in profile:
		var entry: Array = profile[name]
		entry[2] = entry[1]
		entry[1] = 0


## Everything that goes by the clock rather than by people's minutes, brought
## up to the clock (each frame — and, while the player is away, day by day: M20).
func advance_systems() -> void:
	# (What is done once a game day is spread over the first minutes of it —
	# each such system a few minutes after the one before — so that it does
	# not all fall on the one frame at midnight: profiling, 2026-10-06.)
	var t := Time.get_ticks_usec() if profiling else 0
	for entry: Array in system_steps():
		(entry[1] as Callable).call()
		t = _timed(entry[0], t)


## Everything advance_systems does, in order, as named steps — so that the
## time away can be lived a step at a time between frames (the opening
## stuttered behind a whole day of them: the owner, 2026-10-08).
func system_steps() -> Array:
	if _system_steps.is_empty():
		_system_steps = [
			[&"knowledge", func() -> void: knowledge.advance_to(clock.tick - STAGGER_KNOWLEDGE)],
			[&"learning", func() -> void: learning.advance_to(clock.tick - STAGGER_LEARNING)],
			[&"technology", func() -> void: technology.advance_to(clock.tick - STAGGER_TECHNOLOGY)],
			[&"cultures", func() -> void: cultures.advance_to(clock.tick)],
			[&"faith", func() -> void: faith.advance_to(clock.tick)],
			[&"lexicon", func() -> void: lexicon.advance_to(clock.tick)],
			[&"anomaly_archive", func() -> void: anomaly_archive.advance_to(clock.tick)],
			[&"science", func() -> void: science.advance_to(clock.tick)],
			[&"mysteries", func() -> void: mysteries.advance_to(clock.tick)],
			[&"conflicts", func() -> void: conflicts.advance_to(clock.tick)],
			[&"stories", func() -> void: stories.advance_to(clock.tick)],
			[&"weather", func() -> void: weather.advance_to(clock.tick)],
			[&"disasters", func() -> void: disasters.advance_to(clock.tick)],
			[&"soil", func() -> void: soil.advance_to(clock.tick - STAGGER_SOIL)],
			[&"powers", func() -> void: _look_for_powers()],
			[&"nodes", func() -> void:
				if nodes.due(clock.tick - STAGGER_NODES):
					nodes.settle(clock.tick - STAGGER_NODES)],
			[&"settlements", func() -> void: settlements.step(clock.tick)],
			# (These five the people's own step brings up to the clock too, at the
			# clock: never a staggered moment behind it — a day's dice would be
			# thrown again and again for the first minutes of every day as the two
			# took turns at "today" and "yesterday", 2026-10-08.)
			[&"relationships", func() -> void: relationships.settle(clock.tick)],
			[&"lifecycle", func() -> void: lifecycle.advance_to(clock.tick)],
			[&"culture", func() -> void: culture.advance_to(clock.tick)],
			[&"construction", func() -> void: construction.advance_to(clock.tick)],
			[&"traffic", func() -> void: traffic.advance_to(clock.tick)],
			[&"migration", func() -> void: migration.advance_to(clock.tick)],
			[&"trade", func() -> void: trade.advance_to(clock.tick)],
			[&"governance", func() -> void: governance.advance_to(clock.tick)],
			[&"fauna", func() -> void: fauna.advance_to(clock.tick)],
			[&"boats", func() -> void: boats.advance_to(clock.tick - STAGGER_BOATS)],
			[&"predators", func() -> void:
				predators.advance_to(clock.tick)
				parties.advance_to(clock.tick)
				assemblies.advance_to(clock.tick)
				raids.advance_to(clock.tick)
				wars.advance_to(clock.tick)],
			[&"stats", func() -> void: stats.advance_to(clock.tick - STAGGER_STATS)],
		]
	return _system_steps


var _system_steps: Array = []

## How many game minutes after midnight each system that works once a day
## does it (see advance_systems).
## (Only for systems nothing else brings up to the clock: one called at the
## clock as well would go back and forth between the two days — see system_steps.)
const STAGGER_KNOWLEDGE := 6
const STAGGER_STATS := 18
const STAGGER_NODES := 24
const STAGGER_SOIL := 30
const STAGGER_TECHNOLOGY := 48
const STAGGER_LEARNING := 60
const STAGGER_BOATS := 72


## The boats (FB2), as saved — or, in a world from before, one at each
## landing that showed one.
func _bind_boats() -> void:
	boats.bind(world, props, ids, clock.tick)
	boats.settlements = settlements
	boats.construction = construction
	boats.weather = weather
	boats.hydrology = hydrology
	boats.is_frozen = pathfinder.is_frozen
	boats.current = water.current_at
	boats.rng = rng.stream(&"boats")
	boats.waters = fauna.waters
	boats.people = people
	boats.paths.is_ice = pathfinder.is_ice
	boats.paths.is_bridge = func(tile: Vector2i) -> bool:
		var there := props.prop_at(tile)
		return there != null and there.kind == PropData.Kind.BRIDGE
	if typeof(_saved_boats) == TYPE_DICTIONARY:
		var unusable := boats.from_dict(_saved_boats)
		if unusable > 0:
			Log.warn(Log.Category.LOAD, "Some saved boats were unusable and skipped", {"boats": unusable})
	else:
		boats.adopt_landings(clock.tick)
	_saved_boats = {}


## The cemetery nearest `tile`, within reach of mourners (null: none).
func _cemetery_near(tile: Vector2i) -> Variant:
	var best: Variant = null
	var best_d := 25.0
	for prop in props.of_kind(PropData.Kind.CEMETERY):
		var d := Vector2(prop.tile - tile).length()
		if prop.kind == PropData.Kind.CEMETERY and d < best_d:
			best = prop.tile
			best_d = d
	return best


## A boat swamped in a storm (FB4): told; whoever did not reach the bank drowned
## (after the turn they were living: nobody dies in the middle of a step).
func _on_boat_swamped(boat: BoatData, drowned: Array) -> void:
	chronicle.on_boat_swamped(boat, drowned.size())
	for id: int in drowned:
		(func() -> void:
			var person := people.get_person(id)
			if person != null and is_active:
				lifecycle.die(person, Lifecycle.CAUSE_DROWNED, clock.tick)).call_deferred()


## What nature does is noticed too (and people make of it what they will):
## something of `kind` happens around `at` — the settlement's fire, if no
## place is given.
func emit_natural(kind: StringName, at: Vector2 = Vector2.INF) -> void:
	if not is_active or perception == null:
		return
	if at == Vector2.INF:
		if settlement == null or settlement.fire() == null:
			return
		at = settlement.fire().position2d()
	perception.emit(Stimulus.natural(kind, at, clock.tick, Config.reactions))


## Once a game hour: does a crop stand dry in the field (the idea of rain)?
func _look_for_powers() -> void:
	@warning_ignore("integer_division")
	var hour := clock.tick / 60
	if hour == _powers_looked or powers.is_known(ToolReveals.RAIN):
		return
	_powers_looked = hour
	for crop in farming.crops():
		if Farming.looks_dry(crop):
			powers.on_dry_crop(clock.tick)
			return


## The tiles where people live and work: their huts, the fire, the fields.
func settled_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if props == null:
		return tiles
	for prop in props.all_props():
		if prop.kind == PropData.Kind.HUT or prop.kind == PropData.Kind.CAMPFIRE or prop.kind == PropData.Kind.CROP:
			tiles.append(prop.tile)
	return tiles


## Where the settlement keeps `resource` (the middle of its storage tile),
## or Vector2.INF if it has no such place.
func storage_place(resource: StringName) -> Vector2:
	var places := behavior.ctx.places if behavior.ctx != null else null
	return places.store_point(resource) if places != null else Vector2.INF


## How much of `resource` the settlement has in store: what lies in piles at
## its storage place (a pile carried off is no longer its own).
func stored(resource: StringName) -> int:
	var at := storage_place(resource)
	return piles.total(resource, at, Config.resources.storage_radius) if at != Vector2.INF else 0


## The world's numbers as they are now (what the StatsRecorder writes down
## every game hour; M15: StatsSampler).
func sample_stats() -> Dictionary:
	return StatsSampler.sample(self)


func _build_new_world(setup_ids: IdAllocator) -> void:
	var started := Time.get_ticks_msec()
	var template := _load_template(template_id)
	var size := _start_size if _start_size > 0 else Config.world.initial_world_tiles
	world = WorldData.create_centered(size, Config.world.chunk_size, Config.world.height_step)
	generator = WorldGenerator.new(world_seed, template, Config.world)
	generator.keep_made = true # (for the soil: see SoilSystem.bind)
	world.set_generator(generator)
	spatial = SpatialIndex.new(SpatialIndex.FINE_CELL_TILES)
	props = PropRegistry.new(world.chunk_size, spatial)
	loose = LooseObjectRegistry.new(world.chunk_size, spatial)
	start = WorldSetup.create_start(world, generator, props, setup_ids, loose)
	Log.debug(Log.Category.WORLD, "World built", {
		"ms": Time.get_ticks_msec() - started,
		"tiles": world.bounds.size,
		"props": props.size(),
		"loose": loose.size(),
		"settlement": start.settlement_tile,
	})


## The inhabitants: restored from `saved` (PersonRegistry.to_dict()), or — for
## a new world, a world saved before it had people, or unusable data — the
## starting band, made from the world's "people" dice. A world whose people
## are all gone stays empty: only a missing record brings a new band.
func _restore_people(saved: Dictionary) -> void:
	people = PersonRegistry.new(spatial)
	names = NameGenerator.new(Phonology.from_seed(RngStreams.derive_seed(world_seed, &"culture:%d" % FIRST_CULTURE_ID)))
	if occupations == null:
		occupations = OccupationLibrary.load_from()
	if saved.has("persons"):
		var skipped := people.from_dict(saved)
		if skipped >= 0:
			if skipped > 0:
				Log.warn(Log.Category.LOAD, "Some saved people were unusable and skipped", {"people": skipped})
			for person in people.all_people():
				ids.reserve_above(person.id)
			return
		Log.error(Log.Category.LOAD, "Saved people unusable; a new band arrives")
	if start == null or start.campfire_id == 0:
		return # nowhere to live (the world has no settlement)
	var band := StartingBand.spawn(people, ids, rng.stream(&"people"), names, occupations, world, props, start,
		clock.tick, Config.people, Config.time.ticks_per_year(), loose)
	Log.info(Log.Category.SIM, "The first band arrives", {
		"people": band.size(), "households": people.household_ids().size(), "settlement": start.settlement_id})
	for person in band:
		Log.debug(Log.Category.SIM, "  %s" % person.full_name(), {
			"age": person.age_years(clock.tick, Config.time.ticks_per_year()),
			"occupation": person.occupation_id, "household": person.household_id, "at": person.position})


# --- debug commands -----------------------------------------------------------------------------

## Debug: brings someone new into the world, at (or beside) `near`. They join
## the settlement as a household of their own. Null if there is no settlement.
func spawn_person(near: Vector2i, stage: PersonData.LifeStage = PersonData.LifeStage.ADULT) -> PersonData:
	if not is_active or start == null or start.campfire_id == 0:
		return null
	var person := PersonFactory.newcomer(ids, rng.stream(&"people"), names, occupations, people, start, pathfinder,
		clock.tick, near, stage)
	people.add(person)
	households.ensure_records(clock.tick)
	Log.info(Log.Category.SIM, "Someone arrives", {"person": person.full_name(), "id": person.id, "at": person.position,
		"occupation": person.occupation_id})
	EventBus.person_born.emit(person.id)
	return person


## Border stones (FC6) where two settlements have made peace: beside the
## ground they met on between their fires (or the middle, with no way between
## them) — once. Returns them (null: none set).
func border_stones(a: int, b: int) -> PropData:
	var one := settlements.get_settlement(a)
	var two := settlements.get_settlement(b)
	if one == null or two == null or one.fire() == null or two.fire() == null or pathfinder == null:
		return null
	var ground: Variant = wars.meeting_ground(one, two)
	var at: Vector2i = ground if ground != null else WorldCoords.world2d_to_tile((Vector2(one.fire().tile) + Vector2(two.fire().tile)) * 0.5)
	for prop in props.of_kind(PropData.Kind.BORDER_STONES):
		if Vector2(prop.tile - at).length() <= 4.0:
			return null # (set already, at an earlier peace)
	for tile: Vector2i in pathfinder.standable_near(at, 8, 3):
		if tile == at or props.has_prop_at(tile):
			continue
		var stones := PropData.new()
		stones.id = ids.next_id()
		stones.kind = PropData.Kind.BORDER_STONES
		stones.tile = tile
		if props.add(stones):
			return stones
	return null


## Debug: someone dies, of `cause`, as anyone dies (see Lifecycle.die). Those
## who knew them keep their ids (lineage outlives people).
func kill_person(person_id: int, cause: StringName = &"debug") -> bool:
	var person := people.get_person(person_id) if is_active else null
	if person == null:
		return false
	Log.info(Log.Category.SIM, "Someone is gone", {"person": person.full_name(), "id": person_id, "cause": cause})
	lifecycle.die(person, cause, clock.tick)
	return true


## Rebuilds the world from saved state: generator output + saved differences.
## Returns false if the state cannot be used (the caller then regenerates).
func _restore_world(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	var world_data: Variant = state.get("world")
	var props_data: Variant = state.get("props")
	var start_data: Variant = state.get("start")
	if typeof(world_data) != TYPE_DICTIONARY or typeof(props_data) != TYPE_DICTIONARY \
			or typeof(start_data) != TYPE_DICTIONARY:
		return false
	var started := Time.get_ticks_msec()
	var restored := WorldData.new()
	var skipped_chunks := restored.from_dict(world_data)
	if skipped_chunks < 0 or restored.bounds.size.x <= 0 or restored.bounds.size.y <= 0:
		return false
	var restored_start := WorldSetup.StartInfo.from_dict(start_data)
	if restored_start == null:
		return false

	var saved_template := StringName(str(state.get("template_id", DEFAULT_TEMPLATE_ID)))
	var saved_generator := int(state.get("generator_version", WorldGenerator.GENERATOR_VERSION))
	if saved_generator != WorldGenerator.GENERATOR_VERSION:
		# Unmodified chunks are regenerated, so a different generator changes them.
		Log.warn(Log.Category.LOAD, "World was created by a different generator version",
			{"saved": saved_generator, "current": WorldGenerator.GENERATOR_VERSION})

	# The generator must use the world's own geometry, not today's config.
	var world_config := Config.world.duplicate() as WorldConfig
	world_config.chunk_size = restored.chunk_size
	world_config.height_step = restored.height_step
	var restored_generator := WorldGenerator.new(world_seed, _load_template(saved_template), world_config)
	restored_generator.keep_made = true # (for the soil: see SoilSystem.bind)
	restored.set_generator(restored_generator)
	var restored_spatial := SpatialIndex.new(SpatialIndex.FINE_CELL_TILES)
	var restored_props := PropRegistry.new(restored.chunk_size, restored_spatial)
	var skipped_props := restored_props.from_dict(props_data)
	if skipped_props < 0:
		return false
	var restored_loose := LooseObjectRegistry.new(restored.chunk_size, restored_spatial)
	var loose_data: Variant = state.get("loose")
	var skipped_loose := 0
	if typeof(loose_data) == TYPE_DICTIONARY: # (always there since save version 3)
		skipped_loose = restored_loose.from_dict(loose_data)
		if skipped_loose < 0:
			return false
	WorldSetup.populate_all(restored, restored_generator, restored_props, restored_loose)

	template_id = saved_template
	world = restored
	generator = restored_generator
	spatial = restored_spatial
	props = restored_props
	loose = restored_loose
	start = restored_start
	if skipped_chunks > 0 or skipped_props > 0 or skipped_loose > 0:
		Log.warn(Log.Category.LOAD, "Some saved world records were unusable and skipped",
			{"chunks": skipped_chunks, "props": skipped_props, "loose": skipped_loose})
	Log.debug(Log.Category.WORLD, "World restored", {
		"ms": Time.get_ticks_msec() - started,
		"modified_chunks": world.modified_chunks().size(),
		"props": props.size(),
	})
	return true


func _load_template(id: StringName) -> StartTemplate:
	var path := "%s%s.tres" % [TEMPLATE_DIR, id]
	var template: StartTemplate = null
	if ResourceLoader.exists(path):
		template = load(path) as StartTemplate
	if template == null:
		Log.error(Log.Category.WORLD, "Start template missing; using defaults", {"path": path})
		template = StartTemplate.new()
	return template


func _activate() -> void:
	water.bind(world, generator)
	water.from_dict(_saved_water)
	_saved_water = {}
	loose_system.bind(world, loose, props, water.current_at)
	interactions.bind(world, props, loose, loose_system, ids, rng)
	var fire_at := Vector2.INF
	if start != null and start.campfire_id != 0:
		fire_at = Vector2(start.settlement_tile) + Vector2(0.5, 0.5)
	interactions.bind_session(water, clock, history, fire_at)
	interactions.bind_people(people)
	interactions.bind_animals(fauna)
	interactions.bind_environment(weather, hydrology, func(tile: Vector2i) -> int:
		return int(generator.sample_tile(tile)["height"]) if generator != null else world.get_height(tile))
	pathfinder.bind(world, props, loose, water)
	movement.bind(people, pathfinder, clock)
	if activities == null:
		activities = ActivityLibrary.load_from()
	var ai := AiContext.new()
	ai.world = world
	ai.props = props
	ai.people = people
	ai.pathfinder = pathfinder
	ai.movement = movement
	ai.clock = clock
	ai.start = start
	ai.occupations = occupations
	ai.activities = activities
	ai.places = Places.new(world, props, people, pathfinder, start)
	if resources == null:
		resources = ResourceLibrary.load_from()
	nodes.bind(props, Config.resources)
	piles.bind(loose, ids, resources, Config.resources)
	ai.nodes = nodes
	ai.piles = piles
	ai.resources = resources
	ai.places.resources = resources
	ai.places.nodes = nodes
	ai.places.waters = fauna.waters
	ai.places.boats = boats
	# The weather: where the save left it (a world from before there was any
	# begins under a clear sky, now).
	var level := world.get_height(start.settlement_tile) if start != null and start.campfire_id != 0 else 0
	weather.bind(clock, Config.climate, world_seed, world, level)
	weather.from_dict(_saved_weather)
	_saved_weather = {}
	# The river stands where the save left it (and goes on with the weather).
	hydrology.bind(world, water, weather, Config.hydrology, world_seed, generator.water_surface_height())
	hydrology.from_dict(_saved_hydrology)
	_saved_hydrology = {}
	water.river_flow = hydrology.flow()
	weather.advance_to(clock.tick)
	pathfinder.set_frozen(weather.frozen, Config.seasons.ice_depth)
	ai.weather = weather
	# What people are to each other: as saved — or, for a new world (or one
	# from before this was kept), what a new band has.
	relationships.bind(people, Config.relationships)
	var unusable_pairs := relationships.from_dict(_saved_relationships)
	if unusable_pairs > 0:
		Log.warn(Log.Category.LOAD, "Some saved relationships were unusable and dropped", {"pairs": unusable_pairs})
	_saved_relationships = {}
	if relationships.size() == 0:
		relationships.seed_from(people, clock.tick)
	ai.relationships = relationships
	ai.places.relationships = relationships
	ai.places.clock = clock
	# Who has died, and who lives with whom: as saved (a world from before
	# they were kept: nobody has died, and households are as people have them).
	var unusable_dead := archive.from_dict(_saved_archive)
	if unusable_dead > 0:
		Log.warn(Log.Category.LOAD, "Some saved records of the dead were unusable and dropped", {"records": unusable_dead})
	_saved_archive = {}
	people.archive = archive
	households.bind(people, start, Config.life)
	households.from_dict(_saved_households)
	households.ensure_records(clock.tick)
	_saved_households = {}
	# Bad water: a puddle, floodwater — not the river's, nor there of old.
	ai.bad_water = func(tile: Vector2i) -> bool:
		return not hydrology.is_river(tile) and float(generator.sample_tile(tile)["water"]) <= 0.0
	farming.bind(world, props, ids, pathfinder, start, people, occupations, generator, world_seed, Config.farming)
	farming.from_dict(_saved_farming)
	_saved_farming = {}
	ai.farming = farming
	# The land's soil and plants go on from where the save left them.
	soil.bind(world, generator, props, weather, hydrology, Config.vegetation, Config.farming)
	if generator != null:
		generator.stop_keeping()
	soil.from_dict(_saved_soil)
	_saved_soil = {}
	vegetation.bind(world, props, nodes, soil, weather, ids, rng.stream(&"vegetation"), clock, Config.vegetation, fire_at)
	vegetation.from_dict(_saved_vegetation)
	_saved_vegetation = {}
	# The powers that have shown themselves — and, for a world from before
	# they were kept, those it has already earned.
	powers.from_dict(_saved_powers)
	_saved_powers = {}
	_powers_looked = -1_000_000
	powers.on_water_touched(history.count(Intervention.TOUCH, &"water"), clock.tick, true)
	powers.on_weather(weather.state, clock.tick, true)
	if events != null and events.count_of(Chronicler.TYPE_STORM) > 0:
		powers.on_weather(WeatherSystem.STORM, clock.tick, true)
	# The animals: those the save has — or, for a world that never had any, its first.
	if species == null:
		species = SpeciesLibrary.load_from()
	animals = AnimalRegistry.new(spatial)
	fauna.waters_current = water.current_at
	fauna.bind(world, props, people, animals, species, ids, start, rng.stream(&"animals"), pathfinder)
	var lost := fauna.from_dict(_saved_animals)
	if lost > 0:
		Log.warn(Log.Category.LOAD, "Some saved animals were unusable and skipped", {"animals": lost})
	_saved_animals = {}
	for animal in animals.all_animals():
		ids.reserve_above(animal.id)
	fauna.seed_world(clock.tick)
	fauna.settlement_people = func(fire: Vector2i) -> int:
		var own := settlements.nearest(fire) if settlements != null else null
		return own.member_count() if own != null else 0
	ai.fauna = fauna
	ai.boats = boats
	settlements.clear()
	settlement = null
	if start != null and start.campfire_id != 0:
		settlement = _make_settlement(start, ai.places, _saved_settlement)
		settlements.add(settlement)
	_saved_settlement = {}
	# The world's history: what the save has of it. (A world from before
	# there was one begins it now: what it has in store is no discovery.)
	if event_defs == null:
		event_defs = EventLibrary.load_from()
	events.bind(clock, event_defs, Config.events)
	var lost_events := events.from_dict(_saved_events)
	if lost_events > 0:
		Log.warn(Log.Category.LOAD, "Some saved events were unusable and skipped", {"events": lost_events})
	# (An older save's everyday events, no longer written down, make room.)
	var everyday := events.drop_uncited([&"food_spoiled", &"building_repaired"])
	if everyday > 0:
		Log.info(Log.Category.LOAD, "Everyday events dropped from history", {"events": everyday})
	chronicle.listening = true
	chronicle.bind(events, people, props, loose, resources, settlement, farming, Config.events)
	chronicle.settlement_names = func(id: int) -> String:
		var own := settlements.get_settlement(id)
		return own.display_name() if own != null else ""
	chronicle.from_dict(_saved_chronicle)
	if bool(_saved_chronicle.get("adopt", false)):
		chronicle.adopt()
	significance.bind(events, people, Config.significance)
	if not stats.from_dict(_saved_stats):
		Log.warn(Log.Category.LOAD, "The saved statistics were unusable; they begin anew")
	_saved_events = {}
	_saved_chronicle = {}
	_saved_stats = {}
	# What is known of the box (M13.4): the land about home from the start.
	knowledge = FogOfKnowledge.new()
	knowledge.bind(world, people)
	knowledge.from_dict(_saved_knowledge)
	knowledge.settle()
	_saved_knowledge = {}
	if start != null:
		knowledge.know_home(start.settlement_tile)
	knowledge.found.connect(_on_region_found)
	knowledge.at_the_edge.connect(func(person_id: int, _tile: Vector2i) -> void:
		var person := people.get_person(person_id)
		var own := settlements.of(person) if person != null else null
		if own != null:
			own.learn(&"the_edge", person_id, clock.tick))
	ai.settlement = settlement
	ai.rng = rng.stream(&"ai")
	ai.story_rng = rng.stream(&"stories")
	ai.world_seed = world_seed
	memories.bind(people)
	var unusable := memories.from_dict(_saved_memories)
	if unusable > 0:
		Log.warn(Log.Category.LOAD, "Some saved memories were unusable and skipped", {"memories": unusable})
	_saved_memories = {}
	ai.memories = memories
	ai.loose = loose
	ai.places.memories = memories
	var unreadable := day_log.from_dict(_saved_day_log)
	if unreadable > 0:
		Log.warn(Log.Category.LOAD, "Some saved day-log entries were unusable and skipped", {"entries": unreadable})
	_saved_day_log = {}
	ai.day_log = day_log
	# Lives go on from where the save left them.
	lifecycle.bind(people, archive, households, clock.tick, Config.life)
	lifecycle.from_dict(_saved_lifecycle)
	_saved_lifecycle = {}
	lifecycle.relationships = relationships
	lifecycle.memories = memories
	lifecycle.day_log = day_log
	lifecycle.settlement = settlement
	lifecycle.occupations = occupations
	lifecycle.names = names
	lifecycle.ids = ids
	lifecycle.rng = rng.stream(&"life")
	lifecycle.clock = clock
	lifecycle.pathfinder = pathfinder
	lifecycle.start = start
	lifecycle.events = events
	graves.bind(props, world, pathfinder, start, ids, archive, loose)
	graves.starts = func() -> Array:
		var out: Array = []
		for own in settlements.all():
			out.append(own.start_info())
		return out
	# (An older save's graves, one each: gathered into cemeteries.)
	var gathered := graves.gather_old()
	if gathered > 0:
		Log.info(Log.Category.LOAD, "Graves gathered into cemeteries", {"graves": gathered})
	# (An older save's cemetery with something built on or against it: moved.)
	var cleared := graves.clear_plots()
	if cleared > 0:
		Log.info(Log.Category.LOAD, "Cemeteries moved off built ground", {"cemeteries": cleared})
	# (Nothing wild grows inside a cemetery's fence: the owner, 2026-10-06.)
	var wild := graves.clear_wild()
	if wild > 0:
		Log.info(Log.Category.LOAD, "Wild plants taken off cemetery plots", {"plants": wild})
	lifecycle.graves = graves if start != null and start.campfire_id != 0 else null
	ai.lifecycle = lifecycle
	# What settlements remember together, as saved.
	culture.bind(people, memories, clock.tick, Config.memory)
	var unusable_culture := culture.from_dict(_saved_culture)
	if unusable_culture > 0:
		Log.warn(Log.Category.LOAD, "Some saved cultural memories were unusable and dropped", {"records": unusable_culture})
	_saved_culture = {}
	ai.culture = culture
	# What is being built, as saved; what the settlement plans.
	if buildings == null:
		buildings = BuildingLibrary.load_from()
	construction.bind(props, ids, buildings, start, people, clock.tick, Config.construction)
	var unusable_projects := construction.from_dict(_saved_construction)
	if unusable_projects > 0:
		Log.warn(Log.Category.LOAD, "Some saved building projects were unusable and dropped", {"projects": unusable_projects})
	_saved_construction = {}
	traffic.bind(world, props, clock.tick, Config.construction)
	traffic.paving = func() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		for own in settlements.all():
			if own.knows_how(&"engineering") and own.fire() != null:
				out.append(own.fire().tile)
		return out
	traffic.from_dict(_saved_traffic)
	_saved_traffic = {}
	# The disasters: one may be going on, or the world resting after one.
	disasters.bind(self)
	disasters.from_dict(_saved_disasters)
	_saved_disasters = {}
	interactions.disasters = disasters
	ai.water_withheld = disasters.water_is_blood
	# Old stones to take: what fell, not what was there of old or a mystery's.
	ai.is_rubble = func(prop: PropData) -> bool:
		return prop != null and prop.kind == PropData.Kind.RUIN and (start == null or prop.id != start.ruin_id) and not mysteries.lies_at(prop.tile)
	movement.traffic = traffic
	planner.bind(settlement, construction, people, world, pathfinder, clock.tick, Config.construction, households, traffic)
	planner.from_dict(_saved_planner)
	_saved_planner = {}
	if settlement != null:
		settlement.construction = construction
		settlement.planner = planner
	# The settlements founded since (M12.3), as saved.
	for saved: Variant in _saved_settlements:
		if typeof(saved) == TYPE_DICTIONARY:
			found_from_save(saved)
	_saved_settlements = []
	construction.settlements = settlements
	households.settlements = settlements
	lifecycle.settlements = settlements
	lifecycle.migration = migration
	lifecycle.trade = trade
	ai.settlements = settlements
	_place_settlements()
	migration.bind(clock.tick, Config.migration)
	migration.from_dict(_saved_migration)
	_saved_migration = {}
	migration.settlements = settlements
	migration.people = people
	migration.households = households
	migration.relationships = relationships
	migration.props = props
	migration.world = world
	migration.pathfinder = pathfinder
	migration.ids = ids
	migration.events = events
	migration.behavior = behavior
	migration.rng = rng.stream(&"migration")
	migration.add_settlement = func(info: WorldSetup.StartInfo) -> Settlement: return add_settlement(info)
	ai.migration = migration
	interactions.settlements = settlements
	trade.bind(clock.tick, Config.trade)
	trade.from_dict(_saved_trade)
	_saved_trade = {}
	trade.settlements = settlements
	trade.resources = resources
	trade.pathfinder = pathfinder
	governance.bind(clock.tick, Config.governance)
	governance.settlements = settlements
	governance.people = people
	governance.relationships = relationships
	governance.significance = significance
	governance.from_dict(_saved_governance)
	_saved_governance = {}
	learning.bind(people, settlements, clock.tick)
	learning.from_dict(_saved_learning)
	_saved_learning = {}
	if technologies == null:
		technologies = TechnologyLibrary.load_from()
		for problem in technologies.problems:
			Log.warn(Log.Category.WORLD, "Technology definitions", {"problem": problem})
	technology.world = world
	technology.props = props
	technology.buildings = buildings
	technology.trade = trade
	technology.bind(technologies, settlements, learning, clock.tick)
	technology.from_dict(_saved_technology)
	_saved_technology = {}
	cultures.bind(settlements, culture, events, world_seed, clock.tick)
	cultures.from_dict(_saved_cultures)
	_saved_cultures = {}
	faith.bind(culture, settlements, people, world, clock.tick)
	faith.significance = significance
	faith.from_dict(_saved_faith)
	_saved_faith = {}
	lexicon.bind(settlements, culture, world_seed, clock.tick)
	lexicon.from_dict(_saved_lexicon)
	_saved_lexicon = {}
	lexicon.edge_known = func() -> bool: return knowledge != null and knowledge.edge_reached
	lexicon.regions_of = func(_own: Settlement) -> Array[String]:
		var kinds: Array[String] = []
		if knowledge != null:
			for region in knowledge.found_regions():
				var kind: String = ["water", "hills", "lowland"][region.kind]
				if not kinds.has(kind):
					kinds.append(kind)
		return kinds
	anomaly_archive.bind(settlements, weather, clock.tick)
	anomaly_archive.from_dict(_saved_archive_m18)
	_saved_archive_m18 = {}
	ai.archive = anomaly_archive
	science.bind(anomaly_archive, settlements, clock.tick)
	science.from_dict(_saved_science)
	_saved_science = {}
	science.edge_known = func() -> bool: return knowledge != null and knowledge.edge_reached
	if mysteries.defs.is_empty():
		mysteries.load_defs()
	mysteries.bind(world, props, people, settlements, events, ids, world_seed, clock.tick)
	mysteries.from_dict(_saved_mysteries)
	_saved_mysteries = {}
	mysteries.has_scholar = func(own: Settlement) -> bool: return science.investigator(own)[0] != null
	mysteries.edge_known = science.edge_known
	if start != null:
		mysteries.place_all(start.settlement_tile)
	conflicts.bind(settlements, governance, cultures, lexicon, trade, clock.tick)
	conflicts.from_dict(_saved_conflicts)
	_saved_conflicts = {}
	stories.bind(events, people, clock.tick)
	stories.from_dict(_saved_stories)
	_saved_stories = {}
	stories.significance = significance
	stories.historian = func() -> int:
		for own in settlements.all():
			if own.knows_how(&"writing"):
				var who: Array = science.investigator(own)
				if who[0] != null:
					return (who[0] as PersonData).id
		return 0
	conflicts.kill = func(person_id: int, cause: StringName, causes: Array) -> void:
		var person := people.get_person(person_id)
		if person != null:
			lifecycle.die(person, cause, clock.tick, causes)
	conflicts.shortage_event = func(settlement_id: int) -> int:
		var found := events.of_type(&"food_shortage")
		for n in range(found.size() - 1, -1, -1):
			if found[n].settlement_id == settlement_id or (settlement_id == (settlement.id if settlement != null else 0) and found[n].settlement_id == 0):
				return found[n].id
		return 0
	EventText.glossary = func(settlement_id: int, subject: StringName) -> String:
		var concept := Lexicon.concept_of_myth(subject)
		return lexicon.gloss(settlement_id, concept) if concept != &"" and lexicon.word(settlement_id, concept) != "" else ""
	for own in settlements.all():
		if own.planner != null:
			own.planner.faith = faith
	ai.cultures = cultures
	construction.style_of = func(settlement_id: int) -> int: return cultures.architecture_of(settlements.get_settlement(settlement_id))
	ai.governance = governance
	interactions.governance = governance
	for own in settlements.all():
		own.governance = governance
	ai.trade = trade
	_apply_storehouses()
	_bind_boats()
	ai.construction = construction
	interactions.construction = construction
	ai.planner = planner
	ai.traffic = traffic
	interactions.traffic = traffic
	ai.next_stimulus_id = maxi(int(_saved_perception.get("next_stimulus_id", 1)), 1)
	_saved_perception = {}
	behavior.bind(ai)
	predators.bind(clock.tick)
	predators.fauna = fauna
	predators.people = people
	predators.behavior = behavior
	predators.settlements = settlements
	predators.props = props
	predators.day_log = day_log
	predators.rng = rng.stream(&"predators")
	predators.kill = func(person: PersonData, cause: StringName) -> void:
		# (After the turn being lived: nobody dies in the middle of a step.)
		(func() -> void:
			if is_active and people.has_person(person.id):
				lifecycle.die(person, cause, clock.tick)).call_deferred()
	predators.from_dict(_saved_predators)
	_saved_predators = {}
	parties.bind(clock.tick)
	parties.fauna = fauna
	parties.people = people
	parties.behavior = behavior
	parties.settlements = settlements
	parties.watch = predators
	parties.day_log = day_log
	parties.rng = rng.stream(&"hunting_parties")
	parties.kill = predators.kill
	parties.piles = piles
	var remember := func(person: PersonData, subject: StringName, importance: float) -> void:
		lifecycle.remember_life(person, subject, clock.tick, importance)
	parties.remember = remember
	predators.remember = remember
	parties.from_dict(_saved_parties)
	_saved_parties = {}
	assemblies.bind(clock.tick)
	assemblies.people = people
	assemblies.behavior = behavior
	assemblies.settlements = settlements
	assemblies.governance = governance
	assemblies.pathfinder = pathfinder
	assemblies.from_dict(_saved_assemblies)
	_saved_assemblies = {}
	raids.bind(clock.tick)
	raids.people = people
	raids.behavior = behavior
	raids.settlements = settlements
	raids.governance = governance
	raids.rng = rng.stream(&"raids")
	raids.from_dict(_saved_raids)
	_saved_raids = {}
	# (Raids are walked while the box is watched; away, they are made at once: M20.)
	conflicts.walk_raid = func(raider: int, victim: int, leader: int, causes: Array) -> bool:
		return walking_raids and raids.queue(raider, victim, leader, causes, clock.tick)
	wars.bind(clock.tick)
	Signs.reset_rates()
	wars.people = people
	wars.behavior = behavior
	wars.settlements = settlements
	wars.pathfinder = pathfinder
	wars.rng = rng.stream(&"wars")
	wars.from_dict(_saved_wars)
	_saved_wars = {}
	# (Battles too: fought in the open while watched, at once away — FC6.)
	conflicts.walk_battle = func(a: int, b: int, fallen: Array, heroes: Array) -> bool:
		return walking_raids and wars.queue(a, b, fallen, heroes, clock.tick)
	perception.bind(ai)
	behavior.from_dict(_saved_behavior)
	_saved_behavior = {}
	simulation.tiers.low_end = GraphicsQuality.current() == GraphicsQuality.Level.LOW
	simulation.bind(clock, people, behavior, pathfinder, movement)
	clock.speed_changed.connect(_on_speed_changed)
	clock.day_started.connect(_on_day_started)
	clock.season_changed.connect(_on_season_changed)
	clock.year_started.connect(_on_year_started)
	_apply_pause()
	is_active = true
	EventBus.world_loaded.emit(world_id)


func _on_speed_changed(speed_index: int) -> void:
	_apply_pause()
	EventBus.sim_speed_changed.emit(speed_index)


## Paused, the whole world stands still — also what falls and what flows
## (bible §9.2). The UI, the camera and looking at things go on.
func _apply_pause() -> void:
	loose_system.frozen = clock.is_paused()
	water.frozen = clock.is_paused()


func _on_day_started(day: int) -> void:
	EventBus.day_started.emit(day)
	_let_nuts_fall()
	if not unfold_pending and unfolder.due(world, settlements, people.size(), clock.tick):
		unfold_pending = true


## In autumn the broadleaf trees near a settlement let their nuts fall, a
## few a day, until there are enough lying under them to gather (the owner,
## 2026-10-06): food that keeps through the winter.
const NUTS_LYING_MOST := 24
const NUTS_A_DAY := 6


func _let_nuts_fall() -> void:
	if not is_active or settlements == null or interactions == null or Config.time.season_of(clock.tick) != Seasons.AUTUMN:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, clock.tick, "nuts"])
	for own in settlements.all():
		var fire := own.fire()
		if fire == null:
			continue
		var center := fire.position2d()
		var lying := 0
		for object in loose.all_objects():
			if object.kind == LooseObject.Kind.FRUIT and object.resource == &"nuts" and object.position.distance_to(center) <= Places.WORK_RADIUS:
				lying += 1
		if lying >= NUTS_LYING_MOST:
			continue
		var trees: Array[PropData] = []
		for prop in props.of_kind(PropData.Kind.TREE):
			if prop.kind == PropData.Kind.TREE and not prop.felled and not prop.is_conifer() \
					and prop.position2d().distance_to(center) <= Places.WORK_RADIUS:
				trees.append(prop)
		if trees.is_empty():
			continue
		for n in mini(NUTS_A_DAY, NUTS_LYING_MOST - lying):
			var tree := trees[rng.randi_range(0, trees.size() - 1)]
			var under := tree.position2d() + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.3, 0.8)
			interactions.drop_nut(under)


func _on_season_changed(season: int, year: int) -> void:
	Log.info(Log.Category.WORLD, "A new season", {"season": GameClock.season_name(season), "year": year})
	EventBus.season_changed.emit(season, year)


func _on_year_started(year: int) -> void:
	EventBus.year_started.emit(year)


## What the storehouses and woodsheds that stand add to the room in the
## stores (each settlement's own: those near its fire); the food goes into
## the storehouse nearest the fire, the materials into the nearest woodshed.
func _apply_storehouses() -> void:
	if settlement == null or construction == null or buildings == null:
		return
	for own in settlements.all():
		var stores := _standing_near(own, PropData.Kind.STOREHOUSE)
		var sheds := _standing_near(own, PropData.Kind.WOODSHED)
		own.stockpile.extra_room = _room_in(own, PropData.Kind.STOREHOUSE, stores.size())
		own.stockpile.extra_material_room = _room_in(own, PropData.Kind.WOODSHED, sheds.size())
		own.keep_in(_nearest_fire(own, stores), _nearest_fire(own, sheds))


func _standing_near(own: Settlement, kind: int) -> Array[int]:
	return own.planner.standing_near(kind) if own.planner != null else construction.standing(kind)


## What `count` buildings of `kind` hold for the settlement.
func _room_in(own: Settlement, kind: int, count: int) -> int:
	var def := buildings.of_kind(kind)
	var room := count * (def.capacity if def != null else 0)
	# Pots hold more than baskets; what is counted is packed tighter (M16.3).
	if own.knows_how(&"pottery"):
		room = roundi(room * POTTERY_ROOM)
	if own.knows_how(&"mathematics"):
		room = roundi(room * COUNTED_ROOM)
	return room


## Of the buildings `ids`, the one nearest the settlement's fire (0: none).
func _nearest_fire(own: Settlement, ids: Array[int]) -> int:
	var fire := own.fire()
	var nearest := 0
	var best := INF
	for id in ids:
		var distance := Vector2(own.props().get_prop(id).tile - fire.tile).length() if fire != null else 0.0
		if distance < best:
			nearest = id
			best = distance
	return nearest


## A settlement around a fire: its stores, its jobs; told to the chronicle.
func _make_settlement(info: WorldSetup.StartInfo, its_places: Places, saved: Dictionary) -> Settlement:
	var own := Settlement.new()
	own.bind(info, people, props, piles, its_places, resources, loose, Config.settlement)
	own.farming = farming
	own.weather = weather
	own.hydrology = hydrology
	own.world = world
	own.pathfinder = pathfinder
	own.occupations = occupations
	own.fauna = fauna
	own.nodes = nodes
	own.from_dict(saved)
	if farming != null:
		farming.use_start(info)
	own.jobs.refresh(own, clock.tick)
	own.shortage_changed.connect(chronicle.on_shortage_changed)
	own.seed_released.connect(chronicle.on_seed_released)
	own.forage_changed.connect(chronicle.on_forage_changed)
	own.fire_changed.connect(chronicle.on_fire_changed)
	own.spoiled.connect(func(_resource: StringName, amount: int) -> void:
		if amount > 0 and learning != null:
			learning.learn_from(&"food_spoiled", own.id))
	own.took_up.connect(chronicle.on_took_up)
	own.flood_took.connect(chronicle.on_flood_took)
	own.home_moved.connect(chronicle.on_home_moved)
	own.learned.connect(chronicle.on_learned)
	# Something new is known: what it changes, at once (M16.3).
	own.learned.connect(func(_person_id: int, _what: StringName) -> void:
		_apply_storehouses()
		technology.apply_effects())
	own.trade = trade
	own.governance = governance
	return own


## A settlement founded since the first (M12.3): its places, stores, jobs and
## planner, all bound like the first's. `saved`: {"start", "settlement", "planner"}.
## Returns it (null: the saved record was unusable).
func found_from_save(saved: Dictionary) -> Settlement:
	var info := WorldSetup.StartInfo.from_dict(saved.get("start", {}) if typeof(saved.get("start")) == TYPE_DICTIONARY else {})
	if info == null or info.settlement_id == 0 or props.get_prop(info.campfire_id) == null \
			or settlements.get_settlement(info.settlement_id) != null:
		Log.warn(Log.Category.LOAD, "A saved settlement was unusable and dropped", {"settlement": saved.get("start", {})})
		return null
	return add_settlement(info, saved.get("settlement", {}) if typeof(saved.get("settlement")) == TYPE_DICTIONARY else {},
		saved.get("planner", {}) if typeof(saved.get("planner")) == TYPE_DICTIONARY else {})


## Adds a settlement (founded now, or as saved) with everything it needs.
func add_settlement(info: WorldSetup.StartInfo, saved: Dictionary = {}, saved_planner: Dictionary = {}) -> Settlement:
	var first_places := settlement.places() if settlement != null else null
	var its_places := Places.new(world, props, people, pathfinder, info)
	its_places.resources = resources
	its_places.nodes = nodes
	its_places.waters = fauna.waters
	its_places.boats = boats
	its_places.relationships = relationships
	its_places.clock = clock
	its_places.memories = memories
	if first_places != null:
		its_places.share_visited(first_places)
	var own := _make_settlement(info, its_places, saved)
	own.construction = construction
	own.planner = SettlementPlanner.new()
	own.planner.faith = faith
	own.planner.bind(own, construction, people, world, pathfinder, clock.tick, Config.construction, households, traffic)
	own.planner.from_dict(saved_planner)
	settlements.add(own)
	_place_settlements()
	_apply_storehouses()
	return own


## The tools in every settlement's stores (M12.4: the first "tools" statistic).
func _tools_in_store() -> int:
	var count := 0
	for own in settlements.all():
		count += own.stockpile.amount(&"tools")
	return count


## Everything that needs to know where all the settlements are.
func _place_settlements() -> void:
	fauna.settlement_tiles = settlements.fire_tiles()


func _settlements_to_save() -> Array:
	var out: Array = []
	for own in settlements.all():
		if own == settlement:
			continue
		out.append({"start": own.start_info().to_dict(), "settlement": own.to_dict(),
			"planner": own.planner.to_dict() if own.planner != null else {}})
	return out


## Unique even when two worlds share a seed.
static func _make_world_id(seed_value: int, unix_time: int) -> String:
	var salt := RngStreams.fnv1a_32("%d:%d:%d" % [seed_value, unix_time, Time.get_ticks_usec()])
	return "w%d_%08x" % [unix_time, salt]
