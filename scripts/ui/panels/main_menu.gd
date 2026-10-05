class_name MainMenu
extends UIPanel
## The ☰ menu (bible §26.5), v0 (VS.1): a panel that slides in from the left,
## with the sections there is something for — WORLD (Weather, Statistics), PEOPLE
## (Individuals, Families, Relationships, Important People), HISTORY (Timeline:
## the recent events, a tap looks for them; Important People, Firsts), PLAYER
## (Interaction History, with its counts) and SETTINGS (Audio, Haptics, Motion
## while motion controls are on, Save). Other sections (CIVILIZATION, Map…)
## stay hidden until their systems exist (the menu grows with the
## world). The first page is an accordion: the sections' headings, one open at
## a time. Each entry opens a page in the panel; Back goes a page back.

## Someone was picked (living: go to them; dead: read their grave).
signal person_chosen(person_id: int)
## The motion settings were asked for.
signal motion_requested
## The timeline was asked for (M11.3).
signal timeline_requested
## The timeline was asked for, through one filter (M14: Major Events, Disasters).
signal timeline_filter_requested(filter: StringName)
## The statistics were asked for (VS.2).
signal statistics_requested
## The map was asked for (M13.3).
signal map_requested
## A place was chosen (a region, M13.4): the camera goes there.
signal place_chosen(world_xz: Vector2)
## Another world is to be opened (VS.3): `plan` as SaveManager.open_next;
## `erase_this`: this world is erased first (Reset).
signal world_requested(plan: Dictionary, erase_this: bool)
## The player's own history was asked for (M11.4).
signal history_requested

const PAGE_ROOT := &"root"
const PAGE_INDIVIDUALS := &"individuals"
const PAGE_FAMILIES := &"families"
const PAGE_TREE := &"tree"
const PAGE_RELATIONSHIPS := &"relationships"
const PAGE_RELATIONS_OF := &"relations_of"
const PAGE_IMPORTANT := &"important"
const PAGE_FIRSTS := &"firsts"
const PAGE_WEATHER := &"weather"
const PAGE_AUDIO := &"audio"
const PAGE_HAPTICS := &"haptics"
const PAGE_SAVE := &"save"
const PAGE_WORLDS := &"worlds"
const PAGE_BACKUPS := &"backups"
const PAGE_CONFIRM := &"confirm"
const PAGE_NEW_WORLD := &"new_world"
const PAGE_REGIONS := &"regions"
const PAGE_LOCATE := &"locate"
## The most of each kind the Locate page lists.
const LOCATE_EACH := 30
## The boxes a new world can begin in (tiles across; M13.2 — the first is the usual).
const NEW_WORLD_SIZES: Array[int] = [64, 128, 256]

## The volumes on the Audio page, and how far a step moves them.
const VOLUMES: Array[StringName] = [&"audio/master", &"audio/ambience", &"audio/sfx", &"audio/ui"]
const VOLUME_STEP := 0.1
## How many days back the Weather page tells of rain.
const RAIN_DAYS := 7

const EDGE_MARGIN := 24.0
const TOP := 40.0
const MAX_WIDTH := 820.0
const SLIDE_SECONDS := 0.18
## How far a section's entries are set in under its heading.
const SECTION_INDENT := 56.0

var _session: WorldSession
var _stack: Array = [] # [page, argument, second argument]
var _title: Label
var _back: Button
var _close: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _settling := 0
var _slide: Tween
## The question PAGE_CONFIRM asks: [text, yes text, what yes does].
var _confirm: Array = []
## The Locate page's search, and what it found.
var _search: LineEdit
var _query := ""
## Individuals (M14): the search, the order and whom it shows.
var _people_search: LineEdit
var _people_query := ""
var _people_sort: StringName = &"name"
var _people_stage: StringName = &"all"
var _people_rows: VBoxContainer
## The section open on the first page ("": none; kept while the game runs).
static var _open_section := ""
## A section just opened: scrolled to the top of the list once it is laid out.
var _reveal := ""


func _init() -> void:
	super._init()
	var content := VBoxContainer.new()
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_back = Button.new()
	_back.text = "‹"
	_back.focus_mode = Control.FOCUS_NONE
	_back.custom_minimum_size = Vector2(UITheme.TOUCH_TARGET * 0.7, UITheme.TOUCH_TARGET * 0.7)
	_back.pressed.connect(back)
	header.add_child(_back)
	_title = Label.new()
	_title.theme_type_variation = UITheme.TITLE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title)
	_close = CloseButton.new()
	_close.pressed.connect(close)
	header.add_child(_close)
	content.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# (A finger dragged over the entries scrolls them; a tap that wobbles a little is still a tap.)
	_scroll.scroll_deadzone = int(UITheme.TOUCH_TARGET * 0.15)
	content.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


