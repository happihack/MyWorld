class_name MemoryStore
extends RefCounted
## Everyone's memories (bible §15.2). A person holds the ids of theirs
## (PersonData.memory_ids, most recent last); the store holds the memories.
##
## Remembering merges what is the same thing again ("was touched 14 times"
## is one memory, not fourteen), keeps at most MemoryConfig.max_per_person
## per person — the least important go first — and lets what does not
## matter fade, day by day, until it is forgotten.

signal remembered(memory: Memory)
signal forgotten(owner_id: int, memory_id: int)

var _people: PersonRegistry
var _memories: Dictionary = {} # id -> Memory
var _next_id := 1
## The game day up to which fading has been done.
var _faded_day := -1
## For the debug overlay.
var merged := 0
var dropped := 0


func bind(people: PersonRegistry) -> void:
	if _people != null and _people.person_removed.is_connected(_on_person_removed):
		_people.person_removed.disconnect(_on_person_removed)
	_people = people
	if people != null:
		people.person_removed.connect(_on_person_removed)


func clear() -> void:
	_memories.clear()
	_next_id = 1
	_faded_day = -1
	merged = 0
	dropped = 0


func size() -> int:
	return _memories.size()


func get_memory(id: int) -> Memory:
	return _memories.get(id)


## A person's memories, the most recent last.
func of(person: PersonData) -> Array[Memory]:
	var out: Array[Memory] = []
	for id in person.memory_ids:
		var memory: Memory = _memories.get(id)
		if memory != null:
			out.append(memory)
	return out


## The last `count` things a person remembers, the most recent first.
func recent(person: PersonData, count: int = 1) -> Array[Memory]:
	var all := of(person)
	all.sort_custom(func(a: Memory, b: Memory) -> bool: return a.tick > b.tick or (a.tick == b.tick and a.id > b.id))
	return all.slice(0, count)


## What a person remembers of a kind of thing ([] if nothing).
func about(person: PersonData, subject: StringName) -> Array[Memory]:
	var out: Array[Memory] = []
	for memory in of(person):
		if memory.subject == subject:
			out.append(memory)
	return out


## How many times a person remembers a kind of thing happening (to them, or
## before their eyes; what they were only told does not count).
func times(person: PersonData, subject: StringName) -> int:
	var total := 0
	for memory in about(person, subject):
		if memory.source != Memory.Source.TOLD:
			total += memory.count
	return total


# --- remembering --------------------------------------------------------------------------------

## Gives a person a memory. If they already remember the same thing (same
## subject, taken the same way, come by the same way) it happens "again":
## the one memory is brought up to date and grows. Returns the memory they
## now have (the old one, if it was merged).
func remember(person: PersonData, memory: Memory, config: MemoryConfig = null) -> Memory:
	if config == null:
		config = Config.memory
	memory.owner_kind = Memory.OwnerKind.PERSON
	memory.owner_id = person.id
	for known in of(person):
		if known.same_as(memory):
			_merge(known, memory, config)
			_touch(person, known.id)
			merged += 1
			remembered.emit(known)
			return known
	memory.id = _next_id
	_next_id += 1
	if memory.first_tick == 0:
		memory.first_tick = memory.tick
	_memories[memory.id] = memory
	person.memory_ids.append(memory.id)
	compact(person, config)
	if _memories.has(memory.id):
		remembered.emit(memory)
	return memory


## The memory a person keeps of something they noticed and what came of it
## (see Reactions.Outcome) — null if it was not worth remembering.
## `times_before`: how often they had experienced the like already.
static func from_outcome(person: PersonData, outcome: Reactions.Outcome, stage: PersonData.LifeStage, times_before: int,
		now_tick: int, config: MemoryConfig = null) -> Memory:
	if config == null:
		config = Config.memory
	var stimulus := outcome.stimulus
	var told := stimulus.type == Stimulus.TOLD
	# (A dream is remembered however faintly what set it off came through.)
	if not outcome.direct and not told and outcome.salience < config.remember_threshold 			and outcome.interpretation != ReactionTable.DREAM:
		return null
	var memory := Memory.new()
	memory.owner_id = person.id
	memory.subject = stimulus.about if told and stimulus.about != &"" else stimulus.type
	memory.stimulus_id = stimulus.id
	memory.tick = now_tick
	memory.first_tick = now_tick
	memory.location = stimulus.position
	memory.interpretation = outcome.interpretation
	memory.emotions = outcome.emotions.duplicate()
	memory.intensity = clampf(stimulus.intensity, 0.0, 1.0)
	memory.stage = stage
	var relevance := config.relevance_witnessed
	if told:
		memory.source = Memory.Source.TOLD
		memory.told_by = stimulus.told_by
		memory.fidelity = clampf(stimulus.fidelity * config.retelling_fidelity, 0.0, 1.0)
		relevance = config.relevance_told * lerpf(0.5, 1.0, memory.fidelity)
	elif outcome.direct:
		memory.source = Memory.Source.DIRECT
		relevance = config.relevance_direct
	else:
		memory.source = Memory.Source.WITNESSED
	# Importance = intensity × how it felt × how much it was theirs × how new it was.
	var strength := lerpf(0.5, 1.0, memory.intensity) * lerpf(0.5, 1.0, outcome.salience)
	var feeling := 0.35 + 0.65 * Reactions.strongest(outcome.emotions)
	var novelty := 1.0 / (1.0 + float(times_before) * config.novelty_wear)
	memory.importance = clampf(strength * feeling * relevance * novelty, 0.0, 1.0)
	memory.text_key = MemoryText.key_for(memory.subject, memory.interpretation, memory.source, stage == PersonData.LifeStage.CHILD)
	return memory


