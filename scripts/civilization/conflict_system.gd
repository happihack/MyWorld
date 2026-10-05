class_name ConflictSystem
extends RefCounted
## Strife (M19.1, bible §17.5): rare, costly, and a source of history.
##
## **Between settlements**, a tension grows, once a game day, from what sets
## them against each other — both short of food and near enough to want the
## same berries; one going hungry while the other is not; strangers to each
## other (their words have drifted apart, what they make of the Presence
## differs); old raids — and eases with trade, kinship and time. When it runs
## high: **a dispute** (told); higher, with a fierce leader and an empty
## store: **a raid** — food carried off, the raiders' names, sometimes wounds;
## raided twice within two years and still bitter: **war**. A war is fought in
## **battles** (abstracted: now and then, a clash — some fall; the bravest who
## live through it are its **heroes**); it ends in **peace** once it has cost
## enough, or a leader falls — and **a border** is drawn between them. Every
## step names what caused it (the shortage, the dispute, the raids, the war).
##
## **Within a settlement**: its people split into **factions** over what they
## make of the Presence; when most stand against their leader's belief, the
## leader may be **overthrown** (a revolution).

signal dispute(a: int, b: int, causes: Array)
signal raided(raider: int, victim: int, units: int, leader: int, causes: Array)
signal war_begun(a: int, b: int, causes: Array)
signal battle(a: int, b: int, fallen: Array, heroes: Array)
signal peace(a: int, b: int, fallen: int)
signal revolution(settlement_id: int, deposed: int)

## Tension: what a day adds, at most what it can be, and what is lost each day.
const SHARED_HUNGER := 0.06
const ONE_HUNGRY := 0.03
const STRANGERS := 0.015
const AFTER_RAID := 0.04
const EASES := 0.985
const TRADE_EASES := 0.08
const MOST := 1.0
## Near enough to want the same land (tiles between their fires).
const NEAR := 30.0
## The thresholds: a dispute, a raid, a war.
const DISPUTE_AT := 0.35
const RAID_AT := 0.55
const WAR_AT := 0.75
## Raids within this many years make a war (with this many of them).
const WAR_RAIDS := 2
const WAR_WITHIN_YEARS := 2
## A raid carries off this share of the victim's food (at most).
const RAID_TAKES := 0.3
## A leader fierce enough to raid (their aggression, -1 … 1).
const FIERCE := 0.2
## A battle on a day of war (the chance), the share of each side who may fall.
const BATTLE_CHANCE := 0.12
const FALL_CHANCE := 0.12
## Peace once this many have fallen, or this long has passed (days).
const PEACE_AFTER_FALLEN := 4
const PEACE_AFTER_DAYS := 60
## A revolution: when this share stand against the leader's belief (the chance a day).
const AGAINST := 0.6
const REVOLUTION_CHANCE := 0.01
## The cause of death in war (Lifecycle).
const CAUSE_WAR := &"war"

var settlements: Settlements
var governance: Governance
var cultures: CultureSystem
var lexicon: Lexicon
var trade: TradeSystem
## Kills a person (session: Lifecycle.die): Callable(person_id, cause, causes).
var kill := Callable()
## The event id of a settlement's latest shortage (for causes): Callable(settlement_id) -> int (0: none).
var shortage_event := Callable()
## Pair key "a:b" (a < b) -> {"tension", "raids": [ticks], "dispute": event id, "raid_events": [ids], "war": {} or
##   {"since", "fallen", "event"}, "border": bool, "trips": trade trips seen}.
var pairs: Dictionary = {}
var wars_fought := 0
var _day := -1_000_000


func bind(all: Settlements, rule: Governance, culture: CultureSystem, words: Lexicon, goods: TradeSystem, now: int) -> void:
	settlements = all
	governance = rule
	cultures = culture
	lexicon = words
	trade = goods
	_day = Config.time.day_index(now)


static func key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func pair(a: int, b: int) -> Dictionary:
	var k := key(a, b)
	if not pairs.has(k):
		pairs[k] = {"tension": 0.0, "raids": [], "dispute": 0, "raid_events": [], "war": {}, "border": false, "trips": 0}
	return pairs[k]


func tension(a: int, b: int) -> float:
	return float(pair(a, b)["tension"])


func at_war(a: int, b: int) -> bool:
	return not (pair(a, b)["war"] as Dictionary).is_empty()


