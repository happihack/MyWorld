class_name UIRoot
extends CanvasLayer
## Root of all in-game UI (HUD, cards, menus, toasts; bible §26.4).
##
## Panels (cards, menus) live on a stack: the back button closes the top one,
## and only leaves the game when none is open. A panel blocks touches only
## where it is; the rest of the screen still belongs to the world.
##
## Also keeps the UI the same physical size in portrait and landscape.

## The player asked to return to the settlement.
signal home_pressed
## The player chose an action in the context menu opened for `target`.
signal context_action(action: StringName, target: Picker.Result)
## The player chose to do something with the person on the card (see PersonCard).
signal person_action(action: StringName, person_id: int)
## The player picked a person in the UI (family on a card, a marked name).
signal person_chosen(person_id: int)
## The card of this person was closed.
signal person_card_closed(person_id: int)
## "Show" was pressed on a toast: look at this place (world X/Z).
signal locate_requested(position: Vector2)
## An event on the timeline was tapped (M11.3): look for it.
signal event_chosen(event_id: int)
## A disaster was chosen and confirmed (see DisasterCard): bring it down
## where the camera looks.
signal disaster_requested(kind: StringName)
## Another world is to be opened (VS.3; see MainMenu.world_requested).
signal world_requested(plan: Dictionary, erase_this: bool)

const CONTEXT_MENU := preload("res://scenes/ui/panels/context_menu.tscn")
const INSPECT_CARD := preload("res://scenes/ui/panels/inspect_card.tscn")
const PERSON_CARD := preload("res://scenes/ui/person_card.tscn")
const HISTORY_CARD := preload("res://scenes/ui/panels/history_card.tscn")
const GRAVE_CARD := preload("res://scenes/ui/panels/grave_card.tscn")
const CEMETERY_CARD := preload("res://scenes/ui/panels/cemetery_card.tscn")
const TIMELINE := preload("res://scenes/ui/panels/timeline.tscn")
const TOOL_BAR := preload("res://scenes/ui/tool_bar.tscn")
const CALIBRATION := preload("res://scenes/ui/calibration.tscn")
## Upper limit of the UI scale (see ui_scale_for).
const MAX_UI_SCALE := 3.0
## Room between the round buttons of the right-hand column.
const CORNER_GAP := 24.0

## Tapping the version label this many times within UNLOCK_WINDOW_MS toggles
## Settings "debug/enabled" (makes debug tools reachable in release builds).
const UNLOCK_TAPS := 7
const UNLOCK_WINDOW_MS := 3000

@onready var _version_label: Label = %VersionLabel
@onready var _home_button: Button = %HomeButton

## What "leave the game" does; tests replace it so they don't quit the runner.
var quit_action: Callable = func() -> void: get_tree().quit()

var _session: WorldSession
var _unlock_taps: Array[int] = []
var _panel_layer: Control
var _panels: Array[UIPanel] = [] # bottom to top
var _hint_label: HintLabel
var _hints: HintDirector
var _tool_bar: ToolBar
var _pins: PinList
var _follow_banner: FollowBanner
var _journal_button: JournalButton
## The disasters (the owner's design, 2026-10-05): the button in the column,
## and the row of them that slides out to its left.
var _disaster_button: DisasterButton
var _disaster_bar: DisasterBar
var _bar_slide: Tween
## The minimap (M13.3): bottom right, above the journal.
var _minimap: Minimap
## Where the camera is asked to go (Main): Callable(world_xz: Vector2, animate: bool).
var camera_mover: Callable
var _speed_control: SpeedControl
var _toasts: ToastStack
var _menu_button: MenuButtonRound
## Milestones waiting for their card (one at a time; none while the game is in the background).
var _milestones: Array[Notice] = []
var _in_background := false


