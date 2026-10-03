class_name PlayerConsequences
extends RefCounted
## What came of the player's acts (bible §27.2, M11.4), as far as the world
## knows it now: who remembers an act (and what they make of it), and what
## the chronicle records as caused by it. (The story engine, M19, will link
## acts to outcomes further down the line: "saved a settlement from drought".)


## Who among the living remembers any of the acts `ids` (PlayerHistory ids),
## and as what: {"count": int, "as": {interpretation -> count}}.
static func remembered_by(session: WorldSession, ids: Array) -> Dictionary:
	var holders := {}
	var kinds := {}
	if session.memories == null:
		return {"count": 0, "as": {}}
	for person in session.people.all_people():
		for memory in session.memories.of(person):
			if memory.intervention_id != 0 and ids.has(memory.intervention_id) and not holders.has(person.id):
				holders[person.id] = true
				var made := String(memory.interpretation)
				kinds[made] = int(kinds.get(made, 0)) + 1
	return {"count": holders.size(), "as": kinds}


## Everyone living who remembers anything the player did.
static func people_who_remember(session: WorldSession) -> int:
	var count := 0
	if session.memories == null:
		return 0
	for person in session.people.all_people():
		for memory in session.memories.of(person):
			if memory.intervention_id != 0:
				count += 1
				break
	return count


## The events the chronicle records as caused by any of the acts `ids`
## (directly, or by what they caused), the earliest first.
static func caused(session: WorldSession, ids: Array, depth: int = 2) -> Array[WorldEvent]:
	var roots := {}
	for event in session.events.of_type(&"player_intervention"):
		if ids.has(int(event.text_params.get("intervention", 0))):
			roots[event.id] = true
	var out: Array[WorldEvent] = []
	var frontier := roots.duplicate()
	var seen := roots.duplicate()
	for step in depth:
		var next := {}
		for event in session.events.all_events():
			if seen.has(event.id):
				continue
			for cause in event.causes:
				if frontier.has(cause):
					next[event.id] = true
					seen[event.id] = true
					out.append(event)
					break
		if next.is_empty():
			break
		frontier = next
	out.sort_custom(func(a: WorldEvent, b: WorldEvent) -> bool: return a.tick < b.tick or (a.tick == b.tick and a.id < b.id))
	return out


## What came of acts, in words: ["remembered by 3 — a spirit's doing (2)", "→ Food is running short …"].
static func lines(session: WorldSession, ids: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var who := remembered_by(session, ids)
	if int(who["count"]) > 0:
		var most := ""
		var most_count := 0
		for made: String in who["as"]:
			if int(who["as"][made]) > most_count or (int(who["as"][made]) == most_count and made < most):
				most = made
				most_count = int(who["as"][made])
		var belief_key := "MEMBELIEF_" + most.to_upper()
		out.append(MemoryText.translate("HIST_REMEMBERED_BY" if most_count == int(who["count"]) else "HIST_REMEMBERED_BY_MOST").format({"count": who["count"],
			"belief": MemoryText.translate(belief_key if MemoryText.has(belief_key) else "MEMBELIEF_NATURAL"),
			"most": most_count}))
	for event in caused(session, ids).slice(0, 3):
		out.append(MemoryText.translate("HIST_LED_TO").format({"text": EventText.text(event, session.people, session.events)}))
	return out
