class_name NeedsConfig
extends ConfigBase
## How fast needs run down and fill up (bible §13.3). All rates are per game
## minute, as a fraction of the whole need (1/720 = from full to empty in 12
## game hours).

@export_group("Running down")
@export_range(0.0, 0.05, 0.00001) var hunger_per_minute: float = 1.0 / 720.0
@export_range(0.0, 0.05, 0.00001) var thirst_per_minute: float = 1.0 / 600.0
## While awake.
@export_range(0.0, 0.05, 0.00001) var sleep_per_minute: float = 1.0 / 1500.0
@export_range(0.0, 0.05, 0.00001) var social_per_minute: float = 1.0 / 900.0
@export_range(0.0, 0.05, 0.00001) var purpose_per_minute: float = 1.0 / 800.0
## Work makes hungry, thirsty and tired faster by this factor ...
@export_range(1.0, 4.0, 0.05) var working_factor: float = 1.25
## ... and sleep slows hunger and thirst by this one.
@export_range(0.0, 1.0, 0.05) var sleeping_factor: float = 0.3
## Children (growing) and elders get hungry and tired at these rates relative
## to adults.
@export_range(0.2, 3.0, 0.05) var child_body_factor: float = 1.2
@export_range(0.2, 3.0, 0.05) var elder_body_factor: float = 1.1

@export_group("Filling up")
## A meal takes this long and fills hunger completely.
@export_range(1.0, 240.0, 1.0) var meal_minutes: float = 25.0
@export_range(0.5, 60.0, 0.5) var drink_minutes: float = 4.0
## A night's sleep, from empty to rested.
@export_range(60.0, 1440.0, 5.0) var full_sleep_minutes: float = 690.0
## Company fills the social need from empty in this long ...
@export_range(5.0, 600.0, 1.0) var full_company_minutes: float = 45.0
## ... and work the need for purpose in this long.
@export_range(5.0, 1440.0, 1.0) var full_work_minutes: float = 240.0
@export_range(0.0, 0.1, 0.0001) var safety_recovery_per_minute: float = 1.0 / 180.0

@export_group("Going hungry")
## Someone is going hungry with their hunger need below this, and is fed
## again from this.
@export_range(0.0, 1.0, 0.01) var hungry_below: float = 0.1
@export_range(0.0, 1.0, 0.01) var fed_from: float = 0.35
## Going hungry for this many game minutes makes them weak (sick with hunger).
@export_range(1, 100000) var hunger_sick_after_minutes: int = 720
## What their health loses a day while they are, down to this; and what it
## gains a day once they are fed again.
@export_range(0.0, 1.0, 0.01) var sick_health_per_day: float = 0.2
@export_range(0.0, 1.0, 0.01) var sick_health_floor: float = 0.25
@export_range(0.0, 1.0, 0.01) var recover_health_per_day: float = 0.25
## In a shortage, someone this hungry remembers it (and talks of it).
@export_range(0.0, 1.0, 0.01) var hunger_talk_below: float = 0.3


func body_factor(stage: PersonData.LifeStage) -> float:
	match stage:
		PersonData.LifeStage.CHILD:
			return child_body_factor
		PersonData.LifeStage.ELDER:
			return elder_body_factor
	return 1.0


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, hunger_per_minute > 0.0 and thirst_per_minute > 0.0 and sleep_per_minute > 0.0, "needs must run down")
	_check(p, meal_minutes > 0.0 and drink_minutes > 0.0 and full_sleep_minutes > 0.0 and full_company_minutes > 0.0
		and full_work_minutes > 0.0, "needs must be fillable")
	# A night's sleep must restore more than a day awake uses up.
	_check(p, 1.0 / full_sleep_minutes > sleep_per_minute, "sleeping must restore faster than waking tires")
	_check(p, hungry_below < fed_from, "hungry_below must be less than fed_from")
	return p
