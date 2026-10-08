extends TestCase
## The family in the UI (M10.4, bible §26.5, spec §16): the family tree
## across generations (the dead included), the ☰ menu's PEOPLE section
## (Individuals, Families, Relationships), and the way from a person or a
## grave to their family.

var main: Node
var ui: UIRoot
var session: WorldSession
var _knobs: Array = []


func before_each() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	session = main.get_node("WorldSession")
	session.clock.set_speed(0)
	for knob: StringName in [&"base_death_per_year", &"infant_death_per_year", &"old_age_death_per_year",
			&"accident_per_work_day", &"crowding_chance_per_day", &"partner_chance_per_day", &"conceive_chance_per_day",
			&"newcomer_chance_per_day", &"marry_out_chance_per_day", &"gathering_romance"]:
		_knobs.append([knob, Config.life.get(knob)])
		Config.life.set(knob, 0.0)


func after_each() -> void:
	for knob: Array in _knobs:
		Config.life.set(knob[0], knob[1])
	_knobs.clear()
	ui.close_all_panels()
	await wait_frames(2)


## Three generations: the band's elder (dead), their child and partner, and
## grandchildren — one of them born now.
func _three_generations() -> Dictionary:
	var parent: PersonData = null
	for person in session.people.all_people():
		if person.partner_id != 0 and not person.children.is_empty() and person.sex == PersonData.Sex.FEMALE:
			parent = person
	var elder := session.spawn_person(session.start.settlement_tile, PersonData.LifeStage.ELDER)
	elder.children.append(parent.id)
	parent.parents = PackedInt64Array([elder.id])
	session.kill_person(elder.id, Lifecycle.CAUSE_OLD_AGE)
	session.lifecycle.conceive(parent, session.clock.tick)
	var baby := session.lifecycle.give_birth(parent, session.clock.tick)
	return {"elder": elder, "parent": parent, "partner": session.people.get_person(parent.partner_id), "baby": baby}


func test_family_tree_reconstruction() -> void:
	var family := _three_generations()
	var elder: PersonData = family["elder"]
	var parent: PersonData = family["parent"]
	var baby: PersonData = family["baby"]
	# The furthest forebear, from anyone of the family — the dead included.
	assert_eq(FamilyTree.root_of(session, baby.id), elder.id)
	assert_eq(FamilyTree.root_of(session, parent.id), elder.id)
	assert_eq(FamilyTree.root_of(session, elder.id), elder.id)
	var rows := FamilyTree.rows(session, elder.id)
	assert_eq(int(rows[0]["id"]), elder.id)
	assert_false(bool(rows[0]["living"]))
	assert_eq(rows[0]["name"], "%s (died in year 1)" % elder.given_name)
	assert_eq(int(rows[1]["id"]), parent.id)
	assert_eq(int(rows[1]["depth"]), 1)
	assert_eq(rows[1]["prefix"], "└─ ", "an only child")
	assert_true(String(rows[1]["name"]).ends_with("& %s" % (family["partner"] as PersonData).given_name), "with her partner")
	var ids: Array[int] = []
	for row: Dictionary in rows:
		ids.append(int(row["id"]))
	assert_eq(ids.size(), 2 + parent.children.size(), "everyone once")
	for child in parent.children:
		assert_true(ids.has(child))
	# Her children, the eldest first; the newborn last, at the bottom of the lines.
	assert_eq(int(rows[-1]["id"]), baby.id)
	assert_eq(int(rows[-1]["depth"]), 2)
	assert_eq(rows[-1]["prefix"], "   └─ ")
	assert_eq(rows[-1]["name"], "%s, 0" % baby.given_name)
	if parent.children.size() > 1:
		assert_eq(rows[2]["prefix"], "   ├─ ")
	# The families of the world: hers among them, each couple once.
	var roots := FamilyTree.families(session)
	assert_true(roots.has(elder.id))
	assert_false(roots.has(parent.id), "she belongs to her mother's family")
	assert_eq(roots.size(), roots.duplicate().size())
	for root in roots:
		assert_false(roots.has(FamilyTree.partner_of(session, root)) and FamilyTree.partner_of(session, root) != root)
	assert_true(FamilyTree.family_title(session, elder.id).begins_with("The %s family" % elder.family_name))
	assert_true(FamilyTree.family_title(session, elder.id).ends_with("1 gone"))
	# The widget draws it, and a tap names who.
	var tree := FamilyTree.new()
	add_child(tree)
	tree.show_family(session, elder.id, baby.id)
	await wait_frames(1)
	assert_eq(tree.lines().size(), rows.size())
	assert_eq(tree.lines()[-1], "   └─ %s, 0" % baby.given_name)
	var chosen: Array = []
	tree.person_chosen.connect(func(id: int) -> void: chosen.append(id))
	var first_row := tree.get_child(0)
	for part in first_row.get_children():
		if part is Button:
			(part as Button).pressed.emit()
	assert_eq(chosen, [elder.id])
	tree.queue_free()


