class_name EntityViewPool
extends Node3D
## A pool of view nodes for entities that are data, not nodes (bible §31.7):
## whoever needs to be seen borrows a view by id and gives it back when out of
## sight. Views are made on demand, never freed while the pool lives, and
## reused for whoever comes next.
##
## The pool knows nothing about what it shows: `prepare` (called once per new
## view) lets the owner set it up.

var _scene: PackedScene
var _max_views: int
var _prepare: Callable
var _bound: Dictionary = {} # entity id -> Node3D
var _free: Array[Node3D] = []
var _created := 0


func _init(scene: PackedScene = null, max_views: int = 64, prepare: Callable = Callable()) -> void:
	_scene = scene
	_max_views = max_views
	_prepare = prepare


## The view of `id`: the one it has, a free one, or a new one. Null when every
## view is in use and no more may be made.
func acquire(id: int) -> Node3D:
	var view: Node3D = _bound.get(id)
	if view != null:
		return view
	if not _free.is_empty():
		view = _free.pop_back()
	elif _created < _max_views and _scene != null:
		view = _scene.instantiate() as Node3D
		view.name = "View%d" % _created
		_created += 1
		add_child(view)
		if _prepare.is_valid():
			_prepare.call(view)
	else:
		return null
	_bound[id] = view
	return view


## Returns the view of `id` to the pool (hidden). False if it had none.
func release(id: int) -> bool:
	var view: Node3D = _bound.get(id)
	if view == null:
		return false
	_bound.erase(id)
	view.visible = false
	_free.append(view)
	return true


func release_all() -> void:
	for id: int in _bound.keys():
		release(id)


func view_of(id: int) -> Node3D:
	return _bound.get(id)


func has_view(id: int) -> bool:
	return _bound.has(id)


func bound_ids() -> Array[int]:
	var out: Array[int] = []
	for id: int in _bound:
		out.append(id)
	out.sort()
	return out


## Views in use.
func active_count() -> int:
	return _bound.size()


func free_count() -> int:
	return _free.size()


## Views ever made (in use or free).
func created_count() -> int:
	return _created


func capacity() -> int:
	return _max_views
