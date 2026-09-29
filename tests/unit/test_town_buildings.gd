extends GutTest

# ig-wgj.6: a leveled hall shows its level in town. hall_tier maps a level to a tier, every tier's model
# fits the hall's fixed 4.5 m Pick box, the swap keeps its node while the tier holds, the hub hands the
# levels over, and a save brings them back.

const Bounds = preload("res://tests/unit/town_bounds.gd")
const BALANCE: BalanceTable = preload("res://balance.tres")
const TOLERANCE: float = 0.01
## The leveled halls, in GameSession.building_levels order.
const HALLS: Array[StringName] = [&"SummoningCircle", &"Forge", &"TrainingHall", &"Sanctum", &"Reliquary"]


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})


func after_each() -> void:
	GameSession.set_process(true)


func test_the_tier_of_each_level() -> void:
	var wanted: Dictionary[int, int] = {-1: 0, 0: 0, 1: 1, 2: 1, 3: 2, 4: 2, 5: 3, 6: 3}
	for level: int in wanted:
		assert_eq(TownView.hall_tier(level), wanted[level], "level %d" % level)


func test_tiers_names_the_five_halls_in_levels_order_and_every_model_loads() -> void:
	assert_eq(TownView.TIERS.keys(), HALLS as Array)
	assert_eq(HALLS.size(), GameSession.building_levels.size())
	for hall: StringName in HALLS:
		var pairs: Array = TownView.TIERS[hall]
		assert_eq(pairs.size(), 3, "%s: tiers 0, 1 and 2" % hall)
		for pair: Array in pairs:
			assert_true(pair[0] is PackedScene, "%s: a model" % hall)
			assert_gt(float(pair[1]), 0.0, "%s: a factor" % hall)
			var model: Node3D = (pair[0] as PackedScene).instantiate() as Node3D
			assert_gt(Bounds.bounds_under(model, model).size.y, 0.5, "%s: the model has a mesh" % hall)
			model.free()


func test_every_tier_fits_the_fixed_pick_box() -> void:
	for level: int in [0, 1, 3, 5]:
		var town: TownView = _town(_all(level))
		for hall: StringName in HALLS:
			var building: Node3D = town.get_node(NodePath(hall)) as Node3D
			var box: AABB = Bounds.pick_box(building)
			var bounds: AABB = Bounds.bounds_under(building, _shown(building))
			assert_gt(bounds.size.y, 0.5, "%s at level %d: a real model is shown" % [hall, level])
			var fits: bool = Bounds.footprint(box).grow(TOLERANCE).encloses(Bounds.footprint(bounds)) and bounds.end.y <= box.end.y + TOLERANCE
			assert_true(fits, "%s at level %d: %s in %s" % [hall, level, bounds, box])


func test_a_hall_swaps_its_model_by_level_and_keeps_the_node_while_the_tier_holds() -> void:
	var town: TownView = _town(_all(0))
	var forge: Node3D = town.get_node("Forge") as Node3D
	for level: int in 5:
		town.show_buildings(GameSession.town_buildings, _all(level))
		assert_false((forge.get_node("Model") as Node3D).visible, "level %d hides the Model" % level)
		assert_eq(forge.find_children("Tier", "", false, false).size(), 1, "level %d shows one Tier" % level)
		assert_eq(_tier_of(forge), TownView.hall_tier(level))
	town.show_buildings(GameSession.town_buildings, _all(1))
	var small: Node = forge.get_node("Tier")
	town.show_buildings(GameSession.town_buildings, _all(2))
	town.show_buildings(GameSession.town_buildings, _all(2))
	assert_eq(forge.get_node("Tier").get_instance_id(), small.get_instance_id(), "levels 1, 2 and 2 again keep the node")
	town.show_buildings(GameSession.town_buildings, _all(3))
	var bigger: Node = forge.get_node("Tier")
	assert_ne(bigger.get_instance_id(), small.get_instance_id(), "2 to 3 replaces it")
	assert_true(small.is_queued_for_deletion())
	town.show_buildings(GameSession.town_buildings, _all(4))
	assert_eq(forge.get_node("Tier").get_instance_id(), bigger.get_instance_id(), "3 and 4 share a tier")
	town.show_buildings(GameSession.town_buildings, _all(5))
	assert_null(forge.get_node_or_null("Tier"), "level 5 has no Tier")
	assert_true(bigger.is_queued_for_deletion())
	assert_true((forge.get_node("Model") as Node3D).visible, "level 5 shows the Model")


func test_raising_one_level_changes_only_that_halls_node() -> void:
	var levels: Array[int] = _all(0)
	var town: TownView = _town(levels)
	var before: Array[int] = _tier_ids(town)
	levels[1] = 1
	town.show_buildings(GameSession.town_buildings, levels)
	var after: Array[int] = _tier_ids(town)
	for index: int in HALLS.size():
		assert_eq(after[index] != before[index], index == 1, str(HALLS[index]))