func test_the_menu() -> void:
	# The ☰ is always there now, and opens the menu.
	var button := ui.menu_button()
	assert_true(button.visible)
	button.pressed.emit()
	await wait_frames(2)
	var menu := ui.main_menu()
	assert_not_null(menu)
	assert_eq(menu.page(), MainMenu.PAGE_ROOT)
	assert_true(menu.texts().has("PEOPLE"))
	assert_true(menu.entries().any(func(b: Button) -> bool: return b.text == "Individuals"))
	assert_true(menu.texts().has("SETTINGS"), "since VS.1: Audio, Haptics, Save")
	assert_true(menu.texts().has("WORLD"), "since VS.1: Weather")
	assert_false(menu.texts().has("Technology") or menu.texts().has("Wars"), "what is not there yet is hidden")
	assert_true(menu.texts().has("HISTORY"), "since M11.2: Important People, Firsts")
	# Individuals: everyone living; a tap goes to them (and the menu closes).
	_entry_named(menu, "Individuals").pressed.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_INDIVIDUALS)
	assert_eq(menu.entries().size(), session.people.size())
	var rows := MainMenu.individuals(session)
	var first := session.people.get_person(int(rows[0][0]))
	assert_true(menu.entries()[0].text.begins_with(first.full_name()))
	# Back is a page back (the back button too).
	EventBus.back_requested.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_ROOT)
	assert_not_null(ui.main_menu(), "still open")
	menu.open_page(MainMenu.PAGE_INDIVIDUALS)
	await wait_frames(1)
	menu.entries()[0].pressed.emit()
	await wait_frames(2)
	assert_null(ui.main_menu(), "closed: to them")
	assert_not_null(ui.person_card())
	assert_eq(ui.person_card().person_id(), first.id)
	ui.close_all_panels()
	await wait_frames(1)
	# Back on the first page closes it.
	ui.open_menu()
	await wait_frames(1)
	EventBus.back_requested.emit()
	await wait_frames(2)
	assert_null(ui.main_menu())


func test_families_and_relationships_in_the_menu() -> void:
	var family := _three_generations()
	var elder: PersonData = family["elder"]
	var parent: PersonData = family["parent"]
	var menu := ui.open_menu()
	await wait_frames(1)
	menu.open_page(MainMenu.PAGE_FAMILIES)
	await wait_frames(1)
	var titles := menu.texts()
	assert_true(titles.has(FamilyTree.family_title(session, elder.id)), str(titles))
	for entry in menu.entries():
		if entry.text == FamilyTree.family_title(session, elder.id):
			entry.pressed.emit()
	await wait_frames(1)
	assert_eq(menu.page(), MainMenu.PAGE_TREE)
	assert_eq(menu.title_text(), "The %s family" % elder.family_name)
	assert_not_null(menu.tree())
	assert_eq(menu.tree().lines().size(), FamilyTree.rows(session, elder.id).size())
	# Relationships: someone, and what everyone they know is to them.
	menu.back()
	menu.back()
	menu.open_page(MainMenu.PAGE_RELATIONS_OF, parent.id)
	await wait_frames(1)
	assert_eq(menu.title_text(), parent.given_name)
	var said := menu.texts()
	var partner: PersonData = family["partner"]
	assert_true(said[0].begins_with("%s — partner" % partner.given_name) or said[0].contains("— daughter") or said[0].contains("— son"),
		"family first: %s" % said[0])
	var found := false
	for text in said:
		found = found or text.begins_with("%s — partner · " % partner.given_name)
	assert_true(found, str(said))
	assert_eq(MainMenu.feeling_word(0.8), "close")
	assert_eq(MainMenu.feeling_word(-0.8), "hostile")
	ui.close_all_panels()


func test_from_a_person_or_a_grave_to_the_family() -> void:
	var family := _three_generations()
	var elder: PersonData = family["elder"]
	var baby: PersonData = family["baby"]
	# The person card: a tap on the dead reads their grave; "Family tree" opens the tree.
	main.select_person(baby.id, PersonCard.State.FULL)
	await wait_frames(2)
	var card := ui.person_card()
	assert_not_null(card)
	var tree_asked: Array = []
	card.tree_requested.connect(func(id: int) -> void: tree_asked.append(id))
	card.tree_requested.emit(baby.id)
	await wait_frames(2)
	var menu := ui.main_menu()
	assert_not_null(menu, "the tree, in the menu")
	assert_eq(menu.page(), MainMenu.PAGE_TREE)
	assert_eq(menu.title_text(), "The %s family" % elder.family_name)
	assert_true(menu.tree().lines()[-1].ends_with("%s, 0" % baby.given_name))
	# Back: the families of the world.
	assert_true(menu.back())
	assert_eq(menu.page(), MainMenu.PAGE_FAMILIES)
	ui.close_all_panels()
	await wait_frames(1)
	# A tap on the dead (from the tree, or a family list) reads their grave.
	main._on_person_chosen(elder.id)
	await wait_frames(2)
	assert_not_null(ui.grave_card())
	assert_eq(ui.grave_card().person_id(), elder.id)
	# The grave card's "Family tree".
	ui.grave_card().tree_requested.emit(elder.id)
	await wait_frames(2)
	assert_not_null(ui.main_menu())
	assert_eq(ui.main_menu().page(), MainMenu.PAGE_TREE)
	ui.close_all_panels()


func test_the_toasts_wait_while_the_menu_is_open() -> void:
	assert_true(ui.toasts().visible)
	ui.open_menu()
	await wait_frames(1)
	assert_false(ui.toasts().visible)
	ui.close_all_panels()
	await wait_frames(1)
	assert_true(ui.toasts().visible)


func _entry_named(menu: MainMenu, text: String) -> Button:
	for entry in menu.entries():
		if entry.text == text:
			return entry
	return null
