class_name RaidParties
extends RefCounted
## Raids walked (FC5, the owner 2026-10-08). A raid decided in the night is
## made the next morning: the raiders' leader and a few bold ones gather at
## their fire, cross to the other settlement's stores, take an armful each —
## and, if its brave ones come out to meet them, there is a stand-off; as many
## defenders as raiders and the raiders drop what they took and flee; fewer,
## and it comes to a scuffle (a few hurt), and the raiders make off with it.
## Home, what they carry goes to their stores, and the raid is told as it
## went. (Away from the box, raids are as they were: at once.)

const GATHER := &"gather"
const CROSS := &"cross"
const STANDOFF := &"standoff"
const HOME := &"home"

## A raid is over: how much was carried off (0: driven off empty-handed).
signal done(raid: Dictionary, taken: int, repelled: bool)

const CHECK_MINUTES := 10
## Out from this hour, not after that; gathering at most this long.
const FROM_HOUR := 5.0
const TO_HOUR := 15.0
const GATHER_MINUTES := 45
## The leader and at most this many more.
const RAIDERS_MORE := 3
## Within this of the stores they take; defenders come out within SEEN of them.
const AT_STORES := 3.0
const SEEN := 10.0
## The stand-off (minutes), the scuffle (minutes) and its wounds.
const STANDOFF_MINUTES := 5.0
const SCUFFLE_MINUTES := 3.0
const SCUFFLE_WOUND := Vector2(0.1, 0.35)
const SCUFFLE_HURT := 0.35
## A raid not over in this long (minutes) is given up.
const MOST_MINUTES := 12 * 60
## What a raider takes: food, of these.
const FOODS: Array[StringName] = [&"grain", &"meat", &"fish", &"berries"]
const REASON := &"raid"

var people: PersonRegistry
var behavior: BehaviorSystem
var settlements: Settlements
var governance: Governance
var rng: RandomNumberGenerator

var _raids: Array = [] # of Dictionary
var _queued: Array = [] # [raider, victim, leader, causes, tick]
var _last := -1_000_000


func bind(now: int) -> void:
	_raids.clear()
	_queued.clear()
	_last = now


func raids() -> Array:
	return _raids


## A raid has been decided (ConflictSystem): made the next morning. Returns
## true (it will be walked).
func queue(raider_id: int, victim_id: int, leader_id: int, causes: Array, now: int) -> bool:
	_queued.append([raider_id, victim_id, leader_id, causes.duplicate(), now])
	return true


func advance_to(now: int) -> void:
	if behavior == null or now - _last < CHECK_MINUTES:
		return
	_last = now
	var hour := Config.time.minute_of_day(now) / 60.0
	if hour >= FROM_HOUR and hour < TO_HOUR:
		for entry: Array in _queued.duplicate():
			_queued.erase(entry)
			set_out(int(entry[0]), int(entry[1]), int(entry[2]), entry[3], now)
	for raid: Dictionary in _raids.duplicate():
		_act(raid, now)


## The raiders gather. Returns the raid ({} if nobody could go: then it is
## over at once, empty-handed).
func set_out(raider_id: int, victim_id: int, leader_id: int, causes: Array, now: int) -> Dictionary:
	var raider := settlements.get_settlement(raider_id)
	var victim := settlements.get_settlement(victim_id)
	var raiders := _choose(raider, leader_id, now) if raider != null else []
	var raid := {"raider": raider_id, "victim": victim_id, "leader": leader_id, "causes": causes, "members": [],
		"phase": GATHER, "since": now, "started": now, "taken": 0, "repelled": false}
	if raiders.is_empty() or victim == null or victim.fire() == null or raider.fire() == null:
		done.emit(raid, 0, true)
		return {}
	for person in raiders:
		(raid["members"] as Array).append(person.id)
	if leader_id == 0 or not (raid["members"] as Array).has(leader_id):
		raid["leader"] = raiders[0].id
	_raids.append(raid)
	_lead(raid)
	return raid


func _choose(own: Settlement, leader_id: int, now: int) -> Array[PersonData]:
	var out: Array[PersonData] = []
	var leader := people.get_person(leader_id)
	if leader != null and _able(leader, now):
		out.append(leader)
	var bold: Array[PersonData] = []
	for person in own.members():
		if person != leader and _able(person, now):
			bold.append(person)
	bold.sort_custom(func(x: PersonData, y: PersonData) -> bool:
		var bx := Traits.value(x.traits, Traits.Axis.AGGRESSION) + Traits.value(x.traits, Traits.Axis.BRAVERY)
		var by := Traits.value(y.traits, Traits.Axis.AGGRESSION) + Traits.value(y.traits, Traits.Axis.BRAVERY)
		return bx > by or (bx == by and x.id < y.id))
	for person in bold.slice(0, RAIDERS_MORE):
		out.append(person)
	return out


