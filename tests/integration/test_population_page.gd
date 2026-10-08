extends TestCase
## The population page adds up (the owner, 2026-10-08: "10 people", then
## "1 children · 7 grown · 1 elders" — the young one was counted nowhere).

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func test_the_stages_add_up() -> void:
	var year := Config.time.ticks_per_year()
	var young := session.people.all_people()[0]
	# (A youth: past childhood, not yet grown.)
	var age := 0
	while young.life_stage(session.clock.tick, year, Config.people) != PersonData.LifeStage.ADOLESCENT and age < 40:
		age += 1
		young.birth_tick = session.clock.tick - age * year
	assert_eq(young.life_stage(session.clock.tick, year, Config.people), PersonData.LifeStage.ADOLESCENT)
	var lines := MenuPages.population_lines(session)
	var numbers := []
	for word in lines[1].replace("·", " ").split(" ", false):
		if word.is_valid_int():
			numbers.append(int(word))
	assert_eq(numbers.size(), 3, lines[1])
	assert_eq(numbers[0] + numbers[1] + numbers[2], session.people.size(), "%s — of %d" % [lines[1], session.people.size()])
