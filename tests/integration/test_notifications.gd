extends TestCase
## What the player is told as it happens (M7.5, bible §26.7): only what
## matters, a few a minute, the same kind of thing as one, less while the
## camera follows someone — and the toast on screen, with "Show".

var main: Node
var ui: UIRoot
var view: WorldView
var session: WorldSession
var rig: CameraRig

var log: EventLog
var clock: GameClock
var _time := [0]
var _posted: Array[Notice] = []
var _updated: Array[Notice] = []
var _announced: Array[int] = []
var _real_now: Callable
var _real_vibrate: Callable
var _toast_seconds := 0.0


func before_each() -> void:
	_real_now = NotificationManager.now_msec
	_real_vibrate = Haptics.vibrate_action
	Haptics.vibrate_action = func(_ms: int, _amplitude: float) -> void: pass
	_toast_seconds = Config.events.toast_seconds
	NotificationManager.unbind()
	NotificationManager.reset_counters()
	NotificationManager.quiet = false
	NotificationManager.enabled = true
	_posted.clear()
	_updated.clear()
	_announced.clear()
	NotificationManager.posted.connect(_on_posted)
	NotificationManager.updated.connect(_on_updated)
	EventBus.notification_created.connect(_on_announced)
	main = null


func after_each() -> void:
	NotificationManager.posted.disconnect(_on_posted)
	NotificationManager.updated.disconnect(_on_updated)
	EventBus.notification_created.disconnect(_on_announced)
	NotificationManager.now_msec = _real_now
	NotificationManager.unbind()
	NotificationManager.reset_counters()
	NotificationManager.quiet = false
	NotificationManager.enabled = true
	Haptics.vibrate_action = _real_vibrate
	Config.events.toast_seconds = _toast_seconds
	if main != null and get_tree().current_scene != null:
		get_tree().unload_current_scene()
		await wait_frames(2)


func _on_posted(notice: Notice) -> void:
	_posted.append(notice)


func _on_updated(notice: Notice) -> void:
	_updated.append(notice)


func _on_announced(id: int) -> void:
	_announced.append(id)


## A log of its own and a clock the test sets: the manager alone.
func _alone() -> void:
	clock = GameClock.new(Config.time)
	log = EventLog.new()
	log.bind(clock, EventLibrary.load_from(), Config.events)
	_time[0] = 1000
	NotificationManager.now_msec = func() -> int: return _time[0]
	NotificationManager.bind(log)


func _seconds(seconds: float) -> void:
	_time[0] += roundi(seconds * 1000.0)
	NotificationManager.pump()


func _kinds() -> Array:
	return _posted.map(func(notice: Notice) -> StringName: return notice.kind)


func _in_game() -> void:
	AudioManager.ensure_sounds()
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	var first := WorldSession.new()
	add_child(first)
	first.create_new(12345)
	SaveManager.save_world(first, &"test")
	first.queue_free()
	await wait_frames(2)
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	await wait_frames(4)
	main = get_tree().current_scene
	ui = main.get_node("UIRoot")
	view = main.get_node("WorldView")
	session = main.get_node("WorldSession")
	rig = view.camera_rig()
	rig.set_process(false)
	ui.quit_action = func() -> void: pass
	ui.hints().set_process(false)
	session.behavior.enabled = false
	session.clock.set_speed(0)
	_posted.clear()


# --- the manager ----------------------------------------------------------------------------------------

