class_name HuntingParties
extends RefCounted
## The hunting party (PR4, the owner 2026-10-08). A big predator seen near a
## settlement: two to four of its people — hunters first, then the brave and
## the fit; some refuse — gather at the fire, take up their spears, track it
## down, bring it to bay and fight it, round by round, until it is dead, gets
## away, or drives them off. A kill is butchered and carried home: its meat
## to the stores, its hide. At dusk they come home; if it is still about,
## they go out again in the morning.
##
## Weapons are a stone spear for now (D7): every member is armed alike. PR6
## makes weapons things the toolmaker makes.

## Phases of a party.
const GATHER := &"gather"
const TRACK := &"track"
const FIGHT := &"fight"
const BUTCHER := &"butcher"
const HOME := &"home"
## Outcomes.
const KILLED := &"killed"
const ESCAPED := &"escaped"
const BEATEN := &"beaten"
const DARK := &"dark"

## A party has formed; it is over (outcome; how many beasts it killed).
signal formed(party: Dictionary)
## One of them was hurt in the fight (recorded, not told: the outcome is told).
signal wounded(person_id: int, species: StringName, severity: float, settlement_id: int)
signal ended(party: Dictionary, outcome: StringName, killed: int)

## How often it acts (game minutes: one round of a fight).
const CHECK_MINUTES := 10
## How many go, by the beast (the owner: 2–4); fewer able than PARTY_LEAST: none.
const PARTY_SIZE := {&"wolf": 4, &"bear": 4, &"lion": 3, &"boar": 2}
const PARTY_LEAST := 2
## Out only by day: they set out from DAY_FROM, not after SET_OUT_BY, and are
## home by DUSK.
const DAY_FROM := 6.0
const SET_OUT_BY := 16.0
const DUSK := 19.0
## Gathering: until all are at the fire, or this long.
const GATHER_MINUTES := 60
## Within this of it they bring it to bay.
const ENGAGE := 3.0
## A fight nobody is up with for this many rounds: back to tracking it; one
## that goes on this long (minutes): it gets away. Tracking that gets no
## nearer for this long (minutes): it is out of their reach — home.
const OUT_OF_REACH_ROUNDS := 3
const FIGHT_MOST := 120
const TRACK_STUCK := 60
## Not able: health below this.
const ABLE_HEALTH := 0.6
## The timid (bravery below this) refuse this often — never a hunter.
const TIMID := -0.35
const REFUSE := 0.5
## The fight. A member's thrust: STRIKE_BASE + STRIKE_SKILL × hunter skill +
## the spear's SPEAR_HIT; a hit does SPEAR_DAMAGE. The beast strikes back at
## one of them: BEAST_HIT_BASE + BEAST_HIT_DANGER × its danger; the wound its
## danger × 0.35 … 1, less SPEAR_GUARD (the spear keeps it off). Now and then
## (GRAVE_CHANCE a hit) a wound is grave — its danger and more — and the
## worst of those kill (KILL_FROM, KILL_SHARE: the owner, death rare).
const STRIKE_BASE := 0.35
const STRIKE_SKILL := 0.4
const SPEAR_HIT := 0.1
const SPEAR_DAMAGE := 1.0
const SPEAR_GUARD := 0.3
const BEAST_HIT_BASE := 0.3
const BEAST_HIT_DANGER := 0.4
const GRAVE_CHANCE := 0.03
const GRAVE_MORE := 0.25
const KILL_FROM := 0.9
const KILL_SHARE := 0.5
## Badly hurt (this severity and more): two of them, or the leader, and the
## party breaks.
const BADLY_HURT := 0.45
## A beast brought below this share of its strength may get away (this often a round).
const ESCAPE_BELOW := 0.35
const ESCAPE_CHANCE := 0.25
## A pack: when this share of it is down, the rest flee for good.
const PACK_BREAKS := 0.5
## What a hunt teaches (hunter skill), and how long the butchering takes.
const SKILL_GAIN := 0.05
const BUTCHER_MINUTES := 30
## The plans' reason (BehaviorSystem): members are held to it (ACTIVITY_CALLED).
const REASON := &"hunting_party"
## Away, a fight lasts at most this many rounds.
const AWAY_ROUNDS := 15

