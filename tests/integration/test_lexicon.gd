extends TestCase
## M17.3: words — a concept gets a word once it is met often enough; words are
## inherited by a settlement founded from another, borrowed with loads, and
## drift once settlements are long apart; shown with glosses; a settlement
## takes its own word for its place as its name.

const SessionScript := preload("res://scripts/simulation/world_session.gd")

var session: WorldSession
var words: Lexicon


func before_each() -> void:
	SaveManager.attach(null)
	Settings.reset_to_defaults()
	session = SessionScript.new()
	add_child(session)
	session.create_new(12345)
	session.set_process(false)
	session.loose_system.set_process(false)
	session.water.set_process(false)
	words = session.lexicon


func after_each() -> void:
	session.queue_free()
	await wait_frames(1)


func _days(count: int, from: int = 1) -> void:
	for day in range(from, from + count):
		words.each_day(day * TimeConfig.MINUTES_PER_DAY)


func test_lexicon_coining_threshold() -> void:
	var own := session.settlement
	var first := own.display_name()
	assert_eq(words.word(own.id, &"home"), "")
	# Met every day by everyone: their own place gets a word in time — not at once.
	_days(3)
	assert_eq(words.word(own.id, &"home"), "", "not after three days")
	var needed := ceili(Lexicon.COIN_AT / (own.member_count() * 0.15))
	_days(needed + 2, 4)
	var name := words.word(own.id, &"home")
	assert_ne(name, "", "a word for home")
	assert_true(NameGenerator.is_acceptable(name))
	assert_eq(own.display_name(), name, "and the settlement goes by it")
	var renamed := session.events.of_type(&"renamed")
	assert_eq(renamed.size(), 1)
	assert_eq(EventText.text(renamed[0], session.people), "%s came to be called %s" % [MemoryText.capitalized(first), name])
	# What nobody meets gets no word.
	assert_eq(words.word(own.id, &"rainbringer"), "")
	# Glosses.
	assert_eq(words.gloss(own.id, &"rainbringer"), MemoryText.translate("EPITHET_RAIN_FROM_CLEAR_SKY"), "no word: the gloss alone")
	(words.tongues[own.id]["words"] as Dictionary)[&"rainbringer"] = {"word": "Velun", "coined": 0, "from": 0}
	assert_eq(words.gloss(own.id, &"rainbringer"), "Velun (%s)" % MemoryText.translate("EPITHET_RAIN_FROM_CLEAR_SKY"))
	# The same world gives the same words.
	var again := Lexicon.new()
	again.bind(session.settlements, session.culture, session.world_seed, 0)
	assert_eq(again.coin(own, &"edge", 0), words.coin(own, &"edge", 0))


func test_word_inheritance() -> void:
	var own := session.settlement
	words.coin(own, &"river", 0)
	words.coin(own, &"home", 0)
	var founded := Settlement.new()
	founded.id = 980
	founded.settlement_name = "Ama's camp"
	session.settlements.add(founded)
	words.on_founded(founded, {"from": own.id, "tick": 0})
	assert_eq(words.word(founded.id, &"river"), words.word(own.id, &"river"), "they speak as their parents did")
	assert_eq(words.word(founded.id, &"home"), "", "but their place is their own")
	assert_eq(words.kinship(own.id, founded.id), 1.0)
	# Borrowed: a word they lacked, for what they met — with the loads.
	var trading := Settlement.new()
	trading.id = 981
	session.settlements.add(trading)
	(words._tongue(trading.id)["use"] as Dictionary)[&"river"] = 5.0
	var loads := 0
	while words.word(trading.id, &"river") == "" and loads < 500:
		loads += 1
		words.on_traded({"from": own.id, "to": trading.id, "units": loads})
	assert_eq(words.word(trading.id, &"river"), words.word(own.id, &"river"), "borrowed")
	assert_eq(words.word(trading.id, &"edge"), "", "not what they never met")
	session.settlements.remove(founded)
	session.settlements.remove(trading)


func test_culture_divergence_after_split() -> void:
	var own := session.settlement
	for concept: StringName in [&"river", &"hills", &"edge", &"touch", &"flood", &"presence"]:
		words.coin(own, concept, 0)
	var founded := Settlement.new()
	founded.id = 982
	session.settlements.add(founded)
	words.on_founded(founded, {"from": own.id, "tick": 0})
	assert_eq(words.kinship(own.id, founded.id), 1.0, "one language at the split")
	# A hundred years apart.
	var year := Config.time.ticks_per_year()
	for y in range(1, 101):
		words.drift(founded, y * year)
	assert_true(words.kinship(own.id, founded.id) < 0.8, "the words have drifted (%.2f alike)" % words.kinship(own.id, founded.id))
	assert_true(words.kinship(own.id, founded.id) > 0.0, "still kin")
	# What each coined apart differs.
	assert_ne(words.coin(own, &"valley", 0), words.coin(founded, &"valley", 0))
	# And they lean otherwise in what they make of things.
	var prior_own := Config.reactions.culture_prior(session.world_seed, own.id, ReactionTable.SPIRIT)
	var prior_founded := Config.reactions.culture_prior(session.world_seed, founded.id, ReactionTable.SPIRIT)
	assert_ne(prior_own, prior_founded)
	# Saved.
	var again := Lexicon.new()
	again.from_dict(bytes_to_var(var_to_bytes(words.to_dict())))
	assert_eq(again.word(founded.id, &"river"), words.word(founded.id, &"river"))
	session.settlements.remove(founded)
	assert_eq(Lexicon.shifted("Tiravel", 3), Lexicon.shifted("Tiravel", 3), "the same shift for the same salt")
	assert_ne(Lexicon.shifted("Tiravel", 3), "Tiravel")
