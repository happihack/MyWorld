class_name Lore
extends RefCounted
## How a story changes as it is told on (bible §15.4, "mythological
## distortion" v0): each retelling may change it — the more creative the
## teller, the likelier — in one of three ways:
##   it grows        ("— greater than anyone had seen"; told with more force),
##   it moves back   to "the first days",
##   it becomes someone's doing (what was the wind becomes a spirit's).
## What a story has become travels with it (Stimulus.lore → Memory.text_params).

const GRAND := "grand" # how many times it has grown (int)
const FIRST_DAYS := "first_days" # bool
const PERSONIFIED := "personified" # bool
## How much more force a story has each time it has grown.
const GROWTH := 0.2
## What becomes someone's doing: from what is no one's, to a spirit's.
const NO_ONES: Array[StringName] = [&"natural", &"physics", &"hallucination", &"experiment"]


## The story as `teller` tells it on: `lore` (what it has become so far) and
## the interpretation told, perhaps changed. Returns [lore, interpretation].
static func retell(lore: Dictionary, teller: PersonData, interpretation: StringName, rng: RandomNumberGenerator,
		config: MemoryConfig = null) -> Array:
	if config == null:
		config = Config.memory
	var out := lore.duplicate()
	if rng == null:
		return [out, interpretation]
	var chance := config.mutate_chance * lerpf(0.5, 1.0, Traits.value(teller.traits, Traits.Axis.CREATIVITY))
	if rng.randf() >= chance:
		return [out, interpretation]
	var ways: Array[String] = [GRAND]
	if not bool(out.get(FIRST_DAYS, false)):
		ways.append(FIRST_DAYS)
	if NO_ONES.has(interpretation) and not bool(out.get(PERSONIFIED, false)):
		ways.append(PERSONIFIED)
	match ways[rng.randi_range(0, ways.size() - 1)]:
		GRAND:
			out[GRAND] = int(out.get(GRAND, 0)) + 1
		FIRST_DAYS:
			out[FIRST_DAYS] = true
		PERSONIFIED:
			out[PERSONIFIED] = true
			interpretation = &"spirit"
	return [out, interpretation]


## How much more force the story has than what happened.
static func force(lore: Dictionary) -> float:
	return 1.0 + GROWTH * float(int(lore.get(GRAND, 0)))


## The memory's words, as the story has become: "in the first days, …",
## "… — greater than anyone had seen".
static func wrap(text: String, lore: Dictionary) -> String:
	if lore.is_empty():
		return text
	var out := text
	if int(lore.get(GRAND, 0)) > 0:
		out = MemoryText.translate("MEM_LORE_GRAND").format({"text": out})
	if bool(lore.get(FIRST_DAYS, false)):
		out = MemoryText.translate("MEM_LORE_FIRST_DAYS").format({"text": out})
	return out


## What a story was about, as it has become: "a touch from an unseen hand,
## in the first days" (for the words of something told).
static func wrap_what(what: String, lore: Dictionary) -> String:
	var out := what
	if int(lore.get(GRAND, 0)) > 0:
		out = MemoryText.translate("MEM_LORE_WHAT_GRAND").format({"what": out})
	if bool(lore.get(FIRST_DAYS, false)):
		out = MemoryText.translate("MEM_LORE_WHAT_FIRST_DAYS").format({"what": out})
	return out


## Is there anything of a story in these text parameters?
static func has_lore(params: Dictionary) -> bool:
	return params.has(GRAND) or params.has(FIRST_DAYS) or params.has(PERSONIFIED)