func _ready() -> void:
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	_version_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_version_label.add_to_group(InputRouter.UI_BLOCKER_GROUP)
	_version_label.gui_input.connect(_on_version_label_input)
	_home_button.pressed.connect(func() -> void:
		_tick()
		home_pressed.emit())
	EventBus.back_requested.connect(_on_back_requested)
	NotificationManager.posted.connect(func(notice: Notice) -> void:
		if notice.is_milestone():
			_milestones.append(notice)
			show_next_milestone())
	EventBus.app_paused.connect(func() -> void: _in_background = true)
	EventBus.app_resumed.connect(func() -> void:
		_in_background = false
		show_next_milestone())
	_panel_layer = Control.new()
	_panel_layer.name = "Panels"
	_panel_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE # only panels take touches
	add_child(_panel_layer)
	_hint_label = HintLabel.new()
	_hint_label.name = "Hint"
	add_child(_hint_label)
	move_child(_hint_label, _panel_layer.get_index()) # panels draw over the hint
	_tool_bar = TOOL_BAR.instantiate()
	add_child(_tool_bar)
	move_child(_tool_bar, _panel_layer.get_index()) # panels draw over the bar
	_tool_bar.tool_selected.connect(func(_id: StringName) -> void: _tick())
	_pins = PinList.new()
	add_child(_pins)
	move_child(_pins, _panel_layer.get_index()) # panels draw over the list
	_pins.chosen.connect(func(person_id: int) -> void:
		_tick()
		person_chosen.emit(person_id))
	# Home, then the journal (the same size): top right, under the clock and
	# the weather (placed by _place_corner).
	_home_button.anchor_top = 0.0
	_home_button.anchor_bottom = 0.0
	_journal_button = JournalButton.new()
	_journal_button.anchor_left = 1.0
	_journal_button.anchor_right = 1.0
	_journal_button.offset_left = _home_button.offset_left
	_journal_button.offset_right = _home_button.offset_right
	add_child(_journal_button)
	move_child(_journal_button, _panel_layer.get_index())
	_journal_button.pressed.connect(func() -> void:
		_tick()
		toggle_history())
	_disaster_button = DisasterButton.new()
	_disaster_button.anchor_left = 1.0
	_disaster_button.anchor_right = 1.0
	add_child(_disaster_button)
	move_child(_disaster_button, _panel_layer.get_index())
	_disaster_button.pressed.connect(func() -> void:
		_tick()
		toggle_disasters())
	_disaster_bar = DisasterBar.new()
	_disaster_bar.visible = false
	add_child(_disaster_bar)
	move_child(_disaster_bar, _panel_layer.get_index())
	_disaster_bar.chosen.connect(func(kind: StringName) -> void:
		_tick()
		warn_of_disaster(kind))
	# The minimap: bottom right, just above the row of tools, its corner kept
	# as it folds.
	_minimap = Minimap.new()
	_minimap.anchor_left = 1.0
	_minimap.anchor_right = 1.0
	_minimap.anchor_top = 1.0
	_minimap.anchor_bottom = 1.0
	_minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_minimap.offset_bottom = -(ToolBar.BOTTOM_MARGIN + ToolButton.SIZE + CORNER_GAP)
	_minimap.offset_top = _minimap.offset_bottom - Minimap.SIDE
	add_child(_minimap)
	move_child(_minimap, _panel_layer.get_index())
	_minimap.move_camera = func(world_xz: Vector2, animate: bool) -> void:
		if camera_mover.is_valid():
			camera_mover.call(world_xz, animate)
	# The clock and the speed of the world: top right.
	_speed_control = SpeedControl.new()
	add_child(_speed_control)
	move_child(_speed_control, _panel_layer.get_index())
	_speed_control.speed_chosen.connect(func(index: int) -> void:
		_tick()
		set_speed(index))
	_speed_control.selector_requested.connect(func() -> void:
		_tick()
		open_speed_selector())
	_speed_control.resized.connect(_place_corner)
	get_viewport().size_changed.connect(_place_corner)
	_place_corner()
	_follow_banner = FollowBanner.new()
	add_child(_follow_banner)
	move_child(_follow_banner, _panel_layer.get_index()) # panels draw over it
	for pressed: Signal in [_follow_banner.follow_pressed, _follow_banner.stop_pressed, _follow_banner.locate_pressed]:
		pressed.connect(_tick)
	# The menu, top left.
	_menu_button = MenuButtonRound.new()
	add_child(_menu_button)
	move_child(_menu_button, _panel_layer.get_index())
	_menu_button.pressed.connect(func() -> void:
		_tick()
		toggle_menu())
	# What the player is told as it happens: between the marked people and
	# the clock, below the banner.
	_toasts = ToastStack.new()
	add_child(_toasts)
	move_child(_toasts, _panel_layer.get_index()) # panels draw over them
	_toasts.keep_clear_of(_pins, _speed_control, _follow_banner, [_home_button, _journal_button, _disaster_button])
	_toasts.locate_requested.connect(func(position: Vector2) -> void:
		_tick()
		locate_requested.emit(position))
	_hints = HintDirector.new(_hint_label)
	_hints.name = "HintDirector"
	add_child(_hints)
	get_window().size_changed.connect(_apply_ui_scale)
	_apply_ui_scale()


