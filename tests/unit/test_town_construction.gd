extends GutTest

# ig-6m2.3.2: a new House or workplace takes live-play time to go up, shows scaffolding and three
# stages meanwhile, and does nothing until it is finished (SYSTEMS.md § Stone and construction).
# Boundary #1: build_remaining is an additive key on a building dict.

const BALANCE: BalanceTable = preload("res://balance.tres")
const HOUSE_HEX: Vector2i = Vector2i(0, 2)
const MILL_HEX: Vector2i = Vector2i(1, 2)
const STAGE_PATHS: Array[String] = [
	"res://hub/town/models/hexagon/building_scaffolding.gltf",
	"res://hub/town/models/hexagon/building_stage_A.gltf",
	"res://hub/town/models/hexagon/building_stage_B.gltf",
	"res://hub/town/models/hexagon/building_stage_C.gltf",
]


func before_each() -> void:
	GameSession.set_process(false)
	SaveService.load_blocked = false
	SaveService.load_block_reason = ""
	GameSession.from_dict({"roster": []})
	GameSession.town_resources["wood"] = 1000.0


func after_each() -> void:
	GameSession.set_process(true)


func test_a_new_building_starts_with_its_build_time_and_a_hall_has_none() -> void:
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	assert_eq(GameSession.town_building(house)["build_remaining"], 60.0)
	for index: int in TownRules.TYPES.size():
		var type: StringName = TownRules.TYPES[index]
		if TownRules.worker_slots(type, BALANCE) > 0:
			var id: StringName = _place(type, Vector2i(index - 2, 3))
			assert_eq(GameSession.town_building(id)["build_remaining"], 120.0, str(type))
	for hall: Dictionary in TownRules.default_halls():
		assert_false(GameSession.town_building(StringName(hall["id"])).has("build_remaining"), str(hall["id"]))


func test_live_play_builds_it_and_the_offline_catch_up_never_does() -> void:
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	GameSession.tick_expeditions(10.0)
	assert_eq(GameSession.town_building(house)["build_remaining"], 50.0, "1 s a second")
	GameSession._advance_orders_in_memory(36000.0)
	assert_eq(GameSession.town_building(house)["build_remaining"], 50.0, "the catch-up builds nothing, however long")
	GameSession.tick_expeditions(49.5)
	assert_eq(GameSession.town_building(house)["build_remaining"], 0.5)
	GameSession.tick_expeditions(0.5)
	assert_false(GameSession.town_building(house).has("build_remaining"), "finished: the key is gone")
	GameSession.tick_expeditions(10.0)
	assert_false(GameSession.town_building(house).has("build_remaining"))


func test_under_construction_it_takes_nobody_and_after_it_does() -> void:
	var hero: Hero = _add_hero("Mira")
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	GameSession.tick_expeditions(17.5)
	assert_false(GameSession.assign_home(hero, house))
	assert_eq(GameSession.last_action_error, "House 1 is still being built (0:43 left).")
	assert_eq(hero.home, Hero.NO_HOME)
	GameSession.tick_expeditions(42.5)
	assert_true(GameSession.assign_home(hero, house), GameSession.last_action_error)
	assert_false(GameSession.station_hero(hero, mill))
	assert_eq(GameSession.last_action_error, "Lumbermill 2 is still being built (1:00 left).")
	assert_eq(hero.station, Hero.NO_STATION)
	var wood: float = GameSession.town_resources["wood"]
	GameSession.tick_expeditions(60.0)
	assert_eq(GameSession.town_resources["wood"], wood, "nobody works there, so it made nothing")
	assert_true(GameSession.station_hero(hero, mill), GameSession.last_action_error)
	GameSession.tick_expeditions(60.0)
	assert_almost_eq(float(GameSession.town_resources["wood"]), wood + BALANCE.wood_per_worker_minute, 0.0001)


func test_a_move_keeps_the_progress() -> void:
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	GameSession.tick_expeditions(20.0)
	assert_true(GameSession.move_building(house, Vector2i(-3, 3)), GameSession.last_action_error)
	assert_eq(GameSession.town_building(house)["build_remaining"], 40.0)
	assert_eq(GameSession.town_building(house)["q"], -3)