func test_only_the_five_halls_get_a_tier_and_only_when_their_level_is_given() -> void:
	var buildings: Array[Dictionary] = TownRules.default_halls()
	buildings.append({"id": "House_1", "type": "House", "q": 0, "r": 2})
	buildings.append({"id": "Lumbermill_1", "type": "Lumbermill", "q": 1, "r": 2})
	var town: TownView = (load("res://hub/town/town.tscn") as PackedScene).instantiate() as TownView
	add_child_autofree(town)
	town.show_buildings(buildings)
	for building: Dictionary in buildings:
		var node: Node3D = town.get_node(NodePath(building["id"])) as Node3D
		assert_null(node.get_node_or_null("Tier"), "%s: no levels given" % building["id"])
		assert_true((node.get_node("Model") as Node3D).visible, "%s keeps its Model" % building["id"])
	var short: Array[int] = [0]
	town.show_buildings(buildings, short)
	assert_not_null(town.get_node("SummoningCircle").get_node_or_null("Tier"), "its level is given")
	assert_null(town.get_node("Forge").get_node_or_null("Tier"), "its index is past the levels")
	town.show_buildings(buildings, _all(0))
	for building: Dictionary in buildings:
		var node: Node3D = town.get_node(NodePath(building["id"])) as Node3D
		assert_eq(node.get_node_or_null("Tier") != null, HALLS.has(StringName(building["type"])), str(building["id"]))


func test_the_pick_label_and_work_spot_are_the_same_at_every_tier() -> void:
	var towns: Dictionary[int, TownView] = {}
	for level: int in [5, 3, 0]:
		towns[level] = _town(_all(level))
	for hall: StringName in HALLS:
		var wanted: Array = _fixed_parts(towns[5].get_node(NodePath(hall)) as Node3D)
		for level: int in [3, 0]:
			assert_eq(_fixed_parts(towns[level].get_node(NodePath(hall)) as Node3D), wanted, "%s at level %d" % [hall, level])


func test_an_upgrade_shows_its_new_tier_in_the_same_frame() -> void:
	_rich()
	GameSession.building_levels[1] = 2
	var forge: Node3D = _instantiate_hub().get_node("%Town").get_node("Forge") as Node3D
	assert_eq(_tier_of(forge), 1, "level 2 shows tier 1")
	assert_true(GameSession.upgrade_building(1, BALANCE))
	assert_eq(GameSession.building_levels[1], 3)
	assert_eq(_tier_of(forge), 2, "level 3 shows tier 2, with no refresh call")


func test_the_levels_survive_a_disk_round_trip_and_the_rebuilt_town_shows_them() -> void:
	_rich()
	var saved_levels: Array[int] = [0, 2, 3, 5, 1]
	for hall: int in saved_levels.size():
		for _step: int in saved_levels[hall]:
			assert_true(GameSession.upgrade_building(hall, BALANCE), "hall %d" % hall)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	assert_eq(GameSession.building_levels, _all(0))
	_write(bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.building_levels, saved_levels)
	var town: TownView = _instantiate_hub().get_node("%Town") as TownView
	for hall: int in HALLS.size():
		assert_eq(_tier_of(town.get_node(NodePath(HALLS[hall])) as Node3D), TownView.hall_tier(saved_levels[hall]), str(HALLS[hall]))


func test_a_save_with_no_building_levels_loads_every_hall_as_a_ruin() -> void:
	GameSession.building_levels.assign(_all(4))
	assert_true(SaveService.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	assert_true(saved.erase("building_levels"))
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game())
	assert_eq(GameSession.building_levels, _all(0))
	var town: TownView = _instantiate_hub().get_node("%Town") as TownView
	for hall: StringName in HALLS:
		assert_eq(_tier_of(town.get_node(NodePath(hall)) as Node3D), 0, "%s is a ruin" % hall)


func _all(level: int) -> Array[int]:
	var levels: Array[int] = [0, 0, 0, 0, 0]
	levels.fill(level)
	return levels


func _town(levels: Array[int]) -> TownView:
	var town: TownView = (load("res://hub/town/town.tscn") as PackedScene).instantiate() as TownView
	add_child_autofree(town)
	town.show_buildings(GameSession.town_buildings, levels)
	return town


## The model a hall shows: its Tier child, or its own Model.
func _shown(building: Node3D) -> Node3D:
	var tier: Node3D = building.get_node_or_null("Tier") as Node3D
	return tier if tier != null else building.get_node("Model") as Node3D


## The tier a hall shows: its Tier child's, or 3 for its own Model.
func _tier_of(building: Node3D) -> int:
	var tier: Node = building.get_node_or_null("Tier")
	return 3 if tier == null else int(tier.get_meta(&"tier"))


## Each hall's Tier child's instance id, or 0.
func _tier_ids(town: TownView) -> Array[int]:
	var ids: Array[int] = []
	for hall: StringName in HALLS:
		var tier: Node = town.get_node(NodePath(hall)).get_node_or_null("Tier")
		ids.append(0 if tier == null else tier.get_instance_id())
	return ids


func _fixed_parts(building: Node3D) -> Array:
	var shape: CollisionShape3D = building.get_node("Pick/Shape") as CollisionShape3D
	return [
		(building.get_node("Pick") as StaticBody3D).collision_layer,
		(shape.shape as BoxShape3D).size,
		shape.transform,
		(building.get_node("Label") as Label3D).position,
		(building.get_node("WorkSpot") as Marker3D).position,
	]


func _rich() -> void:
	GameSession.parts.fill(99)
	GameSession.town_resources["wood"] = 1000.0
	GameSession.town_resources["stone"] = 1000.0


func _write(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _instantiate_hub() -> Node3D:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	return hub