func _ready() -> void:
	get_viewport().size_changed.connect(layout)
	layout()
	# (It slides in from the left.)
	if not bool(Settings.get_value(&"accessibility/reduced_motion")):
		var rest := position.x
		position.x = -size.x
		_slide = create_tween()
		_slide.tween_property(self, "position:x", rest, SLIDE_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _process(_delta: float) -> void:
	if _settling > 0:
		_settling -= 1
		layout()
		if _settling == 0 and _reveal != "":
			var header := _list.get_node_or_null("Section_" + _reveal) as Control
			_reveal = ""
			if header != null:
				_scroll.scroll_vertical = int(header.position.y)


func setup(session: WorldSession) -> void:
	_session = session
	_stack = [[PAGE_ROOT, 0, 0]]
	_show()


## Opens a page on top of the one shown.
func open_page(page: StringName, argument: int = 0, second: int = 0) -> void:
	_stack.append([page, argument, second])
	_show()


## A page back; false (and nothing done) on the first page.
func back() -> bool:
	if _stack.size() <= 1:
		return false
	_stack.pop_back()
	_show()
	return true


func page() -> StringName:
	return StringName(_stack[-1][0]) if not _stack.is_empty() else &""


func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	# Held upright: as tall as what it lists (no more of the world covered than
	# needs be), scrolling beyond. Turned on its side (M14): a panel down the
	# side, never covering more than half the world.
	var landscape := view.x > view.y
	var tallest := view.y - TOP - EDGE_MARGIN - (EDGE_MARGIN if landscape else 300.0)
	_scroll.custom_minimum_size.y = 0.0
	var rest := get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, 0.0, maxf(tallest - rest, 120.0))
	if landscape:
		_scroll.custom_minimum_size.y = maxf(tallest - rest, 120.0)
	custom_minimum_size = Vector2(panel_width(view), 0.0)
	reset_size()
	position.y = TOP
	if _slide == null or not _slide.is_running():
		position.x = EDGE_MARGIN


## How wide the panel is on a screen of `view` (M14: down the side, at most
## half the world covered, when the screen is on its side).
static func panel_width(view: Vector2) -> float:
	return clampf(view.x * (0.45 if view.x > view.y else 0.82), 300.0, MAX_WIDTH)


# --- the pages --------------------------------------------------------------------------------------