## Keeps a person's memories within the cap: the least important go (of
## equals, the oldest). Returns how many were dropped.
func compact(person: PersonData, config: MemoryConfig = null) -> int:
	if config == null:
		config = Config.memory
	var all := of(person)
	var over := all.size() - config.max_per_person
	if over <= 0:
		return 0
	all.sort_custom(func(a: Memory, b: Memory) -> bool:
		return a.importance < b.importance or (a.importance == b.importance and (a.tick < b.tick or (a.tick == b.tick and a.id < b.id))))
	for i in over:
		forget(person, all[i].id)
	dropped += over
	return over


## Takes a memory from a person.
func forget(person: PersonData, memory_id: int) -> void:
	var at := person.memory_ids.find(memory_id)
	if at >= 0:
		person.memory_ids.remove_at(at)
	if _memories.erase(memory_id):
		forgotten.emit(person.id, memory_id)


# --- forgetting ---------------------------------------------------------------------------------

## Lets time pass for memories: once per game day everything fades a little
## (what matters much, hardly), and what no longer matters is forgotten.
## Cheap to call every frame.
func advance(now_tick: int, config: MemoryConfig = null) -> int:
	@warning_ignore("integer_division")
	var day := now_tick / TimeConfig.MINUTES_PER_DAY
	if _faded_day < 0:
		_faded_day = day
	if day <= _faded_day:
		return 0
	var days := day - _faded_day
	_faded_day = day
	return fade(days, config)


## Lets `days` game days pass for every memory. Returns how many were forgotten.
func fade(days: int, config: MemoryConfig = null) -> int:
	if config == null:
		config = Config.memory
	var gone: Array[Memory] = []
	for memory: Memory in _memories.values():
		for day in days:
			memory.importance -= config.daily_fade * (1.05 - memory.importance)
		if memory.importance < config.forget_below:
			gone.append(memory)
	for memory in gone:
		var owner := _people.get_person(memory.owner_id) if _people != null else null
		if owner != null:
			forget(owner, memory.id)
		else:
			_memories.erase(memory.id)
	return gone.size()


# --- what memories do ---------------------------------------------------------------------------

## How much a person fears a place (0 … 1): by what they remember having
## happened near it, how frightening it was and how much it still matters.
func fear_at(person: PersonData, at: Vector2, config: MemoryConfig = null) -> float:
	if person.memory_ids.is_empty():
		return 0.0
	if config == null:
		config = Config.memory
	var fear := 0.0
	for memory in of(person):
		var felt := memory.emotion(ReactionTable.Emotion.FEAR)
		if felt < config.fear_matters_from:
			continue
		var distance := memory.location.distance_to(at)
		if distance >= config.fear_radius:
			continue
		fear = maxf(fear, felt * clampf(memory.importance * 2.0, 0.0, 1.0) * (1.0 - distance / config.fear_radius))
	return clampf(fear, 0.0, 1.0)


## How much a person wonders at a kind of thing (-1 … 1): curiosity and awe,
## less the fear, in what they remember of it; 0 if they remember nothing.
func wonder_about(person: PersonData, subject: StringName) -> float:
	var weight := 0.0
	var sum := 0.0
	for memory in about(person, subject):
		var w := memory.importance * (0.5 if memory.source == Memory.Source.TOLD else 1.0)
		sum += w * (maxf(memory.emotion(ReactionTable.Emotion.CURIOSITY), memory.emotion(ReactionTable.Emotion.AWE)) \
			- memory.emotion(ReactionTable.Emotion.FEAR))
		weight += w
	return clampf(sum / weight, -1.0, 1.0) if weight > 0.0 else 0.0


