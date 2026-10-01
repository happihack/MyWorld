extends TestCase
## Pure UI logic: wording, menu placement, UI scale.

const VIEW := Rect2(0, 0, 1080, 2400)
const CARD := Vector2(520, 500)


# --- wording ----------------------------------------------------------------------------

func test_every_terrain_and_prop_has_a_name() -> void:
	for terrain: int in ChunkData.Terrain.values():
		assert_true(UIText.TERRAIN_NAMES.has(terrain), ChunkData.Terrain.keys()[terrain])
		assert_false(UIText.terrain_name(terrain).is_empty())
	for kind: int in PropData.Kind.values():
		assert_true(UIText.PROP_NAMES.has(kind), PropData.Kind.keys()[kind])
	assert_eq(UIText.prop_name(PropData.Kind.TREE, 0), "Tree")
	assert_eq(UIText.prop_name(PropData.Kind.TREE, PropData.TREE_CONIFER_FIRST_VARIANT), "Pine")
	assert_eq(UIText.prop_name(PropData.Kind.ROCK, 3), "Rock")
	assert_eq(UIText.terrain_name(999), "Ground", "unknown values still read as something")


func test_loose_object_wording() -> void:
	for kind: int in LooseObject.Kind.values():
		assert_true(UIText.LOOSE_NAMES.has(kind), LooseObject.Kind.keys()[kind])
	assert_eq(UIText.loose_name(LooseObject.Kind.BOULDER), "Boulder")
	assert_eq(UIText.loose_name(99), "Something")
	assert_eq(UIText.weight_text(0.3), "Light (0.3 kg)")
	assert_eq(UIText.weight_text(14.0), "Heavy (14 kg)")
	assert_eq(UIText.weight_text(190.0), "Very heavy (190 kg)")
	assert_eq(UIText.moved_text(0), "Never")
	assert_eq(UIText.moved_text(1), "Once")
	assert_eq(UIText.moved_text(4), "4 times")


func test_subject_name_follows_the_touch() -> void:
	var r := InteractionResponse.new()
	r.terrain = ChunkData.Terrain.SAND
	assert_eq(UIText.subject_name(r), "Sand")
	r.touch_effect = InteractionResponse.RIPPLE
	r.effect = InteractionResponse.INSPECT # a long press on water
	assert_eq(UIText.subject_name(r), "Water")
	r.entity_id = 5
	r.prop_kind = PropData.Kind.RUIN
	assert_eq(UIText.subject_name(r), "Old stones")
	assert_eq(UIText.subject_name(null), "")


func test_action_labels() -> void:
	assert_eq(UIText.action_label(InteractionManager.ACTION_INSPECT), "Inspect")
	assert_eq(UIText.action_label(InteractionManager.ACTION_FOCUS), "Look closer")
	assert_eq(UIText.action_label(InteractionManager.ACTION_TOUCH), "Touch")
	assert_eq(UIText.action_label(InteractionManager.ACTION_TOUCH, InteractionResponse.TREE_SHAKE), "Shake")
	assert_eq(UIText.action_label(InteractionManager.ACTION_TOUCH, InteractionResponse.BUSH_RUSTLE), "Shake")
	assert_eq(UIText.action_label(InteractionManager.ACTION_TOUCH, InteractionResponse.RIPPLE), "Disturb")
	assert_eq(UIText.action_label(InteractionManager.ACTION_TOUCH, InteractionResponse.BUILDING_KNOCK), "Knock")
	assert_eq(UIText.action_label(InteractionManager.ACTION_TOUCH, InteractionResponse.RUIN_HUM), "Touch")
	assert_eq(UIText.action_label(&"give_gift"), "Give Gift", "an unknown action is still readable")


func test_level_words() -> void:
	assert_eq(UIText.moisture_text(0), "Dry (0%)")
	assert_eq(UIText.moisture_text(255), "Wet (100%)")
	assert_eq(UIText.moisture_text(100), "Damp (39%)")
	assert_eq(UIText.fertility_text(200), "Rich (78%)")
	assert_eq(UIText.vegetation_text(130), "Green (51%)")
	assert_eq(UIText.size_text(80), "Small (80%)")
	assert_eq(UIText.size_text(100), "Medium (100%)")
	assert_eq(UIText.size_text(140), "Large (140%)")
	assert_has(UIText.depth_text(0.1, 0.4), "Shallow")
	assert_has(UIText.depth_text(0.9, 0.4), "Deep")
	assert_eq(UIText.level_word(300, ["a", "b"]), "b", "out-of-range values are clamped")
	assert_eq(UIText.level_word(-5, ["a", "b"]), "a")


# --- context menu placement -----------------------------------------------------------------

func test_menu_sits_above_the_finger() -> void:
	var anchor := Vector2(540, 1400)
	var pos := ContextMenu.place(anchor, CARD, VIEW)
	assert_near(pos.x + CARD.x * 0.5, anchor.x, 0.001, "centred on the finger")
	assert_near(pos.y + CARD.y, anchor.y - ContextMenu.FINGER_GAP, 0.001, "above it, a gap away")


