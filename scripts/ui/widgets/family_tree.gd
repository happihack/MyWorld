class_name FamilyTree
extends VBoxContainer
## A family across generations (spec §16, bible §16.2: "family trees are
## always reconstructible from parents/children ids, including the dead"):
## a forebear, and under them their children, and theirs, each line drawn
## in. The living are named with their age, the dead with the year they
## died; partners stand beside the one they are partnered to. Every name is
## a tap away: the living are gone to, the dead are read (their grave).
##
##   Mara (died in year 12) & Jon
##   ├─ Tomas, 34 & Ana
##   │  ├─ Elia, 9
##   │  └─ Jon, 6
##   └─ Sara, 30
##      └─ David, 2

## Someone in the tree was picked (living or dead).
signal person_chosen(person_id: int)

## How far each generation is set in.
const INDENT := 44.0

var _session: WorldSession
var _highlight := 0


## Shows the family that descends from `root`; `highlight` is drawn out (0: nobody).
func show_family(session: WorldSession, root: int, highlight: int = 0) -> void:
	_session = session
	_highlight = highlight
	for child in get_children():
		child.queue_free()
	for row: Dictionary in rows(session, root):
		_add_row(row)


# --- the tree as data ---------------------------------------------------------------------------

## The rows of the tree under `root`, top to bottom:
##   {"id", "depth", "name" (as shown), "living": bool, "prefix": the lines before it ("│  ├─ ")}.
## Everyone once, even if two lines of the family meet again.
##   "trail": for each generation above, whether its line goes on past this
##   row (drawn as a vertical line); "last": the last of its brothers and sisters.
static func rows(session: WorldSession, root: int) -> Array:
	var out: Array = []
	_walk(session, root, 0, "", true, [], {}, out)
	return out


static func _walk(session: WorldSession, id: int, depth: int, lead: String, last: bool, trail: Array, seen: Dictionary,
		out: Array) -> void:
	if seen.has(id) or not _known(session, id):
		return
	seen[id] = true
	var prefix := "" if depth == 0 else lead + ("└─ " if last else "├─ ")
	out.append({"id": id, "depth": depth, "name": label_of(session, id), "living": session.people.has_person(id),
		"prefix": prefix, "trail": trail.duplicate(), "last": last})
	var children: Array[int] = []
	for child in children_of(session, id):
		if not seen.has(child) and _known(session, child):
			children.append(child)
	var next := "" if depth == 0 else lead + ("   " if last else "│  ")
	var next_trail := trail.duplicate()
	if depth > 0:
		next_trail.append(not last)
	for n in children.size():
		_walk(session, children[n], depth + 1, next, n == children.size() - 1, next_trail, seen, out)


## "Tomas, 34 & Ana" / "Mara (died in year 12)".
static func label_of(session: WorldSession, id: int) -> String:
	var text := name_with_years(session, id)
	var partner := partner_of(session, id)
	if partner != 0 and _known(session, partner):
		text = MemoryText.translate("FAM_WITH").format({"name": text, "partner": session.people.name_of(partner)})
	return text


static func name_with_years(session: WorldSession, id: int) -> String:
	var person := session.people.get_person(id)
	if person != null:
		return MemoryText.translate("FAM_LIVING").format({"name": person.given_name,
			"age": person.age_years(session.clock.tick, Config.time.ticks_per_year())})
	var record := session.archive.get_record(id)
	if record == null:
		return MemoryText.translate("EVENT_SOMEONE")
	return MemoryText.translate("GRAVE_DEAD_NAME").format({"name": record.given_name, "year": HistoryText.year_of(record.death_tick)})


## Their children (living or dead), the eldest first.
static func children_of(session: WorldSession, id: int) -> Array[int]:
	var person := session.people.get_person(id)
	var record := session.archive.get_record(id) if person == null else null
	var ids: PackedInt64Array = person.children if person != null else (record.children if record != null else PackedInt64Array())
	var out: Array[int] = []
	for child in ids:
		if not out.has(child):
			out.append(child)
	out.sort_custom(func(a: int, b: int) -> bool:
		var ta: Variant = _birth(session, a)
		var tb: Variant = _birth(session, b)
		if ta == null or tb == null or ta == tb:
			return a < b
		return int(ta) < int(tb))
	return out


## Their partner: now, or when they died — or, for someone widowed, the one
## who died (0: none).
static func partner_of(session: WorldSession, id: int) -> int:
	var person := session.people.get_person(id)
	if person != null and person.partner_id != 0:
		return person.partner_id
	var record := session.archive.get_record(id)
	if record != null and record.partner_id != 0:
		return record.partner_id
	for other in session.archive.all_records():
		if other.partner_id == id:
			return other.id
	return 0


static func parents_of(session: WorldSession, id: int) -> PackedInt64Array:
	var person := session.people.get_person(id)
	if person != null:
		return person.parents
	var record := session.archive.get_record(id)
	return record.parents if record != null else PackedInt64Array()


