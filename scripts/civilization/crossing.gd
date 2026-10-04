class_name Crossing
extends RefCounted
## A bridge across the water, bank to bank (M12 follow-up, at the owner's
## word, 2026-10-04): built tile by tile from the near bank — over deep water
## too — until it reaches the far side. Its deck lies level with the higher of
## the two banks; posts reach down to the bed. What the pathfinder, the
## meshes and the people standing on it agree on is worked out here.
##
## (M12.2's bridge was one tile over a ford waded often: on a river with a
## deep middle it stopped at the shallow edge — four of them in a row along
## one bank on the owner's phone, crossing nothing.)

## How far along its line a bridge looks for the banks (tiles, each way).
const SCAN_MOST := 16
## The deck lies this far above the higher bank (world units).
const DECK_LIFT := 0.06
## Water this close under the deck harms it (world units).
const FLOOD_MARGIN := 0.02


## Which way a bridge runs: east–west when turned (rotation 64), else north–south.
static func axis_of(rotation_step: int) -> Vector2i:
	return Vector2i(1, 0) if rotation_step == 64 else Vector2i(0, 1)


static func is_bridge(props: PropRegistry, tile: Vector2i) -> bool:
	var prop := props.prop_at(tile) if props != null else null
	return prop != null and prop.kind == PropData.Kind.BRIDGE


## A bridge that stands (its deck laid) on `tile`.
static func deck_at(props: PropRegistry, tile: Vector2i) -> PropData:
	var prop := props.prop_at(tile) if props != null else null
	if prop != null and prop.kind == PropData.Kind.BRIDGE and prop.variant >= PropData.BRIDGE_DONE:
		return prop
	return null


## The ground level of the higher bank a bridge on `tile` reaches along
## `axis` (both ways, over water and over bridges, to dry land); -1 if it
## reaches none within SCAN_MOST.
static func bank_level(world: WorldData, props: PropRegistry, tile: Vector2i, axis: Vector2i) -> int:
	var best := -1
	for dir: Vector2i in [axis, -axis]:
		var at := tile + dir
		for i in SCAN_MOST:
			if not world.is_in_bounds(at):
				break
			if is_bridge(props, at) or world.get_water(at) > Pathfinder.WET_DEPTH:
				at += dir
				continue
			best = maxi(best, world.get_height(at))
			break
	return best


## The level (height levels) one walks at on the bridge: its banks', or the
## bed's where that is higher (a ford in a dip).
static func deck_level(world: WorldData, props: PropRegistry, bridge: PropData) -> int:
	return maxi(world.get_height(bridge.tile), bank_level(world, props, bridge.tile, axis_of(bridge.rotation_step)))


## How high the deck is (world units): just above the higher bank, and at
## least PropData.BRIDGE_DECK above the bed (as a ford's bridge always was).
static func deck_y(world: WorldData, props: PropRegistry, bridge: PropData) -> float:
	var step := world.height_step
	var bed := world.get_height(bridge.tile) * step
	var banks := bank_level(world, props, bridge.tile, axis_of(bridge.rotation_step))
	return maxf(bed + PropData.BRIDGE_DECK, banks * step + DECK_LIFT if banks >= 0 else 0.0)


## Is the water up to the deck (a flood harms the bridge only then)?
static func flooded(world: WorldData, props: PropRegistry, bridge: PropData) -> bool:
	var surface := world.get_height(bridge.tile) * world.height_step + world.get_water(bridge.tile)
	return world.get_water(bridge.tile) > Pathfinder.WET_DEPTH and surface > deck_y(world, props, bridge) - FLOOD_MARGIN
