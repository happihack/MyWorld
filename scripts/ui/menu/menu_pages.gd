class_name MenuPages
extends RefCounted
## The ☰ menu's tree and its pages (M14, bible §26.5): the sections and what
## is in them — each entry shown only once what it tells of exists (the menu
## grows with the world: hidden, never greyed) — and the pages M14 adds.
## MainMenu is the panel they are drawn in (its building blocks: heading,
## line, entry, chips, detail…).

const OVERVIEW := &"overview"
const ENVIRONMENT := &"environment"
const RESOURCES := &"resources"
const POPULATION := &"population"
const OCCUPATIONS := &"occupations"
const SETTLEMENTS := &"settlements"
const BUILDINGS := &"buildings"
const ECONOMY := &"economy"
const AGRICULTURE := &"agriculture"
const GOVERNMENT := &"government"
const BELIEFS := &"beliefs"
const TECHNOLOGY := &"technology"
const CULTURE := &"culture"
const BOX_KNOWLEDGE := &"box_knowledge"
const STORIES := &"stories"
const DISCOVERIES := &"discoveries"
const SEEN := &"seen"
const GRAPHICS := &"graphics"
const SPEED := &"speed"
const ACCESSIBILITY := &"accessibility"
const NOTIFICATIONS := &"notifications"
const ADVANCED := &"advanced"
const DEBUG := &"debug"

const GRAPHICS_LEVELS: Array[String] = ["auto", "low", "medium", "high"]
const FPS_CAPS: Array[int] = [30, 60]
## How the list of individuals is ordered and whom it shows (M14).
const SORTS: Array[StringName] = [&"name", &"age", &"work"]
const STAGES: Array[StringName] = [&"all", &"children", &"adults", &"elders"]


