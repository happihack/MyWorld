class_name WarParties
extends RefCounted
## War fought in the open (FC6, the owner 2026-10-08). A battle decided on a
## day of war (ConflictSystem: who falls, by the same dice as ever — and the
## sides' arms, PR6) is fought the next morning where it can be seen: each
## side's fit grown (a share, never all; the fallen-to-be and the bravest
## among them) gather at their fire, take up what weapons the stores have,
## and march to a meeting ground between the fires; the lines face each other
## and shout; then they clash in pairs, round by round, and the fallen fall
## where they stand. After, each side kneels by its fallen — who are carried
## home to be buried (the graves) — and the battle is told, its heroes named.
## With no way between the settlements, or too few to go, or away from the
## box, the battle is as it was: at once.

const GATHER := &"gather"
const MARCH := &"march"
const FACE := &"face"
const CLASH := &"clash"
const TEND := &"tend"
const HOME := &"home"

## A battle is over: told, and its fallen die (ConflictSystem.battle_done).
signal ended(a: int, b: int, fallen: Array, heroes: Array)

const CHECK_MINUTES := 10
## Out from this hour, not after that.
const FROM_HOUR := 7.0
const TO_HOUR := 13.0
## Gathering, marching (at most), facing (minutes); the clash in this many
## rounds of CHECK_MINUTES; kneeling by the fallen.
const GATHER_MINUTES := 45
const MARCH_MOST := 180
const FACE_MINUTES := 10.0
const CLASH_ROUNDS := 3
const TEND_MINUTES := 20.0
## A battle not over in this long (minutes) is told as it is.
const MOST_MINUTES := 10 * 60
## What is not fought within this long (minutes) is fought at once.
const STALE := 2 * 24 * 60
## A side: this share of its grown, at least SIDE_LEAST, at most SIDE_MOST
## (the phone: the owner's crowds) — and always its fallen-to-be and its hero.
const SIDE_SHARE := 0.6
const SIDE_LEAST := 2
const SIDE_MOST := 8
## A clash: this often a round someone standing is hurt (lightly).
const WOUND_CHANCE := 0.15
const WOUND := Vector2(0.08, 0.3)
## Lines this far either side of the middle of the ground, and so far apart along it.
const LINE_OFF := 2.0
const LINE_GAP := 1.0
const REASON := &"war_party"

var people: PersonRegistry
var behavior: BehaviorSystem
var settlements: Settlements
var pathfinder: Pathfinder
var rng: RandomNumberGenerator

var _battles: Array = [] # of Dictionary (see set_out)
var _queued: Array = [] # [a, b, fallen, heroes, tick]
var _last := -1_000_000


func bind(now: int) -> void:
	_battles.clear()
	_queued.clear()
	_last = now


func battles() -> Array:
	return _battles


## A battle has been decided (ConflictSystem): fought the next morning.
## Returns true (it will be walked, and told when it is over).
func queue(a: int, b: int, fallen: Array, heroes: Array, now: int) -> bool:
	_queued.append([a, b, fallen.duplicate(), heroes.duplicate(), now])
	return true


func advance_to(now: int) -> void:
	if behavior == null or now - _last < CHECK_MINUTES:
		return
	_last = now
	var hour := Config.time.minute_of_day(now) / 60.0
	for entry: Array in _queued.duplicate():
		if now - int(entry[4]) > STALE:
			_queued.erase(entry)
			ended.emit(int(entry[0]), int(entry[1]), entry[2], entry[3])
		elif hour >= FROM_HOUR and hour < TO_HOUR:
			_queued.erase(entry)
			set_out(int(entry[0]), int(entry[1]), entry[2], entry[3], now)
	for battle: Dictionary in _battles.duplicate():
		_act(battle, now)


## Open land halfway between their fires that both can walk to (null: none).
func meeting_ground(a: Settlement, b: Settlement) -> Variant:
	if a == null or b == null or a.fire() == null or b.fire() == null or pathfinder == null:
		return null
	var middle := (Vector2(a.fire().tile) + Vector2(b.fire().tile)) * 0.5
	var found := pathfinder.standable_near(WorldCoords.world2d_to_tile(middle), 1, 4)
	if found.is_empty() or not pathfinder.is_reachable(a.fire().tile + Vector2i(1, 0), found[0]) \
			or not pathfinder.is_reachable(b.fire().tile + Vector2i(1, 0), found[0]):
		return null
	return found[0]