func _exit_tree() -> void:
	get_window().content_scale_factor = 1.0


# --- panels ---------------------------------------------------------------------------

func tool_bar() -> ToolBar:
	return _tool_bar


## First-time hints; feed it what the player does.
func hints() -> HintDirector:
	return _hints


## Puts a panel on top of the stack and shows it.
func open_panel(panel: UIPanel) -> void:
	_panels.append(panel)
	panel.closed.connect(_on_panel_closed.bind(panel))
	_panel_layer.add_child(panel)
	_update_hints()


## Closes the top panel. False if none is open.
func close_top_panel() -> bool:
	if _panels.is_empty():
		return false
	_panels[-1].close()
	return true


## "The box is settling…" (M20): over everything while the time away is lived.
func open_settling() -> SettlingOverlay:
	var overlay := SettlingOverlay.new()
	open_panel(overlay)
	return overlay


## WHILE YOU WERE GONE (M20): what happened in the box while the player was away.
func open_while_you_were_gone(summary: Dictionary) -> WhileYouWereGone:
	var card := WhileYouWereGone.new()
	card.setup(summary)
	open_panel(card)
	AudioManager.play_ui(&"chime")
	card.locate_requested.connect(func(at: Vector2) -> void:
		_tick()
		locate_requested.emit(at))
	card.timeline_requested.connect(func() -> void:
		_tick()
		open_timeline.call_deferred())
	return card


func while_you_were_gone() -> WhileYouWereGone:
	for panel: UIPanel in _panels:
		if panel is WhileYouWereGone and not panel.is_closing():
			return panel
	return null


## The next milestone waiting, on its card — unless one is open already, or the
## game is in the background (it waits for the player's return).
func show_next_milestone() -> MilestoneCard:
	if _in_background or _milestones.is_empty() or milestone_card() != null:
		return null
	var card := MilestoneCard.new()
	card.setup(_milestones.pop_front())
	open_panel(card)
	AudioManager.play_ui(&"chime")
	card.locate_requested.connect(func(at: Vector2) -> void:
		_tick()
		locate_requested.emit(at))
	card.closed.connect(func() -> void:
		_tick()
		show_next_milestone.call_deferred())
	return card


func milestone_card() -> MilestoneCard:
	for panel: UIPanel in _panels:
		if panel is MilestoneCard and not panel.is_closing():
			return panel
	return null


func close_all_panels() -> void:
	for panel: UIPanel in _panels.duplicate():
		panel.close()


## Closes panels that only live until the world is touched (the context menu).
## Returns true if any was open.
func dismiss_transient_panels() -> bool:
	var closed_any := false
	for panel: UIPanel in _panels.duplicate():
		if panel.transient:
			panel.close()
			closed_any = true
	return closed_any


func panel_count() -> int:
	return _panels.size()


func top_panel() -> UIPanel:
	return _panels[-1] if not _panels.is_empty() else null