## The menu's sections, each with what is in it now: [[title key, [[text key,
## Callable], …]], …] — sections with nothing in them are left out.
static func sections(menu: MainMenu) -> Array:
	var s := menu.session()
	var out: Array = []
	var world: Array = []
	world.append(["MENU_LOCATE", func() -> void: menu.open_page(MainMenu.PAGE_LOCATE)])
	world.append(["MENU_MAP", func() -> void: menu.map_requested.emit()])
	world.append(["MENU_OVERVIEW", func() -> void: menu.open_page(OVERVIEW)])
	if s.knowledge != null and not s.knowledge.found_regions().is_empty():
		world.append(["MENU_REGIONS", func() -> void: menu.open_page(MainMenu.PAGE_REGIONS)])
	if s.weather != null:
		world.append(["MENU_WEATHER", func() -> void: menu.open_page(MainMenu.PAGE_WEATHER)])
	world.append(["MENU_ENVIRONMENT", func() -> void: menu.open_page(ENVIRONMENT)])
	world.append(["MENU_RESOURCES", func() -> void: menu.open_page(RESOURCES)])
	out.append(["MENU_WORLD", world])
	var people: Array = []
	people.append(["MENU_POPULATION", func() -> void: menu.open_page(POPULATION)])
	people.append(["MENU_INDIVIDUALS", func() -> void: menu.open_page(MainMenu.PAGE_INDIVIDUALS)])
	if not FamilyTree.families(s).is_empty():
		people.append(["MENU_FAMILIES", func() -> void: menu.open_page(MainMenu.PAGE_FAMILIES)])
	if _anyone_working(s):
		people.append(["MENU_OCCUPATIONS", func() -> void: menu.open_page(OCCUPATIONS)])
	if s.relationships != null:
		people.append(["MENU_RELATIONSHIPS", func() -> void: menu.open_page(MainMenu.PAGE_RELATIONSHIPS)])
	people.append(["MENU_IMPORTANT", func() -> void: menu.open_page(MainMenu.PAGE_IMPORTANT)])
	out.append(["MENU_PEOPLE", people])
	var civ: Array = []
	civ.append(["MENU_SETTLEMENTS", func() -> void: menu.open_page(SETTLEMENTS)])
	civ.append(["MENU_BUILDINGS", func() -> void: menu.open_page(BUILDINGS)])
	if s.trade != null and (s.trade.trips > 0 or s.settlements.size() > 1):
		civ.append(["MENU_ECONOMY", func() -> void: menu.open_page(ECONOMY)])
	if s.farming != null and not s.farming.crops().is_empty():
		civ.append(["MENU_AGRICULTURE", func() -> void: menu.open_page(AGRICULTURE)])
	if _anyone_leads(s):
		civ.append(["MENU_GOVERNMENT", func() -> void: menu.open_page(GOVERNMENT)])
	if _beyond_the_beginning(s):
		civ.append(["MENU_TECHNOLOGY", func() -> void: menu.open_page(TECHNOLOGY)])
	civ.append(["MENU_CULTURE", func() -> void: menu.open_page(CULTURE)])
	if not beliefs(s).is_empty():
		civ.append(["MENU_BELIEFS", func() -> void: menu.open_page(BELIEFS)])
	out.append(["MENU_CIVILIZATION", civ])
	var history: Array = []
	history.append(["MENU_TIMELINE", func() -> void: menu.timeline_requested.emit()])
	if _any_event(s, func(e: WorldEvent) -> bool: return TimelineModel.passes(e, TimelineModel.FILTER_MAJOR)):
		history.append(["MENU_MAJOR_EVENTS", func() -> void: menu.timeline_filter_requested.emit(TimelineModel.FILTER_MAJOR)])
	if not discoveries(s).is_empty():
		history.append(["MENU_DISCOVERIES", func() -> void: menu.open_page(DISCOVERIES)])
	if _any_event(s, func(e: WorldEvent) -> bool: return TimelineModel.passes(e, TimelineModel.FILTER_DISASTERS)):
		history.append(["MENU_DISASTERS", func() -> void: menu.timeline_filter_requested.emit(TimelineModel.FILTER_DISASTERS)])
	if s.stories != null and (not s.stories.stories.is_empty() or s.events.count_of(&"era_entered") > 0):
		history.append(["MENU_STORIES", func() -> void: menu.open_page(STORIES)])
	history.append(["MENU_IMPORTANT", func() -> void: menu.open_page(MainMenu.PAGE_IMPORTANT)])
	history.append(["MENU_FIRSTS", func() -> void: menu.open_page(MainMenu.PAGE_FIRSTS)])
	out.append(["MENU_HISTORY", history])
	var player: Array = []
	player.append(["MENU_INTERACTIONS", func() -> void: menu.history_requested.emit()])
	player.append(["MENU_STATISTICS", func() -> void: menu.statistics_requested.emit()])
	if s.anomaly_archive != null and not s.anomaly_archive.anomalies.is_empty():
		player.append(["MENU_BOX_KNOWLEDGE", func() -> void: menu.open_page(BOX_KNOWLEDGE)])
	if s.knowledge != null:
		player.append(["MENU_SEEN", func() -> void: menu.open_page(SEEN)])
	out.append(["MENU_PLAYER", player])
	var settings: Array = []
	settings.append(["MENU_AUDIO", func() -> void: menu.open_page(MainMenu.PAGE_AUDIO)])
	settings.append(["MENU_HAPTICS", func() -> void: menu.open_page(MainMenu.PAGE_HAPTICS)])
	if SensorManager.feature_enabled():
		settings.append(["MENU_MOTION", func() -> void: menu.motion_requested.emit()])
	settings.append(["MENU_GRAPHICS", func() -> void: menu.open_page(GRAPHICS)])
	settings.append(["MENU_SPEED", func() -> void: menu.open_page(SPEED)])
	settings.append(["MENU_ACCESSIBILITY", func() -> void: menu.open_page(ACCESSIBILITY)])
	settings.append(["MENU_NOTIFICATIONS", func() -> void: menu.open_page(NOTIFICATIONS)])
	settings.append(["MENU_SAVE", func() -> void: menu.open_page(MainMenu.PAGE_SAVE)])
	settings.append(["MENU_ADVANCED", func() -> void: menu.open_page(ADVANCED)])
	if bool(Settings.get_value(&"debug/enabled")):
		settings.append(["MENU_DEBUG", func() -> void: menu.open_page(DEBUG)])
	out.append(["MENU_SETTINGS", settings])
	return out.filter(func(section: Array) -> bool: return not (section[1] as Array).is_empty())