func _show() -> void:
	# (Out of the list at once: the new page's names must not meet the old one's.)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_scroll.scroll_vertical = 0
	var entry: Array = _stack[-1]
	_back.visible = _stack.size() > 1
	_settling = 3
	match StringName(entry[0]):
		PAGE_ROOT:
			_title.text = MemoryText.translate("MENU_TITLE")
			if _session == null:
				return
			# The sections (M14, bible §26.5), as an accordion: a heading each;
			# a tap opens what it holds (and closes the one that was open).
			for section: Array in MenuPages.sections(self):
				var key: String = section[0]
				var open := _open_section == key
				var header := Button.new()
				header.name = "Section_" + key
				header.text = MemoryText.translate(key)
				header.alignment = HORIZONTAL_ALIGNMENT_LEFT
				header.focus_mode = Control.FOCUS_NONE
				header.mouse_filter = Control.MOUSE_FILTER_PASS # (a drag on it scrolls the list)
				header.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.8)
				header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var chevron := Label.new()
				chevron.name = "Chevron"
				chevron.text = "−" if open else "+"
				chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
				chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				chevron.add_theme_font_size_override(&"font_size", UITheme.FONT_TITLE)
				chevron.add_theme_color_override(&"font_color", UITheme.INK_DIM)
				chevron.anchor_left = 1.0
				chevron.anchor_right = 1.0
				chevron.anchor_bottom = 1.0
				chevron.offset_left = -UITheme.TOUCH_TARGET * 0.6
				chevron.offset_right = -16.0
				header.add_child(chevron)
				header.pressed.connect(func() -> void:
					_open_section = "" if _open_section == key else key
					_reveal = _open_section
					AudioManager.play_ui(&"ui_tap")
					_show())
				_list.add_child(header)
				var body := VBoxContainer.new()
				body.name = "Body_" + key
				body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				body.mouse_filter = Control.MOUSE_FILTER_PASS
				body.visible = open
				_list.add_child(body)
				for item: Array in section[1]:
					var inner := _make_entry(MemoryText.translate(item[0]), item[1])
					# (Set in under its heading.)
					for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
						var style := inner.get_theme_stylebox(state).duplicate() as StyleBox
						style.content_margin_left += SECTION_INDENT
						inner.add_theme_stylebox_override(state, style)
					body.add_child(inner)
		PAGE_WEATHER:
			_title.text = MemoryText.translate("MENU_WEATHER")
			for text in weather_lines(_session):
				_line(text)
		PAGE_AUDIO:
			_title.text = MemoryText.translate("MENU_AUDIO")
			_toggle(&"audio/muted", "MENU_SOUND", true)
			for key in VOLUMES:
				_volume(key)
		PAGE_HAPTICS:
			_title.text = MemoryText.translate("MENU_HAPTICS")
			_toggle(&"haptics/enabled", "MENU_VIBRATION")
			_small(MemoryText.translate("MENU_VIBRATION_ABOUT"))
		PAGE_SAVE:
			_title.text = MemoryText.translate("MENU_SAVE")
			_line(saved_text(SaveManager.last_save_info, int(Time.get_unix_time_from_system())))
			_small(MemoryText.translate("MENU_SAVED_ABOUT").format({"minutes": roundi(Config.save.autosave_interval_s / 60.0)}))
			_entry(MemoryText.translate("MENU_SAVE_NOW"), func() -> void:
				AudioManager.play_ui(&"ui_tap")
				if _session != null:
					SaveManager.save_world(_session, &"menu")
				_show())
			if not other_worlds(_session).is_empty():
				_entry(MemoryText.translate("MENU_CONTINUE"), func() -> void: open_page(PAGE_WORLDS))
			_entry(MemoryText.translate("MENU_NEW_WORLD"), func() -> void: open_page(PAGE_NEW_WORLD))
			_entry(MemoryText.translate("MENU_BACKUPS"), func() -> void: open_page(PAGE_BACKUPS))
			_entry(MemoryText.translate("MENU_RESET"), func() -> void:
				ask(MemoryText.translate("MENU_RESET_ASK"), MemoryText.translate("MENU_RESET_YES"), func() -> void:
					world_requested.emit({"kind": "new"}, true)))
		PAGE_LOCATE:
			_title.text = MemoryText.translate("MENU_LOCATE")
			_search = LineEdit.new()
			_search.placeholder_text = MemoryText.translate("LOCATE_SEARCH")
			_search.text = _query
			_search.clear_button_enabled = true
			_search.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.6)
			_search.text_changed.connect(func(text: String) -> void:
				_query = text
				_fill_locate())
			_list.add_child(_search)
			_fill_locate()
		PAGE_REGIONS:
			_title.text = MemoryText.translate("MENU_REGIONS")
			for row: Array in regions(_session):
				var at: Vector2 = row[1]
				_entry(row[0], func() -> void: place_chosen.emit(at))
		PAGE_NEW_WORLD:
			_title.text = MemoryText.translate("MENU_NEW_WORLD")
			_line(MemoryText.translate("MENU_NEW_WORLD_ASK"))
			for tiles in NEW_WORLD_SIZES:
				var size := tiles
				var key := "MENU_BOX_USUAL" if size == NEW_WORLD_SIZES[0] else "MENU_BOX_LARGER"
				_entry(MemoryText.translate(key).format({"tiles": size}), func() -> void:
					AudioManager.play_ui(&"ui_tap")
					world_requested.emit({"kind": "new", "size": size}, false))
			_entry(MemoryText.translate("MENU_NO"), func() -> void: back())
		PAGE_WORLDS:
			_title.text = MemoryText.translate("MENU_CONTINUE")
			var now_unix := int(Time.get_unix_time_from_system())
			for other in other_worlds(_session):
				var world_id: String = other["world_id"]
				_entry(world_text(other, now_unix), func() -> void:
					world_requested.emit({"kind": "world", "world_id": world_id}, false))
		PAGE_BACKUPS:
			_title.text = MemoryText.translate("MENU_BACKUPS")
			var kept := SaveManager.backups(_session.world_id) if _session != null else ([] as Array[Dictionary])
			if kept.is_empty():
				_line(MemoryText.translate("MENU_NO_BACKUPS"))
			else:
				_small(MemoryText.translate("MENU_BACKUPS_ABOUT"))
			var now_unix := int(Time.get_unix_time_from_system())
			for backup in kept:
				var file_name: String = backup["file"]
				_entry(backup_text(backup, now_unix), func() -> void:
					ask(MemoryText.translate("MENU_BACKUP_ASK"), MemoryText.translate("MENU_BACKUP_YES"), func() -> void:
						var loaded := SaveManager.load_file(_session.world_id, file_name)
						if loaded.ok:
							world_requested.emit({"kind": "loaded", "loaded": loaded}, false)
						else:
							back()
							_line(MemoryText.translate("MENU_BACKUP_UNREADABLE"))))
		PAGE_CONFIRM:
			_title.text = MemoryText.translate("MENU_SURE")
			_line(_confirm[0])
			var yes: Callable = _confirm[2]
			_entry(_confirm[1], func() -> void:
				AudioManager.play_ui(&"ui_tap")
				yes.call())
			_entry(MemoryText.translate("MENU_NO"), func() -> void: back())
		PAGE_INDIVIDUALS:
			_title.text = MemoryText.translate("MENU_INDIVIDUALS")
			# Search, order and who (M14).
			_people_search = LineEdit.new()
			_people_search.placeholder_text = MemoryText.translate("PEOPLE_SEARCH")
			_people_search.text = _people_query
			_people_search.clear_button_enabled = true
			_people_search.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.6)
			_people_search.text_changed.connect(func(text: String) -> void:
				_people_query = text
				_fill_individuals())
			_list.add_child(_people_search)
			var sorts: Array = []
			for sort in MenuPages.SORTS:
				sorts.append([MemoryText.translate("SORT_" + String(sort).to_upper()), sort])
			add_chips(sorts, _people_sort, func(value: Variant) -> void:
				_people_sort = value
				_fill_individuals())
			var stages: Array = []
			for stage in MenuPages.STAGES:
				stages.append([MemoryText.translate("STAGE_" + String(stage).to_upper()), stage])
			add_chips(stages, _people_stage, func(value: Variant) -> void:
				_people_stage = value
				_fill_individuals())
			_people_rows = VBoxContainer.new()
			_people_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_list.add_child(_people_rows)
			_fill_individuals()
		PAGE_FAMILIES:
			_title.text = MemoryText.translate("MENU_FAMILIES")
			for root in FamilyTree.families(_session):
				var id := root
				_entry(FamilyTree.family_title(_session, root), func() -> void: open_page(PAGE_TREE, id))
		PAGE_TREE:
			_title.text = FamilyTree.family_title(_session, int(entry[1])).get_slice(" ·", 0)
			var tree := FamilyTree.new()
			tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_list.add_child(tree)
			tree.show_family(_session, int(entry[1]), int(entry[2]))
			tree.person_chosen.connect(func(id: int) -> void: person_chosen.emit(id))
		PAGE_IMPORTANT:
			_title.text = MemoryText.translate("MENU_IMPORTANT")
			var rows := important(_session)
			if rows.is_empty():
				_line(MemoryText.translate("MENU_NOBODY_YET"))
			for row: Array in rows:
				var id: int = row[0]
				_entry(row[1], func() -> void: person_chosen.emit(id))
				if String(row[2]) != "":
					_small(row[2])
		PAGE_FIRSTS:
			_title.text = MemoryText.translate("MENU_FIRSTS")
			var firsts := _session.significance.firsts() if _session.significance != null else ([] as Array[WorldEvent])
			if firsts.is_empty():
				_line(MemoryText.translate("MENU_NOTHING_YET"))
			for event in firsts:
				_small(EventText.line(event, _session.people, _session.events))
		PAGE_RELATIONSHIPS:
			_title.text = MemoryText.translate("MENU_RELATIONSHIPS")
			for row: Array in individuals(_session):
				var id: int = row[0]
				_entry(row[1], func() -> void: open_page(PAGE_RELATIONS_OF, id))
		PAGE_RELATIONS_OF:
			var id := int(entry[1])
			_title.text = _session.people.name_of(id)
			var rows := relations_of(_session, id)
			if rows.is_empty():
				_line(MemoryText.translate("MENU_KNOWS_NOBODY"))
			for row: Array in rows:
				var other: int = row[0]
				_entry(row[1], func() -> void: person_chosen.emit(other))
		_:
			if not MenuPages.build(self, StringName(entry[0]), entry):
				_line(MemoryText.translate("MENU_NOTHING_RECORDED"))