func test_a_free_producer_under_construction_still_counts_for_the_free_rule() -> void:
	_place(TownRules.LUMBERMILL, MILL_HEX)
	var plan: Dictionary = GameSession.preview_place_building(TownRules.LUMBERMILL, Vector2i(2, 2))
	assert_eq(int(plan["cost"]), BALANCE.lumbermill_wood_cost, "the first one is still going up")
	var wood: float = GameSession.town_resources["wood"]
	_place(TownRules.LUMBERMILL, Vector2i(2, 2))
	assert_eq(GameSession.town_resources["wood"], wood - int(plan["cost"]), "the preview is what it spends")


# Boundary #1: through SaveService and the disk.
func test_a_half_built_house_survives_a_disk_round_trip() -> void:
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	GameSession.tick_expeditions(30.0)
	assert_true(SaveService.save(), SaveService.last_write_error)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SaveService.SAVE_PATH)
	GameSession.from_dict({"roster": []})
	_write(bytes)
	assert_true(SaveService.load_game())
	assert_eq(GameSession.town_building(house)["build_remaining"], 30.0)
	assert_push_warning_count(0)
	assert_push_error_count(0)


func test_a_save_from_before_construction_loads_every_building_finished() -> void:
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	assert_true(SaveService.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	for building: Dictionary in saved["town_buildings"]:
		building.erase("build_remaining")
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game())
	for id: StringName in [house, mill]:
		assert_false(GameSession.town_building(id).has("build_remaining"), str(id))
	assert_push_warning_count(0)


func test_bad_build_times_load_finished_or_clamped() -> void:
	for case: Array in [[-1.0, false], ["x", false], [1.0e9, true], [0.0, false], [null, false]]:
		GameSession.from_dict({"roster": []})
		var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
		assert_true(SaveService.save())
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
		for building: Dictionary in saved["town_buildings"]:
			if building["id"] == String(house):
				building["build_remaining"] = case[0]
			elif TownRules.is_hall(StringName(building["id"])):
				building["build_remaining"] = 5.0
		_write(JSON.stringify(saved, "\t").to_utf8_buffer())
		assert_true(SaveService.load_game(), str(case))
		var loaded: Dictionary = GameSession.town_building(house)
		if case[1]:
			assert_eq(loaded.get("build_remaining"), BALANCE.house_build_seconds, "clamped to the build time: %s" % str(case))
		else:
			assert_false(loaded.has("build_remaining"), "finished: %s" % str(case))
		assert_false(GameSession.town_building(&"Forge").has("build_remaining"), "a hall ignores it")
	assert_push_warning_count(4, "-1, \"x\", 0 and null each warn")
	assert_push_error_count(0)


func test_the_stages_follow_the_done_fraction_and_the_model_comes_back() -> void:
	var town: TownView = _town()
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	town.show_buildings(GameSession.town_buildings)
	var node: Node3D = town.get_node(NodePath(house)) as Node3D
	for stage: int in 4:
		town.show_buildings(GameSession.town_buildings)
		var shown: Node3D = node.get_node_or_null("Stage") as Node3D
		assert_not_null(shown, "stage %d" % stage)
		if shown == null:
			return
		assert_eq(shown.scene_file_path, STAGE_PATHS[stage], "%d%% done" % (stage * 25))
		assert_eq(shown.scale, Vector3.ONE * TownRules.MODEL_SCALE)
		assert_false((node.get_node("Model") as Node3D).visible)
		GameSession.tick_expeditions(BALANCE.house_build_seconds / 8.0)
		town.show_buildings(GameSession.town_buildings)
		assert_eq(node.get_node("Stage"), shown, "a tick inside the quarter keeps the node")
		GameSession.tick_expeditions(BALANCE.house_build_seconds / 8.0)
	town.show_buildings(GameSession.town_buildings)
	assert_false(GameSession.town_building(house).has("build_remaining"))
	assert_null(node.get_node_or_null("Stage"), "finished: no stage")
	assert_true((node.get_node("Model") as Node3D).visible, "its own model")
	for part: String in ["Label", "Pick", "WorkSpot"]:
		assert_not_null(node.get_node_or_null(part), part)