## Draws a page M14 adds; false if `page` is not one of them.
static func build(menu: MainMenu, page: StringName, entry: Array) -> bool:
	var s := menu.session()
	match page:
		OVERVIEW:
			menu.set_title(MemoryText.translate("MENU_OVERVIEW"))
			for text in overview_lines(s):
				menu.add_line(text)
			menu.add_entry(MemoryText.translate("MENU_COPY_SEED"), func() -> void: copy_seed(s))
		ENVIRONMENT:
			menu.set_title(MemoryText.translate("MENU_ENVIRONMENT"))
			for text in environment_lines(s):
				menu.add_line(text)
		RESOURCES:
			menu.set_title(MemoryText.translate("MENU_RESOURCES"))
			for own in s.settlements.all():
				menu.add_detail(own.display_name(), stores_lines(own), Vector2.INF)
			menu.add_heading(MemoryText.translate("RES_IN_THE_WORLD"))
			for text in world_resource_lines(s):
				menu.add_line(text)
		POPULATION:
			menu.set_title(MemoryText.translate("MENU_POPULATION"))
			for text in population_lines(s):
				menu.add_line(text)
			for row: Array in oldest_and_youngest(s):
				var id: int = row[0]
				menu.add_entry(row[1], func() -> void: menu.person_chosen.emit(id))
		OCCUPATIONS:
			menu.set_title(MemoryText.translate("MENU_OCCUPATIONS"))
			if occupations(s).is_empty():
				menu.add_line(MemoryText.translate("MENU_NOTHING_RECORDED"))
			for row: Array in occupations(s):
				menu.add_heading(row[0])
				for person: Array in row[1]:
					var id: int = person[0]
					menu.add_entry(person[1], func() -> void: menu.person_chosen.emit(id))
		SETTLEMENTS:
			menu.set_title(MemoryText.translate("MENU_SETTLEMENTS"))
			for row: Array in settlements(s):
				menu.add_detail(row[0], row[1], row[2])
		BUILDINGS:
			menu.set_title(MemoryText.translate("MENU_BUILDINGS"))
			for row: Array in buildings(s):
				menu.add_detail(row[0], row[1], row[2])
		ECONOMY:
			menu.set_title(MemoryText.translate("MENU_ECONOMY"))
			for text in economy_lines(s):
				menu.add_line(text)
		TECHNOLOGY:
			menu.set_title(MemoryText.translate("MENU_TECHNOLOGY"))
			var told := technology(s)
			menu.add_line(told["age"])
			menu.add_heading(MemoryText.translate("TECH_KNOWN"))
			for text: String in told["known"]:
				menu.add_line(text)
			if not (told["close"] as PackedStringArray).is_empty():
				menu.add_heading(MemoryText.translate("TECH_CLOSE"))
				for text: String in told["close"]:
					menu.add_line(text)
		AGRICULTURE:
			menu.set_title(MemoryText.translate("MENU_AGRICULTURE"))
			for text in agriculture_lines(s):
				menu.add_line(text)
		GOVERNMENT:
			menu.set_title(MemoryText.translate("MENU_GOVERNMENT"))
			if government(s).is_empty():
				menu.add_line(MemoryText.translate("MENU_NOTHING_RECORDED"))
			for row: Array in government(s):
				var id: int = row[0]
				menu.add_entry(row[1], func() -> void: menu.person_chosen.emit(id))
		STORIES:
			menu.set_title(MemoryText.translate("MENU_STORIES"))
			var eras := s.events.of_type(&"era_entered")
			if not eras.is_empty():
				menu.add_heading(MemoryText.translate("STORIES_ERAS"))
				for e in eras:
					menu.add_line(EventText.line(e, s.people, s.events))
			menu.add_heading(MemoryText.translate("STORIES_TOLD"))
			if s.stories.stories.is_empty():
				menu.add_line(MemoryText.translate("MENU_NOTHING_RECORDED"))
			var told: Array = s.stories.stories.duplicate()
			told.reverse()
			menu.add_paged(told, func(story: Variant) -> void: menu.add_line(s.stories.line(story)))
		BOX_KNOWLEDGE:
			menu.set_title(MemoryText.translate("MENU_BOX_KNOWLEDGE"))
			var told := box_knowledge(s)
			for text: String in told["state"]:
				menu.add_line(text)
			if not (told["hypotheses"] as PackedStringArray).is_empty():
				menu.add_heading(MemoryText.translate("BOX_HYPOTHESES"))
				for text: String in told["hypotheses"]:
					menu.add_line(text)
			if not (told["clues"] as PackedStringArray).is_empty():
				menu.add_heading(MemoryText.translate("BOX_CLUES"))
				for text: String in told["clues"]:
					menu.add_small(text)
		CULTURE:
			menu.set_title(MemoryText.translate("MENU_CULTURE"))
			for own in s.settlements.all():
				menu.add_detail(own.display_name(), culture_lines(s, own), Vector2.INF)
		BELIEFS:
			menu.set_title(MemoryText.translate("MENU_BELIEFS"))
			for own in s.settlements.all():
				var held := faith_lines(s, own)
				if not held.is_empty():
					menu.add_detail(own.display_name(), held, Vector2.INF)
			for text in beliefs(s):
				menu.add_small(text)
			if beliefs(s).is_empty():
				menu.add_line(MemoryText.translate("MENU_NOTHING_RECORDED"))
		DISCOVERIES:
			menu.set_title(MemoryText.translate("MENU_DISCOVERIES"))
			if discoveries(s).is_empty():
				menu.add_line(MemoryText.translate("MENU_NOTHING_RECORDED"))
			for row: Array in discoveries(s):
				var at: Vector2 = row[1]
				if at == Vector2.INF:
					menu.add_small(row[0])
				else:
					menu.add_entry(row[0], func() -> void: menu.place_chosen.emit(at))
		SEEN:
			menu.set_title(MemoryText.translate("MENU_SEEN"))
			menu.add_line(MemoryText.translate("SEEN_SHARE").format({"share": roundi(seen_share(s) * 100.0)}))
			menu.add_small(MemoryText.translate("SEEN_ABOUT"))
		GRAPHICS:
			menu.set_title(MemoryText.translate("MENU_GRAPHICS"))
			menu.add_heading(MemoryText.translate("GRAPHICS_QUALITY"))
			var levels: Array = []
			for level in GRAPHICS_LEVELS:
				levels.append([MemoryText.translate("GRAPHICS_" + level.to_upper()), level])
			menu.add_chips(levels, String(Settings.get_value(&"graphics/quality")), func(value: Variant) -> void:
				Settings.set_value(&"graphics/quality", String(value)))
			menu.add_heading(MemoryText.translate("GRAPHICS_FPS"))
			var caps: Array = []
			for cap in FPS_CAPS:
				caps.append([str(cap), cap])
			menu.add_chips(caps, int(Settings.get_value(&"graphics/fps_cap")), func(value: Variant) -> void:
				Settings.set_value(&"graphics/fps_cap", int(value)))
		SPEED:
			menu.set_title(MemoryText.translate("MENU_SPEED"))
			var speeds: Array = []
			for i in 4:
				speeds.append([MemoryText.translate("SPEED_%d" % i), i])
			menu.add_chips(speeds, s.clock.speed_index, func(value: Variant) -> void: s.clock.set_speed(int(value)))
			menu.add_small(MemoryText.translate("SPEED_ABOUT"))
			# While the player is away (M20): the world goes on — or rests.
			menu.add_toggle(&"gameplay/world_rests", "SPEED_WORLD_RESTS")
			menu.add_small(MemoryText.translate("SPEED_WORLD_RESTS_ABOUT"))
		ACCESSIBILITY:
			menu.set_title(MemoryText.translate("MENU_ACCESSIBILITY"))
			menu.add_toggle(&"accessibility/reduced_motion", "ACCESS_REDUCED_MOTION")
			menu.add_toggle(&"camera/twist_rotate", "ACCESS_TWIST")
		NOTIFICATIONS:
			menu.set_title(MemoryText.translate("MENU_NOTIFICATIONS"))
			menu.add_toggle(&"notifications/toasts", "NOTICE_TOASTS")
			menu.add_small(MemoryText.translate("NOTICE_ABOUT"))
		ADVANCED:
			menu.set_title(MemoryText.translate("MENU_ADVANCED"))
			menu.add_line(MemoryText.translate("ADV_SEED").format({"seed": s.world_seed}))
			menu.add_entry(MemoryText.translate("MENU_COPY_SEED"), func() -> void: copy_seed(s))
			menu.add_small(MemoryText.translate("ADV_WORLD").format({"id": s.world_id}))
			menu.add_small(MemoryText.translate("ADV_VERSION").format({"version": ProjectSettings.get_setting("application/config/version", "?"),
				"save": SaveManager.SAVE_VERSION}))
		DEBUG:
			menu.set_title(MemoryText.translate("MENU_DEBUG"))
			menu.add_toggle(&"debug/overlay_visible", "DEBUG_OVERLAY")
			menu.add_entry(MemoryText.translate("DEBUG_BENCHMARK"), func() -> void: menu.benchmark_requested.emit())
		_:
			return false
	return true