## The long-press menu for `target`, next to the finger at `anchor`.
## `what` describes the target; `actions` are InteractionManager action ids.
func open_context_menu(anchor: Vector2, target: Picker.Result, what: InteractionResponse,
		actions: Array[StringName]) -> ContextMenu:
	dismiss_transient_panels()
	var entries: Array[Dictionary] = []
	for action in actions:
		entries.append({"id": action, "label": UIText.action_label(action, what.touch_effect)})
	var menu: ContextMenu = CONTEXT_MENU.instantiate()
	open_panel(menu)
	menu.setup(UIText.subject_name(what), entries)
	menu.place_near(anchor, Rect2(Vector2.ZERO, _panel_layer.get_viewport_rect().size))
	menu.action_chosen.connect(func(action: StringName) -> void:
		_tick()
		context_action.emit(action, target))
	return menu


## Who the camera follows, and who can be found (top of the screen).
func follow_banner() -> FollowBanner:
	return _follow_banner


## The names of the people marked as important.
func pins() -> PinList:
	return _pins


## The button that opens the menu.
func menu_button() -> MenuButtonRound:
	return _menu_button


## The ☰ menu (bible §26.5), in place of any other card.
func open_menu() -> MainMenu:
	var open := main_menu()
	if open != null:
		return open
	close_all_panels()
	var menu := MainMenu.new()
	open_panel(menu)
	menu.setup(_session)
	# (The toasts wait while the menu is open: they would show through it.)
	_toasts.visible = false
	menu.closed.connect(func() -> void: _toasts.visible = true)
	menu.person_chosen.connect(func(id: int) -> void:
		_tick()
		menu.close() # (to them, or to their grave)
		person_chosen.emit(id))
	menu.motion_requested.connect(func() -> void:
		_tick()
		open_motion_settings())
	menu.timeline_requested.connect(func() -> void:
		_tick()
		open_timeline())
	menu.timeline_filter_requested.connect(func(filter: StringName) -> void:
		_tick()
		open_timeline().set_filter(filter))
	menu.statistics_requested.connect(func() -> void:
		_tick()
		open_statistics())
	menu.map_requested.connect(func() -> void:
		_tick()
		open_map())
	menu.place_chosen.connect(func(world_xz: Vector2) -> void:
		_tick()
		menu.close()
		if camera_mover.is_valid():
			camera_mover.call(world_xz, true))
	menu.world_requested.connect(func(plan: Dictionary, erase_this: bool) -> void:
		menu.close()
		world_requested.emit(plan, erase_this))
	menu.history_requested.connect(func() -> void:
		_tick()
		close_all_panels()
		open_history(_session))
	return menu


## The world's history, year by year (in place of any other card).
func open_timeline() -> TimelinePanel:
	var open := timeline()
	if open != null:
		return open
	close_all_panels()
	var panel: TimelinePanel = TIMELINE.instantiate()
	open_panel(panel)
	panel.setup(_session)
	_toasts.visible = false
	panel.closed.connect(func() -> void: _toasts.visible = true)
	panel.event_chosen.connect(func(id: int) -> void:
		_tick()
		event_chosen.emit(id))
	return panel


## The world's numbers (VS.2), in place of any other card.
func open_statistics() -> StatsPanel:
	var open := statistics()
	if open != null:
		return open
	close_all_panels()
	var panel := StatsPanel.new()
	open_panel(panel)
	panel.setup(_session)
	_toasts.visible = false
	panel.closed.connect(func() -> void: _toasts.visible = true)
	return panel


func statistics() -> StatsPanel:
	for panel: UIPanel in _panels:
		if panel is StatsPanel and not panel.is_closing():
			return panel
	return null


func timeline() -> TimelinePanel:
	for panel: UIPanel in _panels:
		if panel is TimelinePanel and not panel.is_closing():
			return panel
	return null


func toggle_menu() -> void:
	var open := main_menu()
	if open != null:
		open.close()
	else:
		open_menu()


func main_menu() -> MainMenu:
	for panel: UIPanel in _panels:
		if panel is MainMenu and not panel.is_closing():
			return panel
	return null