## The memory a person would tell `listener` of in passing: the one that
## matters most among those recent and true enough, not told lately, and not
## something the listener was there for or has been told by them. Null if
## there is none.
func worth_telling(person: PersonData, listener: PersonData, now_tick: int, config: MemoryConfig = null) -> Memory:
	if config == null:
		config = Config.memory
	var best: Memory = null
	var theirs := of(listener) if listener != null else ([] as Array[Memory])
	for memory in of(person):
		if memory.importance < config.tell_importance or memory.fidelity < config.tell_fidelity:
			continue
		if now_tick - memory.tick > config.tell_recent_days * TimeConfig.MINUTES_PER_DAY:
			continue
		if memory.told_tick >= 0 and now_tick - memory.told_tick < config.tell_again_minutes:
			continue
		if memory.told_by == (listener.id if listener != null else 0) and memory.told_by != 0:
			continue # not back to whoever told them
		var known := false
		for other in theirs:
			if other.subject == memory.subject and (other.source != Memory.Source.TOLD or other.told_by == person.id) \
					and absi(other.tick - memory.tick) < TimeConfig.MINUTES_PER_DAY:
				known = true # they were there, or have heard it from this mouth
				break
		if known:
			continue
		if best == null or memory.importance > best.importance or (memory.importance == best.importance and memory.id < best.id):
			best = memory
	return best


# --- saving -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list: Array = []
	var ids: Array = _memories.keys()
	ids.sort()
	for id: int in ids:
		list.append((_memories[id] as Memory).to_dict())
	return {"next_id": _next_id, "faded_day": _faded_day, "memories": list}


## Restores to_dict() output. Memories whose owner is gone, or that are
## broken, are dropped; people's lists are brought in line with what there is.
func from_dict(data: Dictionary) -> int:
	clear()
	var skipped := 0
	var list: Variant = data.get("memories")
	if typeof(list) == TYPE_ARRAY:
		for record: Variant in list:
			var memory := Memory.from_dict(record) if typeof(record) == TYPE_DICTIONARY else null
			if memory == null or _memories.has(memory.id) \
					or (_people != null and memory.owner_kind == Memory.OwnerKind.PERSON and not _people.has_person(memory.owner_id)):
				skipped += 1
				continue
			_memories[memory.id] = memory
			_next_id = maxi(_next_id, memory.id + 1)
	_next_id = maxi(_next_id, int(data.get("next_id", 1)))
	_faded_day = int(data.get("faded_day", -1))
	# Everyone's list holds exactly their memories that exist.
	if _people != null:
		var listed := {}
		for person in _people.all_people():
			var kept := PackedInt64Array()
			for id in person.memory_ids:
				var memory: Memory = _memories.get(id)
				if memory != null and memory.owner_id == person.id and not listed.has(id):
					kept.append(id)
					listed[id] = true
			person.memory_ids = kept
		var ids: Array = _memories.keys()
		ids.sort()
		for id: int in ids:
			if not listed.has(id):
				var owner := _people.get_person((_memories[id] as Memory).owner_id)
				if owner != null:
					owner.memory_ids.append(id)
				else:
					_memories.erase(id)
	return skipped


func debug_text() -> String:
	return "memories %d  (%d merged, %d dropped)" % [_memories.size(), merged, dropped]


# --- internals ----------------------------------------------------------------------------------

func _merge(known: Memory, again: Memory, config: MemoryConfig) -> void:
	known.count += again.count
	known.tick = maxi(known.tick, again.tick)
	known.location = again.location
	known.stimulus_id = again.stimulus_id
	known.intensity = maxf(known.intensity, again.intensity)
	known.stage = again.stage
	# How it feels now is mostly how it felt the last time.
	for i in mini(known.emotions.size(), again.emotions.size()):
		known.emotions[i] = lerpf(known.emotions[i], again.emotions[i], 0.6)
	known.importance = clampf(maxf(known.importance, again.importance) + config.repeat_gain * (1.0 - maxf(known.importance, again.importance)), 0.0, 1.0)
	if again.source == Memory.Source.TOLD:
		# Heard again: as true as the truest telling.
		known.fidelity = maxf(known.fidelity, again.fidelity)
		known.told_by = again.told_by
	known.text_key = again.text_key
	known.text_params = again.text_params


## Moves a memory to the end of its owner's list (the most recent).
func _touch(person: PersonData, memory_id: int) -> void:
	var at := person.memory_ids.find(memory_id)
	if at >= 0 and at != person.memory_ids.size() - 1:
		person.memory_ids.remove_at(at)
		person.memory_ids.append(memory_id)


func _on_person_removed(person_id: int) -> void:
	for id: int in _memories.keys():
		var memory: Memory = _memories[id]
		if memory.owner_kind == Memory.OwnerKind.PERSON and memory.owner_id == person_id:
			_memories.erase(id)
