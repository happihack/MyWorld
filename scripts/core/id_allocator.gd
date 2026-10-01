class_name IdAllocator
extends RefCounted
## Hands out persistent entity ids (bible §31.2). Ids are positive, monotonic and
## never reused, so a stale id can only ever resolve to "missing", never to a
## different entity. 0 and negative values mean "no entity".

const INVALID_ID := 0

var _next_id: int = 1


func next_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


## The id the next call to next_id() will return.
func peek() -> int:
	return _next_id


## Guarantees future ids are greater than `id` (used when loading entities whose
## ids may exceed a stale counter, e.g. after a repaired save).
func reserve_above(id: int) -> void:
	if id >= _next_id:
		_next_id = id + 1


func to_dict() -> Dictionary:
	return {"next_id": _next_id}


func from_dict(data: Dictionary) -> void:
	var loaded := int(data.get("next_id", 1))
	_next_id = maxi(loaded, 1)
