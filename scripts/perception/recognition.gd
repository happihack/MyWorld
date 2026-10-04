class_name Recognition
extends RefCounted
## "That person remembers what I did" (VS.5, bible §15, §26.1): someone who
## lived or saw one of the player's acts, met by another of them, knows it
## again. It shows — a sign over their head, a softer sound, "Remembers this"
## on their card — and what they remember of the new one goes back to the
## old one: "felt the touch of a spirit (2 times) — just as by the fire last
## spring".
##
## Where it happened is put in their words when it happens (by the fire, by
## the water, among the trees, up among the rocks, out in the open); when, as
## it stood then ("earlier that day", "last spring", "3 years before").

## Something of the player's again within this many game minutes of the last
## is not "again" but more of the same (a touch, and another: no sign each time).
const AFTER_MINUTES := 180
## What mattered less than this to them is not remembered on meeting it again.
const LEAST_IMPORTANCE := 0.05
## How near the fire, the water and the trees count as "by" them (tiles).
const FIRE_NEAR := 4
const WATER_NEAR := 2
const TREES_NEAR := 2
const TREES_LEAST := 2

const WHERE_FIRE := "RECALL_WHERE_FIRE"
const WHERE_WATER := "RECALL_WHERE_WATER"
const WHERE_TREES := "RECALL_WHERE_TREES"
const WHERE_ROCKS := "RECALL_WHERE_ROCKS"
const WHERE_OPEN := "RECALL_WHERE_OPEN"


## What of the player's earlier doing `person` remembers on meeting `stimulus`
## (null: nothing — it is not the player's, or they never knew of any, or it
## was only just now). Of the same kind, the one of the same kind; else what
## mattered most to them.
static func recalled(person: PersonData, stimulus: Stimulus, memories: MemoryStore) -> Memory:
	if memories == null or stimulus == null or stimulus.origin != Stimulus.Origin.PLAYER or stimulus.type == Stimulus.TOLD:
		return null
	var best: Memory = null
	var best_score := -INF
	for memory in memories.of(person):
		if memory.intervention_id == 0 or memory.intervention_id == stimulus.intervention_id \
				or memory.kind != Memory.KIND_EXPERIENCE or memory.importance < LEAST_IMPORTANCE \
				or (memory.source != Memory.Source.DIRECT and memory.source != Memory.Source.WITNESSED) \
				or memory.interpretation == ReactionTable.DREAM:
			continue
		if stimulus.tick - memory.tick < AFTER_MINUTES:
			return null # (just now: more of the same)
		var score := memory.importance + (1.0 if memory.subject == stimulus.type else 0.0)
		if score > best_score:
			best_score = score
			best = memory
	return best


## Writes into `memory` what it goes back to: `earlier` (as it was before
## anything new was added to it) and where that was, in their words.
static func note(memory: Memory, earlier: Memory, where_key: String) -> void:
	memory.recalls_subject = earlier.subject
	memory.recalls_tick = earlier.tick
	memory.recalls_where = where_key


## Where `at` (world X/Z) is, as people would say it.
static func where_key(at: Vector2, world: WorldData, props: PropRegistry, settlements: Settlements) -> String:
	var tile := WorldCoords.world2d_to_tile(at)
	if settlements != null:
		for own in settlements.all():
			var fire := own.fire()
			if fire != null and Vector2(fire.tile - tile).length() <= FIRE_NEAR:
				return WHERE_FIRE
	if world != null:
		for dy in range(-WATER_NEAR, WATER_NEAR + 1):
			for dx in range(-WATER_NEAR, WATER_NEAR + 1):
				var near := tile + Vector2i(dx, dy)
				if world.is_in_bounds(near) and world.get_water(near) > 0.05:
					return WHERE_WATER
	if props != null:
		var trees := 0
		for dy in range(-TREES_NEAR, TREES_NEAR + 1):
			for dx in range(-TREES_NEAR, TREES_NEAR + 1):
				var prop := props.prop_at(tile + Vector2i(dx, dy))
				if prop != null and prop.kind == PropData.Kind.TREE:
					trees += 1
		if trees >= TREES_LEAST:
			return WHERE_TREES
	if world != null and world.is_in_bounds(tile) and world.get_terrain(tile) == ChunkData.Terrain.ROCK:
		return WHERE_ROCKS
	return WHERE_OPEN


## When `then` was, seen from `now`: "earlier that day", "earlier that
## spring", "that spring", "last spring", "3 years before".
static func when_text(then: int, now: int) -> String:
	var time := Config.time
	var season := MemoryText.translate("SEASON_%d" % time.season_of(then)).to_lower()
	if time.day_index(then) == time.day_index(now):
		return MemoryText.translate("RECALL_WHEN_DAY")
	var years := time.year_of(now) - time.year_of(then)
	if years == 0:
		var key := "RECALL_WHEN_SEASON" if time.season_of(then) == time.season_of(now) else "RECALL_WHEN_THAT"
		return MemoryText.translate(key).format({"season": season})
	if years == 1:
		return MemoryText.translate("RECALL_WHEN_LAST").format({"season": season})
	return MemoryText.translate("RECALL_WHEN_YEARS").format({"years": years})


## A memory's words (`text`) with what it goes back to, if anything.
static func wrap(text: String, memory: Memory) -> String:
	if memory.recalls_tick < 0:
		return text
	var where := MemoryText.translate(memory.recalls_where if MemoryText.has(memory.recalls_where) else WHERE_OPEN)
	var when := when_text(memory.recalls_tick, memory.tick)
	if memory.recalls_subject == memory.subject:
		return MemoryText.translate("RECALL_SAME").format({"text": text, "where": where, "when": when})
	var what_key := "MEMWHAT_" + String(memory.recalls_subject).to_upper()
	return MemoryText.translate("RECALL_OTHER").format({"text": text, "where": where, "when": when,
		"what": MemoryText.translate(what_key if MemoryText.has(what_key) else "MEMWHAT_UNKNOWN")})