func test_only_what_matters_is_told() -> void:
	_alone()
	# The first deer is something to tell.
	var first := log.record(&"animal_hunted", {"species": "deer", "position": Vector2(12.5, 7.5)})
	assert_eq(_posted.size(), 1)
	var notice := _posted[0]
	assert_eq([notice.id, notice.event_id, notice.kind], [1, first.id, &"animal_hunted"])
	assert_eq(notice.text, "Someone brought down the first deer")
	assert_eq(notice.position, Vector2(12.5, 7.5))
	assert_true(notice.can_locate() and notice.is_shown())
	assert_near(notice.priority, 0.55, 0.001)
	assert_eq(_announced, [1], "and announced on the bus")
	# The next deer is a day's work; rationing is below the threshold.
	_seconds(30.0)
	log.record(&"animal_hunted", {"species": "deer"})
	log.record(&"rationing", {})
	log.record(&"food_spoiled", {"resource": "berries"})
	assert_eq(_posted.size(), 1)
	# What the player did is never told, however much it matters.
	log.record(&"player_intervention", {"kind": "uproot", "subject": "tree", "significance": 0.9})
	assert_eq(_posted.size(), 1)
	# Something that happened nowhere in particular has nothing to show.
	log.record(&"dry_spell", {"days": 5, "significance": 0.6})
	assert_eq(_posted.size(), 2)
	assert_false(_posted[1].can_locate())
	assert_eq(_posted[1].text, "No rain for 5 days: a dry spell")
	# Switched off, nothing is told.
	NotificationManager.enabled = false
	log.record(&"stores_empty", {})
	assert_eq(_posted.size(), 2)
	# Unbound, it does not listen.
	NotificationManager.enabled = true
	NotificationManager.unbind()
	log.record(&"fire_out", {})
	assert_eq(_posted.size(), 2)
	assert_true(NotificationManager.debug_text().contains("2 shown"))


func test_a_few_a_minute_the_rest_wait_their_turn() -> void:
	_alone()
	assert_eq(Config.events.toasts_per_minute, 3)
	log.record(&"first_farm", {})
	_seconds(20.0)
	log.record(&"food_shortage", {})
	log.record(&"shortage_over", {})
	assert_eq(_kinds(), [&"first_farm", &"food_shortage", &"shortage_over"])
	# Three in this minute: what comes now waits.
	_seconds(10.0)
	log.record(&"fire_out", {})
	log.record(&"stores_empty", {})
	_seconds(20.0)
	log.record(&"crop_failure", {})
	assert_eq(_posted.size(), 3)
	assert_eq(NotificationManager.waiting_count(), 3)
	# A minute after the first: room for one — the one that matters most.
	_seconds(11.0)
	assert_eq(_kinds().slice(3), [&"stores_empty"])
	assert_eq(NotificationManager.waiting_count(), 2)
	# Room again: what has waited too long is no longer news; the rest is told.
	_seconds(20.0)
	assert_eq(_kinds().slice(4), [&"crop_failure"])
	assert_eq(NotificationManager.waiting_count(), 0)
	assert_eq([NotificationManager.shown, NotificationManager.dropped], [5, 1])
	# What matters a great deal waits as long as it takes.
	log.record(&"first_farm", {"significance": 0.9})
	log.record(&"food_shortage", {"significance": 0.9})
	assert_eq([NotificationManager.shown, NotificationManager.waiting_count()], [6, 1])
	_seconds(30.0)
	assert_eq(NotificationManager.waiting_count(), 1)
	_seconds(25.0)
	assert_eq(NotificationManager.waiting_count(), 0, "55 seconds, and still told")
	assert_eq([NotificationManager.shown, NotificationManager.dropped], [7, 1])
	# Every notice has a number of its own, in the order shown.
	assert_eq(_posted.map(func(notice: Notice) -> int: return notice.id), [1, 2, 3, 4, 5, 6, 7])


func test_the_same_kind_of_thing_is_one_notice() -> void:
	_alone()
	log.record(&"resource_discovered", {"resource": "grain"})
	assert_eq(_posted.size(), 1)
	assert_eq(_posted[0].text, "The settlement has its first grain")
	# Again a moment later: the same notice, saying the latest.
	_seconds(5.0)
	log.record(&"resource_discovered", {"resource": "meat", "position": Vector2(2.0, 3.0)})
	assert_eq(_posted.size(), 1)
	assert_eq(_updated, [_posted[0]])
	assert_eq([_posted[0].count, _posted[0].text, _posted[0].position], [2, "The settlement has its first meat", Vector2(2.0, 3.0)])
	assert_eq(NotificationManager.merged, 1)
	# After the merge window: a notice of its own.
	_seconds(Config.events.merge_seconds + 1.0)
	log.record(&"resource_discovered", {"resource": "stone"})
	assert_eq(_posted.size(), 2)
	# An event that happens again and is counted into the earlier one: its notice counts with it.
	_seconds(30.0)
	_updated.clear()
	var failure := log.record(&"crop_failure", {})
	assert_eq(_posted.size(), 3)
	assert_eq(_posted[2].text, "A crop has withered in the field")
	_seconds(Config.events.merge_seconds + 5.0)
	clock.tick += 60
	assert_eq(log.record(&"crop_failure", {}), failure)
	assert_eq(_posted.size(), 3)
	assert_eq(_updated, [_posted[2]])
	assert_eq([_posted[2].count, _posted[2].text], [2, "2 crops have withered in the field"])
	# The same kind waiting for its turn: one of them waits, not two.
	log.record(&"first_farm", {})
	assert_eq(_posted.size(), 4, "(the third in this minute)")
	log.record(&"fire_out", {})
	log.record(&"fire_out", {})
	assert_eq(_posted.size(), 4)
	assert_eq(NotificationManager.waiting_count(), 1)


