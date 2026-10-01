class_name PeopleConfig
extends ConfigBase
## The inhabitants: ages of life and the band a world starts with (bible §13, §16.2).

@export_group("Life stages")
## Age (in game years) at which a child becomes an adolescent, ...
@export_range(1, 40) var adolescent_from_years: int = 13
## ... an adolescent an adult, ...
@export_range(1, 60) var adult_from_years: int = 18
## ... and an adult an elder.
@export_range(1, 150) var elder_from_years: int = 55

@export_group("Starting band")
@export_range(1, 40) var band_min_people: int = 6
@export_range(1, 40) var band_max_people: int = 8
@export_range(1, 10) var band_min_households: int = 2
@export_range(1, 10) var band_max_households: int = 3
## People are placed at most this many tiles from their home.
@export_range(1, 8) var spawn_radius_tiles: int = 3


func stage_for_age(years: int) -> PersonData.LifeStage:
	if years >= elder_from_years:
		return PersonData.LifeStage.ELDER
	if years >= adult_from_years:
		return PersonData.LifeStage.ADULT
	if years >= adolescent_from_years:
		return PersonData.LifeStage.ADOLESCENT
	return PersonData.LifeStage.CHILD


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, adolescent_from_years < adult_from_years and adult_from_years < elder_from_years,
		"life stages must come in order (adolescent < adult < elder)")
	_check(p, band_min_people <= band_max_people, "band_min_people must be <= band_max_people")
	_check(p, band_min_households <= band_max_households, "band_min_households must be <= band_max_households")
	# Every household is at least a couple with a child or an elder.
	_check(p, band_min_people >= band_max_households * 2, "band_min_people must allow two adults per household")
	return p
