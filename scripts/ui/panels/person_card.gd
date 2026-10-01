class_name PersonCard
extends UIPanel
## Who someone is and what they are about (bible §26.6): a sheet at the
## bottom of the screen with three heights —
##   PEEK  who, and what they are doing and why;
##   HALF  + age, occupation, mood, needs, nature, what the player can do;
##   FULL  + family (each of them a tap away).
## The header is a handle: drag it up or down, or tap it. The card follows
## the person as they live (refreshed four times a second) and closes with
## its ✕, the back button, or when the person is gone.
##
## (Recent memory and the "Today" timeline join when people have memories and
## days: M5.4, M6.4. What is not there yet is not shown.)

enum State { PEEK, HALF, FULL }

## The player chose to do something with the person: &"observe", &"touch",
## &"focus", &"mark".
signal action(action: StringName, person_id: int)
## The player tapped one of the person's family.
signal person_chosen(person_id: int)
signal state_changed(state: State)

const REFRESH_INTERVAL_S := 0.25
const MAX_WIDTH := 1016.0
const EDGE_MARGIN := 32.0
## Room kept free below: the card sits above the tool bar's row.
const BOTTOM_MARGIN := 308.0
## A drag of the header by this much (canvas units) changes the height.
const DRAG_STEP := 70.0

const ACTION_OBSERVE := &"observe"
const ACTION_TOUCH := &"touch"
const ACTION_FOCUS := &"focus"
const ACTION_MARK := &"mark"

@onready var _header: Control = %Header
@onready var _glyph: PersonGlyph = %Glyph
@onready var _name: Label = %Name
@onready var _activity: Label = %Activity
@onready var _mark: StarButton = %Mark
@onready var _close: Button = %Close
@onready var _body: Control = %Body
@onready var _about: Label = %About
@onready var _needs: GridContainer = %Needs
@onready var _traits: Label = %Traits
@onready var _actions: HBoxContainer = %Actions
@onready var _more: Control = %More
@onready var _family: VBoxContainer = %Family

var _session: WorldSession
var _person_id := 0
var _state: State = State.PEEK
var _bars: Array[NeedBar] = []
var _buttons: Dictionary = {} # action -> Button
var _family_shown: Array = []
var _observing := false
var _refresh_timer := 0.0
var _press_y := NAN
var _dragged := false


func _ready() -> void:
	_close.pressed.connect(close)
	_mark.pressed.connect(func() -> void: action.emit(ACTION_MARK, _person_id))
	_header.gui_input.connect(_on_header_input)
	for need in Needs.COUNT:
		var label := Label.new()
		label.text = UIText.need_label(Needs.NAMES[need])
		label.theme_type_variation = UITheme.DIM
		_needs.add_child(label)
		var bar := NeedBar.new()
		_needs.add_child(bar)
		_bars.append(bar)
	for entry: Array in [[ACTION_OBSERVE, "Observe"], [ACTION_TOUCH, "Touch"], [ACTION_FOCUS, "Focus"]]:
		var button := Button.new()
		button.text = entry[1]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.8)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_action_pressed.bind(entry[0]))
		_actions.add_child(button)
		_buttons[entry[0]] = button
	var more := Button.new()
	more.text = "More"
	more.focus_mode = Control.FOCUS_NONE
	more.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.8)
	more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	more.pressed.connect(func() -> void: set_state(State.HALF if _state == State.FULL else State.FULL))
	_actions.add_child(more)
	_buttons[&"more"] = more
	get_viewport().size_changed.connect(layout)
	_apply_state()


## Shows `person_id` of `session`, at `state`.
func setup(session: WorldSession, person_id: int, state: State = State.PEEK) -> void:
	_session = session
	_person_id = person_id
	_state = state
	_family_shown = []
	if is_node_ready():
		_apply_state()
		refresh()


func person_id() -> int:
	return _person_id


func state() -> State:
	return _state


func set_state(new_state: State) -> void:
	if new_state == _state:
		return
	_state = new_state
	_apply_state()
	refresh()
	state_changed.emit(_state)


## Lights the Observe button while the person is being observed.
func set_observing(observing: bool) -> void:
	_observing = observing
	if _buttons.has(ACTION_OBSERVE):
		(_buttons[ACTION_OBSERVE] as Button).text = "Observing" if observing else "Observe"


func is_observing() -> bool:
	return _observing


## One of the buttons: &"observe", &"touch", &"focus", &"more", &"mark",
## &"close" (for tests).
func button(which: StringName) -> Button:
	if which == &"mark":
		return _mark
	if which == &"close":
		return _close
	return _buttons.get(which)


## The buttons of the family members shown (FULL), in order.
func family_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in _family.get_children():
		if child is Button and not child.is_queued_for_deletion():
			out.append(child)
	return out


func name_text() -> String:
	return _name.text


func activity_text() -> String:
	return _activity.text


func about_text() -> String:
	return _about.text


func traits_text() -> String:
	return _traits.text


## The needs as shown: one value per Needs.Need.
func need_values() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for bar in _bars:
		out.append(bar.value)
	return out


func _process(delta: float) -> void:
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL_S
		refresh()


