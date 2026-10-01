class_name NameGenerator
extends RefCounted
## Makes names (and words) in the sounds of one culture (bible §19.5).
##
## The dice are passed in (the world's "people" stream), so names are
## deterministic for a world and saved only as the names people carry.

const MIN_LETTERS := 3
const MAX_LETTERS := 8
const MAX_TRIES := 24
const VOWEL_LETTERS := "aeiou"
## Generated words must not contain these (words nobody should be named).
const BLOCKED: PackedStringArray = [
	"ass", "anus", "arse", "coc", "cok", "cum", "cunt", "dic", "dik", "fag", "fak", "fuc", "fuk",
	"kike", "kok", "kum", "nazi", "nig", "pee", "piss", "poo", "rape", "sex", "shit", "sht", "slut",
	"tit", "twat", "turd", "whor",
]

var phonology: Phonology


func _init(sounds: Phonology) -> void:
	phonology = sounds


## A given name for someone of `sex` (PersonData.Sex), not one of `taken`
## (a Dictionary used as a set of names in use) if that can be helped.
func given_name(rng: RandomNumberGenerator, sex: int, taken: Dictionary = {}) -> String:
	var endings := phonology.female_endings if sex == PersonData.Sex.FEMALE else phonology.male_endings
	var candidate := ""
	for attempt in MAX_TRIES:
		var ending := ""
		if not endings.is_empty() and rng.randf() < phonology.ending_chance:
			ending = endings[rng.randi_range(0, endings.size() - 1)]
		candidate = _with_ending(word(rng, _syllable_count(rng)), ending).capitalize()
		if is_acceptable(candidate) and not taken.has(candidate):
			return candidate
	return candidate


## A family name, not one of `taken` if that can be helped.
func family_name(rng: RandomNumberGenerator, taken: Dictionary = {}) -> String:
	var candidate := ""
	for attempt in MAX_TRIES:
		candidate = _with_ending(word(rng, rng.randi_range(1, 2)), phonology.family_suffix).capitalize()
		if is_acceptable(candidate) and not taken.has(candidate):
			return candidate
	return candidate


## A lower-case word of `syllables` syllables.
func word(rng: RandomNumberGenerator, syllables: int) -> String:
	var out := ""
	for i in maxi(syllables, 1):
		var onset := ""
		if i > 0 or rng.randf() >= phonology.vowel_start_chance:
			onset = phonology.onsets[rng.randi_range(0, phonology.onsets.size() - 1)]
			# Never three consonants in a row inside a word.
			if onset.length() > 1 and out != "" and not VOWEL_LETTERS.contains(out[-1]):
				onset = onset[0]
		out += onset + phonology.vowels[rng.randi_range(0, phonology.vowels.size() - 1)]
		# Syllables inside a word are mostly open; the last one may be closed.
		var last := i == syllables - 1
		if rng.randf() < (phonology.coda_chance if last else phonology.coda_chance * 0.3):
			var coda := phonology.codas[rng.randi_range(0, phonology.codas.size() - 1)]
			out += coda if last else coda[0]
	return out


## Pronounceable, of a sensible length, and not something rude.
static func is_acceptable(text: String) -> bool:
	var lower := text.to_lower()
	if lower.length() < MIN_LETTERS or lower.length() > MAX_LETTERS:
		return false
	var run := 1
	for i in range(1, lower.length()):
		run = run + 1 if lower[i] == lower[i - 1] else 1
		if run >= 3:
			return false
	for blocked in BLOCKED:
		if lower.contains(blocked):
			return false
	return true


func _syllable_count(rng: RandomNumberGenerator) -> int:
	var weights := phonology.syllable_weights
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i + 1
	return weights.size()


## Replaces the end of `base` so that it ends in `ending`: a vowel ending
## replaces the final vowel (and coda), a consonant ending closes the word.
static func _with_ending(base: String, ending: String) -> String:
	if ending == "":
		return base
	var stem := base
	# Strip the final coda, then (for a vowel ending) the final vowel too.
	while stem.length() > 1 and not VOWEL_LETTERS.contains(stem[-1]):
		stem = stem.left(-1)
	if VOWEL_LETTERS.contains(ending[0]):
		while stem.length() > 1 and VOWEL_LETTERS.contains(stem[-1]):
			stem = stem.left(-1)
	return stem + ending
