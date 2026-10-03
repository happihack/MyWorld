extends TestCase
## Who matters to the world's history (M11.2, bible §21.5): significance from
## what people take part in, the firsts, and the Important People.

const SessionScript := preload("res://scripts/simulation/world_session.gd")
const DAY := 1440

var session: WorldSession
var events: EventLog
var significance: Significance
var config: SignificanceConfig
var _knobs: Array = []


func before_each() -> void:
	SaveManager.attach(null)
	remove_dir_recursive(Config.save.save_root)
	DirAccess.make_dir_recursive_absolute(Config.save.save_root)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	events = session.events
	significance = session.significance
	config = Config.significance


func after_each() -> void:
	_knobs.reverse()
	for knob: Array in _knobs:
		(knob[0] as Resource).set(knob[1], knob[2])
	_knobs.clear()
	session.queue_free()
	await wait_frames(1)


func _knob(resource: Resource, knob: StringName, value: Variant) -> void:
	_knobs.append([resource, knob, resource.get(knob)])
	resource.set(knob, value)


func test_significance_firsts() -> void:
	assert_eq(config.validate().size(), 0)
	var people := session.people.all_people()
	# The band founded the settlement: its first named most, everyone a little.
	var founded := events.latest(Chronicler.TYPE_FOUNDED)
	assert_not_null(founded)
	var first := session.people.get_person(founded.participants[0])
	assert_true(first.significance >= founded.significance * config.principal_share - 0.0001)
	for n in range(1, founded.participants.size()):
		var other := session.people.get_person(founded.participants[n])
		assert_true(other.significance >= founded.significance * config.other_share - 0.0001, "every founder")
	# The first of a kind is worth more than the next.
	var a := people[2]
	var b := people[3]
	var before_a := a.significance
	var fox := events.record(Chronicler.TYPE_HUNTED, {"participants": [a.id], "species": "fox"})
	assert_true(fox.is_first())
	assert_near(a.significance - before_a, fox.significance + config.first_bonus, 0.0001)
	before_a = a.significance
	var found := events.record(Chronicler.TYPE_DISCOVERED, {"participants": [a.id], "resource": "stone"})
	var once := a.significance - before_a
	assert_near(once, found.significance, 0.0001)
	before_a = a.significance
	events.record(Chronicler.TYPE_DISCOVERED, {"participants": [a.id], "resource": "clay"})
	assert_near(a.significance - before_a, once / (1.0 + config.repeat_wear), 0.0001, "the same kind again counts less")
	# One's own life with others is one's own, not history's.
	before_a = a.significance
	events.record(Chronicler.TYPE_PARTNERS, {"participants": [a.id, b.id]})
	events.record(Chronicler.TYPE_FIGHT, {"participants": [a.id, b.id]})
	events.record(Chronicler.TYPE_FRIENDS, {"participants": [a.id, b.id]})
	assert_eq(a.significance, before_a)
	# What hardly matters adds nothing (a day's hunt is no history).
	var hunter := people[1]
	events.record(Chronicler.TYPE_HUNTED, {"participants": [hunter.id], "species": "deer"}) # (the first: counts)
	var after_first := hunter.significance
	for n in 30:
		events.record(Chronicler.TYPE_HUNTED, {"participants": [hunter.id], "species": "deer"})
	assert_eq(hunter.significance, after_first, "thirty more hunts: nothing")
	# Something of note, again and again: less each time.
	var finder := people[6]
	var gains: Array[float] = []
	for n in 3:
		var was := finder.significance
		events.record(Chronicler.TYPE_DISCOVERED, {"participants": [finder.id], "resource": "r%d" % n})
		gains.append(finder.significance - was)
	assert_true(gains[1] < gains[0] and gains[2] < gains[1], str(gains))
	# What merely happens to someone adds nothing.
	var c := people[4]
	var before_c := c.significance
	events.record(Chronicler.TYPE_INJURED, {"participants": [c.id], "kind": "fall"})
	events.record(&"came_of_age", {"participants": [c.id], "kind": "adult"})
	assert_eq(c.significance, before_c)
	# The firsts ledger: the first of each kind worth telling, the earliest first.
	var firsts := significance.firsts()
	assert_false(firsts.is_empty())
	var types := []
	for event in firsts:
		types.append(event.type)
		assert_true(event.tags.has("first"))
	assert_true(types.has(Chronicler.TYPE_HUNTED))
	for n in range(1, firsts.size()):
		assert_true(firsts[n - 1].tick <= firsts[n].tick)
	# The first death, the first storm, the first touch are firsts too.
	for type: StringName in [Chronicler.TYPE_DIED, Chronicler.TYPE_STORM, Chronicler.TYPE_PLAYER, Chronicler.TYPE_FLOOD]:
		assert_true(session.event_defs.get_def(type).first_significance > 0.0, "%s has a first" % type)


