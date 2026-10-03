class_name AiInspector
extends PanelContainer
## Debug: what one person is doing and why (bible §13.4 "the debug AI
## inspector"), and the commands to try things by hand — freeze everyone,
## bring someone new into the world, make the inspected person think, or
## take them out of it.
##
## Lives on the debug overlay's layer and is only there while the overlay is
## shown. It shows whoever the player has selected (see Main).

## Bring a newcomer into the world / take this person out of it.
signal spawn_requested
signal kill_requested(person_id: int)
## The player closed the inspector on this person (its X).
signal dismissed

const REFRESH_INTERVAL_S := 0.25
const FONT_SIZE := 22
const BUTTON_HEIGHT := 84.0
## How far above the bottom of the screen the panel ends (clear of the tool bar).
const BOTTOM_MARGIN := 300.0
const BAR_CELLS := 10

var _session: WorldSession
var _person_id := 0
var _label: Label
var _freeze: Button
var _think: Button
var _kill: Button
var _close: Button
var _refresh_timer := 0.0
var _buttons: Dictionary = {} # command -> Button


func _init() -> void:
	name = "AiInspector"
	add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.86) # (it may lie over the overlay's own text)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	add_theme_stylebox_override(&"panel", style)
	var column := VBoxContainer.new()
	add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	column.add_child(row)
	_freeze = _button(row, "Freeze AI", _on_freeze)
	_buttons[&"freeze"] = _freeze
	_buttons[&"spawn"] = _button(row, "Spawn", func() -> void: spawn_requested.emit())
	_think = _button(row, "Think", _on_think)
	_kill = _button(row, "Kill", func() -> void: kill_requested.emit(_person_id))
	_close = _button(row, "X", func() -> void:
		clear()
		dismissed.emit())
	_buttons[&"think"] = _think
	_buttons[&"kill"] = _kill
	_buttons[&"close"] = _close
	_label = Label.new()
	_label.name = "Text"
	_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_label.add_theme_color_override(&"font_color", Color(0.85, 1, 0.85))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_label)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = 16.0
	offset_bottom = -BOTTOM_MARGIN
	offset_top = -BOTTOM_MARGIN


func _ready() -> void:
	EventBus.person_died.connect(_on_person_died)


func _exit_tree() -> void:
	if EventBus.person_died.is_connected(_on_person_died):
		EventBus.person_died.disconnect(_on_person_died)


func _on_person_died(person_id: int, _cause: StringName) -> void:
	if person_id == _person_id:
		clear()


func bind(session: WorldSession) -> void:
	_session = session
	_person_id = 0
	refresh()


## Shows this person.
func inspect(person_id: int) -> bool:
	if _session == null or not _session.is_active or not _session.people.has_person(person_id):
		return false
	_person_id = person_id
	refresh()
	return true


## Stops inspecting anyone.
func clear() -> void:
	_person_id = 0
	refresh()


## Ends this far above the bottom of the screen (clear of the tool bar, and
## of a person's card when one is open).
func set_bottom_margin(margin: float) -> void:
	if not is_equal_approx(offset_bottom, -margin):
		offset_bottom = -margin
		offset_top = -margin


## Who is being inspected (0 = nobody).
func inspected_id() -> int:
	return _person_id


func text() -> String:
	return _label.text


## One of the command buttons, by what it does: "freeze", "spawn", "think",
## "kill", "close" (for tests).
func button(command: StringName) -> Button:
	return _buttons.get(command)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL_S
		refresh()


## Rebuilds the text now.
func refresh() -> void:
	var person := _session.people.get_person(_person_id) if _session != null and _session.is_active and _person_id != 0 else null
	if person == null and _person_id != 0:
		_person_id = 0 # they are gone
	_think.visible = person != null
	_kill.visible = person != null
	_close.visible = person != null
	var frozen := _session != null and _session.behavior != null and not _session.behavior.enabled
	_freeze.text = "Unfreeze AI" if frozen else "Freeze AI"
	if person == null:
		_label.text = "AI FROZEN — tap a person to inspect them" if frozen else "tap a person to inspect them"
	else:
		_label.text = describe(_session, person)


# --- what is said about a person ----------------------------------------------------------------

