class_name CivilizationPhase
extends RefCounted
## The broad phases of a civilization (bible §22.1, M16.3) — derived from the
## world as it is, never timed: primitive survival → settlement → agriculture
## → villages → cities → civilization → scientific development → … Each phase
## is entered when its rule holds and every rule before it does too. The first
## time a phase is reached, history says an age has begun (an event); the
## phase now may fall back (a town that empties), the ages reached stay.

enum Phase { PRIMITIVE, SETTLEMENT, AGRICULTURE, VILLAGES, CITIES, CIVILIZATION, SCIENCE, INDUSTRY, ADVANCED,
	BOX_INVESTIGATION, OUTSIDE }
const NAMES: Array[StringName] = [&"primitive", &"settlement", &"agriculture", &"villages", &"cities", &"civilization",
	&"science", &"industry", &"advanced", &"box_investigation", &"outside"]
## Fields feed at least this share of what is brought in for the age of agriculture.
const FARMS_FEED := 0.5
const FOODS: Array[String] = ["berries", "grain", "meat", "fish"]
## What counts as a settlement's specialization (a village's workshops).
const SPECIALIZED: Array[int] = [PropData.Kind.WORKSHOP, PropData.Kind.KILN, PropData.Kind.HERB_RACK]


## The phase the world is in now.
static func evaluate(settlements: Settlements, props: PropRegistry, trade: TradeSystem = null) -> Phase:
	if settlements == null or settlements.size() == 0:
		return Phase.PRIMITIVE
	var phase := Phase.PRIMITIVE
	for next: Phase in [Phase.SETTLEMENT, Phase.AGRICULTURE, Phase.VILLAGES, Phase.CITIES, Phase.CIVILIZATION,
			Phase.SCIENCE, Phase.INDUSTRY, Phase.ADVANCED]:
		if not holds(next, settlements, props, trade):
			break
		phase = next
	return phase


## Does the rule of `phase` hold now?
static func holds(phase: Phase, settlements: Settlements, props: PropRegistry, trade: TradeSystem = null) -> bool:
	match phase:
		Phase.PRIMITIVE:
			return true
		Phase.SETTLEMENT:
			# Homes to stay in, and stores to keep what is gathered.
			return _standing(props, PropData.Kind.HUT) and _standing(props, PropData.Kind.STOREHOUSE)
		Phase.AGRICULTURE:
			return settlements.all().any(func(own: Settlement) -> bool:
				return own.knows_how(&"agriculture") and farms_feed(own) >= FARMS_FEED)
		Phase.VILLAGES:
			return settlements.all().any(func(own: Settlement) -> bool:
				return own.tier() >= Settlements.Tier.VILLAGE and _specialized(own, props))
		Phase.CITIES:
			return settlements.all().any(func(own: Settlement) -> bool:
				return own.tier() >= Settlements.Tier.TOWN and own.knows_how(&"writing"))
		Phase.CIVILIZATION:
			return settlements.size() >= 2 and trade != null and not trade.routes.is_empty()
		Phase.SCIENCE:
			return settlements.all().any(func(own: Settlement) -> bool: return own.knows_how(&"scientific_method"))
		Phase.INDUSTRY:
			return settlements.all().any(func(own: Settlement) -> bool: return own.knows_how(&"industrialization"))
		Phase.ADVANCED:
			return settlements.all().any(func(own: Settlement) -> bool:
				return own.knows_how(&"electricity") or own.knows_how(&"computing"))
	return false # (the box and the world outside: with the research lines, later)


## What share of the food a settlement has brought in of late came from its fields.
static func farms_feed(own: Settlement) -> float:
	var all := 0.0
	for food in FOODS:
		all += float(own.produced.get(food, 0.0))
	return float(own.produced.get("grain", 0.0)) / all if all > 0.0 else 0.0


static func _standing(props: PropRegistry, kind: int) -> bool:
	if props == null:
		return false
	for prop in props.of_kind(kind):
		if prop.kind == kind:
			return true
	return false


static func _specialized(own: Settlement, props: PropRegistry) -> bool:
	if own.planner != null:
		for kind in SPECIALIZED:
			if not own.planner.standing_near(kind).is_empty():
				return true
	return own.members().any(func(p: PersonData) -> bool: return p.occupation_id == &"toolmaker" or p.occupation_id == &"trader")