## The world at a glance (and the answers to "how many people? what weather?").
static func overview_lines(s: WorldSession) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(MainMenu.date_of(s.clock.tick))
	out.append(MemoryText.translate("OV_PEOPLE").format({"people": s.people.size(), "settlements": s.settlements.size()}))
	var size := s.world.bounds.size
	out.append(MemoryText.translate("OV_BOX_UNFOLDED" if s.unfolder.count > 0 else "OV_BOX").format({"w": size.x, "h": size.y, "times": s.unfolder.count}))
	if s.weather != null:
		out.append(MemoryText.translate("MENU_WEATHER_NOW").format({"weather": UIText.weather_line(s.weather.state, s.weather.temperature(s.clock.tick))}))
	if s.vegetation != null:
		out.append(MemoryText.translate("OV_TREES").format({"trees": s.vegetation.tree_count(), "forest": roundi(s.vegetation.forest_coverage() * 100.0)}))
	if s.knowledge != null:
		out.append(MemoryText.translate("OV_REGIONS").format({"found": s.knowledge.found_regions().size(), "all": s.knowledge.regions.regions.size()}))
		out.append(MemoryText.translate("OV_EDGE_YES" if s.knowledge.edge_reached else "OV_EDGE_NO"))
	out.append(MemoryText.translate("ADV_SEED").format({"seed": s.world_seed}))
	return out


static func copy_seed(s: WorldSession) -> void:
	DisplayServer.clipboard_set(str(s.world_seed))
	AudioManager.play_ui(&"ui_tap")
	var notice := Notice.new()
	notice.kind = &"seed_copied"
	notice.text = MemoryText.translate("ADV_COPIED").format({"seed": s.world_seed})
	notice.priority = 1.0
	NotificationManager.offer_notice(notice)


static func environment_lines(s: WorldSession) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(GameClock.season_name(s.clock.season()))
	if s.weather != null:
		for text in MainMenu.weather_lines(s).slice(1):
			out.append(text)
	if s.vegetation != null:
		out.append(MemoryText.translate("ENV_FOREST").format({"forest": roundi(s.vegetation.forest_coverage() * 100.0), "trees": s.vegetation.tree_count()}))
		out.append(MemoryText.translate("ENV_GRASS").format({"grass": roundi(s.vegetation.grass_cover() * 100.0)}))
	if s.farming != null and s.farming.is_dry_spell():
		out.append(MemoryText.translate("ENV_DRY").format({"days": s.farming.dry_days()}))
	return out