func _able(person: PersonData, now: int) -> bool:
	if person.life_stage(now, Config.time.ticks_per_year(), Config.people) != PersonData.LifeStage.ADULT:
		return false
	if person.health < 0.5 or person.aboard != 0:
		return false
	var reason := str(person.current_action.get("reason", ""))
	return reason != "hunting_party" and reason != String(REASON)


func _act(raid: Dictionary, now: int) -> void:
	var members := _members(raid)
	var victim := settlements.get_settlement(int(raid["victim"]))
	if members.is_empty() or victim == null or victim.fire() == null or now - int(raid["started"]) > MOST_MINUTES:
		_end(raid, now)
		return
	var stores := _stores(victim)
	var phase := StringName(raid["phase"])
	match phase:
		GATHER:
			var home := _home(raid)
			var there := true
			for person in members:
				if Vector2(person.position).distance_to(Vector2(home.fire().tile)) > 3.0:
					there = false
			if there or now - int(raid["since"]) >= GATHER_MINUTES:
				raid["phase"] = CROSS
				raid["since"] = now
				_lead(raid)
		CROSS:
			var arrived := false
			for person in members:
				arrived = arrived or Vector2(person.position).distance_to(Vector2(stores)) <= AT_STORES
			if not arrived:
				_lead(raid)
				return
			_take(raid, victim, members)
			var defenders := _defenders(victim, members, now)
			if defenders.is_empty():
				_go_home(raid, now)
				return
			raid["phase"] = STANDOFF
			raid["since"] = now
			raid["defenders"] = defenders.map(func(p: PersonData) -> int: return p.id)
			var at := _middle(members)
			for person in members:
				behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON,
					[ReactStep.make(PersonData.Pose.YELL, Signs.ANGRY, STANDOFF_MINUTES, _middle(defenders))], 8.0)
			for person in defenders:
				behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON,
					[WalkToStep.make(Planner._beside(WorldCoords.world2d_to_tile(at), person.position, behavior.ctx), Vector2(0.5, 0.5), 1.6, Signs.EXCLAIM),
						ReactStep.make(PersonData.Pose.YELL, Signs.ANGRY, STANDOFF_MINUTES, at)], 8.0)
		STANDOFF:
			if now - int(raid["since"]) < STANDOFF_MINUTES:
				return
			var defenders: Array[PersonData] = []
			for id: int in raid.get("defenders", []):
				var person := people.get_person(id)
				if person != null:
					defenders.append(person)
			if defenders.size() >= members.size():
				# Outnumbered: they drop what they took and run.
				for person in members:
					if person.carrying_amount > 0 and FOODS.has(person.carrying):
						victim.stockpile.add(person.carrying, person.carrying_amount)
						person.carrying = &""
						person.carrying_amount = 0
				raid["taken"] = 0
				raid["repelled"] = true
			else:
				# A scuffle; then off with it.
				for person: PersonData in members + defenders:
					behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON,
						[ReactStep.make(PersonData.Pose.SCUFFLE, Signs.ANGRY, SCUFFLE_MINUTES, _middle(members if defenders.has(person) else defenders))], 8.0)
					if rng != null and rng.randf() < SCUFFLE_HURT:
						Health.injure(person, Health.FIGHT, rng.randf_range(SCUFFLE_WOUND.x, SCUFFLE_WOUND.y), now)
			_go_home(raid, now)
		HOME:
			var still := false
			for person in members:
				still = still or str(person.current_action.get("reason", "")) == String(REASON)
			if not still or now - int(raid["since"]) >= 6 * 60:
				_end(raid, now)


## Each raider takes an armful from the victims' stores.
func _take(raid: Dictionary, victim: Settlement, members: Array[PersonData]) -> void:
	var taken := 0
	for person in members:
		if person.carrying_amount > 0:
			continue
		for food: StringName in FOODS:
			var have := victim.stockpile.amount(food)
			if have <= 0:
				continue
			var got := victim.stockpile.take(food, mini(behavior.ctx.carry_capacity(food), have))
			if got > 0:
				person.carrying = food
				person.carrying_amount = got
				taken += got
				break
	raid["taken"] = taken