## The family tree of someone's family (from their furthest known forebear),
## with them drawn out — in the menu, under People → Families.
func open_family_tree(person_id: int) -> MainMenu:
	if _session == null or not (_session.people.has_person(person_id) or _session.archive.get_record(person_id) != null):
		return null
	var menu := open_menu()
	menu.open_page(MainMenu.PAGE_FAMILIES)
	menu.open_page(MainMenu.PAGE_TREE, FamilyTree.root_of(_session, person_id), person_id)
	return menu


## The motion settings, in place of any other card.
func open_motion_settings() -> MotionSettingsPanel:
	var open := motion_settings()
	if open != null or not SensorManager.feature_enabled():
		return open
	close_all_panels()
	var panel := MotionSettingsPanel.new()
	open_panel(panel)
	panel.calibrate_requested.connect(func() -> void:
		_tick()
		open_calibration())
	return panel


## Opens the motion settings, or closes them if they are open.
func toggle_motion_settings() -> void:
	var open := motion_settings()
	if open != null:
		open.close()
	else:
		open_motion_settings()


func motion_settings() -> MotionSettingsPanel:
	for panel: UIPanel in _panels:
		if panel is MotionSettingsPanel and not panel.is_closing():
			return panel
	return null


## The calibration screen, on top of whatever is open (closing it comes
## back to that).
func open_calibration() -> CalibrationPanel:
	var open := calibration_panel()
	if open != null or not SensorManager.feature_enabled():
		return open
	var panel: CalibrationPanel = CALIBRATION.instantiate()
	open_panel(panel)
	return panel


func calibration_panel() -> CalibrationPanel:
	for panel: UIPanel in _panels:
		if panel is CalibrationPanel and not panel.is_closing():
			return panel
	return null


## The toasts: what the player is told as it happens.
func toasts() -> ToastStack:
	return _toasts


## The card of a person; replaces any card that is already open. If it is
## their card that is open, it is kept (and raised to `state` if that is
## higher).
func open_person_card(session: WorldSession, person_id: int, state: PersonCard.State = PersonCard.State.PEEK) -> PersonCard:
	var open := person_card()
	if open != null and open.person_id() == person_id:
		if state > open.state():
			open.set_state(state)
		return open
	for panel: UIPanel in _panels.duplicate():
		if panel is InspectCard or panel is PersonCard or panel is HistoryCard:
			panel.close()
	var card: PersonCard = PERSON_CARD.instantiate()
	card.setup(session, person_id, state)
	open_panel(card)
	card.refresh()
	card.action.connect(func(action: StringName, id: int) -> void:
		_tick()
		person_action.emit(action, id))
	card.person_chosen.connect(func(id: int) -> void:
		_tick()
		person_chosen.emit(id))
	card.tree_requested.connect(func(id: int) -> void:
		_tick()
		open_family_tree(id))
	card.closed.connect(func() -> void: person_card_closed.emit(person_id))
	return card


## The clock and speed button of the HUD.
func speed_control() -> SpeedControl:
	return _speed_control


## Runs the world at a speed (GameClock.SPEED_*).
func set_speed(index: int) -> void:
	if _session != null and _session.is_active:
		_session.clock.set_speed(index)


## The four speeds to choose from, under the speed button.
func open_speed_selector() -> SpeedSelector:
	var open := speed_selector()
	if open != null:
		return open
	dismiss_transient_panels()
	var selector := SpeedSelector.new()
	open_panel(selector)
	selector.set_current(_session.clock.speed_index if _session != null and _session.is_active else GameClock.SPEED_NORMAL)
	selector.place_under(_speed_control.speed_button().get_global_rect())
	selector.chosen.connect(func(index: int) -> void:
		_tick()
		set_speed(index))
	return selector


func speed_selector() -> SpeedSelector:
	for panel: UIPanel in _panels:
		if panel is SpeedSelector and not panel.is_closing():
			return panel
	return null