static func stores_lines(own: Settlement) -> PackedStringArray:
	var out := PackedStringArray()
	var amounts := own.stockpile.amounts()
	var names: Array = amounts.keys()
	names.sort()
	for resource: StringName in names:
		if int(amounts[resource]) > 0:
			out.append(UIText.resource_amount(resource, int(amounts[resource])))
	if out.is_empty():
		out.append(MemoryText.translate("MENU_NOTHING_RECORDED"))
	out.append(MemoryText.translate("SET_FOOD").format({"days": snappedf(minf(own.days_of_food(), 999.0), 0.1)}))
	return out


static func world_resource_lines(s: WorldSession) -> PackedStringArray:
	var trees := 0
	var bushes := 0
	for prop in s.props.of_kind(PropData.Kind.TREE):
		if prop.kind == PropData.Kind.TREE and prop.stock != 0:
			trees += 1
		elif prop.kind == PropData.Kind.BUSH:
			bushes += 1
	var stones := 0
	for object in s.loose.all_objects():
		if object.kind == LooseObject.Kind.ROCK or object.kind == LooseObject.Kind.PEBBLE:
			stones += 1
	return PackedStringArray([MemoryText.translate("RES_WORLD").format({"trees": trees, "bushes": bushes, "stones": stones})])


## How many, who, born and died this year (and the oldest, the youngest).
static func population_lines(s: WorldSession) -> PackedStringArray:
	var out := PackedStringArray()
	var year_ticks := Config.time.ticks_per_year()
	var counts := {PersonData.LifeStage.CHILD: 0, PersonData.LifeStage.ADULT: 0, PersonData.LifeStage.ELDER: 0}
	var men := 0
	var ages := 0
	for p in s.people.all_people():
		var stage := p.life_stage(s.clock.tick, year_ticks, Config.people)
		counts[stage] = int(counts.get(stage, 0)) + 1
		if p.sex == PersonData.Sex.MALE:
			men += 1
		ages += p.age_years(s.clock.tick, year_ticks)
	var total := s.people.size()
	out.append(MemoryText.translate("POP_TOTAL").format({"people": total}))
	out.append(MemoryText.translate("POP_STAGES").format({"children": counts.get(PersonData.LifeStage.CHILD, 0),
		"adults": counts.get(PersonData.LifeStage.ADULT, 0), "elders": counts.get(PersonData.LifeStage.ELDER, 0)}))
	out.append(MemoryText.translate("POP_SEXES").format({"men": men, "women": total - men}))
	if total > 0:
		out.append(MemoryText.translate("POP_AGE").format({"age": roundi(float(ages) / total)}))
	var year := Config.time.year_of(s.clock.tick)
	var born := 0
	var died := 0
	for e in s.events.of_type(&"person_born"):
		if Config.time.year_of(e.tick) == year:
			born += 1
	for e in s.events.of_type(&"person_died"):
		if Config.time.year_of(e.tick) == year:
			died += 1
	out.append(MemoryText.translate("POP_YEAR").format({"born": born, "died": died}))
	if s.settlements.size() > 1:
		for own in s.settlements.all():
			out.append(MemoryText.translate("POP_IN").format({"name": own.display_name(), "people": own.member_count()}))
	return out


## [[id, "The oldest: Seske Poth, 55"], [id, "The youngest: …"]].
static func oldest_and_youngest(s: WorldSession) -> Array:
	var oldest: PersonData = null
	var youngest: PersonData = null
	for p in s.people.all_people():
		if oldest == null or p.birth_tick < oldest.birth_tick:
			oldest = p
		if youngest == null or p.birth_tick > youngest.birth_tick:
			youngest = p
	var out: Array = []
	var year_ticks := Config.time.ticks_per_year()
	if oldest != null:
		out.append([oldest.id, MemoryText.translate("POP_OLDEST").format({"name": oldest.full_name(), "age": oldest.age_years(s.clock.tick, year_ticks)})])
	if youngest != null and youngest != oldest:
		out.append([youngest.id, MemoryText.translate("POP_YOUNGEST").format({"name": youngest.full_name(), "age": youngest.age_years(s.clock.tick, year_ticks)})])
	return out


## [[occupation name · count, [[id, name], …]], …] — the most first.
static func occupations(s: WorldSession) -> Array:
	var by := {}
	for p in s.people.all_people():
		if p.occupation_id == &"":
			continue
		if not by.has(p.occupation_id):
			by[p.occupation_id] = []
		(by[p.occupation_id] as Array).append([p.id, p.full_name()])
	var keys: Array = by.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool: return (by[a] as Array).size() > (by[b] as Array).size() or ((by[a] as Array).size() == (by[b] as Array).size() and String(a) < String(b)))
	var out: Array = []
	for key: StringName in keys:
		out.append(["%s · %d" % [UIText.occupation_name(key), (by[key] as Array).size()], by[key]])
	return out


