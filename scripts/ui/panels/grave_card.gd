class_name GraveCard
extends UIPanel
## A grave, read (bible §16.3, §26.6 "Grave: Read · View Family"): who lies
## there, when they lived and what they died of, their work, what the world
## remembers them for, what they remembered most — and their family, each
## of whom can be gone to (the living) or read in turn (the dead).
##
## A card in the bottom-left corner, like the others; its list scrolls.

## Someone of the family was picked (living or dead).
signal person_chosen(person_id: int)
## Their family tree was asked for.
signal tree_requested(person_id: int)
## The grave is to be looked at (M13.5: Locate).
signal locate_requested(position: Vector2)

const MAX_WIDTH := 852.0
const EDGE_MARGIN := 32.0
const RESERVED_RIGHT := 196.0
const BOTTOM_MARGIN := 308.0
const LIST_MAX_HEIGHT := 760.0
const LIST_MIN_HEIGHT := 150.0
## The "Family tree" button under Family.
const TREE_BUTTON := &"FamilyTree"

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List
@onready var _close: Button = %Close

var _session: WorldSession
var _person_id := 0
var _family_first := false
var _settling := 0


func _ready() -> void:
	_close.pressed.connect(close)
	get_viewport().size_changed.connect(layout)
	refresh()


## Shows the grave of `person_id` (someone in the archive); `family_first`:
## opened to see their family (View family) rather than to read (Read).
func setup(session: WorldSession, person_id: int, family_first: bool = false) -> void:
	_session = session
	_person_id = person_id
	_family_first = family_first
	if is_node_ready():
		refresh()


func person_id() -> int:
	return _person_id


func _process(_delta: float) -> void:
	if _settling > 0:
		_settling -= 1
		layout()


func refresh() -> void:
	if _session == null or not is_node_ready() or is_closing():
		return
	var record := _session.archive.get_record(_person_id)
	if record == null:
		return
	var said := facts(_session, record)
	_title.text = said["name"]
	_subtitle.text = said["years"]
	for child in _list.get_children():
		child.queue_free()
	if _family_first:
		_add_family(said["family"])
		_add_lines(said["life"])
	else:
		_add_lines(said["life"])
		_add_heading(MemoryText.translate("GRAVE_REMEMBERED_FOR"))
		_add_lines(said["deeds"] if not (said["deeds"] as PackedStringArray).is_empty()
			else PackedStringArray([MemoryText.translate("GRAVE_QUIET_LIFE")]))
		if not (said["memories"] as PackedStringArray).is_empty():
			_add_heading(MemoryText.translate("GRAVE_REMEMBERED"))
			_add_lines(said["memories"])
		_add_family(said["family"])
	_settling = 3
	layout()


func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size.x = clampf(view.x - EDGE_MARGIN - RESERVED_RIGHT, 200.0, MAX_WIDTH)
	_scroll.custom_minimum_size.y = 0.0
	var rest := get_combined_minimum_size().y
	var room := minf(view.y - BOTTOM_MARGIN - EDGE_MARGIN - rest, LIST_MAX_HEIGHT)
	_scroll.custom_minimum_size.y = clampf(_list.get_combined_minimum_size().y, 0.0, maxf(room, LIST_MIN_HEIGHT))
	reset_size()
	position = Vector2(EDGE_MARGIN, view.y - BOTTOM_MARGIN - size.y)


# --- what is said ---------------------------------------------------------------------------------

## What the card says of someone who has died, as plain values:
##   name, years: String; life, deeds, memories: PackedStringArray;
##   family: Array of [person id, relation, name, living (bool)].
static func facts(session: WorldSession, record: HistoricalPerson) -> Dictionary:
	var life := PackedStringArray()
	life.append(cause_line(record))
	if record.occupation_id != &"":
		life.append(MemoryText.translate("GRAVE_WORK").format({"work": UIText.occupation_name(record.occupation_id)}))
	var deeds := PackedStringArray()
	for event_id in record.accomplishments:
		var event := session.events.get_event(event_id)
		if event != null:
			deeds.append(EventText.line(event, session.people, session.events))
	var memories := PackedStringArray()
	for memory in record.remembered():
		memories.append(MemoryText.capitalized(MemoryText.text(memory, session.people)))
	return {
		"name": record.full_name(),
		"years": years_line(record),
		"life": life,
		"deeds": deeds,
		"memories": memories,
		"family": family_of(session, record.id),
	}


