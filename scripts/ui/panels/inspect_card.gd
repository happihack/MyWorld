class_name InspectCard
extends UIPanel
## What the player learns by inspecting something (bible §26.6): a card in the
## bottom-left corner with a name and a few plain facts. It stays while the
## player keeps exploring and is closed with its ✕ or the back button.
## v0: the facts are close to the raw data; they get friendlier as systems
## (soil, resources, buildings) come alive.

const MAX_WIDTH := 852.0
const EDGE_MARGIN := 32.0
## Room kept free on the right for the Home button.
const RESERVED_RIGHT := 196.0
## Room kept free below: the card sits above the tool bar's row.
const BOTTOM_MARGIN := 308.0

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _rows: GridContainer = %Rows
@onready var _close: Button = %Close

var _height_step := 0.4


func _ready() -> void:
	_close.pressed.connect(close)
	get_viewport().size_changed.connect(layout)


func setup(report: InspectReport, height_step: float = 0.4) -> void:
	_height_step = height_step
	for child in _rows.get_children():
		child.queue_free()
	var where := "tile %d, %d" % [report.tile.x, report.tile.y]
	match report.subject:
		InspectReport.Subject.PROP:
			_title.text = UIText.prop_name(report.prop_kind, report.prop_variant)
			_subtitle.text = where
			_add_row("Stands on", UIText.terrain_name(report.terrain))
			_add_row("Size", UIText.size_text(report.scale_percent))
			if report.bears >= 0:
				_add_row("Bears", UIText.bears_text(report.bears_left, report.bears,
					report.prop_variant >= PropData.TREE_CONIFER_FIRST_VARIANT))
			_add_row("Ground height", str(report.height_level))
			_add_row("Moisture", UIText.moisture_text(report.moisture))
		InspectReport.Subject.LOOSE:
			_title.text = UIText.loose_name(report.loose_kind)
			_subtitle.text = where
			_add_row("Lies on", UIText.terrain_name(report.terrain))
			_add_row("Weight", UIText.weight_text(report.mass))
			_add_row("Moved", UIText.moved_text(report.moved_count))
			_add_row("Ground height", str(report.height_level))
		InspectReport.Subject.WATER:
			_title.text = UIText.WATER_NAME
			_subtitle.text = where
			_add_row("Depth", UIText.depth_text(report.water_depth, _height_step))
			_add_row("Bed", UIText.terrain_name(report.terrain))
			_add_row("Bed height", str(report.height_level))
		_:
			_title.text = UIText.terrain_name(report.terrain)
			_subtitle.text = where
			_add_row("Height", str(report.height_level))
			_add_row("Moisture", UIText.moisture_text(report.moisture))
			_add_row("Fertility", UIText.fertility_text(report.fertility))
			_add_row("Plant cover", UIText.vegetation_text(report.vegetation))
	layout()


## Sits in the bottom-left corner, as wide as the screen allows.
func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size.x = clampf(view.x - EDGE_MARGIN - RESERVED_RIGHT, 200.0, MAX_WIDTH)
	reset_size()
	position = Vector2(EDGE_MARGIN, view.y - BOTTOM_MARGIN - size.y)


func title_text() -> String:
	return _title.text


func subtitle_text() -> String:
	return _subtitle.text


## The facts shown, as label -> value.
func rows() -> Dictionary:
	var out := {}
	var cells: Array[Label] = []
	for child in _rows.get_children():
		if child is Label and not child.is_queued_for_deletion():
			cells.append(child)
	for i in range(0, cells.size() - 1, 2):
		out[cells[i].text] = cells[i + 1].text
	return out


func _add_row(label: String, value: String) -> void:
	var name_label := Label.new()
	name_label.text = label
	name_label.theme_type_variation = UITheme.DIM
	_rows.add_child(name_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_child(value_label)