## [[title, lines, fire XZ], …] — the largest first ("which has most food?").
static func settlements(s: WorldSession) -> Array:
	var all := s.settlements.all().duplicate()
	all.sort_custom(func(a: Settlement, b: Settlement) -> bool: return a.member_count() > b.member_count())
	var out: Array = []
	for own: Settlement in all:
		var lines := PackedStringArray()
		lines.append(MemoryText.translate("SET_PEOPLE").format({"tier": Settlements.tier_name(own.tier()), "people": own.member_count()}))
		var leader := s.governance.leader_of(own.id) if s.governance != null else 0
		if leader != 0:
			lines.append(MemoryText.translate("SET_LED").format({"name": s.people.name_of(leader)}))
		lines.append(MemoryText.translate("SET_FOOD_UNITS").format({"days": snappedf(minf(own.days_of_food(), 999.0), 0.1),
			"units": own.stockpile.food_units()}))
		var wood := own.stockpile.amount(&"wood")
		var stone := own.stockpile.amount(&"stone")
		lines.append(MemoryText.translate("SET_STORES").format({"wood": wood, "stone": stone, "tools": own.stockpile.amount(&"tools")}))
		var specialty := own.specialty()
		if specialty != &"":
			lines.append(MemoryText.translate("SET_KNOWN_FOR").format({"what": UIText.resource_name(specialty)}))
		lines.append(MemoryText.translate("SET_FOUNDED").format({"year": Config.time.year_of(own.founded_tick)}))
		var tile := own.start_info().settlement_tile
		out.append([own.display_name(), lines, Vector2(tile) + Vector2(0.5, 0.5)])
	return out


## [[settlement, lines (each kind of building, what is going up)], …].
static func buildings(s: WorldSession) -> Array:
	var out: Array = []
	for own in s.settlements.all():
		var kinds := {}
		for prop in s.props.buildings():
			if prop.is_building() and prop.kind != PropData.Kind.CAMPFIRE and s.settlements.nearest(prop.tile) == own:
				kinds[prop.kind] = int(kinds.get(prop.kind, 0)) + 1
		var lines := PackedStringArray()
		var keys: Array = kinds.keys()
		keys.sort()
		for kind: int in keys:
			lines.append("%s · %d" % [UIText.prop_name(kind), int(kinds[kind])])
		for p in s.construction.projects_of(own.id):
			lines.append(MemoryText.translate("BUILD_GOING").format({"what": String(p["def"]).capitalize(), "done": roundi(s.construction.progress(p) * 100.0)}))
		if lines.is_empty():
			lines.append(MemoryText.translate("MENU_NOTHING_RECORDED"))
		var tile := own.start_info().settlement_tile
		out.append([own.display_name(), lines, Vector2(tile) + Vector2(0.5, 0.5)])
	return out


static func economy_lines(s: WorldSession) -> PackedStringArray:
	var out := PackedStringArray()
	out.append(MemoryText.translate("ECO_TRIPS").format({"trips": s.trade.trips}))
	for own in s.settlements.all():
		var balance := s.trade.balance_of(own.id)
		var specialty := own.specialty()
		out.append(MemoryText.translate("ECO_SETTLEMENT").format({"name": own.display_name(),
			"known": UIText.resource_name(specialty) if specialty != &"" else MemoryText.translate("ECO_NOTHING"),
			"sends": UIText.resource_name(StringName(balance[0])) if String(balance[0]) != "" else "—",
			"gets": UIText.resource_name(StringName(balance[1])) if String(balance[1]) != "" else "—"}))
	return out


static func agriculture_lines(s: WorldSession) -> PackedStringArray:
	var out := PackedStringArray()
	var stages := {}
	for crop in s.farming.crops():
		var stage := Farming.stage_of(crop)
		stages[stage] = int(stages.get(stage, 0)) + 1
	out.append(MemoryText.translate("AGR_FIELDS").format({"fields": s.farming.crops().size(), "farmers": s.farming.farmer_count(),
		"harvests": s.farming.harvest_count()}))
	for stage: int in stages:
		out.append("%s · %d" % [MemoryText.translate("AGR_STAGE_%d" % stage), int(stages[stage])])
	if s.farming.is_dry_spell():
		out.append(MemoryText.translate("ENV_DRY").format({"days": s.farming.dry_days()}))
	return out


## [[leader id, "the first camp: led by Teireso"], …].
static func government(s: WorldSession) -> Array:
	var out: Array = []
	for own in s.settlements.all():
		var leader := s.governance.leader_of(own.id)
		if leader != 0:
			out.append([leader, MemoryText.translate("GOV_LEADS").format({"place": own.display_name(), "name": s.people.name_of(leader)})])
	return out