## What the Weather page says: the date, the sky now, what is going on
## (a drought, a cold snap, frozen ground) and the rain of the last days.
static func weather_lines(session: WorldSession) -> PackedStringArray:
	var out := PackedStringArray()
	var weather := session.weather
	var clock := session.clock
	out.append(clock.format_date(false))
	out.append(MemoryText.translate("MENU_WEATHER_NOW").format({"weather": UIText.weather_line(weather.state,
		weather.temperature(clock.tick))}))
	for condition in weather.conditions():
		out.append(MemoryText.translate("MENU_CONDITION_" + String(condition).to_upper()))
	if weather.is_frozen():
		out.append(MemoryText.translate("MENU_FROZEN"))
	var today := clock.day()
	var days := mini(RAIN_DAYS, today + 1)
	var rainy := 0
	for back_days in days:
		if weather.rain_on(today - back_days):
			rainy += 1
	out.append(MemoryText.translate("MENU_RAIN_DAYS").format({"rainy": rainy, "days": days}) if rainy > 0
		else MemoryText.translate("MENU_NO_RAIN").format({"days": days}))
	return out


## Lists what can be found on the Locate page (under the search box), by
## what it is; only what matches the search.
func _fill_locate() -> void:
	for child in _list.get_children():
		if child != _search:
			child.queue_free()
	var last := ""
	for row: Array in locate_rows(_session, _query):
		if String(row[0]) != last:
			last = row[0]
			_heading(MemoryText.translate("LOCATE_" + last.to_upper()))
		var id: int = row[3]
		var at: Vector2 = row[2]
		_entry(row[1], func() -> void:
			if id != 0:
				person_chosen.emit(id)
			else:
				place_chosen.emit(at))
	if last == "":
		_line(MemoryText.translate("LOCATE_NOTHING"))
	_settling = 3