var fauna: AnimalSystem
var people: PersonRegistry
var behavior: BehaviorSystem
var settlements: Settlements
var watch: PredatorWatch
var rng: RandomNumberGenerator
var day_log: DayLog
## Callable(person: PersonData, cause: StringName): someone dies.
var kill: Callable
## The kill's meat lies at the kill while they butcher it (PR5): piles.
var piles: PileStore
## Callable(person: PersonData, subject: StringName, importance: float): a memory (Lifecycle.remember_life).
var remember: Callable

var _parties: Array = [] # of Dictionary (see _form)
var _formed_day: Dictionary = {} # beast group -> the day a party last went after it
var _next_id := 1
var _last := -1_000_000


func bind(now: int) -> void:
	_parties.clear()
	_formed_day.clear()
	_last = now


func parties() -> Array:
	return _parties


func party_of(person_id: int) -> Dictionary:
	for party: Dictionary in _parties:
		if (party["members"] as Array).has(person_id):
			return party
	return {}


func advance_to(now: int) -> void:
	if fauna == null or watch == null or now - _last < CHECK_MINUTES:
		return
	_last = now
	var hour := Config.time.minute_of_day(now) / 60.0
	for party: Dictionary in _parties.duplicate():
		_act(party, now, hour)
	if hour >= DAY_FROM and hour < SET_OUT_BY:
		_form_where_needed(now)


# --- forming -------------------------------------------------------------------------------------------

func _form_where_needed(now: int) -> void:
	var today := Config.time.day_index(now)
	for group: int in watch.known_groups():
		var seen := watch.known(group)
		if seen.is_empty() or fauna.of_group(group).is_empty():
			continue
		var busy := false
		for party: Dictionary in _parties:
			if int(party["group"]) == group:
				busy = true
		if busy or int(_formed_day.get(group, -1)) == today:
			continue
		_formed_day[group] = today
		form(group, int(seen["settlement"]), StringName(seen["species"]), now)


## Gathers a party against a beast (a pack). Returns it ({} if too few are able).
func form(group: int, settlement_id: int, species: StringName, now: int) -> Dictionary:
	var own := settlements.get_settlement(settlement_id) if settlements != null else null
	if own == null or own.fire() == null:
		return {}
	var chosen := choose(own, int(PARTY_SIZE.get(species, 3)), now)
	if chosen.size() < PARTY_LEAST:
		return {}
	var strength := 0.0
	var def := fauna.species.get_def(species)
	for beast in fauna.of_group(group):
		strength += def.strength if def != null else 3.0
	var ids: Array = []
	for person in chosen:
		ids.append(person.id)
	var party := {"id": _next_id, "settlement": settlement_id, "group": group, "species": String(species),
		"leader": chosen[0].id, "members": ids, "phase": GATHER, "since": now, "strength": strength, "full": strength,
		"hurt": [], "killed": 0, "pack": fauna.of_group(group).size(), "meat": 0, "hides": 0}
	_next_id += 1
	_parties.append(party)
	for person in chosen:
		if day_log != null:
			day_log.note(person.id, now, "life", "hunting_party")
	_lead(party, now)
	formed.emit(party)
	return party


