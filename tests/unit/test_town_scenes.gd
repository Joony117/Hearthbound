extends GutTest

# ig-6m2.8.2: every building scene fits its model. The Pick box is 4.5 m square (the Mine's is longer),
# stands on the ground, covers the model except in the OVERFLOWS scenes, and the WorkSpot and Label clear it.

const Bounds = preload("res://tests/unit/town_bounds.gd")

const BOX_SIDE: float = 4.5
## The Mine's box is longer than square, as it is today (mine.tscn).
const MINE_DEPTH: float = 5.3
const TOLERANCE: float = 0.01
## The route rule's margin (ig-6m2.6): a WorkSpot must stand clear of the box grown by this much.
const ROUTE_MARGIN: float = 0.3
## Scenes whose model is bigger than its 4.5 m box today. The Mine: not reshaped here (no bead owns it).
## The Farm: a box wide enough for its fields can't sit on the 6 m hex spacing. The covers-the-model
## check expects exactly these to overflow, so a refit shows up as a red test to delete the entry from.
const OVERFLOWS: Array[StringName] = [TownRules.MINE, TownRules.FARM]
## The designed Pick heights of the seven halls; the box is centred at half of it.
const HALL_HEIGHTS: Dictionary[StringName, float] = {
	&"SummoningCircle": 7.5,
	&"Forge": 3.0,
	&"TrainingHall": 5.0,
	&"Sanctum": 5.0,
	&"Reliquary": 8.0,
	&"TownGate": 3.5,
	&"Apothecary": 2.5,
}


func test_every_scene_has_its_parts_and_its_pick_on_the_pick_layer_alone() -> void:
	assert_eq(TownView.SCENES.size(), 11, "the seven halls, House, Lumbermill, Mine and Farm")
	for type: StringName in TownView.SCENES:
		var building: Node3D = TownView.SCENES[type].instantiate() as Node3D
		for part: String in ["Model", "Label", "Pick/Shape", "WorkSpot"]:
			assert_true(building.has_node(part), "%s has a %s" % [type, part])
		assert_eq((building.get_node("Pick") as StaticBody3D).collision_layer, TownView.PICK_LAYER, "%s: layer 2 alone" % type)
		building.free()


func test_every_pick_box_is_square_and_stands_on_the_ground_and_covers_its_model() -> void:
	for type: StringName in TownView.SCENES:
		var building: Node3D = TownView.SCENES[type].instantiate() as Node3D
		var box: AABB = Bounds.pick_box(building)
		var model: AABB = Bounds.bounds_under(building, building.get_node("Model") as Node3D)
		assert_gt(model.size.y, 0.5, "%s: a real model was found under Model" % type)
		assert_almost_eq(box.size.x, BOX_SIDE, TOLERANCE, "%s: box width" % type)
		if type != TownRules.MINE:
			assert_almost_eq(box.size.z, BOX_SIDE, TOLERANCE, "%s: box depth is square" % type)
		else:
			assert_almost_eq(box.size.z, MINE_DEPTH, TOLERANCE, "%s: box depth" % type)
		assert_almost_eq(box.position.y, 0.0, TOLERANCE, "%s: the box stands on the ground" % type)
		var covers: bool = Bounds.footprint(box).grow(TOLERANCE).encloses(Bounds.footprint(model)) and model.size.y <= box.size.y + TOLERANCE
		assert_eq(covers, not OVERFLOWS.has(type), "%s: model %s in box %s" % [type, model, box])
		building.free()


func test_every_work_spot_is_outside_the_grown_box_and_every_label_above_the_model() -> void:
	for type: StringName in TownView.SCENES:
		var building: Node3D = TownView.SCENES[type].instantiate() as Node3D
		var box: AABB = Bounds.pick_box(building)
		var grown: Rect2 = Bounds.footprint(box).grow(ROUTE_MARGIN)
		var spot: Vector3 = (building.get_node("WorkSpot") as Marker3D).position
		assert_false(grown.has_point(Vector2(spot.x, spot.z)), "%s: the WorkSpot clears the box grown by %s m" % [type, ROUTE_MARGIN])
		assert_gt((building.get_node("Label") as Label3D).position.y, Bounds.bounds_under(building, building.get_node("Model") as Node3D).end.y, "%s: the label is above the model" % type)
		building.free()


func test_the_seven_halls_match_their_designed_boxes_labels_and_work_spots() -> void:
	assert_eq(HALL_HEIGHTS.keys(), TownRules.HALL_HEXES.keys(), "every hall is covered")
	for hall: StringName in HALL_HEIGHTS:
		var building: Node3D = TownView.SCENES[hall].instantiate() as Node3D
		var shape: CollisionShape3D = building.get_node("Pick/Shape") as CollisionShape3D
		assert_almost_eq((shape.shape as BoxShape3D).size, Vector3(BOX_SIDE, HALL_HEIGHTS[hall], BOX_SIDE), Vector3.ONE * TOLERANCE, "%s: box" % hall)
		assert_almost_eq(shape.position, Vector3(0.0, HALL_HEIGHTS[hall] / 2.0, 0.0), Vector3.ONE * TOLERANCE, "%s: centred at half its height" % hall)
		assert_almost_eq((building.get_node("WorkSpot") as Marker3D).position, Vector3(0.0, 0.0, 2.8), Vector3.ONE * TOLERANCE, "%s: WorkSpot" % hall)
		assert_almost_eq((building.get_node("Label") as Label3D).pixel_size, 0.02, 0.0001, "%s: label size" % hall)
		building.free()


func test_arrival_covers_a_body_stopped_on_a_corner_of_a_4_5_m_building() -> void:
	assert_eq(TownView.ARRIVE_RADIUS, 3.6)
	assert_gt(TownView.ARRIVE_RADIUS, sqrt(2.0) * BOX_SIDE / 2.0 + 0.4, "the corner (3.18 m) plus the body's radius")