## The furthest known forebear of someone (themselves if they have none):
## up the first parent there is, as far as anyone is known.
static func root_of(session: WorldSession, id: int) -> int:
	var at := id
	for guard in 64:
		var up := 0
		for parent in parents_of(session, at):
			if _known(session, parent):
				up = parent
				break
		if up == 0:
			return at
		at = up
	return at


## The families of the world: one for each forebear nobody knows the parents
## of, who has children or is still alive (a couple counts once) — the
## eldest first. [root id, …].
static func families(session: WorldSession) -> Array[int]:
	var candidates: Array[int] = []
	for person in session.people.all_people():
		candidates.append(person.id)
	for record in session.archive.all_records():
		candidates.append(record.id)
	var roots: Array[int] = []
	var taken := {}
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var ta: Variant = _birth(session, a)
		var tb: Variant = _birth(session, b)
		if ta == null or tb == null or ta == tb:
			return a < b
		return int(ta) < int(tb))
	for id in candidates:
		if taken.has(id):
			continue
		var known_parent := false
		for parent in parents_of(session, id):
			known_parent = known_parent or _known(session, parent)
		if known_parent:
			continue
		if children_of(session, id).is_empty() and not session.people.has_person(id):
			continue
		# (Someone who joined a family as a partner is of that family.)
		var partner := partner_of(session, id)
		var joined := false
		for parent in parents_of(session, partner):
			joined = joined or _known(session, parent)
		if joined:
			continue
		taken[id] = true
		if partner != 0:
			taken[partner] = true
		roots.append(id)
	return roots


## "The Skadou family" — and how many of it live and have died.
static func family_title(session: WorldSession, root: int) -> String:
	var person := session.people.get_person(root)
	var record := session.archive.get_record(root) if person == null else null
	var family_name: String = person.family_name if person != null else (record.family_name if record != null else "")
	if family_name == "":
		family_name = name_with_years(session, root)
	var living := 0
	var dead := 0
	for row: Dictionary in rows(session, root):
		if bool(row["living"]):
			living += 1
		else:
			dead += 1
		var partner := partner_of(session, int(row["id"]))
		if partner != 0 and _known(session, partner):
			if session.people.has_person(partner):
				living += 1
			else:
				dead += 1
	return MemoryText.translate("FAM_TITLE").format({"name": family_name, "living": living, "dead": dead})


static func _known(session: WorldSession, id: int) -> bool:
	return id > 0 and (session.people.has_person(id) or session.archive.get_record(id) != null)


static func _birth(session: WorldSession, id: int) -> Variant:
	var person := session.people.get_person(id)
	if person != null:
		return person.birth_tick
	var record := session.archive.get_record(id)
	return record.birth_tick if record != null else null


# --- drawing ----------------------------------------------------------------------------------------

func _add_row(row: Dictionary) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 0)
	if int(row["depth"]) > 0:
		var lines := Connector.new()
		lines.trail = row["trail"]
		lines.last = row["last"]
		lines.prefix = row["prefix"]
		lines.custom_minimum_size = Vector2(INDENT * int(row["depth"]), 0.0)
		lines.size_flags_vertical = Control.SIZE_EXPAND_FILL
		line.add_child(lines)
	var button := Button.new()
	button.text = row["name"]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.flat = not bool(row["living"])
	button.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.7)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if int(row["id"]) == _highlight:
		button.add_theme_color_override(&"font_color", UITheme.RIM)
	var id: int = row["id"]
	button.pressed.connect(func() -> void: person_chosen.emit(id))
	line.add_child(button)
	add_child(line)


## The lines of the tree before a name: for each generation above, its line
## going on down (if it does), and the elbow to this one.
class Connector:
	extends Control
	var trail: Array = []
	var last := true
	## The same, as text (for tests and logs).
	var prefix := ""

	func _draw() -> void:
		var width := maxf(2.0, UITheme.TOUCH_TARGET * 0.02)
		var color := UITheme.LINE
		var mid := size.y * 0.5
		for n in trail.size():
			if bool(trail[n]):
				var x := (n + 0.5) * FamilyTree.INDENT
				draw_line(Vector2(x, 0.0), Vector2(x, size.y), color, width)
		var x := (trail.size() + 0.5) * FamilyTree.INDENT
		draw_line(Vector2(x, 0.0), Vector2(x, size.y if not last else mid), color, width)
		draw_line(Vector2(x, mid), Vector2(size.x, mid), color, width)


## For tests: the rows' texts as shown ("├─ Tomas, 34").
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	for line in get_children():
		if line.is_queued_for_deletion():
			continue
		var text := ""
		for part in line.get_children():
			if part is Connector:
				text += (part as Connector).prefix
			elif part is Button:
				text += (part as Button).text
		out.append(text)
	return out