## The button that opens the player's history.
func minimap() -> Minimap:
	return _minimap


## The map (M13.3), in place of any other card.
func open_map() -> MapPanel:
	for panel: UIPanel in _panels:
		if panel is MapPanel and not panel.is_closing():
			return panel
	close_all_panels()
	var panel := MapPanel.new()
	panel.move_camera = camera_mover
	open_panel(panel)
	panel.setup(_session)
	_toasts.visible = false
	panel.closed.connect(func() -> void: _toasts.visible = true)
	return panel


func map_panel() -> MapPanel:
	for panel: UIPanel in _panels:
		if panel is MapPanel and not panel.is_closing():
			return panel
	return null


func journal_button() -> JournalButton:
	return _journal_button


## The player's history, in place of any other card.
func open_history(session: WorldSession = null) -> HistoryCard:
	var open := history_card()
	if open != null:
		return open
	for panel: UIPanel in _panels.duplicate():
		if panel is InspectCard or panel is PersonCard or panel is HistoryCard:
			panel.close()
	var card: HistoryCard = HISTORY_CARD.instantiate()
	card.setup(session if session != null else _session)
	open_panel(card)
	card.layout()
	return card


## Opens the history, or closes it if it is open.
func toggle_history() -> void:
	var open := history_card()
	if open != null:
		open.close()
	else:
		open_history()


func history_card() -> HistoryCard:
	for panel: UIPanel in _panels:
		if panel is HistoryCard and not panel.is_closing():
			return panel
	return null


## The person card that is open (null if none).
func person_card() -> PersonCard:
	for panel: UIPanel in _panels:
		if panel is PersonCard and not panel.is_closing():
			return panel
	return null


## Shows the grave of someone who has died (in the archive); `family_first`:
## to see their family. Replaces a card that is already open.
func open_grave(session: WorldSession, person_id: int, family_first: bool = false) -> GraveCard:
	if session == null or session.archive.get_record(person_id) == null:
		return null
	for panel: UIPanel in _panels.duplicate():
		if panel is InspectCard or panel is PersonCard or panel is HistoryCard or panel is GraveCard or panel is CemeteryCard:
			panel.close()
	var card: GraveCard = GRAVE_CARD.instantiate()
	card.setup(session, person_id, family_first)
	open_panel(card)
	card.person_chosen.connect(func(id: int) -> void:
		_tick()
		person_chosen.emit(id))
	card.tree_requested.connect(func(id: int) -> void:
		_tick()
		open_family_tree(id))
	card.locate_requested.connect(func(at: Vector2) -> void:
		_tick()
		locate_requested.emit(at))
	return card


## Shows a cemetery: who lies there (each can be read). Replaces a card that is already open.
func open_cemetery(session: WorldSession, cemetery_id: int) -> CemeteryCard:
	if session == null or CemeteryCard.facts(session, cemetery_id).is_empty():
		return null
	for panel: UIPanel in _panels.duplicate():
		if panel is InspectCard or panel is PersonCard or panel is HistoryCard or panel is GraveCard or panel is CemeteryCard:
			panel.close()
	var card: CemeteryCard = CEMETERY_CARD.instantiate()
	card.setup(session, cemetery_id)
	open_panel(card)
	card.person_chosen.connect(func(id: int) -> void:
		_tick()
		person_chosen.emit(id))
	card.locate_requested.connect(func(at: Vector2) -> void:
		_tick()
		locate_requested.emit(at))
	return card


func cemetery_card() -> CemeteryCard:
	for panel: UIPanel in _panels:
		if panel is CemeteryCard and not panel.is_closing():
			return panel
	return null


func grave_card() -> GraveCard:
	for panel: UIPanel in _panels:
		if panel is GraveCard and not panel.is_closing():
			return panel
	return null


## Shows the facts about something; replaces a card that is already open.
func open_inspect(report: InspectReport, height_step: float = 0.4) -> InspectCard:
	if report == null:
		return null
	for panel: UIPanel in _panels.duplicate():
		if panel is InspectCard or panel is PersonCard or panel is HistoryCard:
			panel.close()
	var card: InspectCard = INSPECT_CARD.instantiate()
	open_panel(card)
	card.setup(report, height_step)
	return card


