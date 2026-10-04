class_name StatsCatalog
extends RefCounted
## What each of the world's numbers is (M15, bible §27.1): its tab, its name,
## how it is written, and when it is shown — **only once the system behind it
## gives anything** (bible: start with population, food and weather; the rest
## as systems come alive; never overwhelm).

const POPULATION := &"population"
const ECONOMY := &"economy"
const SOCIETY := &"society"
const ENVIRONMENT := &"environment"
const PLAYER := &"player"
const TABS: Array[StringName] = [POPULATION, ECONOMY, SOCIETY, ENVIRONMENT, PLAYER]

## How a number is written.
enum Format { COUNT, DAYS, SHARE, DEGREES, AMOUNT, YEARS, RAIN }

## [series, tab, format, shown from the start (else: once it has been other than nothing)]
const STATS: Array = [
	[&"population", POPULATION, Format.COUNT, true],
	[&"births", POPULATION, Format.COUNT, false],
	[&"deaths", POPULATION, Format.COUNT, false],
	[&"average_age", POPULATION, Format.YEARS, true],
	[&"children", POPULATION, Format.COUNT, false],
	[&"adults", POPULATION, Format.COUNT, true],
	[&"elders", POPULATION, Format.COUNT, false],
	[&"settlements", POPULATION, Format.COUNT, true],
	[&"migrants", POPULATION, Format.COUNT, false],
	[&"health", POPULATION, Format.SHARE, true],
	[&"nutrition", POPULATION, Format.SHARE, true],
	[&"sick", POPULATION, Format.COUNT, false],
	[&"food", ECONOMY, Format.AMOUNT, true],
	[&"food_days", ECONOMY, Format.DAYS, true],
	[&"water", ECONOMY, Format.AMOUNT, true],
	[&"wood", ECONOMY, Format.COUNT, false],
	[&"stone", ECONOMY, Format.COUNT, false],
	[&"tools", ECONOMY, Format.COUNT, false],
	[&"produced", ECONOMY, Format.AMOUNT, false],
	[&"trade", ECONOMY, Format.COUNT, false],
	[&"buildings", ECONOMY, Format.COUNT, false],
	[&"fields", ECONOMY, Format.COUNT, false],
	[&"mood", SOCIETY, Format.SHARE, true],
	[&"fear", SOCIETY, Format.SHARE, false],
	[&"trust", SOCIETY, Format.SHARE, false],
	[&"friendships", SOCIETY, Format.COUNT, false],
	[&"conflict", SOCIETY, Format.COUNT, false],
	[&"temperature", ENVIRONMENT, Format.DEGREES, true],
	[&"rainfall", ENVIRONMENT, Format.RAIN, false],
	[&"forest", ENVIRONMENT, Format.SHARE, true],
	[&"grass", ENVIRONMENT, Format.SHARE, true],
	[&"trees", ENVIRONMENT, Format.COUNT, true],
	[&"wildlife", ENVIRONMENT, Format.COUNT, false],
	[&"soil", ENVIRONMENT, Format.SHARE, true],
	[&"interventions", PLAYER, Format.COUNT, false],
	[&"remembered", PLAYER, Format.COUNT, false],
	[&"divine", PLAYER, Format.SHARE, false],
	[&"natural", PLAYER, Format.SHARE, false],
]


static func entry(name: StringName) -> Array:
	for stat: Array in STATS:
		if stat[0] == name:
			return stat
	return []


static func label(name: StringName) -> String:
	return MemoryText.translate("STAT_" + String(name).to_upper())


## The numbers of a tab that are shown now.
static func shown(stats: StatsRecorder, tab: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for stat: Array in STATS:
		if stat[1] == tab and (bool(stat[3]) or stats.has_data(stat[0])):
			out.append(stat[0])
	return out


## The tabs with anything in them.
static func tabs(stats: StatsRecorder) -> Array[StringName]:
	var out: Array[StringName] = []
	for tab in TABS:
		if tab == PLAYER or not shown(stats, tab).is_empty():
			out.append(tab)
	return out


## A number in words: "8", "4.2 days", "82%", "9°", "1.3 mm".
static func text(name: StringName, value: float) -> String:
	var stat := entry(name)
	var format: int = stat[2] if not stat.is_empty() else Format.COUNT
	match format:
		Format.DAYS:
			return MemoryText.translate("STATS_DAYS").format({"days": snappedf(value, 0.1) if value < 10.0 else roundi(value)})
		Format.SHARE:
			return "%d%%" % roundi(value * 100.0)
		Format.DEGREES:
			return UIText.temperature_text(value)
		Format.YEARS:
			return MemoryText.translate("STAT_YEARS").format({"years": snappedf(value, 0.1)})
		Format.RAIN:
			return MemoryText.translate("STAT_RAIN").format({"rain": snappedf(value, 0.1)})
		Format.AMOUNT:
			return String.num_int64(roundi(value))
	return String.num_int64(roundi(value))


## Is the number one that counts up (so a rise per day says more than its level)?
static func counts_up(name: StringName) -> bool:
	return name in [&"births", &"deaths", &"migrants", &"produced", &"trade", &"interventions"]
