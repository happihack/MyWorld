class_name MemoryText
extends RefCounted
## Memories in words (bible §15.2: "text is generated from templates keyed by
## subject × interpretation"). The templates are in data/text/memories.csv
## and are looked up through the translation server, so that they can be
## translated like any other text.
##
## A memory's text is a clause without its subject — "felt the touch of a
## spirit" — so that it reads the same for everyone and can be put into a
## line ("Age 23 · Felt the touch of a spirit") or a sentence ("At age 23,
## Mara felt the touch of a spirit.").

const PREFIX := "MEM_"


## The template for a memory: the most particular one there is.
##   MEM_<SUBJECT>_<INTERPRETATION>_CHILD   (for what a child lived)
##   MEM_<SUBJECT>_<INTERPRETATION>
##   MEM_<SUBJECT>                          (with {belief})
##   MEM_SAW                                (with {what} and {belief})
## and MEM_TOLD / MEM_TOLD_NOBODY for what was heard from someone.
static func key_for(subject: StringName, interpretation: StringName, source: Memory.Source, child: bool) -> String:
	if source == Memory.Source.TOLD:
		return "MEM_TOLD"
	var base := PREFIX + String(subject).to_upper()
	var particular := "%s_%s" % [base, String(interpretation).to_upper()]
	if child and has(particular + "_CHILD"):
		return particular + "_CHILD"
	if has(particular):
		return particular
	if has(base):
		return base
	return "MEM_SAW"


## Is there a text for this key?
static func has(key: String) -> bool:
	return String(TranslationServer.translate(key)) != key


static func translate(key: String) -> String:
	return String(TranslationServer.translate(key))


## The memory as a clause: "felt the touch of a spirit (3 times)".
## `people`: to name whoever told it (may be null).
static func text(memory: Memory, people: PersonRegistry = null) -> String:
	var key := memory.text_key if memory.text_key != "" else key_for(memory.subject, memory.interpretation, memory.source, false)
	var teller := people.name_of(memory.told_by) if people != null and memory.told_by != 0 else ""
	if key == "MEM_TOLD" and teller == "":
		key = "MEM_TOLD_NOBODY"
	if not has(key):
		key = "MEM_SAW"
	var what_key := "MEMWHAT_" + String(memory.subject).to_upper()
	var belief_key := "MEMBELIEF_" + String(memory.interpretation).to_upper()
	var out := translate(key).format({
		"what": translate(what_key if has(what_key) else "MEMWHAT_UNKNOWN"),
		"belief": translate(belief_key if has(belief_key) else "MEMBELIEF_NATURAL"),
		"teller": teller if teller != "" else translate("MEM_SOMEONE"),
	})
	# What was handed down from someone who has died: their memory, as theirs.
	if memory.source == Memory.Source.INHERITED:
		out = translate("MEM_INHERITED").format({"teller": teller if teller != "" else translate("MEM_SOMEONE"), "text": out})
	if memory.count > 1:
		out = translate("MEM_TIMES").format({"text": out, "count": memory.count})
	return out


## The age its owner was when it (last) happened.
static func age_then(memory: Memory, owner: PersonData) -> int:
	return maxi(owner.age_years(memory.tick, Config.time.ticks_per_year()), 0) if owner != null else 0


## A line for a list: "Age 23 · Felt the touch of a spirit".
static func line(memory: Memory, owner: PersonData, people: PersonRegistry = null) -> String:
	return translate("MEM_AGE").format({"age": age_then(memory, owner), "text": capitalized(text(memory, people))})


## A whole sentence: "At age 23, Mara felt the touch of a spirit."
static func sentence(memory: Memory, owner: PersonData, people: PersonRegistry = null) -> String:
	return translate("MEM_SENTENCE").format({"age": age_then(memory, owner),
		"name": owner.given_name if owner != null else translate("MEM_SOMEONE"), "text": text(memory, people)})


static func capitalized(words: String) -> String:
	return words.left(1).to_upper() + words.substr(1) if words != "" else words
