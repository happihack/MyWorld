class_name PersonCard
extends UIPanel
## Who someone is and what they are about (bible §26.6): a sheet at the
## bottom of the screen with three heights —
##   PEEK  who, and what they are doing and why;
##   HALF  + age, occupation, mood, needs, nature, the last thing they
##         remember, what the player can do;
##   FULL  + family (each of them a tap away) and what they remember.
## The header is a handle: drag it up or down, or tap it. The card follows
## the person as they live (refreshed four times a second) and closes with
## its ✕, the back button, or when the person is gone.
##
## (The "Today" timeline joins when people have days: M6.4.)

enum State { PEEK, HALF, FULL }

## The player chose to do something with the person: &"observe", &"touch",
## &"follow", &"focus", &"mark".
signal action(action: StringName, person_id: int)
## The player tapped one of the person's family.
signal person_chosen(person_id: int)
signal state_changed(state: State)

const REFRESH_INTERVAL_S := 0.25
const MAX_WIDTH := 1016.0
const EDGE_MARGIN := 32.0
## Room kept free below: the card sits above the tool bar's row.
const BOTTOM_MARGIN := 308.0
## The lower part of the full card is never squeezed below this.
const MORE_MIN_HEIGHT := 150.0
## A drag of the header by this much (canvas units) changes the height.
const DRAG_STEP := 70.0

const ACTION_OBSERVE := &"observe"
const ACTION_TOUCH := &"touch"
const ACTION_FOLLOW := &"follow"
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
@onready var _more_scroll: ScrollContainer = %MoreScroll
@onready var _family: VBoxContainer = %Family
@onready var _memory: Label = %Memory
@onready var _memories: VBoxContainer = %Memories

var _session: WorldSession
var _person_id := 0
var _state: State = State.PEEK
var _bars: Array[NeedBar] = []
var _buttons: Dictionary = {} # action -> Button
var _family_shown: Array = []
var _memories_shown := PackedStringArray()
## How many memories the full card lists.
const MEMORIES_SHOWN := 5
var _observing := false
var _following := false
var _refresh_timer := 0.0
var _settling := 0
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
	_actions.add_theme_constant_override(&"separation", 0)
	for entry: Array in [[ACTION_OBSERVE, "Observe"], [ACTION_TOUCH, "Touch"], [ACTION_FOLLOW, "Follow"], [ACTION_FOCUS, "Focus"]]:
		var button := Button.new()
		button.text = entry[1]
		button.focus_mode = Control.FOCUS_NONE
		if entry[0] == ACTION_OBSERVE or entry[0] == ACTION_FOLLOW:
			# On or off: shown by a rim around the word, not by another word
			# (five words have to fit in a row).
			button.toggle_mode = true
			button.add_theme_stylebox_override(&"pressed", _on_style())
			button.add_theme_stylebox_override(&"hover_pressed", _on_style())
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
	_memories_shown = PackedStringArray(["?"]) # (not what anyone remembers: shown anew)
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
		(_buttons[ACTION_OBSERVE] as Button).set_pressed_no_signal(observing)


func is_observing() -> bool:
	return _observing


## Lights the Follow button while the camera follows the person.
func set_following(following: bool) -> void:
	_following = following
	if _buttons.has(ACTION_FOLLOW):
		(_buttons[ACTION_FOLLOW] as Button).set_pressed_no_signal(following)


func is_following() -> bool:
	return _following


## One of the buttons: &"observe", &"touch", &"follow", &"focus", &"more", &"mark",
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


## The last thing they remember, as shown on the half card ("" if nothing).
func memory_text() -> String:
	return _memory.text if _memory.visible else ""


## What they remember, as listed on the full card (the most recent first).
func memory_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _memories.get_children():
		if child is Label and not child.is_queued_for_deletion():
			out.append((child as Label).text)
	return out


## The needs as shown: one value per Needs.Need.
func need_values() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for bar in _bars:
		out.append(bar.value)
	return out


func _process(delta: float) -> void:
	# Wrapped text only knows how tall it is once it has been given its
	# width: after anything is rebuilt the card is laid out again for a few frames.
	if _settling > 0:
		_settling -= 1
		layout()
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
	var remembered: PackedStringArray = shown["memories"]
	_memory.visible = not remembered.is_empty() and _state == State.HALF
	if not remembered.is_empty():
		_memory.text = remembered[0]
	if _state == State.FULL and _family_shown != shown["family"]:
		_family_shown = shown["family"]
		_show_family(_family_shown)
	if _state == State.FULL and _memories_shown != remembered:
		_memories_shown = remembered
		_show_memories(remembered)
	layout()