# A hand-edited save can't put anyone in a building that is still going up.
func test_a_loaded_claim_on_an_unfinished_building_is_cleared() -> void:
	var ada: Hero = _add_hero("Ada")
	var bo: Hero = _add_hero("Bo")
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var other_house: StringName = _place(TownRules.HOUSE, Vector2i(-1, 2))
	var mill: StringName = _place(TownRules.LUMBERMILL, MILL_HEX)
	GameSession.tick_expeditions(BALANCE.workplace_build_seconds)
	assert_true(GameSession.assign_home(ada, house), GameSession.last_action_error)
	assert_true(GameSession.assign_home(bo, other_house), GameSession.last_action_error)
	assert_true(GameSession.station_hero(bo, mill), GameSession.last_action_error)
	assert_true(SaveService.save())
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	for building: Dictionary in saved["town_buildings"]:
		if building["id"] in [String(house), String(mill)]:
			building["build_remaining"] = 10.0
	_write(JSON.stringify(saved, "\t").to_utf8_buffer())
	assert_true(SaveService.load_game())
	assert_eq(GameSession.hero_by_id(ada.instance_id).home, Hero.NO_HOME, "not in a House still going up")
	assert_eq(GameSession.hero_by_id(bo.instance_id).home, other_house, "the finished House keeps its resident")
	assert_eq(GameSession.hero_by_id(bo.instance_id).station, Hero.NO_STATION, "not at a Lumbermill still going up")
	assert_push_warning_count(2)


# A building that finishes is saved at once, so a reload never builds it again.
func test_a_finished_building_is_saved_at_once() -> void:
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	assert_true(SaveService.save())
	GameSession.tick_expeditions(BALANCE.house_build_seconds)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	for building: Dictionary in saved["town_buildings"]:
		if building["id"] == String(house):
			assert_false(building.has("build_remaining"), "finished on disk too")


# The live tick emits only expeditions_changed, and the hub moves the stage on it.
func test_a_plain_live_tick_moves_the_stage_in_the_hub() -> void:
	var hub: Node3D = (load("res://hub/hub.tscn") as PackedScene).instantiate() as Node3D
	add_child_autofree(hub)
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	var node: Node3D = hub.get_node("%Town").get_node(NodePath(house)) as Node3D
	assert_eq(node.get_node("Stage").get_meta(&"stage"), 0)
	watch_signals(GameSession)
	GameSession.tick_expeditions(BALANCE.house_build_seconds / 4.0)
	assert_signal_not_emitted(GameSession, "roster_changed", "a plain tick")
	assert_eq(node.get_node("Stage").get_meta(&"stage"), 1, "the stage moved all the same")


# A town whose only clock is a building going up still gets its periodic save, so a crash never
# rolls the build back further than the last save.
func test_a_building_under_construction_gets_the_periodic_save() -> void:
	var house: StringName = _place(TownRules.HOUSE, HOUSE_HEX)
	assert_true(SaveService.save())
	GameSession.set("_periodic_save_accumulator", GameSession.PERIODIC_SAVE_SECONDS - 0.1)
	GameSession._process(0.25)
	GameSession._process(0.01)  # ig-7sn.10: the periodic save runs on the frame after its pulse.
	var left: float = GameSession.town_building(house)["build_remaining"]
	assert_lt(left, BALANCE.house_build_seconds)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveService.SAVE_PATH)) as Dictionary
	for building: Dictionary in saved["town_buildings"]:
		if building["id"] == String(house):
			assert_almost_eq(float(building["build_remaining"]), left, 0.0001, "the periodic save wrote it")


## ---- helpers

func _place(type: StringName, hex: Vector2i) -> StringName:
	var id := StringName(GameSession.preview_place_building(type, hex)["id"])
	assert_true(GameSession.place_building(type, hex), GameSession.last_action_error)
	return id


func _add_hero(hero_name: String) -> Hero:
	var hero := Hero.new(hero_name, 7)
	hero.def_id = &"knight"
	hero.level = 80
	GameSession.add_hero(hero)
	return hero


func _town() -> TownView:
	var world := Node3D.new()
	var town: TownView = (load("res://hub/town/town.tscn") as PackedScene).instantiate() as TownView
	world.add_child(town)
	add_child_autofree(world)
	return town


func _write(bytes: PackedByteArray) -> void:
	var file := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
