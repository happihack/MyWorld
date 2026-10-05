class_name ScienceSystem
extends RefCounted
## Scholars look into the unexplained (M18, bible §20.2–20.4).
##
## **Who**: a settlement's scientists (the occupation, once it knows natural
## philosophy) — and before them, once it writes, its most curious person (a
## scholar of sorts, slower at it). **What**: once a game day, they go over
## what their settlement knows of the unexplained (AnomalyArchive) and run
## **correlation checks** — the patterns that, unknown to them, reveal the
## player:
##
##   - the phenomena cluster at an hour of the day (**the player's own real
##     schedule**: "The phenomena occur mostly in the evening");
##   - rain falls from clear skies when the land is dry (**a responsive agent**);
##   - it happens where people are (**the observer looks where it acts**);
##   - nothing leaves the Edge (**enclosure**: once an expedition has studied it).
##
## Each is a **hypothesis** with a confidence that grows with the evidence;
## written up (once they write) it is told, and its discoverer named
## ("Scientists noticed a strange correlation between rainfall and your
## interactions."). Never the truth outright.
##
## **The box research track** (stages 1–4): an anomaly noticed → a pattern
## (the first hypothesis) → an external force (two hypotheses held with
## confidence) → expeditions to the Edge (with scientists, once the Edge is
## found) — each a historic step with a name to it.
##
## **Science and faith**: what their scholars publish moves those who can think
## in such terms (natural philosophy) towards PHYSICS; patterned play feeds
## science, capricious play feeds myth (CulturalMemory) — on its own.

signal hypothesis_formed(hypothesis: Dictionary)
signal stage_reached(stage: int, settlement_id: int, person_id: int)

enum Kind { TIME_OF_DAY, RESPONSIVE_RAIN, WATCHED, ENCLOSURE }
const KIND_NAMES: Array[StringName] = [&"time_of_day", &"responsive_rain", &"watched", &"enclosure"]
## Stages of the box research (bible §20.3), as far as M18 goes.
enum Stage { NONE, ANOMALY_NOTICED, PATTERN, EXTERNAL_FORCE, EDGE_EXPEDITIONS }

## No checks with fewer anomalies to go on.
const LEAST_ANOMALIES := 8
## The phenomena "cluster" when this share falls within one stretch of the day (4 real hours).
const CLUSTER_SHARE := 0.55
const CLUSTER_HOURS := 4
## Rain from a clear sky "answers" drought when this share of it fell in one (and at least this many).
const RESPONSIVE_SHARE := 0.5
const RESPONSIVE_LEAST := 3
## "Where people are": this share seen by more than one.
const WATCHED_SHARE := 0.8
const WATCHED_LEAST := 10
## A scholar (no scientist) checks this much less often.
const SCHOLAR_RATE := 0.25
## External force: this many hypotheses held at least this confidently.
const FORCE_HYPOTHESES := 2
const FORCE_CONFIDENCE := 0.6
## An expedition comes back from the Edge after this many days.
const EXPEDITION_DAYS := 12
## Each stage of the box research waits at least this long after the last (game days):
## understanding is slow (bible §20.5).
const STAGE_GAP_DAYS := 24
## What a publication does to those who can think in such terms.
const PHYSICS_NUDGE := 0.08

var archive: AnomalyArchive
var settlements: Settlements
## Has the Edge been found (by anyone)? Callable() -> bool.
var edge_known := Callable()
## Every hypothesis: {"id", "kind" (KIND_NAMES), "settlement", "by", "formed", "confidence", "evidence", "params", "published"}.
var hypotheses: Array[Dictionary] = []
var stage := Stage.NONE
## When the last stage was reached (tick).
var stage_since := 0
## The expedition to the Edge: {"settlement", "leader", "left"} ({}: none).
var expedition: Dictionary = {}
var _next := 1
var _day := -1_000_000


func bind(records: AnomalyArchive, all: Settlements, now: int) -> void:
	archive = records
	settlements = all
	_day = Config.time.day_index(now)


## Who looks into the unexplained for a settlement: its scientist (the most
## knowing of the unexplained), else — once it writes — its most curious grown
## person. [person or null, is a scientist].
func investigator(own: Settlement) -> Array:
	var best: PersonData = null
	for person in own.members():
		if person.occupation_id == &"scientist" and (best == null or Knowledge.points(person, Knowledge.Domain.ANOMALY) > Knowledge.points(best, Knowledge.Domain.ANOMALY)):
			best = person
	if best != null:
		return [best, true]
	if not own.knows_how(&"writing"):
		return [null, false]
	var year := Config.time.ticks_per_year()
	for person in own.members():
		if person.life_stage(_day * TimeConfig.MINUTES_PER_DAY, year, Config.people) == PersonData.LifeStage.CHILD:
			continue
		if best == null or Traits.value(person.traits, Traits.Axis.CURIOSITY) > Traits.value(best.traits, Traits.Axis.CURIOSITY):
			best = person
	return [best, false]