## Everything that can be found (M13.5), matching `query` (any case; "" all):
## [[kind, text, world XZ, person id (0: a place)], …], by kind — people,
## settlements, buildings, events, discoveries.
static func locate_rows(session: WorldSession, query: String = "") -> Array:
	var out: Array = []
	if session == null:
		return out
	var wanted := query.strip_edges().to_lower()
	var add := func(kind: String, text: String, at: Vector2, id: int) -> void:
		if wanted == "" or text.to_lower().contains(wanted):
			out.append([kind, text, at, id])
	var shown := 0
	for row: Array in individuals(session):
		var person := session.people.get_person(int(row[0]))
		if person != null and shown < LOCATE_EACH:
			add.call("people", row[1], person.world2d(), person.id)
			shown += 1
	for own in session.settlements.all():
		var tile := own.start_info().settlement_tile
		add.call("settlements", "%s · %s" % [own.display_name(), Settlements.tier_name(own.tier())], Vector2(tile) + Vector2(0.5, 0.5), 0)
	shown = 0
	for prop in session.props.all_props():
		if not prop.is_building() or prop.kind == PropData.Kind.CAMPFIRE or shown >= LOCATE_EACH:
			continue
		var own := session.settlements.nearest(prop.tile)
		var where := own.display_name() if own != null else ""
		var living := session.people.living_in(prop.id)
		var key := "LOCATE_HOME" if not living.is_empty() and living[0].family_name != "" else "LOCATE_BUILDING"
		add.call("buildings", MemoryText.translate(key).format({"what": UIText.prop_name(prop.kind, prop.variant), "where": where,
			"family": living[0].family_name if not living.is_empty() else ""}),
			prop.position2d(), 0)
		shown += 1
	var events := session.events.all_events()
	shown = 0
	for i in range(events.size() - 1, -1, -1):
		var event: WorldEvent = events[i]
		if shown >= LOCATE_EACH:
			break
		if event.position != Vector2.INF and event.significance >= Config.events.major_from:
			add.call("events", EventText.line(event, session.people, session.events), event.position, 0)
			shown += 1
	if session.knowledge != null:
		for region in session.knowledge.found_regions():
			add.call("discoveries", region.name.substr(0, 1).to_upper() + region.name.substr(1), region.centre, 0)
	for prop in session.props.all_props():
		if prop.kind == PropData.Kind.RUIN:
			add.call("discoveries", UIText.prop_name(prop.kind, prop.variant), prop.position2d(), 0)
	return out


## The regions the world has found, the largest first: [[text, centre], …]
## ("the eastern hills · 40% explored").
static func regions(session: WorldSession) -> Array:
	var out: Array = []
	if session == null or session.knowledge == null:
		return out
	for region in session.knowledge.found_regions():
		out.append([MemoryText.translate("MENU_REGION_ROW").format({"name": region_name(session, region),
			"explored": roundi(session.knowledge.explored_share(region) * 100.0)}), region.centre])
	return out


## A region's name — in the home settlement's word for its kind, if it has
## one: "Tiravel (the river)" (M17.3).
static func region_name(session: WorldSession, region: Regions.Region) -> String:
	var name := region.name.substr(0, 1).to_upper() + region.name.substr(1)
	var home := session.settlements.home() if session.settlements != null else null
	if session.lexicon == null or home == null:
		return name
	var said := session.lexicon.word(home.id, [&"river", &"hills", &"valley"][region.kind])
	return MemoryText.translate("WORD_GLOSS").format({"word": said, "gloss": region.name}) if said != "" else name


## Asks before something that cannot simply be taken back (a page of its own).
func ask(text: String, yes_text: String, yes: Callable) -> void:
	_confirm = [text, yes_text, yes]
	open_page(PAGE_CONFIRM)