## Away (offline, M20): a party against a beast lived through at once — the
## same rounds, nobody walking anywhere. Returns the outcome (&"": too few to go).
func resolve_away(group: int, settlement_id: int, species: StringName, now: int) -> StringName:
	_formed_day[group] = Config.time.day_index(now)
	var party := form(group, settlement_id, species, now)
	if party.is_empty():
		return &""
	party["phase"] = FIGHT
	party["since"] = now
	for round in AWAY_ROUNDS:
		var beasts := fauna.of_group(group)
		if beasts.is_empty():
			break
		_round(party, beasts, _members(party), now, true)
		if StringName(party["phase"]) != FIGHT:
			break
	if StringName(party["phase"]) == FIGHT:
		fauna.hold(group, 0)
		_go_home(party, now, ESCAPED)
	elif StringName(party["phase"]) == BUTCHER:
		_go_home(party, now, KILLED)
	_parties.erase(party)
	return StringName(party.get("outcome", ""))


## Who goes: the able grown (hunters first, then by skill and courage) — the
## timid may refuse. The best of them leads (first).
func choose(own: Settlement, size: int, now: int) -> Array[PersonData]:
	var scored: Array = []
	for person in own.members():
		if not _able(person, now) or not party_of(person.id).is_empty():
			continue
		var bravery := float(person.traits[Traits.Axis.BRAVERY]) if person.traits.size() > Traits.Axis.BRAVERY else 0.0
		var hunter := person.occupation_id == &"hunter"
		if not hunter and bravery < TIMID and rng != null and rng.randf() < REFUSE:
			continue # (they will not go)
		var skill := float(person.skills.get("hunter", 0.0))
		scored.append([(2.0 if hunter else 0.0) + skill * 2.0 + bravery + person.health, person])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and (a[1] as PersonData).id < (b[1] as PersonData).id))
	var out: Array[PersonData] = []
	for entry: Array in scored.slice(0, size):
		out.append(entry[1])
	return out


func _able(person: PersonData, now: int) -> bool:
	if person.life_stage(now, Config.time.ticks_per_year(), Config.people) != PersonData.LifeStage.ADULT:
		return false
	if person.health < ABLE_HEALTH or Health.is_ill(person) or person.aboard != 0:
		return false
	return Hardship.condition_of(person, Lifecycle.PREGNANT).is_empty()


# --- acting ----------------------------------------------------------------------------------------------

func _act(party: Dictionary, now: int, hour: float) -> void:
	_drop_the_fallen(party)
	var members := _members(party)
	var phase := StringName(party["phase"])
	var beasts := fauna.of_group(int(party["group"]))
	if members.size() < PARTY_LEAST and phase != HOME and phase != BUTCHER:
		_go_home(party, now, BEATEN if phase == FIGHT else DARK)
		return
	if beasts.is_empty() and (phase == GATHER or phase == TRACK or phase == FIGHT):
		_go_home(party, now, ESCAPED) # (gone back to the wilds)
		return
	if hour >= DUSK and (phase == GATHER or phase == TRACK or phase == FIGHT):
		fauna.hold(int(party["group"]), 0)
		_go_home(party, now, DARK if phase != FIGHT else ESCAPED)
		return
	match phase:
		GATHER:
			var fire := Vector2(_own(party).fire().tile)
			var there := true
			for person in members:
				if Vector2(person.position).distance_to(fire) > 3.0:
					there = false
			if there or now - int(party["since"]) >= GATHER_MINUTES:
				party["phase"] = TRACK
				party["since"] = now
		TRACK:
			var nearest := _nearest(beasts, _middle(members))
			var gap := _middle(members).distance_to(nearest.position)
			var closest := INF
			for person in members:
				closest = minf(closest, person.world2d().distance_to(nearest.position))
			if closest <= ENGAGE:
				party["phase"] = FIGHT
				party["since"] = now
				party["idle"] = 0
				fauna.hold(int(party["group"]), now + 24 * 60)
			else:
				# (Getting no nearer: out of their reach — across water, up a cliff.)
				if gap < float(party.get("best", INF)) - 0.5:
					party["best"] = gap
					party["best_at"] = now
				elif now - int(party.get("best_at", now)) >= TRACK_STUCK:
					_go_home(party, now, DARK)
					return
		FIGHT:
			if now - int(party["since"]) >= FIGHT_MOST:
				fauna.hold(int(party["group"]), 0)
				_go_home(party, now, ESCAPED)
				return
			_round(party, beasts, members, now)
			if StringName(party["phase"]) != FIGHT:
				return
		BUTCHER:
			if now - int(party["since"]) >= BUTCHER_MINUTES:
				_go_home(party, now, KILLED)
				return
		HOME:
			# (They have their plans home: once those are done, the party is over.)
			var still := false
			for person in members:
				if str(person.current_action.get("reason", "")) == String(REASON):
					still = true
			if not still or now - int(party["since"]) >= 6 * 60:
				_parties.erase(party)
			return
	_lead(party, now)


