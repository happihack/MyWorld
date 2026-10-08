class_name Signs
extends RefCounted
## The signs above people's heads (FC1, the owner 2026-10-08). A step shows
## one while it lasts (PersonData.emote: a shout, a question, a story told);
## what happens to someone may show one for a few minutes besides (a
## "flash": anger after a quarrel, a heart at a flirt, the hurt of a fall).
## Where two would show, the weightier does.

const EXCLAIM := &"exclaim"
const QUESTION := &"question"
const PRAY := &"pray"
const SPEECH := &"speech"
const NOTE := &"note"
const DOTS := &"dots"
const RECOGNIZE := &"recognize"
const ANGRY := &"angry"
const SAD := &"sad"
const LOVE := &"love"
const HURT := &"hurt"
const ILL := &"ill"
const HUNGRY := &"hungry"
const TIRED := &"tired"

## How weighty each sign is (the weightier shows).
const PRIORITY := {
	EXCLAIM: 7, ANGRY: 6, HURT: 6, SAD: 5, ILL: 4, HUNGRY: 4, RECOGNIZE: 4, PRAY: 3, LOVE: 3,
	SPEECH: 2, QUESTION: 2, NOTE: 1, DOTS: 1, TIRED: 1,
}
## How long a flash shows, game minutes, unless said otherwise.
const MINUTES := {
	ANGRY: 8, SAD: 25, LOVE: 12, HURT: 15, ILL: 15, HUNGRY: 15, TIRED: 10, EXCLAIM: 4, NOTE: 8, QUESTION: 6,
}
const DEFAULT_MINUTES := 8
## How many flashes of a light kind one settlement may show in a game hour
## (FC8: a big village is not a sea of hearts). The weighty kinds — anger,
## hurt, grief, alarm — are never held back.
const RATE_PER_HOUR := {LOVE: 3, NOTE: 4, TIRED: 3, QUESTION: 4, HUNGRY: 4, ILL: 4}

static var _rate_hour := -1
static var _rate_counts: Dictionary = {} # "settlement:sign" -> flashes this hour


## `person` shows `sign` for a while from `now` (`minutes` < 0: its usual
## length) — unless a weightier one is already showing, or their settlement
## has shown enough of that kind this hour (RATE_PER_HOUR).
static func flash(person: PersonData, sign: StringName, now: int, minutes: int = -1) -> bool:
	if person == null or sign == &"":
		return false
	if person.flash != &"" and now < person.flash_until and weight(person.flash) > weight(sign):
		return false
	if RATE_PER_HOUR.has(sign):
		var hour := floori(now / 60.0)
		if hour != _rate_hour:
			_rate_hour = hour
			_rate_counts.clear()
		var key := "%d:%s" % [person.settlement_id, sign]
		if int(_rate_counts.get(key, 0)) >= int(RATE_PER_HOUR[sign]):
			return false
		_rate_counts[key] = int(_rate_counts.get(key, 0)) + 1
	person.flash = sign
	person.flash_until = now + (minutes if minutes >= 0 else int(MINUTES.get(sign, DEFAULT_MINUTES)))
	return true


## What `person` shows now (&"": nothing): what they are doing, or what has
## just happened to them — the weightier.
static func shown(person: PersonData, now: int) -> StringName:
	var flashing := person.flash if person.flash != &"" and now < person.flash_until else &""
	if flashing == &"":
		return person.emote
	if person.emote == &"":
		return flashing
	return flashing if weight(flashing) > weight(person.emote) else person.emote


static func weight(sign: StringName) -> int:
	return int(PRIORITY.get(sign, 0))


## What someone is going through, to show while they are the one selected
## (FC3: shown to everyone only as it begins): hurt, ill, hungry (&"": well).
static func state_of(person: PersonData) -> StringName:
	if Hardship.is_sick(person):
		return HUNGRY
	if Health.is_ill(person) or Exposure.is_sick(person):
		return ILL
	if Health.worst_injury(person) > 0.15:
		return HURT
	return &""


## Forget how many of each kind were shown this hour (a new world, a test).
static func reset_rates() -> void:
	_rate_hour = -1
	_rate_counts.clear()


## No more flash (a person who is gone, or a test).
static func clear(person: PersonData) -> void:
	person.flash = &""
	person.flash_until = 0
