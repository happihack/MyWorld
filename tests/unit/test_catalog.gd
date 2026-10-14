extends TestCase
## Buildings & villagers F1: the data model. Buildings say what kind they
## are, who works them, where they go and how many a settlement keeps;
## occupations say their family, workplaces, what a day of them teaches,
## whether elders keep them. Everything named exists.


func test_the_data_names_only_what_there_is() -> void:
	var buildings := BuildingLibrary.load_from()
	var occupations := OccupationLibrary.load_from()
	var resources := ResourceLibrary.load_from()
	var techs := TechnologyLibrary.load_from()
	assert_eq(buildings.problems, PackedStringArray())
	assert_eq(occupations.problems, PackedStringArray())
	assert_eq(Catalog.check(buildings, occupations, resources, techs), PackedStringArray())
	for id in buildings.ids():
		var def := buildings.get_def(id)
		assert_false(def.category.is_empty(), "%s has a category" % id)
	assert_eq(buildings.get_def(&"landing").site, &"bank")
	assert_eq(buildings.get_def(&"bridge").site, &"crossing")
	assert_eq(buildings.get_def(&"workshop").workers, {"toolmaker": 1})
	assert_eq(occupations.get_def(&"fisher").workplaces, PackedStringArray(["landing", "net_rack", "fish_trap"]))
	assert_true(occupations.get_def(&"toolmaker").elder_keeps)
	assert_eq(occupations.get_def(&"toolmaker").teaches_by_domain(), {Knowledge.Domain.CRAFT: 0.7})
	# Staffing (F2): the trades taken up when wanted, in today's order.
	var staffed := occupations.ids().filter(func(id: StringName) -> bool: return occupations.get_def(id).staffing_order > 0)
	staffed.sort_custom(func(a: StringName, b: StringName) -> bool: return occupations.get_def(a).staffing_order < occupations.get_def(b).staffing_order)
	assert_eq(staffed, [&"farmer", &"hunter", &"fisher", &"builder", &"trader", &"toolmaker", &"scientist"])


func test_what_is_named_but_not_there_is_found() -> void:
	var buildings := BuildingLibrary.load_from()
	var occupations := OccupationLibrary.load_from()
	var odd := BuildingDef.new()
	odd.id = &"odd"
	odd.category = PackedStringArray(["nonsense"])
	odd.site = &"the_moon"
	odd.workers = {"wizard": 1}
	odd.recipe = [{"in": {&"unobtainium": 1}, "out": {}, "minutes": 0}]
	odd.upgrade_of = &"palace"
	assert_eq(odd.validate().size(), 3, str(odd.validate()))
	buildings._defs[&"odd"] = odd
	var problems := Catalog.check(buildings, occupations, ResourceLibrary.load_from(), TechnologyLibrary.load_from())
	assert_eq(problems.size(), 3, str(problems))
	var trade := OccupationDef.new()
	trade.id = &"odd_trade"
	trade.teaches = {"alchemy": 1.0}
	trade.requires = {"luck": 1}
	assert_eq(trade.validate().size(), 2, str(trade.validate()))