## One round of the fight: their thrusts, then the beast's.
func _round(party: Dictionary, beasts: Array[AnimalData], members: Array[PersonData], now: int, all_up: bool = false) -> void:
	var def := fauna.species.get_def(StringName(party["species"]))
	var target := _nearest(beasts, _middle(members))
	var up := 0
	for person in members:
		if not all_up and person.world2d().distance_to(target.position) > ENGAGE + 1.0:
			continue # (not up with it yet)
		up += 1
		var skill := float(person.skills.get("hunter", 0.0))
		if rng.randf() < STRIKE_BASE + STRIKE_SKILL * skill + SPEAR_HIT:
			party["strength"] = float(party["strength"]) - SPEAR_DAMAGE
	if up == 0:
		party["idle"] = int(party.get("idle", 0)) + 1
		if int(party["idle"]) >= OUT_OF_REACH_ROUNDS:
			fauna.hold(int(party["group"]), 0)
			party["phase"] = TRACK
			party["since"] = now
			party.erase("best")
		return # (nobody up with it: no blows either way)
	party["idle"] = 0
	# A pack: one down for every one's worth of strength taken (the one they
	# are at first).
	var per := def.strength if def != null else 3.0
	var down_should := int(floor((float(party["full"]) - float(party["strength"])) / per + 0.0001))
	while int(party["killed"]) < down_should and not beasts.is_empty():
		var falls: AnimalData = target if beasts.has(target) else beasts.back()
		beasts.erase(falls)
		_slain(party, falls)
		if not beasts.is_empty():
			target = _nearest(beasts, _middle(members))
	if beasts.is_empty() or float(party["strength"]) <= 0.0:
		for rest in beasts:
			_slain(party, rest)
		_won(party, now)
		return
	if int(party["pack"]) > 1 and int(party["killed"]) >= ceili(int(party["pack"]) * PACK_BREAKS):
		fauna.send_off(int(party["group"])) # (the rest flee for good)
		_won(party, now)
		return
	# The beast strikes back at one of those up with it.
	var near: Array[PersonData] = []
	for person in members:
		if all_up or person.world2d().distance_to(target.position) <= ENGAGE + 1.0:
			near.append(person)
	if near.is_empty():
		return
	var victim: PersonData = near[rng.randi_range(0, near.size() - 1)]
	if rng.randf() < BEAST_HIT_BASE + BEAST_HIT_DANGER * def.danger:
		var severity := def.danger * rng.randf_range(0.35, 1.0) * (1.0 - SPEAR_GUARD)
		if rng.randf() < GRAVE_CHANCE:
			severity = def.danger + GRAVE_MORE
		severity = clampf(severity, 0.05, 1.0)
		Health.injure(victim, Health.MAULED, severity, now)
		wounded.emit(victim.id, StringName(party["species"]), severity, int(party["settlement"]))
		if severity >= KILL_FROM and rng.randf() < KILL_SHARE and kill.is_valid():
			kill.call(victim, Lifecycle.CAUSE_MAULED)
			(party["members"] as Array).erase(victim.id)
			if victim.id == int(party["leader"]):
				_go_home(party, now, BEATEN)
				fauna.hold(int(party["group"]), 0)
				return
		elif severity >= BADLY_HURT:
			(party["hurt"] as Array).append(victim.id)
	if (party["hurt"] as Array).size() >= 2 or (party["hurt"] as Array).has(int(party["leader"])):
		fauna.hold(int(party["group"]), 0)
		_go_home(party, now, BEATEN)
		return
	# Badly hurt, it may get away.
	if float(party["strength"]) < float(party["full"]) * ESCAPE_BELOW and rng.randf() < ESCAPE_CHANCE:
		fauna.hold(int(party["group"]), 0)
		for beast in beasts:
			fauna.startle_one(beast.id, _middle(members), now)
		_go_home(party, now, ESCAPED)