func test_while_following_only_what_matters_a_great_deal() -> void:
	_alone()
	NotificationManager.quiet = true
	log.record(&"first_farm", {})
	log.record(&"crop_failure", {})
	assert_eq(_posted.size(), 0)
	assert_eq(NotificationManager.silenced, 2)
	assert_eq(NotificationManager.waiting_count(), 0, "not told later either")
	log.record(&"stores_empty", {})
	assert_eq(_kinds(), [&"stores_empty"])
	NotificationManager.quiet = false
	log.record(&"fire_out", {})
	assert_eq(_kinds(), [&"stores_empty", &"fire_out"])


# --- on screen ------------------------------------------------------------------------------------------

func test_a_toast_says_it_and_shows_where() -> void:
	await _in_game()
	var stack := ui.toasts()
	assert_not_null(stack)
	assert_eq(stack.toasts().size(), 0, "nothing to tell of a world just opened")
	# Something happens in the world: a toast.
	var farmer: PersonData = null
	for p in session.people.all_people():
		if p.occupation_id == &"farmer":
			farmer = p
	var place := Vector2(session.start.settlement_tile) + Vector2(14.5, -9.5)
	session.events.record(&"first_farm", {"position": place, "participants": [farmer.id]})
	await wait_frames(2)
	assert_eq(stack.toasts().size(), 1)
	var toast := stack.toasts()[0]
	assert_eq(toast.text(), "%s has sown the first field" % farmer.given_name)
	assert_true(toast.locate_button().visible)
	assert_eq(toast.locate_button().text, "Show")
	assert_true(toast.is_in_group(InputRouter.UI_BLOCKER_GROUP), "a touch on it is not a touch on the world")
	# It keeps clear of the clock and of the edge of the screen.
	var rect := toast.get_global_rect()
	var screen := stack.get_viewport_rect()
	assert_true(rect.position.x >= 0.0 and rect.end.x <= screen.size.x, str(rect))
	assert_false(rect.intersects(ui.speed_control().get_global_rect()), "%s / %s" % [rect, ui.speed_control().get_global_rect()])
	assert_true(rect.size.x >= ToastStack.MIN_WIDTH - 1.0)
	# "Show": the camera goes there, and the toast has done its work.
	var before := rig.pivot()
	toast.locate_button().pressed.emit()
	for i in 240:
		rig.advance(1.0 / 60.0)
	var after := rig.pivot()
	assert_true(Vector2(after.x, after.z).distance_to(place) < 0.5, "looking at %s (was at %s)" % [after, before])
	assert_true(toast.is_closing())
	await wait_seconds(0.5)
	assert_eq(stack.toasts().size(), 0)
	# Something with no place: no "Show"; a tap sends it away.
	session.events.record(&"dry_spell", {"days": 6, "significance": 0.6})
	await wait_frames(2)
	toast = stack.toasts()[0]
	assert_false(toast.locate_button().visible)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	toast._gui_input(press)
	assert_true(toast.is_closing())
	assert_eq(stack.toasts().size(), 0)
	# The same again: the toast on screen says so instead of a second one.
	session.events.record(&"crop_failure", {"position": place})
	session.clock.tick += 30
	session.events.record(&"crop_failure", {"position": place})
	await wait_frames(2)
	assert_eq(stack.texts(), PackedStringArray(["2 crops have withered in the field"]))
	# It goes by itself after a while.
	Config.events.toast_seconds = 0.3
	var brief := Notice.new()
	brief.text = "The fire has gone out"
	var fire_toast := stack.show_notice(brief)
	await wait_frames(2)
	assert_eq(stack.toasts().size(), 2)
	await wait_seconds(1.0)
	assert_false(is_instance_valid(fire_toast) and not fire_toast.is_closing(), "gone after its time")
	assert_eq(stack.toasts().size(), 1, "the other has its time still")
	# No more than a few at once: the oldest makes room.
	Config.events.toast_seconds = 30.0
	stack.clear()
	for i in Config.events.max_toasts + 2:
		var notice := Notice.new()
		notice.id = 100 + i
		notice.text = "Notice %d" % i
		stack.show_notice(notice)
	assert_eq(stack.toasts().size(), Config.events.max_toasts)
	assert_eq(stack.texts()[0], "Notice 2")
	stack.clear()
	assert_eq(stack.toasts().size(), 0)