## Brings the card up to date with the person. Closes it if they are gone.
func refresh() -> void:
	if _session == null or not is_node_ready() or is_closing():
		return
	var person := _session.people.get_person(_person_id) if _session.is_active else null
	if person == null:
		close()
		return
	var shown := facts(_session, person)
	_glyph.show_person(person, shown["stage"])
	_name.text = shown["name"]
	_activity.text = shown["activity"]
	_mark.marked = shown["marked"]
	if _state == State.PEEK:
		layout()
		return
	_about.text = " · ".join(PackedStringArray([shown["age"], shown["occupation"], shown["mood"]]))
	var needs: PackedFloat32Array = shown["needs"]
	for need in mini(needs.size(), _bars.size()):
		_bars[need].value = needs[need]
	_traits.text = " · ".join(shown["traits"]) if not (shown["traits"] as PackedStringArray).is_empty() else "Unremarkable"
	if _state == State.FULL and _family_shown != shown["family"]:
		_family_shown = shown["family"]
		_show_family(_family_shown)
	layout()


## Sits at the bottom of the screen, above the tool bar, as wide as it may.
func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size.x = clampf(view.x - EDGE_MARGIN * 2.0, 200.0, MAX_WIDTH)
	reset_size()
	position = Vector2(EDGE_MARGIN, view.y - BOTTOM_MARGIN - size.y)


# --- what is said about a person ----------------------------------------------------------------

## What the card shows about `person`, as plain values:
##   name, age, occupation, activity, mood: String; stage: PersonData.LifeStage;
##   needs: PackedFloat32Array; traits: PackedStringArray; marked: bool;
##   family: Array of [person id, relation, name] (those still in the world).
static func facts(session: WorldSession, person: PersonData) -> Dictionary:
	var now := session.clock.tick
	var year := Config.time.ticks_per_year()
	var stage := person.life_stage(now, year, Config.people)
	var doing := BehaviorSystem.activity_of(person)
	var family: Array = []
	var seen := {}
	var relatives: Array = [[person.partner_id, &"partner"]]
	for parent_id in person.parents:
		relatives.append([parent_id, &"parent"])
	for child_id in person.children:
		relatives.append([child_id, &"child"])
	for entry: Array in relatives:
		var relative := session.people.get_person(entry[0])
		if relative != null and not seen.has(relative.id):
			seen[relative.id] = true
			family.append([relative.id, UIText.relation_word(entry[1], relative.sex), relative.given_name])
	return {
		"name": person.full_name(),
		"stage": stage,
		"age": UIText.age_text(person.age_years(now, year)),
		"occupation": UIText.occupation_name(person.occupation_id) if person.occupation_id != &"" else UIText.life_stage_name(stage),
		"activity": UIText.activity_phrase(doing, BehaviorSystem.reason_of(person)) if doing != &"" else UIText.ACTIVITY_NAMES[&"idle"],
		"mood": UIText.mood_word(person.mood, person.stress),
		"needs": Needs.sanitized(person.needs, person.id),
		"traits": UIText.trait_words(person.traits),
		"marked": person.has_flag(PersonData.FLAG_MARKED_IMPORTANT),
		"family": family,
	}


# --- internals ----------------------------------------------------------------------------------

func _apply_state() -> void:
	_body.visible = _state != State.PEEK
	_more.visible = _state == State.FULL
	if _buttons.has(&"more"):
		(_buttons[&"more"] as Button).text = "Less" if _state == State.FULL else "More"


func _show_family(family: Array) -> void:
	for child in _family.get_children():
		child.queue_free()
	if family.is_empty():
		var alone := Label.new()
		alone.text = "No family here"
		alone.theme_type_variation = UITheme.DIM
		_family.add_child(alone)
		return
	for entry: Array in family:
		var button := Button.new()
		button.text = "%s  %s" % [entry[1], entry[2]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.7)
		button.pressed.connect(func() -> void: person_chosen.emit(entry[0]))
		_family.add_child(button)


func _on_action_pressed(which: StringName) -> void:
	action.emit(which, _person_id)


## The header is a handle: a tap toggles between the short card and the
## middle one; a drag up or down goes a height up or down (down from the
## shortest closes the card).
func _on_header_input(event: InputEvent) -> void:
	var y := NAN
	var pressed := false
	var released := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		y = (event as InputEventMouseButton).global_position.y
		pressed = (event as InputEventMouseButton).pressed
		released = not pressed
	elif event is InputEventScreenTouch:
		y = (event as InputEventScreenTouch).position.y
		pressed = (event as InputEventScreenTouch).pressed
		released = not pressed
	elif event is InputEventMouseMotion and not is_nan(_press_y):
		y = (event as InputEventMouseMotion).global_position.y
	elif event is InputEventScreenDrag and not is_nan(_press_y):
		y = (event as InputEventScreenDrag).position.y
	if is_nan(y):
		return
	if pressed:
		_press_y = y
		_dragged = false
		return
	if is_nan(_press_y):
		return
	var moved := y - _press_y
	if absf(moved) >= DRAG_STEP:
		_dragged = true
		_press_y = y
		_step(-1 if moved > 0.0 else 1)
	if released:
		if not _dragged:
			set_state(State.HALF if _state == State.PEEK else State.PEEK)
		_press_y = NAN


## One height up (+1) or down (-1); down from the shortest closes.
func _step(direction: int) -> void:
	var next := int(_state) + direction
	if next < 0:
		close()
	else:
		set_state(mini(next, State.FULL) as State)