func advance_to(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	_day = today
	each_day(now)


func each_day(now: int) -> void:
	_day = Config.time.day_index(now)
	if settlements == null:
		return
	var all := settlements.all()
	for i in all.size():
		for j in range(i + 1, all.size()):
			_between(all[i], all[j], now)
	for own in all:
		_factions(own, now)


func _between(a: Settlement, b: Settlement, now: int) -> void:
	var record := pair(a.id, b.id)
	var fire_a := a.fire()
	var fire_b := b.fire()
	if fire_a == null or fire_b == null:
		return
	var apart := Vector2(fire_a.tile - fire_b.tile).length()
	var hungry_a := a.shortage != Settlement.Shortage.NONE
	var hungry_b := b.shortage != Settlement.Shortage.NONE
	var t := float(record["tension"]) * EASES
	if apart <= NEAR:
		if hungry_a and hungry_b:
			t += SHARED_HUNGER
		elif hungry_a != hungry_b:
			t += ONE_HUNGRY
	if lexicon != null and lexicon.kinship(a.id, b.id) >= 0.0:
		t += STRANGERS * (1.0 - lexicon.kinship(a.id, b.id))
	if cultures != null:
		var pa: Dictionary = cultures.profiles.get(a.id, {})
		var pb: Dictionary = cultures.profiles.get(b.id, {})
		if not pa.is_empty() and not pb.is_empty() and pa.get("presence") != pb.get("presence"):
			t += STRANGERS
	# Trade eases it: each trip between them since yesterday.
	if trade != null:
		var trips := int((trade.routes.get("%d>%d" % [a.id, b.id], {}) as Dictionary).get("trips", 0)) \
			+ int((trade.routes.get("%d>%d" % [b.id, a.id], {}) as Dictionary).get("trips", 0))
		t -= TRADE_EASES * maxi(trips - int(record["trips"]), 0)
		record["trips"] = trips
	t = clampf(t, 0.0, MOST)
	record["tension"] = t
	if at_war(a.id, b.id):
		_wage(a, b, record, now)
		return
	if t >= DISPUTE_AT and int(record["dispute"]) == 0:
		record["dispute"] = -1 # (told; the event id is filled in by note_dispute)
		dispute.emit(a.id, b.id, _hunger_causes(a, b))
	if t >= RAID_AT:
		var raider := a if hungry_a and not hungry_b else (b if hungry_b and not hungry_a else (a if a.id < b.id else b))
		var victim := b if raider == a else a
		var leader := governance.leader_of(raider.id) if governance != null else 0
		var fierce := leader != 0 and raider.members().any(func(p: PersonData) -> bool:
			return p.id == leader and ReactionTable.lean(p.traits, Traits.Axis.AGGRESSION) >= FIERCE)
		var roll := float(posmod(hash([a.id, b.id, _day, "raid"]), 1000)) / 1000.0
		if fierce and raider.shortage != Settlement.Shortage.NONE and roll < t * 0.2:
			_raid(raider, victim, leader, record, now)
	var raids: Array = record["raids"]
	var recent := raids.filter(func(tick: int) -> bool: return now - tick <= WAR_WITHIN_YEARS * Config.time.ticks_per_year())
	if recent.size() >= WAR_RAIDS and t >= WAR_AT:
		record["war"] = {"since": now, "fallen": 0, "event": 0}
		wars_fought += 1
		war_begun.emit(a.id, b.id, (record["raid_events"] as Array).duplicate())


func _hunger_causes(a: Settlement, b: Settlement) -> Array:
	var out: Array = []
	if shortage_event.is_valid():
		for own in [a, b]:
			var id := int(shortage_event.call(own.id))
			if id != 0:
				out.append(id)
	return out


func _raid(raider: Settlement, victim: Settlement, leader: int, record: Dictionary, now: int) -> void:
	var taken := 0
	for resource: StringName in [&"grain", &"berries", &"meat", &"fish"]:
		var units := floori(victim.stockpile.amount(resource) * RAID_TAKES)
		if units <= 0:
			continue
		var got := victim.stockpile.take(resource, units)
		raider.stockpile.add(resource, mini(got, raider.stockpile.room(resource)))
		taken += got
	(record["raids"] as Array).append(now)
	record["tension"] = minf(float(record["tension"]) + AFTER_RAID, MOST)
	var causes: Array = []
	if int(record["dispute"]) > 0:
		causes.append(int(record["dispute"]))
	causes.append_array(_hunger_causes(raider, victim))
	raided.emit(raider.id, victim.id, taken, leader, causes)


## A day of war: perhaps a battle; peace once it has cost enough, or lasted long enough.
func _wage(a: Settlement, b: Settlement, record: Dictionary, now: int) -> void:
	var war: Dictionary = record["war"]
	var roll := float(posmod(hash([a.id, b.id, _day, "battle"]), 1000)) / 1000.0
	if roll < BATTLE_CHANCE:
		var fallen: Array = []
		var heroes: Array = []
		for own in [a, b]:
			var fighters: Array = own.members().filter(func(p: PersonData) -> bool:
				return p.life_stage(now, Config.time.ticks_per_year(), Config.people) == PersonData.LifeStage.ADULT)
			fighters.sort_custom(func(x: PersonData, y: PersonData) -> bool: return x.id < y.id)
			var bravest: PersonData = null
			for person: PersonData in fighters:
				var fate := float(posmod(hash([person.id, _day, "fall"]), 1000)) / 1000.0
				if fate < FALL_CHANCE * (1.0 - 0.5 * maxf(ReactionTable.lean(person.traits, Traits.Axis.BRAVERY), 0.0)):
					fallen.append(person.id)
				elif bravest == null or Traits.value(person.traits, Traits.Axis.BRAVERY) > Traits.value(bravest.traits, Traits.Axis.BRAVERY):
					bravest = person
			if bravest != null:
				heroes.append(bravest.id)
		battle.emit(a.id, b.id, fallen, heroes)
		# (The fallen died of this battle — told just now: its id is noted.)
		var of_it := int(war.get("battle", 0)) if int(war.get("battle", 0)) > 0 else int(war["event"])
		for id: int in fallen:
			if kill.is_valid():
				kill.call(id, CAUSE_WAR, [of_it] if of_it > 0 else [])
		war["fallen"] = int(war["fallen"]) + fallen.size()
	if int(war["fallen"]) >= PEACE_AFTER_FALLEN or now - int(war["since"]) >= PEACE_AFTER_DAYS * TimeConfig.MINUTES_PER_DAY:
		record["war"] = {}
		record["border"] = true
		record["tension"] = DISPUTE_AT * 0.5
		record["raids"] = []
		record["raid_events"] = []
		peace.emit(a.id, b.id, int(war["fallen"]))


## The event that told of a step (the session fills it in, for the causes of the next).
func note_event(a: int, b: int, what: String, event_id: int) -> void:
	var record := pair(a, b)
	match what:
		"dispute":
			record["dispute"] = event_id
		"raid":
			(record["raid_events"] as Array).append(event_id)
		"war":
			if not (record["war"] as Dictionary).is_empty():
				record["war"]["event"] = event_id
		"battle":
			if not (record["war"] as Dictionary).is_empty():
				record["war"]["battle"] = event_id


# --- within a settlement ------------------------------------------------------------------------------

## The factions of a settlement: what each of its people makes of the Presence
## most — interpretation -> how many hold it most.
static func factions(own: Settlement) -> Dictionary:
	var out := {}
	for person in own.members():
		var held := Interpretation.beliefs_of(person)
		var best := 0
		for i in held.size():
			if held[i] > held[best]:
				best = i
		if held.size() > 0 and held[best] > 0.0:
			var name := String(ReactionTable.INTERPRETATIONS[best])
			out[name] = int(out.get(name, 0)) + 1
	return out


func _factions(own: Settlement, now: int) -> void:
	if governance == null:
		return
	var leader := governance.leader_of(own.id)
	if leader == 0:
		return
	var held := factions(own)
	var leader_person: PersonData = null
	for person in own.members():
		if person.id == leader:
			leader_person = person
	if leader_person == null:
		return
	var theirs := Interpretation.beliefs_of(leader_person)
	var best := 0
	for i in theirs.size():
		if theirs[i] > theirs[best]:
			best = i
	var with_leader := int(held.get(String(ReactionTable.INTERPRETATIONS[best]), 0))
	var everyone := maxi(own.member_count(), 1)
	if float(everyone - with_leader) / everyone < AGAINST:
		return
	var roll := float(posmod(hash([own.id, _day, "revolution"]), 10000)) / 10000.0
	if roll < REVOLUTION_CHANCE:
		governance.depose(own.id, now)
		revolution.emit(own.id, leader)


func forget_settlement(settlement_id: int) -> void:
	for k: String in pairs.keys():
		var parts := k.split(":")
		if int(parts[0]) == settlement_id or int(parts[1]) == settlement_id:
			pairs.erase(k)


func to_dict() -> Dictionary:
	return {"pairs": pairs.duplicate(true), "wars": wars_fought, "day": _day}


func from_dict(data: Dictionary) -> void:
	pairs.clear()
	if typeof(data.get("pairs")) == TYPE_DICTIONARY:
		for k: Variant in data["pairs"]:
			var record: Variant = data["pairs"][k]
			if typeof(record) == TYPE_DICTIONARY and (record as Dictionary).has("tension"):
				pairs[str(k)] = (record as Dictionary).duplicate(true)
	wars_fought = int(data.get("wars", 0))
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])


func debug_text() -> String:
	var parts := PackedStringArray()
	for k: String in pairs:
		var record: Dictionary = pairs[k]
		parts.append("%s %.2f%s%s" % [k, float(record["tension"]), " WAR" if not (record["war"] as Dictionary).is_empty() else "",
			" border" if bool(record["border"]) else ""])
	return "conflict: %s  wars %d" % [", ".join(parts) if not parts.is_empty() else "-", wars_fought]
