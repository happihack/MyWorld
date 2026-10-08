extends TestCase
## FC1: the signs above heads. Every sign has a picture; what has happened to
## someone shows for a while (a flash); the weightier sign shows.


func test_every_sign_has_a_picture() -> void:
	for sign: StringName in Signs.PRIORITY:
		assert_true(PeopleView.EMOTES.has(sign), "%s is drawn" % sign)


func test_a_flash_shows_for_a_while() -> void:
	var person := PersonData.new()
	assert_eq(Signs.shown(person, 100), &"")
	assert_true(Signs.flash(person, Signs.LOVE, 100))
	assert_eq(Signs.shown(person, 101), Signs.LOVE)
	assert_eq(Signs.shown(person, 100 + int(Signs.MINUTES[Signs.LOVE])), &"", "and goes")


func test_the_weightier_shows() -> void:
	var person := PersonData.new()
	Signs.flash(person, Signs.ANGRY, 0)
	assert_false(Signs.flash(person, Signs.NOTE, 1), "a tune does not cut off anger")
	assert_eq(Signs.shown(person, 2), Signs.ANGRY)
	person.emote = Signs.SPEECH
	assert_eq(Signs.shown(person, 2), Signs.ANGRY, "anger over talk")
	person.emote = Signs.EXCLAIM
	assert_eq(Signs.shown(person, 2), Signs.EXCLAIM, "a shout over anger")
	assert_true(Signs.flash(person, Signs.HURT, 3), "as weighty: the new one")
	Signs.clear(person)
	assert_eq(Signs.shown(person, 4), Signs.EXCLAIM)