## The saved worlds other than this one, the newest first (SaveManager.worlds).
static func other_worlds(session: WorldSession) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for world in SaveManager.worlds():
		if session == null or world["world_id"] != session.world_id:
			out.append(world)
	return out


## "Year 3 · Spring · Day 4" of a game tick.
static func date_of(tick: int) -> String:
	return String(TranslationServer.translate(&"TIME_DATE")).format({"year": Config.time.year_of(tick),
		"season": GameClock.season_name(Config.time.season_of(tick)), "day": Config.time.day_of_season(tick)})


## A saved world in a line: "Seed 48213 · Year 3 · Spring · Day 4 · Saved 2 h ago".
static func world_text(world: Dictionary, now_unix: int) -> String:
	return MemoryText.translate("MENU_WORLD_ROW").format({"seed": int(world["seed"]), "date": date_of(int(world["game_tick"])),
		"saved": ago_text(int(world["saved_unix"]), now_unix)})


## A backup in a line: "Year 1 · Spring · Day 3 · Saved 4 min ago".
static func backup_text(backup: Dictionary, now_unix: int) -> String:
	return MemoryText.translate("MENU_BACKUP_ROW").format({"date": date_of(int(backup["game_tick"])),
		"saved": ago_text(int(backup["saved_unix"]), now_unix)})


## How long ago, in a word or two: "just now", "4 min ago", "2 h ago", "3 days ago".
static func ago_text(then_unix: int, now_unix: int) -> String:
	var ago := maxi(now_unix - then_unix, 0)
	if ago < 60:
		return MemoryText.translate("MENU_AGO_NOW")
	if ago < 3600:
		return MemoryText.translate("MENU_AGO_MINUTES").format({"count": ago / 60})
	if ago < 86400:
		return MemoryText.translate("MENU_AGO_HOURS").format({"count": ago / 3600})
	return MemoryText.translate("MENU_AGO_DAYS").format({"count": ago / 86400})


## When the world was last saved, in words: "Saved just now", "Saved 3 minutes ago".
static func saved_text(info: Dictionary, now_unix: int) -> String:
	if info.has("error"):
		return MemoryText.translate("MENU_SAVE_FAILED")
	if not info.has("unix"):
		return MemoryText.translate("MENU_NOT_SAVED")
	var ago := maxi(now_unix - int(info["unix"]), 0)
	if ago < 60:
		return MemoryText.translate("MENU_SAVED_NOW")
	if ago < 3600:
		return MemoryText.translate("MENU_SAVED_MINUTES").format({"count": ago / 60})
	return MemoryText.translate("MENU_SAVED_HOURS").format({"count": ago / 3600})


## The Important People, living and dead, the most significant first:
## [[id, "Mara Tirn" / "Huto (died in year 12)", what they are remembered for], …].
static func important(session: WorldSession) -> Array:
	var out: Array = []
	if session.significance == null:
		return out
	for id in session.significance.important_people():
		var person := session.people.get_person(id)
		var record := session.archive.get_record(id) if person == null else null
		var name := person.full_name() if person != null else MemoryText.translate("GRAVE_DEAD_NAME").format(
			{"name": record.full_name(), "year": HistoryText.year_of(record.death_tick)})
		var deed := session.significance.best_deed(id)
		out.append([id, name, EventText.line(deed, session.people, session.events) if deed != null else ""])
	return out


## The people the Individuals page lists now (its search, order and whom).
func _fill_individuals() -> void:
	for child in _people_rows.get_children():
		child.queue_free()
	var rows := individuals(_session, _people_query, _people_sort, _people_stage)
	for row: Array in rows:
		var id: int = row[0]
		var button := _make_entry(row[1], func() -> void: person_chosen.emit(id))
		_people_rows.add_child(button)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = MemoryText.translate("MENU_NOBODY_YET")
		_people_rows.add_child(empty)
	_settling = 3