## What the world has come to believe: its shared memories and myths, in words.
static func beliefs(s: WorldSession) -> PackedStringArray:
	var out := PackedStringArray()
	for type: StringName in [&"myth_formed", &"cultural_memory", &"faith_founded", &"schism", &"myth_spread"]:
		for e in s.events.of_type(type):
			out.append(EventText.line(e, s.people, s.events))
	return out


## The Box Knowledge page (M18): what the civilization thinks of the
## unexplained — never the truth. {"state", "hypotheses", "clues": PackedStringArray}.
static func box_knowledge(s: WorldSession) -> Dictionary:
	var state := PackedStringArray()
	var hypotheses := PackedStringArray()
	var clues := PackedStringArray()
	if s.science != null:
		state.append(MemoryText.translate("BOX_STAGE_%d" % int(s.science.stage)))
	if s.anomaly_archive != null:
		var written := s.anomaly_archive.anomalies.filter(func(a: Dictionary) -> bool: return bool(a["written"])).size()
		state.append(MemoryText.translate("BOX_ANOMALIES").format({"count": s.anomaly_archive.anomalies.size(), "written": written}))
	if s.science != null:
		var best := {}
		for h in s.science.hypotheses:
			if not best.has(str(h["kind"])) or float(h["confidence"]) > float(best[str(h["kind"])]["confidence"]):
				best[str(h["kind"])] = h
		for kind: String in best:
			var h: Dictionary = best[kind]
			var part := str((h.get("params", {}) as Dictionary).get("part", ""))
			hypotheses.append(MemoryText.translate("BOX_HYP_" + kind.to_upper()).format({
				"sure": MemoryText.translate(ScienceSystem.confidence_word(float(h["confidence"]))),
				"part": MemoryText.translate("PART_" + part.to_upper()) if part != "" else ""}))
	for e in s.events.of_type(&"mystery_clue"):
		clues.append(EventText.line(e, s.people, s.events))
	return {"state": state, "hypotheses": hypotheses, "clues": clues}


## A settlement's culture in words (M17.1): what it values, what it makes of
## the Presence, its traditions and its look.
static func culture_lines(s: WorldSession, own: Settlement) -> PackedStringArray:
	var out := PackedStringArray()
	if s.cultures == null:
		return out
	var profile := s.cultures.profile_of(own)
	for value: Array in [["innovation", "CULT_INNOVATION", "CULT_TRADITION"], ["collectivism", "CULT_COMMUNITY", "CULT_SELF"],
			["piety", "CULT_PIETY", "CULT_SKEPTICISM"]]:
		var lean := float(profile[value[0]])
		if absf(lean) >= 0.15:
			out.append(MemoryText.translate(value[1] if lean > 0.0 else value[2]))
	if StringName(profile["presence"]) != &"":
		var belief_key := "MEMBELIEF_" + String(profile["presence"]).to_upper()
		out.append(MemoryText.translate("CULT_PRESENCE").format({"belief": MemoryText.translate(belief_key if MemoryText.has(belief_key) else "MEMBELIEF_NATURAL"),
			"share": roundi(float(profile["presence_share"]) * 100.0)}))
	for tradition in s.cultures.traditions_of(own.id):
		var day := int(tradition["day"])
		var when := MemoryText.translate("CULT_WHEN_DROUGHT") if String(tradition["when"]) == "drought" else \
			MemoryText.translate("CULT_WHEN_DAY").format({"day": (day - 1) % Config.time.days_per_season + 1,
				"season": MemoryText.translate("SEASON_%d" % ((day - 1) / Config.time.days_per_season)).to_lower()})
		var line := MemoryText.translate("CULT_TRADITION_LINE").format({"tradition": MemoryText.capitalized(MemoryText.translate(str(tradition["name"]))), "when": when})
		if bool(tradition["player"]):
			line += MemoryText.translate("CULT_FROM_YOU")
		out.append(line)
	out.append(MemoryText.translate("CULT_ROOFS_%d" % int(profile["architecture"])))
	if s.lexicon != null:
		var said := PackedStringArray()
		for concept: StringName in Lexicon.CONCEPTS:
			if concept != &"home" and s.lexicon.word(own.id, concept) != "":
				said.append(s.lexicon.gloss(own.id, concept))
		if not said.is_empty():
			out.append(MemoryText.translate("CULT_WORDS").format({"words": ", ".join(said)}))
	return out


## What a settlement believes (M17.2): its myths, who speaks for them, how many
## believe, their sacred places and shrine.
static func faith_lines(s: WorldSession, own: Settlement) -> PackedStringArray:
	var out := PackedStringArray()
	if s.faith == null:
		return out
	for myth in s.faith.myths_of(own.id):
		var epithet := MemoryText.translate(str(myth["epithet"])) if MemoryText.has(str(myth["epithet"])) else MemoryText.translate("EPITHET_UNKNOWN")
		if s.lexicon != null:
			var concept := Lexicon.concept_of_myth(StringName(str(myth["subject"])))
			if concept != &"" and s.lexicon.word(own.id, concept) != "":
				epithet = s.lexicon.gloss(own.id, concept)
		var founder := int(s.faith.founders.get(int(myth["id"]), 0))
		out.append(MemoryText.translate("FAITH_MYTH").format({"epithet": MemoryText.capitalized(epithet), "believers": int(myth["believers"]),
			"places": (myth.get("places", []) as Array).size()}))
		if founder != 0:
			out.append(MemoryText.translate("FAITH_FOUNDER").format({"name": s.people.name_of(founder)}))
	if own.planner != null and not own.planner.standing_near(PropData.Kind.SHRINE).is_empty():
		out.append(MemoryText.translate("FAITH_SHRINE"))
	return out