## The sides gather. Returns the battle ({}: fought at once — no ground, or too few).
func set_out(a_id: int, b_id: int, fallen: Array, heroes: Array, now: int) -> Dictionary:
	var a := settlements.get_settlement(a_id)
	var b := settlements.get_settlement(b_id)
	var ground: Variant = meeting_ground(a, b)
	var sides := {}
	if ground != null:
		for own: Settlement in [a, b]:
			var side := _choose(own, fallen, heroes, now)
			if side.size() < SIDE_LEAST:
				ground = null
				break
			sides[own.id] = side
	if ground == null:
		ended.emit(a_id, b_id, fallen, heroes)
		return {}
	var battle := {"a": a_id, "b": b_id, "fallen": fallen.duplicate(), "heroes": heroes.duplicate(), "ground": ground,
		"sides": {}, "arms": {}, "falls": {}, "down": [], "phase": GATHER, "since": now, "started": now, "round": 0}
	for own: Settlement in [a, b]:
		var side: Array[PersonData] = sides[own.id]
		var ids: Array = []
		var arms := Weapons.take(own, side.size())
		for i in side.size():
			ids.append(side[i].id)
			battle["arms"][str(side[i].id)] = String(arms[i])
		battle["sides"][str(own.id)] = ids
	# (When each of the fallen falls: in which round of the clash.)
	for id: Variant in fallen:
		battle["falls"][str(int(id))] = rng.randi_range(0, CLASH_ROUNDS - 1) if rng != null else 0
	_battles.append(battle)
	_lead(battle, now)
	return battle


## Who goes from `own`: its fallen-to-be and its hero first, then the bravest
## of its able grown, up to its share.
func _choose(own: Settlement, fallen: Array, heroes: Array, now: int) -> Array[PersonData]:
	var out: Array[PersonData] = []
	if own == null:
		return out
	var able: Array[PersonData] = []
	var grown := 0
	for person in own.members():
		if person.life_stage(now, Config.time.ticks_per_year(), Config.people) != PersonData.LifeStage.ADULT:
			continue
		grown += 1
		if fallen.has(person.id) or heroes.has(person.id):
			out.append(person)
		elif _able(person):
			able.append(person)
	able.sort_custom(func(x: PersonData, y: PersonData) -> bool:
		var bx := Traits.value(x.traits, Traits.Axis.BRAVERY)
		var by := Traits.value(y.traits, Traits.Axis.BRAVERY)
		return bx > by or (bx == by and x.id < y.id))
	var size := clampi(ceili(grown * SIDE_SHARE), SIDE_LEAST, SIDE_MOST)
	for person in able:
		if out.size() >= size:
			break
		out.append(person)
	return out


func _able(person: PersonData) -> bool:
	if person.health < 0.5 or person.aboard != 0 or Health.is_ill(person):
		return false
	if not Hardship.condition_of(person, Lifecycle.PREGNANT).is_empty():
		return false
	var reason := str(person.current_action.get("reason", ""))
	return reason != "hunting_party" and reason != "raid" and reason != String(REASON)


func _act(battle: Dictionary, now: int) -> void:
	var a := settlements.get_settlement(int(battle["a"]))
	var b := settlements.get_settlement(int(battle["b"]))
	var phase := StringName(battle["phase"])
	if (a == null or b == null or now - int(battle["started"]) > MOST_MINUTES) and phase != HOME:
		_finish(battle, now)
		return
	match phase:
		GATHER:
			var there := true
			for own: Settlement in [a, b]:
				for person in _side(battle, own.id):
					there = there and Vector2(person.position).distance_to(Vector2(own.fire().tile)) <= 3.0
			if there or now - int(battle["since"]) >= GATHER_MINUTES:
				_phase(battle, MARCH, now)
		MARCH:
			var arrived := 0
			var all := 0
			for own: Settlement in [a, b]:
				var side := _side(battle, own.id)
				for i in side.size():
					all += 1
					if Vector2(side[i].position).distance_to(Vector2(_line_spot(battle, own, i, side.size()))) <= 2.0:
						arrived += 1
			if arrived >= ceili(all * 0.7) or now - int(battle["since"]) >= MARCH_MOST:
				_phase(battle, FACE, now)
		FACE:
			if now - int(battle["since"]) >= FACE_MINUTES:
				_phase(battle, CLASH, now)
		CLASH:
			_clash_round(battle, now)
		TEND:
			if now - int(battle["since"]) >= TEND_MINUTES:
				_finish(battle, now)
		HOME:
			var still := false
			for person in _everyone(battle):
				still = still or str(person.current_action.get("reason", "")) == String(REASON)
			if not still or now - int(battle["since"]) >= 6 * 60:
				_battles.erase(battle)