## Shows the facts about something on the card that is open, if one is (a
## trail of tiles under a moving finger: the card stays, what it says
## changes); opens one otherwise.
func show_inspect(report: InspectReport, height_step: float = 0.4) -> InspectCard:
	if report == null:
		return null
	for panel: UIPanel in _panels:
		if panel is InspectCard:
			(panel as InspectCard).setup(report, height_step)
			(panel as InspectCard).layout()
			return panel
	return open_inspect(report, height_step)


func _on_panel_closed(panel: UIPanel) -> void:
	_panels.erase(panel)
	_update_hints()
	if not panel.transient:
		AudioManager.play_ui(&"ui_close")


## One thing at a time: no hints while a panel is open — except a person's
## card, which has a hint of its own (shown above it).
func _update_hints() -> void:
	var card := person_card()
	var other := false
	for panel: UIPanel in _panels:
		if not panel.is_closing() and not (panel is PersonCard):
			other = true
	_hints.set_suppressed(other)
	_hints.set_person_card_open(card != null and not other)
	_hint_label.set_above(card)


## The sound and feel of pressing something in the UI.
func _tick() -> void:
	AudioManager.play_ui(&"ui_tap")
	Haptics.light()


# --- scale ----------------------------------------------------------------------------

## The UI is designed for a portrait screen `base.x` units wide. Turned to
## landscape, the same canvas would be squeezed to fit the short side and
## everything would shrink; this factor keeps a unit the same physical size.
static func ui_scale_for(window_size: Vector2, base: Vector2) -> float:
	if window_size.x <= 0.0 or window_size.y <= 0.0 or base.x <= 0.0 or base.y <= 0.0:
		return 1.0
	var short_side := minf(window_size.x, window_size.y)
	var long_side := maxf(window_size.x, window_size.y)
	var wanted := minf(short_side / base.x, long_side / base.y) # as if held upright
	var actual := minf(window_size.x / base.x, window_size.y / base.y)
	return clampf(wanted / actual, 1.0, MAX_UI_SCALE)


# --- the disasters --------------------------------------------------------------------------------

## Slides the disasters out to the left of their button (or back in).
func toggle_disasters() -> void:
	if _disaster_bar.visible:
		hide_disasters()
	else:
		show_disasters()