## Once a game day.
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
	if archive == null or settlements == null:
		return
	if stage == Stage.NONE and not archive.anomalies.is_empty():
		_reach(Stage.ANOMALY_NOTICED, int(archive.anomalies[0]["settlement"]), 0)
	for own in settlements.all():
		var who: Array = investigator(own)
		if who[0] == null:
			continue
		if not bool(who[1]) and float(posmod(hash([own.id, _day, "scholar"]), 1000)) / 1000.0 >= SCHOLAR_RATE:
			continue
		check(own, who[0], now)
	_research(now)


## The correlation checks of a settlement's investigator, today.
func check(own: Settlement, by: PersonData, now: int) -> void:
	var known := archive.of(own.id)
	if known.size() < LEAST_ANOMALIES:
		return
	var found := {} # kind -> [confidence, evidence, params]
	# The hour of the day (the player's real hours).
	var hours := PackedInt32Array()
	hours.resize(24)
	for anomaly in known:
		hours[posmod(int(anomaly["real_hour"]), 24)] += 1
	var best_start := 0
	var best_count := 0
	for start in 24:
		var count := 0
		for h in CLUSTER_HOURS:
			count += hours[(start + h) % 24]
		if count > best_count:
			best_count = count
			best_start = start
	var share := float(best_count) / known.size()
	if share >= CLUSTER_SHARE:
		found[Kind.TIME_OF_DAY] = [clampf((share - 0.4) * 1.5 + known.size() / 100.0, 0.05, 1.0), best_count,
			{"part": part_of_day((best_start + CLUSTER_HOURS / 2) % 24), "from": best_start}]
	# Rain from a clear sky, when the land is dry.
	var rains := known.filter(func(a: Dictionary) -> bool: return str(a["type"]) == String(Stimulus.RAIN_FROM_CLEAR_SKY))
	var in_drought := rains.filter(func(a: Dictionary) -> bool: return bool(a["drought"])).size()
	if in_drought >= RESPONSIVE_LEAST and float(in_drought) / maxi(rains.size(), 1) >= RESPONSIVE_SHARE:
		found[Kind.RESPONSIVE_RAIN] = [clampf(float(in_drought) / 8.0, 0.1, 1.0), in_drought, {}]
	# Where people are.
	var many := known.filter(func(a: Dictionary) -> bool: return int(a["witnesses"]) >= 2).size()
	if known.size() >= WATCHED_LEAST and float(many) / known.size() >= WATCHED_SHARE:
		found[Kind.WATCHED] = [clampf(float(many) / 40.0, 0.1, 1.0), many, {}]
	# Nothing leaves the Edge (an expedition has come back).
	if stage >= Stage.EDGE_EXPEDITIONS and expedition.is_empty():
		found[Kind.ENCLOSURE] = [0.5, 1, {}]
	for kind: int in found:
		var held := hypothesis_of(own.id, kind)
		var result: Array = found[kind]
		if held.is_empty():
			_form(own, by, kind, float(result[0]), int(result[1]), result[2], now)
		else:
			held["confidence"] = maxf(float(held["confidence"]), float(result[0]))
			held["evidence"] = int(result[1])
			if not bool(held["published"]) and own.knows_how(&"writing"):
				held["published"] = true
				hypothesis_formed.emit(held)


## "morning", "afternoon", "evening", "night" — of a real hour.
static func part_of_day(hour: int) -> String:
	if hour >= 5 and hour < 12:
		return "morning"
	if hour >= 12 and hour < 17:
		return "afternoon"
	if hour >= 17 and hour < 22:
		return "evening"
	return "night"


func _form(own: Settlement, by: PersonData, kind: int, confidence: float, evidence: int, params: Dictionary, now: int) -> void:
	var hypothesis := {"id": _next, "kind": String(KIND_NAMES[kind]), "settlement": own.id, "by": by.id, "formed": now,
		"confidence": confidence, "evidence": evidence, "params": params, "published": own.knows_how(&"writing")}
	_next += 1
	hypotheses.append(hypothesis)
	# What is written up moves those who can think in such terms (natural philosophy).
	var physics := ReactionTable.INTERPRETATIONS.find(ReactionTable.PHYSICS)
	if physics >= 0:
		for person in own.members():
			if person.knowledge.has("natural_philosophy"):
				var beliefs := Interpretation.beliefs_of(person)
				beliefs[physics] = minf(beliefs[physics] + PHYSICS_NUDGE, 1.0)
	if bool(hypothesis["published"]):
		hypothesis_formed.emit(hypothesis)