## How a person took something they noticed: what it was, what they made of
## it (with the runners-up), what they felt and what they did.
static func describe_outcome(outcome: Reactions.Outcome) -> String:
	var made := PackedStringArray()
	var ids: Array = outcome.interpretation_scores.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool:
		var sa: float = outcome.interpretation_scores[a]
		var sb: float = outcome.interpretation_scores[b]
		return sa > sb or (sa == sb and String(a) < String(b)))
	for id: StringName in ids.slice(0, 4):
		made.append("%s %.2f%s" % [id, float(outcome.interpretation_scores[id]), "*" if id == outcome.interpretation else ""])
	var felt := PackedStringArray()
	for emotion in mini(outcome.emotions.size(), ReactionTable.EMOTION_COUNT):
		felt.append("%s %.2f" % [String(ReactionTable.EMOTION_NAMES[emotion]).left(3), outcome.emotions[emotion]])
	return "noticed: %s%s  salience %.2f -> %s%s\n  made of it: %s\n  felt: %s" % [outcome.stimulus.type,
		" (direct)" if outcome.direct else "", outcome.salience, outcome.reaction, " +tell" if outcome.tells else "",
		"  ".join(made), "  ".join(felt)]

## Everything the inspector shows about `person`, as text.
static func describe(session: WorldSession, person: PersonData) -> String:
	var lines := PackedStringArray()
	var now := session.clock.tick
	var year := Config.time.ticks_per_year()
	var stage := person.life_stage(now, year, Config.people)
	lines.append("%s  %s %d  %s  #%d  tier %d%s" % [person.full_name(), "F" if person.sex == PersonData.Sex.FEMALE else "M",
		person.age_years(now, year), UIText.occupation_name(person.occupation_id) if person.occupation_id != &"" else UIText.life_stage_name(stage),
		person.id, person.sim_tier, "  INDOORS" if person.has_flag(PersonData.FLAG_INDOORS) else ""])
	lines.append("%s   mood %.2f  stress %.2f  at %s" % [", ".join(UIText.trait_words(person.traits)), person.mood, person.stress, person.position])
	for need in mini(person.needs.size(), Needs.COUNT):
		lines.append("%-8s %s %.2f" % [Needs.NAMES[need], bar(person.needs[need]), person.needs[need]])
	# What they are doing, and the steps of it.
	var activity := BehaviorSystem.activity_of(person)
	var since := now - int(person.current_action.get("since", now))
	lines.append("doing: %s  (%s, for %d min, begun at %.2f)" % [
		PersonCard.activity_line(person) if activity != &"" else "nothing",
		activity, since, float(person.current_action.get("score", 0.0))])
	# Who they are close to, and at odds with.
	if session.relationships != null:
		var close := PackedStringArray()
		var known := session.relationships.of(person.id)
		var ids: Array = known.keys()
		ids.sort_custom(func(x: int, y: int) -> bool: return (known[x] as Relationship).affinity > (known[y] as Relationship).affinity)
		for other_id: int in ids.slice(0, 4):
			var other := session.people.get_person(other_id)
			var record: Relationship = known[other_id]
			close.append("%s %+.2f%s" % [other.given_name if other != null else "#%d" % other_id, record.affinity,
				" friend" if record.has_kind(Relationship.Kind.FRIEND) else (" RIVAL" if record.has_kind(Relationship.Kind.RIVAL) else "")])
		lines.append("knows %d: %s" % [known.size(), ", ".join(close)])
	# Their family and health.
	var partner := session.people.name_of(person.partner_id) if person.partner_id != 0 else "-"
	var carrying := Hardship.condition_of(person, Lifecycle.PREGNANT)
	var injuries := PackedStringArray()
	for injury: Variant in person.injuries:
		if typeof(injury) == TYPE_DICTIONARY:
			injuries.append("%s %.2f" % [str(injury.get("kind", "")), float(injury.get("severity", 0.0))])
	lines.append("significance %.2f%s" % [person.significance, "  IMPORTANT" if session.significance != null and session.significance.is_important(person.id) else ""])
	lines.append("life: partner %s, %d children, household %d%s%s%s  (dies today: %.4f)" % [partner, person.children.size(),
		person.household_id,
		"  WITH CHILD (%d days)" % ((now - int(carrying.get("since", now))) / TimeConfig.MINUTES_PER_DAY) if not carrying.is_empty() else "",
		"  hurt: " + ", ".join(injuries) if not injuries.is_empty() else "",
		"  ILL (%s)" % str(Health.illness_of(person).get("kind", "")) if Health.is_ill(person) else "",
		float(session.lifecycle.death_chance(person, now)[0]) if session.lifecycle != null else 0.0])
	# What they remember.
	if session.memories != null and not person.memory_ids.is_empty():
		var latest := session.memories.recent(person, 1)[0]
		lines.append("remembers %d; last: %s  (imp %.2f fid %.2f, %s)" % [person.memory_ids.size(), MemoryText.text(latest, session.people),
			latest.importance, latest.fidelity, String(Memory.Source.keys()[latest.source]).to_lower()])
	# How they took the last thing they noticed.
	var outcome := session.behavior.last_outcome(person.id)
	if outcome != null:
		lines.append(describe_outcome(outcome))
	var steps: Variant = person.current_action.get("steps")
	if typeof(steps) == TYPE_ARRAY:
		var index := int(person.current_action.get("index", 0))
		for i in (steps as Array).size():
			if typeof((steps as Array)[i]) == TYPE_DICTIONARY:
				lines.append("%s %s" % [">" if i == index else " ", describe_step((steps as Array)[i])])
	if session.movement.is_walking(person.id):
		lines.append("walking: %s" % ("waiting for the way" if session.movement.is_waiting(person.id)
			else "%d tiles to go" % session.movement.remaining_path(person.id).size()))
	# How the last weighing up came out.
	var decision := session.behavior.last_decision(person.id)
	if decision == null:
		lines.append("scores: (nothing decided in this session yet)")
	else:
		var ids: Array = decision.scores.keys()
		ids.sort_custom(func(a: StringName, b: StringName) -> bool:
			var sa: float = decision.scores[a]
			var sb: float = decision.scores[b]
			return sa > sb or (sa == sb and String(a) < String(b)))
		var parts := PackedStringArray()
		for id: StringName in ids:
			var score: float = decision.scores[id]
			parts.append("%s %s%s" % [id, "%.2f" % score if score >= 0.0 else "--", "*" if id == decision.activity else ""])
		lines.append("scores: " + "  ".join(parts.slice(0, 4)))
		if parts.size() > 4:
			lines.append("        " + "  ".join(parts.slice(4)))
	lines.append("looked up %d times  waiting %.1f min  temperature %.3f" % [session.behavior.looked_up.get(person.id, 0),
		session.simulation.pending_minutes(person.id), Brain.temperature(person)])
	return "\n".join(lines)