func _slain(party: Dictionary, beast: AnimalData) -> void:
	var def := fauna.species.get_def(beast.species)
	if fauna.slay(beast.id) == &"":
		return
	party["killed"] = int(party["killed"]) + 1
	party["meat"] = int(party["meat"]) + (def.meat if def != null else 0)
	party["hides"] = int(party["hides"]) + (def.hide if def != null else 0)
	party["at"] = beast.position
	# (Its meat, laid out where it fell, to be butchered: PR5.)
	if piles != null and def != null and def.meat > 0:
		piles.add(&"meat", def.meat, beast.position)


func _won(party: Dictionary, now: int) -> void:
	party["phase"] = BUTCHER
	party["since"] = now
	for person in _members(party):
		person.skills["hunter"] = minf(float(person.skills.get("hunter", 0.0)) + SKILL_GAIN, 1.0)
	_lead(party, now)


## Home: the meat in their arms (what they cannot carry, and the hides, the
## others fetch: into the stores), and the party is told of.
func _go_home(party: Dictionary, now: int, outcome: StringName) -> void:
	party["phase"] = HOME
	party["since"] = now
	party["outcome"] = String(outcome)
	var own := _own(party)
	var meat := int(party["meat"])
	if outcome == KILLED and piles != null and party.has("at"):
		piles.take(&"meat", meat, party["at"], 3.0) # (off the ground: in arms, or fetched to the stores)
	if outcome == KILLED and own != null:
		for person in _members(party):
			if remember.is_valid():
				remember.call(person, StringName("life_slew_" + String(party["species"])), 0.8)
		for person in _members(party):
			if meat <= 0:
				break
			if person.carrying_amount > 0 and person.carrying != &"meat":
				continue
			var room := behavior.ctx.carry_capacity(&"meat") - person.carrying_amount
			var takes := mini(room, meat)
			if takes > 0:
				person.carrying = &"meat"
				person.carrying_amount += takes
				meat -= takes
		if meat > 0:
			own.stockpile.add(&"meat", meat)
		if int(party["hides"]) > 0:
			own.stockpile.add(&"hide", int(party["hides"]))
		own.note_produced(&"meat", int(party["meat"]))
	_lead(party, now)
	ended.emit(party, outcome, int(party["killed"]))