## When they lived ("Year 3 – Year 41").
static func years_line(record: HistoricalPerson) -> String:
	# (Born before the world began: the band's own.)
	return MemoryText.translate("GRAVE_YEARS" if record.birth_tick >= 0 else "GRAVE_YEARS_BEFORE").format(
		{"born": HistoryText.year_of(record.birth_tick), "died": HistoryText.year_of(record.death_tick)})


## What they died of, and at what age.
static func cause_line(record: HistoricalPerson) -> String:
	var cause_key := "GRAVE_CAUSE_" + String(record.cause).to_upper()
	return MemoryText.translate(cause_key if MemoryText.has(cause_key) else "GRAVE_CAUSE").format(
		{"age": record.age_years(Config.time.ticks_per_year())})


## Someone's family, living or dead: parents, partner, children, brothers
## and sisters — [person id, relation, name, living], in that order.
static func family_of(session: WorldSession, id: int) -> Array:
	var out: Array = []
	var seen := {id: true}
	var person := session.people.get_person(id)
	var record := session.archive.get_record(id)
	var parents := person.parents if person != null else (record.parents if record != null else PackedInt64Array())
	var children := person.children if person != null else (record.children if record != null else PackedInt64Array())
	var partner := person.partner_id if person != null else (record.partner_id if record != null else 0)
	var relatives: Array = []
	for parent in parents:
		relatives.append([parent, &"parent"])
	if partner != 0:
		relatives.append([partner, &"partner"])
	# A partner who died before them (whose record names them).
	for other in session.archive.all_records():
		if other.partner_id == id:
			relatives.append([other.id, &"partner"])
	for child in children:
		relatives.append([child, &"child"])
	for parent in parents:
		for sibling in _children_of(session, parent):
			relatives.append([sibling, &"sibling"])
	for entry: Array in relatives:
		var other_id: int = entry[0]
		if seen.has(other_id):
			continue
		var living := session.people.get_person(other_id)
		var dead := session.archive.get_record(other_id) if living == null else null
		if living == null and dead == null:
			continue
		seen[other_id] = true
		var sex: int = living.sex if living != null else dead.sex
		var name: String = living.given_name if living != null else MemoryText.translate("GRAVE_DEAD_NAME").format(
			{"name": dead.given_name, "year": HistoryText.year_of(dead.death_tick)})
		out.append([other_id, UIText.relation_word(entry[1], sex), name, living != null])
	return out


static func _children_of(session: WorldSession, id: int) -> PackedInt64Array:
	var person := session.people.get_person(id)
	if person != null:
		return person.children
	var record := session.archive.get_record(id)
	return record.children if record != null else PackedInt64Array()


# --- building ---------------------------------------------------------------------------------------

func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = UITheme.DIM
	_list.add_child(label)


func _add_lines(lines: PackedStringArray) -> void:
	for text in lines:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		_list.add_child(label)


func _add_family(family: Array) -> void:
	_add_heading(MemoryText.translate("GRAVE_FAMILY"))
	var tree := Button.new()
	tree.text = MemoryText.translate("FAM_TREE")
	tree.name = TREE_BUTTON
	tree.focus_mode = Control.FOCUS_NONE
	tree.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.7)
	tree.pressed.connect(func() -> void: tree_requested.emit(_person_id))
	_list.add_child(tree)
	if family.is_empty():
		_add_lines(PackedStringArray([MemoryText.translate("GRAVE_NO_FAMILY")]))
		_add_locate()
		return
	for entry: Array in family:
		var button := Button.new()
		button.text = "%s  %s" % [entry[1], entry[2]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.7)
		button.pressed.connect(func() -> void: person_chosen.emit(entry[0]))
		_list.add_child(button)
	_add_locate()


## Where they lie (M13.5): a button that takes the camera there.
func _add_locate() -> void:
	var record := _session.archive.get_record(_person_id) if _session != null else null
	var grave := _session.props.get_prop(record.grave_id) if record != null and record.grave_id > 0 else null
	if grave == null:
		return
	var locate := Button.new()
	locate.text = MemoryText.translate("LOCATE")
	locate.name = "Locate"
	locate.focus_mode = Control.FOCUS_NONE
	locate.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.7)
	var at := grave.position2d()
	locate.pressed.connect(func() -> void: locate_requested.emit(at))
	_list.add_child(locate)


# --- for tests --------------------------------------------------------------------------------------

func title_text() -> String:
	return _title.text


func subtitle_text() -> String:
	return _subtitle.text


## What the list shows, in order (labels and buttons).
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _list.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
	return out


func family_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in _list.get_children():
		if child is Button and not child.is_queued_for_deletion() and child.name != TREE_BUTTON and child.name != "Locate":
			out.append(child)
	return out