func show_disasters() -> void:
	_refresh_disaster_state()
	_disaster_bar.visible = true
	_disaster_button.open = true
	_disaster_bar.reset_size()
	var button := _disaster_button.get_global_rect()
	var rest := Vector2(button.position.x - CORNER_GAP - _disaster_bar.size.x, button.get_center().y - _disaster_bar.size.y * 0.5)
	if _bar_slide != null:
		_bar_slide.kill()
	if bool(Settings.get_value(&"accessibility/reduced_motion")):
		_disaster_bar.position = rest
		_disaster_bar.modulate.a = 1.0
		return
	_disaster_bar.position = Vector2(button.position.x - _disaster_bar.size.x * 0.3, rest.y)
	_disaster_bar.modulate.a = 0.0
	_bar_slide = create_tween().set_parallel()
	_bar_slide.tween_property(_disaster_bar, "position", rest, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_bar_slide.tween_property(_disaster_bar, "modulate:a", 1.0, 0.18)


func hide_disasters() -> void:
	if _bar_slide != null:
		_bar_slide.kill()
	_disaster_bar.visible = false
	_disaster_button.open = false


## The warning before `kind` (or, while the world rests, when it can be).
func warn_of_disaster(kind: StringName) -> DisasterCard:
	hide_disasters()
	var card := DisasterCard.new()
	var now := _session.clock.tick if _session != null else 0
	var waiting := 0
	if _session != null and not _session.disasters.can_start(now):
		waiting = maxi(_session.disasters.rest_left(now), 1)
	card.setup(kind, waiting)
	card.confirmed.connect(func(which: StringName) -> void: disaster_requested.emit(which))
	open_panel(card)
	return card


func disaster_button() -> DisasterButton:
	return _disaster_button


func disaster_bar() -> DisasterBar:
	return _disaster_bar


## The button shows whether a disaster goes on, and how far the world has
## rested since the last.
func _refresh_disaster_state() -> void:
	if _session == null or _session.disasters == null or _disaster_button == null:
		return
	var disasters := _session.disasters
	var now := _session.clock.tick
	_disaster_button.active = disasters.is_active()
	_disaster_button.rested = 1.0 - clampf(float(disasters.rest_left(now)) / DisasterSystem.REST_MINUTES, 0.0, 1.0) 		if not disasters.is_active() else 0.0
	_disaster_bar.can_strike = disasters.can_start(now)


func _process(_delta: float) -> void:
	_refresh_disaster_state()


## The round buttons under the speed button, top to bottom.
func column() -> Array[Control]:
	return [_home_button, _journal_button, _disaster_button]


## The right-hand column: Home under the clock and the weather, the journal
## under Home. The minimap stays at the bottom, beside the column instead
## when the screen is too low for both (landscape).
func _place_corner() -> void:
	if _speed_control == null or _journal_button == null or _minimap == null:
		return
	# All the round buttons of the column as big as the speed button above
	# them, in line with it, evenly spaced (the owner's playtest, 2026-10-05).
	var side := SpeedControl.BUTTON_SIZE
	var top := _speed_control.offset_top + _speed_control.size.y + CORNER_GAP
	for button: Control in column():
		button.custom_minimum_size = Vector2(side, side)
		button.offset_right = -SpeedControl.EDGE_MARGIN
		button.offset_left = button.offset_right - side
		button.offset_top = top
		button.offset_bottom = top + side
		top += side + CORNER_GAP
	var view := _panel_layer.get_viewport_rect().size if _panel_layer != null and _panel_layer.is_inside_tree() else Vector2.ZERO
	var map_top := view.y + _minimap.offset_bottom - Minimap.SIDE
	var lowest := column()[-1]
	var beside := view != Vector2.ZERO and map_top < lowest.offset_bottom + CORNER_GAP
	_minimap.offset_right = (lowest.offset_left - CORNER_GAP) if beside else _home_button.offset_right
	_minimap.offset_left = _minimap.offset_right - _minimap.custom_minimum_size.x


func _apply_ui_scale() -> void:
	var window := get_window()
	var base := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	var factor := ui_scale_for(Vector2(window.size), base)
	if not is_equal_approx(window.content_scale_factor, factor):
		window.content_scale_factor = factor


func bind_session(session: WorldSession) -> void:
	_session = session
	_speed_control.bind(session.clock if session != null else null, session.weather if session != null else null)


func register_unlock_tap(time_ms: int) -> void:
	_unlock_taps.append(time_ms)
	while not _unlock_taps.is_empty() and time_ms - _unlock_taps[0] > UNLOCK_WINDOW_MS:
		_unlock_taps.pop_front()
	if _unlock_taps.size() >= UNLOCK_TAPS:
		_unlock_taps.clear()
		var enabled := not bool(Settings.get_value(&"debug/enabled"))
		Settings.set_value(&"debug/enabled", enabled)
		Log.info(Log.Category.UI, "Debug tools toggled via hidden unlock", {"enabled": enabled})


func _on_version_label_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
		register_unlock_tap(Time.get_ticks_msec())
		_version_label.accept_event()


func _on_back_requested() -> void:
	# In the menu, back is a page back.
	if top_panel() is MainMenu and (top_panel() as MainMenu).back():
		return
	if close_top_panel():
		return
	# Nothing open, so back means "leave the game". Listeners of
	# app_quit_requested (e.g. SaveManager) run synchronously before we quit.
	Log.info(Log.Category.UI, "Back with no open panels: quitting")
	EventBus.app_quit_requested.emit()
	quit_action.call()