## Gives every member their plan for the phase (again each round).
func _lead(party: Dictionary, now: int) -> void:
	var own := _own(party)
	if own == null:
		return
	var ctx := behavior.ctx
	var phase := StringName(party["phase"])
	var beasts := fauna.of_group(int(party["group"]))
	var members := _members(party)
	for i in members.size():
		var person := members[i]
		var steps: Array = []
		match phase:
			GATHER:
				steps = [WalkToStep.make(Planner._beside(own.fire().tile, person.position, ctx), Vector2(0.5, 0.5), 1.3),
					ReactStep.make(PersonData.Pose.IDLE, &"", float(GATHER_MINUTES))]
			TRACK:
				var to := _nearest(beasts, person.world2d()).position
				var spot := Planner._beside(WorldCoords.world2d_to_tile(to), person.position, ctx)
				steps = [WalkToStep.make(spot, Vector2(0.5, 0.5), 1.2), ReactStep.make(PersonData.Pose.IDLE, &"", float(CHECK_MINUTES))]
			FIGHT:
				var beast := _nearest(beasts, _middle(members))
				var around := beast.position + Vector2.RIGHT.rotated(TAU * i / maxf(members.size(), 1.0)) * 1.1
				steps = [WalkToStep.make(WorldCoords.world2d_to_tile(around), around - Vector2(WorldCoords.world2d_to_tile(around)), 1.4, &"exclaim"),
					ReactStep.make(PersonData.Pose.WORK, &"exclaim", float(CHECK_MINUTES), beast.position)]
			BUTCHER:
				var at: Vector2 = party.get("at", person.world2d())
				steps = [WalkToStep.make(Planner._beside(WorldCoords.world2d_to_tile(at), person.position, ctx)),
					ReactStep.make(PersonData.Pose.CROUCH, &"", float(BUTCHER_MINUTES), at)]
			HOME:
				var stores: Variant = own.places().storage_tile(&"meat") if person.carrying_amount > 0 else null
				if stores != null:
					steps = [WalkToStep.make(stores, Planner.STORE_STAND), StoreStep.make()]
				else:
					steps = [WalkToStep.make(Planner._beside(own.fire().tile, person.position, ctx))]
		if not steps.is_empty():
			behavior.set_plan(person, BehaviorSystem.ACTIVITY_CALLED, REASON, steps, 8.0)


func _drop_the_fallen(party: Dictionary) -> void:
	var still: Array = []
	for id: int in party["members"]:
		if people.has_person(id):
			still.append(id)
	party["members"] = still


func _members(party: Dictionary) -> Array[PersonData]:
	var out: Array[PersonData] = []
	for id: int in party["members"]:
		var person := people.get_person(id)
		if person != null:
			out.append(person)
	return out


func _own(party: Dictionary) -> Settlement:
	return settlements.get_settlement(int(party["settlement"])) if settlements != null else null


static func _nearest(beasts: Array[AnimalData], from: Vector2) -> AnimalData:
	var best: AnimalData = null
	for beast in beasts:
		if best == null or beast.position.distance_squared_to(from) < best.position.distance_squared_to(from):
			best = beast
	return best


static func _middle(members: Array[PersonData]) -> Vector2:
	var sum := Vector2.ZERO
	for person in members:
		sum += person.world2d()
	return sum / maxf(members.size(), 1.0)


func to_dict() -> Dictionary:
	var list: Array = []
	for party: Dictionary in _parties:
		var copy := party.duplicate(true)
		if copy.has("at"):
			copy["at_x"] = (copy["at"] as Vector2).x
			copy["at_z"] = (copy["at"] as Vector2).y
			copy.erase("at")
		copy["phase"] = String(copy["phase"])
		list.append(copy)
	var days := {}
	for group: int in _formed_day:
		days[str(group)] = _formed_day[group]
	return {"parties": list, "formed_day": days, "next_id": _next_id, "last": _last}


func from_dict(data: Dictionary) -> void:
	_parties.clear()
	_formed_day.clear()
	for item: Variant in data.get("parties", []):
		if typeof(item) != TYPE_DICTIONARY or not (item as Dictionary).has("group"):
			continue
		var party: Dictionary = (item as Dictionary).duplicate(true)
		party["phase"] = StringName(str(party.get("phase", HOME)))
		if party.has("at_x"):
			party["at"] = Vector2(float(party["at_x"]), float(party["at_z"]))
		var ids: Array = []
		for id: Variant in party.get("members", []):
			ids.append(int(id))
		party["members"] = ids
		var hurt: Array = []
		for id: Variant in party.get("hurt", []):
			hurt.append(int(id))
		party["hurt"] = hurt
		_parties.append(party)
	var days: Variant = data.get("formed_day")
	if typeof(days) == TYPE_DICTIONARY:
		for key: Variant in days:
			_formed_day[int(str(key))] = int(days[key])
	_next_id = maxi(int(data.get("next_id", 1)), 1)
	_last = int(data.get("last", _last))
