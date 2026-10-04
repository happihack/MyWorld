class_name MainMenu
extends UIPanel
## The ☰ menu (bible §26.5), v0 (VS.1): a panel that slides in from the left,
## with the sections there is something for — WORLD (Weather, Statistics), PEOPLE
## (Individuals, Families, Relationships, Important People), HISTORY (Timeline:
## the recent events, a tap looks for them; Important People, Firsts), PLAYER
## (Interaction History, with its counts) and SETTINGS (Audio, Haptics, Motion
## while motion controls are on, Save). Other sections (CIVILIZATION, Map…)
## stay hidden until their systems exist (the menu grows with the
## world). Each entry opens a page in the panel; Back goes a page back.

## Someone was picked (living: go to them; dead: read their grave).
signal person_chosen(person_id: int)
## The motion settings were asked for.
signal motion_requested
## The timeline was asked for (M11.3).
signal timeline_requested
## The statistics were asked for (VS.2).
signal statistics_requested
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

## The volumes on the Audio page, and how far a step moves them.
const VOLUMES: Array[StringName] = [&"audio/master", &"audio/ambience", &"audio/sfx", &"audio/ui"]
const VOLUME_STEP := 0.1
## How many days back the Weather page tells of rain.
const RAIN_DAYS := 7

const EDGE_MARGIN := 24.0
const TOP := 40.0
const MAX_WIDTH := 820.0
const SLIDE_SECONDS := 0.18

var _session: WorldSession
var _stack: Array = [] # [page, argument, second argument]
var _title: Label
var _back: Button
var _close: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _settling := 0
var _slide: Tween


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
	# As tall as what it lists (no more of the world covered than needs be), scrolling beyond.
	var tallest := view.y - TOP - EDGE_MARGIN - 300.0
	_scroll.custom_minimum_size.y = 0.0
	var rest := get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, 0.0, maxf(tallest - rest, 120.0))
	custom_minimum_size = Vector2(clampf(view.x * 0.82, 300.0, MAX_WIDTH), 0.0)
	reset_size()
	position.y = TOP
	if _slide == null or not _slide.is_running():
		position.x = EDGE_MARGIN


# --- the pages --------------------------------------------------------------------------------------

func _show() -> void:
	for child in _list.get_children():
		child.queue_free()
	_scroll.scroll_vertical = 0
	var entry: Array = _stack[-1]
	_back.visible = _stack.size() > 1
	_settling = 3
	match StringName(entry[0]):
		PAGE_ROOT:
			_title.text = MemoryText.translate("MENU_TITLE")
			if _session != null and _session.weather != null:
				_heading(MemoryText.translate("MENU_WORLD"))
				_entry(MemoryText.translate("MENU_WEATHER"), func() -> void: open_page(PAGE_WEATHER))
				_entry(MemoryText.translate("MENU_STATISTICS"), func() -> void: statistics_requested.emit())
			_heading(MemoryText.translate("MENU_PEOPLE"))
			_entry(MemoryText.translate("MENU_INDIVIDUALS"), func() -> void: open_page(PAGE_INDIVIDUALS))
			_entry(MemoryText.translate("MENU_FAMILIES"), func() -> void: open_page(PAGE_FAMILIES))
			_entry(MemoryText.translate("MENU_RELATIONSHIPS"), func() -> void: open_page(PAGE_RELATIONSHIPS))
			_entry(MemoryText.translate("MENU_IMPORTANT"), func() -> void: open_page(PAGE_IMPORTANT))
			_heading(MemoryText.translate("MENU_HISTORY"))
			_entry(MemoryText.translate("MENU_TIMELINE"), func() -> void: timeline_requested.emit())
			_entry(MemoryText.translate("MENU_IMPORTANT"), func() -> void: open_page(PAGE_IMPORTANT))
			_entry(MemoryText.translate("MENU_FIRSTS"), func() -> void: open_page(PAGE_FIRSTS))
			_heading(MemoryText.translate("MENU_PLAYER"))
			_entry(MemoryText.translate("MENU_INTERACTIONS"), func() -> void: history_requested.emit())
			_heading(MemoryText.translate("MENU_SETTINGS"))
			_entry(MemoryText.translate("MENU_AUDIO"), func() -> void: open_page(PAGE_AUDIO))
			_entry(MemoryText.translate("MENU_HAPTICS"), func() -> void: open_page(PAGE_HAPTICS))
			if SensorManager.feature_enabled():
				_entry(MemoryText.translate("MENU_MOTION"), func() -> void: motion_requested.emit())
			_entry(MemoryText.translate("MENU_SAVE"), func() -> void: open_page(PAGE_SAVE))
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
		PAGE_INDIVIDUALS:
			_title.text = MemoryText.translate("MENU_INDIVIDUALS")
			for row: Array in individuals(_session):
				var id: int = row[0]
				_entry(row[1], func() -> void: person_chosen.emit(id))
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


## Everyone living, by name: [[id, "Ama · 34 · Forager"], …].
static func individuals(session: WorldSession) -> Array:
	var everyone := session.people.all_people()
	everyone.sort_custom(func(a: PersonData, b: PersonData) -> bool:
		return a.given_name < b.given_name or (a.given_name == b.given_name and a.id < b.id))
	var out: Array = []
	var year := Config.time.ticks_per_year()
	for person in everyone:
		var stage := person.life_stage(session.clock.tick, year, Config.people)
		var work := UIText.occupation_name(person.occupation_id) if person.occupation_id != &"" else UIText.life_stage_name(stage)
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


func _entry(text: String, pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.7)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(pressed)
	_list.add_child(button)


# --- for tests --------------------------------------------------------------------------------------

func title_text() -> String:
	return _title.text


## The page's entries (buttons) and lines (labels), in order.
func entries() -> Array[Button]:
	var out: Array[Button] = []
	for child in _list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			out.append(child)
	return out


func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _list.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Button:
			out.append((child as Button).text)
		elif child is Label:
			out.append((child as Label).text)
	return out


func tree() -> FamilyTree:
	for child in _list.get_children():
		if child is FamilyTree and not child.is_queued_for_deletion():
			return child
	return null