## What has been found: regions, the Edge, what was worked out — [[text, XZ or INF], …].
static func discoveries(s: WorldSession) -> Array:
	var out: Array = []
	for type: StringName in [&"region_found", &"knowledge_learned", &"resource_discovered"]:
		for e in s.events.of_type(type):
			out.append([EventText.line(e, s.people, s.events), e.position if e.position != Vector2.INF else Vector2.INF])
	return out


## Does anyone know anything beyond what all knew from the start (or come close)?
static func _beyond_the_beginning(s: WorldSession) -> bool:
	if s.technology == null or s.technologies == null:
		return false
	for own in s.settlements.all():
		for entry: Array in s.technology.known_by(own):
			if not s.technologies.get_def(entry[0]).known_from_start:
				return true
		if not s.technology.close_to(own).is_empty():
			return true
	return false


## The Technology page (M16.3): the age now; what is known, when, and who
## worked it out (or where it came from), the oldest first; what they are
## close to, vaguely. {"age": String, "known": PackedStringArray, "close": PackedStringArray}
static func technology(s: WorldSession) -> Dictionary:
	var out := {"age": "", "known": PackedStringArray(), "close": PackedStringArray()}
	if s.technology == null or s.technologies == null:
		return out
	var known := PackedStringArray()
	var hints := PackedStringArray()
	out["age"] = MemoryText.translate("TECH_AGE").format({"age": MemoryText.translate("ERA_" + String(CivilizationPhase.NAMES[s.technology.phase_now]).to_upper())})
	# Who worked what out, and what came from elsewhere (as history tells it).
	var told := {}
	for type: StringName in [&"knowledge_learned", &"knowledge_spread"]:
		for e in s.events.of_type(type):
			var kind := str(e.text_params.get("kind", ""))
			if not told.has(kind):
				told[kind] = e
	var start := PackedStringArray()
	var seen := {}
	for own in s.settlements.all():
		for entry: Array in s.technology.known_by(own):
			var id: StringName = entry[0]
			if seen.has(id):
				continue
			seen[id] = true
			var def := s.technologies.get_def(id)
			if def.known_from_start:
				start.append(tech_name(id))
				continue
			var e: WorldEvent = told.get(String(id))
			var who := s.people.name_of(e.participants[0]) if e != null and not e.participants.is_empty() else ""
			var line := "TECH_KNOWN_LINE" if e == null or e.type == &"knowledge_learned" else "TECH_KNOWN_FROM"
			known.append(MemoryText.translate(line).format({
				"year": HistoryText.year_of(int(entry[1])), "tech": tech_name(id),
				"name": who if who != "" else MemoryText.translate("EVENT_SOMEONE"), "place": str(e.text_params.get("place", "")) if e != null else ""}))
	if not start.is_empty():
		known.insert(0, MemoryText.translate("TECH_FROM_START").format({"techs": ", ".join(start)}))
	out["known"] = known
	var close := {}
	for own in s.settlements.all():
		for id in s.technology.close_to(own):
			close[id] = true
	for id: StringName in close:
		var hint := "TECH_HINT_" + String(id).to_upper()
		hints.append(MemoryText.translate(hint if MemoryText.has(hint) else "TECH_HINT"))
	out["close"] = hints
	return out


static func tech_name(id: StringName) -> String:
	var key := "TECH_" + String(id).to_upper()
	return MemoryText.translate(key) if MemoryText.has(key) else String(id).capitalize()


## How much of the box the player has seen close up (0 … 1).
static func seen_share(s: WorldSession) -> float:
	var b := s.world.bounds
	var seen := 0
	var all := 0
	for y in range(b.position.y, b.end.y, 2):
		for x in range(b.position.x, b.end.x, 2):
			all += 1
			if s.knowledge.is_seen(Vector2i(x, y)):
				seen += 1
	return float(seen) / maxf(all, 1.0)


static func _anyone_working(s: WorldSession) -> bool:
	for p in s.people.all_people():
		if p.occupation_id != &"":
			return true
	return false


static func _anyone_leads(s: WorldSession) -> bool:
	if s.governance == null:
		return false
	for own in s.settlements.all():
		if s.governance.leader_of(own.id) != 0:
			return true
	return false


static func _any_event(s: WorldSession, test: Callable) -> bool:
	for e in s.events.all_events():
		if test.call(e):
			return true
	return false