## A round of the clash: those whose round it is fall; the rest scuffle in
## pairs (now and then one is hurt).
func _clash_round(battle: Dictionary, now: int) -> void:
	var round := int(battle["round"])
	if round >= CLASH_ROUNDS:
		_phase(battle, TEND, now)
		return
	var down: Array = battle["down"]
	for key: String in (battle["falls"] as Dictionary):
		var id := int(key)
		if int(battle["falls"][key]) == round and not down.has(id):
			down.append(id)
			var person := people.get_person(id)
			if person != null:
				Signs.flash(person, Signs.HURT, now, MOST_MINUTES)
				behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON,
					[ReactStep.make(PersonData.Pose.SLEEP, Signs.HURT, float(MOST_MINUTES))], 9.0)
	var a := _standing(battle, int(battle["a"]))
	var b := _standing(battle, int(battle["b"]))
	for i in maxi(a.size(), b.size()):
		var x: PersonData = a[i % a.size()] if not a.is_empty() else null
		var y: PersonData = b[i % b.size()] if not b.is_empty() else null
		for pair: Array in [[x, y], [y, x]]:
			var person: PersonData = pair[0]
			var foe: PersonData = pair[1]
			if person == null or (i >= a.size() and person == x) or (i >= b.size() and person == y):
				continue
			var at := foe.world2d() if foe != null else Vector2(battle["ground"])
			behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON,
				[WalkToStep.make(WorldCoords.world2d_to_tile(at), at - Vector2(WorldCoords.world2d_to_tile(at)), 1.5, Signs.ANGRY),
					ReactStep.make(PersonData.Pose.SCUFFLE, Signs.ANGRY, float(CHECK_MINUTES), at)], 9.0)
			var guard := float(Weapons.stat(weapon_of(battle, person.id), "guard"))
			if rng != null and rng.randf() < WOUND_CHANCE * (1.0 - guard):
				Health.injure(person, Health.FIGHT, rng.randf_range(WOUND.x, WOUND.y), now)
	battle["round"] = round + 1


## Over: told (the fallen die of it and are buried), the heroes named; home
## with their weapons (but the fallen's).
func _finish(battle: Dictionary, now: int) -> void:
	if StringName(battle["phase"]) == HOME:
		return
	for key: String in (battle["arms"] as Dictionary).keys():
		if (battle["fallen"] as Array).has(int(key)) or not people.has_person(int(key)):
			(battle["arms"] as Dictionary).erase(key)
	for own_id: int in [int(battle["a"]), int(battle["b"])]:
		var own := settlements.get_settlement(own_id)
		var kinds: Array = []
		for id: Variant in battle["sides"].get(str(own_id), []):
			kinds.append(battle["arms"].get(str(int(id)), ""))
		Weapons.give_back(own, kinds)
	battle["arms"] = {}
	battle["phase"] = HOME
	battle["since"] = now
	ended.emit(int(battle["a"]), int(battle["b"]), battle["fallen"], battle["heroes"])
	for id: Variant in battle["heroes"]:
		var hero := people.get_person(int(id))
		if hero != null:
			Signs.flash(hero, Signs.NOTE, now)
	_lead(battle, now)


func _phase(battle: Dictionary, phase: StringName, now: int) -> void:
	battle["phase"] = phase
	battle["since"] = now
	if phase == CLASH:
		_clash_round(battle, now)
	else:
		_lead(battle, now)


## Everyone's plan for the phase.
func _lead(battle: Dictionary, now: int) -> void:
	var ctx := behavior.ctx
	var phase := StringName(battle["phase"])
	var ground := Vector2(battle["ground"] as Vector2i) + Vector2(0.5, 0.5)
	for own_id: int in [int(battle["a"]), int(battle["b"])]:
		var own := settlements.get_settlement(own_id)
		if own == null or own.fire() == null:
			continue
		var side := _side(battle, own_id)
		var fallen_here: Array[PersonData] = []
		for person in side:
			if (battle["down"] as Array).has(person.id):
				fallen_here.append(person)
		for i in side.size():
			var person := side[i]
			if (battle["down"] as Array).has(person.id) and phase != HOME:
				continue # (where they fell)
			person.armed = &"" if phase == HOME else Weapons.stat(weapon_of(battle, person.id), "carried")
			var steps: Array = []
			match phase:
				GATHER:
					steps = [WalkToStep.make(Planner._beside(own.fire().tile, person.position, ctx), Vector2(0.5, 0.5), 1.2),
						ReactStep.make(PersonData.Pose.IDLE, &"", float(GATHER_MINUTES))]
				MARCH:
					steps = [WalkToStep.make(_line_spot(battle, own, i, side.size()), Vector2(0.5, 0.5), 1.1),
						ReactStep.make(PersonData.Pose.IDLE, &"", float(MARCH_MOST), ground)]
				FACE:
					steps = [ReactStep.make(PersonData.Pose.YELL, Signs.ANGRY, FACE_MINUTES + CHECK_MINUTES, ground)]
				TEND:
					var by: Vector2 = fallen_here[i % fallen_here.size()].world2d() if not fallen_here.is_empty() else ground
					steps = [WalkToStep.make(Planner._beside(WorldCoords.world2d_to_tile(by), person.position, ctx)),
						ReactStep.make(PersonData.Pose.KNEEL if not fallen_here.is_empty() else PersonData.Pose.IDLE,
							Signs.SAD if not fallen_here.is_empty() else &"", TEND_MINUTES + CHECK_MINUTES, by)]
				HOME:
					steps = [WalkToStep.make(Planner._beside(own.fire().tile, person.position, ctx), Vector2(0.5, 0.5), 1.0)]
			if not steps.is_empty():
				behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON, steps, 9.0)
	if phase == HOME:
		for person in _everyone(battle):
			person.armed = &""


