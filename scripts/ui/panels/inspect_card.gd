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
## The tile it tells of (no longer written on the card: the owner found "tile 12, 8" no use to a player).
var _tile := Vector2i.ZERO


func _ready() -> void:
	_close.pressed.connect(close)
	get_viewport().size_changed.connect(layout)


func setup(report: InspectReport, height_step: float = 0.4) -> void:
	_height_step = height_step
	for child in _rows.get_children():
		child.queue_free()
	_tile = report.tile
	_subtitle.visible = false
	match report.subject:
		InspectReport.Subject.PROP:
			_title.text = UIText.node_name(report.prop_kind, report.prop_variant, report.look)
			if report.crop_stage >= 0:
				_title.text = UIText.crop_name(report.crop_stage)
				_add_row("Crop", UIText.crop_state(report.crop_stage, report.crop_growth, report.crop_vigor, report.crop_dry))
				_add_row("Soil", "%s · %s" % [UIText.moisture_text(report.moisture), UIText.fertility_text(report.fertility)])
			_add_row("Stands on", UIText.terrain_name(report.terrain))
			if report.condition >= 0:
				_add_row("Condition", UIText.condition_text(report.condition))
				if report.repair_progress >= 0.0:
					_add_row("Being repaired", "%d%%" % roundi(report.repair_progress * 100.0))
			elif report.build_progress >= 0.0:
				_add_row("Going up", UIText.building_name(report.building))
				_add_row("Completion", "%d%%" % roundi(report.build_progress * 100.0))
				if not report.still_needed.is_empty():
					_add_row("Waiting for", UIText.needed_text(report.still_needed))
			elif report.prop_kind != PropData.Kind.SITE:
				_add_row("Size", UIText.size_text(report.scale_percent))
			if report.bears >= 0:
				_add_row("Bears", UIText.bears_text(report.bears_left, report.bears,
					report.prop_variant >= PropData.TREE_CONIFER_FIRST_VARIANT))
			if report.resource != &"" and (report.crop_stage < 0 or report.resource_left > 0):
				_add_row("Holds", UIText.holds_text(report.resource, report.resource_left, report.resource_capacity))
			if report.prop_kind == PropData.Kind.CAMPFIRE:
				_add_row("Fire", "Gone out — no wood" if report.look == ResourceNodes.Look.BARE else "Burning")
				if report.settlement_name != "":
					_add_row("Settlement", report.settlement_name.left(1).to_upper() + report.settlement_name.substr(1))
					_add_row("Tier", "%s — %d people" % [Settlements.tier_name(report.settlement_tier as Settlements.Tier), report.settlement_people])
					if report.leader_name != "":
						_add_row("Led by", report.leader_name)
					if report.known_for != "":
						_add_row("Known for", UIText.resource_name(StringName(report.known_for)))
					if report.sends != "" or report.gets != "":
						_add_row("Trade", UIText.trade_text(report.sends, report.gets))
					if not report.knows.is_empty():
						_add_row("Knows", ", ".join(report.knows))
			_add_row("Ground height", str(report.height_level))
			# (What grows drinks from the ground; buildings and stones do not care.)
			if report.prop_kind == PropData.Kind.TREE or report.prop_kind == PropData.Kind.BUSH:
				_add_row("Moisture", UIText.moisture_text(report.moisture))
		InspectReport.Subject.LOOSE:
			_title.text = UIText.loose_name(report.loose_kind)
			if report.resource != &"":
				_title.text = String(TranslationServer.translate("RES_PILE")).format({"name": UIText.resource_name(report.resource)})
				_add_row("Holds", UIText.resource_amount(report.resource, report.resource_left))
			_add_row("Lies on", UIText.terrain_name(report.terrain))
			_add_row("Weight", UIText.weight_text(report.mass))
			_add_row("Moved", UIText.moved_text(report.moved_count))
			_add_row("Ground height", str(report.height_level))
		InspectReport.Subject.ANIMAL:
			_title.text = UIText.species_name(report.species)
			_add_row("Doing", UIText.animal_state(report.animal_state, report.species == &"fox"))
			_add_row("Age", UIText.animal_age(report.animal_age_days, report.animal_grown))
			_add_row("In the box", str(report.species_count))
			_add_row("Stands on", UIText.terrain_name(report.terrain))
		InspectReport.Subject.WATER:
			_title.text = UIText.WATER_NAME
			_add_row("Depth", UIText.depth_text(report.water_depth, _height_step))
			_add_row("Bed", UIText.terrain_name(report.terrain))
			_add_row("Bed height", str(report.height_level))
		_:
			_title.text = UIText.terrain_name(report.terrain)
			_add_row("Height", str(report.height_level))
			_add_row("Moisture", UIText.moisture_text(report.moisture))
			_add_row("Fertility", UIText.fertility_text(report.fertility))
			if report.terrain != ChunkData.Terrain.ROAD: # (worn bare)
				_add_row("Plant cover", UIText.vegetation_text(report.vegetation))
			_add_row("Footfall", UIText.footfall_text(report.footfall, report.path))
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
	return _subtitle.text if _subtitle.visible else ""


## The tile the card tells of.
func tile() -> Vector2i:
	return _tile


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
