extends TestCase
## Lists through time (Discoveries, Stories & eras, Beliefs, Box clues, Firsts,
## Technology) read newest to oldest: the latest year at the top (the owner,
## 2026-10-08).


func _event(id: int, tick: int) -> WorldEvent:
	var e := WorldEvent.new()
	e.id = id
	e.tick = tick
	return e


func test_newest_first() -> void:
	var events := [_event(1, 100), _event(2, 5000), _event(3, 2000), _event(4, 5000)]
	var ordered := MenuPages.newest_first(events)
	assert_eq(ordered.map(func(e: WorldEvent) -> int: return e.id), [4, 2, 3, 1], "latest year first; the later of a tie first")
	assert_eq(events.map(func(e: WorldEvent) -> int: return e.id), [1, 2, 3, 4], "(the list given is left as it was)")