func test_a_milestone_is_told_so_it_can_be_read() -> void:
	# (Owner: discoveries should grab the eye — and stay until they have been read.)
	await _in_game()
	var people := session.people.all_people()
	session.events.record(&"knowledge_learned", {"participants": [people[0].id], "significance": 0.2})
	await wait_frames(2)
	var card := ui.milestone_card()
	assert_not_null(card, "a card, not only a toast")
	assert_eq(card.heading_text(), "A DISCOVERY")
	assert_eq(card.text(), "%s has worked something out" % people[0].given_name)
	assert_true(card.is_in_group(InputRouter.UI_BLOCKER_GROUP), "the world waits behind it: no touch reaches it")
	assert_eq(card.get_global_rect().size, card.get_viewport_rect().size, "across the whole screen")
	# Its toast, framed in gold.
	var toast := ui.toasts().toasts()[-1]
	assert_eq((toast.get_theme_stylebox(&"panel") as StyleBoxFlat).border_color, MilestoneCard.GOLD)
	# Another while it is open: its turn comes after (not merged into the first).
	session.events.record(&"knowledge_learned", {"participants": [people[1].id], "significance": 0.2})
	await wait_frames(2)
	assert_true(ui.milestone_card() == card, "one at a time")
	card.continue_button().pressed.emit()
	await wait_frames(2)
	assert_not_null(ui.milestone_card())
	assert_eq(ui.milestone_card().text(), "%s has worked something out" % people[1].given_name)
	ui.milestone_card().continue_button().pressed.emit()
	await wait_frames(2)
	assert_null(ui.milestone_card())
	# In the background: it waits for the player's return.
	EventBus.app_paused.emit()
	session.events.record(&"era_entered", {"significance": 0.9})
	await wait_frames(2)
	assert_null(ui.milestone_card(), "nothing pops up while nobody is looking")
	EventBus.app_resumed.emit()
	await wait_frames(2)
	assert_not_null(ui.milestone_card())
	assert_eq(ui.milestone_card().heading_text(), "A NEW AGE")
	ui.milestone_card().close()
	await wait_frames(2)


func test_following_someone_quiets_the_toasts() -> void:
	await _in_game()
	var stack := ui.toasts()
	var person := session.people.all_people()[0]
	person.set_flag(PersonData.FLAG_INDOORS, false)
	assert_false(NotificationManager.quiet)
	assert_true(main.follow_person(person.id))
	assert_true(NotificationManager.quiet)
	session.events.record(&"crop_failure", {})
	session.events.record(&"stores_empty", {})
	await wait_frames(2)
	assert_eq(stack.texts(), PackedStringArray(["The stores are empty"]), "only what matters a great deal")
	# "Show" leaves the person be: the following is taken up again from the banner.
	session.events.record(&"stores_empty", {"position": person.world2d() + Vector2(20.0, 0.0), "significance": 0.9})
	await wait_frames(2)
	stack.toasts()[0].locate_button().pressed.emit()
	assert_true(main.follow.state == CameraFollow.State.PAUSED)
	assert_false(NotificationManager.quiet, "the camera is no longer with them")
	main.stop_following()
	session.events.record(&"first_farm", {})
	await wait_frames(2)
	assert_true(stack.texts().has("Someone has sown the first field"))
	# The world closed: nothing is left on screen, and nothing more is told.
	get_tree().unload_current_scene()
	await wait_frames(2)
	main = null
	assert_eq(NotificationManager.waiting_count(), 0)