func test_menu_drops_below_the_finger_near_the_top() -> void:
	var anchor := Vector2(540, 300)
	var pos := ContextMenu.place(anchor, CARD, VIEW)
	assert_near(pos.y, anchor.y + ContextMenu.FINGER_GAP, 0.001)


func test_menu_goes_beside_the_finger_on_a_low_wide_screen() -> void:
	var landscape := Rect2(0, 0, 2400, 1080)
	var card := Vector2(520, 600)
	for anchor: Vector2 in [Vector2(1200, 600), Vector2(300, 500), Vector2(2300, 540), Vector2(40, 540)]:
		var rect := Rect2(ContextMenu.place(anchor, card, landscape), card)
		assert_true(landscape.encloses(rect), "on screen at %s" % anchor)
		assert_false(rect.has_point(anchor), "never under the finger (pressed at %s -> %s)" % [anchor, rect])
	var right := ContextMenu.place(Vector2(1200, 600), card, landscape)
	assert_near(right.x, 1200 + ContextMenu.FINGER_GAP, 0.001, "to the right when there is room")
	var left := ContextMenu.place(Vector2(2300, 540), card, landscape)
	assert_near(left.x + card.x, 2300 - ContextMenu.FINGER_GAP, 0.001, "to the left near the right edge")


func test_menu_never_leaves_the_screen() -> void:
	for anchor: Vector2 in [Vector2(0, 0), Vector2(1080, 0), Vector2(1080, 2400), Vector2(0, 2400),
			Vector2(-500, 1200), Vector2(5000, 1200), Vector2(540, 2390), Vector2(10, 1000)]:
		var rect := Rect2(ContextMenu.place(anchor, CARD, VIEW), CARD)
		assert_true(VIEW.grow(-ContextMenu.EDGE_MARGIN + 0.01).encloses(rect), "pressed at %s -> %s" % [anchor, rect])
	# A card bigger than the screen is pinned to the top-left margin.
	var huge := ContextMenu.place(Vector2(540, 1200), Vector2(3000, 5000), VIEW)
	assert_eq(huge, Vector2(ContextMenu.EDGE_MARGIN, ContextMenu.EDGE_MARGIN))


func test_menu_respects_a_view_that_does_not_start_at_zero() -> void:
	var view := Rect2(100, 200, 800, 1000)
	var pos := ContextMenu.place(Vector2(110, 210), Vector2(300, 300), view)
	assert_true(pos.x >= 100 + ContextMenu.EDGE_MARGIN and pos.y >= 200 + ContextMenu.EDGE_MARGIN)


# --- UI scale ------------------------------------------------------------------------------

func test_ui_scale_is_one_when_held_upright() -> void:
	var base := Vector2(1080, 1920)
	assert_near(UIRoot.ui_scale_for(Vector2(1080, 2400), base), 1.0, 0.0001)
	assert_near(UIRoot.ui_scale_for(Vector2(1080, 1920), base), 1.0, 0.0001)
	assert_near(UIRoot.ui_scale_for(Vector2(540, 960), base), 1.0, 0.0001, "a small desktop window")
	assert_near(UIRoot.ui_scale_for(Vector2(720, 1600), base), 1.0, 0.0001)


func test_ui_scale_keeps_its_size_in_landscape() -> void:
	var base := Vector2(1080, 1920)
	var portrait := Vector2(1080, 2400)
	var landscape := Vector2(2400, 1080)
	var factor := UIRoot.ui_scale_for(landscape, base)
	assert_near(factor, 1.0 / 0.5625, 0.001)
	# Pixels per UI unit are the same both ways round.
	var px_portrait := minf(portrait.x / base.x, portrait.y / base.y) * UIRoot.ui_scale_for(portrait, base)
	var px_landscape := minf(landscape.x / base.x, landscape.y / base.y) * factor
	assert_near(px_landscape, px_portrait, 0.0001)


func test_ui_scale_handles_odd_windows() -> void:
	var base := Vector2(1080, 1920)
	assert_near(UIRoot.ui_scale_for(Vector2(0, 0), base), 1.0, 0.0)
	assert_near(UIRoot.ui_scale_for(Vector2(800, 800), base), 1.0, 0.0001, "square")
	assert_true(UIRoot.ui_scale_for(Vector2(8000, 300), base) <= UIRoot.MAX_UI_SCALE, "extreme strips are capped")


# --- theme ---------------------------------------------------------------------------------

func test_theme_is_shared_and_has_the_label_styles() -> void:
	var theme := UITheme.get_theme()
	assert_true(theme == UITheme.get_theme(), "built once")
	assert_eq(theme.get_font_size(&"font_size", UITheme.TITLE), UITheme.FONT_TITLE)
	assert_eq(theme.get_color(&"font_color", UITheme.DIM), UITheme.INK_DIM)
	assert_true(theme.has_stylebox(&"panel", &"PanelContainer"))
	assert_true(UITheme.TOUCH_TARGET >= 48.0 * 2.8, "48 dp on a 450 dpi phone")
