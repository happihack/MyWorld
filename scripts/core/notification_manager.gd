extends Node
## Autoload "NotificationManager": what of the world's events the player is
## told as it happens (bible §26.7 — "discoveries, not chores").
##
## Every event the log records is offered here. Told are only those that
## matter enough (a threshold); at most a few a minute (a rate limit: the
## rest wait their turn, the most important first, and are dropped when
## they have waited too long); the same kind of thing again and again is
## one notice (a merge window); and while the camera follows someone only
## what matters a great deal gets through.
##
## It decides; the toasts on screen (ToastStack) only show what it posts.

## A notice is to be shown now.
signal posted(notice: Notice)
## A notice that is being shown has changed (it happened again).
signal updated(notice: Notice)
## Everything is to be taken off the screen (the world was closed).
signal cleared

const MINUTE_MSEC := 60_000

## The camera is following someone: only what matters a great deal is told.
var quiet := false
## Off: nothing is told at all.
var enabled := true
## The real time, in milliseconds (tests put their own clock here).
var now_msec: Callable = func() -> int: return Time.get_ticks_msec()
## For the debug overlay and tests.
var offered := 0
var shown := 0
var merged := 0
var dropped := 0
var silenced := 0

var _log: EventLog
var _people: PersonRegistry
var _config: EventsConfig
var _next_id := 1
## Waiting for their turn, the most important first.
var _queue: Array[Notice] = []
## Shown, the latest last (kept for as long as they may be merged into, or
## count against the rate limit).
var _recent: Array[Notice] = []


func _ready() -> void:
	EventBus.world_unloaded.connect(unbind)


## Listens to a world's event log from now on. `people`: to name names.
func bind(log: EventLog, people: PersonRegistry = null, config: EventsConfig = null) -> void:
	unbind()
	_log = log
	_people = people
	_config = config
	if _log != null:
		_log.recorded.connect(offer)
		_log.merged.connect(_on_merged)


func unbind() -> void:
	if _log != null:
		if _log.recorded.is_connected(offer):
			_log.recorded.disconnect(offer)
		if _log.merged.is_connected(_on_merged):
			_log.merged.disconnect(_on_merged)
	_log = null
	_people = null
	_next_id = 1
	clear()


## Forgets what is waiting and what was shown.
func clear() -> void:
	_queue.clear()
	_recent.clear()
	cleared.emit()


func reset_counters() -> void:
	offered = 0
	shown = 0
	merged = 0
	dropped = 0
	silenced = 0


func _process(_delta: float) -> void:
	if not _queue.is_empty():
		pump()


# --- offering ---------------------------------------------------------------------------------------

## A world event has happened: the player is told of it — now, later, or
## not at all. Returns the notice it became (or was merged into), or null.
func offer(event: WorldEvent) -> Notice:
	if event == null or not enabled:
		return null
	var def := _log.library.get_def(event.type) if _log != null and _log.library != null else null
	if def != null and not def.toast:
		return null
	var notice := Notice.new()
	notice.event_id = event.id
	notice.kind = event.type
	notice.text = EventText.text(event, _people, _log)
	notice.position = event.position
	notice.priority = event.significance
	return offer_notice(notice)


## Offers a notice made by hand (same rules).
func offer_notice(notice: Notice) -> Notice:
	if notice == null or not enabled:
		return null
	var config := _settings()
	offered += 1
	if notice.priority < config.notify_from:
		return null
	if quiet and notice.priority < config.high_from:
		silenced += 1
		return null
	var now: int = now_msec.call()
	# The same kind of thing, told (or about to be told) a moment ago: one notice.
	var known := _same_kind(notice.kind, now)
	if known != null:
		known.count += 1
		known.priority = maxf(known.priority, notice.priority)
		if notice.position != Vector2.INF:
			known.position = notice.position
		known.text = notice.text if notice.text != "" else known.text
		merged += 1
		if known.is_shown():
			updated.emit(known)
		return known
	notice.offered_msec = now
	_queue.append(notice)
	_queue.sort_custom(func(a: Notice, b: Notice) -> bool:
		return a.priority > b.priority or (a.priority == b.priority and a.offered_msec < b.offered_msec))
	pump()
	return notice


## Shows what is waiting, as far as the rate limit allows; drops what has
## waited too long.
func pump() -> void:
	var config := _settings()
	var now: int = now_msec.call()
	# (What was shown long ago no longer counts.)
	while not _recent.is_empty() and now - _recent[0].shown_msec > MINUTE_MSEC:
		_recent.pop_front()
	var i := 0
	while i < _queue.size():
		var waiting := _queue[i]
		if now - waiting.offered_msec > config.stale_seconds * 1000.0 and waiting.priority < config.high_from:
			_queue.remove_at(i)
			dropped += 1
		else:
			i += 1
	while not _queue.is_empty() and _recent.size() < config.toasts_per_minute:
		var notice: Notice = _queue.pop_front()
		notice.id = _next_id
		_next_id += 1
		notice.shown_msec = now
		_recent.append(notice)
		shown += 1
		posted.emit(notice)
		EventBus.notification_created.emit(notice.id)


## How many notices are waiting for their turn.
func waiting_count() -> int:
	return _queue.size()


func debug_text() -> String:
	return "notices: %d offered  %d shown  %d merged  %d dropped  %d silenced  %d waiting%s" % [offered, shown, merged,
		dropped, silenced, _queue.size(), "  (quiet: following)" if quiet else ""]


# --- internals --------------------------------------------------------------------------------------

func _settings() -> EventsConfig:
	return _config if _config != null else Config.events


## An event happened again and was counted into an earlier one: the notice
## that tells of it (if there is one on screen or waiting) says so.
func _on_merged(event: WorldEvent) -> void:
	if event == null:
		return
	for notice: Notice in _queue + _recent:
		if notice.event_id == event.id:
			notice.count = event.count
			notice.text = EventText.text(event, _people, _log)
			merged += 1
			if notice.is_shown():
				updated.emit(notice)
			return


## A notice of this kind that is waiting, or was shown within the merge window.
func _same_kind(kind: StringName, now: int) -> Notice:
	if kind == &"":
		return null
	for notice in _queue:
		if notice.kind == kind:
			return notice
	var window := _settings().merge_seconds * 1000.0
	for i in range(_recent.size() - 1, -1, -1):
		if _recent[i].kind == kind and now - _recent[i].shown_msec <= window:
			return _recent[i]
	return null
