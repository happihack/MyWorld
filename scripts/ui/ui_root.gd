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

const CONTEXT_MENU := preload("res://scenes/ui/panels/context_menu.tscn")
const INSPECT_CARD := preload("res://scenes/ui/panels/inspect_card.tscn")
const TOOL_BAR := preload("res://scenes/ui/tool_bar.tscn")
## Upper limit of the UI scale (see ui_scale_for).
const MAX_UI_SCALE := 3.0

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


func _ready() -> void:
	_version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "?")
	_version_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_version_label.add_to_group(InputRouter.UI_BLOCKER_GROUP)
	_version_label.gui_input.connect(_on_version_label_input)
	_home_button.pressed.connect(func() -> void:
		_tick()
		home_pressed.emit())
	EventBus.back_requested.connect(_on_back_requested)
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
	_hints.set_suppressed(true) # one thing at a time
	panel.closed.connect(_on_panel_closed.bind(panel))
	_panel_layer.add_child(panel)


## Closes the top panel. False if none is open.
func close_top_panel() -> bool:
	if _panels.is_empty():
		return false
	_panels[-1].close()
	return true


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


## Shows the facts about something; replaces a card that is already open.
func open_inspect(report: InspectReport, height_step: float = 0.4) -> InspectCard:
	if report == null:
		return null
	for panel: UIPanel in _panels.duplicate():
		if panel is InspectCard:
			panel.close()
	var card: InspectCard = INSPECT_CARD.instantiate()
	open_panel(card)
	card.setup(report, height_step)
	return card


func _on_panel_closed(panel: UIPanel) -> void:
	_panels.erase(panel)
	_hints.set_suppressed(not _panels.is_empty())
	if not panel.transient:
		AudioManager.play_ui(&"ui_close")


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
	if close_top_panel():
		return
	# Nothing open, so back means "leave the game". Listeners of
	# app_quit_requested (e.g. SaveManager) run synchronously before we quit.
	Log.info(Log.Category.UI, "Back with no open panels: quitting")
	EventBus.app_quit_requested.emit()
	quit_action.call()