func hypothesis_of(settlement_id: int, kind: int) -> Dictionary:
	for hypothesis in hypotheses:
		if int(hypothesis["settlement"]) == settlement_id and str(hypothesis["kind"]) == String(KIND_NAMES[kind]):
			return hypothesis
	return {}


## The box research: from the hypotheses to an external force, and to the Edge
## — a stage at a time, and never soon after the last.
func _research(now: int) -> void:
	if expedition.is_empty() and stage != Stage.NONE and now - stage_since < STAGE_GAP_DAYS * TimeConfig.MINUTES_PER_DAY:
		return
	if stage == Stage.ANOMALY_NOTICED and not hypotheses.is_empty():
		var first: Dictionary = hypotheses[0]
		_reach(Stage.PATTERN, int(first["settlement"]), int(first["by"]))
	elif stage == Stage.PATTERN:
		var held := hypotheses.filter(func(h: Dictionary) -> bool: return float(h["confidence"]) >= FORCE_CONFIDENCE)
		if held.size() >= FORCE_HYPOTHESES:
			var last: Dictionary = held[-1]
			_reach(Stage.EXTERNAL_FORCE, int(last["settlement"]), int(last["by"]))
	elif stage == Stage.EXTERNAL_FORCE and edge_known.is_valid() and bool(edge_known.call()):
		for own in settlements.all():
			var who: Array = investigator(own)
			if who[0] != null and bool(who[1]):
				expedition = {"settlement": own.id, "leader": (who[0] as PersonData).id, "left": now}
				_reach(Stage.EDGE_EXPEDITIONS, own.id, (who[0] as PersonData).id)
				break
	if not expedition.is_empty() and now - int(expedition["left"]) >= EXPEDITION_DAYS * TimeConfig.MINUTES_PER_DAY:
		var back := expedition
		expedition = {}
		stage_reached.emit(-Stage.EDGE_EXPEDITIONS, int(back["settlement"]), int(back["leader"])) # (the expedition is back)


func _reach(to: Stage, settlement_id: int, person_id: int) -> void:
	if to <= stage:
		return
	stage = to
	stage_since = _day * TimeConfig.MINUTES_PER_DAY
	stage_reached.emit(to, settlement_id, person_id)


## In words, how sure they are: "a hunch", "a notion", "likely", "near certain".
static func confidence_word(confidence: float) -> String:
	if confidence < 0.3:
		return "SCI_HUNCH"
	if confidence < 0.55:
		return "SCI_NOTION"
	if confidence < 0.8:
		return "SCI_LIKELY"
	return "SCI_CERTAIN"


func to_dict() -> Dictionary:
	var kept: Array = []
	for hypothesis in hypotheses:
		kept.append(hypothesis.duplicate(true))
	return {"hypotheses": kept, "stage": stage, "since": stage_since, "expedition": expedition.duplicate(), "next": _next, "day": _day}


func from_dict(data: Dictionary) -> void:
	hypotheses.clear()
	if typeof(data.get("hypotheses")) == TYPE_ARRAY:
		for h: Variant in data["hypotheses"]:
			if typeof(h) == TYPE_DICTIONARY and (h as Dictionary).has_all(["id", "kind", "settlement", "confidence"]):
				hypotheses.append((h as Dictionary).duplicate(true))
	stage = clampi(int(data.get("stage", 0)), 0, Stage.size() - 1) as Stage
	stage_since = int(data.get("since", 0))
	expedition = (data["expedition"] as Dictionary).duplicate() if typeof(data.get("expedition")) == TYPE_DICTIONARY else {}
	_next = maxi(int(data.get("next", 1)), 1)
	for h in hypotheses:
		_next = maxi(_next, int(h["id"]) + 1)
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])


func debug_text() -> String:
	var parts := PackedStringArray()
	for h in hypotheses:
		parts.append("%s %.2f" % [h["kind"], float(h["confidence"])])
	return "science: stage %d  hypotheses: %s%s" % [stage, ", ".join(parts) if not parts.is_empty() else "-",
		"  (expedition at the Edge)" if not expedition.is_empty() else ""]