func test_touched_by_the_presence_again_and_again() -> void:
	var person := session.people.all_people()[5]
	var before := person.significance
	# Touches taken together (one event, counted) — each adds.
	for n in 20:
		events.record(Chronicler.TYPE_PLAYER, {"kind": "touch", "subject": "person", "participants": [person.id],
			"significance": 0.1})
	var event := events.latest(Chronicler.TYPE_PLAYER)
	assert_eq(event.count, 20, "one event, twenty times")
	assert_near(person.significance - before, 20 * config.presence_touch + config.first_bonus, 0.0001, "(the first touch of all is a first)")
	assert_true(20 * config.presence_touch >= config.important_from, "touched twenty times: one of the Important People")
	# Someone else touched in the same while: only they gain from that touch.
	var other := session.people.all_people()[6]
	var other_before := other.significance
	var mine := person.significance
	events.record(Chronicler.TYPE_PLAYER, {"kind": "touch", "subject": "person", "participants": [other.id], "significance": 0.1})
	assert_near(other.significance - other_before, config.presence_touch, 0.0001)
	assert_eq(person.significance, mine)


func test_important_people() -> void:
	var people := session.people.all_people()
	var person := people[6]
	person.significance = config.important_from - 0.05
	assert_false(significance.is_important(person.id))
	var deed := events.record(Chronicler.TYPE_HUNTED, {"participants": [person.id], "species": "deer"})
	assert_true(significance.is_important(person.id))
	var spoken := events.latest(Chronicler.TYPE_IMPORTANT)
	assert_not_null(spoken, "the world takes note")
	assert_eq(EventText.text(spoken, session.people, events), "%s is someone people speak of now" % person.given_name)
	assert_eq(Array(spoken.causes), [deed.id], "because of what tipped it")
	assert_eq(significance.best_deed(person.id), deed)
	# Once.
	var count := events.count_of(Chronicler.TYPE_IMPORTANT)
	events.record(Chronicler.TYPE_HUNTED, {"participants": [person.id], "species": "rabbit"})
	assert_eq(events.count_of(Chronicler.TYPE_IMPORTANT), count)
	# Listed, the most significant first — and still when they have died.
	var greater := people[7]
	greater.significance = config.important_from * 3.0
	var listed := significance.important_people()
	assert_eq(listed[0], greater.id)
	assert_true(listed.has(person.id))
	session.kill_person(person.id, Lifecycle.CAUSE_ILLNESS)
	var record := session.archive.get_record(person.id)
	assert_true(record.significance >= config.important_from, "the archive keeps their points (%f)" % record.significance)
	assert_true(significance.important_people().has(person.id))
	assert_true(significance.is_important(person.id))
	# Their obituary is that of someone who mattered.
	var died := events.get_event(record.obituary_event)
	assert_near(died.significance, Chronicler.OBITUARY_BASE + Chronicler.OBITUARY_WEIGHT, 0.0001)
	# In the menu: who, and what they are remembered for.
	var rows := MainMenu.important(session)
	assert_eq(int(rows[0][0]), greater.id)
	var theirs: Array = []
	for row: Array in rows:
		if int(row[0]) == person.id:
			theirs = row
	assert_true(String(theirs[1]).contains("died in year"))
	assert_true(String(theirs[2]).contains(person.given_name), str(theirs))


func test_significance_is_kept() -> void:
	var person := session.people.all_people()[2]
	person.significance = 2.75
	assert_true(SaveManager.save_world(session, &"test"))
	var loaded := SaveManager.load_world(session.world_id)
	var again: WorldSession = SessionScript.new()
	add_child(again)
	assert_true(again.load_from(loaded.world))
	again.set_process(false)
	assert_eq(again.people.get_person(person.id).significance, 2.75)
	assert_eq(again.significance.firsts().size(), significance.firsts().size(), "the firsts ledger, too")
	# Opening a world does not count its history again.
	assert_eq(again.people.get_person(person.id).significance, 2.75)
	again.queue_free()