## The victims' brave grown near the raiders (as many as there are raiders, at most).
func _defenders(victim: Settlement, raiders: Array[PersonData], now: int) -> Array[PersonData]:
	var out: Array[PersonData] = []
	var at := _middle(raiders)
	var candidates: Array[PersonData] = []
	for person in victim.members():
		if person.has_flag(PersonData.FLAG_INDOORS) or person.pose == PersonData.Pose.SLEEP:
			continue
		if person.life_stage(now, Config.time.ticks_per_year(), Config.people) != PersonData.LifeStage.ADULT:
			continue
		if person.world2d().distance_to(at) > SEEN:
			continue
		Signs.flash(person, Signs.EXCLAIM, now)
		if Traits.value(person.traits, Traits.Axis.BRAVERY) > -0.2:
			candidates.append(person)
	candidates.sort_custom(func(x: PersonData, y: PersonData) -> bool: return x.world2d().distance_to(at) < y.world2d().distance_to(at))
	for person in candidates.slice(0, raiders.size() + 1):
		out.append(person)
	return out


func _go_home(raid: Dictionary, now: int) -> void:
	raid["phase"] = HOME
	raid["since"] = now
	var carried := 0
	for person in _members(raid):
		if FOODS.has(person.carrying):
			carried += person.carrying_amount
	if not bool(raid["repelled"]):
		raid["taken"] = carried
	_lead(raid)


func _end(raid: Dictionary, _now: int) -> void:
	_raids.erase(raid)
	done.emit(raid, int(raid["taken"]), bool(raid["repelled"]))


## Their plans for the phase.
func _lead(raid: Dictionary) -> void:
	var ctx := behavior.ctx
	var home := _home(raid)
	var victim := settlements.get_settlement(int(raid["victim"]))
	if home == null or victim == null:
		return
	for person in _members(raid):
		var steps: Array = []
		match StringName(raid["phase"]):
			GATHER:
				steps = [WalkToStep.make(Planner._beside(home.fire().tile, person.position, ctx), Vector2(0.5, 0.5), 1.2),
					ReactStep.make(PersonData.Pose.IDLE, &"", float(GATHER_MINUTES))]
			CROSS:
				steps = [WalkToStep.make(Planner._beside(_stores(victim), person.position, ctx), Vector2(0.5, 0.5), 1.1),
					ReactStep.make(PersonData.Pose.CROUCH, &"", float(CHECK_MINUTES))]
			HOME:
				var stores: Variant = home.places().storage_tile(person.carrying) if person.carrying_amount > 0 else null
				if stores != null:
					steps = [WalkToStep.make(stores, Planner.STORE_STAND, 1.4), StoreStep.make()]
				else:
					steps = [WalkToStep.make(Planner._beside(home.fire().tile, person.position, ctx), Vector2(0.5, 0.5), 1.4)]
		if not steps.is_empty():
			behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON, steps, 8.0)


func _members(raid: Dictionary) -> Array[PersonData]:
	var out: Array[PersonData] = []
	for id: int in raid["members"]:
		var person := people.get_person(id)
		if person != null:
			out.append(person)
	return out


func _home(raid: Dictionary) -> Settlement:
	return settlements.get_settlement(int(raid["raider"]))


func _stores(own: Settlement) -> Vector2i:
	var stores: Variant = own.places().storage_tile(&"grain")
	return stores if stores != null else own.fire().tile


static func _middle(group: Array) -> Vector2:
	var sum := Vector2.ZERO
	for person: PersonData in group:
		sum += person.world2d()
	return sum / maxf(group.size(), 1.0)


func to_dict() -> Dictionary:
	var list: Array = []
	for raid: Dictionary in _raids:
		var copy := raid.duplicate(true)
		copy["phase"] = String(copy["phase"])
		list.append(copy)
	return {"raids": list, "queued": _queued.duplicate(true), "last": _last}


func from_dict(data: Dictionary) -> void:
	_raids.clear()
	_queued.clear()
	for item: Variant in data.get("raids", []):
		if typeof(item) == TYPE_DICTIONARY and (item as Dictionary).has("raider"):
			var raid: Dictionary = (item as Dictionary).duplicate(true)
			raid["phase"] = StringName(str(raid.get("phase", HOME)))
			var ids: Array = []
			for id: Variant in raid.get("members", []):
				ids.append(int(id))
			raid["members"] = ids
			_raids.append(raid)
	for item: Variant in data.get("queued", []):
		if typeof(item) == TYPE_ARRAY and (item as Array).size() == 5:
			_queued.append(item)
	_last = int(data.get("last", _last))