## Where the i-th of `own`'s side stands in its line: LINE_OFF from the
## middle of the ground on its own side, LINE_GAP apart.
func _line_spot(battle: Dictionary, own: Settlement, i: int, count: int) -> Vector2i:
	var ground := Vector2(battle["ground"] as Vector2i)
	var toward := (Vector2(own.fire().tile) - ground).normalized()
	if toward == Vector2.ZERO:
		toward = Vector2.RIGHT if own.id == int(battle["a"]) else Vector2.LEFT
	var spot := ground + toward * LINE_OFF + toward.orthogonal() * (i - (count - 1) * 0.5) * LINE_GAP
	var tile := Vector2i(roundi(spot.x), roundi(spot.y))
	if pathfinder != null and not pathfinder.can_stand(tile):
		var near := pathfinder.standable_near(tile, 1, 3)
		if not near.is_empty():
			return near[0]
		return battle["ground"]
	return tile


## What a member has in hand (Weapons kind).
static func weapon_of(battle: Dictionary, person_id: int) -> StringName:
	return StringName(str((battle.get("arms", {}) as Dictionary).get(str(person_id), "")))


func _side(battle: Dictionary, own_id: int) -> Array[PersonData]:
	var out: Array[PersonData] = []
	for id: Variant in (battle["sides"] as Dictionary).get(str(own_id), []):
		var person := people.get_person(int(id))
		if person != null:
			out.append(person)
	return out


func _standing(battle: Dictionary, own_id: int) -> Array[PersonData]:
	return _side(battle, own_id).filter(func(p: PersonData) -> bool: return not (battle["down"] as Array).has(p.id))


func _everyone(battle: Dictionary) -> Array[PersonData]:
	return _side(battle, int(battle["a"])) + _side(battle, int(battle["b"]))


func to_dict() -> Dictionary:
	var list: Array = []
	for battle: Dictionary in _battles:
		var copy := battle.duplicate(true)
		copy["phase"] = String(copy["phase"])
		copy["ground"] = [(battle["ground"] as Vector2i).x, (battle["ground"] as Vector2i).y]
		list.append(copy)
	return {"battles": list, "queued": _queued.duplicate(true), "last": _last}


func from_dict(data: Dictionary) -> void:
	_battles.clear()
	_queued.clear()
	for item: Variant in data.get("battles", []):
		if typeof(item) != TYPE_DICTIONARY or not (item as Dictionary).has("sides"):
			continue
		var battle: Dictionary = (item as Dictionary).duplicate(true)
		battle["phase"] = StringName(str(battle.get("phase", HOME)))
		var g: Variant = battle.get("ground")
		battle["ground"] = Vector2i(int(g[0]), int(g[1])) if typeof(g) == TYPE_ARRAY and (g as Array).size() == 2 else Vector2i.ZERO
		for key: String in ["fallen", "heroes", "down"]:
			var ids: Array = []
			for id: Variant in battle.get(key, []):
				ids.append(int(id))
			battle[key] = ids
		var sides := {}
		for side: Variant in (battle["sides"] as Dictionary):
			var ids: Array = []
			for id: Variant in battle["sides"][side]:
				ids.append(int(id))
			sides[str(side)] = ids
		battle["sides"] = sides
		_battles.append(battle)
	for item: Variant in data.get("queued", []):
		if typeof(item) == TYPE_ARRAY and (item as Array).size() == 5:
			_queued.append(item)
	_last = int(data.get("last", _last))