## Everyone living, by name: [[id, "Ama · 34 · Forager"], …] — found by
## `query` (any case), in the order `sort` ("name", "age": the oldest first,
## "work"), only those of `stage` ("all", "children", "adults", "elders").
static func individuals(session: WorldSession, query: String = "", sort: StringName = &"name", stage: StringName = &"all") -> Array:
	var everyone := session.people.all_people()
	match sort:
		&"age":
			everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool:
				return a.birth_tick < b.birth_tick or (a.birth_tick == b.birth_tick and a.id < b.id))
		&"work":
			everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool:
				return String(a.occupation_id) < String(b.occupation_id) or (a.occupation_id == b.occupation_id and a.given_name < b.given_name))
		_:
			everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool:
				return a.given_name < b.given_name or (a.given_name == b.given_name and a.id < b.id))
	var out: Array = []
	var year := Config.time.ticks_per_year()
	var wanted := query.strip_edges().to_lower()
	var stages := {&"children": PersonData.LifeStage.CHILD, &"adults": PersonData.LifeStage.ADULT, &"elders": PersonData.LifeStage.ELDER}
	for person in everyone:
		var stage_now := person.life_stage(session.clock.tick, year, Config.people)
		var grouped := PersonData.LifeStage.CHILD if stage_now == PersonData.LifeStage.ADOLESCENT else stage_now
		if stages.has(stage) and grouped != stages[stage]:
			continue
		if wanted != "" and not person.full_name().to_lower().contains(wanted):
			continue
		var work := UIText.occupation_name(person.occupation_id) if person.occupation_id != &"" else UIText.life_stage_name(stage_now)
		out.append([person.id, MemoryText.translate("MENU_PERSON").format({"name": person.full_name(),
			"age": person.age_years(session.clock.tick, year), "work": work})])
	return out


## What everyone known to `person_id` is to them, the closest first:
## [[id, "Ama — mother · close"], …]. Family first, then by how much they like them.
static func relations_of(session: WorldSession, person_id: int) -> Array:
	var store := session.relationships
	var person := session.people.get_person(person_id)
	if store == null or person == null:
		return []
	var known := store.of(person_id)
	var ids: Array = known.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var fa := store.is_family(person_id, a)
		var fb := store.is_family(person_id, b)
		if fa != fb:
			return fa
		var aa := (known[a] as Relationship).affinity
		var ab := (known[b] as Relationship).affinity
		return aa > ab if aa != ab else a < b)
	var out: Array = []
	for other_id: int in ids:
		var other := session.people.get_person(other_id)
		if other == null:
			continue
		var record: Relationship = known[other_id]
		var what := _what(store.kinds(person_id, other_id), other.sex)
		out.append([other_id, MemoryText.translate("MENU_RELATION").format({"name": other.given_name, "what": what,
			"feeling": feeling_word(record.affinity)})])
	return out


## How someone feels about another, in a word.
static func feeling_word(affinity: float) -> String:
	if affinity >= 0.6:
		return MemoryText.translate("FEEL_CLOSE")
	if affinity >= 0.25:
		return MemoryText.translate("FEEL_WARM")
	if affinity > -0.15:
		return MemoryText.translate("FEEL_EASY")
	if affinity > -0.5:
		return MemoryText.translate("FEEL_COOL")
	return MemoryText.translate("FEEL_HOSTILE")


## What one is to the other, in a word (family first).
static func _what(kinds: int, sex: int) -> String:
	if kinds & Relationship.Kind.PARTNER:
		return UIText.relation_word(&"partner", sex).to_lower()
	if kinds & Relationship.Kind.PARENT:
		return UIText.relation_word(&"parent", sex).to_lower()
	if kinds & Relationship.Kind.CHILD:
		return UIText.relation_word(&"child", sex).to_lower()
	if kinds & Relationship.Kind.SIBLING:
		return UIText.relation_word(&"sibling", sex).to_lower()
	if kinds & Relationship.Kind.ENEMY:
		return MemoryText.translate("REL_ENEMY")
	if kinds & Relationship.Kind.RIVAL:
		return MemoryText.translate("REL_RIVAL")
	if kinds & Relationship.Kind.FRIEND:
		return MemoryText.translate("REL_FRIEND")
	if kinds & Relationship.Kind.ACQUAINTANCE:
		return MemoryText.translate("REL_ACQUAINTANCE")
	return MemoryText.translate("REL_STRANGER")


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = UITheme.DIM
	_list.add_child(label)