## One step of a plan, in a line.
static func describe_step(step: Dictionary) -> String:
	var kind := str(step.get("type", "?"))
	var parts := PackedStringArray([kind])
	for key: String in ["target", "at", "partner", "kind"]:
		if step.has(key) and not (key == "target" and kind == "work"):
			parts.append("%s %s" % [key, step[key]])
	if step.has("minutes"):
		parts.append("%.0f/%.0f min" % [float(step.get("elapsed", 0.0)), float(step["minutes"])])
	elif step.has("elapsed"):
		parts.append("%.0f min" % float(step["elapsed"]))
	return "  ".join(parts)


## A value 0 … 1 as a bar of BAR_CELLS characters.
static func bar(value: float) -> String:
	var filled := clampi(roundi(value * BAR_CELLS), 0, BAR_CELLS)
	return "[%s%s]" % ["#".repeat(filled), ".".repeat(BAR_CELLS - filled)]


# --- internals ----------------------------------------------------------------------------------

func _button(row: HBoxContainer, caption: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.add_theme_font_size_override(&"font_size", 26)
	button.pressed.connect(pressed)
	row.add_child(button)
	return button


func _on_freeze() -> void:
	if _session != null and _session.behavior != null:
		_session.behavior.enabled = not _session.behavior.enabled
		refresh()


func _on_think() -> void:
	var person := _session.people.get_person(_person_id) if _session != null else null
	if person != null:
		_session.behavior.think(person)
		refresh()