## Sits at the bottom of the screen, above the tool bar, as wide as it may.
func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size.x = clampf(view.x - EDGE_MARGIN * 2.0, 200.0, MAX_WIDTH)
	# The lower part (family, memories) takes the room there is and scrolls
	# if that is not enough: the card never leaves the screen.
	_more_scroll.custom_minimum_size.y = 0.0
	if _more_scroll.visible:
		var rest := get_combined_minimum_size().y
		var room := view.y - BOTTOM_MARGIN - EDGE_MARGIN - rest
		_more_scroll.custom_minimum_size.y = clampf(_more.get_combined_minimum_size().y, 0.0, maxf(room, MORE_MIN_HEIGHT))
	reset_size()
	position = Vector2(EDGE_MARGIN, view.y - BOTTOM_MARGIN - size.y)


# --- what is said about a person ----------------------------------------------------------------

## What the card shows about `person`, as plain values:
##   name, age, occupation, activity, mood: String; stage: PersonData.LifeStage;
##   needs: PackedFloat32Array; traits: PackedStringArray; marked: bool;
##   family: Array of [person id, relation, name] (those still in the world);
##   memories: PackedStringArray, the most recent first ("Age 23 · Felt …").
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
		"activity": activity_line(person),
		"mood": UIText.mood_word(person.mood, person.stress),
		"needs": Needs.sanitized(person.needs, person.id),
		"traits": UIText.trait_words(person.traits),
		"marked": person.has_flag(PersonData.FLAG_MARKED_IMPORTANT),
		"family": family,
		"memories": memory_lines_of(session, person, MEMORIES_SHOWN),
	}


## What a person remembers, in lines, the most recent first.
static func memory_lines_of(session: WorldSession, person: PersonData, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	if session.memories == null:
		return out
	for memory in session.memories.recent(person, count):
		out.append(MemoryText.line(memory, person, session.people))
	return out


## What the person is doing and why, in a line. Someone reacting to
## something: what they do about it and what they make of it.
static func activity_line(person: PersonData) -> String:
	var doing := BehaviorSystem.activity_of(person)
	if doing == BehaviorSystem.ACTIVITY_REACT:
		return UIText.reaction_phrase(BehaviorSystem.reaction_of(person), BehaviorSystem.reason_of(person))
	if doing == &"":
		return UIText.ACTIVITY_NAMES[&"idle"]
	return UIText.activity_phrase(doing, BehaviorSystem.reason_of(person))


# --- internals ----------------------------------------------------------------------------------

func _apply_state() -> void:
	_settling = 3
	_body.visible = _state != State.PEEK
	_more_scroll.visible = _state == State.FULL
	if _buttons.has(&"more"):
		(_buttons[&"more"] as Button).text = "Less" if _state == State.FULL else "More"


func _show_family(family: Array) -> void:
	_settling = 3
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


func _show_memories(lines: PackedStringArray) -> void:
	_settling = 3
	for child in _memories.get_children():
		child.queue_free()
	if lines.is_empty():
		lines = PackedStringArray([MemoryText.translate("MEM_NONE")])
	for text in lines:
		var label := Label.new()
		label.text = text
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override(&"font_size", UITheme.FONT_SMALL)
		_memories.add_child(label)


func _on_action_pressed(which: StringName) -> void:
	# A toggle shows what is so, not what was pressed: whoever answers the
	# action says which it is (set_observing, set_following).
	if which == ACTION_OBSERVE:
		(_buttons[which] as Button).set_pressed_no_signal(_observing)
	elif which == ACTION_FOLLOW:
		(_buttons[which] as Button).set_pressed_no_signal(_following)
	action.emit(which, _person_id)


## The look of a button whose action is going on.
static func _on_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.82, 0.36, 0.16)
	style.border_color = StarButton.LIT
	style.set_border_width_all(3)
	style.set_corner_radius_all(20)
	style.content_margin_left = UITheme.BUTTON_PAD
	style.content_margin_right = UITheme.BUTTON_PAD
	return style


## The header is a handle: a tap toggles between the short card and the
## middle one; a drag up or down goes a height up or down (down from the
## shortest closes the card).
func _on_header_input(event: InputEvent) -> void:
	# On a touch screen every touch arrives twice: as itself and as the mouse
	# it is made to stand in for. One of them is enough.
	if (event is InputEventMouse) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var y := NAN
	var pressed := false
	var released := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		y = (event as InputEventMouseButton).position.y
		pressed = (event as InputEventMouseButton).pressed
		released = not pressed
	elif event is InputEventScreenTouch:
		y = (event as InputEventScreenTouch).position.y
		pressed = (event as InputEventScreenTouch).pressed
		released = not pressed
	elif event is InputEventMouseMotion and not is_nan(_press_y):
		y = (event as InputEventMouseMotion).position.y
	elif event is InputEventScreenDrag and not is_nan(_press_y):
		y = (event as InputEventScreenDrag).position.y
	if is_nan(y):
		return
	# Positions come relative to the header, which moves as the card grows:
	# measured on the screen, a still finger stays still.
	y += _header.global_position.y
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