func _small(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = UITheme.DIM
	label.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
	_list.add_child(label)


func _line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(label)


## A setting that is on or off, as a button that says which: "Sound: on".
## `inverted`: the setting says the opposite (muted is sound off).
func _toggle(key: StringName, text_key: String, inverted: bool = false) -> void:
	var on := bool(Settings.get_value(key)) != inverted
	_entry(MemoryText.translate("MENU_SETTING").format({"name": MemoryText.translate(text_key),
		"value": MemoryText.translate("MOTION_ON" if on else "MOTION_OFF")}), func() -> void:
		Settings.set_value(key, not bool(Settings.get_value(key)))
		AudioManager.play_ui(&"ui_tap")
		_show())


## A volume, with − and + either side: "Ambience   80%".
func _volume(key: StringName) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = MemoryText.translate("MENU_" + String(key).replace("/", "_").to_upper())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := Label.new()
	value.text = "%d%%" % roundi(float(Settings.get_value(key)) * 100.0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(120.0, 0.0)
	for by: float in [-VOLUME_STEP, VOLUME_STEP]:
		var button := Button.new()
		button.text = "−" if by < 0.0 else "+"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(UITheme.TOUCH_TARGET * 0.7, UITheme.TOUCH_TARGET * 0.7)
		button.pressed.connect(func() -> void:
			Settings.set_value(key, snappedf(clampf(float(Settings.get_value(key)) + by, 0.0, 1.0), VOLUME_STEP))
			AudioManager.play_ui(&"ui_tap")
			_show())
		row.add_child(button)
		if by < 0.0:
			row.add_child(value)
	_list.add_child(row)


# --- building blocks for the pages (MenuPages) -------------------------------------------------------

func session() -> WorldSession:
	return _session


func set_title(text: String) -> void:
	_title.text = text


func add_heading(text: String) -> void:
	_heading(text)


func add_line(text: String) -> void:
	_line(text)


func add_small(text: String) -> void:
	_small(text)


func add_entry(text: String, pressed: Callable) -> void:
	_entry(text, pressed)


func add_toggle(key: StringName, text_key: String, inverted: bool = false) -> void:
	_toggle(key, text_key, inverted)


## A row of chips, one of them chosen: `options` [[label, value], …]; a tap
## chooses one (`picked.call(value)`) and the page is drawn again.
func add_chips(options: Array, chosen: Variant, picked: Callable) -> HFlowContainer:
	var row := HFlowContainer.new()
	for option: Array in options:
		var chip := Button.new()
		chip.text = option[0]
		chip.toggle_mode = true
		chip.button_pressed = option[1] == chosen
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.55)
		var value: Variant = option[1]
		chip.pressed.connect(func() -> void:
			AudioManager.play_ui(&"ui_tap")
			picked.call(value)
			for other in row.get_children():
				(other as Button).set_pressed_no_signal(other == chip))
		row.add_child(chip)
	_list.add_child(row)
	return row


## A card within the page: a title, its lines, and Locate when it has a place.
func add_detail(title: String, lines: PackedStringArray, at: Vector2) -> PanelContainer:
	var card := PanelContainer.new()
	var box := VBoxContainer.new()
	card.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var name := Label.new()
	name.text = title
	name.theme_type_variation = UITheme.TITLE
	name.add_theme_font_size_override(&"font_size", UITheme.FONT_BODY)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	if at.is_finite():
		var locate := Button.new()
		locate.name = "Locate"
		locate.text = MemoryText.translate("LOCATE")
		locate.focus_mode = Control.FOCUS_NONE
		locate.pressed.connect(func() -> void: place_chosen.emit(at))
		head.add_child(locate)
	for text in lines:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.theme_type_variation = UITheme.DIM
		label.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		box.add_child(label)
	_list.add_child(card)
	return card


func _entry(text: String, pressed: Callable) -> void:
	_list.add_child(_make_entry(text, pressed))


func _make_entry(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	# (Long lines — a saved world, a backup — wrap rather than lose their end.)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.7)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_PASS # (a drag on it scrolls the list)
	button.pressed.connect(pressed)
	return button


# --- for tests --------------------------------------------------------------------------------------

func title_text() -> String:
	return _title.text


## The page's entries (buttons), in order — on the first page, those of every
## section, open or not (as if its heading had been tapped).
func entries() -> Array[Button]:
	var out: Array[Button] = []
	var holders: Array = [_list]
	if page() == PAGE_INDIVIDUALS and is_instance_valid(_people_rows):
		holders = [_people_rows]
	for holder: Node in holders:
		for child in holder.get_children():
			if child.is_queued_for_deletion():
				continue
			if child is VBoxContainer and String(child.name).begins_with("Body_"):
				for inner in child.get_children():
					if inner is Button:
						out.append(inner)
			elif child is Button and not String(child.name).begins_with("Section_"):
				out.append(child)
	return out


## What the page shows, in order (buttons and lines; on the first page, the
## headings and what the open section holds).
func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _list.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is VBoxContainer and String(child.name).begins_with("Body_"):
			if (child as Control).visible:
				for inner in child.get_children():
					if inner is Button:
						out.append((inner as Button).text)
		elif child is Button:
			out.append((child as Button).text)
		elif child is Label:
			out.append((child as Label).text)
	return out


## Opens a section of the first page (as a tap on its heading would; "" closes it).
func open_section(key: String) -> void:
	_open_section = key
	if page() == PAGE_ROOT:
		_show()


func open_section_key() -> String:
	return _open_section


func tree() -> FamilyTree:
	for child in _list.get_children():
		if child is FamilyTree and not child.is_queued_for_deletion():
			return child
	return null
