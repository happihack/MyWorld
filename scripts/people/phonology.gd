class_name Phonology
extends RefCounted
## The sounds of one culture's speech (bible §19.5): which consonants and
## vowels it uses and how it builds syllables. Names (and later the words of
## its lexicon, M17) are made from it, so the people of one culture sound
## alike and the people of another sound different.
##
## A phonology is a pure function of its seed: it is never saved, only the
## names made from it are. Changing the tables below changes the sound of new
## names in existing worlds (never the names people already have).

const ONSETS: PackedStringArray = [
	"b", "d", "f", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "w", "y", "z",
	"sh", "th", "ch",
	"br", "dr", "kr", "tr", "st", "gl", "fl", "sk",
]
## How many of ONSETS are single sounds (the rest are clusters).
const SIMPLE_ONSETS := 20
const VOWELS: PackedStringArray = ["a", "e", "i", "o", "u", "ai", "ea", "ia", "ou", "ei"]
const SIMPLE_VOWELS := 5
const CODAS: PackedStringArray = ["n", "r", "l", "s", "m", "k", "t", "d", "th", "sh", "nd", "rn", "st"]

var seed_value := 0
var onsets: PackedStringArray = []
var vowels: PackedStringArray = []
var codas: PackedStringArray = []
## Chance that a word's last syllable is closed by a coda.
var coda_chance := 0.4
## Chance that a word begins with a vowel.
var vowel_start_chance := 0.15
## Relative weights of words with 1, 2 and 3 syllables.
var syllable_weights := PackedFloat32Array([1.0, 6.0, 2.0])
## How names of women and men tend to end, and how often they do.
var female_endings: PackedStringArray = []
var male_endings: PackedStringArray = []
var ending_chance := 0.7
## Family names end like this ("" for none).
var family_suffix := ""


static func from_seed(seed_number: int) -> Phonology:
	var p := Phonology.new()
	p.seed_value = seed_number
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_number
	# Mostly single sounds, with a few clusters for character.
	p.onsets = _pick(rng, ONSETS.slice(0, SIMPLE_ONSETS), rng.randi_range(7, 10))
	p.onsets.append_array(_pick(rng, ONSETS.slice(SIMPLE_ONSETS), rng.randi_range(0, 3)))
	p.vowels = _pick(rng, VOWELS.slice(0, SIMPLE_VOWELS), rng.randi_range(3, 4))
	p.vowels.append_array(_pick(rng, VOWELS.slice(SIMPLE_VOWELS), rng.randi_range(0, 2)))
	p.codas = _pick(rng, CODAS, rng.randi_range(3, 6))
	p.coda_chance = rng.randf_range(0.2, 0.6)
	p.vowel_start_chance = rng.randf_range(0.05, 0.3)
	p.syllable_weights = PackedFloat32Array([rng.randf_range(0.3, 1.5), 6.0, rng.randf_range(1.0, 3.5)])
	# Women's names end in one of two vowels; men's in another vowel or a consonant.
	var plain := PackedStringArray()
	for vowel in p.vowels:
		if vowel.length() == 1:
			plain.append(vowel)
	var simple := _pick(rng, plain, 3)
	p.female_endings = simple.slice(0, 2)
	p.male_endings = PackedStringArray([simple[2] if simple.size() > 2 else simple[0]])
	p.male_endings.append_array(_pick(rng, p.codas, 2))
	p.ending_chance = rng.randf_range(0.6, 0.85)
	if rng.randf() < 0.6:
		p.family_suffix = p.vowels[rng.randi_range(0, mini(p.vowels.size(), 3) - 1)] + p.codas[rng.randi_range(0, p.codas.size() - 1)]
	return p


## `count` different entries of `from`, in the order the dice gave them.
static func _pick(rng: RandomNumberGenerator, from: PackedStringArray, count: int) -> PackedStringArray:
	var pool := from.duplicate()
	var out := PackedStringArray()
	while out.size() < count and not pool.is_empty():
		var i := rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out
